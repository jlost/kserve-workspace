#!/bin/bash
# Idempotent devspace debug launcher
# - Ensures devspace dev is running (for sync + port forwarding)
# - Always (re)starts dlv on :2345

set -e

NAMESPACE="${1:-opendatahub}"
KUBECONTEXT="${2:-crc-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COLOR_BLUE="\033[0;94m"
COLOR_GREEN="\033[0;92m"
COLOR_YELLOW="\033[0;93m"
COLOR_RED="\033[0;91m"
COLOR_RESET="\033[0m"

cd "$SCRIPT_DIR/.."

# Get devspace pod name (if exists)
get_devspace_pod() {
    kubectl get pods -n "$NAMESPACE" --context "$KUBECONTEXT" \
        -l control-plane=kserve-controller-manager \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -o '.*devspace.*' || true
}

# Check if devspace dev process is running
is_devspace_running() {
    pgrep -f "devspace dev.*--namespace.*$NAMESPACE" >/dev/null 2>&1
}

wait_for_pod_ready() {
    local pod="$1"
    local timeout=120
    local elapsed=0
    echo -e "${COLOR_YELLOW}Waiting for pod $pod to be ready...${COLOR_RESET}"
    while [ $elapsed -lt $timeout ]; do
        local ready=$(kubectl get pod "$pod" -n "$NAMESPACE" --context "$KUBECONTEXT" \
            -o jsonpath='{.status.containerStatuses[?(@.name=="manager")].ready}' 2>/dev/null)
        if [ "$ready" = "true" ]; then
            echo -e "${COLOR_GREEN}Pod ready${COLOR_RESET}"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo -e "${COLOR_RED}Timeout waiting for pod${COLOR_RESET}"
    return 1
}

wait_for_sync() {
    local pod="$1"
    local timeout=60
    local elapsed=0
    echo -e "${COLOR_YELLOW}Waiting for file sync...${COLOR_RESET}"
    while [ $elapsed -lt $timeout ]; do
        # Check if go.mod exists (indicates sync complete)
        if kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            test -f /app/go.mod 2>/dev/null; then
            echo -e "${COLOR_GREEN}Sync complete${COLOR_RESET}"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo -e "${COLOR_YELLOW}Sync may not be complete, continuing anyway...${COLOR_RESET}"
}

wait_for_port_forward() {
    local timeout=30
    local elapsed=0
    echo -e "${COLOR_YELLOW}Waiting for port forward...${COLOR_RESET}"
    while [ $elapsed -lt $timeout ]; do
        if nc -z localhost 2345 2>/dev/null; then
            echo -e "${COLOR_GREEN}Port forward ready${COLOR_RESET}"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo -e "${COLOR_YELLOW}Port forward not yet ready, dlv will establish it...${COLOR_RESET}"
}

start_devspace() {
    echo -e "${COLOR_GREEN}Starting devspace dev session...${COLOR_RESET}"
    # Start devspace in background
    devspace dev --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT" &
    DEVSPACE_PID=$!
    
    # Wait for the devspace pod to appear and become ready
    local timeout=120
    local elapsed=0
    local pod=""
    while [ $elapsed -lt $timeout ]; do
        pod=$(get_devspace_pod)
        if [ -n "$pod" ]; then
            echo -e "${COLOR_GREEN}Devspace pod: $pod${COLOR_RESET}"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ -z "$pod" ]; then
        echo -e "${COLOR_RED}Failed to create devspace pod${COLOR_RESET}"
        exit 1
    fi
    
    wait_for_pod_ready "$pod"
    wait_for_sync "$pod"
    wait_for_port_forward
    
    echo "$pod"
}

kill_existing_dlv() {
    local pod="$1"
    echo -e "${COLOR_YELLOW}Killing any existing dlv processes...${COLOR_RESET}"
    
    # Kill dlv and any debug binaries it spawned
    kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
        /bin/sh -c 'pkill -9 -f "dlv|__debug_bin" 2>/dev/null; exit 0' || true
    
    # Wait and verify dlv is dead
    local retries=5
    while [ $retries -gt 0 ]; do
        if ! kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            pgrep -f "dlv" >/dev/null 2>&1; then
            echo -e "${COLOR_GREEN}dlv killed${COLOR_RESET}"
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
        # Force kill again if still running
        kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            /bin/sh -c 'pkill -9 -f "dlv|__debug_bin" 2>/dev/null; exit 0' || true
    done
    echo -e "${COLOR_YELLOW}Warning: dlv may still be running${COLOR_RESET}"
}

start_dlv() {
    local pod="$1"
    
    # Always kill existing dlv first
    kill_existing_dlv "$pod"
    
    echo -e "${COLOR_BLUE}Starting delve debugger on :2345...${COLOR_RESET}"
    
    # Start dlv - this blocks until dlv exits
    kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
        /bin/sh -c 'cd /app/cmd/manager && exec dlv debug --listen=:2345 --headless --accept-multiclient --api-version=2 main.go --'
}

# Main logic
POD=$(get_devspace_pod)

if is_devspace_running; then
    echo -e "${COLOR_GREEN}Devspace dev is running${COLOR_RESET}"
    if [ -n "$POD" ]; then
        echo -e "${COLOR_GREEN}Using existing pod: $POD${COLOR_RESET}"
        wait_for_pod_ready "$POD"
    else
        echo -e "${COLOR_RED}Devspace running but no pod found, restarting...${COLOR_RESET}"
        pkill -f "devspace dev.*--namespace.*$NAMESPACE" || true
        sleep 2
        POD=$(start_devspace)
    fi
else
    echo -e "${COLOR_YELLOW}Devspace dev not running, starting...${COLOR_RESET}"
    # Kill any stale devspace pod since we need fresh port forwarding
    if [ -n "$POD" ]; then
        echo -e "${COLOR_YELLOW}Resetting stale devspace pod...${COLOR_RESET}"
        devspace reset pods --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT" 2>/dev/null || true
        sleep 2
    fi
    POD=$(start_devspace)
fi

# At this point POD should be set and ready, devspace should be running with port forward
start_dlv "$POD"
