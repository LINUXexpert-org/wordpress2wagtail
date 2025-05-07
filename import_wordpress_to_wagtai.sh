#!/bin/bash

################################################################################
# WordPress to Wagtail Import Script
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
EXPORT_FILE="/tmp/wordpress_export.tar.gz"
EXPORT_DIR="/tmp/wp_migration"
MEDIA_DIR="/var/www/$WAGTAIL_PROJECT/media"
PROJECT_DIR="/var/www/$WAGTAIL_PROJECT"
VENV_DIR="$PROJECT_DIR/venv"
DJANGO_MANAGE="$PROJECT_DIR/manage.py"

# Ensure export file exists
if [[ ! -f "$EXPORT_FILE" ]]; then
    echo "Error: Export file not found! Please transfer it first."
    exit 1
fi

echo "Extracting export archive..."
mkdir -p "$EXPORT_DIR"
tar -xzvf "$EXPORT_FILE" -C "$EXPORT_DIR"

echo "Moving media files..."
mkdir -p "$MEDIA_DIR"
rsync -avz "$EXPORT_DIR/uploads/" "$MEDIA_DIR/"

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Install dependencies
pip install wagtail markdown pandas

# Import WordPress content into Wagtail
echo "Importing WordPress posts and pages..."
python <<EOF
import csv
import os
import django
from django.utils.text import slugify
from wagtail.core.models import Page
from wagtail.contrib.redirects.models import Redirect
from django.contrib.sites.models import Site

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "$WAGTAIL_PROJECT.settings")
django.setup()

home_page = Page.objects.get(title="Home")
site = Site.objects.get(domain="$DOMAIN")

with open("$EXPORT_DIR/posts_pages.csv", newline='') as csvfile:
    reader = csv.DictReader(csvfile, fieldnames=["ID", "title", "content", "type", "date", "slug"])
    next(reader)  # Skip header

    for row in reader:
        title = row["title"]
        content = row["content"]
        post_type = row["type"]
        slug = slugify(row["slug"])

        new_page = Page(
            title=title,
            slug=slug,
            live=True,
            first_published_at=row["date"]
        )

        if post_type == "post":
            new_page.content_type = "blog.BlogPage"
        else:
            new_page.content_type = "home.HomePage"

        home_page.add_child(instance=new_page)
        print(f"Imported: {title}")

        # Create redirects
        old_url = "/index.php/" + row["slug"]
        new_url = "/" + row["slug"]
        Redirect.objects.create(old_path=old_url, redirect_link=new_url, site=site)
        print(f"Redirect added: {old_url} -> {new_url}")

print("Import completed!")
EOF

echo "Restarting services..."
sudo systemctl restart gunicorn
sudo systemctl restart nginx

echo "Migration complete! Your new Wagtail site is live at https://$DOMAIN"
