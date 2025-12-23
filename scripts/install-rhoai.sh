#!/bin/bash
set -e

echo "=== RHOAI 3.0.0 Installation Script for OpenShift Local ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if logged into OpenShift
if ! oc whoami &>/dev/null; then
    error "Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

info "Logged in as: $(oc whoami)"
info "Cluster: $(oc whoami --show-server)"

# Step 1: Enable default CatalogSources
info "Step 1: Enabling default CatalogSources..."
oc patch operatorhub cluster --type merge -p '{"spec":{"disableAllDefaultSources":false}}'

# Wait for catalog sources to be created
info "Waiting for CatalogSources to be available..."
sleep 5

# Check CatalogSource status
info "Current CatalogSource status:"
oc get catalogsource -n openshift-marketplace

# Step 2: Create the namespace for RHOAI operator
OPERATOR_NAMESPACE="redhat-ods-operator"

info "Step 2: Creating namespace ${OPERATOR_NAMESPACE}..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${OPERATOR_NAMESPACE}
  labels:
    openshift.io/cluster-monitoring: "true"
EOF

# Step 3: Create OperatorGroup
info "Step 3: Creating OperatorGroup..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: ${OPERATOR_NAMESPACE}
EOF

# Step 4: Create the Subscription for RHOAI 3.0.0
# The channel for 3.0.0 is typically 'fast' or 'stable-2.x'
# Package name is 'rhods-operator'
info "Step 4: Creating RHOAI Subscription..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: fast
  installPlanApproval: Automatic
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: rhods-operator.3.0.0
EOF

info "Subscription created. Waiting for operator installation..."

# Step 5: Wait for the InstallPlan to be created and check status
info "Step 5: Monitoring installation progress..."

echo ""
info "Checking for InstallPlan (may take a minute)..."
for i in {1..30}; do
    INSTALL_PLAN=$(oc get installplan -n ${OPERATOR_NAMESPACE} -o name 2>/dev/null | head -1)
    if [ -n "$INSTALL_PLAN" ]; then
        info "InstallPlan found: ${INSTALL_PLAN}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Show current status
info "Current Subscription status:"
oc get subscription -n ${OPERATOR_NAMESPACE}

info "Current InstallPlan status:"
oc get installplan -n ${OPERATOR_NAMESPACE} 2>/dev/null || warn "No InstallPlan yet"

info "Current CSV status:"
oc get csv -n ${OPERATOR_NAMESPACE} 2>/dev/null || warn "No CSV yet"

echo ""
info "=== Installation initiated ==="
info "Monitor progress with:"
echo "  oc get csv -n ${OPERATOR_NAMESPACE} -w"
echo "  oc get pods -n ${OPERATOR_NAMESPACE}"
echo ""
info "Once the operator is installed, create a DataScienceCluster:"
cat <<'EXAMPLE'
---
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    dashboard:
      managementState: Managed
    workbenches:
      managementState: Managed
    datasciencepipelines:
      managementState: Managed
    modelmeshserving:
      managementState: Managed
    kserve:
      managementState: Managed
    modelregistry:
      managementState: Managed
EXAMPLE

