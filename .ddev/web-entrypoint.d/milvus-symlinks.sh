#!/bin/bash
# Ensure Milvus, Minio, and Etcd volume directories exist and create symlinks
mkdir -p /var/www/html/.devpanel/milvus/volumes/milvus \
         /var/www/html/.devpanel/milvus/volumes/minio \
         /var/www/html/.devpanel/milvus/volumes/etcd
ln -sf /var/www/html/.devpanel/milvus/volumes/milvus /var/lib/milvus
ln -sf /var/www/html/.devpanel/milvus/volumes/minio /minio_data
ln -sf /var/www/html/.devpanel/milvus/volumes/etcd /etcd
