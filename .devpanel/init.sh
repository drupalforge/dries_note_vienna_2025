#!/usr/bin/env bash
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail
cd $APP_ROOT

LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee $LOG_FILE) 2>&1

TIMEFORMAT=%lR
# For faster performance, don't audit dependencies automatically.
export COMPOSER_NO_AUDIT=1

#== Remove root-owned files.
echo
echo Remove root-owned files.
time sudo rm -rf lost+found

#== Composer install.
echo
if [ -f composer.json ]; then
  if composer show --locked cweagans/composer-patches ^2 &> /dev/null; then
    echo 'Update patches.lock.json.'
    time composer prl
    echo
  fi
else
  echo 'Generate composer.json.'
  time source .devpanel/composer_setup.sh
  echo
fi
time composer -n update --no-progress
time ln -s -f $(realpath -s --relative-to=web/profiles project_template/web/profiles/drupal_cms_installer) web/profiles

#== Create the private files directory.
if [ ! -d private ]; then
  echo
  echo 'Create the private files directory.'
  time mkdir private
fi

#== Create the config sync directory.
if [ ! -d config/sync ]; then
  echo
  echo 'Create the config sync directory.'
  time mkdir -p config/sync
fi

#== Generate hash salt.
if [ ! -f .devpanel/salt.txt ]; then
  echo
  echo 'Generate hash salt.'
  time openssl rand -hex 32 > .devpanel/salt.txt
fi

#== Install Drupal.
echo
if [ -z "$(drush status --field=db-status)" ]; then
  echo 'Install Drupal.'
  if ${IS_DDEV_PROJECT:-false}; then
    # For some reason, writable directories are sometimes detected as not
    # writable, so loop until it works.
    until time drush -n si drupal_cms_installer installer_site_template_form.add_ons=byte; do
      :
    done
  else
    # Attempt install once; on failure, emit diagnostics and exit.
    if ! time drush -n -vvv --debug si drupal_cms_installer installer_site_template_form.add_ons=byte; then
      echo 'Drush site-install failed. Diagnostics:'
      echo 'Check updates.drupal.org (HEAD):'
      (curl -sS -I https://updates.drupal.org || true)
      echo 'Check release-history endpoint (HEAD):'
      (curl -sS -I https://updates.drupal.org/release-history/drupal/current || true)
      echo 'DNS resolution for updates.drupal.org:'
      (getent hosts updates.drupal.org || nslookup updates.drupal.org || ping -c 1 updates.drupal.org || true)
      echo 'Composer diagnose summary:'
      (composer -n diagnose || true)
      echo 'Check update fetch diagnostic logs:'
      (ls -lt logs/update-fetch-diagnosis-*.log 2>/dev/null | head -3 || echo 'No update fetch logs found')
      (tail -50 logs/update-fetch-diagnosis-*.log 2>/dev/null || true)
      exit 1
    fi
  fi
  time drush cr
  echo 'Apply Canvas AI Setup recipe.'
  time drush -q recipe ../custom_recipes/canvas_ai_setup
  time drush cr
  echo 'Apply Media Images recipe.'
  if ${IS_DDEV_PROJECT:-false}; then
    # For some reason, writable directories are sometimes detected as not
    # writable, so loop until it works.
    until time drush -q recipe ../custom_recipes/media_images; do
      :
    done
  else
    time drush -q recipe ../custom_recipes/media_images
  fi
  echo 'Apply Mercury Demo Page recipe.'
  time drush -q recipe ../custom_recipes/new_canvas_page
  time drush cr
  time drush sapi-i

  echo
  echo 'Tell Automatic Updates about patches.'
  drush -n cset --input-format=yaml package_manager.settings additional_trusted_composer_plugins '["cweagans/composer-patches"]'
  drush -n cset --input-format=yaml package_manager.settings additional_known_files_in_project_root '["patches.json", "patches.lock.json"]'
  time drush ev '\Drupal::moduleHandler()->invoke("automatic_updates", "modules_installed", [[], FALSE])'
else
  echo 'Update database.'
  time drush -n updb
fi

#== Warm up caches.
echo
echo 'Run cron.'
time drush cron
echo
echo 'Populate caches.'
time drush cache:warm &> /dev/null || :
time .devpanel/warm

#== Finish measuring script time.
INIT_DURATION=$SECONDS
INIT_HOURS=$(($INIT_DURATION / 3600))
INIT_MINUTES=$(($INIT_DURATION % 3600 / 60))
INIT_SECONDS=$(($INIT_DURATION % 60))
printf "\nTotal elapsed time: %d:%02d:%02d\n" $INIT_HOURS $INIT_MINUTES $INIT_SECONDS
