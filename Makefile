# Makefile — local development shortcuts. Run `make help` for the list.

ENV_FILE ?= .env.local
COMPOSE  := docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.local.yml

.DEFAULT_GOAL := help
.PHONY: help init env certs up down restart reload nginx-t logs ps

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: env certs ## One-time local setup: .env.local + TLS certs

env: ## Generate .env.local from .env.example (keeps an existing file)
	@scripts/init-local-env.sh

certs: ## Generate local TLS certs in certs/local (keeps existing ones)
	@test -f certs/local/cert.pem || scripts/generate-self-signed.sh

$(ENV_FILE):
	@echo "$(ENV_FILE) is missing — run 'make init' first." >&2; exit 1

up: $(ENV_FILE) ## Build and start the local stack in the background
	$(COMPOSE) up -d --build

down: $(ENV_FILE) ## Stop the local stack
	$(COMPOSE) down

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
