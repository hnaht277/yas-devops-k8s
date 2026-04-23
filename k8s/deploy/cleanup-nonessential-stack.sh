#!/bin/bash
set -euo pipefail
set -x

# Cleanup components from setup-cluster.sh that are not required for minimal CD testing.
# Kept intentionally: postgres-operator/postgres, redis, keycloak, jenkins.

helm uninstall kafka-operator -n kafka || true
helm uninstall kafka-cluster -n kafka || true
helm uninstall akhq -n kafka || true

helm uninstall elastic-operator -n elasticsearch || true
helm uninstall elasticsearch-cluster -n elasticsearch || true

helm uninstall loki -n observability || true
helm uninstall tempo -n observability || true
helm uninstall opentelemetry-operator -n observability || true
helm uninstall opentelemetry-collector -n observability || true
helm uninstall promtail -n observability || true
helm uninstall prometheus -n observability || true
helm uninstall grafana-operator -n observability || true
helm uninstall grafana -n observability || true

helm uninstall cert-manager -n cert-manager || true
helm uninstall zookeeper -n zookeeper || true
helm uninstall pgadmin -n postgres || true

# Optional namespace cleanup for fully removing unused stacks.
if [[ "${DELETE_UNUSED_NAMESPACES:-false}" == "true" ]]; then
  kubectl delete namespace kafka --ignore-not-found=true
  kubectl delete namespace elasticsearch --ignore-not-found=true
  kubectl delete namespace observability --ignore-not-found=true
  kubectl delete namespace cert-manager --ignore-not-found=true
  kubectl delete namespace zookeeper --ignore-not-found=true
fi

echo "Cleanup completed."
echo "Set DELETE_UNUSED_NAMESPACES=true to remove empty namespaces too."
