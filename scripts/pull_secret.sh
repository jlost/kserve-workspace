#!/bin/bash
set -e

# --- Usage ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Configure pull secrets for OpenShift clusters.

Modes:
  --global              Update the global cluster pull secret (default, for CRC)
  --namespace <ns>      Create namespace-scoped pull secret (for ROSA/HyperShift)

Options:
  --secret <name>       Secret name (default: pull-secret for global, my-pull-secret for namespace)
  --service-account <sa> Service account to link (default: default). Can specify multiple times.
  --auth-file <path>    Path to auth.json (default: ~/.config/containers/auth.json)
  -h, --help            Show this help message

Examples:
  # CRC: Update global cluster pull secret
  $(basename "$0") --global

  # ROSA: Create namespace-scoped secret and link to default SA
  $(basename "$0") --namespace kserve-ci-e2e-test

  # ROSA: Create secret and link to multiple service accounts
  $(basename "$0") --namespace my-ns --service-account default --service-account my-sa
EOF
  exit 0
}

# --- Config ---
YOUR_AUTH_FILE="$HOME/.config/containers/auth.json"
MODE="global"
TARGET_NAMESPACE=""
SECRET_NAME=""
SERVICE_ACCOUNTS=()

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --global)
      MODE="global"
      shift
      ;;
    --namespace|-n)
      MODE="namespace"
      TARGET_NAMESPACE="$2"
      shift 2
      ;;
    --secret|-s)
      SECRET_NAME="$2"
      shift 2
      ;;
    --service-account|--sa)
      SERVICE_ACCOUNTS+=("$2")
      shift 2
      ;;
    --auth-file)
      YOUR_AUTH_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# --- Validation ---
if [[ ! -f "$YOUR_AUTH_FILE" ]]; then
  echo "ERROR: Auth file not found: $YOUR_AUTH_FILE"
  exit 1
fi

if [[ "$MODE" == "namespace" && -z "$TARGET_NAMESPACE" ]]; then
  echo "ERROR: --namespace requires a namespace name"
  exit 1
fi

# Set defaults based on mode
if [[ "$MODE" == "global" ]]; then
  SECRET_NAME="${SECRET_NAME:-pull-secret}"
  TARGET_NAMESPACE="openshift-config"
else
  SECRET_NAME="${SECRET_NAME:-my-pull-secret}"
  [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 ]] && SERVICE_ACCOUNTS=("default")
fi

BACKUP=$(mktemp /tmp/pull-secret-backup.XXXXXX.json)
MERGED=$(mktemp /tmp/pull-secret-merged.XXXXXX.json)

# Cleanup temp files on exit (success or failure)
trap 'rm -f "$BACKUP" "$MERGED"' EXIT

# --- Functions ---
verify_registry() {
  local registry="$1"
  local display_name="$2"
  local source_file="$3"
  
  local expected_auth
  expected_auth=$(jq -r ".auths[\"$registry\"].auth // empty" "$YOUR_AUTH_FILE")
  
  if [[ -z "$expected_auth" ]]; then
    echo "  Warning: $display_name not in your auth file, skipping."
    return 0
  fi
  
  local actual_auth
  actual_auth=$(jq -r ".auths[\"$registry\"].auth // empty" "$source_file")
  
  if [[ "$expected_auth" == "$actual_auth" ]]; then
    echo "  OK: $display_name credentials found."
  else
    echo "  ERROR: $display_name credentials MISSING or mismatched."
    exit 1
  fi
}

check_managed_secret() {
  local managed
  managed=$(oc get secret/pull-secret -n openshift-config -o jsonpath='{.metadata.labels.hypershift\.openshift\.io/managed}' 2>/dev/null || true)
  if [[ "$managed" == "true" ]]; then
    echo ""
    echo "WARNING: This cluster's global pull secret is managed by HyperShift."
    echo "         Changes will be overwritten. Use --namespace mode instead."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 1
    fi
  fi
}

# --- Global Mode ---
run_global_mode() {
  echo "=== Global Pull Secret Mode ==="
  echo "Namespace: $TARGET_NAMESPACE"
  echo "Secret: $SECRET_NAME"
  echo ""

  check_managed_secret

  echo "--- 1. Reading Cluster Secret ---"
  oc get secret/$SECRET_NAME -n $TARGET_NAMESPACE --template='{{index .data ".dockerconfigjson" | base64decode}}' > "$BACKUP"

  echo "--- 2. Merging Credentials ---"
  # Merge your file ON TOP of the cluster secret, and duplicate docker.io key
  jq -s '
    (.[0] * .[1]) as $merged |
    $merged | 
    .auths["https://index.docker.io/v1/"] = $merged.auths["docker.io"]
  ' "$BACKUP" "$YOUR_AUTH_FILE" > "$MERGED"

  echo "--- 3. Verifying Merge ---"
  verify_registry "docker.io" "Docker Hub" "$MERGED"
  verify_registry "quay.io" "Quay.io" "$MERGED"

  echo "--- 4. Uploading to Cluster ---"
  oc set data secret/$SECRET_NAME -n $TARGET_NAMESPACE --from-file=.dockerconfigjson="$MERGED"

  echo ""
  echo "=== Success ==="
  echo "Global secret updated. Nodes will rolling update (may take 30+ min on ROSA)."
}

# --- Namespace Mode ---
run_namespace_mode() {
  echo "=== Namespace Pull Secret Mode ==="
  echo "Namespace: $TARGET_NAMESPACE"
  echo "Secret: $SECRET_NAME"
  echo "Service Accounts: ${SERVICE_ACCOUNTS[*]}"
  echo ""

  # Prepare the auth file with docker.io duplication
  echo "--- 1. Preparing Credentials ---"
  jq '
    .auths["https://index.docker.io/v1/"] = .auths["docker.io"]
  ' "$YOUR_AUTH_FILE" > "$MERGED"

  echo "--- 2. Verifying Credentials ---"
  verify_registry "docker.io" "Docker Hub" "$MERGED"
  verify_registry "quay.io" "Quay.io" "$MERGED"

  echo "--- 3. Creating/Updating Secret ---"
  # Check if secret exists
  if oc get secret "$SECRET_NAME" -n "$TARGET_NAMESPACE" &>/dev/null; then
    echo "  Updating existing secret..."
    oc create secret generic "$SECRET_NAME" \
      --from-file=.dockerconfigjson="$MERGED" \
      --type=kubernetes.io/dockerconfigjson \
      -n "$TARGET_NAMESPACE" \
      --dry-run=client -o yaml | oc apply -f -
  else
    echo "  Creating new secret..."
    oc create secret generic "$SECRET_NAME" \
      --from-file=.dockerconfigjson="$MERGED" \
      --type=kubernetes.io/dockerconfigjson \
      -n "$TARGET_NAMESPACE"
  fi

  echo "--- 4. Linking to Service Accounts ---"
  for sa in "${SERVICE_ACCOUNTS[@]}"; do
    echo "  Linking to service account: $sa"
    oc secrets link "$sa" "$SECRET_NAME" --for=pull -n "$TARGET_NAMESPACE" 2>/dev/null || \
      echo "    Warning: Could not link to $sa (may not exist yet)"
  done

  echo ""
  echo "=== Success ==="
  echo "Namespace secret created and linked."
  echo ""
  echo "To link additional service accounts later:"
  echo "  oc secrets link <sa-name> $SECRET_NAME --for=pull -n $TARGET_NAMESPACE"
}

# --- Main ---
if [[ "$MODE" == "global" ]]; then
  run_global_mode
else
  run_namespace_mode
fi
