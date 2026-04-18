.PHONY: help build push infra-up cluster-config stack-up apps-up all validate status port-forward destroy

REGION ?= us-east-2
CLUSTER_NAME ?= observability-cluster
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text)
REGISTRY ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
TERRAFORM_DIR := terraform

help:
	@echo "Observability Portfolio - Available Targets"
	@echo ""
	@echo "Infrastructure:"
	@echo "  make infra-up             Create VPC and EKS cluster (15 min)"
	@echo "  make cluster-config       Configure kubectl for the cluster"
	@echo ""
	@echo "Monitoring Stack:"
	@echo "  make stack-up             Install Prometheus, Grafana, Tempo, OTel"
	@echo ""
	@echo "Applications:"
	@echo "  make build                Build Docker images for all apps"
	@echo "  make push                 Push images to ECR"
	@echo "  make apps-up              Deploy apps to Kubernetes"
	@echo ""
	@echo "Utilities:"
	@echo "  make all                  Full deploy: build + push + infra-up + stack-up + apps-up"
	@echo "  make validate             Validate Terraform and Kubernetes manifests"
	@echo "  make status               Show all pods and services"
	@echo "  make port-forward         Port-forward Grafana (3000), Prometheus (9090), Tempo (3100)"
	@echo "  make destroy              Destroy all AWS resources (CAUTION)"
	@echo ""

build:
	@echo "Building Docker images..."
	docker build -t $(REGISTRY)/java-app:latest ./apps/java-app
	docker build -t $(REGISTRY)/go-app:latest ./apps/go-app
	docker build -t $(REGISTRY)/python-app:latest ./apps/python-app
	docker build -t $(REGISTRY)/load-tester:latest ./apps/load-tester
	@echo "✓ All images built"

push: build
	@echo "Pushing images to ECR..."
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(REGISTRY)
	docker push $(REGISTRY)/java-app:latest
	docker push $(REGISTRY)/go-app:latest
	docker push $(REGISTRY)/python-app:latest
	docker push $(REGISTRY)/load-tester:latest
	@echo "✓ All images pushed"

infra-up:
	@echo "Creating AWS infrastructure..."
	cd $(TERRAFORM_DIR) && terraform init
	cd $(TERRAFORM_DIR) && terraform plan -var region=$(REGION) -var cluster_name=$(CLUSTER_NAME) -out=tfplan
	cd $(TERRAFORM_DIR) && terraform apply tfplan
	@echo "✓ Infrastructure deployed"

cluster-config:
	@echo "Configuring kubectl..."
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
	@echo "✓ Kubeconfig updated"

stack-up:
	@echo "Installing monitoring stack..."
	scripts/03-install-monitoring.sh
	@echo "✓ Monitoring stack installed"

apps-up:
	@echo "Deploying applications..."
	scripts/04-deploy-apps.sh
	@echo "✓ Applications deployed"

all: build push infra-up cluster-config stack-up apps-up
	@echo "✓ Full deployment complete!"

validate:
	@echo "Validating Terraform..."
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive . || terraform fmt -recursive .
	cd $(TERRAFORM_DIR) && terraform validate
	@echo "Validating Kubernetes manifests..."
	kubectl apply --dry-run=client -f kubernetes/ -R
	@echo "✓ All validations passed"

status:
	@echo "=== Nodes ==="
	kubectl get nodes
	@echo ""
	@echo "=== All Pods ==="
	kubectl get pods --all-namespaces
	@echo ""
	@echo "=== Services ==="
	kubectl get svc --all-namespaces

port-forward:
	@echo "Setting up port-forwards..."
	@echo "Grafana: http://localhost:3000 (admin/observability123)"
	@echo "Prometheus: http://localhost:9090"
	@echo "Tempo: http://localhost:3100"
	@echo ""
	@kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80 &
	@kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
	@kubectl port-forward -n monitoring svc/tempo 3100:3100 &
	@wait

destroy:
	@echo "WARNING: This will destroy ALL AWS resources."
	@echo "Cluster name: $(CLUSTER_NAME)"
	@echo "Region: $(REGION)"
	@read -p "Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cd $(TERRAFORM_DIR) && terraform destroy -var region=$(REGION) -var cluster_name=$(CLUSTER_NAME); \
	else \
		echo "Cancelled"; \
	fi

.DEFAULT_GOAL := help
