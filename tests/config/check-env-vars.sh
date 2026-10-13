#!/usr/bin/env bash
# check-env-vars.sh — keep .env.example in sync with what the repo references.
#
# Fails when:
#   - a ${VAR} used in nginx/templates/** is missing from .env.example
#     (it would render as an empty string and break `nginx -t` for every site);
#   - a variable in .env.example is referenced nowhere (templates or compose files).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

defined=$(grep -oE '^[A-Z_][A-Z0-9_]*=' .env.example | tr -d '=' | sort -u)
# shellcheck disable=SC2016 # literal ${...} patterns, not expansions
in_templates=$(grep -rhoE '\$\{[A-Z_][A-Z0-9_]*\}' nginx/templates | tr -d '${}' | sort -u)
# shellcheck disable=SC2016
in_compose=$(grep -hoE '\$\{[A-Z_][A-Z0-9_]*' docker-compose*.yml | tr -d '${' | sort -u)

status=0

missing=$(comm -23 <(echo "$in_templates") <(echo "$defined"))
if [ -n "$missing" ]; then
    echo "error: used in nginx/templates but missing from .env.example:" >&2
    while read -r v; do echo "  $v"; done <<< "$missing" >&2
    status=1
fi

unused=$(comm -23 <(echo "$defined") <(sort -u <(echo "$in_templates") <(echo "$in_compose")))
if [ -n "$unused" ]; then
    echo "error: defined in .env.example but referenced nowhere:" >&2
    while read -r v; do echo "  $v"; done <<< "$unused" >&2
    status=1
fi

[ "$status" -eq 0 ] && echo "env vars: OK ($(echo "$defined" | wc -l | tr -d ' ') variables)"
exit "$status"
