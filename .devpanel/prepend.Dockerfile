ARG BASE_IMAGE=devpanel/php:8.4-base-rc

FROM zilliz/attu:v2.3.10 AS attu
FROM quay.io/coreos/etcd:v3.5.5 AS etcd
FROM milvusdb/milvus:v2.4.1 AS milvus
FROM rustfs/rustfs:1.0.4 AS rustfs
