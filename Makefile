PROJECT_NAME := eks-auto-mode-demo
AWS_REGION := us-east-1
TF_DIR := terraform

# ------------------------------------------------------------------------------
# Terraform
# ------------------------------------------------------------------------------
.PHONY: init plan apply destroy

init:
	cd $(TF_DIR) && terraform init

plan:
	cd $(TF_DIR) && terraform plan

apply:
	cd $(TF_DIR) && terraform apply

destroy:
	cd $(TF_DIR) && terraform destroy

# ------------------------------------------------------------------------------
# Kubernetes
# ------------------------------------------------------------------------------
.PHONY: configure-kubectl deploy-app delete-app

configure-kubectl:
	aws eks update-kubeconfig --name $(PROJECT_NAME) --region $(AWS_REGION)

deploy-app: configure-kubectl
	$(eval ECR_URL := $(shell cd $(TF_DIR) && terraform output -raw ecr_repository_url))
	kubectl apply -f k8s/rbac.yaml
	sed "s|ECR_REPOSITORY_URL|$(ECR_URL)|g" k8s/deployment.yaml | kubectl apply -f -
	kubectl apply -f k8s/service.yaml
	kubectl apply -f k8s/hpa.yaml
	kubectl apply -f k8s/pdb.yaml
	@echo "Load balancing (IngressClass + Ingress) is managed by Terraform"

delete-app:
	kubectl delete -f k8s/ --ignore-not-found

# ------------------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------------------
.PHONY: docker-build docker-push

docker-build:
	$(eval ECR_URL := $(shell cd $(TF_DIR) && terraform output -raw ecr_repository_url))
	$(eval ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text))
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	cd app && docker buildx build --platform linux/amd64,linux/arm64 -t $(ECR_URL):latest --push .

docker-push:
	@echo "docker-push is no longer needed - docker-build now builds multi-arch and pushes directly to ECR"

# ------------------------------------------------------------------------------
# Scaling demo
# ------------------------------------------------------------------------------
.PHONY: demo-scale-up demo-scale-down demo-load-start demo-load-stop demo-watch

demo-scale-up:
	@echo "Scaling demo-api to 15 replicas to trigger node provisioning..."
	kubectl scale deployment demo-api -n demo --replicas=15
	@echo "Watch node provisioning with: make demo-watch"

demo-scale-down:
	@echo "Scaling demo-api back to 2 replicas..."
	kubectl scale deployment demo-api -n demo --replicas=2
	@echo "Watch node consolidation with: make demo-watch"

demo-load-start:
	@echo "Starting load generator to trigger HPA scaling..."
	kubectl apply -f k8s/load-generator.yaml
	@echo "Watch HPA and node scaling with: make demo-watch"

demo-load-stop:
	@echo "Stopping load generator..."
	kubectl delete -f k8s/load-generator.yaml --ignore-not-found
	@echo "HPA will scale pods down, then Auto Mode consolidates nodes"

demo-watch:
	@echo "=== HPA Status ==="
	kubectl get hpa -n demo
	@echo ""
	@echo "=== Pods ==="
	kubectl get pods -n demo -o wide
	@echo ""
	@echo "=== Nodes ==="
	kubectl get nodes -o wide
	@echo ""
	@echo "=== NodePools ==="
	kubectl get nodepools
	@echo ""
	@echo "=== Recent Auto Mode Events ==="
	kubectl get events -A --sort-by='.lastTimestamp' | grep -E 'Nominated|Launched|Disruption|Consolidat' | tail -10

# ------------------------------------------------------------------------------
# Cluster inspection
# ------------------------------------------------------------------------------
.PHONY: status nodes nodepools pods events

status:
	kubectl get nodes -o wide
	@echo "---"
	kubectl get nodepools
	@echo "---"
	kubectl get all -n demo

nodes:
	kubectl get nodes -o wide --show-labels

nodepools:
	kubectl get nodepools
	kubectl describe nodepool general-purpose

pods:
	kubectl get pods -n demo -o wide

events:
	kubectl get events -A --sort-by='.lastTimestamp' | tail -20
