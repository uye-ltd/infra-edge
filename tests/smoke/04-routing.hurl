# Each site proxies to its own upstream; X-Request-ID reaches the upstream.
GET https://localhost/api/users
HTTP 200
[Captures]
request_id: header "X-Request-ID"
[Asserts]
jsonpath "$.service" == "go-gateway-stub"
jsonpath "$.host" == "localhost"
jsonpath "$.path" == "/api/users"
jsonpath "$.request_id" == "{{request_id}}"

GET https://localhost/api/auth/login
HTTP 200
[Asserts]
jsonpath "$.service" == "go-gateway-stub"
jsonpath "$.path" == "/api/auth/login"

GET https://localhost/
HTTP 200
[Asserts]
jsonpath "$.service" == "go-gateway-stub"

# demo.localhost must never reach go-gateway (Host/SNI isolation)
GET https://demo.localhost/api/users
HTTP 200
[Asserts]
jsonpath "$.service" == "demo-stub"
jsonpath "$.host" == "demo.localhost"
