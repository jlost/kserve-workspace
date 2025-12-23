#!/usr/bin/env bash
set -euo pipefail

# Default to current namespace from oc/kubectl context
NAMESPACE="${1:-$(oc project -q 2>/dev/null || kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")}"

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "Error: HF_TOKEN environment variable is not set"
    exit 1
fi

echo "Creating HuggingFace token secret and service account in namespace: ${NAMESPACE}"

oc apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: hf-token-secret
type: Opaque
stringData:
  HF_TOKEN: ${HF_TOKEN}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hf-service-account
secrets:
  - name: hf-token-secret
EOF

echo "Done! Created:"
echo "  - Secret: hf-token-secret"
echo "  - ServiceAccount: hf-service-account"
