#!/bin/bash

set -e

echo "Installing monitoring stack..."

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Create monitoring namespace
echo "Creating monitoring namespace..."
kubectl apply -f kubernetes/monitoring/namespace.yaml

# Install kube-prometheus-stack
echo "Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kubernetes/monitoring/kube-prometheus-stack/values.yaml \
  --wait

# Install Grafana Tempo
echo "Installing Grafana Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace monitoring \
  --values kubernetes/monitoring/tempo/values.yaml \
  --wait

# Install OpenTelemetry Collector
echo "Installing OpenTelemetry Collector..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  --values kubernetes/monitoring/otel-collector/values.yaml \
  --wait

# Wait for all pods to be running
echo "Waiting for all monitoring pods to be running..."
kubectl wait --for=condition=ready pod -l release=kube-prometheus -n monitoring --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tempo -n monitoring --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=otel-collector -n monitoring --timeout=300s || true

echo "✓ Monitoring stack installed successfully!"
echo ""
echo "To access Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80"
echo ""
echo "To access Prometheus:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
echo ""
echo "To access Tempo:"
echo "  kubectl port-forward -n monitoring svc/tempo 3100:3100"
