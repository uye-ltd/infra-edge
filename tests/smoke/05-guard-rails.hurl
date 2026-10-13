# snippets/guard-rails.conf + conf.d/security.conf

# Methods: TRACE/TRACK blocked, DELETE/PATCH allowed
TRACE https://localhost/api/x
HTTP 405

TRACK https://localhost/api/x
HTTP 405

DELETE https://localhost/api/x
HTTP 200

PATCH https://localhost/api/x
HTTP 200

# Scanner user agents
GET https://localhost/api/x
User-Agent: sqlmap/1.7.2#stable (https://sqlmap.org)
HTTP 403

GET https://localhost/api/x
User-Agent: Mozilla/5.00 (Nikto/2.5.0)
HTTP 403

GET https://demo.localhost/
User-Agent: masscan/1.3
HTTP 403

# Go HTTP client is explicitly allowed
GET https://localhost/api/x
User-Agent: Go-http-client/1.1
HTTP 200

# Sensitive paths — any segment starting with .git/.env/.htaccess/.htpasswd/.DS_Store
GET https://localhost/.git
HTTP 404

GET https://localhost/.git/config
HTTP 404

GET https://localhost/.env
HTTP 404

GET https://localhost/.env.local
HTTP 404

GET https://localhost/static/.htpasswd
HTTP 404

GET https://localhost/api/.git/HEAD
HTTP 404

GET https://demo.localhost/.env.production
HTTP 404
