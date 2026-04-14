#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Copyright (C) 2024 DevPanel
# You can install any service here to support your project
# Please make sure you run apt update before install any packages
# Example:
# - apt-get update
# - apt-get install nano
#
# ----------------------------------------------------------------------
if [ -n "$DEBUG_SCRIPT" ]; then
  set -x
fi

# Install APT packages.
if ! command -v npm >/dev/null 2>&1; then
  apt-get update
  apt-get install -y jq nano npm
fi

# Enable AVIF support in GD extension if not already enabled.
if [ -z "$(php --ri gd | grep AVIF)" ]; then
  apt-get install -y libavif-dev
  docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp
  docker-php-ext-install gd
  # Mark runtime libraries as manually installed, then purge dev package to reduce image size
  for pkg in $(apt-cache depends libavif-dev | grep '^\s*Depends:' | grep -o 'libavif[^, ]*'); do
    apt-mark manual "$pkg"
  done
  apt-get purge -y -qq libavif-dev
  apt-get autoremove -y -qq
fi

PECL_UPDATED=false
# Install APCU extension. Bypass question about enabling internal debugging.
if ! php --ri apcu > /dev/null 2>&1; then
  $PECL_UPDATED || pecl update-channels && PECL_UPDATED=true
  pecl install apcu <<< ''
  echo 'extension=apcu.so' > /usr/local/etc/php/conf.d/apcu.ini
fi
# Install uploadprogress extension.
if ! php --ri uploadprogress > /dev/null 2>&1; then
  $PECL_UPDATED || pecl update-channels && PECL_UPDATED=true
  pecl install uploadprogress
  echo 'extension=uploadprogress.so' > /usr/local/etc/php/conf.d/uploadprogress.ini
fi
# Disable Xdebug if it's enabled, as it can interfere with performance and is
# not needed in production.
if [ -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini ]; then
  rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && PECL_UPDATED=true
fi
# Enable JIT if not already enabled, as it can improve performance for Drupal.
if php --ri 'Zend OPcache' | grep 'opcache.enable => On' > /dev/null 2>&1; then
  echo 'opcache.jit=tracing' > /usr/local/etc/php/conf.d/opcache.ini \
    && PECL_UPDATED=true
fi
# Reload Apache if it's running.
if $PECL_UPDATED && /etc/init.d/apache2 status > /dev/null; then
  /etc/init.d/apache2 reload
fi

# Add service hostnames to /etc/hosts if not already present
for host in etcd minio milvus attu; do
  if grep -q "$host" /etc/hosts; then
    echo "$host found in /etc/hosts"
  elif timeout 2 getent hosts "$host" >/dev/null 2>&1; then
    echo "$host resolves via getent"
  else
    echo "Adding $host to /etc/hosts"
    if sed "/localhost/s/$/ $host/" /etc/hosts | sudo tee /etc/hosts; then
      echo "$host added successfully"
    else
      echo "Failed to add $host to /etc/hosts"
      exit 1
    fi
  fi
done

# Ensure Milvus, Minio, and Etcd volume directories exist
mkdir -p "$APP_ROOT/.devpanel/milvus/volumes/milvus" \
         "$APP_ROOT/.devpanel/milvus/volumes/minio" \
         "$APP_ROOT/.devpanel/milvus/volumes/etcd" \
         "$WEB_ROOT" \
         /run/milvus

# Set ownership of Milvus volume directories
chown -R $APACHE_RUN_USER:$APACHE_RUN_GROUP \
  "$APP_ROOT" \
  /run/milvus

chmod go-rwx "$APP_ROOT/.devpanel/milvus/volumes/etcd"

if [ "${IS_DDEV_PROJECT:-false}" != "true" ]; then
  # Start supervisord only when not in DDEV, in background mode
  /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
fi
