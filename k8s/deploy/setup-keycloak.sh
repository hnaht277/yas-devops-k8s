
set -x

#Read configuration value from cluster-config.yaml file
read -rd '' DOMAIN POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
BOOTSTRAP_ADMIN_USERNAME BOOTSTRAP_ADMIN_PASSWORD \
KEYCLOAK_HOSTNAME \
KEYCLOAK_BACKOFFICE_REDIRECT_URL KEYCLOAK_STOREFRONT_REDIRECT_URL \
< <(yq -r '.domain,
  .postgresql.username, .postgresql.password,
  .keycloak.bootstrapAdmin.username, .keycloak.bootstrapAdmin.password,
    (.keycloak.hostname // ""),
  .keycloak.backofficeRedirectUrl, .keycloak.storefrontRedirectUrl' ./cluster-config.yaml)

if [[ -n "$KEYCLOAK_HOSTNAME" && "$KEYCLOAK_HOSTNAME" != "null" ]]; then
    EFFECTIVE_KEYCLOAK_HOSTNAME="$KEYCLOAK_HOSTNAME"
else
    EFFECTIVE_KEYCLOAK_HOSTNAME="identity.$DOMAIN"
fi

#Install CRD keycloak
kubectl create namespace keycloak
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n keycloak

# Install keycloak
helm upgrade --install keycloak ./keycloak/keycloak \
--namespace keycloak \
--set hostname="$EFFECTIVE_KEYCLOAK_HOSTNAME" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set bootstrapAdmin.username="$BOOTSTRAP_ADMIN_USERNAME" \
--set bootstrapAdmin.password="$BOOTSTRAP_ADMIN_PASSWORD" \
--set backofficeRedirectUrl="$KEYCLOAK_BACKOFFICE_REDIRECT_URL" \
--set storefrontRedirectUrl="$KEYCLOAK_STOREFRONT_REDIRECT_URL"
