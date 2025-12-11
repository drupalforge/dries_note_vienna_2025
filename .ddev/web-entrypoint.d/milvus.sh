#!/bin/bash

# Ensure Milvus, Minio, and Etcd volume directories exist
mkdir -p "$APP_ROOT/.devpanel/milvus/volumes/milvus" \
         "$APP_ROOT/.devpanel/milvus/volumes/minio" \
         "$APP_ROOT/.devpanel/milvus/volumes/etcd"
chmod go-rwx "$APP_ROOT/.devpanel/milvus/volumes/etcd"

# Restore Milvus volumes from archive if present
if [ -f "$APP_ROOT/.devpanel/dumps/milvus.tgz" ]; then
  echo 'Restoring Milvus volumes from archive...'
  rm -rf "$APP_ROOT/.devpanel/milvus/volumes/*"
  tar xzf "$APP_ROOT/.devpanel/dumps/milvus.tgz" -C "$APP_ROOT/.devpanel/milvus/volumes"
  rm -f "$APP_ROOT/.devpanel/dumps/milvus.tgz"
fi
