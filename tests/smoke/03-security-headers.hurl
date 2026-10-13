# snippets/security-headers.conf must reach clients on every site.
GET https://localhost/api/headers
HTTP 200
[Asserts]
header "Strict-Transport-Security" == "max-age=63072000; includeSubDomains; preload"
header "X-Frame-Options" == "DENY"
header "X-Content-Type-Options" == "nosniff"
header "Referrer-Policy" == "strict-origin-when-cross-origin"
header "Permissions-Policy" exists
header "Content-Security-Policy" contains "frame-ancestors 'none'"
header "X-Request-ID" matches /^[0-9a-f]{32}$/
# server_tokens off; upstream Server / X-Powered-By are hidden
header "Server" == "nginx"
header "X-Powered-By" not exists

GET https://demo.localhost/
HTTP 200
[Asserts]
header "Strict-Transport-Security" exists
header "Content-Security-Policy" exists
header "X-Request-ID" matches /^[0-9a-f]{32}$/
