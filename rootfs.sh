#!/bin/sh
# Builds /rootfs inside the official OpenResty image: nginx, the Lua libraries, the given
# variant's modules and exactly the shared libraries they load (ldd), stripped; the
# configuration from /conf and the license texts from /licenses.
#
#   rootfs.sh [geoip2]
set -eu
variant=${1:-default}
R=/usr/local/openresty

bins="$R/nginx/sbin/nginx $(find $R/lualib -name '*.so')"
if [ "$variant" = geoip2 ]; then
    bins="$bins $R/nginx/modules/ngx_http_geoip2_module.so $R/nginx/modules/ngx_stream_geoip2_module.so"
fi
# (ldd reports the lua_* symbols of the Lua C modules as missing: nginx provides them)
libs=$(for f in $bins; do ldd "$f" 2>/dev/null || true; done | awk '/=>/ {print $3} /ld-musl/ {print $1}' | sort -u)

mkdir /rootfs
# shellcheck disable=SC2086 # $bins and $libs are word lists
# -h: copy the files behind the library symlinks (libfoo.so.1 -> libfoo.so.1.2.3)
tar -chf - $bins $libs $R/lualib $R/luajit/share/lua $R/luajit/share/luajit-* \
    $R/nginx/html $R/nginx/conf/mime.types $R/nginx/conf/fastcgi.conf $R/nginx/conf/fastcgi_params \
    $R/nginx/conf/scgi_params $R/nginx/conf/uwsgi_params $R/nginx/conf/koi-utf $R/nginx/conf/koi-win \
    $R/nginx/conf/win-utf | tar -xf - -C /rootfs
find /rootfs -type f \( -name '*.so*' -o -path '*/sbin/nginx' \) ! -name 'ld-musl*' -exec strip --strip-unneeded {} +

# the official image's command name
mkdir -p /rootfs$R/bin
ln -s ../nginx/sbin/nginx /rootfs$R/bin/openresty

# configuration
cp /conf/nginx.conf /rootfs$R/nginx/conf/nginx.conf
mkdir -p /rootfs/etc/nginx/conf.d /rootfs/etc/nginx/modules
cp /conf/conf.d/default.conf /rootfs/etc/nginx/conf.d/
if [ "$variant" = geoip2 ]; then cp /conf/modules/geoip2.conf /rootfs/etc/nginx/modules/; fi

# licenses and the versions of the components in this image
L=/rootfs/usr/share/licenses/openresty-hardened
mkdir -p $L
cp /licenses/*.txt $L/
[ "$variant" = geoip2 ] || rm $L/ngx_http_geoip2_module.txt $L/libmaxminddb*.txt
cp /usr/local/openresty/pcre2/share/doc/pcre2/LICENCE.md $L/pcre2.txt
{
    echo "variant: $variant"
    echo "openresty: $(nginx -v 2>&1 | sed -n 's|.*openresty/||p')"
    nginx -V 2>&1 | sed -n 's/^built with //p'
    echo "pcre2: $(awk '/define PCRE2_MAJOR/ {a=$3} /define PCRE2_MINOR/ {b=$3} END {print a "." b}' $R/pcre2/include/pcre2.h)"
    echo "alpine packages (source: https://gitlab.alpinelinux.org/alpine/aports):"
    apk info -v 2>/dev/null | grep -E '^(musl|libgcc|zlib|libmaxminddb)-[0-9]' | sed 's/^/  /'
    echo "files:"
    (cd /rootfs && find . -type f -name '*.so*' | sort | sed 's|^\.|  |')
} > $L/VERSIONS

# owned by root, read-only for everybody; /tmp is the only writable directory
chown -R 0:0 /rootfs
chmod -R a-w,a+rX /rootfs
mkdir -p /rootfs/tmp && chmod 1777 /rootfs/tmp
