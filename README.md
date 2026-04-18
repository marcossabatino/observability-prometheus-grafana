# Observability Portfolio: EKS + Prometheus + Grafana + APM

A complete, production-grade observability demonstration using open-source tools. Equivalent to a Datadog APM experience with Prometheus metrics, Grafana dashboards, and distributed tracing via Grafana Tempo.

## Architecture

```
┌──────────────────────────────────────┐
│ AWS EKS Cluster (us-east-2)          │
│ 3x t3.medium SPOT nodes              │
└──────────────────────────────────────┘
         │
    ┌────┴─────────────────────────────────┐
    │                                       │
┌───┴────────────────────┐    ┌────────────┴──────────────┐
│  Monitoring Namespace  │    │  Apps Namespace            │
│                        │    │                            │
├─ Prometheus            │    ├─ java-app (Spring Boot)    │
├─ Grafana (3000)        │    ├─ go-app                    │
├─ Grafana Tempo         │    ├─ python-app (FastAPI)      │
├─ OTel Collector        │    ├─ nginx + exporter sidecar  │
└────────────────────────┘    └─ load-tester (Go)          │
                             └────────────────────────────┘

Metrics Flow:
  Apps (Prometheus client libs)
    ↓
  OTel Collector (receives OTLP traces)
    ↓
  Prometheus & Grafana Tempo
    ↓
  Grafana Dashboards (RED metrics + trace linking)
```

## Quick Start

### Prerequisites

- AWS Account with appropriate IAM permissions
- `terraform` >= 1.0
- `kubectl` configured for AWS
- `helm` 3.x
- Docker (for building images)
- `aws` CLI v2

### Full Deploy (One Command)

```bash
# Configure your AWS region and cluster name
export REGION=us-east-2
export CLUSTER_NAME=observability-cluster

# Deploy everything (builds images, pushes to ECR, creates infra, installs apps)
make all
```

This takes approximately **30 minutes** and costs about **$0.50-1.00 in AWS charges**.

### Step-by-Step

```bash
# 1. Create infrastructure (15 min)
make infra-up
make cluster-config

# 2. Install monitoring stack (5 min)
make stack-up

# 3. Build and push application images
make push

# 4. Deploy applications
make apps-up

# 5. Set up local port-forwards
make port-forward

# 6. Open Grafana
# → http://localhost:3000
# → Username: admin
# → Password: observability123
```

## What's Inside

### Terraform IaC (`terraform/`)

- **VPC**: 3 AZs, 3 public + 3 private subnets, 1 NAT Gateway
- **EKS**: Managed cluster with 3x t3.medium SPOT nodes
  - Auto-scaling: min=2, desired=3, max=5
  - Add-ons: vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver
  - OIDC provider for IRSA

**Cost optimization:**
- SPOT instances (~$0.03/hour per node) instead of on-demand
- Single NAT Gateway (vs 3) saves ~$32/month
- Total: ~$27/month nodes + $72/month control plane = **~$100/month**

### Monitoring Stack

#### kube-prometheus-stack

- Prometheus with 20 GiB PVC (persistent metrics)
- Grafana (admin UI at localhost:3000)
- AlertManager (disabled for this portfolio)
- Node Exporter, kube-state-metrics (cluster-level metrics)

**Critical configuration:**
- `--enable-feature=exemplar-storage` — enables trace→metric linking
- ServiceMonitor label: `release: kube-prometheus` (required)

#### Grafana Tempo (Distributed Tracing)

- Single-binary deployment
- Local filesystem storage (5 GiB PVC)
- Receives OTLP traces from OTel Collector
- Integrated into Grafana: `http://tempo.monitoring.svc:3100`

#### OpenTelemetry Collector

- Central ingestion point for all app traces
- Pipeline: OTLP (gRPC 4317) → memory_limiter → batch → Tempo
- DaemonSet or Deployment (configurable)

### Applications

All apps expose:
- `GET /health` → 200 OK (baseline metric)
- `GET /simulate-slow` → sleep 1-3 seconds (populates P95/P99 latencies)
- `GET /simulate-error` → 50% chance of 500 error (failure rate)
- `GET /metrics` → Prometheus scrape endpoint

#### Java App (Spring Boot)

