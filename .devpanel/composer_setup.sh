#!/usr/bin/env bash
# This file is an example for a template that wraps a Composer project. It
# pulls composer.json from the Drupal recommended project and customizes it.
# You do not need this file if your template provides its own composer.json.

set -eu -o pipefail
cd $APP_ROOT

# Create required composer.json and composer.lock files.
git clone --depth 1 https://github.com/FreelyGive/v2025demo.git
rm v2025demo/composer.lock v2025demo/LICENSE.txt
cp -rn v2025demo/* ./
rm -rf v2025demo

# Programmatically fix Composer 2.2 allow-plugins to avoid errors.
composer config --no-plugins allow-plugins.cweagans/composer-patches true

# Scaffold settings.php.
composer config -jm extra.drupal-scaffold.file-mapping '{
    "[web-root]/robots.txt": false,
    "[web-root]/sites/default/settings.php": {
        "path": "web/core/assets/scaffold/files/default.settings.php",
        "overwrite": false
    }
}'
composer config scripts.post-drupal-scaffold-cmd \
    'cd web/sites/default && test -z "$(grep '\''include \$devpanel_settings;'\'' settings.php)" && patch -Np1 -r /dev/null < $APP_ROOT/.devpanel/drupal-settings.patch || :'

# Add repositories for Webform libraries.
composer config repositories.tippyjs '{
    "type": "package",
    "package": {
        "name": "tippyjs/tippyjs",
        "version": "6.3.7",
        "type": "drupal-library",
        "extra": {
            "installer-name": "tippyjs"
        },
        "dist": {
            "url": "https://registry.npmjs.org/tippy.js/-/tippy.js-6.3.7.tgz",
            "type": "tar"
        },
        "license": "MIT"
    }
}'
composer config repositories.tabby '{
    "type": "package",
    "package": {
        "name": "tabby/tabby",
        "version": "12.0.3",
        "type": "drupal-library",
        "extra": {
            "installer-name": "tabby"
        },
        "dist": {
            "url": "https://github.com/cferdinandi/tabby/archive/refs/tags/v12.0.3.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories.signature_pad '{
    "type": "package",
    "package": {
        "name": "signature_pad/signature_pad",
        "version": "2.3.0",
        "type": "drupal-library",
        "extra": {
            "installer-name": "signature_pad"
        },
        "dist": {
            "url": "https://github.com/szimek/signature_pad/archive/refs/tags/v2.3.0.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories.progress-tracker '{
    "type": "package",
    "package": {
        "name": "progress-tracker/progress-tracker",
        "version": "2.0.7",
        "type": "drupal-library",
        "extra": {
            "installer-name": "progress-tracker"
        },
        "dist": {
            "url": "https://github.com/NigelOToole/progress-tracker/archive/refs/tags/2.0.7.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories.popperjs '{
    "type": "package",
    "package": {
        "name": "popperjs/popperjs",
        "version": "2.11.6",
        "type": "drupal-library",
        "extra": {
            "installer-name": "popperjs"
        },
        "dist": {
            "url": "https://registry.npmjs.org/@popperjs/core/-/core-2.11.6.tgz",
            "type": "tar"
        },
        "license": "MIT"
    }
}'
composer config repositories."jquery.timepicker" '{
    "type": "package",
    "package": {
        "name": "jquery/timepicker",
        "version": "1.14.0",
        "type": "drupal-library",
        "extra": {
            "installer-name": "jquery.timepicker"
        },
        "dist": {
            "url": "https://github.com/jonthornton/jquery-timepicker/archive/refs/tags/1.14.0.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories."jquery.textcounter" '{
    "type": "package",
    "package": {
        "name": "jquery/textcounter",
        "version": "0.9.1",
        "type": "drupal-library",
        "extra": {
            "installer-name": "jquery.textcounter"
        },
        "dist": {
            "url": "https://github.com/ractoon/jQuery-Text-Counter/archive/refs/tags/0.9.1.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories."jquery.select2" '{
    "type": "package",
    "package": {
        "name": "jquery/select2",
        "version": "4.0.13",
        "type": "drupal-library",
        "extra": {
            "installer-name": "jquery.select2"
        },
        "dist": {
            "url": "https://github.com/select2/select2/archive/refs/tags/4.0.13.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories."jquery.rateit" '{
    "type": "package",
    "package": {
        "name": "jquery/rateit",
        "version": "1.1.5",
        "type": "drupal-library",
        "extra": {
            "installer-name": "jquery.rateit"
        },
        "dist": {
            "url": "https://github.com/gjunge/rateit.js/archive/refs/tags/1.1.5.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories."jquery.intl-tel-input" '{
    "type": "package",
    "package": {
        "name": "jquery/intl-tel-input",
        "version": "17.0.19",
        "type": "drupal-library",
        "extra": {
            "installer-name": "jquery.intl-tel-input"
        },
        "dist": {
            "url": "https://github.com/jackocnr/intl-tel-input/archive/refs/tags/v17.0.19.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories."jquery.inputmask" '{
    "type": "package",
    "package": {
        "name": "jquery/inputmask",
        "version": "5.0.9",
        "type": "drupal-library",
        "extra": {
            "installer-name": "jquery.inputmask"
        },
        "dist": {
            "url": "https://github.com/RobinHerbots/jquery.inputmask/archive/refs/tags/5.0.9.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'
composer config repositories.codemirror '{
    "type": "package",
    "package": {
        "name": "codemirror/codemirror",
        "version": "5.65.12",
        "type": "drupal-library",
        "extra": {
            "installer-name": "codemirror"
        },
        "dist": {
            "url": "https://github.com/components/codemirror/archive/refs/tags/5.65.12.zip",
            "type": "zip"
        },
        "license": "MIT"
    }
}'

# Add Webform libraries and AI demos.
composer require -n --no-install \
    codemirror/codemirror \
    drupal/ai:1.2.x-dev@dev \
    drupal/ai_agents:1.2.x-dev@dev \
    drupal/ai_provider_litellm \
    drupal/ai_provider_openai:1.2.x-dev@dev \
    drupal/ai_simple_pdf_to_text:^1.0@alpha \
    drupal/ai_vdb_provider_milvus:1.1.x-dev@dev \
    drupal/page_cache_exclusion:^1.0 \
    drupal/pexels_ai:^1.0@alpha \
    jfcherng/php-diff:^6.0 \
    jquery/inputmask \
    jquery/intl-tel-input \
    jquery/rateit \
    jquery/select2 \
    jquery/textcounter \
    jquery/timepicker \
    popperjs/popperjs \
    progress-tracker/progress-tracker \
    signature_pad/signature_pad \
    tabby/tabby \
    tippyjs/tippyjs