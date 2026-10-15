#!/usr/bin/env bash
# compose-config.sh — validate the compose files (production and production+local).
# --env-file feeds ${VAR} interpolation. A temporary final overlay points the
# nginx service's env_file at the tracked example: Compose still checks that
# env_file exists even with --no-env-resolution, while .env/.env.local are not
# present in a fresh CI checkout.
set -euo pipefail

cd "$(dirname "$0")/../.."

env_override=$(mktemp)
trap 'rm -f "$env_override"' EXIT
cat > "$env_override" <<'YAML'
services:
  nginx:
    env_file: !override
      - .env.example
YAML

docker compose --env-file .env.example -f docker-compose.yml -f "$env_override" \
    config --no-env-resolution -q
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.production.yml -f "$env_override" \
    config --no-env-resolution -q
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.local.yml -f "$env_override" \
    config --no-env-resolution -q

echo "compose config: OK"
