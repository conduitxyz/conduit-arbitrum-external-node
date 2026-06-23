![Conduit](logo.png)

# Conduit Node

Conduit provides fully-managed, production-grade rollups on Ethereum. We highly recommend using a managed Conduit RPC for the fastest and most reliable experience, visit the [Conduit App](https://app.conduit.xyz/nodes) to create your very own RPC.

This repository contains the relevant Docker builds to run your own node on the specific Conduit network.

[![Website conduit.xyz](https://img.shields.io/website-up-down-green-red/https/conduit.xyz.svg)](https://conduit.xyz)
[![Status](https://img.shields.io/badge/status-up-green)](https://status.conduit.xyz/)
[![Blog](https://img.shields.io/badge/blog-up-green)](https://conduit.xyz/blog)
[![Docs](https://img.shields.io/badge/docs-up-green)](https://docs.conduit.xyz/overview)
[![Twitter Conduit](https://img.shields.io/twitter/follow/conduitxyz?style=social)](https://twitter.com/conduitxyz)

## Prerequisites

- Docker and Docker Compose
- `make`
- `jq`
- `curl` and `bc`
- Google Cloud CLI with `gcloud storage` (required when restoring snapshots)

## Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32 GB |
| Storage | 500 GB SSD | 1 TB+ NVMe SSD |

**Note:** Archive mode requires significantly more storage than full mode.

## Node Mode

**The node runs in archive mode by default.** Archive mode retains full historical state, which requires more disk space but allows querying any historical block.

To switch to full mode (non-archive), edit the docker-compose file and comment out the archive flag:

```yaml
# - --execution.caching.archive    # Comment this line for full mode
```

| Mode | Description | Disk Usage |
|------|-------------|------------|
| `archive` | Retains all historical state | Higher |
| `full` | Prunes old state, keeps recent | Lower |

## Required Environment Variables

Before starting, configure these in your `.env` file:

| Variable | Description |
|----------|-------------|
| `CHAIN_NAME` | Unique identifier for data directory (use network slug) |
| `FORWARDING_TARGET` | Sequencer RPC URL (e.g., `https://rpc-<network-slug>.t.conduit.xyz`) |
| `SEQUENCER_FEED_RELAY` | Websocket relay URL (e.g., `wss://relay-<network-slug>.t.conduit.xyz/`) |
| `PARENT_CHAIN_RPC` | Parent chain RPC URL |
| `DAS_URL` | Data Availability Server URL |
| `PARENT_CHAIN_BEACON_URL` | Beacon chain RPC (required if parent is Ethereum mainnet) |
| `GCP_PROJECT` | Google Cloud billing project used by `gcloud storage` for requester-pays snapshot downloads; defaults to the active `gcloud` project when unset |

**Note:** `FORWARDING_TARGET` and `SEQUENCER_FEED_RELAY` are automatically set by `make setup`. For production usage, create an API key in the [Conduit application](https://app.conduit.xyz/nodes) and append it to the URL:
```
FORWARDING_TARGET=https://rpc-<network-slug>.t.conduit.xyz/<api-key>
SEQUENCER_FEED_RELAY=wss://relay-<network-slug>.t.conduit.xyz/<api-key>
```

**Note:** Snapshot restores stream from a requester-pays Google Cloud Storage bucket into `./data/${CHAIN_NAME}`. Set `SNAPSHOT_ENABLED=true` in `.env` before running `make setup` to enable restore. Set `GCP_PROJECT` in `.env`, export it, or configure an active `gcloud` project for billing. The authenticated Google Cloud account also needs the `roles/serviceusage.serviceUsageConsumer` role on the billing project used for requester-pays requests.

### Celestia-specific

| Variable | Description |
|----------|-------------|
| `CELESTIA_RPC` | Celestia RPC endpoint |
| `CELESTIA_NAMESPACE_ID` | Celestia namespace |
| `SEQUENCER_INBOX_ADDRESS` | Sequencer inbox contract |

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with the required variables listed above.

### 2. Setup and Run

**ETH DA chains:**
```bash
make setup NETWORK=<network-slug>
make up
```

To restore the latest snapshot during setup, set `SNAPSHOT_ENABLED=true` in `.env` before running `make setup`.

**Celestia (Alt DA) chains:**
```bash
make setup NETWORK=<network-slug> ALTDA=celestia
make up ALTDA=celestia
```

### 3. Monitor and Manage

```bash
make status    # Show sync progress
make logs      # Show container logs
make down [ALTDA=celestia]  # Stop containers, add ALTDA flag if its enabled
make clean [ALTDA=celestia]   # Stop and remove all data, add ALTDA flag if its enabled
```

## Make Commands

| Command | Description |
|---------|-------------|
| `make setup NETWORK=<slug>` | Download chain config and optionally restore a snapshot |
| `make setup NETWORK=<slug> ALTDA=celestia` | Download config for Celestia enabled chains and optionally restore a snapshot |
| `make up` | Start containers (add `ALTDA=celestia` if using celestia) |
| `make down` | Stop containers (add `ALTDA=celestia` if using celestia) |
| `make logs` | Show container logs |
| `make status` | Show sync progress |
| `make clean` | Stop containers and remove data (add `ALTDA=celestia` if using celestia) |

## Configuration Files

| File | Description |
|------|-------------|
| `Makefile` | Make commands for setup and management |
| `docker-compose.yml` | AnyTrust (DAS) configuration |
| `docker-compose.celestia.yml` | Celestia DA with AnyTrust fallback |
| `.env.example` | Environment variable template |
| `download-config.sh` | Downloads chainInfo.json and other required info from Conduit API |
| `download-snapshot.sh` | Restores the Conduit `latest.tar` snapshot into `./data/${CHAIN_NAME}` when enabled during setup |
| `sync-status.sh` | Monitors node sync progress |

## Data Storage

Node data is stored in `./data/${CHAIN_NAME}/`

## Disclaimer

THE NODE SOFTWARE AND SMART CONTRACTS CONTAINED HEREIN ARE FURNISHED AS IS, WHERE IS, WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING ANY WARRANTY OF MERCHANTABILITY, NON- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE. IN PARTICULAR, THERE IS NO REPRESENTATION OR WARRANTY THAT THE NODE SOFTWARE AND SMART CONTRACTS WILL PROTECT YOUR ASSETS — OR THE ASSETS OF THE USERS OF YOUR APPLICATION — FROM THEFT, HACKING, CYBER ATTACK, OR OTHER FORM OF LOSS OR DEVALUATION.
