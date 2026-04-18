# Jenkins Bootstrap on Minikube

This folder contains bootstrap files for Jenkins on Kubernetes with two profiles:

- local: Jenkins exposed by NodePort for a single developer machine.
- shared: Jenkins exposed by Ingress for team access through a shared host.

## Files

- values-local.yaml: Helm values for local mode.
- values-shared.yaml: Helm values for shared mode.
- rbac.yaml: ServiceAccount and namespace-scoped deploy permissions.
- jcasc.yaml: JCasC source file rendered by setup script and injected into Helm values.
- agent-image/Dockerfile: custom Jenkins inbound agent image with kubectl and helm.

## Required inputs

- GitHub repository URL.
- Jenkins UI credentials created manually after bootstrap:
  - ID: github-credentials (type: Username with password)
  - ID: docker-registry-creds (type: Username with password)

## Install

Run from k8s/deploy:

./setup-jenkins.sh

The script reads non-secret settings from cluster-config.yaml, renders JCasC from jcasc.yaml, and installs Jenkins with rendered values.

After Jenkins is up, create credentials in Jenkins UI:

Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials

- github-credentials: GitHub username + PAT
- docker-registry-creds: Docker Hub username + PAT

## Verify

kubectl get pods -n cicd
kubectl get svc -n cicd

Local mode URL:

minikube service jenkins -n cicd --url

## Custom Jenkins agent image (kubectl and helm)

For this repo, the default Jenkins Kubernetes cloud and pod template are configured in JCasC (`jcasc.yaml`), not only in UI.

1) Build and push custom image:

cd k8s/deploy/jenkins/agent-image
docker build -t docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1 .
docker push docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1

2) Update JCasC pod template image in:

- jcasc.yaml

Current keys:

- jenkins.clouds[].kubernetes.namespace
- jenkins.clouds[].kubernetes.templates[].serviceAccount
- jenkins.clouds[].kubernetes.templates[].containers[].image

3) Re-apply Jenkins release:

cd k8s/deploy
./setup-jenkins.sh

4) Validate in a Pipeline job:

sh 'kubectl version --client'
sh 'helm version'

## UI or values-local/values-shared?

- Default recommendation for your current setup: configure through JCasC so cloud and pod template are versioned and reproducible.
- Use Jenkins UI pod templates only when you need extra specialized templates per team/job.
- If a UI template and Helm-managed default template overlap, prefer one source of truth to avoid drift.

## Reset

Run from k8s/deploy:

./reset-jenkins.sh
