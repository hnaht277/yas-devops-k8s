#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/developer-build-config.yaml}"
REMOVE_YAS_CONFIGURATION="${REMOVE_YAS_CONFIGURATION:-false}"
DELETE_NAMESPACE="${DELETE_NAMESPACE:-false}"

for command_name in yq helm kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
done

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Config file not found: ${CONFIG_FILE}" >&2
  exit 1
fi

DEPLOY_NAMESPACE="$(yq -r '.deployment.namespace' "${CONFIG_FILE}")"
if [[ -z "${DEPLOY_NAMESPACE}" || "${DEPLOY_NAMESPACE}" == "null" ]]; then
  echo "deployment.namespace is required in ${CONFIG_FILE}" >&2
  exit 1
fi

service_count="$(yq -r '.services | length' "${CONFIG_FILE}")"
if [[ "${service_count}" -le 0 ]]; then
  echo "No services found in ${CONFIG_FILE}"
  exit 0
fi

echo "Cleaning developer build releases in namespace ${DEPLOY_NAMESPACE}"
echo "Helm releases in ${DEPLOY_NAMESPACE} (before cleanup):"
helm list -n "${DEPLOY_NAMESPACE}" -o table || true
echo "---"

for ((index=0; index<service_count; index++)); do
  release_name="$(yq -r ".services[${index}].release // .services[${index}].chart" "${CONFIG_FILE}")"
  echo "Uninstalling ${release_name}"
  helm uninstall "${release_name}" -n "${DEPLOY_NAMESPACE}" --ignore-not-found || true
done

if [[ "${REMOVE_YAS_CONFIGURATION}" == "true" ]]; then
  echo "Uninstalling yas-configuration"
  helm uninstall yas-configuration -n "${DEPLOY_NAMESPACE}" --ignore-not-found || true
fi

if [[ "${DELETE_NAMESPACE}" == "true" ]]; then
  echo "Deleting namespace ${DEPLOY_NAMESPACE}"
  kubectl delete namespace "${DEPLOY_NAMESPACE}" --ignore-not-found=true
fi

echo "Developer build cleanup completed."
