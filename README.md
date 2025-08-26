### Sidecars Battle: Spring WebFlux Echo with Envoy and Traefik

A small, production-style demo that contrasts two sidecar proxies (Envoy and Traefik) in front of a reactive Spring Boot (WebFlux) echo service. It includes local builds, container images, and an AWS ECS Fargate deployment via Terraform.

### Features
- **Reactive app (Spring WebFlux)**: non-blocking echo endpoints and health checks
- **Security**:
  - App-level OAuth2/JWT required for `GET /internal/**` (Spring Security Resource Server)
  - Proxy-level JWT for `GET /private/**` (implemented at the sidecar: Envoy or Traefik)
- **Sidecars**:
  - Envoy v1.31.0 example with JWT filter and readiness probe
  - Traefik v2.10 with a JWT plugin and `/ping` health endpoint
- **Infra**: Terraform module for AWS ECS Fargate + ALB + ECR

### Architecture (high level)
```
Client -> [ALB:80] -> [Sidecar on :10000] -> [App on :8080]

Sidecar options:
  - Envoy (example config provided)
  - Traefik (used in the ECS task definition)

App: Spring Boot WebFlux
```

### Key components and ports
- **App (Spring Boot)**: `:8080`
- **Traefik sidecar**: `:10000` (with `/ping` health)
- **Envoy sidecar**: `:10000` (admin `:9901`, `/ready` health)
- **AWS ALB**: listens on `:80`, forwards to sidecar `:10000`

### Endpoints (application)
- `GET /info` — basic app info
- `GET /private/echo/{msg}/{delayMs}` — echo response, proxy-level JWT required when traversing sidecar (no Spring security at the app level)
- `GET /internal/echo/{msg}/{delayMs}` — echo response, app-level OAuth2/JWT required by Spring Security
- Actuator: `GET /actuator/health`, `GET /actuator/health/readiness`, `GET /actuator/health/liveness`

Notes on security and headers:
- Sidecars forward JWT-derived identity in header `X-Forwarded-User: <sub>`.
- JWKS used: `https://auth.example.com/.well-known/jwks.json`
- Issuer for Envoy: `https://id.example.com/`

### Requirements
- Java 21, Maven 3.9+
- Docker 24+
- AWS CLI v2 (configured credentials) if pushing to ECR / deploying
- Terraform 1.5+

### Quick start (local, app only)
Run the app directly (without sidecar) and hit endpoints on `:8080`.

```bash
# Build JAR
make build

# Run locally (one of the following)
java -jar app/target/echo-0.0.1-SNAPSHOT.jar
# or
cd app && mvn spring-boot:run

# Sample requests
curl -s http://localhost:8080/info | jq
curl -s http://localhost:8080/private/echo/hello/250 | jq

# The internal path requires a valid JWT because Spring protects /internal/**
curl -s -H "Authorization: Bearer <YOUR_JWT>" \
  http://localhost:8080/internal/echo/hi/300 | jq
```

Sidecars are primarily configured for the ECS task model where the sidecar and app share a network namespace (127.0.0.1). For local sidecar testing you would need to run both containers with compatible networking so that the sidecar reaches the app at `127.0.0.1:8080` (or adjust configs accordingly).

### Build container images
Default image/tag variables (see `Makefile`):
- `APP_NAME=echo`
- `VERSION=0.0.1-SNAPSHOT`
- `AWS_REGION=us-east-1`
- `ECR_REGISTRY` is auto-detected from your AWS account unless you override it

