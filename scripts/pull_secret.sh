#!/bin/bash
set -e

# --- Config ---
YOUR_AUTH_FILE="$HOME/.config/containers/auth.json"
NAMESPACE="openshift-config"
SECRET="pull-secret"
BACKUP=$(mktemp /tmp/pull-secret-backup.XXXXXX.json)
MERGED=$(mktemp /tmp/pull-secret-merged.XXXXXX.json)

# Cleanup temp files on exit (success or failure)
trap 'rm -f "$BACKUP" "$MERGED"' EXIT

# --- Functions ---
verify_registry() {
  local registry="$1"
  local display_name="$2"
  
  # Extract the auth value from your source file
  local expected_auth
  expected_auth=$(jq -r ".auths[\"$registry\"].auth // empty" "$YOUR_AUTH_FILE")
  
  if [[ -z "$expected_auth" ]]; then
    echo "Warning: $display_name not in your auth file, skipping."
    return 0
  fi
  
  # Check if it exists in the merged file
  local merged_auth
  merged_auth=$(jq -r ".auths[\"$registry\"].auth // empty" "$MERGED")
  
  if [[ "$expected_auth" == "$merged_auth" ]]; then
    echo "OK: $display_name credentials found."
  else
    echo "ERROR: $display_name credentials MISSING or mismatched."
    exit 1
  fi
}

# --- Main ---
echo "--- 1. Reading Cluster Secret ---"
# Download and decode the current cluster secret
oc get secret/$SECRET -n $NAMESPACE --template='{{index .data ".dockerconfigjson" | base64decode}}' > "$BACKUP"

echo "--- 2. Merging Credentials ---"
# This jq command does three things:
# 1. Loads the cluster secret (.[0]) and your file (.[1])
# 2. Merges your file ON TOP of the cluster secret.
# 3. DUPLICATES the 'docker.io' credential to 'https://index.docker.io/v1/' 
#    (This guarantees the fix works regardless of how the node references Docker Hub)
jq -s '
  (.[0] * .[1]) as $merged |
  $merged | 
  .auths["https://index.docker.io/v1/"] = $merged.auths["docker.io"]
' "$BACKUP" "$YOUR_AUTH_FILE" > "$MERGED"

echo "--- 3. Verifying Merge ---"
verify_registry "docker.io" "Docker Hub"
verify_registry "quay.io" "Quay.io"

echo "--- 4. Uploading to Cluster ---"
oc set data secret/$SECRET -n $NAMESPACE --from-file=.dockerconfigjson="$MERGED"

echo "--- Success ---"
echo "Secret updated. Your nodes will now rolling update."
