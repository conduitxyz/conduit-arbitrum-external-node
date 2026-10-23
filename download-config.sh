#!/bin/bash
# Fetch chainInfo.json from Conduit API for Arbitrum chains

set -e

if [[ $# -ne 1 || -z "${1:-}" || "$1" == -* ]]; then
    echo "Error: Exactly one network slug is required; options are not supported." >&2
    echo "Usage: $0 <network-slug> (or make setup NETWORK=<slug>)" >&2
    exit 1
fi

SLUG=$1
API_URL="https://api.conduit.xyz/file/v1/arbitrum/chaininfo"

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

echo "Configuration: AnyTrust DAS or parent-chain blobs"
echo ""
echo "Required .env variables:"
echo "  - FORWARDING_TARGET"
echo "  - SEQUENCER_FEED_RELAY"
echo "  - PARENT_CHAIN_RPC"
echo "  - PARENT_CHAIN_BEACON_URL (for Ethereum mainnet or Ethereum Sepolia parents)"
echo "  - DAS_URL (for AnyTrust chains)"
echo ""
echo "For HyperEVM parents: set DISABLE_BLOB_READER=true and leave PARENT_CHAIN_BEACON_URL empty."
echo "For Arbitrum parents: keep DISABLE_BLOB_READER=false and leave PARENT_CHAIN_BEACON_URL empty; Nitro detects the parent automatically."
echo "For Ethereum mainnet/Sepolia parents: keep DISABLE_BLOB_READER=false and provide PARENT_CHAIN_BEACON_URL."
echo ""
echo "Run with:"
echo "  make up"
