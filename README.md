# openresty-hardened

[OpenResty](https://openresty.org/) container images built for locked-down environments:

- **no shell, no package manager**: distroless static base plus only nginx, LuaJIT,
  the OpenResty Lua libraries and exactly the shared libraries they load;
- **non-root**: runs as `65532:65532`, listens on `8080`;
- **read-only root filesystem**: nginx writes only to `/tmp` (pid, temp files), logs go
  to stdout/stderr;
- **small**: ~7 MB compressed, ~27 MB unpacked (the official Alpine image: ~64 MB / ~250 MB);
- multi-arch (`linux/amd64`, `linux/arm64`), base images pinned by digest, SBOM and
  provenance attestations, signed with cosign.

The binaries are those of the official image `openresty/openresty:<version>-alpine`
(the same nginx, OpenSSL, PCRE2 and LuaJIT builds), copied and stripped. Nothing is
patched.

## Variants and tags

| Image | Contents |
|---|---|
| `ghcr.io/olegbuevich/openresty-hardened:<tag>` | OpenResty |
| `ghcr.io/olegbuevich/openresty-hardened:<tag>-geoip2` | OpenResty + [ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module) (http and stream), libmaxminddb. No database is included. |

| Tag | Meaning |
|---|---|
| `1.31.9.1-1` | OpenResty 1.31.9.1, image revision 1 (immutable) |
| `1.31.9.1` | latest image revision of OpenResty 1.31.9.1 |
| `latest` | latest release |
| `edge` | the main branch |

Pin by digest in production: `ghcr.io/olegbuevich/openresty-hardened:1.31.9.1-1@sha256:...`.

## Usage

```sh
docker run --rm --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
  -p 8080:8080 ghcr.io/olegbuevich/openresty-hardened:latest
```

`/tmp` must be writable: a tmpfs (Docker) or an `emptyDir` (Kubernetes).

Kubernetes:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: openresty
      image: ghcr.io/olegbuevich/openresty-hardened:1.31.9.1-1
      ports: [{containerPort: 8080}]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: [ALL]}
      volumeMounts:
        - {name: tmp, mountPath: /tmp}
        - {name: conf, mountPath: /etc/nginx/conf.d, readOnly: true}
  volumes:
    - name: tmp
      emptyDir: {medium: Memory, sizeLimit: 64Mi}
    - name: conf
      configMap: {name: openresty-conf}
```

## Configuration

The layout follows the official image:

| Path | |
|---|---|
| `/usr/local/openresty/nginx/conf/nginx.conf` | main configuration ([conf/nginx.conf](conf/nginx.conf)) |
| `/etc/nginx/conf.d/*.conf` | included in `http {}`; `default.conf` is a sample server on 8080 |
| `/etc/nginx/conf.d/*.main` | included in the main context |
| `/etc/nginx/modules/*.conf` | `load_module` lines of the variant (geoip2: `geoip2.conf`) |
| `/usr/local/openresty/lualib` | OpenResty Lua libraries (`lua_package_path` default) |

The entrypoint is `nginx -p /tmp/ -e stderr -g "daemon off;"` with the command
`-c /usr/local/openresty/nginx/conf/nginx.conf`. To use your own main configuration,
mount it and pass `-c /path/nginx.conf`. It must not set `daemon`, and it should keep
everything nginx writes under `/tmp`: `pid /tmp/nginx.pid;` and the `*_temp_path`
directives (see [conf/nginx.conf](conf/nginx.conf)). Relative paths resolve against
`/tmp/` (the prefix) or the directory of the configuration file (includes).

GeoIP2 (variant `geoip2`), with your own database:

```nginx
geoip2 /etc/geoip/GeoLite2-Country.mmdb {
    $geoip2_country_code source=$remote_addr country iso_code;
}
```

## Differences from the official image

- No shell, `apk`, `resty`/`opm`/`restydoc` CLIs, Perl, headers or static libraries.
  Debug with an ephemeral container: `kubectl debug -it <pod> --image=busybox --target=openresty`.
- Not included: the dynamic modules `image_filter`, `xslt` and the legacy `geoip` (and
  their X11/gd/libxml2/libxslt dependencies). Everything compiled into nginx is the same.
- Listens on 8080 instead of 80; `server_tokens off`; access log to stdout, error log to
  stderr.
- `openresty` is available as `/usr/local/openresty/bin/openresty` (a symlink to nginx).

## Verification

```sh
cosign verify ghcr.io/olegbuevich/openresty-hardened:latest \
  --certificate-identity-regexp '^https://github.com/olegbuevich/openresty-hardened/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
docker buildx imagetools inspect ghcr.io/olegbuevich/openresty-hardened:latest --format '{{json .SBOM}}'
```

Vulnerability scanners see the Debian packages of the distroless base. The OpenResty,
OpenSSL, PCRE2 and Alpine libraries are copied files that scanners do not detect; their
versions are listed in `/usr/share/licenses/openresty-hardened/VERSIONS`. Releases follow
the official image, which tracks OpenSSL and PCRE2 security releases.

## Building and testing

```sh
make test    # builds both variants, runs test/smoke.sh (read-only, non-root, no capabilities)
make scan    # trivy, HIGH and CRITICAL
```

[test/smoke.sh](test/smoke.sh) checks: image user, no shell, serving with a read-only
root filesystem and no capabilities, Lua + cjson + PCRE2 JIT, TLS, GeoIP2 lookups
(MaxMind test database), the user of all processes, a clean shutdown.

Releasing: Dependabot updates the base image digests and the actions. For a new OpenResty
version, also update `OPENRESTY_SHA256` in the [Dockerfile](Dockerfile), then tag
`v<openresty version>-<revision>` (e.g. `v1.31.9.1-1`); CI checks that the tag matches.

## License

The build files are under the [BSD-2-Clause](LICENSE) license. The images contain
third-party software under its own licenses, see [THIRD_PARTY.md](THIRD_PARTY.md).
OpenResty is a registered trademark of OpenResty Inc.; this project is not affiliated
with OpenResty Inc.
