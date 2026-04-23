#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/developer-build-config.yaml}"
CLUSTER_CONFIG_FILE="${CLUSTER_CONFIG_FILE:-${SCRIPT_DIR}/cluster-config.yaml}"
CHARTS_DIR="${CHARTS_DIR:-${REPO_ROOT}/k8s/charts}"
RESULT_FILE="${RESULT_FILE:-${SCRIPT_DIR}/developer-build-result.txt}"
DEPLOY_YAS_CONFIGURATION="${DEPLOY_YAS_CONFIGURATION:-true}"

for command_name in yq helm kubectl curl sed; do
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

normalize_branch_to_tag() {
  local branch_name="$1"
  local normalized

  normalized="$(echo "${branch_name}" | tr '[:upper:]' '[:lower:]')"
  normalized="${normalized//\//-}"
  normalized="$(echo "${normalized}" | sed -E 's/[^a-z0-9_.-]+/-/g; s/^[.-]+//; s/[.-]+$//; s/-+/-/g')"

  if [[ -z "${normalized}" ]]; then
    normalized="detached"
  fi

  if [[ ! "${normalized}" =~ ^[a-z0-9_] ]]; then
    normalized="b-${normalized}"
  fi

  normalized="${normalized:0:128}"
  normalized="$(echo "${normalized}" | sed -E 's/[.-]+$//')"

  if [[ -z "${normalized}" ]]; then
    normalized="detached"
  fi

  echo "${normalized}"
}