```bash
# Build app JAR and Docker image
make docker-build

# (Optional) Log in to ECR explicitly
make docker-login

# Push app image to ECR
make docker-push

# Build Traefik sidecar image and push (used by Terraform stack)
docker build --platform linux/arm64 -t \ 
  "$ECR_REGISTRY/${APP_NAME}-traefik:${VERSION}" ./traefik
aws ecr create-repository --repository-name "${APP_NAME}-traefik" --region "$AWS_REGION" 2>/dev/null || true
aws ecr get-login-password --region "$AWS_REGION" | \ 
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker push "$ECR_REGISTRY/${APP_NAME}-traefik:${VERSION}"

# (Optional) Build Envoy image and push (example provided; not used by ECS task)
docker build --platform linux/arm64 -t \ 
  "$ECR_REGISTRY/${APP_NAME}-envoy:${VERSION}" ./envoy
aws ecr create-repository --repository-name "${APP_NAME}-envoy" --region "$AWS_REGION" 2>/dev/null || true
docker push "$ECR_REGISTRY/${APP_NAME}-envoy:${VERSION}"
```

### AWS deployment (ECS Fargate + ALB)
The Terraform stack creates: ECR repos, ECS cluster/service, ALB, security groups, logs.

Variables of interest (see `infra/variables.tf`):
- `region` (default `us-east-1`)
- `app_name` (default `echo`)
- `image_tag` (tag for the app image)
- `traefik_image_tag` (tag for the Traefik image)
- `desired_count`, `task_cpu`, `task_memory`

Workflow:
```bash
# 1) Initialize Terraform
cd infra
terraform init

# 2) Apply. Pass the tags you pushed above (VERSION)
terraform apply \
  -auto-approve \
  -var "region=${AWS_REGION}" \
  -var "app_name=${APP_NAME}" \
  -var "image_tag=${VERSION}" \
  -var "traefik_image_tag=${VERSION}"

# 3) Outputs
terraform output alb_url
```

The ALB will forward traffic to Traefik on `:10000`. Traefik routes:
- All paths except `/private` and `/ping` go to the app directly
- `/private/**` requires a valid JWT (checked at the proxy)
- `/ping` is Traefik’s own health endpoint (used by ALB health checks)

### Testing via ALB
```bash
ALB_URL=$(terraform -chdir=infra output -raw alb_url)

curl -s "$ALB_URL/info" | jq
curl -s "$ALB_URL/private/echo/hello/200" | jq            # requires JWT at proxy
curl -s -H "Authorization: Bearer <YOUR_JWT>" \
  "$ALB_URL/internal/echo/hi/300" | jq                    # app-level JWT

# Health
curl -s "$ALB_URL/ping"     # 200 OK (Traefik ping)
```

### Makefile targets (convenience)
Common targets provided in the root `Makefile`:
- `build` — Maven build (skips tests)
- `jar` — lists the built JAR
- `docker-build` — builds the app image
- `docker-login` — logs in to ECR
- `docker-push` — builds and pushes the app image
- `ecr-create` — ensures the app ECR repo exists
- `tf-init` — terraform init (in `infra`)
- `tf-apply` — terraform apply (in `infra`)
- `tf-destroy` — terraform destroy (in `infra`)
- `deploy` — ecr-create + docker-push + tf-apply

Note: The Terraform variables used by the stack are `image_tag` and `traefik_image_tag`. Ensure you pass tags that match the images you pushed.

### Configuration references
- App Spring configuration: `app/src/main/resources/application.yml`
- Security (Spring): `app/src/main/java/com/example/echo/config/SecurityConfig.java`
- Custom JWT validator: `app/src/main/java/com/example/echo/config/CustomJwtValidator.java`
- Envoy config: `envoy/envoy.yaml`
- Traefik configs: `traefik/traefik.yml`, `traefik/traefik-dynamic.yml`

### Troubleshooting
- 401/403 on `/private/**` through sidecar: ensure your JWT is valid against the configured JWKS and issuer
- 401 on `/internal/**` to the app: Spring Security requires a valid JWT on these paths
- ALB health failing: confirm `GET /ping` on Traefik returns 200, and ECS task is healthy
- Sidecar cannot reach app locally: configs assume `127.0.0.1:8080` inside the same task; adjust for local multi-container testing

### License
This project is licensed under the MIT License. See `LICENSE` for details.


