#!/bin/bash

# === Initial Setup ===
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt upgrade -y

# === Basic Tools ===
apt install -y software-properties-common curl unzip git ufw

# === Add PHP PPA ===
add-apt-repository ppa:ondrej/php -y
apt update -y

# === Install PHP 8.1 and Required Extensions ===
apt install -y php8.1 php8.1-fpm php8.1-cli php8.1-mysql php8.1-curl php8.1-mbstring \
php8.1-xml php8.1-bcmath php8.1-zip php8.1-gd php8.1-soap php8.1-common

# === Install Apache ===
apt install -y apache2 libapache2-mod-php8.1
a2enmod php8.1 rewrite headers
systemctl enable apache2

# === Install MySQL Server ===
apt install -y mysql-server

# === Setup UFW ===
ufw allow OpenSSH
ufw allow 'Apache Full'
ufw --force enable

# === Install Composer ===
curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# === Setup Laravel Directories ===
APP_DIR="/var/www/cpms"
REPO_DIR="/var/repo/cpms.git"

mkdir -p $APP_DIR
mkdir -p $REPO_DIR
chown -R ubuntu:ubuntu $APP_DIR $REPO_DIR

# === Post-Receive Hook Script ===
cat << 'EOF' > $REPO_DIR/hooks/post-receive
#!/bin/bash

APP_DIR="/var/www/cpms"
GIT_DIR="/var/repo/cpms.git"

echo ">>> Deploying Laravel to \$APP_DIR..."

git --work-tree=\$APP_DIR --git-dir=\$GIT_DIR checkout -f

cd \$APP_DIR
composer install --no-dev --optimize-autoloader
php artisan config:cache
php artisan route:cache

if [ -f "\$APP_DIR/.env" ]; then
    php artisan migrate --force
else
    echo "⚠️ Skipping migrations — .env not found."
fi

chown -R www-data:www-data \$APP_DIR
chmod -R 775 storage bootstrap/cache

echo ">>> Deployment complete ✅"
EOF

chmod +x $REPO_DIR/hooks/post-receive

# === Final Permissions ===
chown -R www-data:www-data $APP_DIR
chmod -R 775 $APP_DIR/storage $APP_DIR/bootstrap/cache

# === Apache Restart ===
systemctl restart apache2
