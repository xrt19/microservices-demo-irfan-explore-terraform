# Load Test Plan — Online Boutique (GKE Standard)

## Cluster Infrastructure

| Spec | Value |
|------|-------|
| Node type | `e2-custom-4-6144` (4 vCPU, 6 GB RAM) |
| Nodes (min) | 3 (1 per zone, `asia-southeast2`) |
| Nodes (max) | 6 (2 per zone, autoscaler) |
| Allocatable per node | ~3,400m CPU, ~5.2 GB RAM |
| **Total allocatable (3 nodes)** | **~10,200m CPU, ~15.6 GB RAM** |
| **Total allocatable (6 nodes)** | **~20,400m CPU, ~31.2 GB RAM** |

## Service Resource Summary

### CPU Requests per Pod

| Service | CPU Request | CPU Limit | Min Replicas | Max Replicas |
|---------|-------------|-----------|:------------:|:------------:|
| frontend | 100m | 200m | 3 | 6 |
| cartservice | 200m | 300m | 3 | 5 |
| redis-cart | 70m | 125m | 1 | 1 |
| checkoutservice | 100m | 200m | 3 | 5 |
| currencyservice | 100m | 200m | 3 | 6 |
| emailservice | 100m | 200m | 3 | 5 |
| paymentservice | 100m | 200m | 3 | 5 |
| productcatalogservice | 100m | 200m | 3 | 5 |
| recommendationservice | 100m | 200m | 3 | 5 |
| shippingservice | 100m | 200m | 3 | 5 |
| adservice | 200m | 300m | 3 | 5 |
| loadgenerator | 300m | 500m | 1 | 1 |

### Memory Requests per Pod

| Service | Mem Request | Mem Limit |
|---------|-------------|-----------|
| frontend | 64Mi | 128Mi |
| cartservice | 64Mi | 128Mi |
| redis-cart | 200Mi | 256Mi |
| checkoutservice | 64Mi | 128Mi |
| currencyservice | 64Mi | 128Mi |
| emailservice | 64Mi | 128Mi |
| paymentservice | 64Mi | 128Mi |
| productcatalogservice | 64Mi | 128Mi |
| recommendationservice | 220Mi | 450Mi |
| shippingservice | 64Mi | 128Mi |
| adservice | 180Mi | 300Mi |
| loadgenerator | 256Mi | 512Mi |

### Aggregate Resource Consumption

| State | Total Pods | Total CPU Request | Total Mem Request |
|-------|:----------:|:-----------------:|:-----------------:|
| Min replicas (baseline) | 32 | 3,970m | ~3.1 GB |
| Max replicas (full HPA) | 54 | 6,570m | ~5.0 GB |

## Bottleneck Analysis

1. **currencyservice** — highest QPS (called by both frontend and checkoutservice on every page/checkout). First to hit HPA threshold.
2. **adservice** — heaviest per-pod resource (Java, 200m CPU request). CPU bottleneck hits fastest.
3. **cartservice** — depends on redis-cart (single replica, emptyDir). Redis is a single point of throughput.
4. **frontend** — entry point for all HTTP traffic. Scales to max 6 replicas.
5. **checkoutservice** — fan-out orchestrator (calls 6 downstream services). Latency accumulates here.

## Load Test Scenarios

All scenarios use the built-in Locust loadgenerator. Current config: `USERS=10`, `RATE=1`.

### Scenario 1: Baseline (Steady State)

| Parameter | Value |
|-----------|-------|
| USERS | 10–20 |
| RATE | 1 |
| Duration | 10–15 min |
| Purpose | Validate all services healthy, no errors, establish baseline latency |

Expected behavior:
- All services stay at min replicas (3 pods each)
- No HPA triggers (CPU < 70% threshold)
- 3 nodes, no autoscaler activity

### Scenario 2: Moderate Load

| Parameter | Value |
|-----------|-------|
| USERS | 30–50 |
| RATE | 2–3 |
| Duration | 15–20 min |
| Purpose | Validate HPA triggers correctly, service latency under moderate pressure |

