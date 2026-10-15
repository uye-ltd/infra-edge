#!/usr/bin/env bash
# certbot-renew.sh — renew Let's Encrypt certificates and reload nginx.
#
# Intended to be run as a cron job on the host or inside a scheduled container:
#   0 3 * * * /home/ghrunner/infra-edge/scripts/certbot-renew.sh >> /home/ghrunner/certbot-renew.log 2>&1
set -euo pipefail

EDGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting certificate renewal ..."

# .env selects the production host-network overlay, but certbot itself needs
# neither host networking nor free HTTP ports.
cd "$EDGE_DIR"
docker compose \
    --profile certbot \
    run --rm --no-deps certbot renew --quiet

# Reload nginx config so it picks up the refreshed certificates
if [ "$(docker inspect --format '{{.State.Running}}' uye-edge 2>/dev/null || true)" = true ]; then
    docker kill --signal HUP uye-edge >/dev/null
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Certificate renewal complete."
