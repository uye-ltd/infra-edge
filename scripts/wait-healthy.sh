#!/usr/bin/env bash
# wait-healthy.sh — wait until the nginx container reports healthy.
#
# Post-deploy hook for the infra-runner deployer (.infra-runner.plugin): runs inside
# the deployer container after `compose up` recreated nginx. Uses only `docker inspect`
# (EXEC is disabled in the deployer's socket proxy). Exit 1 marks the deployer unhealthy.
set -euo pipefail

CONTAINER="${WAIT_HEALTHY_CONTAINER:-uye-edge}"
TIMEOUT="${WAIT_HEALTHY_TIMEOUT:-120}"
INTERVAL=3

state=""
deadline=$(( SECONDS + TIMEOUT ))
while (( SECONDS < deadline )); do
    if ! state=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$CONTAINER" 2>/dev/null); then
        state="missing"
    fi
    if [ "$state" = "running healthy" ]; then
        echo "$CONTAINER is healthy"
        exit 0
    fi
    sleep "$INTERVAL"
done

echo "$CONTAINER not healthy after ${TIMEOUT}s (status/health: $state)" >&2
docker inspect -f '{{if .State.Health}}{{range .State.Health.Log}}{{.Output}}{{end}}{{end}}' \
    "$CONTAINER" 2>/dev/null | tail -n 5 >&2 || true
exit 1
