#!/usr/bin/env bash
# generate-self-signed.sh — generate a self-signed TLS cert for local development.
# Output: ./certs/local/{cert,key,ca}.pem (ca.pem = the cert itself, used as
# ssl_trusted_certificate and as the CA bundle for clients).
set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/certs/local"
mkdir -p "$CERT_DIR"

echo "Generating self-signed certificate in $CERT_DIR ..."

openssl req -x509 \
    -newkey rsa:4096 \
    -keyout "$CERT_DIR/key.pem" \
    -out    "$CERT_DIR/cert.pem" \
    -sha256 \
    -days   365 \
    -nodes \
    -subj "/O=uye-edge-local/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

cp "$CERT_DIR/cert.pem" "$CERT_DIR/ca.pem"

echo "Done."
echo "  Certificate : $CERT_DIR/cert.pem"
echo "  Private key : $CERT_DIR/key.pem"
