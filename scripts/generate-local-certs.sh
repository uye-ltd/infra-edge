#!/usr/bin/env bash
# generate-local-certs.sh — generate the local TLS certificate.
#
# Output: ./certs/local/{cert,key,ca}.pem
#   cert.pem / key.pem — server certificate for every local hostname
#   ca.pem             — CA that signed cert.pem; used as ssl_trusted_certificate
#                        and as the CA bundle for clients (curl --cacert, hurl)
#
# Uses mkcert when installed (cert is trusted by the system/browsers after
# `mkcert -install`); otherwise falls back to a self-signed openssl cert
# (ca.pem = the cert itself; browsers will warn).
#
# Usage: scripts/generate-local-certs.sh [--force]
set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/certs/local"
# Every hostname served locally — add new local sites here.
HOSTS="localhost demo.localhost 127.0.0.1 ::1"

if [ -f "$CERT_DIR/cert.pem" ] && [ "${1:-}" != "--force" ]; then
    echo "$CERT_DIR/cert.pem already exists — leaving it untouched (use --force to regenerate)."
    exit 0
fi

mkdir -p "$CERT_DIR"

if command -v mkcert > /dev/null; then
    echo "Generating mkcert certificate in $CERT_DIR ..."
    # shellcheck disable=SC2086 # word splitting of HOSTS is intended
    mkcert -cert-file "$CERT_DIR/cert.pem" -key-file "$CERT_DIR/key.pem" $HOSTS
    cp "$(mkcert -CAROOT)/rootCA.pem" "$CERT_DIR/ca.pem"
    echo "Run 'mkcert -install' once if the local CA is not trusted yet."
else
    echo "mkcert not found — falling back to a self-signed openssl certificate."
    echo "For browser-trusted local certs: brew install mkcert && mkcert -install && make certs-force"
    san=""
    for h in $HOSTS; do
        case "$h" in
            *[!0-9.:a-f]*) san="${san:+$san,}DNS:$h" ;;
            *)             san="${san:+$san,}IP:$h" ;;
        esac
    done
    openssl req -x509 \
        -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out    "$CERT_DIR/cert.pem" \
        -sha256 \
        -days   365 \
        -nodes \
        -subj "/O=uye-edge-local/CN=localhost" \
        -addext "subjectAltName=$san" 2> /dev/null
    cp "$CERT_DIR/cert.pem" "$CERT_DIR/ca.pem"
fi

echo "Done: $CERT_DIR/{cert,key,ca}.pem"
