# syntax=docker/dockerfile:1
#
# Hardened OpenResty: the binaries of the official OpenResty Alpine image (nginx, LuaJIT,
# OpenSSL, PCRE2) and exactly the shared libraries they load, stripped, on a distroless
# base: no shell, no package manager, non-root (65532), read-only root filesystem
# (nginx writes only to /tmp).
#
# Targets: default (plain OpenResty) and geoip2 (+ ngx_http_geoip2_module and
# ngx_stream_geoip2_module, loaded by /etc/nginx/modules/geoip2.conf).
#
# Base images are pinned by digest (Dependabot updates them). After an OpenResty update,
# set OPENRESTY_SHA256 to the checksum of the new source tarball.

ARG OPENRESTY_SHA256=71d49935bdc186dafc1f4b0a8ba44dba1bf4abc8ca52d4621f2039ec8fdcc95f
ARG GEOIP2_VERSION=3.4
ARG GEOIP2_SHA256=ad72fc23348d715a330994984531fab9b3606e160483236737f9a4a6957d9452

FROM openresty/openresty:1.31.9.1-alpine@sha256:40b124f4e477efb8c67ea997c3eef3a9b1619eef3aa3f5c394d14b68e42b564d AS openresty

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab AS distroless

# ngx_http_geoip2_module, built inside the official image against its own OpenSSL and
# PCRE2 with the same core configure options (`openresty -V`): a dynamic module must
# have the same signature as the nginx binary that loads it.
FROM openresty AS geoip2-module
ARG OPENRESTY_SHA256 GEOIP2_VERSION GEOIP2_SHA256
RUN apk add --no-cache build-base perl linux-headers libmaxminddb-dev zlib-dev \
      gd-dev libxslt-dev geoip-dev
WORKDIR /build
RUN set -eu; \
    v=$(openresty -v 2>&1 | sed -n 's|.*openresty/||p'); \
    wget -qO openresty.tgz "https://openresty.org/download/openresty-${v}.tar.gz"; \
    wget -qO geoip2.tgz "https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/${GEOIP2_VERSION}.tar.gz"; \
    printf '%s  %s\n' "$OPENRESTY_SHA256" openresty.tgz "$GEOIP2_SHA256" geoip2.tgz | sha256sum -c -; \
    tar xzf openresty.tgz; tar xzf geoip2.tgz; \
    cd openresty-${v}/bundle/nginx-*; \
    ./configure --with-compat --with-pcre --with-pcre-jit --with-threads --with-ipv6 \
      --with-cc-opt='-I/usr/local/openresty/pcre2/include -I/usr/local/openresty/openssl3/include' \
      --with-ld-opt='-L/usr/local/openresty/pcre2/lib -L/usr/local/openresty/openssl3/lib' \
      --without-mail_pop3_module --without-mail_imap_module --without-mail_smtp_module \
      --with-http_addition_module --with-http_auth_request_module --with-http_dav_module \
      --with-http_flv_module --with-http_geoip_module=dynamic --with-http_gunzip_module \
      --with-http_gzip_static_module --with-http_image_filter_module=dynamic --with-http_mp4_module \
      --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module \
      --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module \
      --with-http_sub_module --with-http_v2_module --with-http_v3_module --with-http_xslt_module=dynamic \
      --with-mail --with-mail_ssl_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module \
      --add-dynamic-module=/build/ngx_http_geoip2_module-${GEOIP2_VERSION} >/dev/null; \
    make modules >/dev/null; \
    mkdir /build/modules; cp objs/ngx_http_geoip2_module.so objs/ngx_stream_geoip2_module.so /build/modules/

# root filesystems: the files to copy onto the distroless base (see rootfs.sh)
FROM openresty AS rootfs-default
RUN apk add --no-cache binutils
COPY rootfs.sh /rootfs.sh
COPY conf/ /conf/
COPY licenses/ /licenses/
RUN /bin/sh /rootfs.sh

FROM openresty AS rootfs-geoip2
RUN apk add --no-cache binutils libmaxminddb
COPY --from=geoip2-module /build/modules/ /usr/local/openresty/nginx/modules/
COPY rootfs.sh /rootfs.sh
COPY conf/ /conf/
COPY licenses/ /licenses/
RUN /bin/sh /rootfs.sh geoip2

FROM distroless AS geoip2
COPY --from=rootfs-geoip2 /rootfs/ /
ENV PATH=/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:/usr/local/bin:/usr/bin:/bin
USER 65532:65532
EXPOSE 8080
STOPSIGNAL SIGQUIT
# -p /tmp/: the prefix (logs, temp files) is the only writable path; -e stderr: no
# error.log under the read-only install prefix before the configuration is read
ENTRYPOINT ["nginx", "-p", "/tmp/", "-e", "stderr", "-g", "daemon off;"]
CMD ["-c", "/usr/local/openresty/nginx/conf/nginx.conf"]

FROM distroless AS default
COPY --from=rootfs-default /rootfs/ /
ENV PATH=/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:/usr/local/bin:/usr/bin:/bin
USER 65532:65532
EXPOSE 8080
STOPSIGNAL SIGQUIT
ENTRYPOINT ["nginx", "-p", "/tmp/", "-e", "stderr", "-g", "daemon off;"]
CMD ["-c", "/usr/local/openresty/nginx/conf/nginx.conf"]
