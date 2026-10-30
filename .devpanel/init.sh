#!/usr/bin/env bash
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail
cd $APP_ROOT

LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee $LOG_FILE) 2>&1

TIMEFORMAT=%lR
# Install regardless of security audit.
export COMPOSER_NO_AUDIT=1
export COMPOSER_NO_BLOCKING=1
# Keep deprecated var for compatibility with Composer versions where
# COMPOSER_NO_BLOCKING/--no-blocking is not supported yet.
export COMPOSER_NO_SECURITY_BLOCKING=1

# Convert an OpenAI reset duration (for example 1m30s, 1.5s or 250ms) to whole
# seconds, rounded up.
reset_seconds() {
  awk -v d="$1" 'BEGIN {
    t = 0
    while (match(d, /^[0-9.]+(ms|h|m|s)/)) {
      n = substr(d, 1, RLENGTH); d = substr(d, RLENGTH + 1)
      if (n ~ /ms$/) t += n / 1000
      else if (n ~ /h$/) t += n * 3600
      else if (n ~ /m$/) t += n * 60
      else t += n
    }
    print (t == int(t)) ? t : int(t) + 1
  }'
}

# Print a response header value; missing headers print nothing and succeed.
rate_limit_header() {
  grep -i "^$2:" "$1" | awk '{print $2}' | tr -d '\r' || true
}

# Probe the embedding model used for indexing and wait when its request or
# token limit is exhausted or nearly exhausted.
check_rate_limit_and_delay() {
  if [ -z "${OPENAI_KEY:-}" ]; then
    return 0
  fi
  local headers status wait=0 kind remaining limit reset seconds retry_after
  headers=$(mktemp)
  status=$(curl -s -o /dev/null -D "$headers" -w '%{http_code}' \
    -X POST https://api.openai.com/v1/embeddings \
    -H "Authorization: Bearer ${OPENAI_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"text-embedding-3-small","input":"rate limit probe"}' || true)

  for kind in requests tokens; do
    remaining=$(rate_limit_header "$headers" "x-ratelimit-remaining-$kind")
    limit=$(rate_limit_header "$headers" "x-ratelimit-limit-$kind")
    reset=$(rate_limit_header "$headers" "x-ratelimit-reset-$kind")
    if [[ "$remaining" =~ ^[0-9]+$ ]] && [[ "$limit" =~ ^[0-9]+$ ]]; then
      echo "OpenAI $kind: $remaining/$limit remaining."
    fi
    # 429 reset headers are useful even when quota counters are unavailable.
    if [ "$status" = 429 ] || { [[ "$remaining" =~ ^[0-9]+$ ]] && [[ "$limit" =~ ^[0-9]+$ ]] && [ "$remaining" -lt $((limit / 5)) ]; }; then
      seconds=$(reset_seconds "$reset")
      if [ "$seconds" -gt "$wait" ]; then
        wait=$seconds
      fi
    fi
  done
  retry_after=$(rate_limit_header "$headers" retry-after)
  rm -f "$headers"
  if [[ "$retry_after" =~ ^[0-9]+$ ]] && [ "$retry_after" -gt "$wait" ]; then
    wait=$retry_after
  fi
  if [ "$status" = 429 ] && [ "$wait" -eq 0 ]; then
    wait=20
  elif [ "$status" != 200 ] && [ "$status" != 429 ]; then
    echo "OpenAI rate limit probe returned HTTP $status."
  fi
  if [ "$wait" -gt 300 ]; then
    echo "OpenAI rate limit resets in ${wait}s; waiting 300s at most."
    wait=300
  fi
  if [ "$wait" -gt 0 ]; then
    echo "Waiting ${wait}s for OpenAI rate limit reset..."
    sleep "$wait"
  fi
}

# Count items still pending in enabled, writable Search API indexes.
remaining_search_items() {
  local count
  count=$(drush php:eval '$n = 0; foreach (\Drupal\search_api\Entity\Index::loadMultiple() as $index) { if ($index->status() && !$index->isReadOnly()) { $n += $index->getTrackerInstance()->getRemainingItemsCount(); } } echo $n;')
  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    echo "Could not count pending search items: $count" >&2
    return 1
  fi
  echo "$count"
}

# Index in small, throttled chunks. Failed items stay pending, so retry them
# with exponential backoff, and fail the build if indexing stops progressing.
# Search API logs indexing errors without returning a failure exit code.
index_until_complete() {
  local remaining previous retries=0 delay
  remaining=$(remaining_search_items)
  while [ "$remaining" -gt 0 ]; do
    check_rate_limit_and_delay
    drush sapi-i --limit=5 --batch-size=5
    previous=$remaining
    remaining=$(remaining_search_items)
    echo "$remaining search items remaining."
    if [ "$remaining" -lt "$previous" ]; then
      retries=0
      continue
    fi
    retries=$((retries + 1))
    if [ "$retries" -gt 5 ]; then
      echo "Search indexing is incomplete ($remaining items remaining); refusing to publish." >&2
      return 1
    fi
    delay=$(((2 ** retries) * 5 + RANDOM % 5))
    echo "No indexing progress; retry $retries/5 in ${delay}s."
    sleep "$delay"
  done
  echo 'Search indexing complete.'
}

#== Remove root-owned files.
echo
echo Remove root-owned files.
time sudo rm -rf lost+found

#== Composer install.
echo
if [ -f composer.json ]; then
  if composer show cweagans/composer-patches ^2 &> /dev/null; then
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

#== Install Drupal.
echo
if [ -z "$(drush status --field=db-status)" ]; then
  echo 'Install Drupal.'
  if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
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
  if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
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
  time index_until_complete

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
echo 'Index items queued by cron.'
time index_until_complete
echo
echo 'Populate caches.'
time drush cache:warm &> /dev/null || :
time .devpanel/warm
time .devpanel/warm /user/login

#== Finish measuring script time.
INIT_DURATION=$SECONDS
INIT_HOURS=$(($INIT_DURATION / 3600))
INIT_MINUTES=$(($INIT_DURATION % 3600 / 60))
INIT_SECONDS=$(($INIT_DURATION % 60))
printf "\nTotal elapsed time: %d:%02d:%02d\n" $INIT_HOURS $INIT_MINUTES $INIT_SECONDS
