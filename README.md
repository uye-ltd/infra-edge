
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
├── docker-compose.local.yml    # Local overrides (local build, local cert, stub upstream)
├── docker-compose.infra-runner.yml # Overlay for the infra-runner deployer (plugin mounts)
├── .infra-runner.plugin        # infra-runner deployer plugin descriptor
├── Makefile                    # Local shortcuts (`make help`)
├── .env.example                # All supported environment variables (the only tracked .env*)
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
│   ├── init-local-env.sh       # Local: generate .env.local from .env.example
│   ├── generate-local-certs.sh # Local: certs/local/ via mkcert (fallback: openssl)
│   ├── certbot-renew.sh        # Production: renew Let's Encrypt certs + reload
│   ├── wait-healthy.sh         # Production: deployer post-deploy hook (wait for healthy)
│   └── healthcheck.sh          # Manual health probe
├── local/
│   ├── go-gateway-stub.conf    # nginx stub that mimics the Go Gateway locally
│   ├── demo-stub.conf          # upstream stub for the demo site
│   ├── observability/          # local Prometheus / Loki / Alloy / Grafana configs
│   └── sites/demo.conf         # local-only second site on demo.localhost
├── tests/
│   ├── config/                 # env-var sync, compose config, nginx -t + gixy
│   └── smoke/                  # hurl smoke tests (`make smoke`)
└── certbot/                    # Certbot data (mounted as a Docker volume)
```

---

## Quick start (local)

Environments: **local** = developer machine, **dev** = reserved for a future shared
dev server, **production** = `docker-compose.yml` + `.env`.

### 1. One-time setup
```bash
# Optional, for browser-trusted certs (no warnings, no --cacert):
brew install mkcert && mkcert -install

make init   # .env.local (generated from .env.example) + certs/local/*
```
Without mkcert a self-signed cert is generated; after installing mkcert later run
`make certs-force`.

### 2. Start the stack
```bash
make up     # nginx + stub go-gateway + nginx-exporter
```

### 3. Verify
```bash
curl --cacert certs/local/ca.pem https://localhost/healthz
# {"status":"ok","service":"uye-edge"}

curl --cacert certs/local/ca.pem https://localhost/api/users
# {"service":"go-gateway-stub","host":"localhost","path":"/api/users",...}

curl --cacert certs/local/ca.pem https://demo.localhost/
# {"service":"demo-stub","host":"demo.localhost","path":"/"}
```

`demo.localhost` is a local-only second site (`local/sites/demo.conf`) for checking
multi-site behaviour; `*.localhost` resolves to 127.0.0.1 without `/etc/hosts` edits.

Other targets: `make reload` (static config), `make restart` (templates), `make logs`,
`make down`; see `make help`.

---

## Checks

```bash
make hooks         # one-time: git hooks (lint on commit, nginx -t + gixy on push)
make lint          # shellcheck, hadolint, yamllint, dotenv-linter, env/compose checks
make test-config   # nginx -t + gixy for production and local env (Docker only)
make smoke         # hurl smoke tests against the running local stack
make test          # test-config + up + smoke
```

CI (`.github/workflows/ci.yml`) runs the same `make lint`-equivalent pre-commit
hooks, `make test-config` and `make init up smoke` on every PR and push to `main`.

---

## Production deploy (infra-runner)

The image is built, pushed to `ghcr.io/uye-ltd/infra-edge` and cosign-signed by the
`publish` job in `.github/workflows/ci.yml` on every push to `main` (after lint, config
and smoke pass), on the self-hosted [infra-runner](https://github.com/uye-ltd/infra-runner).
The infra-runner **deployer** treats this repo as a plugin (`.infra-runner.plugin`): each
poll cycle it pulls `infra-edge:latest`, verifies the signature against the `ci.yml`
identity, runs `docker compose up -d --no-deps nginx` and then `scripts/wait-healthy.sh`.
No SSH, no deploy job.

The GHCR package must be **public** (the deployer uses a GitHub App token, which cannot
read GHCR). After the first `publish` run: package settings → Change visibility → Public.

### First-time server setup (as `ghrunner`, next to `~/infra-runner`)
```bash
git clone https://github.com/uye-ltd/infra-edge ~/infra-edge
cd ~/infra-edge
cp .env.example .env    # set NGINX_DOMAIN, CERTBOT_EMAIL, cert paths, NGINX_UPSTREAM_*

