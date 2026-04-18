# Deployment Guide

Complete step-by-step instructions to deploy the observability portfolio to AWS EKS.

## Prerequisites

### AWS Account Setup

1. **IAM User with Permissions**
   - EC2 (full access)
   - EKS (full access)
   - EBS (full access)
   - VPC (full access)
   - ECR (full access)
   - CloudFormation (full access)
   - IAM (role creation)

2. **Install AWS CLI v2**
   ```bash
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   aws --version
   ```

3. **Configure AWS Credentials**
   ```bash
   aws configure
   # Enter your Access Key ID and Secret Access Key
   # Default region: us-east-2
   # Default output: json
   ```

4. **Verify Access**
   ```bash
   aws sts get-caller-identity
   ```

### Local Environment Setup

1. **Install Terraform** (>= 1.0)
   ```bash
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com jammy main"
   sudo apt-get update && sudo apt-get install terraform
   terraform version
   ```

2. **Install kubectl**
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   kubectl version --client
   ```

3. **Install Helm 3.x**
   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   helm version
   ```

4. **Install Docker** (for building images)
   ```bash
   sudo apt-get update && sudo apt-get install -y docker.io
   sudo usermod -aG docker $USER
   # Log out and back in for group changes to take effect
   ```

5. **Install Make**
   ```bash
   sudo apt-get install -y make
   make --version
   ```

## Deployment Steps

### 1. Clone and Setup (5 min)

```bash
# Navigate to the project directory
cd observability-prometheus-grafana

# Copy and edit Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit the file to match your preferences
# nano terraform/terraform.tfvars
# Key variables:
#   - region: us-east-2 (or your preferred region)
#   - cluster_name: observability-cluster
#   - node_instance_type: t3.medium (recommended for cost)
#   - node_desired_count: 3
#   - enable_spot_instances: true (for cost savings)
```

### 2. Create ECR Repository (2 min)

The Makefile expects images to be pushed to ECR. Create the repositories:

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com"

# Create ECR repositories
aws ecr create-repository --repository-name java-app --region us-east-2 || true
aws ecr create-repository --repository-name go-app --region us-east-2 || true
aws ecr create-repository --repository-name python-app --region us-east-2 || true
aws ecr create-repository --repository-name load-tester --region us-east-2 || true
```

### 3. Build and Push Docker Images (10-15 min)

```bash
# Build all images
make build

# Push to ECR
make push
# This will prompt for login credentials - ECR will authenticate automatically

# Verify images in ECR
aws ecr describe-images --repository-name java-app --region us-east-2
aws ecr describe-images --repository-name go-app --region us-east-2
aws ecr describe-images --repository-name python-app --region us-east-2
aws ecr describe-images --repository-name load-tester --region us-east-2
```

### 4. Create AWS Infrastructure (15 min)

**WARNING:** This creates AWS resources that will incur charges (~$0.50/hour).

```bash
# Deploy VPC and EKS
make infra-up

# You will see:
# 1. VPC creation (with subnets, NAT Gateway, security groups)
# 2. EKS cluster creation (takes ~12-15 minutes)
# 3. Managed node group provisioning (adds ~2-3 minutes)

# Wait for completion. Progress messages show:
# - "aws_eks_cluster.main: Still creating..."
# - "aws_eks_node_group.main: Still creating..."
```

### 5. Configure kubectl (1 min)

```bash
# Update kubeconfig to connect to the new cluster
make cluster-config

# Verify cluster access
kubectl cluster-info
kubectl get nodes
# You should see 3 nodes in Ready state (may take a few minutes)
```

### 6. Install Monitoring Stack (10 min)

```bash
# Install Prometheus, Grafana, Tempo, and OTel Collector
make stack-up

# Monitor progress
kubectl get pods -n monitoring -w
# Wait for all pods to be Running (includes Prometheus, Grafana, Tempo, OTel Collector)
# Ctrl+C to exit watch mode

# Verify installations
kubectl get all -n monitoring
```

### 7. Deploy Applications (5 min)

```bash
# Deploy Java, Go, Python apps, Nginx, and Load Tester
make apps-up

# Monitor deployment progress
kubectl get pods -n apps -w
# Wait for all deployments to be Ready
# Ctrl+C to exit

# Verify applications
kubectl get all -n apps
```

### 8. Access Grafana and Verify (5 min)

```bash
# Start port-forwarding (runs in foreground, Ctrl+C to stop)
./scripts/05-port-forward.sh

# In another terminal, open Grafana
curl http://localhost:3000
# Or open in browser: http://localhost:3000

# Log in:
# Username: admin
# Password: observability123
```

### 9. Verify Metrics and Tracing (5 min)

**In Grafana:**

1. **Check Prometheus Datasource**
   - Configuration → Data Sources → Prometheus
   - Click "Test" - should show "Data source is working"

2. **Check Tempo Datasource**
   - Configuration → Data Sources → Tempo
   - Click "Test" - should show "Data source is working"

3. **Open APM Overview Dashboard**
   - Click "Dashboards" → Search "APM Overview"
   - Should see:
     - Request Rate increasing (load-tester generating load)
     - Error Rate showing errors from `/simulate-error` endpoint
     - Latency P99 showing spikes from `/simulate-slow` endpoint

4. **Open Service Detail Dashboard**
   - Shows RED metrics (Rate, Errors, Duration) for each service
   - Try clicking a latency spike dot - should open trace in Tempo

5. **Open JVM Metrics Dashboard** (if Java app is running)
   - Shows heap usage, GC pauses, thread count

6. **Check Prometheus Targets**
   - Click "Status" → "Targets"
   - All app targets should show "UP" (java-app, go-app, python-app, nginx)
   - If "DOWN", check ServiceMonitor labels: must have `release: kube-prometheus`

## Post-Deployment: Scaling Load

### Increase Load Tester Traffic

```bash
# Current: 1 pod sending 10 req/s = 10 total req/s per service
# Scale to 3 replicas: 30 total req/s per service

