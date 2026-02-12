#!/bin/bash
# Interactive devspace dev with controller selection
# Usage: devspace_dev.sh <namespace> <kubecontext> [controller]
# Controller: kserve (default), llmisvc, or localmodel

set -e

NAMESPACE="$1"
KUBECONTEXT="$2"
CONTROLLER="${3:-kserve}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR/.."

# Validate controller
case "$CONTROLLER" in
    kserve|llmisvc|localmodel)
        ;;
    *)
        echo "Unknown controller: $CONTROLLER" >&2
        echo "Valid options: kserve, llmisvc, localmodel" >&2
        exit 1
        ;;
esac

# Build profile flags
# kserve uses default 'app' dev config, others need their profile
PROFILE_FLAG=""
[[ "$CONTROLLER" != "kserve" ]] && PROFILE_FLAG="--profile $CONTROLLER"

echo "Starting devspace dev for $CONTROLLER controller..."
# shellcheck disable=SC2086
exec devspace dev --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT" --profile interactive $PROFILE_FLAG
