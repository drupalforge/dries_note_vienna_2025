#!/bin/bash
# ---------------------------------------------------------------------
# Copyright (C) 2025 DevPanel
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation version 3 of the
# License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# For GNU Affero General Public License see <https://www.gnu.org/licenses/>.
# ----------------------------------------------------------------------

#== Import database
if [ -z "$(drush status --field=db-status)" ]; then
  if [[ -f "$APP_ROOT/.devpanel/dumps/db.sql.gz" ]]; then
    echo  'Import mysql file ...'
    drush sqlq --file="$APP_ROOT/.devpanel/dumps/db.sql.gz" --file-delete
  fi
fi

if [[ -n "$DB_SYNC_VOL" ]]; then
  if [[ ! -f "/var/www/build/.devpanel/init-container.sh" ]]; then
    echo  'Sync volume...'
    sudo chown -R 1000:1000 /var/www/build 
    rsync -av --delete --delete-excluded $APP_ROOT/ /var/www/build
  fi
fi

drush -n updb
echo
echo 'Run cron.'
drush cron
echo
echo 'Populate caches.'
drush cache:warm &> /dev/null || :
$APP_ROOT/.devpanel/warm

# Restore Milvus volumes from archive if present
MILVUS_VOL_DIR="$APP_ROOT/.devpanel/milvus/volumes"
MILVUS_ARCHIVE="$APP_ROOT/.devpanel/dumps/milvus.tgz"
if [ -f "$MILVUS_ARCHIVE" ]; then
  echo 'Restoring Milvus volumes from archive...'
  mkdir -p "$MILVUS_VOL_DIR"
  rm -rf "$MILVUS_VOL_DIR"/*
  tar xzf "$MILVUS_ARCHIVE" -C "$MILVUS_VOL_DIR"
fi
