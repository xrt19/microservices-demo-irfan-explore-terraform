# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fork of Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) — a cloud-first microservices e-commerce demo app. This fork is being customized for a **GKE Standard multi-zone production deployment** (not Autopilot) and used as a portfolio/Medium blog post project.

## Architecture

11 microservices + Redis (in-cluster), communicating over gRPC. Frontend exposes HTTP to users.

| Service | Language | Role |
|---|---|---|
| frontend | Go | HTTP web server |
| cartservice | C# | Cart storage (Redis-backed) |
| productcatalogservice | Go | Product listing |
| currencyservice | Node.js | Currency conversion (highest QPS) |
| paymentservice | Node.js | Payment processing (mock) |
| shippingservice | Go | Shipping cost estimation (mock) |
| emailservice | Python | Order confirmation email (mock) |
| checkoutservice | Go | Order orchestration |
| recommendationservice | Python | Product recommendations |
| adservice | Java | Text ads |
| loadgenerator | Python/Locust | Continuous traffic simulation |

## Deployment

### Primary method: Terraform + Kustomize

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

Terraform creates the GKE cluster, then runs `kubectl apply -k ../kustomize/` via `null_resource` local-exec. The Kustomize base (`kustomize/base/`) contains manifests with pre-built images from `us-central1-docker.pkg.dev/google-samples/microservices-demo/`.

### Three manifest locations (same app, different workflows)

- `kubernetes-manifests/` — for Skaffold local development (image tags without registry)
- `kustomize/base/` — for Kustomize deployment (full registry image paths) **← currently used by Terraform**
- `release/kubernetes-manifests.yaml` — single consolidated file for quick manual `kubectl apply -f`

### Key Terraform variables (terraform/variables.tf)

- `gcp_project_id` — GCP project ID (required)
- `region` — default `us-central1`
- `filepath_manifest` — default `../kustomize/`
- `memorystore` — swap in-cluster Redis for Cloud Memorystore

## Cluster Design Decisions

- **GKE Standard** (Terraform currently has `enable_autopilot = true` — needs to be changed to Standard)
- **Multi-zone**: 3 AZ, 1 node per AZ
- **Node spec**: `e2-custom-4-6144` (4 vCPU, 6 GB RAM) — see `docs/gke-node-spec-recommendation.md` for full calculation
- **Min 3 pods per service** (1 per AZ)
- **Target utilization**: 70% (based on Google Cloud best practices)
- **No add-ons** enabled (no Istio, no OpenTelemetry Collector, no network policies)

## Service Communication

All inter-service communication uses **gRPC** (defined in `protos/demo.proto`). Frontend is the only service exposing HTTP.

**Service dependency graph:**
```
frontend (HTTP entry point, port 80 → container 8080)
├── productcatalogservice:3550
├── currencyservice:7000
├── cartservice:7070 → redis-cart:6379
├── recommendationservice:8080 → productcatalogservice:3550
├── adservice:9555
├── shippingservice:50051
└── checkoutservice:5050 (orchestrator)
    ├── productcatalogservice:3550
    ├── shippingservice:50051
    ├── paymentservice:50051
    ├── emailservice:5000
    ├── currencyservice:7000
    └── cartservice:7070
```

**Leaf services** (no downstream dependencies): productcatalogservice, currencyservice, paymentservice, shippingservice, emailservice, adservice, redis-cart.

## Health Checks

| Type | Services | Probe |
|---|---|---|
| gRPC | cartservice, checkoutservice, adservice, recommendationservice, paymentservice, shippingservice, currencyservice, emailservice | `grpc: port` |
| HTTP | frontend | `GET /_healthz` on port 8080 |
| TCP | redis-cart | TCP socket on port 6379 |

## Data Persistence

Redis (redis-cart) uses `emptyDir` — **data is lost on pod restart**. No PersistentVolume configured. Alternative backends available via Kustomize components: Memorystore, Spanner, AlloyDB.

## Security Context (all services)

All pods run with: non-root user (UID 1000), all Linux capabilities dropped, no privilege escalation, read-only root filesystem.

## Container Images

All services use multi-stage builds with distroless/minimal runtime images. Pre-built images tagged `v0.10.5` from `us-central1-docker.pkg.dev/google-samples/microservices-demo/`. Multi-arch: `linux/amd64` + `linux/arm64`.

## Kustomize Components (all optional, all disabled by default)

Available in `kustomize/components/`: cymbal-branding, google-cloud-operations, memorystore, network-policies, non-public-frontend, service-accounts, alloydb, single-shared-session, spanner, service-mesh-istio, without-loadgenerator, container-images-tag, container-images-tag-suffix, container-images-registry. Enable by uncommenting in `kustomize/kustomization.yaml`.
