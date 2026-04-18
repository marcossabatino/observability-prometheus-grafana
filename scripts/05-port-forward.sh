#!/bin/bash

echo "Setting up port-forwards..."
echo ""
echo "Grafana will be available at http://localhost:3000"
echo "  Username: admin"
echo "  Password: observability123"
echo ""
echo "Prometheus will be available at http://localhost:9090"
echo "Tempo will be available at http://localhost:3100"
echo ""
echo "Press Ctrl+C to stop port-forwarding"
echo ""

# Start port-forwards in background
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80 &
GRAFANA_PID=$!

kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
PROMETHEUS_PID=$!

kubectl port-forward -n monitoring svc/tempo 3100:3100 &
TEMPO_PID=$!

# Trap Ctrl+C to clean up
trap "kill $GRAFANA_PID $PROMETHEUS_PID $TEMPO_PID" INT

# Wait for all background jobs
wait
