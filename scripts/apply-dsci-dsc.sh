#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENABLE_KUEUE="${1:-false}"

DSCI_FILE="${SCRIPT_DIR}/../resources/dsci.yaml"
DSC_FILE="${SCRIPT_DIR}/../resources/dsc.yaml"
CERT_MANAGER_OPERATORGROUP="${SCRIPT_DIR}/../resources/cert-manager-operatorgroup.yaml"
CERT_MANAGER_SUBSCRIPTION="${SCRIPT_DIR}/../resources/cert-manager-subscription.yaml"
KUEUE_SUBSCRIPTION="${SCRIPT_DIR}/../resources/kueue-subscription.yaml"
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
if [[ "$ENABLE_KUEUE" == "true" ]]; then
  # Install cert-manager (required by Kueue)
  if oc get csv -n cert-manager-operator 2>/dev/null | grep -q "cert-manager-operator.*Succeeded"; then
    echo "cert-manager Operator already installed, skipping..."
  else
    echo "Installing cert-manager Operator (required by Kueue)..."
    oc create namespace cert-manager-operator --dry-run=client -o yaml | oc apply -f -
    oc apply -f "$CERT_MANAGER_OPERATORGROUP"
    oc apply -f "$CERT_MANAGER_SUBSCRIPTION"
    
    echo "Waiting for cert-manager InstallPlan (timeout: 60s)..."
    SECONDS=0
    until oc get subscription openshift-cert-manager-operator -n cert-manager-operator -o jsonpath='{.status.installPlanRef.name}' 2>/dev/null | grep -q .; do
      if (( SECONDS > 60 )); then
        echo "ERROR: Timed out waiting for cert-manager InstallPlan"
        exit 1
      fi
      sleep 5
    done
    
    INSTALL_PLAN=$(oc get subscription openshift-cert-manager-operator -n cert-manager-operator -o jsonpath='{.status.installPlanRef.name}')
    echo "Approving InstallPlan: $INSTALL_PLAN"
    oc patch installplan "$INSTALL_PLAN" -n cert-manager-operator --type merge -p '{"spec":{"approved":true}}'
    
    echo "Waiting for cert-manager CSV to install (timeout: 300s)..."
    SECONDS=0
    until oc get csv -n cert-manager-operator 2>/dev/null | grep -q "cert-manager-operator.*Succeeded"; do
      if (( SECONDS > 300 )); then
        echo "ERROR: Timed out waiting for cert-manager Operator to install"
        exit 1
      fi
      sleep 10
    done
    echo "cert-manager Operator installed."
  fi

  # Install Kueue
  if oc get csv -n openshift-operators -l operators.coreos.com/kueue-operator.openshift-operators 2>/dev/null | grep -q Succeeded; then
    echo "Kueue Operator already installed, skipping..."
  else
    echo "Installing Red Hat Kueue Operator..."
    oc apply -f "$KUEUE_SUBSCRIPTION"
    
    echo "Waiting for Kueue InstallPlan (timeout: 60s)..."
    SECONDS=0
    until oc get subscription kueue-operator -n openshift-operators -o jsonpath='{.status.installPlanRef.name}' 2>/dev/null | grep -q .; do
      if (( SECONDS > 60 )); then
        echo "ERROR: Timed out waiting for Kueue InstallPlan"
        exit 1
      fi
      sleep 5
    done
    
    INSTALL_PLAN=$(oc get subscription kueue-operator -n openshift-operators -o jsonpath='{.status.installPlanRef.name}')
    echo "Approving InstallPlan: $INSTALL_PLAN"
    oc patch installplan "$INSTALL_PLAN" -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
    
    echo "Waiting for Kueue CSV to install (timeout: 300s)..."
    SECONDS=0
    until oc get csv -n openshift-operators -l operators.coreos.com/kueue-operator.openshift-operators 2>/dev/null | grep -q Succeeded; do
      if (( SECONDS > 300 )); then
        echo "ERROR: Timed out waiting for Kueue Operator to install"
        exit 1
      fi
      sleep 10
    done
    echo "Kueue Operator installed."
  fi
  export KUEUE_STATE="Unmanaged"
else
  export KUEUE_STATE="Removed"
fi
envsubst '$KUEUE_STATE' < "$DSC_FILE" | oc apply -f -
echo "DSC applied, waiting for deployment to be created..."
sleep 30

echo "Waiting for kserve-controller-manager to roll out in $APP_NS..."
oc rollout status deployment/kserve-controller-manager -n "$APP_NS" --timeout=300s
echo "kserve-controller-manager is ready"
