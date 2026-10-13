#!/usr/bin/env bash
# compose-config.sh — validate the compose files (production and production+local).
# --no-env-resolution: env_file contents are not needed (.env / .env.local are
# not tracked); --env-file .env.example feeds ${VAR} interpolation.
set -euo pipefail

cd "$(dirname "$0")/../.."

docker compose --env-file .env.example -f docker-compose.yml \
    config --no-env-resolution -q
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.local.yml \
    config --no-env-resolution -q

echo "compose config: OK"
