#!/bin/bash

################################################################################
# WordPress Export Script
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
read -p "Enter the WordPress database name: " WP_DB_NAME
read -p "Enter the WordPress database user: " WP_DB_USER
read -s -p "Enter the WordPress database password: " WP_DB_PASS
echo ""
read -p "Enter the WordPress site directory (e.g., /var/www/html): " WP_DIR
EXPORT_DIR="/tmp/wp_migration"
EXPORT_FILE="wordpress_export.tar.gz"

echo "Creating export directory..."
mkdir -p "$EXPORT_DIR"

# Dump WordPress database
echo "Exporting WordPress database..."
mysqldump -u "$WP_DB_USER" -p"$WP_DB_PASS" "$WP_DB_NAME" > "$EXPORT_DIR/wordpress.sql"

# Extract WordPress posts and pages
echo "Extracting posts and pages..."
mysql -u "$WP_DB_USER" -p"$WP_DB_PASS" "$WP_DB_NAME" -e "
SELECT ID, post_title, post_content, post_type, post_date, post_name
FROM wp_posts
WHERE post_status = 'publish' AND (post_type = 'post' OR post_type = 'page');" > "$EXPORT_DIR/posts_pages.csv"

# Copy media files
echo "Copying media files..."
rsync -avz "$WP_DIR/wp-content/uploads/" "$EXPORT_DIR/uploads/"

# Compress everything
echo "Creating tar.gz archive..."
tar -czvf "$EXPORT_FILE" -C "$EXPORT_DIR" .

echo "Export complete! File saved as $EXPORT_FILE."
echo "Transfer this file to your Wagtail server for import."
