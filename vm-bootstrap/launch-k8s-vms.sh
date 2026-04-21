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

CONTROL_PLANE_NODES=(k8s-cp1 k8s-cp2 k8s-cp3)
WORKER_NODES=(k8s-worker1 k8s-worker2)

CP_CPU=2
CP_MEM=3G
CP_DISK=15G

WORKER_CPU=2
WORKER_MEM=2G
WORKER_DISK=15G

launch_vm() {
  local name=$1 cpu=$2 mem=$3 disk=$4
  echo ">>> Launching $name (cpu=$cpu, mem=$mem, disk=$disk)..."
  multipass launch \
    --name "$name" \
    --cpus "$cpu" \
    --memory "$mem" \
    --disk "$disk" \
    --cloud-init "$CLOUD_INIT" \
    "$CLOUD_IMAGE"
  echo ">>> $name is up."
}

echo "=== Launching Kubernetes control-plane nodes ==="
for node in "${CONTROL_PLANE_NODES[@]}"; do
  launch_vm "$node" "$CP_CPU" "$CP_MEM" "$CP_DISK"
done

echo "=== Launching Kubernetes worker nodes ==="
for node in "${WORKER_NODES[@]}"; do
  launch_vm "$node" "$WORKER_CPU" "$WORKER_MEM" "$WORKER_DISK"
done

echo ""
echo "=== All K8s VMs launched. Current status: ==="
multipass list
