# Third-party components

The LICENSE of this repository covers the build files (Dockerfile, scripts,
configuration). The images contain the following software, each under its own license.
The license texts are in [licenses/](licenses) and, inside every image, in
`/usr/share/licenses/openresty-hardened/` together with `VERSIONS` (the exact versions
and the list of shared libraries of that image).

| Component | Variant | License | Taken from | Source |
|---|---|---|---|---|
| OpenResty (nginx core, LuaJIT, ngx_lua, lua-resty-* and the other bundled modules) | both | BSD-2-Clause (OpenResty, nginx), MIT (LuaJIT, lua-cjson); see `openresty.txt`, `nginx.txt`, `luajit.txt` | official image `openresty/openresty:<version>-alpine` | https://openresty.org/en/download.html |
| OpenSSL 3 | both | Apache-2.0 (`openssl.txt`) | official image (built by docker-openresty) | https://github.com/openssl/openssl |
| PCRE2 | both | BSD-3-Clause WITH PCRE2-exception (`pcre2.txt`) | official image (built by docker-openresty) | https://github.com/PCRE2Project/pcre2 |
| musl libc | both | MIT (`musl.txt`) | Alpine package `musl` | https://musl.libc.org/, Alpine aports `main/musl` |
| zlib | both | Zlib (`zlib.txt`) | Alpine package `zlib` | https://zlib.net/, Alpine aports `main/zlib` |
| libgcc_s (GCC runtime) | both | GPL-3.0-or-later WITH GCC-exception-3.1 (`gcc-COPYING3.txt`, `gcc-COPYING.RUNTIME.txt`) | Alpine package `libgcc`, unmodified | https://gcc.gnu.org/, Alpine aports `main/gcc` |
| ngx_http_geoip2_module | geoip2 | BSD-2-Clause (`ngx_http_geoip2_module.txt`) | built from the release tarball | https://github.com/leev/ngx_http_geoip2_module |
| libmaxminddb | geoip2 | Apache-2.0 (`libmaxminddb.txt`, `libmaxminddb-NOTICE.txt`) | Alpine package `libmaxminddb` | https://github.com/maxmind/libmaxminddb |
| distroless static base (Debian 12: base-files, netbase, tzdata, ca-certificates) | both | per package, see `/usr/share/doc/*/copyright` in the image | `gcr.io/distroless/static-debian12:nonroot` | https://github.com/GoogleContainerTools/distroless |

Alpine package sources are at https://gitlab.alpinelinux.org/alpine/aports (branch of
the Alpine release of the official OpenResty image, version in `VERSIONS`); Alpine keeps
the source archives of its packages. libgcc_s is the only GPL component; it is shipped
unmodified, and its source is available there and from https://gcc.gnu.org/.

No GeoIP database is included: MaxMind GeoLite2/GeoIP2 databases may not be
redistributed under their EULA. Mount your own `.mmdb` file.

OpenResty is a registered trademark of OpenResty Inc. This project is not affiliated with
or endorsed by OpenResty Inc., F5/NGINX or MaxMind.
