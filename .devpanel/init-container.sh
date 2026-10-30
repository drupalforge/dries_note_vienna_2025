#!/bin/bash
# ---------------------------------------------------------------------
# Copyright (C) 2026 DevPanel
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

export PATH="$APP_ROOT/vendor/bin:$PATH"
cd $APP_ROOT

#== Import database
if [ -z "$(drush status --field=db-status)" ]; then
  if [[ -f .devpanel/dumps/db.sql.gz ]]; then
    echo 'Import mysql file ...'
    drush sqlq --file=../.devpanel/dumps/db.sql.gz
    gzip .devpanel/dumps/db.sql
  fi
fi

if [[ -n "${DB_SYNC_VOL:-}" ]]; then
  if [[ ! -f "../build/.devpanel/init-container.sh" ]]; then
    sudo rm -rf ../build/lost+found
    echo 'Sync volume...'
    if [[ -n "$DRUPALFORGE_DEVCONTAINER" ]]; then
      # Preserve source permissions, but ensure rsync-created directories remain
      # user-writable so it can continue copying nested files on fresh volumes.
      sudo rsync -a --chmod=Du+w --ignore-existing --exclude .git --exclude .devpanel/dumps ./ ../build
    else
      sudo rsync -a --delete --ignore-existing --exclude .devpanel/dumps ./ ../build
    fi
  fi
fi

drush -n updb
echo
echo 'Run cron.'
drush cron
echo
echo 'Populate caches.'
drush cache:warm &> /dev/null || :
.devpanel/warm
.devpanel/warm /user/login

#== Fix ownership for strict permissions.
echo
echo 'Fix ownership for strict permissions.'
sudo chown -R ${APACHE_RUN_USER:=www-data}:${APACHE_RUN_GROUP:=www-data} ../build/web/sites/default/files ../build/private ../build/config/sync
