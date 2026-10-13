# :80 default server — redirect to HTTPS, keep path and query; ACME webroot is
# served directly (no redirect).
GET http://localhost/api/users?page=2
HTTP 301
[Asserts]
header "Location" == "https://localhost/api/users?page=2"

GET http://localhost/.well-known/acme-challenge/missing-token
HTTP 404

# stub_status is reachable from the internal Docker network
GET http://localhost/nginx-status
HTTP 200
[Asserts]
body contains "Active connections"
