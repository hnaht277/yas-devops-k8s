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

kubectl apply -f ./argocd/app-project.yaml
kubectl apply -f ./argocd/applicationset-dev.yaml
kubectl apply -f ./argocd/yas-configuration-dev.yaml

echo "Argo CD dev applications applied."