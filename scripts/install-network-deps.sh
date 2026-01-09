#!/bin/bash

# Install network layer dependencies for Kind cluster
# Usage: install-network-deps.sh <network-layer>
#   network-layer: istio (default), istio-gatewayapi, envoy-gatewayapi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/hack/setup/common.sh"

NETWORK_LAYER="${1:-istio}"

echo "=========================================="
echo "Installing network dependencies"
echo "Network layer: ${NETWORK_LAYER}"
echo "=========================================="

# Parse network layer configuration
USES_GATEWAY_API=false
USES_ENVOY=false

case "$NETWORK_LAYER" in
  istio-gatewayapi)
    USES_GATEWAY_API=true
    ;;
  envoy-gatewayapi)
    USES_GATEWAY_API=true
    USES_ENVOY=true
    ;;
  istio|istio-ingress)
    # Default Istio ingress - nothing extra needed
    ;;
  *)
    echo "Unknown network layer: ${NETWORK_LAYER}"
    echo "Supported: istio, istio-ingress, istio-gatewayapi, envoy-gatewayapi"
    exit 1
    ;;
esac

# Install Gateway API CRDs if needed
if [[ $USES_GATEWAY_API == true ]]; then
  echo "Installing Gateway API CRDs..."
  "${REPO_ROOT}/hack/setup/infra/gateway-api/manage.gateway-api-crd.sh"
fi

# Install Envoy Gateway if needed
if [[ $USES_ENVOY == true ]]; then
  echo "Installing Envoy Gateway..."
  export GATEWAY_NETWORK_LAYER="envoy"
  "${REPO_ROOT}/hack/setup/infra/manage.envoy-gateway-helm.sh"
  "${REPO_ROOT}/hack/setup/infra/gateway-api/manage.gateway-api-gwclass.sh"
fi

# Create KServe Gateway for Gateway API
if [[ $USES_GATEWAY_API == true ]]; then
  echo "Creating KServe Gateway..."
  export GATEWAYCLASS_NAME="${NETWORK_LAYER%%-*}"
  "${REPO_ROOT}/hack/setup/infra/gateway-api/manage.gateway-api-gw.sh"
fi

echo "=========================================="
echo "Network dependencies installed for: ${NETWORK_LAYER}"
echo "=========================================="

