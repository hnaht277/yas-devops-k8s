# Service Mesh (Istio + Kiali) — YAS Microservices

Hướng dẫn triển khai Istio Service Mesh với mTLS, Kiali visualization, retry policy và authorization policy cho ứng dụng YAS trên Kubernetes.

> **Lưu ý:** Cấu hình mặc định sử dụng namespace `yas` — tương thích với `deploy-yas-applications.sh`.
> Nếu dùng ArgoCD (namespace `dev`), set biến môi trường: `export YAS_NAMESPACE=dev` trước khi chạy.

## Mục lục

1. [Tổng quan](#tổng-quan)
2. [Prerequisites](#prerequisites)
3. [Bước 1: Cài đặt Istio + Kiali](#bước-1-cài-đặt-istio--kiali)
4. [Bước 2: Enable mTLS](#bước-2-enable-mtls)
5. [Bước 3: Cấu hình Retry Policy](#bước-3-cấu-hình-retry-policy)
6. [Bước 4: Cấu hình Authorization Policy](#bước-4-cấu-hình-authorization-policy)
7. [Bước 5: Kiểm tra và Test](#bước-5-kiểm-tra-và-test)
8. [Kiali Dashboard](#kiali-dashboard)
9. [Troubleshooting](#troubleshooting)

---

## Tổng quan

### Active Services

> **13 services được deploy:** product, cart, order, customer, inventory, tax,
> media, search, storefront-bff, storefront-ui, backoffice-bff, backoffice-ui, swagger-ui
>
> **Services tắt (không deploy):** payment, rating, location, promotion, sampledata

### Service Dependency Map (Active Services)

```
storefront-bff ──→ cart, customer, order, inventory, tax, product, media, search

backoffice-bff ──→ product, media, customer, order, inventory, tax, search

cart       → product, media
order      → cart, customer, product, tax
inventory  → product
customer   → (standalone)
tax        → (standalone)
search     → (standalone)
```

### Các thành phần Istio được sử dụng

| Resource | Mục đích |
|----------|----------|
| `PeerAuthentication` | Bắt buộc mTLS (STRICT mode) |
| `DestinationRule` | Client-side mTLS configuration |
| `VirtualService` | Retry policy, timeout |
| `AuthorizationPolicy` | Service-to-service access control |

---

## Prerequisites

- Kubernetes cluster (Minikube ≥16GB RAM)
- `kubectl` configured
- `helm` installed
- YAS services đã deploy (qua `deploy-yas-applications.sh` hoặc ArgoCD)
- `curl` (để test)

---

## Bước 1: Cài đặt Istio + Kiali

```bash
cd k8s/deploy
chmod +x setup-istio.sh
./setup-istio.sh
```

Script sẽ tự động:
1. Download Istio 1.24.2
2. Cài đặt Istio (demo profile) gồm istiod, ingress/egress gateway
3. Cài Kiali, Prometheus, Grafana (addons)
4. Label namespace `yas` với `istio-injection=enabled`
5. Restart tất cả pods để inject Istio sidecar

**Kiểm tra sidecar đã inject:**
```bash
kubectl get pods -n yas
# Mỗi pod phải có 2/2 READY (app container + istio-proxy)
```

---

## Bước 2: Enable mTLS

```bash
kubectl apply -f istio/istio-mtls.yaml
```

### File `istio-mtls.yaml` gồm:

**PeerAuthentication** — Server-side: chỉ chấp nhận mTLS traffic
```yaml
spec:
  mtls:
    mode: STRICT   # Từ chối plaintext, chỉ nhận mTLS
```

**DestinationRule** — Client-side: dùng ISTIO_MUTUAL khi gọi service
```yaml
spec:
  host: "*.yas.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL   # Tự động dùng cert do Istio cấp
```

**Kiểm tra mTLS:**
```bash
# Kiểm tra mTLS trên 1 pod
istioctl x describe pod <pod-name> -n yas

# Kết quả mong đợi: "STRICT" mTLS enforced
```

---

## Bước 3: Cấu hình Retry Policy

```bash
kubectl apply -f istio/istio-retry-policy.yaml
```

### Cấu hình retry cho mỗi service:

| Tham số | Giá trị | Giải thích |
|---------|---------|------------|
| `attempts` | 3 | Retry tối đa 3 lần |
| `perTryTimeout` | 5s | Mỗi lần retry timeout 5 giây |
| `retryOn` | 5xx, reset, connect-failure | Retry khi gặp lỗi 5xx/reset/mất kết nối |
| `timeout` | 20s | Tổng thời gian timeout cho request |

**Kiểm tra:**
```bash
kubectl get virtualservice -n yas
```

---

## Bước 4: Cấu hình Authorization Policy

```bash
kubectl apply -f istio/istio-authz-policy.yaml
```

### Chiến lược: deny-all → whitelist

1. **deny-all-default**: Chặn TẤT CẢ traffic mặc định
2. **Per-service ALLOW**: Chỉ cho phép caller đã được whitelist

### Ví dụ policy cho `search` service:

```yaml
# CHỈ storefront-bff và backoffice-bff được phép gọi search
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: search
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/yas/sa/storefront-bff"
              - "cluster.local/ns/yas/sa/backoffice-bff"
```

> **Lưu ý:** Service account name phải khớp với SA thực tế.
> Kiểm tra bằng: `kubectl get sa -n yas`

---

## Bước 5: Kiểm tra và Test

```bash
chmod +x istio/test-service-mesh.sh
./istio/test-service-mesh.sh
```

### Test cases:

| # | Test | Lệnh thủ công | Expected |
|---|------|----------------|----------|
| 1 | Sidecar injection | `kubectl get pods -n yas` | 2/2 READY |
| 2 | mTLS STRICT | `istioctl x describe pod <pod> -n yas` | STRICT |
| 3 | Allowed: cart→product | `kubectl exec -n yas <cart-pod> -c cart -- curl http://product:80/product/actuator/health` | HTTP 200 |
| 4 | Denied: temp→product | `kubectl run test --image=curlimages/curl -n yas --rm -it -- curl http://product:80/product/actuator/health` | HTTP 403 |
| 5 | Cross-ns block | `kubectl run test --image=curlimages/curl -n default --rm -it -- curl http://product.yas:80/product/actuator/health` | Timeout/403 |
| 6 | Retry policies | `kubectl get virtualservice -n yas` | ≥3 VirtualService |

---

## Kiali Dashboard

Mở Kiali để quan sát service mesh topology:

```bash
istioctl dashboard kiali
```

### Trong Kiali bạn sẽ thấy:
- **Graph**: Service dependency topology với mTLS lock icons
- **Workloads**: Chi tiết từng deployment với sidecar status
- **Services**: Traffic metrics cho từng service
- **Istio Config**: Validation status của PeerAuthentication, VirtualService, AuthorizationPolicy

---

## Troubleshooting

### Sidecar không inject
```bash
# Kiểm tra label namespace
kubectl get namespace yas --show-labels
# Phải có: istio-injection=enabled

# Force restart
kubectl rollout restart deployment -n yas

# Nếu dùng ArgoCD: ArgoCD sẽ tự re-sync, pod mới sẽ có sidecar
```

### mTLS errors
```bash
# Kiểm tra Istio proxy logs
kubectl logs <pod> -n yas -c istio-proxy --tail=50

# Kiểm tra cert
istioctl proxy-config secret <pod> -n yas
```

### AuthorizationPolicy không hoạt động
```bash
# Kiểm tra SA name thực tế
kubectl get sa -n yas
kubectl get pod <pod> -n yas -o jsonpath='{.spec.serviceAccountName}'

# Kiểm tra policy
istioctl x authz check <pod> -n yas
```

### Retry không kích hoạt
```bash
# Kiểm tra Envoy config
istioctl proxy-config route <pod> -n yas -o json | grep -A5 retry
```

---

## Cấu trúc file

```
k8s/deploy/
├── setup-istio.sh                     # Script cài Istio + Kiali
├── istio/
│   ├── istio-mtls.yaml                # mTLS (PeerAuthentication + DestinationRule)
│   ├── istio-retry-policy.yaml        # VirtualService retry config
│   ├── istio-authz-policy.yaml        # AuthorizationPolicy
│   ├── test-service-mesh.sh           # Test script
│   └── README-service-mesh.md         # README này
└── setup-cluster.sh                   # (existing, có thể gọi setup-istio.sh)
```
