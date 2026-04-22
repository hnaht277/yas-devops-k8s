# Jenkins Kubernetes Agent Custom Image

This image extends `jenkins/inbound-agent` and pre-installs:

- kubectl
- helm
- yq
- git
- jq

## Build

Run from this folder:

docker build -t docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1 .

## Push

docker push docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1

## Local tool check

docker run --rm docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1 kubectl version --client

docker run --rm docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1 helm version

docker run --rm docker.io/<dockerhub-user>/jenkins-agent-k8s:0.1 yq --version

## Notes

- Keep tag immutable per release (for example: 0.1, 0.2, 2026-04-17).
- Update Helm values files in `k8s/deploy/jenkins` after pushing a new tag.
