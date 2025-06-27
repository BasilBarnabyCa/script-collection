#!/bin/bash
# === Only for use on Ubuntu 22.04 ===
(
trap 'echo "❌ Error on line $LINENO: $BASH_COMMAND" | tee -a /var/log/provision.log' ERR
set -euo pipefail

log() {
    echo -e "\n===== $1 =====\n" | tee -a /var/log/provision.log
}

log "🟢 STARTING PROVISION SCRIPT"

# === Initial Setup ===
export DEBIAN_FRONTEND=noninteractive
log "🔄 apt update & upgrade"
apt update -y && apt upgrade -y

# === Basic Tools ===
log "🔧 Installing basic tools (curl, git, unzip, etc.)"
apt install -y software-properties-common curl unzip git ufw

# === Add PHP PPA ===
log "➕ Adding PHP PPA"
add-apt-repository ppa:ondrej/php -y
apt update -y

# === Install PHP 8.1 and Extensions ===
log "🐘 Installing PHP 8.1 and extensions"
apt install -y php8.1 php8.1-fpm php8.1-cli php8.1-mysql php8.1-curl php8.1-mbstring \
php8.1-xml php8.1-bcmath php8.1-zip php8.1-gd php8.1-soap php8.1-common

# === Install Apache ===
log "🌐 Installing Apache"
apt install -y apache2

a2enmod rewrite headers proxy_fcgi setenvif

a2enconf php8.1-fpm || true
a2dismod php8.1 || echo "php8.1 already disabled or not found"

systemctl enable apache2

# === Install MySQL Server with Retry ===
log "🗄 Installing MySQL Server"
apt-get clean && apt-get autoclean
for i in {1..3}; do
    echo "Attempt $i to install mysql-server..."
    if apt install -y mysql-server; then
        echo "✅ mysql-server installed successfully"
        break
    else
        echo "⚠️ mysql-server install failed, retrying in 10s..."
        sleep 10
    fi
done

# === Function to setup Laravel app ===
setup_app() {
  local APP_NAME=$1
  local APP_DIR=/var/www/$APP_NAME
  local GIT_DIR=/var/repo/$APP_NAME.git

  log "📁 Setting up $APP_NAME"
  mkdir -p "$APP_DIR"
  git init --bare "$GIT_DIR"
  chown -R ubuntu:ubuntu "$GIT_DIR"
  chown -R www-data:www-data "$APP_DIR"

  cat << EOF > "$GIT_DIR/hooks/post-receive"
  #!/bin/bash
  APP_DIR="$APP_DIR"
  GIT_DIR="$GIT_DIR"
  DEPLOY_USER="ubuntu"
  WEB_USER="www-data"
  
  echo ">>> Deploying Laravel to \$APP_DIR..."
  
  sudo chown -R \$DEPLOY_USER:\$DEPLOY_USER \$APP_DIR
  git --work-tree=\$APP_DIR --git-dir=\$GIT_DIR checkout -f
  sudo chown -R \$DEPLOY_USER:\$DEPLOY_USER \$APP_DIR
  
  sudo -u \$DEPLOY_USER bash << 'INNER'
  cd \$APP_DIR
  if command -v composer >/dev/null 2>&1 && [ -f ".env" ]; then
      composer install --no-dev --optimize-autoloader
      php artisan config:cache
      php artisan route:cache
      php artisan migrate --force
  else
      echo "⚠️ Skipping Composer and Artisan commands"
  fi
  INNER
  
  sudo chown -R \$WEB_USER:\$WEB_USER \$APP_DIR
  sudo chmod -R 775 \$APP_DIR/storage \$APP_DIR/bootstrap/cache
  
  echo ">>> Deployment complete ✅"
  EOF

  chmod +x "$GIT_DIR/hooks/post-receive"

  # === Create setup script ===
  cat << EOF > "/home/ubuntu/setup-$APP_NAME.sh"
  #!/bin/bash
  
  LOG_FILE="/home/ubuntu/setup-$APP_NAME.log"
  exec > >(tee -a "\$LOG_FILE") 2>&1
  set -euo pipefail
  
  APP_DIR="$APP_DIR"
  log() { echo -e "\n===== \$1 =====\n"; }
  
  log "🚀 Setting up $APP_NAME"
  cd /tmp
  curl -sS https://getcomposer.org/installer | php
  sudo mv composer.phar /usr/local/bin/composer
  sudo chmod +x /usr/local/bin/composer
  
  sudo chown -R ubuntu:ubuntu "\$APP_DIR"
  cd "\$APP_DIR"
  
  if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
  fi
  
  composer install --no-dev --optimize-autoloader
  php artisan key:generate || true
  php artisan passport:install || true
  
  sudo chown -R www-data:www-data "\$APP_DIR"
  sudo chmod -R 775 "\$APP_DIR/storage" "\$APP_DIR/bootstrap/cache"
  
  log "✅ $APP_NAME setup complete."
  EOF

  chmod +x "/home/ubuntu/setup-$APP_NAME.sh"
  chown ubuntu:ubuntu "/home/ubuntu/setup-$APP_NAME.sh"
}

setup_app site
setup_app core

# === Tune PHP-FPM ===
log "⚙️ Tuning PHP-FPM"
FPM_POOL_CONF="/etc/php/8.1/fpm/pool.d/www.conf"
PHP_INI="/etc/php/8.1/fpm/php.ini"
sed -i 's|^;*\s*pm\s*=.*|pm = dynamic|' "$FPM_POOL_CONF"
sed -i 's|^;*\s*pm\.max_children\s*=.*|pm.max_children = 15|' "$FPM_POOL_CONF"
sed -i 's|^;*\s*pm\.start_servers\s*=.*|pm.start_servers = 4|' "$FPM_POOL_CONF"
sed -i 's|^;*\s*pm\.min_spare_servers\s*=.*|pm.min_spare_servers = 4|' "$FPM_POOL_CONF"
sed -i 's|^;*\s*pm\.max_spare_servers\s*=.*|pm.max_spare_servers = 6|' "$FPM_POOL_CONF"
sed -i 's|^;*\s*pm\.max_requests\s*=.*|pm.max_requests = 500|' "$FPM_POOL_CONF"
sed -i 's|^;*\s*cgi\.fix_pathinfo\s*=.*|cgi.fix_pathinfo=0|' "$PHP_INI"

# === Tune OPcache ===
log "🔧 Tuning OPcache"
cat << EOF > /etc/php/8.1/fpm/conf.d/10-opcache.ini
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.revalidate_freq=60
opcache.validate_timestamps=1
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.enable_file_override=0
EOF

systemctl restart php8.1-fpm

# === UFW Setup ===
log "🛡 Configuring UFW"
ufw allow OpenSSH
ufw allow 'Apache Full'
ufw --force enable

log "✅ PROVISIONING COMPLETE"
log "🔁 Rebooting now"

) | tee /var/log/provision.log

apt update -y && apt upgrade -y
sleep 15
sudo reboot
