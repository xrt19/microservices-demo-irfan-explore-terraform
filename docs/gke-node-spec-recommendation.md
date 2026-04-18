# GKE Node Spec Recommendation

## Cluster Constraints

| Parameter | Value |
|---|---|
| Environment | Production |
| Platform | GKE |
| Topology | Multi-zone, 3 AZ |
| Nodes | 1 node per AZ (3 total) |
| Min pods per service | 3 (1 per AZ) |
| Total services | 12 (11 application + 1 redis-cart) |
| Total minimum pods | 36 |
| Optimization priority | Reliability |

## Existing Resource Requests & Limits per Pod

These values are taken directly from `kubernetes-manifests/*.yaml` without modification.

| Service | CPU Req | CPU Lim | Mem Req | Mem Lim |
|---|---|---|---|---|
| adservice | 200m | 300m | 180Mi | 300Mi |
| cartservice | 200m | 300m | 64Mi | 128Mi |
| redis-cart | 70m | 125m | 200Mi | 256Mi |
| checkoutservice | 100m | 200m | 64Mi | 128Mi |
| currencyservice | 100m | 200m | 64Mi | 128Mi |
| emailservice | 100m | 200m | 64Mi | 128Mi |
| frontend | 100m | 200m | 64Mi | 128Mi |
| paymentservice | 100m | 200m | 64Mi | 128Mi |
| productcatalogservice | 100m | 200m | 64Mi | 128Mi |
| recommendationservice | 100m | 200m | 220Mi | 450Mi |
| shippingservice | 100m | 200m | 64Mi | 128Mi |
| loadgenerator | 300m | 500m | 256Mi | 512Mi |

> **Note:** `loadgenerator` is a load testing tool, not an application service.
> It is typically not deployed in production. However, the calculations below
> include loadgenerator as a worst case. If not deployed, headroom will be
> larger than the figures shown.

## Resource Calculation per Node

With 3 pods per service evenly spread across 3 AZs (1 pod per node per service),
each node runs 1 pod of every service. Total resource per node = sum of all
service resources.

| Metric | Total per Node |
|---|---|
| CPU Requests | **1570m** |
| CPU Limits | **2825m** |
| Memory Requests | **1368Mi** |
| Memory Limits | **2542Mi** |

## Node Spec Recommendation

### Target Utilization: 70%

Based on Google Cloud best practices for cost-optimized Kubernetes
([source](https://docs.cloud.google.com/architecture/best-practices-for-running-cost-effective-kubernetes-applications-on-gke)),
70% utilization provides a 30% buffer for spikes and scaling. Google does not
prescribe a specific number for node sizing, but the example they provide for
HPA yields a target of ~69% using the formula `(1 - buff) / (1 + perc)`.

### Why CPU uses requests, memory uses limits?

- **CPU**: The Kubernetes scheduler uses requests to determine whether a pod can
  be scheduled. If a pod exceeds its CPU limit, it gets **throttled**
  (slowed down), not killed.
- **Memory**: If a pod exceeds its memory limit, it gets **OOM killed**. Therefore,
  the node must have enough memory to accommodate total limits, not just
  requests.

### Determining vCPU

Workload CPU requests per node: **1570m**

Target 70% → required effective available: `1570 / 0.7 = 2243m`

GKE custom machine types only support 1 vCPU or even multiples (2, 4, 6, ...).

| vCPU | GKE Reserved | Daemonsets* | Effective Available | Utilization | Status |
|---|---|---|---|---|---|
| 2 | 70m | ~150m | 1780m | 88% | Exceeds 70% target |
| 4 | 80m | ~150m | 3770m | 42% | Below 70% target |

\* Estimated default GKE Standard daemonsets (kube-proxy, gke-metadata-server,
netd, pdcsi-node) without additional add-ons. These are estimates, not exact
figures. For actual values, check `kubectl top pods -n kube-system` on a
running cluster.

GKE CPU reserved formula ([source](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-node-sizes)):
- 6% of first core + 1% of next core + 0.5% of next 2 cores

2 vCPU already exceeds the target → **4 vCPU**.

### Determining Memory

Workload memory limits per node: **2542Mi**

Target 70% → required effective available: `2542 / 0.7 = 3631Mi`

GKE custom machine type constraints for 4 vCPU:
- Min: 4 x 0.9 GB = 3.6 GB
- Max: 4 x 6.5 GB = 26 GB
- Increment: 256 MB

GKE memory reserved formula ([source](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-node-sizes)):
- 25% of first 4 GiB + 20% of next 4 GiB + 10% of next 8 GiB
- Eviction threshold: 100 Mi

| Total RAM | GKE Reserved | Eviction | Allocatable | Daemonsets* | Effective Available | Utilization (limits) | Status |
|---|---|---|---|---|---|---|---|
| 4 GB | 1024Mi | 100Mi | 2972Mi | ~230Mi | 2742Mi | 93% | Too high |
| 5 GB | 1229Mi | 100Mi | 3791Mi | ~230Mi | 3561Mi | 71% | Right at the limit |
| 6 GB | 1434Mi | 100Mi | 4610Mi | ~230Mi | 4380Mi | 58% | Healthy headroom |

\* Estimated default GKE Standard daemonsets without additional add-ons.

- **4 GB**: 93% — risk of OOM if multiple pods approach their limits simultaneously.
- **5 GB**: 71% — right at the target boundary, no room for additional overhead.
- **6 GB**: 58% — healthy headroom for production.

→ **6 GB (6144 MB)**.

### Recommendation: `e2-custom-4-6144`

| Parameter | Value |
|---|---|
| Machine type | `e2-custom-4-6144` |
| vCPU | 4 |
| Memory | 6 GB |
| CPU utilization (requests) | 42% |
| Memory utilization (limits) | 58% |

### Alternative: `n2-custom-4-6144`

If the workload requires more consistent CPU performance (latency-sensitive):

- Identical spec (4 vCPU, 6 GB)
- More predictable CPU performance (dedicated, not shared like e2)
- ~15-20% more expensive than e2

## Cluster Summary

| Parameter | Value |
|---|---|
| Machine type | `e2-custom-4-6144` |
| Nodes | 3 (1 per AZ) |
| Total cluster vCPU | 12 |
| Total cluster RAM | 18 GB |
| Total pods (min) | 36 |
| Pods per node | 12 |
