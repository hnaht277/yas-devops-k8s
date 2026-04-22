#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/developer-build-config.yaml}"
CLUSTER_CONFIG_FILE="${CLUSTER_CONFIG_FILE:-${SCRIPT_DIR}/cluster-config.yaml}"
CHARTS_DIR="${CHARTS_DIR:-${REPO_ROOT}/k8s/charts}"
RESULT_FILE="${RESULT_FILE:-${SCRIPT_DIR}/developer-build-result.txt}"
DEPLOY_YAS_CONFIGURATION="${DEPLOY_YAS_CONFIGURATION:-true}"

for command_name in yq helm kubectl git awk; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
done

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Config file not found: ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ ! -d "${CHARTS_DIR}" ]]; then
  echo "Charts directory not found: ${CHARTS_DIR}" >&2
  exit 1
fi

DEPLOY_NAMESPACE="$(yq -r '.deployment.namespace' "${CONFIG_FILE}")"
DOMAIN="$(yq -r '.deployment.domain' "${CONFIG_FILE}")"
IMAGE_REGISTRY="$(yq -r '.image.registry' "${CONFIG_FILE}")"
IMAGE_NAMESPACE="$(yq -r '.image.namespace' "${CONFIG_FILE}")"
IMAGE_PREFIX="$(yq -r '.image.prefix' "${CONFIG_FILE}")"
MAIN_TAG="$(yq -r '.image.mainTag // "main"' "${CONFIG_FILE}")"

if [[ -z "${DEPLOY_NAMESPACE}" || "${DEPLOY_NAMESPACE}" == "null" ]]; then
  echo "deployment.namespace is required in ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ -z "${DOMAIN}" || "${DOMAIN}" == "null" ]]; then
  echo "deployment.domain is required in ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ -z "${IMAGE_REGISTRY}" || "${IMAGE_REGISTRY}" == "null" ]]; then
  echo "image.registry is required in ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ -z "${IMAGE_NAMESPACE}" || "${IMAGE_NAMESPACE}" == "null" ]]; then
  echo "image.namespace is required in ${CONFIG_FILE}" >&2
  exit 1
fi

if [[ -z "${IMAGE_PREFIX}" || "${IMAGE_PREFIX}" == "null" ]]; then
  echo "image.prefix is required in ${CONFIG_FILE}" >&2
  exit 1
fi

REPO_URL="${GITHUB_REPO_URL:-}"
if [[ -z "${REPO_URL}" && -f "${CLUSTER_CONFIG_FILE}" ]]; then
  REPO_URL="$(yq -r '.jenkins.github.repoUrl // ""' "${CLUSTER_CONFIG_FILE}")"
fi

if [[ -z "${REPO_URL}" || "${REPO_URL}" == "null" ]]; then
  REPO_URL="$(git -C "${REPO_ROOT}" config --get remote.origin.url || true)"
fi

if [[ -z "${REPO_URL}" ]]; then
  echo "Unable to resolve repository URL from environment, cluster-config, or git remote." >&2
  exit 1
fi

