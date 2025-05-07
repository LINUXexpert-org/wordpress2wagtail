#!/bin/bash

################################################################################
# Wagtail Image Optimization & Permalink Restructuring Script
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

set -e

# User input
read -p "Enter the Wagtail project name: " WAGTAIL_PROJECT
read -p "Enter the domain for the Wagtail site (e.g., example.com): " DOMAIN
MEDIA_DIR="/var/www/$WAGTAIL_PROJECT/media"
PROJECT_DIR="/var/www/$WAGTAIL_PROJECT"
VENV_DIR="$PROJECT_DIR/venv"
DJANGO_MANAGE="$PROJECT_DIR/manage.py"

# Ensure required tools are installed
echo "Checking for required tools..."
sudo apt update
sudo apt install -y jpegoptim optipng webp

echo "Optimizing JPEG and PNG images..."
find "$MEDIA_DIR" -type f -iname "*.jpg" -exec jpegoptim --max=85 --strip-all {} \;
find "$MEDIA_DIR" -type f -iname "*.jpeg" -exec jpegoptim --max=85 --strip-all {} \;
find "$MEDIA_DIR" -type f -iname "*.png" -exec optipng -o7 {} \;

echo "Converting images to WebP format..."
find "$MEDIA_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -exec sh -c 'cwebp -q 80 "$1" -o "${1%.*}.webp"' _ {} \;

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Install dependencies if not already installed
pip install wagtail django

echo "Fixing permalink redirects in Wagtail..."
python <<EOF
import os
import django
from wagtail.contrib.redirects.models import Redirect
from django.contrib.sites.models import Site

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "$WAGTAIL_PROJECT.settings")
django.setup()

site = Site.objects.get(domain="$DOMAIN")

# Fix common WordPress permalink structures
wp_permalink_prefixes = ["/index.php/", "/?p=", "/category/", "/tag/", "/author/"]

for redirect in Redirect.objects.filter(site=site):
    for prefix in wp_permalink_prefixes:
        if redirect.old_path.startswith(prefix):
            new_path = redirect.old_path.replace(prefix, "/", 1)
            redirect.old_path = new_path
            redirect.save()
            print(f"Updated redirect: {redirect.old_path} -> {redirect.redirect_link}")

print("Permalink restructuring complete!")
EOF

echo "Restarting services..."
sudo systemctl restart gunicorn
sudo systemctl restart nginx

echo "Optimization and permalink fixes are complete!"
