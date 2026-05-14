# YAS K8S Deployment
## Resource cluster installation reference
- **Postgresql:** https://github.com/zalando/postgres-operator
- **Elasticsearch:** https://github.com/elastic/cloud-on-k8s
- **Kafka:** https://github.com/strimzi/strimzi-kafka-operator
- **Debezium Connect:** https://debezium.io/documentation/reference/stable/operations/kubernetes.html
- **Keycloak:** https://www.keycloak.org/operator/installation
- **Redis:** https://artifacthub.io/packages/helm/bitnami/redis
- **Reloader:** https://github.com/stakater/Reloader
- **Prometheus:** https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- **Grafana:** https://github.com/grafana-operator/grafana-operator
- **Loki:** https://github.com/grafana/loki/tree/main/production/helm/loki
- **Tempo:** https://github.com/grafana/helm-charts/tree/main/charts/tempo
- **Promtail:** https://github.com/grafana/helm-charts/tree/main/charts/promtail
- **Opentelemetry:** https://github.com/open-telemetry/opentelemetry-operator
## Local installation steps
- Require a minikube node minimum 16G memory and 40G disk space and run on Ubuntu operator
```shell
minikube start --disk-size='40000mb' --memory='16g'
```
- Enable ingress addon
```shell
minikube addons enable ingress
```
- Install helm
  https://helm.sh/
- Install yq (the tool read, update yaml file)
  https://github.com/mikefarah/yq
- Goto `k8s-deployment` folder
- Execute [setup-keycloak.sh](setup-cluster.sh) to set up keycloak as the Identity and Access Management server.
```shell
./setup-keycloak.sh
```
- Execute [setup-redis.sh](setup-cluster.sh) to set up Redis as the server to store sessions for backends.
```shell
./setup-redis.sh
```
- Execute [setup-jenkins.sh](setup-jenkins.sh) to set up Jenkins on Minikube.
```shell
./setup-jenkins.sh
```
- Execute [reset-jenkins.sh](reset-jenkins.sh) to uninstall Jenkins bootstrap when needed.
```shell
./reset-jenkins.sh
```
- Optional local test (without Jenkins): run [developer-build.sh](developer-build.sh) to deploy developer_build workload into `yas-dev` with NodePort services.
```shell
bash ./developer-build.sh
```
- Optional local cleanup: run [cleanup-developer-build.sh](cleanup-developer-build.sh) to remove developer_build releases.
```shell
bash ./cleanup-developer-build.sh
```
- Execute [setup-cluster.sh](setup-cluster.sh) to set up severs: `postgresql`, `elasticsearch`, `kafka`, `debezium connect`
```shell
./setup-cluster.sh
```
- Verify all servers run successful on namespaces: `postgres`, `elasticsearch`, `kafka`, `keycloak`
- After all above servers are running status, execute  [deploy-yas-applications.sh](deploy-yas-applications.sh) file to deploy all of yas applications to `yas` namespace
```shell
./deploy-yas-applications
```
All of YAS microservice deployed in `yas` namespace
- Setup hosts file
edit host file `/etc/hots`
```shell
192.168.49.2 pgoperator.yas.local.com
192.168.49.2 pgadmin.yas.local.com
192.168.49.2 akhq.yas.local.com
192.168.49.2 kibana.yas.local.com
192.168.49.2 identity.yas.local.com
192.168.49.2 backoffice.yas.local.com
192.168.49.2 storefront.yas.local.com
192.168.49.2 grafana.yas.local.com

```
`192.168.49.2` is ip of minikbe node use this command line to get the ip of minikube
```shell
minikube ip
```
## Keycloak bootstrap admin credentials
The username and password of Keycloak admin user store in the `keycloak-credentials` secret, `keycloak` namespace
use bellow command line to get the admin password
```shell
kubectl get secret keycloak-credentials -n keycloak -o jsonpath="{.data.password}" | base64 --decode
```
bootstrap admin is a temporary admin user. To harden security, create a permanent admin account and delete the temporary one.
## Cluster configuration
All configuration of cluster is setting on [cluster-config.yaml](cluster-config.yaml) in folder k8s-deploy