AUTH_REPO_URL="${REPO_URL}"
if [[ -n "${GITHUB_USER:-}" && -n "${GITHUB_TOKEN:-}" && "${REPO_URL}" =~ ^https:// ]]; then
  AUTH_REPO_URL="${REPO_URL/https:\/\//https://${GITHUB_USER}:${GITHUB_TOKEN}@}"
fi

resolve_branch_tag() {
  local branch_name="$1"
  local commit_sha

  if [[ "${branch_name}" == "main" ]]; then
    echo "${MAIN_TAG}"
    return 0
  fi

  commit_sha="$(git ls-remote "${AUTH_REPO_URL}" "refs/heads/${branch_name}" | awk 'NR==1 {print $1}')"
  if [[ -z "${commit_sha}" ]]; then
    echo "Cannot resolve branch '${branch_name}' from ${REPO_URL}." >&2
    return 1
  fi

  echo "${commit_sha:0:12}"
}

if [[ "${DEPLOY_YAS_CONFIGURATION}" == "true" ]]; then
  echo "Deploying shared yas-configuration to namespace ${DEPLOY_NAMESPACE}"
  helm dependency build "${CHARTS_DIR}/yas-configuration" >/dev/null
  helm upgrade --install yas-configuration "${CHARTS_DIR}/yas-configuration" \
    --namespace "${DEPLOY_NAMESPACE}" \
    --create-namespace \
    --wait \
    --timeout 5m
fi

service_count="$(yq -r '.services | length' "${CONFIG_FILE}")"
if [[ "${service_count}" -le 0 ]]; then
  echo "No services found in ${CONFIG_FILE}" >&2
  exit 1
fi

mkdir -p "$(dirname "${RESULT_FILE}")"
{
  echo "service|chart|release|branch|image_tag|service_name|node_port|url"
} >"${RESULT_FILE}"

for ((index=0; index<service_count; index++)); do
  service_name="$(yq -r ".services[${index}].name" "${CONFIG_FILE}")"
  chart_name="$(yq -r ".services[${index}].chart" "${CONFIG_FILE}")"
  release_name="$(yq -r ".services[${index}].release // .services[${index}].chart" "${CONFIG_FILE}")"
  values_key="$(yq -r ".services[${index}].valuesKey" "${CONFIG_FILE}")"
  branch_param="$(yq -r ".services[${index}].branchParam" "${CONFIG_FILE}")"
  default_branch="$(yq -r ".services[${index}].defaultBranch // \"main\"" "${CONFIG_FILE}")"

  selected_branch="${!branch_param:-${default_branch}}"
  selected_branch="${selected_branch:-${default_branch}}"

  if [[ ! "${selected_branch}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "Invalid branch name '${selected_branch}' for ${service_name}" >&2
    exit 1
  fi

  image_tag="$(resolve_branch_tag "${selected_branch}")"
  image_repository="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/${IMAGE_PREFIX}-${service_name}"
  chart_path="${CHARTS_DIR}/${chart_name}"

  if [[ ! -d "${chart_path}" ]]; then
    echo "Chart path not found for ${service_name}: ${chart_path}" >&2
    exit 1
  fi

  echo "Deploying ${release_name} (${service_name}) from branch ${selected_branch} with tag ${image_tag}"
  helm dependency build "${chart_path}" >/dev/null
  helm upgrade --install "${release_name}" "${chart_path}" \
    --namespace "${DEPLOY_NAMESPACE}" \
    --create-namespace \
    --set-string "${values_key}.image.repository=${image_repository}" \
    --set-string "${values_key}.image.tag=${image_tag}" \
    --set "${values_key}.service.type=NodePort" \
    --set "${values_key}.ingress.enabled=false" \
    --wait \
    --timeout 5m

  service_k8s_name="$(kubectl get svc -n "${DEPLOY_NAMESPACE}" -l "app.kubernetes.io/instance=${release_name}" -o jsonpath='{.items[0].metadata.name}')"
  if [[ -z "${service_k8s_name}" ]]; then
    service_k8s_name="${release_name}"
  fi

  http_node_port="$(kubectl get svc "${service_k8s_name}" -n "${DEPLOY_NAMESPACE}" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')"
  if [[ -z "${http_node_port}" ]]; then
    http_node_port="$(kubectl get svc "${service_k8s_name}" -n "${DEPLOY_NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')"
  fi

  if [[ -z "${http_node_port}" ]]; then
    echo "Cannot resolve NodePort for service ${service_k8s_name}" >&2
    exit 1
  fi

  access_url="http://${DOMAIN}:${http_node_port}"
  echo "${service_name}|${chart_name}|${release_name}|${selected_branch}|${image_tag}|${service_k8s_name}|${http_node_port}|${access_url}" >>"${RESULT_FILE}"
done

echo "Developer build deployment completed."
echo "Result file: ${RESULT_FILE}"
if command -v column >/dev/null 2>&1; then
  column -t -s '|' "${RESULT_FILE}"
else
  cat "${RESULT_FILE}"
fi

echo "Add hosts entry on your machine: <worker-node-ip> ${DOMAIN}"
