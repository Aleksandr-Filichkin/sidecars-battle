APP_NAME ?= echo
VERSION ?= 0.0.1-SNAPSHOT
AWS_REGION ?= us-east-1
# Auto-detect AWS account for default ECR registry if not provided
ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
ECR_REGISTRY ?= $(if $(ACCOUNT_ID),$(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com,)

PLATFORM ?= linux/arm64

# Repository names
APP_REPO ?= $(APP_NAME)
TRAEFIK_REPO ?= $(APP_NAME)-traefik

# Images
APP_IMAGE ?= $(ECR_REGISTRY)/$(APP_REPO):$(VERSION)
TRAEFIK_IMAGE ?= $(ECR_REGISTRY)/$(TRAEFIK_REPO):$(VERSION)
# Back-compat for previous variable name
IMAGE ?= $(APP_IMAGE)

.PHONY: build jar docker-login docker-build docker-push ecr-create tf-init tf-apply tf-destroy deploy

build:
	cd app && mvn -q -DskipTests package

jar: build
	@ls -lh app/target/echo-$(VERSION).jar

docker-login:
	@test -n "$(ECR_REGISTRY)" || (echo "ECR_REGISTRY is empty and AWS account not detected. Export ECR_REGISTRY or configure AWS CLI." && exit 1)
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY)

# Create ECR repositories if missing
ecr-create:
	@test -n "$(ECR_REGISTRY)" || (echo "ECR_REGISTRY is empty and AWS account not detected. Export ECR_REGISTRY or configure AWS CLI." && exit 1)
	@aws ecr describe-repositories --repository-names $(APP_REPO) --region $(AWS_REGION) >/dev/null 2>&1 || \
		aws ecr create-repository --repository-name $(APP_REPO) --image-scanning-configuration scanOnPush=true --region $(AWS_REGION) >/dev/null
	@true

# Build app image
docker-build: jar
	docker build --platform $(PLATFORM) -t $(APP_IMAGE) ./app

# Push image
 docker-push: docker-build docker-login
	docker push $(APP_IMAGE)

tf-init:
	cd infra && terraform init

# Pass app and traefik images into Terraform
 tf-apply:
	cd infra && terraform apply -auto-approve -var "region=$(AWS_REGION)" -var "app_name=$(APP_NAME)" -var "image=$(APP_IMAGE)"

 tf-destroy:
	cd infra && terraform destroy -auto-approve -var "region=$(AWS_REGION)" -var "app_name=$(APP_NAME)" -var "image=$(APP_IMAGE)"

# One-shot deploy: create repos, push both images, and apply infra
 deploy: ecr-create docker-push tf-apply




