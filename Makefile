.PHONY: setup download snapshot up down logs status clean help

NETWORK ?=
ALTDA ?= false

# Determine compose file based on ALTDA flag
ifeq ($(ALTDA),celestia)
	COMPOSE_FILE := docker-compose.celestia.yml
	DOWNLOAD_FLAGS := --celestia
else
	COMPOSE_FILE := docker-compose.yml
	DOWNLOAD_FLAGS :=
endif

help:
	@echo "Arbitrum Node Management"
	@echo ""
	@echo "Usage:"
	@echo "  make setup NETWORK=<slug>               Setup standard AnyTrust network"
	@echo "  make setup NETWORK=<slug> ALTDA=celestia   Setup Celestia DA network"
	@echo ""
	@echo "Targets:"
	@echo "  setup    Download chain config and optionally restore a snapshot"
	@echo "           Set SNAPSHOT_ENABLED=true in .env to restore before starting"
	@echo "  up       Start containers"
	@echo "  down     Stop containers"
	@echo "  logs     Show container logs"
	@echo "  status   Show sync status"
	@echo "  clean    Stop containers and remove data"
	@echo ""


setup: download snapshot
	@echo "Setup complete! Run 'make up' to start the node."

download:
ifndef NETWORK
	$(error NETWORK is required. Usage: make setup NETWORK=<slug>)
endif
	@echo "Downloading config for $(NETWORK)..."
	./download-config.sh $(DOWNLOAD_FLAGS) $(NETWORK)

snapshot:
	@SNAPSHOT_ENABLED_VALUE=$$(awk -F= '/^SNAPSHOT_ENABLED=/{value=$$2; gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$$/, "", value); print value; exit}' .env 2>/dev/null); \
	if [ "$${SNAPSHOT_ENABLED_VALUE:-false}" = "true" ]; then \
		echo "Restoring snapshot for $(NETWORK)..."; \
		./download-snapshot.sh $(NETWORK); \
	else \
		echo "Snapshot restore disabled; skipping."; \
	fi

up:
	@echo "Starting containers with $(COMPOSE_FILE)..."
	docker compose -f $(COMPOSE_FILE) up -d

down:
	docker compose -f $(COMPOSE_FILE) down

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

status:
	./sync-status.sh

clean: down
	@echo "WARNING: This will permanently delete all node data in ./data"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted." && exit 1)
	@echo "Removing data directory..."
	rm -rf ./data
	@echo "Clean complete. Run 'make setup NETWORK=<slug>' to reinitialize."
