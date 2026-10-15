# :80 default server redirects to HTTPS and preserves path and query.
GET http://localhost/api/users?page=2
HTTP 301
[Asserts]
header "Location" == "https://localhost/api/users?page=2"

GET http://localhost/.well-known/acme-challenge/missing-token
HTTP 301

# stub_status is reachable from the internal Docker network
GET http://localhost/nginx-status
HTTP 200
[Asserts]
body contains "Active connections"
