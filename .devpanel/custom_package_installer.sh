#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Copyright (C) 2024 DevPanel
# You can install any service here to support your project
# Please make sure you run apt update before install any packages
# Example:
# - sudo apt-get update
# - sudo apt-get install nano
#
# ----------------------------------------------------------------------
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail

# Install APT packages.
if ! command -v npm >/dev/null 2>&1; then
  # If DEBIAN_FRONTEND is set to noninteractive, this is likely a Docker build
  # and apt-get update has already run.
  if [ "${DEBIAN_FRONTEND:-}" != "noninteractive" ]; then
    sudo apt-get update -qq
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq nano npm
fi

# Enable AVIF support in GD extension if not already enabled.
if [ -z "$(php --ri gd | grep AVIF)" ]; then
  sudo apt-get install -y -qq libavif-dev
  sudo docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp
  sudo docker-php-ext-install gd
  # Mark runtime libraries as manually installed, then purge dev package to reduce image size
  for pkg in $(apt-cache depends libavif-dev | grep '^\s*Depends:' | grep -o 'libavif[^, ]*'); do
    sudo apt-mark manual "$pkg"
  done
  sudo apt-get purge -y -qq libavif-dev
  sudo apt-get autoremove -y -qq
fi

PECL_UPDATED=false
# Install APCU extension. Bypass question about enabling internal debugging.
if ! php --ri apcu > /dev/null 2>&1; then
  $PECL_UPDATED || sudo pecl update-channels && PECL_UPDATED=true
  sudo pecl install apcu <<< ''
  echo 'extension=apcu.so' | sudo tee /usr/local/etc/php/conf.d/apcu.ini
fi
# Install uploadprogress extension.
if ! php --ri uploadprogress > /dev/null 2>&1; then
  $PECL_UPDATED || sudo pecl update-channels && PECL_UPDATED=true
  sudo pecl install uploadprogress
  echo 'extension=uploadprogress.so' | sudo tee /usr/local/etc/php/conf.d/uploadprogress.ini
fi
# Reload Apache if it's running.
if $PECL_UPDATED && sudo /etc/init.d/apache2 status > /dev/null; then
  sudo /etc/init.d/apache2 reload
fi
