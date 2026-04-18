# HPA Sizing Rationale

## Overview

HorizontalPodAutoscaler (HPA) is configured for 10 out of 12 deployments using `autoscaling/v2` with CPU-based scaling at 70% target utilization.

## Target Utilization: 70%

Chosen based on:

- **Google Cloud best practices** recommend 70% for production workloads.
- **Spike tolerance** — the scheduled spike test (loadgenerator cronjob, 09:00-09:30 WIB daily) generates sudden traffic increases, not gradual ramps.
- **Pod startup time** — several services have `initialDelaySeconds` of 15-20 seconds. At 85% target, existing pods risk saturation before new pods become ready to serve traffic.
- **Headroom** — 30% buffer absorbs short bursts without triggering unnecessary scale-up events.

### Why not 85%?

85% is viable for predictable/gradual traffic patterns, but in this setup:

- Spike test traffic is sudden, not gradual.
- Pod startup (readiness probe + initialDelaySeconds) takes 15-30 seconds.
- At 85%, existing pods can become overloaded during the startup window of new pods, increasing response latency.

## Tiered Max Replicas

Max replicas are tiered by traffic volume and service role.

### Tier 1 — High Traffic (maxReplicas: 6)

| Service | Reason |
|---|---|
| frontend | Entry point for all user HTTP traffic |
| currencyservice | Highest QPS — called by both frontend and checkoutservice on every request |

### Tier 2 — Medium/Low Traffic (maxReplicas: 5)

| Service | Reason |
|---|---|
| cartservice | Called on add-to-cart, view cart, and checkout flows |
| productcatalogservice | Called by frontend, recommendationservice, and checkoutservice |
| checkoutservice | Orchestrator — fans out to 6 downstream services |
| recommendationservice | Called on every frontend page load |
| adservice | Called on every frontend page load |
| paymentservice | Called only during checkout |
| shippingservice | Called during checkout and shipping cost estimation |
| emailservice | Called only during checkout (order confirmation) |

### No HPA

| Service | Reason |
|---|---|
| redis-cart | Stateful — uses `emptyDir` storage. Scaling creates independent Redis instances with separate data, breaking cart consistency across pods. |
| loadgenerator | Test tooling, not a production service. Runs with 1 replica. |

## Worst Case Resource Calculation

All services scaled to their max replicas simultaneously.

### CPU Requests

| Service | Per Pod | Max Replicas | Total |
|---|---|---|---|
| frontend | 100m | 6 | 600m |
| currencyservice | 100m | 6 | 600m |
| cartservice | 200m | 5 | 1,000m |
| productcatalogservice | 100m | 5 | 500m |
| checkoutservice | 100m | 5 | 500m |
| recommendationservice | 100m | 5 | 500m |
| adservice | 200m | 5 | 1,000m |
| paymentservice | 100m | 5 | 500m |
| shippingservice | 100m | 5 | 500m |
| emailservice | 100m | 5 | 500m |
| redis-cart (no HPA) | 70m | 1 | 70m |
| loadgenerator (no HPA) | 300m | 1 | 300m |
| **Total** | | | **6,570m** |

### Memory Requests

| Service | Per Pod | Max Replicas | Total |
|---|---|---|---|
| frontend | 64Mi | 6 | 384Mi |
| currencyservice | 64Mi | 6 | 384Mi |
| cartservice | 64Mi | 5 | 320Mi |
| productcatalogservice | 64Mi | 5 | 320Mi |
| checkoutservice | 64Mi | 5 | 320Mi |
| recommendationservice | 220Mi | 5 | 1,100Mi |
| adservice | 180Mi | 5 | 900Mi |
| paymentservice | 64Mi | 5 | 320Mi |
| shippingservice | 64Mi | 5 | 320Mi |
| emailservice | 64Mi | 5 | 320Mi |
| redis-cart | 200Mi | 1 | 200Mi |
| loadgenerator | 256Mi | 1 | 256Mi |
| **Total** | | | **5,144Mi (~5 GB)** |

### Node Capacity (Max 6 Nodes)

| Resource | Worst Case | Allocatable (6 nodes) | Utilization |
|---|---|---|---|
| CPU | 6.57 vCPU | ~18 vCPU | 36.5% |
| Memory | 5.02 GB | ~27 GB | 18.6% |

Node spec: `e2-custom-4-6144` (4 vCPU, 6 GB RAM) x 6 nodes (max 2 per zone x 3 zones).
Allocatable capacity accounts for ~1 vCPU and ~1.5 GB per node reserved for system components.

### Conclusion

Even at worst case (all services at max replicas), cluster utilization stays well below 40%. The chosen max replica values are safe and will not cause resource pressure on the cluster.

## HPA Configuration Summary

All 10 HPA resources use the same structure:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: <service>-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <service>
  minReplicas: 3
  maxReplicas: 5 or 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

- `minReplicas: 3` — ensures 1 pod per availability zone (3 zones in asia-southeast2).
- `maxReplicas: 5 or 6` — tiered by traffic volume.
- `averageUtilization: 70` — Google Cloud recommended target for production workloads.
