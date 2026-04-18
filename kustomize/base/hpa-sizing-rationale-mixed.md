# HPA Sizing Rationale

## Overview

HorizontalPodAutoscaler (HPA) di-configure untuk 10 dari 12 deployment, pakai `autoscaling/v2` dengan CPU-based scaling di target 70%.

## Target Utilization: Kenapa 70%?

Dipilih berdasarkan:

- **Google Cloud best practices** — rekomendasi 70% untuk production workloads.
- **Spike tolerance** — ada scheduled spike test (loadgenerator cronjob, 09:00-09:30 WIB daily) yang nge-generate traffic mendadak, bukan gradual.
- **Pod startup time** — beberapa service punya `initialDelaySeconds` 15-20 detik. Kalau target 85%, pod yang ada bisa overload sebelum pod baru ready serve traffic.
- **Headroom** — 30% buffer bisa nyerap short burst tanpa trigger scale-up yang ga perlu.

### Kenapa bukan 85%?

85% viable untuk traffic yang predictable/gradual, tapi di setup ini:

- Spike test traffic-nya mendadak, bukan gradual.
- Pod startup (readiness probe + initialDelaySeconds) butuh 15-30 detik.
- Di 85%, pod yang ada bisa saturated selama window startup pod baru, bikin response latency naik.

## Tiered Max Replicas

Max replicas dibagi berdasarkan volume traffic dan role service.

### Tier 1 — High Traffic (maxReplicas: 6)

| Service | Alasan |
|---|---|
| frontend | Entry point semua HTTP traffic dari user |
| currencyservice | QPS paling tinggi — dipanggil frontend dan checkoutservice di setiap request |

### Tier 2 — Medium/Low Traffic (maxReplicas: 5)

| Service | Alasan |
|---|---|
| cartservice | Dipanggil saat add-to-cart, view cart, dan checkout |
| productcatalogservice | Dipanggil frontend, recommendationservice, dan checkoutservice |
| checkoutservice | Orchestrator — fan out ke 6 downstream service |
| recommendationservice | Dipanggil di setiap page load frontend |
| adservice | Dipanggil di setiap page load frontend |
| paymentservice | Cuma dipanggil saat checkout |
| shippingservice | Dipanggil saat checkout dan estimasi shipping cost |
| emailservice | Cuma dipanggil saat checkout (order confirmation) |

### No HPA

| Service | Alasan |
|---|---|
| redis-cart | Stateful — pakai `emptyDir` storage. Kalau di-scale, tiap Redis instance punya data sendiri-sendiri, cart user jadi pecah/inkonsisten antar pod. |
| loadgenerator | Test tooling, bukan production service. Jalan dengan 1 replica aja. |

## Worst Case Resource Calculation

Semua service di-scale ke max replicas secara bersamaan.

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
Allocatable capacity udah dipotong ~1 vCPU dan ~1.5 GB per node buat system components (kubelet, kube-proxy, dll).

### Kesimpulan

Bahkan di worst case (semua service di max replicas), cluster utilization masih di bawah 40%. Max replica yang dipilih aman dan ga akan bikin resource pressure di cluster.

## HPA Configuration Summary

Semua 10 HPA resource pakai struktur yang sama:

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

- `minReplicas: 3` — memastikan 1 pod per availability zone (3 zone di asia-southeast2).
- `maxReplicas: 5 atau 6` — dibagi berdasarkan volume traffic (tiered).
- `averageUtilization: 70` — target yang direkomendasikan Google Cloud untuk production workloads.
