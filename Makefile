# =============================================================================
# Convenience wrapper around `docker compose`. Modules are composed via the
# COMPOSE_FILE env var so every target (logs, ps, down...) sees the same stack.
#
#   make up                 # core only
#   make MODULES="agent" up # core + Elastic Agent
#   make MODULES="agent logstash apm" up
#
# Without `make`, the equivalent raw command is printed by `make print`.
# =============================================================================

# Space-separated module names (agent, logstash, apm, filebeat, metricbeat,
# auditbeat, heartbeat). Empty = core only.
MODULES ?=

# Build the chained -f argument list: compose.yaml + each module file.
COMPOSE_FILES := -f compose.yaml $(foreach m,$(MODULES),-f compose.$(m).yaml)
DC := docker compose $(COMPOSE_FILES)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: env
env: ## Create .env from sample.env if missing
	@test -f .env || (cp sample.env .env && echo "Created .env from sample.env — review it!")

.PHONY: up
up: env ## Start the stack (set MODULES="agent ...")
	$(DC) up -d

.PHONY: down
down: ## Stop and remove containers (keeps data volumes)
	$(DC) down

.PHONY: destroy
destroy: ## Stop and remove containers AND data volumes
	$(DC) down -v

.PHONY: ps
ps: ## List stack containers and health
	$(DC) ps

.PHONY: logs
logs: ## Tail logs of all running services
	$(DC) logs -f --tail=100

.PHONY: pull
pull: ## Pull all images at the pinned STACK_VERSION
	$(DC) pull

.PHONY: print
print: ## Print the raw docker compose command for the current MODULES
	@echo "$(DC) up -d"