```
Port: 8080
Metrics: Micrometer + prometheus-registry
Tracing: OTel Java Agent (zero-code)
Exemplars: Micrometer ↔ OTel bridge
```

Built with:
- Spring Boot 3.x
- Micrometer + Prometheus
- OTel Java Agent (-javaagent flag)
- Micrometer Tracing Bridge for exemplar support

#### Go App

```
Port: 8080
Metrics: prometheus/client_golang
Tracing: OTel SDK + otelhttp middleware
Exemplars: Native histogram (v1.17+)
```

#### Python App (FastAPI)

```
Port: 8080
Metrics: prometheus-client
Tracing: OTel auto-instrumentation
Entrypoint: opentelemetry-instrument
```

#### Nginx

```
Port: 80/443 (reverse proxy)
Metrics: nginx-prometheus-exporter sidecar
Tracing: None (stub_status only)
```

#### Load Tester (Go)

```
Sends 10 req/s per pod to all other apps:
  - 70% to /health
  - 20% to /simulate-slow
  - 10% to /simulate-error

Total RPS = (number of load-tester replicas) × 10 req/s
```

**Auto-scales with pod count:**
```bash
# Scale load tester from 1 to 3 pods = 30 total req/s
kubectl scale deployment load-tester --replicas=3 -n apps

# Watch RPS increase in Grafana
```

### Grafana Dashboards

#### 1. APM Overview

- List of all services with RED metrics
- Request rate, error rate %, latency (P50/P95/P99)
- Apdex score per service
- One-click drill-down to service detail

**Equivalent to:** Datadog Services List

#### 2. Service Detail

- Time series: Request rate, error rate, latency heatmap
- Top endpoints by latency
- Error breakdown by HTTP status
- **Exemplar-linked trace navigation:**
  - Click any latency spike dot → opens trace in Tempo
  - See full request flow across all services

**Equivalent to:** Datadog APM Service page

#### 3. JVM Metrics (Java only)

- Heap usage (used/max)
- GC pause duration (P99)
- Thread count
- Process CPU usage

#### 4. Load Tester Activity

- Requests/second per target service
- Replica count over time
- Response time distribution observed by load tester

#### 5. Infrastructure Overview

- Node CPU/memory (from node-exporter)
- Pod restarts (from kube-state-metrics)
- PVC usage

## Observability Features

### Metrics (RED)

All apps expose:
- **Rate:** `http_requests_total` (requests/second)
- **Errors:** `http_requests_total{status=~"5.."}` (5xx errors)
- **Duration:** `http_request_duration_seconds` histogram (latency percentiles)

Consistent histogram buckets across all languages:
```
[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
```

This enables meaningful comparisons of P99 latencies across languages.

### Distributed Tracing

All three apps (Java, Go, Python) instrument with OpenTelemetry:

- **Java:** OTel Java Agent (automatic instrumentation)
- **Go:** OTel SDK + HTTP middleware
- **Python:** OTel auto-instrumentation via `opentelemetry-instrument`

Traces captured:
- HTTP request/response spans
- Downstream service calls
- Response times
- Errors and exceptions

### Exemplars (Trace ↔ Metric Linking)

The key feature bridging metrics and traces:

1. Each request gets a trace ID
2. Micrometer (Java) and prometheus_client (all langs) attach trace IDs to histogram observations
3. Prometheus stores trace IDs alongside metric values
4. Grafana detects exemplars in histogram data
5. **Click the dot → jump to the trace in Tempo**

This is the DataDog APM defining feature, fully implemented with OSS.

## File Structure

