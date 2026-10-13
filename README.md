
# uye-edge

NGINX-based edge API gateway for the UYE platform. Handles TLS termination, reverse proxying, rate limiting, compression, and observability at the network boundary before traffic reaches the internal Go Gateway.

```
Browser / Client
       │  HTTPS
       ▼
┌─────────────────────────┐
│     uye-edge (NGINX)    │
│  - TLS termination      │
│  - Rate limiting        │
│  - Gzip compression     │
│  - Security headers     │
│  - Access logging (JSON)│
│  - X-Request-ID tracing │
└──────────┬──────────────┘
           │  HTTP  (internal)
           ▼
    Go Gateway (uye-gate)
           │  JWT / session → JWT
           ▼
    Microservices
```

---

## Repository layout

```
uye-edge/
├── Dockerfile
├── docker-compose.yml          # Production compose
├── docker-compose.dev.yml      # Dev overrides (self-signed cert + stub upstream)
├── .env.example                # All supported environment variables
├── .env.dev                    # Dev defaults (relaxed limits, self-signed TLS)
├── nginx/
│   ├── nginx.conf              # Main nginx config (static — tuned defaults)
│   ├── conf.d/                 # Static modular configs (included at build time)
│   │   ├── logging.conf        # JSON access log format
│   │   ├── gzip.conf           # Gzip compression settings
│   │   ├── security.conf       # UA filtering, method blocking, maps
│   │   ├── ssl-params.conf     # TLS protocols, ciphers, OCSP stapling
│   │   └── proxy-params.conf   # Upstream headers, buffering, timeouts
│   ├── snippets/               # Shared server/location includes (headers, guard rails, health, errors, TLS)
│   ├── templates/              # envsubst templates → /etc/nginx/generated/ at startup
│   │   ├── rate-limit.conf.template
│   │   ├── upstream.conf.template
│   │   ├── http-server.conf.template   # :80 default server (ACME, health, redirect)
│   │   ├── https-server.conf.template  # :443 default server (unknown hosts → 444)
│   │   └── sites/                      # One file per application served by the edge
│   │       └── uye.conf.template
│   └── examples/
│       └── app.conf.template   # Starting point for a new application site
├── scripts/
│   ├── generate-self-signed.sh # Dev: create self-signed cert
│   ├── certbot-renew.sh        # Production: renew Let's Encrypt certs + reload
│   └── healthcheck.sh          # Manual health probe
├── dev/
│   └── go-gateway-stub.conf    # nginx stub that mimics the Go Gateway in dev
└── certbot/                    # Certbot data (mounted as a Docker volume)
```

---

## Quick start (development)

### 1. Generate a self-signed certificate
```bash
bash scripts/generate-self-signed.sh
```

### 2. Start the stack
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

### 3. Verify
```bash
curl -k https://localhost/healthz
# {"status":"ok","service":"uye-edge"}

curl -k https://localhost/api/users
# {"service":"go-gateway-stub","path":"/api/users","message":"..."}
```

---

## Production setup

### 1. Configure environment
```bash
cp .env.example .env
# Edit .env — set NGINX_DOMAIN, CERTBOT_EMAIL, NGINX_UPSTREAM_HOST, etc.
```

### 2. Issue a Let's Encrypt certificate (first run)
```bash
# Start nginx on HTTP only first (comment out https-server include temporarily)
docker compose up -d nginx

# Issue certificate via webroot challenge
docker compose --profile certbot run --rm certbot
```

### 3. Start the full stack
```bash
docker compose up -d
```

