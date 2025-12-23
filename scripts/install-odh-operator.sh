#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
OPERATOR_TYPE="${1:-odh}"  # odh or rhods
OPERATOR_VERSION="${2:-}"

# Set operator-specific variables
case "${OPERATOR_TYPE}" in
    odh|opendatahub)
        OPERATOR_NAME="opendatahub-operator"
        OPERATOR_SOURCE="community-operators"
        CONTROLLER_DEPLOYMENT="opendatahub-operator-controller-manager"
        OPERATOR_VERSION="${OPERATOR_VERSION:-3.2.0}"
        CSV_VERSION="v${OPERATOR_VERSION}"  # ODH uses 'v' prefix
        # Select channel based on major version
        if [[ "${OPERATOR_VERSION}" == 3.* ]]; then
            OPERATOR_CHANNEL="fast-3"
        else
            OPERATOR_CHANNEL="fast"
        fi
        ;;
    rhods|rhoai)
        OPERATOR_NAME="rhods-operator"
        OPERATOR_SOURCE="redhat-operators"
        CONTROLLER_DEPLOYMENT="rhods-operator-controller-manager"
        OPERATOR_VERSION="${OPERATOR_VERSION:-3.0.0}"
        CSV_VERSION="${OPERATOR_VERSION}"  # RHODS has no 'v' prefix
        # Select channel based on major version
        if [[ "${OPERATOR_VERSION}" == 3.* ]]; then
            OPERATOR_CHANNEL="fast-3.x"
        else
            OPERATOR_CHANNEL="fast"
        fi
        ;;
    *)
        echo "Error: Unknown operator type '${OPERATOR_TYPE}'"
        echo "Usage: $0 [odh|rhods] [version]"
        echo "  odh   - OpenDataHub operator (default)"
        echo "  rhods - Red Hat OpenShift AI operator"
        exit 1
        ;;
esac

echo "Installing ${OPERATOR_NAME} v${OPERATOR_VERSION}..."

# Export variables for envsubst
export OPERATOR_NAME OPERATOR_SOURCE OPERATOR_CHANNEL OPERATOR_VERSION CSV_VERSION

# Apply the subscription
envsubst < "${SCRIPT_DIR}/../resources/operator-subscription.yaml.tmpl" | oc apply -f -

echo "Waiting for install plan to be created..."
timeout 120 bash -c "
    while true; do
        install_plan=\$(oc get subscription ${OPERATOR_NAME} -n openshift-operators -o jsonpath=\"{.status.installplan.name}\" 2>/dev/null || echo \"\")
        if [[ -n \"\${install_plan}\" ]]; then
            echo \"  Found install plan: \${install_plan}\"
            break
        fi
        echo \"  Waiting for install plan...\"
        sleep 5
    done
"

echo "Approving install plan..."
install_plan=$(oc get subscription "${OPERATOR_NAME}" -n openshift-operators -o jsonpath="{.status.installplan.name}")
oc patch installplan "${install_plan}" -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
echo "Install plan approved"

echo "Waiting for ${OPERATOR_NAME} CSV to succeed..."
timeout 300 bash -c "
    while true; do
        phase=\$(oc get csv -n openshift-operators -l operators.coreos.com/${OPERATOR_NAME}.openshift-operators -o jsonpath=\"{.items[0].status.phase}\" 2>/dev/null || echo \"Pending\")
        echo \"  CSV phase: \${phase}\"
        if [[ \"\${phase}\" == \"Succeeded\" ]]; then
            break
        fi
        sleep 10
    done
"
echo "${OPERATOR_NAME} installed successfully"

echo "Waiting for ${CONTROLLER_DEPLOYMENT} deployment to be available..."
timeout 300 bash -c "
    # First wait for the deployment to exist
    while ! oc get deployment ${CONTROLLER_DEPLOYMENT} -n openshift-operators &>/dev/null; do
        echo \"  Waiting for ${CONTROLLER_DEPLOYMENT} deployment to be created...\"
        sleep 10
    done
    
    # Then wait for it to be available
    oc wait deployment/${CONTROLLER_DEPLOYMENT} -n openshift-operators \
        --for=condition=Available \
        --timeout=300s
"
echo "${CONTROLLER_DEPLOYMENT} is available"

echo "Done! ${OPERATOR_NAME} v${OPERATOR_VERSION} installed and ready."
