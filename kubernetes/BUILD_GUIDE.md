[English](./BUILD_GUIDE.md) | [简体中文](./BUILD_GUIDE_CN.md)

# Complete Guide: Build from Source to Kubernetes Deployment

## Overview

- This guide is for engineers who need to build AI Gateway core components from source.
- It covers the full workflow: cloning source code, building container images, pushing to a registry, and deploying/integrating on Kubernetes.

### Components Covered

This guide covers building and deploying the following three core components:

1. **BFE (Data Plane)** – traffic forwarding and access control
   - GitHub: https://github.com/bfenetworks/bfe

2. **AI Gateway API (Control Plane)** – policy/config management APIs (includes Dashboard)
   - GitHub: https://github.com/rainway-ai-gateway/ai-gateway-api

3. **AI Gateway Web (Control Plane Dashboard)** – provides a graphical UI for the control plane
   - GitHub: https://github.com/rainway-ai-gateway/ai-gateway-web

4. **Service Controller** – discovers and syncs backend Services into the control plane
   - GitHub: https://github.com/bfenetworks/service-controller

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Build BFE](#build-bfe)
- [Build AI Gateway API](#build-ai-gateway-api)
- [Build Service Controller](#build-service-controller)
- [Kubernetes Deployment Integration](#kubernetes-deployment-integration)
- [Troubleshooting](#troubleshooting)
- [Log Collection](#log-collection)
- [References](#references)

---

## Prerequisites

### Development Environment

Before you start, ensure your machine meets these requirements:

#### Go

- **Required**: Go 1.22+
- **Verify**:
  ```bash
  go version
  # Expected: go version go1.22.x ...
  ```
- **Install**: https://go.dev/dl/

#### Docker

- **Required**: Docker with Buildx support (Docker Desktop 20.10+ or Docker Engine 19.03+)
- **Verify Docker**:
  ```bash
  docker --version
  # Expected: Docker version 20.10.x ...
  ```
- **Verify Buildx**:
  ```bash
  docker buildx version
  # Expected: github.com/docker/buildx vX.X.X ...
  ```
- **Install**:
  - macOS/Windows: https://www.docker.com/products/docker-desktop
  - Linux: https://docs.docker.com/engine/install/

#### Git

- **Required**: Git 2.0+
- **Verify**:
  ```bash
  git --version
  ```

### Optional Tools

#### kubectl (to validate Kubernetes deployment)

```bash
kubectl version --client
```

Install: https://kubernetes.io/docs/tasks/tools/

#### Container Registry Account

To push images to a remote registry, prepare one of:
- GitHub Container Registry (ghcr.io): https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- Docker Hub: https://hub.docker.com/
- A private registry

Example login commands:
```bash
# GitHub Container Registry
docker login ghcr.io -u <username>

# Docker Hub
docker login -u <username>
```

---

## Build BFE

BFE is the data plane component responsible for traffic forwarding and access control.

### 1. Get the Source

**Repo**: https://github.com/bfenetworks/bfe

```bash
# Clone the repo
git clone https://github.com/bfenetworks/bfe.git
```

### 2. Build Local Images

Run from the repo root:

```bash
make docker
```

Notes:
- Builds both **prod** and **debug** images.
- The image contains **BFE** and **conf-agent** (configuration agent).
- The tag is read from the `VERSION` file at the repo root.
- The tag is normalized with a `v` prefix (e.g., `1.8.0` → `v1.8.0`).

Example outputs (if `VERSION=1.8.0`):

```
bfe:v1.8.0        # prod
bfe:v1.8.0-debug  # debug
bfe:latest        # always points to the latest prod build
```

### 3. Verify Images

List images:

```bash
docker images | grep bfe
```

Run to validate:

```bash
docker run --rm \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 8421:8421 \
  bfe:latest
```

Validate endpoints:
- Monitor: http://127.0.0.1:8421/monitor
- Service: http://127.0.0.1:8080/ (may return 500 when no route matches; that’s expected)

### 4. Multi-arch Build & Push

To push images to a registry for Kubernetes:

```bash
make docker-push REGISTRY=<your-registry> CONF_AGENT_VERSION=v0.0.3
```

Required:
- `REGISTRY`: registry prefix (e.g. `ghcr.io/your-org`)

Optional:
- `PLATFORMS`: platforms (default `linux/amd64, linux/arm64`)
- `CONF_AGENT_VERSION`: a released conf-agent version
  - Tags: https://github.com/bfenetworks/conf-agent/tags

Examples:

```bash
# Push to GHCR (multi-arch)
make docker-push REGISTRY=ghcr.io/cc14514 CONF_AGENT_VERSION=v0.0.3

# Push to a private registry (amd64 only)
make docker-push \
  REGISTRY=registry.example.com \
  CONF_AGENT_VERSION=v0.0.3 \
  PLATFORMS=linux/amd64
```

### 5. Image Layout

Key directories inside the image:

```
/home/work/bfe/conf/           # BFE config
/home/work/bfe/log/            # BFE logs
/home/work/conf-agent/conf/    # conf-agent config
/home/work/conf-agent/log/     # conf-agent logs
```

Custom config mount (for testing):

```bash
docker run --rm \
  -p 8080:8080 -p 8443:8443 -p 8421:8421 \
  -v $(pwd)/bfe-conf:/home/work/bfe/conf \
  -v $(pwd)/confagent-conf:/home/work/conf-agent/conf/ \
  bfe:latest
```

---

## Build AI Gateway API

AI Gateway API is the control plane component providing policy/config APIs.

### 1. Get the Source

**Repo**: https://github.com/rainway-ai-gateway/ai-gateway-api

```bash
git clone https://github.com/rainway-ai-gateway/ai-gateway-api.git
cd ai-gateway-api
git checkout v0.0.1
```

### 2. Build Local Image

Run from the repo root:

```bash
make docker
```

Notes:
- The image includes the **AI Gateway API** backend and the **Dashboard** frontend.
- Dashboard assets are embedded into the image under `static/` during build.

Optional parameter: `DASHBOARD_VERSION`

The dashboard release version from https://github.com/rainway-ai-gateway/ai-gateway-web:

```bash
make docker DASHBOARD_VERSION=v0.0.1
```

Outputs:

```
ai-gateway-api:v<Version>  # versioned image
ai-gateway-api:latest      # latest
```

### 3. Verify Image

List images:

```bash
docker images | grep ai-gateway-api
```

Run to validate:

```bash
docker run -d \
  --name ai-gateway-api \
  -p 8183:8183 \
  ai-gateway-api:latest
```

Validate:
- Logs: `docker logs ai-gateway-api`
- Dashboard (requires correct database config):
  - URL: `http://localhost:8183`
  - Username: `admin`
  - Password: `admin`

### 4. Push Image

```bash
make docker-push REGISTRY=<your-registry> DASHBOARD_VERSION=v0.0.1
```

### 5. Image Layout & Config

Working directory: `/home/work/api-server`

```
/home/work/api-server/
├── api-server          # binary
├── conf/               # config (can be overridden via volume)
├── static/             # Dashboard static assets
└── log/                # logs
```

Recommended mounts:

```bash
docker run -d \
  --name ai-gateway-api \
  -p 8183:8183 \
  -v $(pwd)/conf:/home/work/api-server/conf \
  -v $(pwd)/log:/home/work/api-server/log \
  ai-gateway-api:latest
```

Config notes:
- `conf/` contains DB and Redis connection settings.

---

## Build AI Gateway Web

When building the `ai-gateway-api` image, it automatically pulls the specified version from the `ai-gateway-web` releases, so you typically **do not need to build it separately**.

### Build from Source

If you need to build from source, refer to the build guide in the `ai-gateway-web` repository:

**GitHub Repository**: [https://github.com/rainway-ai-gateway/ai-gateway-web](https://github.com/rainway-ai-gateway/ai-gateway-web)

**Build Guide**: [BUILD_GUIDE.md](https://github.com/rainway-ai-gateway/ai-gateway-web/blob/develop/BUILD_GUIDE.md)

---

## Build Service Controller

Service Controller discovers Kubernetes Services and registers eligible ones into the AI Gateway control plane.

### 1. Get the Source

**Repo**: https://github.com/bfenetworks/service-controller

```bash
git clone https://github.com/bfenetworks/service-controller.git
```

### 2. Build Local Image

Run from the repo root:

```bash
make docker
```

Output:

```
service-controller:latest
```

### 3. Verify

List images:

```bash
docker images | grep service-controller
```

Verify in Kubernetes (recommended):

```bash
# Apply manifest (requires AI Gateway API address and Token pre-configured)
kubectl apply -f ./examples/service-controller-endpoints.yaml

# Check status
kubectl get deployment bfe-service-controller
kubectl get pods | grep service-controller

# Logs
kubectl logs -f <pod-name>
```

Health endpoints:
- Readiness: `GET /ready`
- Liveness: `GET /healthz`

### 4. Multi-arch Push

```bash
make docker-push REGISTRY=<your-registry>
```

### 5. Kubernetes Deployment Notes

Prerequisites:
- Kubernetes v1.20+

Key args in `examples/service-controller-endpoints.yaml`:

```yaml
......
          args:
            - '-bfe-api-addr=http://ai-gateway-api.ai-gateway-system.svc.cluster.local:8183'
            - '-bfe-api-token=Token eT5QWkLhQmp6lO4NWxAc'
            - '-k8s-cluster-name=szyf'
            - '-namespace=default'
......
```

- `bfe-api-addr`: AI Gateway API address (control plane)
- `bfe-api-token`: API auth Token (create from Dashboard)
- `namespace`: which Kubernetes namespace(s) to watch for backend Services
  - In this demo, the backend test service (llm-d inference simulator) is deployed in the `default` namespace, so set it to: `default`
  - Control plane/data plane runs in `ai-gateway-system`, but discovered backend Services can live in other namespaces (controlled by this arg)


### Backend Service Requirements

Service Controller discovers backend services by watching Kubernetes Service **labels** and will sync eligible services into the AI Gateway control plane.

To be discovered and registered, a backend Service must meet all of these:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  namespace: <namespace>
  labels:
    bfe-product: AI_product  # required: fixed value
spec:
  ports:
    - name: http             # required: port name must be set
      port: 8080
      targetPort: 80
```

Notes:
- `bfe-product`: **required and must be exactly `AI_product`**
  - The control plane creates a fixed product line named `AI_product` during DB initialization.
  - Currently the Dashboard does not support creating new product lines.
  - Therefore all backend Services must use `bfe-product: AI_product`.
  - Service Controller syncs discovered Services into this `AI_product` product line.
- `spec.ports[].name`: **required**
  - Service Controller only syncs ports that have a `name`.
  - The name can be anything meaningful: `http`, `https`, `grpc`, etc.

---

## Kubernetes Deployment Integration

This section shows how to integrate and deploy the three built images on a Kubernetes cluster.

### 1. Cluster Preparation

#### Verify cluster access

```bash
# Check kubectl context
kubectl cluster-info

# Check nodes
kubectl get nodes
```

#### Create namespace

This project uses a dedicated namespace to isolate resources:

```bash
kubectl apply -f kubernetes/namespace.yaml
```

Verify:

```bash
kubectl get namespace ai-gateway-system
```

### 2. Update Image References

Edit `kubernetes/kustomization.yaml` and replace the example images with your built/pushed images.

> The `kustomization.yaml` already includes default image tags from `ghcr.io` for immediate use. Override only if you built your own images or use a mirror registry.

```yaml
images:
  # 1. BFE data plane image (includes conf-agent)
  - name: ghcr.io/bfenetworks/bfe
    newName: ghcr.io/<your-org>/bfe
    newTag: <your-vsn>

  # 2. AI Gateway API control plane image (includes Dashboard)
  - name: ghcr.io/rainway-ai-gateway/ai-gateway-api
    newName: ghcr.io/<your-org>/ai-gateway-api
    newTag: <your-vsn>

  # 3. Service Controller
  - name: ghcr.io/bfenetworks/service-controller
    newName: ghcr.io/<your-org>/service-controller
    newTag: <your-vsn>

  # Other images (e.g. mysql/redis) can be adjusted as needed
```

### 3. Configure Image Pull Credentials (Private Registry)

If you use a private registry, create an `imagePullSecret` first:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<your-username> \
  --docker-password=<your-token> \
  --namespace=ai-gateway-system
```

Then reference it in the deployment manifests (edit `kubernetes/*-deploy.yaml`):

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-secret
```

### 4. Configure External Database

Using the built-in demo database (default):
- The demo uses in-cluster MySQL with `emptyDir` storage (data will be lost on restart).
- Fine for demos/dev; **not recommended for production**.

Using an external database (recommended for production):
- If you have an external MySQL and have run the DB init script
  - DB DDL: see `db_ddl.sql` in this repository
- Update AI Gateway API DB config accordingly.

#### 4.1 Update ai-gateway-configmap.yaml

Edit `kubernetes/ai-gateway-configmap.yaml` and update connection info:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-gateway-api-config
data:
  ai_gateway_api.toml: |-
    # ---------------------------------
    # AI GATEWAY API Config
    ......
    # ---------------------------------
    # Database Config
    # see https://github.com/go-sql-driver/mysql/blob/master/dsn.go#L37
    [Databases.bfe_db]
    DBName               = "<your-mysql-db-name>"
    # MySQL service in the same namespace
    Addr                 = "<your-mysql-host>:<your-mysql-port>"
    Net                  = "tcp"
    User                 = "<your-mysql-user>"
    Passwd               = "<your-mysql-password>"
    MultiStatements      = true
    MaxAllowedPacket     = 67108864
    ParseTime            = true
    AllowNativePasswords = true
    ......
```

#### 4.2 Update kustomization.yaml

Disable the demo MySQL deployment by commenting it out in `kubernetes/kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  # - mysql-deploy.yaml          # comment out when using external MySQL
  - redis-deploy.yaml
  - bfe-configmap.yaml
  - bfe-deploy.yaml
  - ai-gateway-configmap.yaml
  - ai-gateway-deploy.yaml
  - service-controller-deploy.yaml
```

### 5. One-command Deploy

Deploy everything with Kustomize:

```bash
kubectl apply -k kubernetes/
```

Notes:
- `-k` uses Kustomize to orchestrate resources.
- Applies image overrides from `kustomization.yaml`.
- Creates resources in the correct order (Namespace, ConfigMaps, Deployments, Services, etc.).

Deployed resources (Namespace: `ai-gateway-system`):
- MySQL (or skipped if using external MySQL)
- Redis
- BFE (includes conf-agent)
- AI Gateway API (includes Dashboard)
- Service Controller

### 6. Deploy Test Service (Validate Routing)

About the demo backend service (llm-d inference simulator):

This repo provides a demo backend service manifest that runs an LLM inference simulator (Deployment `vllm-llama3-8b-instruct`, Service `vllm-llama3-8b-instruct-svc`). It can be used as a backend to validate Service discovery and BFE routing/forwarding.

Deploy:

```bash
kubectl apply -f kubernetes/llm-d-inference-sim-deploy.yaml
```

Key notes:
- The demo backend service is deployed in the `default` namespace (not `ai-gateway-system`).
- If you want to use a different image/model args, edit `kubernetes/llm-d-inference-sim-deploy.yaml`.
- You must configure forwarding rules in the Dashboard before accessing the backend through BFE.

The Service must include required labels and named ports:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vllm-llama3-8b-instruct-svc
  namespace: default
  labels:
    bfe-product: AI_product  # required: Service Controller uses this to discover
spec:
  ports:
    - name: http             # required: port must be named
      port: 8000
      targetPort: 8000
  selector:
    app: vllm-llama3-8b-instruct
```

### 7. Validate Deployment

Check Pods:

```bash
kubectl get pods -n ai-gateway-system
```

Expected output:

```
NAME                                READY   STATUS    RESTARTS   AGE
ai-gateway-api-xxx                  1/1     Running   0          5m
bfe-xxx                             1/1     Running   0          5m
mysql-xxx                           1/1     Running   0          6m
redis-xxx                           1/1     Running   0          6m
service-controller-xxx              1/1     Running   0          5m
```

Access control plane (configure forwarding rules):

Open: `http://<NodeIP>:30183`

- Username: `admin`
- Password: `admin`

Test routing:

If forwarding rules are not configured correctly, you will get HTTP 500:

```bash
curl http://<NodeIP>:30080/
```

---

## Troubleshooting

### 1) Image pull failures (ImagePullBackOff / ErrImagePull)

```bash
kubectl get pods -n ai-gateway-system
kubectl describe pod -n ai-gateway-system <pod-name>
```

Common causes:
- `images:` overrides in `kubernetes/kustomization.yaml` are not updated correctly (repo/tag does not exist)
- `imagePullSecrets` is missing (or Secret created in the wrong namespace)

### 2) Control plane not starting (ai-gateway-api CrashLoopBackOff)

```bash
kubectl logs -n ai-gateway-system -l app=ai-gateway-api --tail=200
kubectl get pods -n ai-gateway-system -l app=mysql
kubectl get pods -n ai-gateway-system -l app=redis
```

Common causes:
- MySQL/Redis is not ready or connection settings are incorrect (more likely when using external DB)
- DB init script was not applied (external MySQL scenario)

### 3) Service Controller does not discover/sync the demo backend service

```bash
# Does the Service have Endpoints?
kubectl get endpoints vllm-llama3-8b-instruct-svc -n default

# Does the Service have the required fixed label?
kubectl get svc vllm-llama3-8b-instruct-svc -n default -o yaml | grep -A3 "labels:"

# Service Controller logs
kubectl logs -n ai-gateway-system -l app=service-controller --tail=200
```

Checkpoints:
- The backend Service must include `bfe-product: AI_product`.
- Service Controller’s watched namespace must include `default` (this repo’s demo manifests watch `default`).

### 4) BFE returns 500

```bash
curl -v http://<NodeIP>:30080/
kubectl logs -n ai-gateway-system -l app=bfe --tail=200
```

Notes:
- 500 is expected when no forwarding rule is configured in the Dashboard.
- If rules exist but 500 persists, confirm the backend is synced by Service Controller (see previous section).

## Log Collection

```bash
# Create log directory
mkdir -p /tmp/ai-gateway-logs

# Collect component logs
kubectl logs -n ai-gateway-system -l app=bfe > /tmp/ai-gateway-logs/bfe.log
kubectl logs -n ai-gateway-system -l app=ai-gateway-api > /tmp/ai-gateway-logs/api.log
kubectl logs -n ai-gateway-system -l app=service-controller > /tmp/ai-gateway-logs/controller.log
kubectl logs -n ai-gateway-system -l app=mysql > /tmp/ai-gateway-logs/mysql.log
kubectl logs -n ai-gateway-system -l app=redis > /tmp/ai-gateway-logs/redis.log

# Collect events
kubectl get events -n ai-gateway-system --sort-by='.lastTimestamp' > /tmp/ai-gateway-logs/events.log
```

View live logs:

```bash
kubectl logs -f -n ai-gateway-system -l app=bfe --all-containers=true --tail=100
```

---

## References

### Official Docs

- **BFE**
  - GitHub: https://github.com/bfenetworks/bfe
  - Docs: https://www.bfe-networks.net/
  - Config reference: https://www.bfe-networks.net/en_us/configuration/overview/

- **AI Gateway API**
  - GitHub: https://github.com/rainway-ai-gateway/ai-gateway-api
  - Dashboard frontend: https://github.com/rainway-ai-gateway/ai-gateway-web

- **llm-d inference simulator (demo backend)**
  - GitHub: https://github.com/llm-d/llm-d-inference-sim

- **Service Controller**
  - GitHub: https://github.com/bfenetworks/service-controller
  - Kubernetes integration: https://github.com/bfenetworks/service-controller/blob/main/README.md

### Stack Docs

- **Kubernetes**
  - Docs: https://kubernetes.io/docs/
  - Kustomize: https://kubectl.docs.kubernetes.io/references/kustomize/

- **Docker**
  - Docker Buildx: https://docs.docker.com/buildx/working-with-buildx/
  - Multi-platform builds: https://docs.docker.com/build/building/multi-platform/
