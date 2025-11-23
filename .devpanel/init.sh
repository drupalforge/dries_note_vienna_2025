#!/usr/bin/env bash
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail
cd $APP_ROOT

LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee $LOG_FILE) 2>&1

# Diagnostic checks for /etc/hosts
if [ ! -e /etc/hosts ]; then
  echo "/etc/hosts does not exist"
else
  echo "/etc/hosts exists:"
  ls -lhA /etc/hosts || echo "ls failed: $?"
  [ -w /etc/hosts ] && echo "/etc/hosts is writable" || echo "/etc/hosts is NOT writable (owner: $(stat -c "%U:%G" /etc/hosts))"
  cat /etc/hosts || echo "cat failed: $?"

  # Add service hostnames to localhost lines in /etc/hosts if not already present
  echo "Checking hostname resolution..."
  for host in etcd minio milvus attu; do
    # Check grep first (faster), only run getent if grep fails
    timeout 1 grep -q "$host" /etc/hosts
    grep_result=$?
    if [ $grep_result -eq 0 ]; then
      echo "$host found in /etc/hosts"
    elif [ $grep_result -eq 124 ]; then
      echo "$host grep timed out, skipping"
    elif timeout 2 getent hosts "$host" >/dev/null 2>&1; then
      echo "$host resolves via getent"
    else
      echo "Adding $host to /etc/hosts"
      if sudo sed -i "/localhost/s/$/ $host/" /etc/hosts; then
        echo "$host added successfully"
      else
        echo "Failed to add $host (possibly read-only), continuing..."
      fi
    fi
  done
  echo "Hostname configuration complete"
fi

TIMEFORMAT=%lR
# For faster performance, don't audit dependencies automatically.
export COMPOSER_NO_AUDIT=1

# Install VSCode Extensions
if [ -n "${DP_VSCODE_EXTENSIONS:-}" ]; then
  IFS=','
  for value in $DP_VSCODE_EXTENSIONS; do
    time code-server --install-extension $value
  done
fi

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
  # For some reason, writable directories are sometimes detected as not
  # writable, so loop until it works.
  until time drush -n si drupal_cms_installer installer_site_template_form.add_ons=byte; do
    :
  done
  time drush cr
  echo 'Apply Canvas AI Setup recipe.'
  time drush -q recipe ../custom_recipes/canvas_ai_setup
  time drush cr
  echo 'Apply Media Images recipe.'
  until time drush -q recipe ../custom_recipes/media_images; do
    :
  done
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