Expected behavior:
- currencyservice and frontend start scaling (4–5 replicas)
- Other services may start scaling
- Still within 3 nodes capacity (~6,500m CPU max)
- Watch for latency increase in checkoutservice (fan-out)

### Scenario 3: Stress Test

| Parameter | Value |
|-----------|-------|
| USERS | 80–100 |
| RATE | 5 |
| Duration | 20–30 min |
| Purpose | Push HPA to near-max, possibly trigger node autoscaler |

Expected behavior:
- Most services at 4–5 replicas
- Total CPU requests approach 6,000m+
- Node autoscaler may add 1–2 nodes (4–5 total)
- Monitor for error rate increase, p99 latency spikes

### Scenario 4: Max Capacity

| Parameter | Value |
|-----------|-------|
| USERS | 150–200 |
| RATE | 5–10 |
| Duration | 15–20 min |
| Purpose | Find the breaking point, validate node autoscaler max (6 nodes) |

Expected behavior:
- All services at max replicas
- Node autoscaler scales to 5–6 nodes
- Error rate will start increasing
- redis-cart (single replica) becomes bottleneck for cart operations
- Identify which service fails first

## Execution Log

| Scenario | USERS | RATE | Started At | Status |
|----------|:-----:|:----:|------------|--------|
| 1 — Baseline | 10 | 1 | 2026-04-19 03:30 WIB | Done |
| 2 — Moderate | 40 | 3 | 2026-04-19 03:45 WIB | Done |
| 3 — Stress | 100 | 5 | 2026-04-19 03:56 WIB | Done |
| 4 — Max Capacity | 150 | 10 | 2026-04-19 04:28 WIB | Running |

### Scenario 1 Notes (sampled ~03:45 WIB)

**Node Utilization:**

| Node | CPU | CPU% | Memory | Mem% |
|------|-----|:----:|--------|:----:|
| 5a88a43b-zss3 | 141m | 3% | 1,596Mi | 36% |
| 7f116bd2-svf2 | 131m | 3% | 1,843Mi | 41% |
| e766f3e7-20hq | 141m | 3% | 1,755Mi | 39% |

**Service CPU Utilization (HPA target: 70%):**

| Service | CPU/pod (avg) | HPA Actual | Replicas |
|---------|:-------------:|:----------:|:--------:|
| frontend | 6m | 6% | 3 |
| currencyservice | 4m | 4% | 3 |
| recommendationservice | 5m | 5% | 3 |
| productcatalogservice | 3m | 3% | 3 |
| cartservice | 3m | 2% | 3 |
| emailservice | 3m | 3% | 3 |
| checkoutservice | 1m | 1% | 3 |
| adservice | 1m | 1% | 3 |
| paymentservice | 1m | 1% | 3 |
| shippingservice | 1m | 1% | 3 |
| loadgenerator | 5m | — | 1 |
| redis-cart | 4m | — | 1 |

**Observations:**
- All services well below HPA threshold — no scaling triggered
- Node CPU ~3% across all 3 nodes — cluster very lightly loaded
- Node memory 36–41% — mostly base overhead, not load-driven
- Zero HPA scale-ups — all services at minReplicas (3)
- Cluster is comfortably handling USERS=10, RATE=1

### Scenario 2 Notes (sampled ~03:55 WIB)

**Node Utilization:**

| Node | CPU | CPU% | Memory | Mem% |
|------|-----|:----:|--------|:----:|
| 5a88a43b-zss3 | 174m | 4% | 1,601Mi | 36% |
| 7f116bd2-svf2 | 164m | 4% | 1,817Mi | 41% |
| e766f3e7-20hq | 274m | 6% | 1,820Mi | 41% |

**Service CPU Utilization (HPA target: 70%):**

