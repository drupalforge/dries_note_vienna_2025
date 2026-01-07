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

# Track start time for rate limit calculations
SCRIPT_START_TIME=$(date +%s)

# Function to check rate limit and add delay if needed
check_rate_limit_and_delay() {
  if [ -n "${OPENAI_KEY:-}" ]; then
    echo "Checking OpenAI API rate limit status..."
    
    # Make a minimal API call to check rate limit headers
    RESPONSE=$(curl -s -i -X POST https://api.openai.com/v1/chat/completions \
      -H "Authorization: Bearer ${OPENAI_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"model":"gpt-4.1","messages":[{"role":"user","content":"test"}],"max_tokens":1}' 2>&1 || echo "")
    
    # Extract rate limit headers
    REMAINING=$(echo "$RESPONSE" | grep -i "x-ratelimit-remaining-requests:" | awk '{print $2}' | tr -d '\r')
    LIMIT=$(echo "$RESPONSE" | grep -i "x-ratelimit-limit-requests:" | awk '{print $2}' | tr -d '\r')
    RESET_TIME=$(echo "$RESPONSE" | grep -i "x-ratelimit-reset-requests:" | awk '{print $2}' | tr -d '\r')
    
    if [ -n "$REMAINING" ] && [ -n "$LIMIT" ]; then
      echo "Rate limit: $REMAINING/$LIMIT requests remaining"
      
      # If we're below 20% of limit, wait for reset
      THRESHOLD=$((LIMIT / 5))
      if [ "$REMAINING" -lt "$THRESHOLD" ]; then
        CURRENT_TIME=$(date +%s)
        
        # Parse reset time (format: 1m30s or 30s)
        if [[ "$RESET_TIME" =~ ([0-9]+)m([0-9]+)s ]]; then
          WAIT_SECONDS=$((${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]}))
        elif [[ "$RESET_TIME" =~ ([0-9]+)s ]]; then
          WAIT_SECONDS=${BASH_REMATCH[1]}
        elif [[ "$RESET_TIME" =~ ([0-9]+)ms ]]; then
          WAIT_SECONDS=1
        else
          # Default to 60 seconds if can't parse
          WAIT_SECONDS=60
        fi
        
        echo "Only $REMAINING requests remaining (threshold: $THRESHOLD). Waiting ${WAIT_SECONDS}s for rate limit reset..."
        sleep $WAIT_SECONDS
      fi
    else
      # Fallback: calculate time-based delay
      CURRENT_TIME=$(date +%s)
      ELAPSED=$((CURRENT_TIME - SCRIPT_START_TIME))
      
      # If less than 60 seconds elapsed, wait the difference
      if [ $ELAPSED -lt 60 ]; then
        WAIT_TIME=$((60 - ELAPSED))
        echo "Elapsed time: ${ELAPSED}s. Adding ${WAIT_TIME}s delay to avoid rate limit..."
        sleep $WAIT_TIME
      fi
    fi
  fi
}

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
time composer -n install --no-progress
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
    time drush -n si drupal_cms_installer installer_site_template_form.add_ons=byte
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
check_rate_limit_and_delay
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
