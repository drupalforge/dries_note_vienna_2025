#!/usr/bin/env bash
# This file is an example for a template that wraps a Composer project. It
# pulls composer.json from the Drupal recommended project and customizes it.
# You do not need this file if your template provides its own composer.json.

set -eu -o pipefail
cd $APP_ROOT

# Create required composer.json and composer.lock files.
composer create-project --no-install ${PROJECT:=drupal/recommended-project}
cp -r "${PROJECT#*/}"/* ./
rm -rf "${PROJECT#*/}" patches.lock.json

# Programmatically fix Composer 2.2 allow-plugins to avoid errors.
composer config --no-plugins allow-plugins.cweagans/composer-patches true

# Scaffold settings.php.
composer config -jm extra.drupal-scaffold.file-mapping '{
    "[web-root]/sites/default/settings.php": {
        "path": "web/core/assets/scaffold/files/default.settings.php",
        "overwrite": false
    }
}'
composer config scripts.post-drupal-scaffold-cmd \
    'cd web/sites/default && test -z "$(grep '\''include \$devpanel_settings;'\'' settings.php)" && patch -Np1 -r /dev/null < $APP_ROOT/.devpanel/drupal-settings.patch || :'

# Add Drush and Composer Patches.
composer require -n --no-update \
    drush/drush \
    cweagans/composer-patches:^2@beta
