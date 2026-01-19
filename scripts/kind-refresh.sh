#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CONFIG="${SCRIPT_DIR}/../resources/kind.cluster.yaml"
CLUSTER_NAME="kind"

echo "=== Kind Cluster Refresh ==="

# 1. Stop and delete any existing kind cluster
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Deleting existing kind cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name "${CLUSTER_NAME}"
else
    echo "No existing kind cluster '${CLUSTER_NAME}' found."
fi

# 2. Create a fresh cluster from config
echo "Creating kind cluster from ${KIND_CONFIG}..."
kind create cluster --config "${KIND_CONFIG}"

echo "Cluster created successfully!"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# 3. Start cloud-provider-kind if not already running
# Note: Use -f to match full command line since process names are truncated to 15 chars
if pgrep -f "cloud-provider-kind" > /dev/null; then
    echo "cloud-provider-kind is already running."
else
    echo "Starting cloud-provider-kind in background..."
    nohup cloud-provider-kind > /tmp/cloud-provider-kind.log 2>&1 &
    echo "cloud-provider-kind started (PID: $!, logs: /tmp/cloud-provider-kind.log)"
fi

echo "=== Done ==="






