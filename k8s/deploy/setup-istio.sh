#!/bin/bash
###############################################################################
# setup-istio.sh — Install Istio Service Mesh + Kiali for YAS on K8s
#
# Prerequisites:
#   - kubectl configured and pointing to your cluster
#   - helm installed
#   - Namespace 'yas' already exists (created by deploy-yas-applications.sh)
#
# Usage:
#   chmod +x setup-istio.sh && ./setup-istio.sh
###############################################################################
set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.24.2}"
YAS_NAMESPACE="${YAS_NAMESPACE:-yas}"

echo "============================================"
echo " [1/7] Downloading Istio ${ISTIO_VERSION}"
echo "============================================"
if [ ! -d "istio-${ISTIO_VERSION}" ]; then
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh -
else
  echo "Istio ${ISTIO_VERSION} already downloaded, skipping."
fi

export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"

echo "============================================"
echo " [2/7] Pre-flight check"
echo "============================================"
istioctl version --remote=false
istioctl x precheck

echo "============================================"
echo " [3/7] Installing Istio (demo profile)"
echo "============================================"
# demo profile includes: istiod, ingress gateway, egress gateway
istioctl install --set profile=demo -y

echo "============================================"
echo " [4/7] Verifying Istio installation"
echo "============================================"
kubectl get pods -n istio-system
echo "Checking Istio components are Running..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=120s

echo "============================================"
echo " [5/7] Installing Kiali, Prometheus, Grafana"
echo "============================================"
kubectl apply -f "istio-${ISTIO_VERSION}/samples/addons/prometheus.yaml"
kubectl apply -f "istio-${ISTIO_VERSION}/samples/addons/grafana.yaml"
# Kiali may need a retry due to CRD timing
kubectl apply -f "istio-${ISTIO_VERSION}/samples/addons/kiali.yaml" || \
  (sleep 10 && kubectl apply -f "istio-${ISTIO_VERSION}/samples/addons/kiali.yaml")

echo "Waiting for Kiali to be ready..."
kubectl rollout status deployment/kiali -n istio-system --timeout=180s

echo "============================================"
echo " [6/7] Enabling sidecar injection for '${YAS_NAMESPACE}'"
echo "============================================"
kubectl create namespace "${YAS_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${YAS_NAMESPACE}" istio-injection=enabled --overwrite

echo "============================================"
echo " [7/7] Restarting deployments to inject sidecars"
echo "============================================"
kubectl rollout restart deployment -n "${YAS_NAMESPACE}"

echo ""
echo "============================================"
echo " Istio Service Mesh installed successfully!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Wait for all pods to restart:  kubectl get pods -n ${YAS_NAMESPACE} -w"
echo "  2. Apply mTLS policy:             kubectl apply -f istio/istio-mtls.yaml"
echo "  3. Apply retry policies:          kubectl apply -f istio/istio-retry-policy.yaml"
echo "  4. Apply authz policies:          kubectl apply -f istio/istio-authz-policy.yaml"
echo "  5. Open Kiali dashboard:          istioctl dashboard kiali"
echo ""