### 4. Schedule certificate renewal
```bash
# Add to crontab on the host
echo "0 3 * * * /opt/uye-edge/scripts/certbot-renew.sh >> /var/log/certbot-renew.log 2>&1" | crontab -
```

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `NGINX_DOMAIN` | `example.com` | Primary domain (also applied to `www.`) |
| `CERTBOT_EMAIL` | — | Email for Let's Encrypt account |
| `NGINX_SSL_CERT_PATH` | `/etc/nginx/ssl/live/…/fullchain.pem` | Path to TLS certificate inside container |
| `NGINX_SSL_KEY_PATH` | `/etc/nginx/ssl/live/…/privkey.pem` | Path to TLS private key |
| `NGINX_SSL_CHAIN_PATH` | `/etc/nginx/ssl/live/…/chain.pem` | Path to CA chain (for OCSP stapling) |
| `NGINX_UPSTREAM_HOST` | `go-gateway` | Go Gateway hostname |
| `NGINX_UPSTREAM_PORT` | `8080` | Go Gateway port |
| `NGINX_LB_ALGORITHM` | _(empty = round-robin)_ | `least_conn;` or `ip_hash;` |
| `NGINX_RATE_LIMIT_RATE` | `100r/m` | `/api/*` rate limit |
| `NGINX_RATE_LIMIT_BURST` | `20` | `/api/*` burst |
| `NGINX_RATE_LIMIT_AUTH_RATE` | `10r/m` | `/api/auth/*` rate limit |
| `NGINX_RATE_LIMIT_AUTH_BURST` | `5` | `/api/auth/*` burst |
| `NGINX_RATE_LIMIT_GENERAL_RATE` | `200r/m` | All other routes rate limit |
| `NGINX_RATE_LIMIT_GENERAL_BURST` | `50` | All other routes burst |
| `NGINX_CONN_LIMIT_PER_IP` | `20` | Max concurrent connections per IP |

---

## Observability

### Prometheus metrics
The `nginx-exporter` service (enable with `--profile observability`) scrapes `/nginx-status` and exposes standard metrics on `:9113/metrics`:

```bash
docker compose --profile observability up -d nginx-exporter
curl http://localhost:9113/metrics
```

Key metrics exposed:
- `nginx_connections_active`
- `nginx_http_requests_total`
- `nginx_connections_accepted_total`

### Access logs
Logs are written in JSON to `/var/log/nginx/access.log` (buffered, flushed every 5 s). Each line includes:
- `request_id` — unique per-request ID, also propagated as `X-Request-ID` header
- `upstream_response_time` — latency contribution from the Go Gateway
- `status`, `request_time`, `remote_addr`, TLS details, and more

### Distributed tracing
`X-Request-ID` is generated by nginx (`$request_id`) and:
1. Forwarded to the Go Gateway as a proxy header
2. Returned to the client in the response

The Go Gateway is expected to forward it to downstream microservices.

---

## Horizontal scaling

### Docker Swarm / multiple Go Gateway instances
Add additional `server` lines in `nginx/templates/upstream.conf.template`:
```nginx
server go-gateway-1:8080  max_fails=3  fail_timeout=30s;
server go-gateway-2:8080  max_fails=3  fail_timeout=30s;
server go-gateway-3:8080  max_fails=3  fail_timeout=30s  backup;
```

Set `NGINX_LB_ALGORITHM=least_conn;` for connection-aware balancing.

### Kubernetes
Replace docker-compose with Helm. Use envsubst or Helm values to populate the same environment variables. The HTTPS server template is compatible with cert-manager — set `NGINX_SSL_CERT_PATH` to the Kubernetes secret mount path.

---

## Security notes

- TLS 1.0 and 1.1 are disabled. Only TLS 1.2 and 1.3 are accepted.
- HSTS is set with a 2-year max-age and `preload` to prevent downgrade attacks.
- Empty `User-Agent` and known scanner signatures (`sqlmap`, `nikto`, `nmap`, `masscan`, `zgrab`) return `403`.
- `TRACE` and `TRACK` methods return `405`.
- Access to `.git`, `.env`, `.htaccess`, `.htpasswd` paths returns `404`.
- `client_max_body_size` is capped at `10m` in `nginx.conf`. Adjust if your API handles large file uploads.
- To add IP blocklists, uncomment and populate the `geo $blocked_ip` block in `nginx/conf.d/security.conf` and add `if ($blocked_ip) { return 403; }` to the HTTPS server template.
