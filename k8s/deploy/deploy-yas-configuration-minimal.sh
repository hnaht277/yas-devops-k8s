#!/bin/bash
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Keep this isolated from the system deploy script: deploy to yas-dev and skip reloader.
helm repo add stakater https://stakater.github.io/stakater-charts || true
helm repo update

helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
  --namespace yas-dev --create-namespace \
  --set reloader.enabled=false
