#!/bin/bash
# Idempotent devspace debug launcher
# - Ensures devspace dev is running (for sync + port forwarding)
# - Always (re)starts dlv on :2345

set -e

NAMESPACE="${1:-opendatahub}"
KUBECONTEXT="${2:-crc-admin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Timeout for kubectl commands (prevents hanging when cluster is down)
KUBECTL_TIMEOUT="10s"
# Wrapper timeout with forced kill if command doesn't respond to SIGTERM
TIMEOUT_CMD="timeout --kill-after=5"

COLOR_BLUE="\033[0;94m"
COLOR_GREEN="\033[0;92m"
COLOR_YELLOW="\033[0;93m"
COLOR_RED="\033[0;91m"
COLOR_RESET="\033[0m"

cd "$SCRIPT_DIR/.."

# Check if cluster is reachable
check_cluster() {
    if ! $TIMEOUT_CMD 15 kubectl cluster-info --context "$KUBECONTEXT" --request-timeout="$KUBECTL_TIMEOUT" >/dev/null 2>&1; then
        echo -e "${COLOR_RED}ERROR: Cluster is unreachable (context: $KUBECONTEXT)${COLOR_RESET}" >&2
        echo -e "${COLOR_YELLOW}Please ensure the cluster is running and accessible.${COLOR_RESET}" >&2
        exit 1
    fi
}

# Get devspace pod name (if exists and Running)
get_devspace_pod() {
    # Only return pods that are Running (not Terminating/Pending)
    $TIMEOUT_CMD 15 kubectl get pods -n "$NAMESPACE" --context "$KUBECONTEXT" \
        --request-timeout="$KUBECTL_TIMEOUT" \
        -l control-plane=kserve-controller-manager \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -o '.*devspace.*' || true
}

# Check if devspace dev process is running
is_devspace_running() {
    pgrep -f "devspace dev.*--namespace.*$NAMESPACE" >/dev/null 2>&1
}

wait_for_pod_ready() {
    local pod="$1"
    local max_wait=120
    local elapsed=0
    echo -e "${COLOR_YELLOW}Waiting for pod $pod to be ready...${COLOR_RESET}" >&2
    while [ $elapsed -lt $max_wait ]; do
        local ready=$($TIMEOUT_CMD 15 kubectl get pod "$pod" -n "$NAMESPACE" --context "$KUBECONTEXT" \
            --request-timeout="$KUBECTL_TIMEOUT" \
            -o jsonpath='{.status.containerStatuses[?(@.name=="manager")].ready}' 2>/dev/null)
        if [ "$ready" = "true" ]; then
            echo -e "${COLOR_GREEN}Pod ready${COLOR_RESET}" >&2
            return 0
        fi
        # Check if cluster is still reachable
        if ! $TIMEOUT_CMD 10 kubectl cluster-info --context "$KUBECONTEXT" --request-timeout="$KUBECTL_TIMEOUT" >/dev/null 2>&1; then
            echo -e "${COLOR_RED}Cluster became unreachable${COLOR_RESET}" >&2
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo -e "${COLOR_RED}Timeout waiting for pod${COLOR_RESET}" >&2
    return 1
}

wait_for_sync() {
    local pod="$1"
    local max_wait=300  # 5 minutes max
    local elapsed=0
    local last_count=0
    local stable_count=0
    local required_stable=3  # File count must be stable for 3 consecutive checks
    
    echo -e "${COLOR_YELLOW}Waiting for file sync (this can take 1-2 minutes on first run)...${COLOR_RESET}" >&2
    
    # First wait for go.mod to appear (basic sanity check that sync has started)
    local gomod_timeout=180  # 3 minutes for initial file to appear
    while [ $elapsed -lt $gomod_timeout ]; do
        if $TIMEOUT_CMD 10 kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            test -f /app/go.mod 2>/dev/null; then
            echo -e "${COLOR_YELLOW}go.mod found, waiting for sync to stabilize...${COLOR_RESET}" >&2
            break
        fi
        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo -e "${COLOR_YELLOW}Waiting for sync to start... (${elapsed}s)${COLOR_RESET}" >&2
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    if [ $elapsed -ge $gomod_timeout ]; then
        echo -e "${COLOR_RED}Sync failed - go.mod not found after ${gomod_timeout}s${COLOR_RESET}" >&2
        return 1
    fi
    
    # Now wait for file count to stabilize (indicates sync is complete)
    echo -e "${COLOR_YELLOW}Waiting for sync to stabilize...${COLOR_RESET}" >&2
    while [ $elapsed -lt $max_wait ]; do
        # Count files in /app (excluding .git and vendor)
        local current_count
        current_count=$($TIMEOUT_CMD 15 kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            /bin/sh -c 'find /app -type f ! -path "*/\.git/*" ! -path "*/vendor/*" 2>/dev/null | wc -l' 2>/dev/null || echo "0")
        
        if [ "$current_count" = "$last_count" ] && [ "$current_count" != "0" ]; then
            stable_count=$((stable_count + 1))
            if [ $stable_count -ge $required_stable ]; then
                echo -e "${COLOR_GREEN}Sync complete ($current_count files)${COLOR_RESET}" >&2
                return 0
            fi
        else
            stable_count=0
            if [ "$current_count" != "$last_count" ]; then
                echo -e "${COLOR_YELLOW}Syncing... ($current_count files)${COLOR_RESET}" >&2
            fi
        fi
        
        last_count="$current_count"
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    echo -e "${COLOR_RED}Sync timeout - file count didn't stabilize after ${max_wait}s${COLOR_RESET}" >&2
    return 1
}

