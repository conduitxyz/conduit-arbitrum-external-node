#!/usr/bin/env bash

set -euo pipefail

NETWORK="${1:-${NETWORK:-}}"
PROGRESS_MONITOR_PID=""
SNAPSHOT_TOTAL_SIZE=""
STAGING_DIR=""

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

make_writable() {
    local target="$1"
    shift

    if ! chmod "$@" "$target"; then
        echo "Warning: unable to update permissions for ${target}."
        echo "If the node cannot write to this directory, fix host permissions and rerun setup or up."
    fi
}

ensure_datadir() {
    local parent

    parent="$(dirname "$DATADIR")"
    if ! mkdir -p "$DATADIR" "$RESTORE_DIR"; then
        echo "Error: unable to create snapshot data directory: ${DATADIR}"
        echo "The parent directory ${parent} is not writable by the current user."
        echo "Fix host permissions, for example:"
        echo "  sudo chown -R \$(id -u):\$(id -g) ${parent}"
        exit 1
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

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    stop_progress_monitor
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
    exit "$status"
}

if [[ -z "$NETWORK" ]]; then
    echo "Usage: ./download-snapshot.sh <network-slug>"
    echo "Or set NETWORK in the environment."
    exit 1
fi

CHAIN_NAME="${CHAIN_NAME:-$(read_env_value CHAIN_NAME)}"
DATADIR="${DATADIR:-./data/${CHAIN_NAME:-$NETWORK}}"
RESTORE_DIR="${RESTORE_DIR:-${DATADIR}/conduit-orbit-deployer/nitro}"

ensure_datadir

if [[ -d "${DATADIR}/l2chaindata" ]]; then
    echo "Error: snapshot data appears to be restored at the wrong level: ${DATADIR}/l2chaindata"
    echo "Nitro expects snapshot data under: ${RESTORE_DIR}"
    echo "Remove the broken data directory and rerun setup:"
    echo "  sudo rm -rf ${DATADIR}"
    exit 1
fi

if [[ -d "${RESTORE_DIR}/l2chaindata" ]]; then
    make_writable "$DATADIR" -R a+rwX
    echo "Snapshot restore skipped: ${RESTORE_DIR} already contains a database."
    exit 0
fi

if [[ -n "$(find "$RESTORE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Error: ${RESTORE_DIR} is not empty and has no restored l2chaindata database."
    echo "Move or remove its contents before restoring a snapshot."
    exit 1
fi

make_writable "$DATADIR" a+rwX
make_writable "$RESTORE_DIR" a+rwX

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
SNAPSHOT_METADATA="$(
    gcloud --billing-project="$GCP_PROJECT" storage objects describe "$SNAPSHOT_URL" \
        --format='value(generation,size,crc32c)'
)"
IFS=$'\t' read -r SNAPSHOT_GENERATION SNAPSHOT_TOTAL_BYTES SNAPSHOT_CRC32C <<< "$SNAPSHOT_METADATA"
if [[ ! "$SNAPSHOT_GENERATION" =~ ^[0-9]+$ || ! "$SNAPSHOT_TOTAL_BYTES" =~ ^[0-9]+$ || -z "$SNAPSHOT_CRC32C" ]]; then
    echo "Error: snapshot metadata must include generation, size and CRC32C."
    exit 1
fi
SNAPSHOT_TOTAL_SIZE="$(format_bytes "$SNAPSHOT_TOTAL_BYTES")"
SNAPSHOT_URL="${SNAPSHOT_URL}#${SNAPSHOT_GENERATION}"

# Keep the database out of the live path until the full stream is validated.
# This is one extracted copy on the same filesystem; no archive file is saved.
STAGING_DIR="$(mktemp -d "${RESTORE_DIR%/}.restore.XXXXXX")"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Streaming snapshot from ${SNAPSHOT_URL} into ${RESTORE_DIR}..."
echo "Snapshot size: ${SNAPSHOT_TOTAL_SIZE}; expected CRC32C: ${SNAPSHOT_CRC32C}."
echo "Large database files may take a while to extract without additional output."
start_progress_monitor
if CLOUDSDK_STORAGE_CHECK_HASHES=always gcloud --billing-project="$GCP_PROJECT" storage cp --do-not-decompress "$SNAPSHOT_URL" - | {
    if tar --no-same-owner --no-same-permissions -xf - -C "$STAGING_DIR" --strip-components=1; then
        # tar can stop at archive-end markers before EOF. Drain trailing bytes
        # so gcloud can validate the complete object rather than a short stream.
        cat > /dev/null
    else
        exit "$?"
    fi
}; then
    echo "Snapshot download checksum verified."
else
    echo "Error: snapshot download, checksum validation or extraction failed."
    exit 1
fi
if [[ ! -d "$STAGING_DIR/l2chaindata" ]]; then
    echo "Error: snapshot does not contain the expected l2chaindata database."
    exit 1
fi
stop_progress_monitor
make_writable "$STAGING_DIR" -R a+rwX
rmdir -- "$RESTORE_DIR"
mv -- "$STAGING_DIR" "$RESTORE_DIR"
STAGING_DIR=""

echo "Snapshot restore complete."
