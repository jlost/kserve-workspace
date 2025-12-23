#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DSCI_FILE="${SCRIPT_DIR}/../resources/dsci.yaml"
DESIRED_APP_NS=$(yq '.spec.applicationsNamespace' "$DSCI_FILE")
DESIRED_MON_NS=$(yq '.spec.monitoring.namespace' "$DSCI_FILE")

echo "Applying DSCI..."
if oc get dscinitialization default-dsci &>/dev/null; then
  CURRENT_APP_NS=$(oc get dscinitialization default-dsci -o jsonpath='{.spec.applicationsNamespace}')
  CURRENT_MON_NS=$(oc get dscinitialization default-dsci -o jsonpath='{.spec.monitoring.namespace}')
  
  if [[ "$CURRENT_APP_NS" != "$DESIRED_APP_NS" ]] || [[ "$CURRENT_MON_NS" != "$DESIRED_MON_NS" ]]; then
    echo "DSCI already exists with different immutable values:"
    echo "  applicationsNamespace: $CURRENT_APP_NS (desired: $DESIRED_APP_NS)"
    echo "  monitoring.namespace: $CURRENT_MON_NS (desired: $DESIRED_MON_NS)"
    echo "Keeping existing DSCI unchanged."
  else
    echo "DSCI already exists with matching namespaces, skipping apply."
  fi
else
  oc apply -f "$DSCI_FILE"
fi
APP_NS=$(oc get dscinitialization default-dsci -o jsonpath='{.spec.applicationsNamespace}')
echo "DSCI ready (applicationsNamespace: $APP_NS), waiting 5s..."
sleep 5

echo "Applying DSC..."
oc apply -f "${SCRIPT_DIR}/../resources/dsc.yaml"
echo "DSC applied, waiting for deployment to be created..."
sleep 10

echo "Waiting for kserve-controller-manager to roll out in $APP_NS..."
oc rollout status deployment/kserve-controller-manager -n "$APP_NS" --timeout=300s
echo "kserve-controller-manager is ready"