# First certificate: certbot standalone on :80 before nginx exists
# (nginx cannot start without the certificate files).
docker compose --profile certbot run --rm -p 80:80 certbot \
    certonly --standalone --email "$CERTBOT_EMAIL" --agree-tos --no-eff-email \
    -d "$NGINX_DOMAIN" -d "www.$NGINX_DOMAIN"

docker compose pull nginx
docker compose up -d nginx
```
(`CERTBOT_EMAIL` / `NGINX_DOMAIN` above are shell variables — export them or type the values.)

Register the plugin in `~/infra-runner/.env`, then recreate the deployer:
```bash
EDGE_COMPOSE_DIR=/home/ghrunner/infra-edge
# append to the existing list (setting COMPOSE_FILE disables override.yml auto-discovery):
COMPOSE_FILE=docker-compose.yml:<existing overlays>:../infra-edge/docker-compose.infra-runner.yml
```
```bash
cd ~/infra-runner && docker compose up -d deployer
```

Cron (`crontab -e` as `ghrunner`):
```bash
# Keep the checkout current: compose file, descriptor and hook script are read from it
*/5 * * * * git -C /home/ghrunner/infra-edge pull --ff-only origin main
# Certificate renewal + nginx reload
0 3 * * * /home/ghrunner/infra-edge/scripts/certbot-renew.sh >> /home/ghrunner/certbot-renew.log 2>&1
```

### What deploys automatically

| Change | How it reaches the server |
|---|---|
| `nginx/**`, `Dockerfile` (everything inside the image) | automatically: new signed image → deployer recreates nginx |
| `docker-compose.yml`, `.infra-runner.plugin`, `scripts/wait-healthy.sh` | after the `git pull` cron; compose changes apply with the next image update or `docker compose up -d nginx` |
| server `.env` | manual `docker compose up -d nginx` |

A failed signature check, `compose up` or health wait marks the deployer's
`GET :8080/health` as `503`; there is no automatic rollback. Deployer logs:
`docker compose -f ~/infra-runner/docker-compose.yml logs -f --no-log-prefix deployer | jq .`

### Upstream network
The `edge` network has a fixed name, `uye-edge`. The Go Gateway stack joins it as an
external network and must be up before nginx starts (nginx resolves
`NGINX_UPSTREAM_HOST` at startup):
```yaml
networks:
  uye-edge:
    external: true
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

### Local monitoring
```bash
make up-monitoring   # + Prometheus (:9090), Loki, Alloy, Grafana (:3000)
```
Grafana opens without login on the "uye-edge (local)" dashboard: connections,
requests by status/host, request and upstream latency percentiles, live access log.
Configs: `local/observability/`.

### Access logs
Logs are written in JSON to the container's stdout (`/var/log/nginx/access.log` is a symlink to `/dev/stdout`; buffered, flushed every 5 s) — read them with `docker logs uye-edge` or a log shipper. Each line includes:
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
- Any path segment starting with `.git`, `.env`, `.htaccess`, `.htpasswd`, `.DS_Store` (e.g. `/.git/config`, `/.env.local`) returns `404`.
- `client_max_body_size` is capped at `10m` in `nginx.conf`. Adjust if your API handles large file uploads.
- To add IP blocklists, uncomment and populate the `geo $blocked_ip` block in `nginx/conf.d/security.conf` and add `if ($blocked_ip) { return 403; }` to the HTTPS server template.
