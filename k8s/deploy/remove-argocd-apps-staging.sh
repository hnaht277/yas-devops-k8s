#!/bin/bash
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

for command_name in kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
done

kubectl delete -f ./argocd/applicationset-staging.yaml --ignore-not-found
kubectl delete -f ./argocd/yas-configuration-staging.yaml --ignore-not-found
kubectl delete -f ./argocd/app-project.yaml --ignore-not-found

echo "Argo CD staging applications removed."