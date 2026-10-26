USER root

ARG DEBIAN_FRONTEND=noninteractive

# Install the packages previously supplied by the custom build action.
RUN apt-get update -qq && \
    apt-get install -y -qq jq nano npm ripgrep supervisor python3-pip curl \
        libaio1t64 libopenblas0 libgomp1 yarnpkg && \
    pip3 install supervisord-dependent-startup --break-system-packages && \
    pecl update-channels && \
    printf '' | pecl install apcu && \
    echo 'extension=apcu.so' > /usr/local/etc/php/conf.d/apcu.ini && \
    pecl install uploadprogress && \
    echo 'extension=uploadprogress.so' > /usr/local/etc/php/conf.d/uploadprogress.ini && \
    LIBAIO_LIBDIR=$(dpkg-architecture -q DEB_HOST_MULTIARCH) && \
    ln -s /usr/lib/$LIBAIO_LIBDIR/libaio.so.1t64 /usr/lib/$LIBAIO_LIBDIR/libaio.so.1 && \
    ln -sf /usr/bin/yarnpkg /usr/bin/yarn && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=attu /app /app
COPY --from=attu /usr/local/bin/node /usr/local/bin/node
COPY --from=attu /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=etcd /usr/local/bin/etcd /usr/local/bin/etcd
COPY --from=etcd /usr/local/bin/etcdctl /usr/local/bin/etcdctl
COPY --from=milvus /milvus /milvus
COPY --from=rustfs /usr/bin/rustfs /usr/local/bin/rustfs

RUN echo "/milvus/lib" > /etc/ld.so.conf.d/milvus.conf && \
    ldconfig && chmod +x /milvus/bin/milvus

COPY .ddev/apache/attu-proxy.conf /etc/apache2/conf-available/attu-proxy.conf
RUN a2enmod proxy proxy_http proxy_wstunnel headers substitute && a2enconf attu-proxy

# Share service definitions with DDEV, adapting its environment to DevPanel.
COPY .ddev/web-build/supervisor/*.conf /etc/supervisor/conf.d/
RUN sed -i \
        -e 's/ENV_DDEV_USER/ENV_APACHE_RUN_USER/g' \
        -e 's/%(ENV_DDEV_SITENAME)s.ddev.site/%(ENV_DP_HOSTNAME)s/g' \
        /etc/supervisor/conf.d/*.conf && \
    mkdir -p /var/log/supervisor && \
    (grep -q '^Mutex ' /templates/apache2.conf || echo 'Mutex file:/var/run/apache2' >> /templates/apache2.conf) && \
    (grep -q '^ServerName ' /templates/apache2.conf || echo 'ServerName localhost' >> /templates/apache2.conf) && \
    sed -i 's|/bin/bash source ~/.bashrc|source ~/.bashrc|' /scripts/apache-start.sh

RUN cd /app && yarn install && \
    chown -R $APACHE_RUN_USER:$APACHE_RUN_GROUP build && \
    ln -sf "$APP_ROOT/.devpanel/milvus/volumes/etcd" /etcd && \
    ln -sf "$APP_ROOT/.devpanel/milvus/volumes/milvus" /var/lib/milvus

USER ${USER}
