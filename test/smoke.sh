#!/usr/bin/env bash
# Smoke test of an image, run the way a hardened Kubernetes pod runs it: read-only root
# filesystem with a tmpfs on /tmp, image user (non-root), all capabilities dropped,
# no-new-privileges.
#
#   test/smoke.sh IMAGE [default|geoip2]
set -euo pipefail
IMAGE=$1
VARIANT=${2:-default}
cd "$(dirname "$0")"
MAXMIND_DB_COMMIT=5c972a8a85df5557c122f79d6e172c7a5cfe93c5
work=$(mktemp -d)
name=smoke-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
fail() { echo "FAIL: $*"; docker logs "$name" 2>&1 | tail -20 || true; exit 1; }
pass() { echo "PASS: $*"; }

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=smoke \
  -keyout "$work/tls.key" -out "$work/tls.crt" 2>/dev/null
chmod 0644 "$work/tls.key"
cp smoke.conf "$work/"
mounts=(-v "$work/tls.crt:/test/tls.crt:ro" -v "$work/tls.key:/test/tls.key:ro"
  -v "$work/smoke.conf:/etc/nginx/conf.d/smoke.conf:ro")
ports=(-p 127.0.0.1::8080 -p 127.0.0.1::8081 -p 127.0.0.1::8443)
if [[ $VARIANT == geoip2 ]]; then
  curl -sfL -o "$work/GeoIP2-Country-Test.mmdb" \
    "https://raw.githubusercontent.com/maxmind/MaxMind-DB/$MAXMIND_DB_COMMIT/test-data/GeoIP2-Country-Test.mmdb"
  cp smoke-geoip2.conf "$work/"
  mounts+=(-v "$work/GeoIP2-Country-Test.mmdb:/test/GeoIP2-Country-Test.mmdb:ro"
    -v "$work/smoke-geoip2.conf:/etc/nginx/conf.d/smoke-geoip2.conf:ro")
  ports+=(-p 127.0.0.1::8082)
fi

[[ $(docker image inspect -f '{{.Config.User}}' "$IMAGE") == 65532:65532 ]] || fail "image user is not 65532:65532"
pass "image user 65532:65532"
for sh in /bin/sh /bin/bash /bin/busybox /sbin/apk; do
  if docker run --rm --entrypoint "$sh" "$IMAGE" -c true >/dev/null 2>&1; then fail "$sh exists"; fi
done
pass "no shell, busybox or apk"

docker run -d --name "$name" --read-only --tmpfs /tmp:rw,mode=1777 --cap-drop ALL \
  --security-opt no-new-privileges "${mounts[@]}" "${ports[@]}" "$IMAGE" >/dev/null
port() { docker port "$name" "$1" | head -1 | sed 's/.*://'; }
for _ in $(seq 50); do
  curl -sf "http://127.0.0.1:$(port 8080)/" >/dev/null 2>&1 && break
  sleep 0.2
done

page=$(curl -sf "http://127.0.0.1:$(port 8080)/") || fail "default page"
[[ $page == *OpenResty* ]] || fail "default page content"
pass "default page on 8080 (read-only, non-root, no capabilities)"
[[ $(curl -sI "http://127.0.0.1:$(port 8080)/" | tr -d '\r' | grep -i '^server:') == "Server: openresty" ]] ||
  fail "server_tokens off"
pass "server_tokens off"
out=$(curl -sf "http://127.0.0.1:$(port 8081)/lua") || fail "lua"
[[ $out == *'"ok":true'* && $out == *'"re":"123"'* ]] || fail "lua: $out"
pass "Lua, cjson, ngx.re (PCRE2 JIT): $out"
out=$(curl -skf "https://127.0.0.1:$(port 8443)/lua") || fail "tls"
[[ $out == *'"ssl":"on"'* ]] || fail "tls: $out"
pass "TLS (OpenSSL)"
if [[ $VARIANT == geoip2 ]]; then
  out=$(curl -sf "http://127.0.0.1:$(port 8082)/country?ip=2.125.160.216") || fail "geoip2"
  [[ $out == GB ]] || fail "geoip2: want GB, got '$out'"
  pass "geoip2: 2.125.160.216 -> $out"
fi
users=$(docker top "$name" -o pid,user | awk 'NR > 1 {print $2}' | sort -u | tr '\n' ' ')
[[ $users == "65532 " ]] || fail "container processes run as: $users"
pass "all processes run as 65532"
docker stop "$name" >/dev/null
logs=$(docker logs "$name" 2>&1)
if grep -E '\[(emerg|alert|crit)\]' <<<"$logs"; then fail "errors in the log"; fi
pass "clean shutdown, no emerg/alert/crit in the log"
