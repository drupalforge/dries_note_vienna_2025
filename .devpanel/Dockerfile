USER root

ARG DEBIAN_FRONTEND=noninteractive
ARG DP_HOSTNAME=localhost
ARG CODES_ENABLE=no

RUN apt-get update -qq && \
    apt-get install -y -qq jq nano npm ripgrep supervisor python3-pip curl \
      libaio1t64 libopenblas0 libgomp1 yarnpkg && \
    pecl update-channels && \
    printf '' | pecl install apcu && \
    echo 'extension=apcu.so' > /usr/local/etc/php/conf.d/apcu.ini && \
    pecl install uploadprogress && \
    echo 'extension=uploadprogress.so' > /usr/local/etc/php/conf.d/uploadprogress.ini && \
    pip3 install supervisord-dependent-startup --break-system-packages && \
    LIBAIO_LIBDIR=$(dpkg-architecture -q DEB_HOST_MULTIARCH) && \
    ln -s /usr/lib/$LIBAIO_LIBDIR/libaio.so.1t64 /usr/lib/$LIBAIO_LIBDIR/libaio.so.1 && \
    ln -sf /usr/bin/yarnpkg /usr/bin/yarn && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=attu /app /app
COPY --from=etcd /usr/local/bin/etcd /usr/local/bin/etcd
COPY --from=etcd /usr/local/bin/etcdctl /usr/local/bin/etcdctl
COPY --from=milvus /milvus /milvus
COPY --from=rustfs /usr/bin/rustfs /usr/bin/rustfs
RUN echo "/milvus/lib" > /etc/ld.so.conf.d/milvus.conf && ldconfig && \
    chmod +x /milvus/bin/milvus

COPY .ddev/apache/attu-proxy.conf /etc/apache2/conf-available/attu-proxy.conf
COPY .ddev/web-build/supervisor/*.conf /etc/supervisor/conf.d/

RUN a2enmod proxy proxy_http proxy_wstunnel headers substitute && \
    a2enconf attu-proxy && \
    { grep -q '^Mutex ' /templates/apache2.conf || echo 'Mutex file:/var/run/apache2' >> /templates/apache2.conf; } && \
    { grep -q '^ServerName ' /templates/apache2.conf || echo 'ServerName localhost' >> /templates/apache2.conf; }

RUN sed -i 's|/bin/bash source ~/.bashrc|source ~/.bashrc|' /scripts/apache-start.sh && \
    cd /app && yarn install && \
    chown -R "${APACHE_RUN_USER}:${APACHE_RUN_GROUP}" build && \
    ln -sf "$APP_ROOT/.devpanel/milvus/volumes/etcd" /etcd && \
    ln -sf "$APP_ROOT/.devpanel/milvus/volumes/milvus" /var/lib/milvus && \
    mkdir -p /var/log/supervisor

ENV APP_ROOT=${APP_ROOT} \
    APACHE_RUN_USER=${APACHE_RUN_USER} \
    APACHE_RUN_GROUP=${APACHE_RUN_GROUP} \
    DDEV_USER=${APACHE_RUN_USER} \
    DDEV_SITENAME=localhost \
    DP_HOSTNAME=${DP_HOSTNAME} \
    CODES_ENABLE=${CODES_ENABLE} \
    WEB_ROOT=${WEB_ROOT}

USER ${USER}