| Service | CPU/pod (avg) | HPA Actual | Replicas |
|---------|:-------------:|:----------:|:--------:|
| frontend | 22m | 22% | 3 |
| currencyservice | 16m | 13% | 3 |
| recommendationservice | 12m | 12% | 3 |
| productcatalogservice | 11m | 12% | 3 |
| cartservice | 8m | 4% | 3 |
| emailservice | 3m | 3% | 3 |
| checkoutservice | 2m | 2% | 3 |
| adservice | 3m | 1% | 3 |
| paymentservice | 1m | 1% | 3 |
| shippingservice | 2m | 2% | 3 |
| loadgenerator | 16m | — | 1 |
| redis-cart | 5m | — | 1 |

**Observations:**
- Frontend highest at 22% CPU — 4x increase from Scenario 1 but still well under HPA threshold
- currencyservice 13%, productcatalogservice 12%, recommendationservice 12% — moderate increase
- No HPA scaling triggered — all services still at minReplicas (3)
- Node CPU 4–6% — still very lightly loaded
- Node memory unchanged (~36–41%) — confirms memory is not load-driven
- Cluster handles USERS=40, RATE=3 comfortably without any scaling

### Scenario 3 Notes (sampled ~04:27 WIB)

**Node Utilization:**

| Node | CPU | CPU% | Memory | Mem% |
|------|-----|:----:|--------|:----:|
| 5a88a43b-zss3 | 390m | 9% | 1,668Mi | 37% |
| 7f116bd2-svf2 | 295m | 7% | 1,859Mi | 42% |
| e766f3e7-20hq | 351m | 8% | 1,787Mi | 40% |

**Service CPU Utilization (HPA target: 70%):**

| Service | CPU/pod (avg) | HPA Actual | Replicas |
|---------|:-------------:|:----------:|:--------:|
| frontend | 52m | 56% | 3 |
| currencyservice | 25m | 26% | 3 |
| productcatalogservice | 25m | 26% | 3 |
| recommendationservice | 22m | 23% | 3 |
| cartservice | 16m | 8% | 3 |
| adservice | 5m | 3% | 3 |
| checkoutservice | 3m | 3% | 3 |
| emailservice | 3m | 3% | 3 |
| shippingservice | 3m | 3% | 3 |
| paymentservice | 1m | 1% | 3 |
| loadgenerator | 38m | — | 1 |
| redis-cart | 7m | — | 1 |

**Observations:**
- Frontend at 56% CPU — approaching HPA threshold (70%), close to triggering scale-up
- currencyservice and productcatalogservice both at 26% — significant increase from Scenario 2
- recommendationservice at 23% — also climbing
- Node CPU 7–9% — still moderate headroom
- Node memory still flat at 37–42% — confirms CPU-bound workload
- No HPA scaling triggered yet — but frontend is close
- One frontend pod (tf7zv) at 74m CPU individually — uneven load distribution

## Recommended Test Sequence

Run scenarios in order, with 5–10 min cooldown between each:

1. **Baseline** (USERS=10, RATE=1) — 10 min, confirm zero errors
2. **Moderate** (USERS=40, RATE=3) — 15 min, confirm HPA works
3. **Stress** (USERS=100, RATE=5) — 20 min, confirm autoscaler works
4. **Max** (USERS=150, RATE=5) — 15 min, find breaking point

## How to Run

```bash
# Option A: Change loadgenerator.yaml env vars and redeploy
kubectl apply -k ../kustomize/

# Option B: Use Locust Web UI (realtime adjustment, recommended)
kubectl port-forward svc/loadgenerator 8089:8089
# Open http://localhost:8089 and set USERS/RATE from the UI
```

## What to Monitor

- **Per-service CPU/memory**: `kubectl top pods`
- **HPA status**: `kubectl get hpa -w`
- **Node autoscaler**: `kubectl get nodes -w`
- **Error rate**: Locust Web UI (http://localhost:8089)
- **Pod events**: `kubectl get events --sort-by=.metadata.creationTimestamp`
- **Pending pods** (waiting for node): `kubectl get pods --field-selector=status.phase=Pending`