```
observability-prometheus-grafana/
├── Makefile                              # One-command targets
├── README.md                             # This file
├── .gitignore
│
├── terraform/
│   ├── main.tf                           # Root module
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf                       # Required provider versions
│   ├── terraform.tfvars.example          # Copy → terraform.tfvars
│   │
│   └── modules/
│       ├── vpc/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       └── eks/
│           ├── main.tf                   # EKS cluster + node group + add-ons
│           ├── variables.tf
│           └── outputs.tf
│
├── kubernetes/
│   ├── monitoring/
│   │   ├── namespace.yaml
│   │   ├── kube-prometheus-stack/
│   │   │   ├── values.yaml               # Helm values override
│   │   │   └── additional-scrape-configs.yaml
│   │   ├── tempo/
│   │   │   └── values.yaml
│   │   ├── otel-collector/
│   │   │   └── values.yaml
│   │   └── dashboards/
│   │       ├── apm-overview.json
│   │       ├── service-detail.json
│   │       ├── jvm-metrics.json
│   │       └── load-tester.json
│   │
│   └── apps/
│       ├── namespace.yaml
│       ├── java-app/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── servicemonitor.yaml
│       ├── go-app/
│       ├── python-app/
│       ├── nginx/
│       └── load-tester/
│
├── apps/
│   ├── java-app/
│   │   ├── Dockerfile
│   │   ├── pom.xml
│   │   ├── src/main/java/...
│   │   └── docker/application.properties
│   ├── go-app/
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── main.go
│   ├── python-app/
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── main.py
│   └── load-tester/
│       ├── Dockerfile
│       ├── go.mod
│       ├── go.sum
│       └── main.go
│
└── scripts/
    ├── 01-terraform-apply.sh
    ├── 02-configure-kubectl.sh
    ├── 03-install-monitoring.sh          # Helm installs
    ├── 04-deploy-apps.sh                 # kubectl apply
    ├── 05-port-forward.sh
    └── teardown.sh                       # Full cleanup
```

## Cost Analysis

### Monthly Costs (us-east-2)

| Component | Cost/Month | Notes |
|-----------|-----------|-------|
| EKS Control Plane | $72 | Fixed, regardless of node count |
| EC2 3x t3.medium SPOT | $27 | ~$0.03/hr per node (typical SPOT pricing) |
| EBS Storage (Prometheus) | $2 | 20 GiB gp2 |
| EBS Storage (Tempo) | $0.50 | 5 GiB gp2 |
| Data Transfer | ~$1 | Minimal inter-AZ traffic |
| **Total** | **~$103** | |

**To minimize costs:**
1. Stop the cluster: `make destroy` (removes EKS control plane)
2. Do NOT leave cluster running with zero pods

## Troubleshooting

### Prometheus targets are DOWN

**Check:** ServiceMonitor labels
```bash
kubectl get servicemonitor -n apps
kubectl describe servicemonitor -n apps java-app

# Must have label: release=kube-prometheus
```

### No traces appearing in Tempo

**Check:** OTel Collector logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector -f
```

**Ensure:**
1. Collector pod is Running
2. OTel receiver listens on 0.0.0.0:4317
3. Apps can reach `otel-collector.monitoring.svc:4317` (network connectivity)

### Exemplars not linking to traces

**Check:** Prometheus exemplar storage is enabled
```bash
kubectl exec -n monitoring prometheus-0 -- ps aux | grep exemplar
# Should see: --enable-feature=exemplar-storage
```

**Check:** Grafana datasource UID matches
```bash
# In Grafana UI:
Configuration → Data Sources → Prometheus → UID should be "prometheus"
Configuration → Data Sources → Tempo → tracesToMetrics.datasourceUid should be "prometheus"
```

### Load tester not sending requests

**Check:** Deployment status
```bash
kubectl get deployment load-tester -n apps
kubectl logs -n apps -l app=load-tester -f
```

**Ensure:**
1. Target services are reachable (curl from load-tester pod)
2. Environment variables set correctly (`TARGETS`, `BASE_RPS`)

## Learning Path

This project is designed to progressively teach observability:

1. **Start here:** Open Grafana, click "APM Overview" dashboard
2. **Understand metrics:** Identify request rate, error rate, latency on one service
3. **Explore tracing:** Click a latency spike dot → see the trace
4. **Load test:** Scale load-tester replicas, watch RPS increase
5. **Drill-down:** Service Detail dashboard, find slowest endpoints
6. **Simulate problems:** Kill a pod, watch error rate spike in dashboard

## Cleanup

To destroy all AWS resources and stop incurring charges:

```bash
make destroy
```

This removes:
- EKS cluster and nodes
- VPC and subnets
- EBS volumes
- NAT Gateway
- Load Balancer (if any)

Takes ~5-10 minutes.

## References

- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Tempo](https://grafana.com/oss/tempo/)
- [OpenTelemetry](https://opentelemetry.io/)
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)

---

Built for portfolio demonstration and learning.
