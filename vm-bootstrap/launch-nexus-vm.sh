#!/usr/bin/env bash
set -euo pipefail

CLOUD_IMAGE="${CLOUD_IMAGE:-${1:-}}"
if [[ -z "$CLOUD_IMAGE" ]]; then
  echo "Error: CLOUD_IMAGE is required." >&2
  echo "Usage: CLOUD_IMAGE=<path> $0" >&2
  echo "   or: $0 <cloud-image-path>" >&2
  exit 1
fi
CLOUD_INIT="$(dirname "$0")/cloud-init.yml"

NEXUS_NODE="nexus"
NEXUS_CPU=4
NEXUS_MEM=8G
NEXUS_DISK=20G

echo ">>> Launching $NEXUS_NODE (cpu=$NEXUS_CPU, mem=$NEXUS_MEM, disk=$NEXUS_DISK)..."
multipass launch \
  --name "$NEXUS_NODE" \
  --cpus "$NEXUS_CPU" \
  --memory "$NEXUS_MEM" \
  --disk "$NEXUS_DISK" \
  --cloud-init "$CLOUD_INIT" \
  "$CLOUD_IMAGE"
echo ">>> $NEXUS_NODE is up."

echo ""
echo "=== Nexus VM launched. Current status: ==="
multipass list
