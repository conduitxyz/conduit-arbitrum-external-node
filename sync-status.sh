#!/bin/bash
# sync.sh - Monitor Arbitrum node sync progress

# Load .env if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

LOCAL_RPC="${L2_RPC_URL:-http://localhost:8547}"
REMOTE_RPC="${FORWARDING_TARGET}"

if [ -z "$REMOTE_RPC" ]; then
    echo "Error: FORWARDING_TARGET not set in .env"
    exit 1
fi

echo "Monitoring sync progress..."
echo "Local:  $LOCAL_RPC"
echo "Remote: $REMOTE_RPC"
echo ""

while true; do
    # Get local block
    LOCAL_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$LOCAL_RPC" 2>/dev/null | jq -r '.result' 2>/dev/null | xargs printf "%d" 2>/dev/null)

    # Get remote/sequencer block
    REMOTE_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$REMOTE_RPC" 2>/dev/null | jq -r '.result' 2>/dev/null | xargs printf "%d" 2>/dev/null)

    if [ -n "$LOCAL_BLOCK" ] && [ "$LOCAL_BLOCK" -gt 0 ] && [ -n "$REMOTE_BLOCK" ] && [ "$REMOTE_BLOCK" -gt 0 ]; then
        BEHIND=$((REMOTE_BLOCK - LOCAL_BLOCK))
        PERCENT=$(echo "scale=4; ($LOCAL_BLOCK / $REMOTE_BLOCK) * 100" | bc)

        if [ "$BEHIND" -eq 0 ]; then
            echo -e "\r\033[KLocal: $LOCAL_BLOCK | Remote: $REMOTE_BLOCK | ✓ Synced!"
        else
            echo -e "\r\033[KLocal: $LOCAL_BLOCK | Remote: $REMOTE_BLOCK | Behind: $BEHIND blocks | Progress: ${PERCENT}%"
        fi
    else
        echo -e "\r\033[KWaiting for node to respond..."
    fi

    sleep 15
done
