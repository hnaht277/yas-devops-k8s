#!/bin/bash
set -euo pipefail
set -x

read -rd '' JENKINS_NAMESPACE JENKINS_RELEASE_NAME \
< <(yq -r '.jenkins.namespace, .jenkins.releaseName' ./cluster-config.yaml)

helm uninstall "$JENKINS_RELEASE_NAME" -n "$JENKINS_NAMESPACE" || true
kubectl delete sa jenkins-deployer -n "$JENKINS_NAMESPACE" --ignore-not-found=true
kubectl delete rolebinding jenkins-yas-deployer-binding -n yas-dev --ignore-not-found=true
kubectl delete role jenkins-yas-deployer -n yas-dev --ignore-not-found=true

echo "Jenkins release removed."
echo "If you want to remove namespace too, run: kubectl delete namespace $JENKINS_NAMESPACE"
