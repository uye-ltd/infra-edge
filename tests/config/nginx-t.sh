#!/usr/bin/env bash
# nginx-t.sh — render every template with each env file and validate the result.
#
# For .env.example (production shape) and a freshly generated local env:
#   1. run the image's envsubst step with that env;
#   2. `nginx -t` — expected "ssl_stapling ignored" warnings are filtered (dummy certs are mounted at the paths from the env file, the
#      upstream hosts are pointed at 127.0.0.1 so they resolve);
#   3. run gixy (static security analysis) on the rendered config.
#
# Needs only Docker. Usage: tests/config/nginx-t.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Accepted gixy findings — every skip needs a reason:
#   resolver_external     resolver 1.1.1.1/8.8.8.8 is used only for OCSP
#                         stapling (see AGENTS.md, ssl-params.conf)
#   add_header_redefinition  named error locations (@rate_limited, …) add their
#                         own headers and intentionally drop security headers
#   hsts_header           reported for the :80 / :443 default servers, which
#                         never serve a site; sites get HSTS from
#                         snippets/security-headers.conf (checked by smoke tests)
GIXY_SKIPS=resolver_external,add_header_redefinition,hsts_header

IMAGE=uye-edge:test
GIXY_IMAGE=uye-edge-gixy:test
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> building $IMAGE and $GIXY_IMAGE"
docker build -q -t "$IMAGE" . > /dev/null
docker build -q -t "$GIXY_IMAGE" -f tests/config/gixy.Dockerfile tests/config > /dev/null

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=nginx-t" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2> /dev/null

LOCAL_ENV_FILE="$WORK/env.local" scripts/init-local-env.sh > /dev/null

env_value() { grep -E "^$2=" "$1" | tail -1 | cut -d= -f2-; }

check() {
    local name="$1" env_file="$2"; shift 2
    local out="$WORK/rendered-$name"
    mkdir -p "$out"
    echo "==> [$name] nginx -t"

    local upstream_host
    upstream_host=$(env_value "$env_file" NGINX_UPSTREAM_HOST)
    local -a host_args=()
    if [[ "$upstream_host" != 127.0.0.1 ]]; then
        host_args=(--add-host "$upstream_host:127.0.0.1")
    fi

    docker run --rm --env-file "$env_file" \
        "${host_args[@]}" \
        -v "$WORK/cert.pem:$(env_value "$env_file" NGINX_SSL_CERT_PATH):ro" \
        -v "$WORK/key.pem:$(env_value "$env_file" NGINX_SSL_KEY_PATH):ro" \
        -v "$WORK/cert.pem:$(env_value "$env_file" NGINX_SSL_CHAIN_PATH):ro" \
        "$@" \
        --entrypoint sh "$IMAGE" -c '
            /docker-entrypoint.d/20-envsubst-on-templates.sh > /dev/null &&
            { out=$(nginx -t -q 2>&1) || { echo "$out" >&2; exit 1; }; } &&
            { echo "$out" | grep -v "ssl_stapling\" ignored" >&2 || true; } &&
            tar -C /etc/nginx -cf - .' | tar -C "$out" -xf -

    echo "==> [$name] gixy"
    docker run --rm -v "$out:/etc/nginx:ro" "$GIXY_IMAGE" --skips "$GIXY_SKIPS" /etc/nginx/nginx.conf
}

check production .env.example
check local "$WORK/env.local" \
    --add-host demo-stub:127.0.0.1 \
    -v "$ROOT/local/sites:/etc/nginx/local-sites:ro"

echo "nginx config: OK"