is_valid_docker_tag() {
  local tag="$1"
  [[ "${tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]
}

image_tag_exists() {
  local image_repository="$1"
  local tag="$2"
  local registry_normalized
  local repository_path
  local status_code

  registry_normalized="${IMAGE_REGISTRY#https://}"
  registry_normalized="${registry_normalized#http://}"

  if [[ "${registry_normalized}" == "docker.io" || "${registry_normalized}" == "index.docker.io" || "${registry_normalized}" == "registry-1.docker.io" ]]; then
    repository_path="${image_repository#docker.io/}"
    repository_path="${repository_path#index.docker.io/}"
    repository_path="${repository_path#registry-1.docker.io/}"

    status_code="$(curl -s -o /dev/null -w '%{http_code}' "https://registry.hub.docker.com/v2/repositories/${repository_path}/tags/${tag}" || true)"
    if [[ "${status_code}" == "200" ]]; then
      return 0
    fi

    if [[ "${status_code}" == "401" || "${status_code}" == "429" ]]; then
      echo "Warning: cannot validate tag '${tag}' for ${image_repository} (HTTP ${status_code}); assume exists for safety." >&2
      return 0
    fi

    return 1
  fi

  echo "Warning: tag existence check is implemented for docker.io only; skipping strict check for registry '${IMAGE_REGISTRY}'." >&2
  return 0
}

resolve_image_tag() {
  local service_name="$1"
  local branch_name="$2"
  local manual_tag="$3"
  local image_repository="$4"
  local branch_tag

  if [[ -n "${manual_tag}" ]]; then
    if ! is_valid_docker_tag "${manual_tag}"; then
      echo "Invalid manual tag '${manual_tag}' for ${service_name}." >&2
      return 1
    fi

    if image_tag_exists "${image_repository}" "${manual_tag}"; then
      echo "${manual_tag}|manual"
      return 0
    fi

    echo "Manual tag '${manual_tag}' not found for ${service_name} in ${image_repository}." >&2
    return 1
  fi

  branch_tag="$(normalize_branch_to_tag "${branch_name}")"
  if image_tag_exists "${image_repository}" "${branch_tag}"; then
    echo "${branch_tag}|branch:${branch_name}"
    return 0
  fi

  if image_tag_exists "${image_repository}" "${MAIN_TAG}"; then
    echo "${MAIN_TAG}|fallback-main"
    return 0
  fi

  echo "No usable image tag found for ${service_name}. Tried branch tag '${branch_tag}' and fallback main tag '${MAIN_TAG}' in ${image_repository}." >&2
  return 1
}

if [[ "${DEPLOY_YAS_CONFIGURATION}" == "true" ]]; then
  echo "Deploying shared yas-configuration to namespace ${DEPLOY_NAMESPACE}"
  helm dependency build "${CHARTS_DIR}/yas-configuration" >/dev/null
  helm upgrade --install yas-configuration "${CHARTS_DIR}/yas-configuration" \
    --namespace "${DEPLOY_NAMESPACE}" \
    --set reloader.enabled=false \
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
  echo "service|chart|release|branch|tag_param|manual_tag|image_tag|tag_source|service_name|node_port|url"
} >"${RESULT_FILE}"

for ((index=0; index<service_count; index++)); do
  service_name="$(yq -r ".services[${index}].name" "${CONFIG_FILE}")"
  chart_name="$(yq -r ".services[${index}].chart" "${CONFIG_FILE}")"
  release_name="$(yq -r ".services[${index}].release // .services[${index}].chart" "${CONFIG_FILE}")"
  values_key="$(yq -r ".services[${index}].valuesKey" "${CONFIG_FILE}")"
  branch_param="$(yq -r ".services[${index}].branchParam" "${CONFIG_FILE}")"
  tag_param="$(yq -r ".services[${index}].tagParam // \"\"" "${CONFIG_FILE}")"
  default_branch="$(yq -r ".services[${index}].defaultBranch // \"main\"" "${CONFIG_FILE}")"

  if [[ -z "${tag_param}" || "${tag_param}" == "null" ]]; then
    if [[ "${branch_param}" == *_BRANCH ]]; then
      tag_param="${branch_param%_BRANCH}_TAG"
    else
      tag_param="${branch_param}_TAG"
    fi
  fi

  selected_branch="${!branch_param:-${default_branch}}"
  selected_branch="${selected_branch:-${default_branch}}"
  manual_tag="${!tag_param:-}"

  if [[ ! "${selected_branch}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "Invalid branch name '${selected_branch}' for ${service_name}" >&2
    exit 1
  fi

  if [[ -n "${manual_tag}" ]] && [[ ! "${manual_tag}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid tag '${manual_tag}' for ${service_name}." >&2
    exit 1
  fi

  image_repository="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/${IMAGE_PREFIX}-${service_name}"
  resolved_tag_info="$(resolve_image_tag "${service_name}" "${selected_branch}" "${manual_tag}" "${image_repository}")"
  image_tag="${resolved_tag_info%%|*}"
  tag_source="${resolved_tag_info#*|}"
  chart_path="${CHARTS_DIR}/${chart_name}"

  if [[ ! -d "${chart_path}" ]]; then
    echo "Chart path not found for ${service_name}: ${chart_path}" >&2
    exit 1
  fi

  echo "Deploying ${release_name} (${service_name})"
  echo "  branch param ${branch_param}: ${selected_branch}"
  echo "  tag param ${tag_param}: ${manual_tag:-<empty>}"
  echo "  resolved image tag: ${image_tag} (source: ${tag_source})"

  helm dependency build "${chart_path}" >/dev/null
  helm upgrade --install "${release_name}" "${chart_path}" \
    --namespace "${DEPLOY_NAMESPACE}" \
    --set-string "${values_key}.image.repository=${image_repository}" \
    --set-string "${values_key}.image.tag=${image_tag}" \
    --set "${values_key}.service.type=NodePort" \
    --set "${values_key}.ingress.enabled=false" \
    --set "${values_key}.serviceMonitor.enabled=false" \
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
  echo "${service_name}|${chart_name}|${release_name}|${selected_branch}|${tag_param}|${manual_tag}|${image_tag}|${tag_source}|${service_k8s_name}|${http_node_port}|${access_url}" >>"${RESULT_FILE}"
done

echo "Developer build deployment completed."
echo "Result file: ${RESULT_FILE}"
if command -v column >/dev/null 2>&1; then
  column -t -s '|' "${RESULT_FILE}"
else
  cat "${RESULT_FILE}"
fi

echo "Add hosts entry on your machine: <worker-node-ip> ${DOMAIN}"
