#!/bin/bash
set -euo pipefail

# Read Jenkins bootstrap settings from cluster-config.yaml
mapfile -t JENKINS_CONFIG < <(
  yq -r '.jenkins.mode,
    .jenkins.namespace,
    .jenkins.releaseName,
    .jenkins.admin.username,
    .jenkins.admin.password,
    .jenkins.localUrl,
    .jenkins.sharedUrl,
    .jenkins.github.repoUrl' ./cluster-config.yaml
)

if [[ "${#JENKINS_CONFIG[@]}" -ne 8 ]]; then
  echo "Failed to read Jenkins configuration from cluster-config.yaml" >&2
  exit 1
fi

JENKINS_MODE="${JENKINS_CONFIG[0]}"
JENKINS_NAMESPACE="${JENKINS_CONFIG[1]}"
JENKINS_RELEASE_NAME="${JENKINS_CONFIG[2]}"
JENKINS_ADMIN_USERNAME="${JENKINS_CONFIG[3]}"
JENKINS_ADMIN_PASSWORD="${JENKINS_CONFIG[4]}"
JENKINS_LOCAL_URL="${JENKINS_CONFIG[5]}"
JENKINS_SHARED_URL="${JENKINS_CONFIG[6]}"
GITHUB_REPO_URL="${JENKINS_CONFIG[7]}"

if [[ "$JENKINS_MODE" == "shared" ]]; then
  VALUES_FILE="./jenkins/values-shared.yaml"
  JENKINS_URL="$JENKINS_SHARED_URL"
else
  VALUES_FILE="./jenkins/values-local.yaml"
  JENKINS_URL="$JENKINS_LOCAL_URL"
fi

export JENKINS_URL
export JENKINS_NAMESPACE
export JENKINS_RELEASE_NAME

JENKINS_VALUES_RENDERED="$(mktemp)"
JENKINS_JCASC_RENDERED="$(mktemp)"
trap 'rm -f "$JENKINS_VALUES_RENDERED" "$JENKINS_JCASC_RENDERED"' EXIT

envsubst < ./jenkins/jcasc.yaml > "$JENKINS_JCASC_RENDERED"
cp "$VALUES_FILE" "$JENKINS_VALUES_RENDERED"
yq -i '.controller.JCasC.defaultConfig = false' "$JENKINS_VALUES_RENDERED"

kubectl create namespace "$JENKINS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace yas-dev --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f ./jenkins/rbac.yaml

helm repo add jenkins https://charts.jenkins.io
helm repo update

helm upgrade --install "$JENKINS_RELEASE_NAME" jenkins/jenkins \
  --namespace "$JENKINS_NAMESPACE" \
  --values "$JENKINS_VALUES_RENDERED" \
  --set-file controller.JCasC.configScripts."yas-jenkins-config"="$JENKINS_JCASC_RENDERED" \
  --set controller.admin.username="$JENKINS_ADMIN_USERNAME" \
  --set controller.admin.password="$JENKINS_ADMIN_PASSWORD"

kubectl rollout status statefulset/"$JENKINS_RELEASE_NAME" -n "$JENKINS_NAMESPACE" --timeout=300s
kubectl get pods -n "$JENKINS_NAMESPACE"
kubectl get svc -n "$JENKINS_NAMESPACE"

echo "Jenkins mode: $JENKINS_MODE"
echo "For local mode, get URL: minikube service $JENKINS_RELEASE_NAME -n $JENKINS_NAMESPACE --url"
echo "GitHub repo: $GITHUB_REPO_URL"
echo "Create Jenkins UI credentials manually with IDs: github-credentials and docker-registry-creds"
