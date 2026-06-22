#!/usr/bin/env bash

set -euo pipefail

NETWORK="${1:-${NETWORK:-}}"
PROGRESS_MONITOR_PID=""
SNAPSHOT_TOTAL_SIZE=""

read_env_value() {
    local key="$1"
    local file="${2:-.env}"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    awk -F= -v key="$key" '
        $1 == key {
            value = substr($0, index($0, "=") + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["'\'']|["'\'']$/, "", value)
            print value
            exit
        }
    ' "$file"
}

format_bytes() {
    local bytes="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        awk -v bytes="$bytes" '
            BEGIN {
                split("B KiB MiB GiB TiB PiB", units, " ")
                value = bytes
                unit = 1
                while (value >= 1024 && unit < 6) {
                    value /= 1024
                    unit++
                }
                if (unit == 1) {
                    printf "%.0f%s\n", value, units[unit]
                } else {
                    printf "%.1f%s\n", value, units[unit]
                }
            }
        '
    fi
}

start_progress_monitor() {
    (
        while true; do
            sleep 30
            SIZE="$(du -sh "$DATADIR" 2>/dev/null | awk '{print $1}')"
            if [[ -z "$SIZE" ]]; then
                SIZE="unknown"
            fi
            if [[ -n "$SNAPSHOT_TOTAL_SIZE" ]]; then
                echo "Snapshot restore in progress: ${DATADIR} is currently ${SIZE} of ${SNAPSHOT_TOTAL_SIZE}."
            else
                echo "Snapshot restore in progress: ${DATADIR} is currently ${SIZE}."
            fi
        done
    ) &
    PROGRESS_MONITOR_PID="$!"
}

stop_progress_monitor() {
    if [[ -n "${PROGRESS_MONITOR_PID:-}" ]]; then
        kill "$PROGRESS_MONITOR_PID" 2>/dev/null || true
        wait "$PROGRESS_MONITOR_PID" 2>/dev/null || true
        PROGRESS_MONITOR_PID=""
    fi
}

if [[ -z "$NETWORK" ]]; then
    echo "Usage: ./download-snapshot.sh <network-slug>"
    echo "Or set NETWORK in the environment."
    exit 1
fi

CHAIN_NAME="${CHAIN_NAME:-$(read_env_value CHAIN_NAME)}"
DATADIR="${DATADIR:-./data/${CHAIN_NAME:-$NETWORK}}"

mkdir -p "$DATADIR"

if find "$DATADIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    chmod -R a+rwX "$DATADIR"
    echo "Snapshot restore skipped: ${DATADIR} already contains data."
    exit 0
fi

chmod a+rwX "$DATADIR"

if ! command -v gcloud >/dev/null 2>&1; then
    echo "Error: gcloud is required to restore requester-pays snapshots."
    echo "Install the Google Cloud CLI and configure billing."
    exit 1
fi

if [[ -z "${GCP_PROJECT:-}" ]]; then
    GCP_PROJECT="$(read_env_value GCP_PROJECT)"
fi

if [[ -z "${GCP_PROJECT:-}" ]]; then
    GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
    if [[ "$GCP_PROJECT" == "(unset)" ]]; then
        GCP_PROJECT=""
    fi
fi

if [[ -z "${GCP_PROJECT:-}" ]]; then
    echo "Error: GCP_PROJECT is required to restore requester-pays snapshots."
    echo "Add GCP_PROJECT=<project-id> to .env, export it, or run: gcloud config set project <project-id>"
    exit 1
fi

SNAPSHOT_URL="gs://conduit-networks-snapshots/${NETWORK}/latest.tar"
SNAPSHOT_TOTAL_BYTES="$(
    gcloud --billing-project="$GCP_PROJECT" storage objects describe "$SNAPSHOT_URL" --format="value(size)" 2>/dev/null || true
)"
if [[ "$SNAPSHOT_TOTAL_BYTES" =~ ^[0-9]+$ ]]; then
    SNAPSHOT_TOTAL_SIZE="$(format_bytes "$SNAPSHOT_TOTAL_BYTES")"
fi

echo "Streaming snapshot from ${SNAPSHOT_URL} into ${DATADIR}..."
if [[ -n "$SNAPSHOT_TOTAL_SIZE" ]]; then
    echo "Snapshot size: ${SNAPSHOT_TOTAL_SIZE}."
fi
echo "Large database files may take a while to extract without additional output."
start_progress_monitor
trap stop_progress_monitor EXIT
trap 'stop_progress_monitor; exit 130' INT
trap 'stop_progress_monitor; exit 143' TERM
gcloud --billing-project="$GCP_PROJECT" storage cat "$SNAPSHOT_URL" |
    tar --no-same-owner --no-same-permissions -xf - -C "$DATADIR" --strip-components=1
chmod -R a+rwX "$DATADIR"
stop_progress_monitor
trap - EXIT INT TERM

echo "Snapshot restore complete."
