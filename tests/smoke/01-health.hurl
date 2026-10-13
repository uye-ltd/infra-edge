# /healthz is answered by nginx itself on every server, HTTP and HTTPS.
GET https://localhost/healthz
HTTP 200
[Asserts]
header "Content-Type" == "application/json"
jsonpath "$.status" == "ok"
jsonpath "$.service" == "uye-edge"
header "Strict-Transport-Security" exists

GET https://demo.localhost/healthz
HTTP 200
[Asserts]
jsonpath "$.status" == "ok"

GET http://localhost/healthz
HTTP 200
[Asserts]
jsonpath "$.status" == "ok"
