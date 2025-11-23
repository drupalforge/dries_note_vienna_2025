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

# Helper functions for safe logging operations when running as non-root user.
# These functions handle log file access permissions by using sudo when necessary.

# Check if the script is running as root (UID 0).
is_root() {
  [ "$(id -u)" -eq 0 ]
}

# Create /var/log/etcd.log with permissive permissions (0666) so non-root users can write.
# Uses sudo if the script is not running as root.
ensure_log_file() {
  local log_file="${1:-/var/log/etcd.log}"
  if is_root; then
    touch "$log_file"
    chmod 0666 "$log_file"
  else
    sudo touch "$log_file"
    sudo chmod 0666 "$log_file"
  fi
}

# Append a single line to a log file using tee.
# Uses sudo tee if the script is not running as root.
# Example: log_append "Starting etcd service..."
log_append() {
  local message="$1"
  local log_file="${2:-/var/log/etcd.log}"
  if is_root; then
    echo "$message" | tee -a "$log_file" >/dev/null
  else
    echo "$message" | sudo tee -a "$log_file" >/dev/null
  fi
}

# Run an arbitrary command as root using bash -c.
# This ensures shell redirections in the command run with root privileges.
# Uses sudo bash -c if the script is not running as root.
# Example: run_as_root "etcd --data-dir=/var/lib/etcd >/var/log/etcd.log 2>&1 &"
run_as_root() {
  local cmd="$1"
  if is_root; then
    bash -c "$cmd"
  else
    sudo bash -c "$cmd"
  fi
}

# Install APT packages.
if ! command -v milvus >/dev/null 2>&1; then
  # Ensure log file exists with proper permissions before any redirections occur.
  ensure_log_file /var/log/etcd.log
  
  sudo apt-get update
  ARCH=$(dpkg --print-architecture)
  
  # Install dependencies.
  sudo apt-get install -y jq nano npm wget curl
  
  # Install etcd manually (required for Milvus external etcd mode)
  # Note: Milvus supports embedded etcd, but it has limitations in containerized environments.
  # External etcd provides better reliability for DDEV/Docker deployments.
  if ! command -v etcd >/dev/null 2>&1; then
    ETCD_VER=v3.5.16
    ETCD_ARCH="linux-arm64"
    if [ "$ARCH" = "amd64" ]; then
      ETCD_ARCH="linux-amd64"
    fi
    
    wget -q https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-${ETCD_ARCH}.tar.gz
    sudo tar -xzf etcd-${ETCD_VER}-${ETCD_ARCH}.tar.gz -C /tmp
    sudo cp /tmp/etcd-${ETCD_VER}-${ETCD_ARCH}/etcd* /usr/local/bin/
    sudo chmod +x /usr/local/bin/etcd /usr/local/bin/etcdctl
    rm -rf etcd-${ETCD_VER}-${ETCD_ARCH}.tar.gz
    sudo rm -rf /tmp/etcd-${ETCD_VER}-${ETCD_ARCH}
    
    # Create etcd data and log directories.
    sudo mkdir -p /var/lib/etcd /var/log
    # Copy Supervisor config for etcd.
    sudo mkdir -p /etc/supervisor/conf.d
    if [ -f "$APP_ROOT/.devpanel/milvus/etcd.conf" ]; then
      sudo cp "$APP_ROOT/.devpanel/milvus/etcd.conf" /etc/supervisor/conf.d/etcd.conf
    fi
    # Start etcd directly after install. (Supervisor will manage on next restart.)
    # Use run_as_root to ensure shell redirections run with root privileges.
    run_as_root "setsid etcd --data-dir=/var/lib/etcd \
      --listen-client-urls=http://127.0.0.1:2379 \
      --advertise-client-urls=http://127.0.0.1:2379 \
      --listen-peer-urls=http://127.0.0.1:2380 </dev/null >/var/log/etcd.log 2>&1 &"
    # Wait for etcd to be ready.
    echo "Waiting for etcd to be ready..."
    for i in {1..30}; do
      if curl -s http://127.0.0.1:2379/health | grep -q 'true'; then
        echo "etcd is ready."
        break
      fi
      sleep 1
    done
    if ! curl -s http://127.0.0.1:2379/health | grep -q 'true'; then
      echo "ERROR: etcd did not become ready in time." >&2
      exit 1
    fi
  fi
  
  # Download Milvus deb package.
  wget https://github.com/milvus-io/milvus/releases/download/v2.6.4/milvus_2.6.4-1_${ARCH}.deb
  
  # Extract and configure Milvus YAML BEFORE installing the package.
  # This prevents the package from starting with wrong config.
  sudo dpkg-deb -x milvus_2.6.4-1_${ARCH}.deb /tmp/milvus_extract
  sudo mkdir -p /etc/milvus/configs
  sudo cp /tmp/milvus_extract/etc/milvus/configs/*.yaml /etc/milvus/configs/
  
  # Configure Milvus to use external etcd (more reliable in containerized environments).
  sudo perl -pi -e 's/^(\s+)embed:\s*true/\1embed: false/' /etc/milvus/configs/milvus.yaml
  
  # Enable local RPC for standalone mode.
  sudo perl -pi -e 's/^localRPCEnabled:\s*false/localRPCEnabled: true/' /etc/milvus/configs/milvus.yaml
  
  # Now install Milvus deb package with pre-configured settings.
  # Use noninteractive + keep existing config (the one we just staged) to avoid dpkg prompt.
  sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" -y install ./milvus_2.6.4-1_${ARCH}.deb
  rm milvus_2.6.4-1_${ARCH}.deb
  sudo rm -rf /tmp/milvus_extract
  
  # Create Milvus data directory.
  sudo mkdir -p /var/lib/milvus
  # Copy Supervisor config for Milvus.
  sudo mkdir -p /etc/supervisor/conf.d
  if [ -f "$APP_ROOT/.devpanel/milvus/milvus.conf" ]; then
    sudo cp "$APP_ROOT/.devpanel/milvus/milvus.conf" /etc/supervisor/conf.d/milvus.conf
  fi
  # Start Milvus directly after install. (Supervisor will manage Milvus on next container restart.)
  # Use run_as_root to ensure shell redirections run with root privileges.
  run_as_root "cd / && setsid bash -c 'MILVUSCONF=/etc/milvus/configs/ /usr/bin/milvus run standalone' </dev/null >/var/log/milvus.out.log 2>/var/log/milvus.err.log &"
  # Wait for Milvus to be ready.
  echo "Waiting for Milvus to be ready..."
  for i in {1..60}; do
    if curl -s http://127.0.0.1:9091/healthz | grep -q '^OK$'; then
      echo "Milvus is ready."
      break
    fi
    sleep 1
  done
  if ! curl -s http://127.0.0.1:9091/healthz | grep -q '^OK$'; then
    echo "ERROR: Milvus did not become ready in time." >&2
    exit 1
  fi
fi
if ! getent hosts | grep -q milvus && curl -s http://127.0.0.1:9091/healthz | grep -q '^OK$'; then
  sed '/localhost/ s/$/ milvus/' /etc/hosts | sudo tee /etc/hosts || :
fi

# Enable AVIF support in GD extension if not already enabled.
if [ -z "$(php --ri gd | grep AVIF)" ]; then
  sudo apt-get install -y libavif-dev
  sudo docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp
  sudo docker-php-ext-install gd
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
