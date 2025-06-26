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
chmod -R 775 storage bootstrap/cache

echo ">>> Deployment complete ✅"
EOF

chmod +x "$GIT_DIR/hooks/post-receive"

# === Final Permissions ===
chown -R www-data:www-data "$GIT_DIR"
chmod -R 775 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"

# === Apache Restart ===
systemctl restart apache2

# === Create setup-env.sh Script ===
cat << EOF > /home/ubuntu/setup-env.sh
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
EOF

chmod +x /home/ubuntu/setup-env.sh
chown ubuntu:ubuntu /home/ubuntu/setup-env.sh
