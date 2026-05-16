#!/bin/bash
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

for command_name in kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
done

kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${ARGOCD_NAMESPACE}" --server-side --force-conflicts -f "${ARGOCD_INSTALL_URL}"

kubectl -n "${ARGOCD_NAMESPACE}" wait deploy/argocd-server --for=condition=Available --timeout=300s
kubectl -n "${ARGOCD_NAMESPACE}" wait deploy/argocd-repo-server --for=condition=Available --timeout=300s
kubectl -n "${ARGOCD_NAMESPACE}" rollout status statefulset/argocd-application-controller --timeout=300s
kubectl -n "${ARGOCD_NAMESPACE}" wait deploy/argocd-applicationset-controller --for=condition=Available --timeout=300s



echo "Argo CD installed and GitOps applications applied."
echo "Login (local): kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8081:443"
echo "Admin password: kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
