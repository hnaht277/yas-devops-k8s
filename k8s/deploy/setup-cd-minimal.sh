#!/bin/bash
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

mapfile -t _cfg < <(yq -r '.postgresql.replicas, .postgresql.username, .postgresql.password, .redis.password' ./cluster-config.yaml)
POSTGRESQL_REPLICAS="${_cfg[0]}"
POSTGRESQL_USERNAME="${_cfg[1]}"
POSTGRESQL_PASSWORD="${_cfg[2]}"
REDIS_PASSWORD="${_cfg[3]}"

helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator || true
helm repo update

helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
  --create-namespace --namespace postgres

helm upgrade --install postgres ./postgres/postgresql \
  --create-namespace --namespace postgres \
  --set replicas="${POSTGRESQL_REPLICAS}" \
  --set username="${POSTGRESQL_USERNAME}" \
  --set password="${POSTGRESQL_PASSWORD}"

helm upgrade --install redis \
  --set auth.password="${REDIS_PASSWORD}" \
  oci://registry-1.docker.io/bitnamicharts/redis -n redis --create-namespace

chmod +x ./setup-keycloak.sh
chmod +x ./deploy-yas-configuration-minimal.sh

./setup-keycloak.sh

kubectl create namespace yas-dev --dry-run=client -o yaml | kubectl apply -f -

./deploy-yas-configuration-minimal.sh

echo "Minimal CD prerequisites deployed."
echo "Verify core components:"
echo "  kubectl get svc -n postgres | grep postgresql"
echo "  kubectl get pods -n keycloak"
echo "  kubectl get pods -n redis"
echo "  kubectl get cm,secret -n yas-dev | grep yas-"
