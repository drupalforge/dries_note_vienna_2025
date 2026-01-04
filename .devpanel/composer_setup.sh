#!/usr/bin/env bash
# This file is an example for a template that wraps a Composer project. It
# pulls composer.json from the Drupal recommended project and customizes it.
# You do not need this file if your template provides its own composer.json.

set -eu -o pipefail
cd "$APP_ROOT"

# Create required composer.json and composer.lock files.
git clone --depth 1 --quiet https://github.com/FreelyGive/v2025demo.git
rm -rf v2025demo/LICENSE.txt
cp -rn v2025demo/* ./
cp -n v2025demo/.ddev/.env.template .ddev/
rm -rf v2025demo

# Scaffold settings.php.
composer config -jm extra.drupal-scaffold.file-mapping '{
    "[web-root]/robots.txt": false,
    "[web-root]/sites/default/settings.php": {
        "path": "web/core/assets/scaffold/files/default.settings.php",
        "overwrite": false
    },
    "[web-root]/base-path-rewrite.js": ".devpanel/base-path-rewrite.js"
}'
composer config scripts.post-drupal-scaffold-cmd \
    'cd web/sites/default && test -z "$(grep '\''include \$devpanel_settings;'\'' settings.php)" && patch -Np1 -r /dev/null < $APP_ROOT/.devpanel/drupal-settings.patch || :'

# Add AI demos.
time composer -n require --no-install \
    drupal/ai:1.2.x-dev@dev \
    drupal/ai_agents:1.2.x-dev@dev \
    drupal/ai_provider_openai:1.2.x-dev@dev \
    drupal/ai_simple_pdf_to_text:^1.0@alpha \
    drupal/ai_vdb_provider_milvus:1.1.x-dev@dev \
    drupal/page_cache_exclusion:^1.0 \
    drupal/pexels_ai:^1.0@alpha \
    jfcherng/php-diff:^6.0
