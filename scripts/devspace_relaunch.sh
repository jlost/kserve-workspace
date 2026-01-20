#!/bin/bash
# Wrapper script for devspace debug that handles session conflicts
# Purges existing session if one exists, then starts fresh

set -e

NAMESPACE="${1:-opendatahub}"
KUBECONTEXT="${2:-crc-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COLOR_BLUE="\033[0;94m"
COLOR_GREEN="\033[0;92m"
COLOR_YELLOW="\033[0;93m"
COLOR_RESET="\033[0m"

cd "$SCRIPT_DIR/.."

# Reset pods to clean up any stale devspace state (this restarts the dev container)
echo -e "${COLOR_YELLOW}Resetting devspace pods to ensure clean state...${COLOR_RESET}"
devspace reset pods --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT" 2>/dev/null || true

# Small delay for pod to stabilize
sleep 2

# Start fresh devspace session
echo -e "${COLOR_GREEN}Starting devspace debug session...${COLOR_RESET}"
exec devspace dev -p debug --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT"
