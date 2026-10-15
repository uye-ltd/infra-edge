#!/bin/sh
# run.sh — smoke tests against the running local stack.
# Runs inside the `smoke` container (docker-compose.local.yml, profile "test"),
# on the edge network: every local hostname is routed to the nginx service.
# Usage: make smoke
set -eu

cd "$(dirname "$0")"

CACERT=/certs/ca.pem
EDGE=nginx

echo "==> hurl"
# --jobs 1 + the (sorted) glob: files run in name order; zz-rate-limit.hurl
# must be last because it exhausts the /api/auth/ rate-limit bucket.
hurl --test --jobs 1 --cacert "$CACERT" \
    --connect-to "localhost:443:$EDGE:443" \
    --connect-to "localhost:80:$EDGE:80" \
    --connect-to "demo.localhost:443:$EDGE:443" \
    ./*.hurl

echo "==> migrated Caddy hosts: private sites reject non-VPN clients"
for host in filebrowser.uye.rocks vault.uye.rocks portainer.uye.rocks; do
    code=$(curl -ksS -o /dev/null -w '%{http_code}' \
        --connect-to "$host:443:$EDGE:443" \
        -H 'X-Forwarded-For: 10.0.0.2' "https://$host/")
    if [ "$code" != 403 ]; then
        echo "FAIL  $host accepted a non-VPN client (HTTP $code)" >&2
        exit 1
    fi
    echo "ok    $host rejects forged VPN address"
done

echo "==> unknown host is dropped (444: connection closed, no response)"
fail=0
expect_dropped() {
    desc="$1"; shift
    if code=$(curl -s -o /dev/null -w '%{http_code}' "$@"); then
        echo "FAIL  $desc: got HTTP $code" >&2
        fail=1
    elif [ "$code" != "000" ]; then
        echo "FAIL  $desc: got HTTP $code" >&2
        fail=1
    else
        echo "ok    $desc"
    fi
}
for proto in --http1.1 --http2; do
    expect_dropped "Host: unknown.localhost ($proto)" "$proto" --cacert "$CACERT" \
        --connect-to "localhost:443:$EDGE:443" -H "Host: unknown.localhost" https://localhost/
    expect_dropped "SNI unknown.localhost ($proto)" "$proto" --insecure \
        --connect-to "unknown.localhost:443:$EDGE:443" https://unknown.localhost/
done
expect_dropped "retired navidromed.uye.rocks" --insecure \
    --connect-to "navidromed.uye.rocks:443:$EDGE:443" https://navidromed.uye.rocks/

[ "$fail" -eq 0 ] && echo "smoke: OK"
exit "$fail"
