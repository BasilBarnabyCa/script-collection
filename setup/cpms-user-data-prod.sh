#!/bin/bash
(
set -euo pipefail

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
apt install -y apache2
a2enmod rewrite headers proxy_fcgi setenvif
a2enconf php8.1-fpm
a2dismod php8.1
systemctl enable apache2

# === Tune PHP-FPM Workers ===
FPM_POOL_CONF="/etc/php/8.1/fpm/pool.d/www.conf"

sed -i 's/^pm = .*/pm = dynamic/' $FPM_POOL_CONF
sed -i 's/^pm.max_children = .*/pm.max_children = 15/' $FPM_POOL_CONF
sed -i 's/^pm.start_servers = .*/pm.start_servers = 4/' $FPM_POOL_CONF
sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 4/' $FPM_POOL_CONF
sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 6/' $FPM_POOL_CONF
sed -i 's/^pm.max_requests = .*/pm.max_requests = 500/' $FPM_POOL_CONF

systemctl restart php8.1-fpm

# === Install MySQL Server ===
apt install -y mysql-server

# === Setup UFW ===
ufw allow OpenSSH
ufw allow 'Apache Full'
ufw --force enable

# === Install Composer ===
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer

# === Setup Laravel Directories ===
APP_DIR="/var/www/cpms"
GIT_DIR="/var/repo/cpms.git"

mkdir -p "$APP_DIR"
git init --bare "$GIT_DIR"
chown -R ubuntu:ubuntu "$APP_DIR" "$GIT_DIR"

# === Post-Receive Hook Script ===
cat << EOF > "$GIT_DIR/hooks/post-receive"
#!/bin/bash

APP_DIR="$APP_DIR"
GIT_DIR="$GIT_DIR"

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
chmod -R 775 \$APP_DIR/storage \$APP_DIR/bootstrap/cache

echo ">>> Deployment complete ✅"
EOF

chmod +x "$GIT_DIR/hooks/post-receive"

# === Final Permissions ===
chown -R www-data:www-data "$GIT_DIR"

# === Apache Restart ===
systemctl restart apache2

# === Create setup.sh Script ===
cat << EOF > /home/ubuntu/setup.sh
#!/bin/bash

APP_DIR="$APP_DIR"
ENV_FILE="\$APP_DIR/.env"

if [ ! -f "\$ENV_FILE" ]; then
    cp "\$APP_DIR/.env.example" "\$ENV_FILE"
fi

echo "=== Laravel .env Setup ==="

read -p "APP_NAME: " APP_NAME
read -p "APP_ENV (e.g. production): " APP_ENV
read -p "APP_URL (e.g. https://cpms.example.com): " APP_URL
read -p "DB_DATABASE: " DB_DATABASE
read -p "DB_USERNAME: " DB_USERNAME
read -s -p "DB_PASSWORD: " DB_PASSWORD; echo
read -p "MAIL_HOST: " MAIL_HOST
read -p "MAIL_PORT: " MAIL_PORT
read -p "MAIL_USERNAME: " MAIL_USERNAME
read -s -p "MAIL_PASSWORD: " MAIL_PASSWORD; echo
read -p "MAIL_ENCRYPTION (tls/ssl): " MAIL_ENCRYPTION
read -p "AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
read -p "AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
read -p "AWS_DEFAULT_REGION: " AWS_DEFAULT_REGION
read -p "AWS_BUCKET: " AWS_BUCKET
read -p "AWS_URL: " AWS_URL
read -p "OPEN_WEATHER_API_KEY: " OPEN_WEATHER_API_KEY

sed -i "s|^APP_NAME=.*|APP_NAME=\"\$APP_NAME\"|" \$ENV_FILE
sed -i "s|^APP_ENV=.*|APP_ENV=\$APP_ENV|" \$ENV_FILE
sed -i "s|^APP_URL=.*|APP_URL=\$APP_URL|" \$ENV_FILE
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=\$DB_DATABASE|" \$ENV_FILE
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=\$DB_USERNAME|" \$ENV_FILE
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=\$DB_PASSWORD|" \$ENV_FILE
sed -i "s|^MAIL_HOST=.*|MAIL_HOST=\$MAIL_HOST|" \$ENV_FILE
sed -i "s|^MAIL_PORT=.*|MAIL_PORT=\$MAIL_PORT|" \$ENV_FILE
sed -i "s|^MAIL_USERNAME=.*|MAIL_USERNAME=\$MAIL_USERNAME|" \$ENV_FILE
sed -i "s|^MAIL_PASSWORD=.*|MAIL_PASSWORD=\$MAIL_PASSWORD|" \$ENV_FILE
sed -i "s|^MAIL_ENCRYPTION=.*|MAIL_ENCRYPTION=\$MAIL_ENCRYPTION|" \$ENV_FILE
sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=\$AWS_ACCESS_KEY_ID|" \$ENV_FILE
sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=\$AWS_SECRET_ACCESS_KEY|" \$ENV_FILE
sed -i "s|^AWS_DEFAULT_REGION=.*|AWS_DEFAULT_REGION=\$AWS_DEFAULT_REGION|" \$ENV_FILE
sed -i "s|^AWS_BUCKET=.*|AWS_BUCKET=\$AWS_BUCKET|" \$ENV_FILE
sed -i "s|^AWS_URL=.*|AWS_URL=\$AWS_URL|" \$ENV_FILE
sed -i "s|^OPEN_WEATHER_API_KEY=.*|OPEN_WEATHER_API_KEY=\$OPEN_WEATHER_API_KEY|" \$ENV_FILE

cd \$APP_DIR
php artisan key:generate
php artisan passport:install

# Fix permissions
sudo chown -R www-data:www-data $APP_DIR
sudo chmod -R 775 $APP_DIR/storage $APP_DIR/bootstrap/cache

echo "✅ .env configured, Laravel keys generated, and permissions fixed."

if [ -d "/var/www/core/public" ]; then
    # === Configure Apache Virtual Host ===
    cat << 'EOVHOST' > /etc/apache2/sites-available/svrel.conf
    <VirtualHost *:80>
        ServerAdmin admin@caymanasracing.com
        ServerName core3003.caymanasracing.com
        ServerAlias core3003.caymanasracing.com
        <Directory /var/www/core>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>
        DocumentRoot "/var/www/core/public"
        Header always set Access-Control-Allow-Origin "*"
        Header always set Access-Control-Allow-Headers "Content-Type, X-CSRF-TOKEN, X-Requested-With, Authorization"
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
    EOVHOST
    
    a2dissite 000-default.conf
    a2ensite svrel.conf
    systemctl reload apache2
    
    echo "✅ Apache virtual host 'svrel.conf' enabled."
else
  echo "⚠️ Skipping vhost setup — /var/www/core/public does not exist yet."
fi
EOF

chmod +x /home/ubuntu/setup.sh
chown ubuntu:ubuntu /home/ubuntu/setup.sh

# === Create README.TXT with Pre-Setup Instructions ===
cat << 'EOF' > /home/ubuntu/README.TXT
CPMS SERVER – PRE-SETUP INSTRUCTIONS
====================================

Before running setup.sh, please complete the following steps:

1. Secure MySQL
-------------------
Run the MySQL hardening script to set passwords and remove insecure defaults:

    sudo mysql_secure_installation

Recommended options:
- Set root password
- Remove anonymous users
- Disallow root login remotely
- Remove test database
- Reload privilege tables

2. Prepare the Database
---------------------------
You MUST create and import the production database **before running** setup.sh.

- Example:
    mysql -u root -p < /path/to/cpms_production_dump.sql

Make sure the database name matches what you will enter during the setup prompts.

3. Laravel Project Must Be Pushed
-----------------------------------
Your Laravel project must already be deployed via Git to `/var/www/cpms` using the post-receive hook setup. 

From your local machine, run:

    git remote add live ssh://ubuntu@<server_ip>:/var/repo/cpms.git
    git push live master

This will install dependencies and deploy the code.

4. Ready to Run `setup.sh`
------------------------------
Once all steps above are complete, run:

    sudo bash /home/ubuntu/setup.sh

This script will:
- Prompt for necessary `.env` values
- Generate app key and install Passport
- Fix file permissions
- Optionally enable Apache virtual host if `/var/www/core/public` exists

✅ Required `.env` Variables Prompted by `setup.sh`

Prepare the following values before running the script:

```env
APP_NAME=
APP_ENV=
APP_URL=

DB_DATABASE=
DB_USERNAME=
DB_PASSWORD=

MAIL_HOST=
MAIL_PORT=
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=
AWS_BUCKET=
AWS_URL=

OPEN_WEATHER_API_KEY=
==============================
File generated by provision script
EOF

chmod 644 /home/ubuntu/README.TXT
chown ubuntu:ubuntu /home/ubuntu/README.TXT
)  | tee /var/log/provision.log
