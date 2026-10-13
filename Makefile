# Makefile — local development shortcuts. Run `make help` for the list.

ENV_FILE ?= .env.local
COMPOSE  := docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.local.yml

.DEFAULT_GOAL := help
.PHONY: help init env certs certs-force up up-monitoring down restart reload nginx-t logs ps hooks lint test-config smoke test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: env certs ## One-time local setup: .env.local + TLS certs

env: ## Generate .env.local from .env.example (keeps an existing file)
	@scripts/init-local-env.sh

certs: ## Generate local TLS certs in certs/local (mkcert if installed; keeps existing ones)
	@scripts/generate-local-certs.sh

certs-force: ## Regenerate local TLS certs (e.g. after installing mkcert or adding a host)
	@scripts/generate-local-certs.sh --force

$(ENV_FILE):
	@echo "$(ENV_FILE) is missing — run 'make init' first." >&2; exit 1

up: $(ENV_FILE) ## Build and start the local stack, wait until healthy
	$(COMPOSE) up -d --build --wait

up-monitoring: $(ENV_FILE) ## Start the stack plus Prometheus/Loki/Alloy/Grafana (http://localhost:3000)
	$(COMPOSE) --profile monitoring up -d --build

down: $(ENV_FILE) ## Stop the local stack (including monitoring)
	$(COMPOSE) --profile monitoring down

restart: $(ENV_FILE) ## Restart nginx (re-renders templates)
	$(COMPOSE) restart nginx

reload: $(ENV_FILE) ## Validate and hot-reload static config (conf.d, snippets, nginx.conf)
	$(COMPOSE) exec nginx nginx -t
	$(COMPOSE) exec nginx nginx -s reload

nginx-t: $(ENV_FILE) ## Validate config inside the running nginx container
	$(COMPOSE) exec nginx nginx -t

logs: $(ENV_FILE) ## Follow logs of all services
	$(COMPOSE) logs -f

ps: $(ENV_FILE) ## Show service status
	$(COMPOSE) ps

# ---- Checks ------------------------------------------------------------------

hooks: ## Install git hooks (pre-commit on commit, nginx -t + gixy on push)
	pre-commit install --hook-type pre-commit --hook-type pre-push

lint: ## Run all pre-commit linters on the whole repo
	pre-commit run --all-files

test-config: ## Env var sync, compose config, nginx -t + gixy for prod and local env
	tests/config/check-env-vars.sh
	tests/config/compose-config.sh
	tests/config/nginx-t.sh

smoke: $(ENV_FILE) ## hurl smoke tests against the running local stack (tests/smoke)
	$(COMPOSE) --profile test run --rm --build smoke

test: test-config up smoke ## Everything: config checks, start the stack, smoke tests
