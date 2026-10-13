# Runs last (see run.sh): exhausts the /api/auth/ bucket of this client IP.
# Local limits come from scripts/init-local-env.sh: auth 100r/m, burst 50 —
# 80 back-to-back requests are enough to trip it.
GET https://localhost/api/auth/flood
[Options]
repeat: 80
HTTP *

GET https://localhost/api/auth/flood
HTTP 429
[Asserts]
header "Retry-After" == "60"
header "Content-Type" == "application/json"
jsonpath "$.error" == "too_many_requests"
