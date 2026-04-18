#!/bin/bash

set -e

echo "WARNING: This will destroy all AWS resources and delete all data."
echo ""
echo "This operation is IRREVERSIBLE."
echo ""

read -p "Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Destroying Kubernetes resources..."

# Delete applications
kubectl delete namespace apps --ignore-not-found=true --wait=true

# Delete monitoring stack
kubectl delete namespace monitoring --ignore-not-found=true --wait=true

echo "Waiting for namespaces to be fully deleted..."
sleep 10

echo ""
echo "Destroying AWS infrastructure with Terraform..."

REGION="${REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-observability-cluster}"

cd terraform

terraform destroy \
    -var region="${REGION}" \
    -var cluster_name="${CLUSTER_NAME}" \
    -auto-approve || true

cd ..

echo "✓ Teardown complete!"
echo ""
echo "Note: Some resources may take a few minutes to fully delete."
echo "      Check AWS Console for any remaining resources."
