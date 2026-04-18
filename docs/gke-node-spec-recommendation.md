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

Angka ini diambil langsung dari `kubernetes-manifests/*.yaml` tanpa perubahan.

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

> **Catatan:** `loadgenerator` adalah tool untuk load testing, bukan application service.
> Untuk production biasanya tidak di-deploy. Namun perhitungan di bawah tetap
> menyertakan loadgenerator sebagai worst case. Jika tidak di-deploy, headroom
> akan lebih besar dari angka yang tertera.

## Perhitungan Resource per Node

Dengan 3 pod per service tersebar merata di 3 AZ (1 pod per node per service),
maka setiap node menjalankan 1 pod dari masing-masing service. Total resource
per node = jumlah resource seluruh service.

| Metric | Total per Node |
|---|---|
| CPU Requests | **1570m** |
| CPU Limits | **2825m** |
| Memory Requests | **1368Mi** |
| Memory Limits | **2542Mi** |

## Node Spec Recommendation

### Target Utilization: 70%

Mengacu pada Google Cloud best practices untuk cost-optimized Kubernetes
([source](https://docs.cloud.google.com/architecture/best-practices-for-running-cost-effective-kubernetes-applications-on-gke)),
70% utilization memberikan 30% buffer untuk spike dan scaling. Google tidak
menetapkan angka baku untuk node sizing, tapi contoh yang mereka berikan untuk
HPA menghasilkan target ~69% dari formula `(1 - buff) / (1 + perc)`.

### Kenapa CPU pakai requests, memory pakai limits?

- **CPU**: Kubernetes scheduler memakai requests untuk menentukan pod bisa
  di-schedule atau tidak. Jika pod melebihi CPU limit, pod di-**throttle**
  (diperlambat), bukan di-kill.
- **Memory**: Jika pod melebihi memory limit, pod di-**OOM killed**. Oleh karena
  itu node harus punya cukup memory untuk menampung total limits, bukan hanya
  requests.

### Menentukan vCPU

Workload CPU requests per node: **1570m**

Target 70% → effective available yang dibutuhkan: `1570 / 0.7 = 2243m`

GKE custom machine type hanya mendukung 1 vCPU atau kelipatan genap (2, 4, 6, ...).

| vCPU | GKE Reserved | Daemonsets* | Effective Available | Utilization | Status |
|---|---|---|---|---|---|
| 2 | 70m | ~150m | 1780m | 88% | Melebihi target 70% |
| 4 | 80m | ~150m | 3770m | 42% | Di bawah target 70% |

\* Estimasi default GKE Standard daemonsets (kube-proxy, gke-metadata-server,
netd, pdcsi-node) tanpa add-on tambahan. Angka ini estimasi, bukan angka pasti.
Untuk angka aktual, cek `kubectl top pods -n kube-system` pada cluster yang
sudah berjalan.

GKE CPU reserved formula ([source](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-node-sizes)):
- 6% of first core + 1% of next core + 0.5% of next 2 cores

2 vCPU sudah melebihi target → **4 vCPU**.

### Menentukan Memory

Workload memory limits per node: **2542Mi**

Target 70% → effective available yang dibutuhkan: `2542 / 0.7 = 3631Mi`

GKE custom machine type constraint untuk 4 vCPU:
- Min: 4 x 0.9 GB = 3.6 GB
- Max: 4 x 6.5 GB = 26 GB
- Increment: 256 MB

GKE memory reserved formula ([source](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-node-sizes)):
- 25% of first 4 GiB + 20% of next 4 GiB + 10% of next 8 GiB
- Eviction threshold: 100 Mi

| Total RAM | GKE Reserved | Eviction | Allocatable | Daemonsets* | Effective Available | Utilization (limits) | Status |
|---|---|---|---|---|---|---|---|
| 4 GB | 1024Mi | 100Mi | 2972Mi | ~230Mi | 2742Mi | 93% | Terlalu tinggi |
| 5 GB | 1229Mi | 100Mi | 3791Mi | ~230Mi | 3561Mi | 71% | Tepat di batas |
| 6 GB | 1434Mi | 100Mi | 4610Mi | ~230Mi | 4380Mi | 58% | Ada headroom |

\* Estimasi default GKE Standard daemonsets tanpa add-on tambahan.

- **4 GB**: 93% — risiko OOM jika beberapa pod mendekati limit bersamaan.
- **5 GB**: 71% — tepat di batas target, tidak ada ruang untuk overhead tambahan.
- **6 GB**: 58% — ada headroom yang sehat untuk prod.

→ **6 GB (6144 MB)**.

### Rekomendasi: `e2-custom-4-6144`

| Parameter | Value |
|---|---|
| Machine type | `e2-custom-4-6144` |
| vCPU | 4 |
| Memory | 6 GB |
| CPU utilization (requests) | 42% |
| Memory utilization (limits) | 58% |

### Alternatif: `n2-custom-4-6144`

Jika workload membutuhkan performa CPU yang lebih konsisten (latency-sensitive):

- Spec identik (4 vCPU, 6 GB)
- Performa CPU lebih predictable (dedicated, bukan shared seperti e2)
- Harga ~15-20% lebih mahal dari e2

## Cluster Summary

| Parameter | Value |
|---|---|
| Machine type | `e2-custom-4-6144` |
| Nodes | 3 (1 per AZ) |
| Total cluster vCPU | 12 |
| Total cluster RAM | 18 GB |
| Total pods (min) | 36 |
| Pods per node | 12 |