kubectl scale deployment load-tester --replicas=3 -n apps

# Watch RPS increase in Grafana APM Overview dashboard
# Each pod sends 10 req/s independently
```

### Simulate Failures

```bash
# Kill a pod to trigger errors
kubectl delete pod <pod-name> -n apps

# Watch error rate spike in Grafana
# Pod automatically restarts (due to deployment replicas)

# Scale down one app and watch error rate from load-tester increase
kubectl scale deployment go-app --replicas=0 -n apps
kubectl scale deployment go-app --replicas=1 -n apps  # Restore
```

## Troubleshooting

### 1. Prometheus Targets are DOWN

```bash
# Check ServiceMonitor labels
kubectl get servicemonitor -n apps
kubectl describe servicemonitor java-app -n apps

# ServiceMonitor MUST have: release: kube-prometheus
# If missing, edit the ServiceMonitor:
kubectl edit servicemonitor java-app -n apps
# Add label: release: kube-prometheus
```

### 2. No Metrics in Prometheus

Wait 2-3 minutes for Prometheus to scrape the targets (default interval: 30s).

```bash
# Check Prometheus scrape logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -f | grep scrape

# Check app metrics endpoint is reachable
kubectl port-forward -n apps svc/java-app 8080:8080
curl http://localhost:8080/actuator/prometheus
```

### 3. No Traces in Tempo

Check OTel Collector logs:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector -f

# Look for errors in OTLP ingestion or trace exports
# Common issues:
# - Apps cannot reach otel-collector.monitoring.svc:4317 (network)
# - Memory limiter processor has hard limit hit (logs show "memory_limiter dropping spans")
```

### 4. Grafana Can't Connect to Data Sources

```bash
# Verify datasources can reach Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
curl http://localhost:9090/-/healthy

# Verify datasources can reach Tempo
kubectl port-forward -n monitoring svc/tempo 3100:3100
curl http://localhost:3100/ready
```

### 5. EKS Cluster Not Responding

```bash
# Check cluster status
kubectl get cs

# Check if nodes are ready
kubectl get nodes

# If nodes are NotReady, check node logs
kubectl describe node <node-name>
kubectl logs -n kube-system -l k8s-app=aws-node -f
```

## Costs

### Monthly Estimate (3x t3.medium SPOT, us-east-2)

| Resource | Cost/Month |
|----------|-----------|
| EKS Control Plane | $72.00 |
| EC2 3x t3.medium SPOT | $27.00 |
| EBS Storage (Prometheus 20GiB) | $2.00 |
| EBS Storage (Tempo 5GiB) | $0.50 |
| Data Transfer | ~$1.00 |
| **Total** | **~$103/month** |

### Cost Reduction Tips

1. **Use Spot Instances** (already configured): ~60% savings
2. **Reduce cluster size**: Cluster will run on 2 nodes instead of 3
3. **Smaller storage**: Reduce Prometheus PVC from 20Gi to 10Gi
4. **Delete cluster when not in use**: `make destroy`

## Cleanup

### Remove All Resources

**WARNING:** This is irreversible and will delete all data.

```bash
# Destroy all resources
make destroy
# Type 'yes' to confirm

# This will:
# 1. Delete Kubernetes namespaces (monitoring, apps)
# 2. Delete EKS cluster
# 3. Delete VPC, subnets, NAT Gateway
# 4. Delete EC2 instances
# 5. Delete EBS volumes

# Takes ~5-10 minutes
```

### Partial Cleanup

```bash
# Delete only applications (keep monitoring stack)
kubectl delete namespace apps --wait=true

# Delete only monitoring stack (keep applications)
kubectl delete namespace monitoring --wait=true

# Note: Control plane and infrastructure still cost money
```

## Next Steps

1. **Explore Dashboards**
   - APM Overview: Services list with RED metrics
   - Service Detail: Drill-down with trace linking
   - JVM Metrics: Java internals

2. **Test Observability Features**
   - Scale load-tester pods
   - Watch metrics respond
   - Click trace links from Grafana to Tempo
   - View distributed traces across services

3. **Modify for Your Use Case**
   - Add custom endpoints to apps
   - Create custom dashboards in Grafana
   - Adjust histogram buckets for different latencies
   - Add alerting rules (AlertManager)

4. **Production Hardening** (beyond this portfolio)
   - TLS/HTTPS between components
   - RBAC for Kubernetes access
   - Network policies
   - Pod security policies
   - OIDC authentication for Grafana
   - Object storage for Tempo traces (S3)
   - Long-term metrics retention (Thanos)

## Support

For issues or questions:

1. Check the Troubleshooting section above
2. Review application logs: `kubectl logs -n <namespace> <pod-name>`
3. Check Kubernetes events: `kubectl describe pod <pod-name> -n <namespace>`
4. View Prometheus targets: `http://localhost:9090/targets`
5. Review Grafana datasource connectivity in UI

---

**Estimated Total Time: ~45-60 minutes**
(Mostly waiting for AWS resource creation)
