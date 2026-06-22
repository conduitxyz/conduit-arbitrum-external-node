#!/usr/bin/env bash
#
# Monitor Arbitrum node sync progress
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

LOCAL_RPC="${L2_RPC_URL:-http://localhost:8547}"
REMOTE_RPC="${FORWARDING_TARGET:-}"
REFRESH_SECONDS="${STATUS_REFRESH_SECONDS:-10}"

if [[ -z "$REMOTE_RPC" ]]; then
    echo "Error: FORWARDING_TARGET not set in .env"
    exit 1
fi

rpc_block_number() {
    local rpc_url="$1"
    local result

    result="$(
        curl -s -X POST "$rpc_url" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' |
            jq -r '.result // empty' 2>/dev/null || true
    )"

    if [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf "%d\n" "$result"
    else
        echo "N/A"
    fi
}

is_number() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

print_box_header() {
    local title="$1"

    echo "┌─────────────────────────────────┐"
    printf "│ %31s │\n" "$title"
    echo "├─────────────────┬───────────────┤"
}

print_box_footer() {
    echo "└─────────────────┴───────────────┘"
}

print_row() {
    local label="$1"
    local value="$2"

    printf "│ %-15s │ %13s │\n" "$label" "$value"
}

while true; do
    clear
    echo "=== Sync Status - $(date) ==="
    echo ""
    echo "Local:  $LOCAL_RPC"
    echo "Remote: $REMOTE_RPC"
    echo ""

    LOCAL_BLOCK="$(rpc_block_number "$LOCAL_RPC")"
    REMOTE_BLOCK="$(rpc_block_number "$REMOTE_RPC")"
    BEHIND="N/A"
    PROGRESS="N/A"
    STATUS="Unavailable"

    if is_number "$LOCAL_BLOCK" && is_number "$REMOTE_BLOCK" && [[ "$REMOTE_BLOCK" -gt 0 ]]; then
        if [[ "$LOCAL_BLOCK" -ge "$REMOTE_BLOCK" ]]; then
            BEHIND=0
            PROGRESS="100.00%"
            STATUS="Synced"
        else
            BEHIND=$((REMOTE_BLOCK - LOCAL_BLOCK))
            PROGRESS="$(awk -v local="$LOCAL_BLOCK" -v remote="$REMOTE_BLOCK" 'BEGIN { printf "%.2f%%", (local * 100) / remote }')"
            STATUS="Syncing"
        fi
    elif ! is_number "$LOCAL_BLOCK" && is_number "$REMOTE_BLOCK"; then
        STATUS="Waiting for local RPC"
    elif is_number "$LOCAL_BLOCK" && ! is_number "$REMOTE_BLOCK"; then
        STATUS="Waiting for remote RPC"
    fi

    print_box_header "L2 Status"
    print_row "Local Latest" "$LOCAL_BLOCK"
    print_row "Remote Latest" "$REMOTE_BLOCK"
    print_row "Behind by" "$BEHIND"
    print_box_footer

    echo ""

    print_box_header "Sync Progress"
    print_row "Progress" "$PROGRESS"
    print_row "Status" "$STATUS"
    print_box_footer

    echo ""
    echo "Refreshing in ${REFRESH_SECONDS}s... (Ctrl+C to exit)"

    if [[ "${STATUS_ONCE:-false}" == "true" ]]; then
        exit 0
    fi

    sleep "$REFRESH_SECONDS"
done
