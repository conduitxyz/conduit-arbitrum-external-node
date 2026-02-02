#!/bin/bash
# Fetch chainInfo.json from Conduit API for Arbitrum chains

set -e

# Parse arguments
CELESTIA=false
SLUG=""

for arg in "$@"; do
    case $arg in
        --celestia)
            CELESTIA=true
            ;;
        *)
            SLUG=$arg
            ;;
    esac
done

API_URL="https://api.conduit.xyz/file/v1/arbitrum/chaininfo"

if [ -z "$SLUG" ]; then
    echo "Error: Network slug required."
    echo "Use: make setup NETWORK=<slug>"
    exit 1
fi

echo "Fetching chainInfo.json for $SLUG..."
curl -sf "${API_URL}/${SLUG}" -o chainInfo.json

if [ ! -s chainInfo.json ]; then
    echo "Failed to fetch chainInfo.json. Check the network slug."
    rm -f chainInfo.json
    exit 1
fi

echo "chainInfo.json has been created."
echo ""

# Update .env with network-specific values
if [ -f .env ]; then
    # Helper function to update or add env var
    update_env() {
        local key=$1
        local value=$2
        if grep -q "^${key}=" .env; then
            sed -i.bak "s|^${key}=.*|${key}=${value}|" .env && rm -f .env.bak
        else
            echo "${key}=${value}" >> .env
        fi
    }

    update_env "CHAIN_NAME" "$SLUG"
    update_env "FORWARDING_TARGET" "https://rpc-${SLUG}.t.conduit.xyz"
    update_env "SEQUENCER_FEED_RELAY" "wss://relay-${SLUG}.t.conduit.xyz/"
    update_env "DAS_URL" "https://das-${SLUG}.t.conduit.xyz"

    echo "Updated .env:"
    echo "  CHAIN_NAME=$SLUG"
    echo "  FORWARDING_TARGET=https://rpc-${SLUG}.t.conduit.xyz"
    echo "  SEQUENCER_FEED_RELAY=wss://relay-${SLUG}.t.conduit.xyz/"
    echo "  DAS_URL=https://das-${SLUG}.t.conduit.xyz"
fi

# Extract and write sequencer-inbox address to .env
if command -v jq &> /dev/null && [ -f .env ]; then
    SEQ_INBOX=$(jq -r '.chain["info-json"] | fromjson | .[0].rollup["sequencer-inbox"] // empty' chainInfo.json 2>/dev/null)
    if [ -n "$SEQ_INBOX" ]; then
        update_env "SEQUENCER_INBOX_ADDRESS" "$SEQ_INBOX"
        echo "  SEQUENCER_INBOX_ADDRESS=$SEQ_INBOX"
        echo ""
    fi
fi

if [ "$CELESTIA" = "true" ]; then
    echo "Configuration: Celestia DA (with AnyTrust fallback)"
    echo ""
    echo "Required .env variables:"
    echo "  - FORWARDING_TARGET"
    echo "  - SEQUENCER_FEED_RELAY"
    echo "  - PARENT_CHAIN_RPC"
    echo "  - PARENT_CHAIN_BEACON_URL (if parent chain is Ethereum mainnet)"
    echo "  - DAS_URL"
    echo "  - CELESTIA_RPC"
    echo "  - CELESTIA_NAMESPACE_ID"
    echo "  - SEQUENCER_INBOX_ADDRESS"
    echo ""
    echo "Run with:"
    echo "  docker compose -f docker-compose.celestia.yml up -d"
else
    echo "Configuration: ETH DA"
    echo ""
    echo "Required .env variables:"
    echo "  - FORWARDING_TARGET"
    echo "  - SEQUENCER_FEED_RELAY"
    echo "  - PARENT_CHAIN_RPC"
    echo "  - DAS_URL"
    echo ""
fi