## Jenkins bootstrap configuration
Jenkins bootstrap supports two modes configured in `cluster-config.yaml`:

- `local`: expose Jenkins by NodePort and access it from local machine.
- `shared`: expose Jenkins by Ingress to support a shared Minikube host for the team.

Jenkins bootstrap assets are stored at [jenkins](./jenkins/README.md).
JCasC source is defined in [jcasc.yaml](./jenkins/jcasc.yaml) and rendered by setup script during install.
GitHub and registry credentials are managed in Jenkins UI (credential IDs are documented in jenkins/README.md), not stored in cluster-config.yaml.
Default Kubernetes agent image for Jenkins is configured in values files and built from [agent-image](./jenkins/agent-image/README.md).

## Yas configuration 
All configurations of YAS application putted in the yas-configuration helm chart.

Bellow is the values of [values.yaml](../charts/yas-configuration/values.yaml)

## Yas helm charts
All charts of Yas application situated in `charts` folder

To Install the Yas helm charts access to [https://nashtech-garage.github.io/yas/](https://nashtech-garage.github.io/yas/)

## Observability
The Yas observability follows the OpenTelemetry standard recommendation.

### Architecture
- **Logs**: Promtail collects logs from all applications and sends them directly to Loki
- **Traces**: Applications send trace data to OpenTelemetry Collector, which forwards to Tempo
- **Metrics**: Prometheus scrapes metrics from applications and exporters
- **Visualization**: Grafana provides unified dashboards for logs, traces, and metrics

### Components
- **Loki**: Log aggregation system
- **Tempo**: Distributed tracing backend
- **Prometheus**: Metrics collection and storage (part of kube-prometheus-stack)
- **Grafana**: Visualization and dashboarding UI
- **Promtail**: Log shipping agent (DaemonSet on each node)
- **OpenTelemetry Collector**: Trace collection and forwarding

View detailed configuration:
- OpenTelemetry Collector: [opentelemetry/values.yaml](./observability/opentelemetry/values.yaml)
- Prometheus + Grafana: [prometheus.values.yaml](./observability/prometheus.values.yaml)
- Loki: [loki.values.yaml](./observability/loki.values.yaml)
- Promtail: [promtail.values.yaml](./observability/promtail.values.yaml)

### Setup
The observability stack is automatically deployed by [setup-cluster.sh](setup-cluster.sh). No manual steps required.

**Note**: Grafana passwords are managed via Kubernetes Secret and sourced from [cluster-config.yaml](cluster-config.yaml). The setup script automatically creates the `grafana-secrets` Secret in the `observability` namespace.

### How to view logs in Grafana
1. Access Grafana at `http://grafana.yas.local.com` (after setting up hosts file)
2. On the left menu select `Explore` → select `Loki` datasource
3. Select Label filters:
   - `namespace`: filter by Kubernetes namespace
   - `container`: filter by application/container name
4. Loki supports trace correlation - click on a traceId to jump to Tempo

### How to view traces in Grafana
1. In Grafana, select `Explore` → select `Tempo` datasource
2. Search by traceId or use the Node Graph to visualize request flows
3. Click on spans to see detailed timing and logs

### How to view metrics in Grafana
1. In Grafana, go to `Dashboards`
2. Pre-configured dashboards are available for:
   - JVM metrics (Hikari CP, JVM memory, threads)
   - Kubernetes cluster metrics
   - Node exporter metrics 

## Service Mesh (Istio + Kiali)
Setup Istio service mesh with mTLS, authorization policies, retry policies, and Kiali visualization.

See full documentation: [istio/README-service-mesh.md](istio/README-service-mesh.md)

Quick start:
```shell
# Install Istio + Kiali
chmod +x setup-istio.sh && ./setup-istio.sh

# Apply mTLS, retry, and authorization policies
kubectl apply -f istio/istio-mtls.yaml
kubectl apply -f istio/istio-retry-policy.yaml
kubectl apply -f istio/istio-authz-policy.yaml

# Run tests
chmod +x istio/test-service-mesh.sh && ./istio/test-service-mesh.sh

# Open Kiali dashboard
istioctl dashboard kiali
```