wait_for_port_forward() {
    local max_wait=30
    local elapsed=0
    echo -e "${COLOR_YELLOW}Waiting for port forward...${COLOR_RESET}" >&2
    while [ $elapsed -lt $max_wait ]; do
        if nc -z localhost 2345 2>/dev/null; then
            echo -e "${COLOR_GREEN}Port forward ready${COLOR_RESET}" >&2
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo -e "${COLOR_YELLOW}Port forward not yet ready, dlv will establish it...${COLOR_RESET}" >&2
}

start_devspace() {
    # Use stderr for progress messages so they're visible even in subshell
    echo -e "${COLOR_GREEN}Starting devspace dev session...${COLOR_RESET}" >&2
    
    # Start devspace in background
    # IMPORTANT: Redirect stdout/stderr to avoid blocking the subshell's $() capture
    # Devspace output goes to stderr so it's still visible
    devspace dev --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT" >&2 &
    DEVSPACE_PID=$!
    
    # Give devspace time to create/select its pod before we start looking
    echo -e "${COLOR_YELLOW}Waiting for devspace to initialize...${COLOR_RESET}" >&2
    sleep 8
    
    # Verify devspace started successfully (didn't immediately crash)
    if ! kill -0 "$DEVSPACE_PID" 2>/dev/null; then
        echo -e "${COLOR_RED}Devspace failed to start${COLOR_RESET}" >&2
        exit 1
    fi
    
    # Wait for the devspace pod to appear and become ready
    local max_wait=120
    local elapsed=0
    local pod=""
    while [ $elapsed -lt $max_wait ]; do
        # Check if devspace process is still running
        if ! kill -0 "$DEVSPACE_PID" 2>/dev/null; then
            echo -e "${COLOR_RED}Devspace process exited unexpectedly${COLOR_RESET}" >&2
            exit 1
        fi
        # Check if cluster is still reachable (with timeout wrapper)
        if ! $TIMEOUT_CMD 10 kubectl cluster-info --context "$KUBECONTEXT" --request-timeout="$KUBECTL_TIMEOUT" >/dev/null 2>&1; then
            echo -e "${COLOR_RED}Cluster became unreachable${COLOR_RESET}" >&2
            kill -9 "$DEVSPACE_PID" 2>/dev/null || true
            exit 1
        fi
        pod=$(get_devspace_pod)
        if [ -n "$pod" ]; then
            echo -e "${COLOR_GREEN}Devspace pod: $pod${COLOR_RESET}" >&2
            break
        fi
        echo -e "${COLOR_YELLOW}Waiting for devspace pod... (${elapsed}s)${COLOR_RESET}" >&2
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ -z "$pod" ]; then
        echo -e "${COLOR_RED}Failed to create devspace pod${COLOR_RESET}" >&2
        kill -9 "$DEVSPACE_PID" 2>/dev/null || true
        exit 1
    fi
    
    wait_for_pod_ready "$pod" || exit 1
    wait_for_sync "$pod" || { echo -e "${COLOR_RED}Sync failed - cannot continue${COLOR_RESET}" >&2; exit 1; }
    wait_for_port_forward
    
    echo "$pod"
}

kill_existing_dlv() {
    local pod="$1"
    echo -e "${COLOR_YELLOW}Killing any existing dlv processes...${COLOR_RESET}" >&2
    
    # Kill dlv and any debug binaries it spawned
    $TIMEOUT_CMD 10 kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
        /bin/sh -c 'pkill -9 -f "dlv|__debug_bin" 2>/dev/null; exit 0' || true
    
    # Wait and verify dlv is dead
    local retries=5
    while [ $retries -gt 0 ]; do
        if ! $TIMEOUT_CMD 5 kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            pgrep -f "dlv" >/dev/null 2>&1; then
            echo -e "${COLOR_GREEN}dlv killed${COLOR_RESET}" >&2
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
        # Force kill again if still running
        $TIMEOUT_CMD 5 kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
            /bin/sh -c 'pkill -9 -f "dlv|__debug_bin" 2>/dev/null; exit 0' || true
    done
    echo -e "${COLOR_YELLOW}Warning: dlv may still be running${COLOR_RESET}" >&2
}

start_dlv() {
    local pod="$1"
    
    echo -e "${COLOR_BLUE}Preparing to start debugger...${COLOR_RESET}"
    
    # Verify cluster is still reachable before starting dlv
    check_cluster
    
    # Always kill existing dlv first
    kill_existing_dlv "$pod"
    
    echo -e "${COLOR_BLUE}Starting delve debugger on :2345...${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Building and starting debugger (this may take 30-90 seconds)...${COLOR_RESET}"
    
    # Start dlv - this blocks until dlv exits
    # No timeout here since dlv is meant to run until debugger disconnects
    kubectl exec -n "$NAMESPACE" --context "$KUBECONTEXT" "$pod" -c manager -- \
        /bin/sh -c 'cd /app/cmd/manager && exec dlv debug --listen=:2345 --headless --accept-multiclient --api-version=2 main.go --'
}

# Main logic
echo -e "${COLOR_BLUE}Checking cluster connectivity...${COLOR_RESET}"
check_cluster

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
        $TIMEOUT_CMD 30 devspace reset pods --namespace "$NAMESPACE" --kube-context "$KUBECONTEXT" 2>/dev/null || true
        # Wait for old pods to be fully terminated
        echo -e "${COLOR_YELLOW}Waiting for old pods to terminate...${COLOR_RESET}"
        sleep 5
    fi
    POD=$(start_devspace)
fi

# At this point POD should be set and ready, devspace should be running with port forward
start_dlv "$POD"
