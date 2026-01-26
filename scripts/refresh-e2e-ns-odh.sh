#!/usr/bin/env bash
set -euo pipefail

# Older versions of ODH/RHOAI don't have the e2e scripts refactor, so use this temporarily as a fallback.

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$PROJECT_ROOT/test/scripts/openshift-ci"
source "$SCRIPT_DIR/common.sh"
readonly MARKERS="${1:-raw}"
readonly DEPLOYMENT_PROFILE="${2:-raw}"
validate_deployment_profile "${DEPLOYMENT_PROFILE}"
: "${NS:=opendatahub}"
: "${SKLEARN_IMAGE:=kserve/sklearnserver:latest}"
: "${STORAGE_INITIALIZER_IMAGE:=quay.io/opendatahub/kserve-storage-initializer:latest}"

oc delete ns kserve-ci-e2e-test || true

echo "Prepare CI namespace and install ServingRuntimes"
oc create ns kserve-ci-e2e-test || true

if [ "${DEPLOYMENT_PROFILE}" == "serverless" ]; then
  cat <<EOF | oc apply -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMember
metadata:
  name: default
  namespace: kserve-ci-e2e-test
spec:
  controlPlaneRef:
    namespace: istio-system
    name: basic
EOF
fi

oc apply -n kserve-ci-e2e-test -f <(
  sed "s|http://minio-service\.kserve:9000|http://minio-service.${NS}:9000|g" \
      "$PROJECT_ROOT/config/overlays/test/minio/minio-user-secret.yaml"
)

kustomize build $PROJECT_ROOT/config/overlays/odh-test/clusterresources |
  sed "s|kserve/sklearnserver:latest|${SKLEARN_IMAGE}|" |
  sed "s|kserve/storage-initializer:latest|${STORAGE_INITIALIZER_IMAGE}|" |
  oc apply -n kserve-ci-e2e-test -f -

# Add the enablePassthrough annotation to the ServingRuntimes, to let Knative to
# generate passthrough routes.
if [ "${DEPLOYMENT_PROFILE}" == "serverless" ]; then
  oc annotate servingruntimes -n kserve-ci-e2e-test --all serving.knative.openshift.io/enablePassthrough=true
fi

if [[ "${MARKERS}" =~ "kserve_on_openshift" ]]; then
  echo "Configuring minio tls"
  ${PROJECT_ROOT}/test/scripts/openshift-ci/tls/setup-minio-tls-custom-cert.sh
  ${PROJECT_ROOT}/test/scripts/openshift-ci/tls/setup-minio-tls-serving-cert.sh
fi