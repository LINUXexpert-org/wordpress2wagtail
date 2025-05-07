#!/bin/bash

################################################################################
# Wagtail Deployment Script for Debian with Nginx and Let's Encrypt SSL
#
# Copyright (C) 2025 linuxexpert.org
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Attribution: This script was developed by linuxexpert.org
################################################################################

set -e  # Exit immediately if a command fails
set -o pipefail  # Exit on pipeline errors

# Interactive prompts
read -p "Enter your domain (e.g., example.com): " DOMAIN
read -p "Enter the Wagtail project name: " WAGTAIL_PROJECT
read -p "Enter the PostgreSQL database name: " DB_NAME
read -p "Enter the PostgreSQL username: " DB_USER
read -s -p "Enter the PostgreSQL password: " DB_PASS
echo ""

# Set directories
PROJECT_DIR="/var/www/$WAGTAIL_PROJECT"
VENV_DIR="$PROJECT_DIR/venv"
GUNICORN_SERVICE="/etc/systemd/system/gunicorn.service"
NGINX_CONF="/etc/nginx/sites-available/$WAGTAIL_PROJECT"

echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv python3-dev \
                     postgresql postgresql-contrib libpq-dev \
                     nginx certbot python3-certbot-nginx \
                     supervisor git

# Set up PostgreSQL
echo "Setting up PostgreSQL database..."
sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
ALTER ROLE $DB_USER SET client_encoding TO 'utf8';
ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';
ALTER ROLE $DB_USER SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

# Create Wagtail project
echo "Creating Wagtail project..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install wagtail psycopg2 gunicorn

wagtail start "$WAGTAIL_PROJECT" .
cd "$PROJECT_DIR"

# Configure Wagtail settings
echo "Configuring Wagtail settings..."
sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = \['$DOMAIN', 'localhost'\]/" "$PROJECT_DIR/$WAGTAIL_PROJECT/settings/base.py"
cat >> "$PROJECT_DIR/$WAGTAIL_PROJECT/settings/base.py" <<EOL

# Database configuration
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '$DB_NAME',
        'USER': '$DB_USER',
        'PASSWORD': '$DB_PASS',
        'HOST': 'localhost',
        'PORT': '',
    }
}
EOL

# Run migrations and create superuser
echo "Running migrations..."
python manage.py migrate
python manage.py createsuperuser --username=admin --email=admin@$DOMAIN --noinput || true

# Collect static files
echo "Collecting static files..."
python manage.py collectstatic --noinput

# Set up Gunicorn
echo "Setting up Gunicorn..."
cat > "$GUNICORN_SERVICE" <<EOL
[Unit]
Description=Gunicorn instance to serve Wagtail
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind unix:$PROJECT_DIR/gunicorn.sock $WAGTAIL_PROJECT.wsgi:application

[Install]
WantedBy=multi-user.target
EOL

# Start and enable Gunicorn
sudo systemctl daemon-reload
sudo systemctl start gunicorn
sudo systemctl enable gunicorn

# Configure Nginx
echo "Configuring Nginx..."
cat > "$NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location /static/ {
        alias $PROJECT_DIR/static/;
    }

    location /media/ {
        alias $PROJECT_DIR/media/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$PROJECT_DIR/gunicorn.sock;
    }
}
EOL

sudo ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/"
sudo systemctl restart nginx

# Obtain SSL Certificate
echo "Obtaining Let's Encrypt SSL certificate..."
sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN

echo "Deployment completed! Access your site securely at https://$DOMAIN"
