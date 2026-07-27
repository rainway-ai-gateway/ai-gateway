[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg)](https://go.dev/)

[English](README.md) | [简体中文](README_CN.md)

# YF AI Gateway

AI Gateway is an open-source AI traffic gateway built on top of [BFE](https://github.com/bfenetworks/bfe). It provides unified API management, authentication, rate limiting, and intelligent routing for multiple AI model providers, giving developers a single entry point for all AI services.

## Architecture

![Architecture](./.images/deploy_architecture_ai.png)

AI Gateway consists of the following core components:

| Component | Role | Description | Repository |
|---|---|---|---|
| **AI Gateway API** | Control plane | Open APIs for policy/config management and distribution | [yf-networks/ai-gateway-api](https://github.com/yf-networks/ai-gateway-api) |
| **Dashboard** | Admin console | Web UI for visual management (bundled in API image) | [yf-networks/ai-gateway-web](https://github.com/yf-networks/ai-gateway-web) |
| **BFE** | Data plane | Traffic forwarding and access control | [bfenetworks/bfe](https://github.com/bfenetworks/bfe) |
| **Conf Agent** | Config agent | Fetches config and triggers BFE hot reload | [bfenetworks/conf-agent](https://github.com/bfenetworks/conf-agent) |
| **Log Reader** | Log collector | Reads BFE access logs and sends to Kafka | [bfenetworks/log-reader](https://github.com/bfenetworks/log-reader) |
| **Service Controller** | Service discovery | Discovers and syncs K8s backend services (K8s only) | [bfenetworks/service-controller](https://github.com/bfenetworks/service-controller) |

## Key Features

- **AI route management**: Route configuration for multiple AI model providers (OpenAI, DeepSeek, Qwen, etc.)
- **API key management**: Create, delete, and validate API keys for AI services
- **Domain management**: Bind domains and configure routing rules
- **Cluster/sub-cluster management**: Manage backend service clusters
- **Traffic management**: Traffic allocation and scheduling
- **Dashboard**: Web-based management console (bundled in API image)
- **Config export**: Export configuration for BFE data plane and Conf Agent

## Deployment Modes

| Mode | Command | Use Case |
|---|---|---|
| **Container** | `docker compose up -d` | Development, demo, small-scale |
| **Kubernetes** | `kubectl apply -k kubernetes/` | Production, cluster |

## Quick Start

### Docker Compose (Recommended — No Config Needed)

`docker-compose.yml` integrates MySQL 8 + Redis 6.2 + AI Gateway (with BFE + Conf Agent + Log Reader). Configs are pre-set with Docker network DNS — works out of the box.

| Container | DNS name | Port |
|---|---|---|
| MySQL 8 | `mysql.ai-gateway-system` | 3306 |
| Redis 6.2 | `redis.ai-gateway-system` | 6379 |
| AI Gateway | — | 8080, 8183, 8992 |

> **Prerequisite**: Docker Compose plugin. If `docker compose` is not available:
> 1. Download the binary from https://github.com/docker/compose/releases
> 2. Place it at `$HOME/.docker/cli-plugins/docker-compose`
> 3. `chmod +x $HOME/.docker/cli-plugins/docker-compose`
>
> Or use standalone binary: `docker-compose up -d`

```bash
git clone https://github.com/yf-networks/ai-gateway.git
cd ai-gateway
docker compose up -d
```

> **If you get "not a directory" mount errors**: ensure the `conf/` files exist. If any file under `conf/` is missing, Docker creates a directory placeholder, causing a mount conflict. Run `git status` and `git checkout conf/` to restore them.

Dashboard: `http://localhost:8183` (admin / admin)

**With test simulator** (validate end-to-end routing):

```bash
docker compose --profile test up -d
```

Adds `vllm-sim` (mock LLM backend, port 8000). Configure a forwarding rule in Dashboard to verify routing.

> `vllm-sim` is for functional testing only. The compose MySQL has no persistent storage — uncomment `volumes` in `docker-compose.yml` for data persistence, or use an external MySQL in production.

```bash
# Operations
docker compose stop                     # Stop all services
docker compose start                    # Restart all services
docker compose down                     # Stop and remove containers
docker compose --profile test up -d     # Add simulator after initial deploy
docker compose restart ai-gateway       # Restart after config changes
```

### Observability Stack (Optional)

Enable full observability with Kafka + Doris + Grafana:

```bash
docker compose --profile observability up -d
```

| Container | DNS name | Port | Purpose |
|---|---|---|---|
| Kafka 3.7.1 | `kafka.ai-gateway-system` | 9092 | Message queue (KRaft single-node) |
| Doris FE 4.1.3 | `doris-fe.ai-gateway-system` | 8030, 9030 | Doris Frontend (SQL + Web) |
| Doris BE 4.1.3 | `doris-be.ai-gateway-system` | 8040 | Doris Backend (storage) |
| Grafana 11.5.1 | `grafana.ai-gateway-system` | 3000 | Dashboards (pre-provisioned) |


- `doris-init` container automatically creates database, tables, Routine Load, and INSERT JOB on first start
- Grafana dashboard "BFE AI Gateway 可观测仪表盘" is pre-provisioned
- All observability services use ephemeral storage — data lost on restart

Grafana: `http://localhost:3000` (admin / admin)
Doris FE Web: `http://localhost:8030`

> The Log Reader is built into the AI Gateway image and runs as the 3rd process alongside BFE and Conf Agent. It reads `pb_access3.log` and sends to Kafka. Its config is at `conf/log-reader/` and mounted into the container. If Kafka is unavailable, Log Reader retries silently without affecting traffic routing.

### Manual Deployment (External MySQL / Redis)

If you have your own MySQL and Redis, configure and start the container manually:

1. **Configure** — edit `conf/` files with your addresses:

| File | Key settings |
|---|---|
| `conf/ai_gateway_api.toml` | `Addr`, `User`, `Passwd` under `[Databases.bfe_db]` |
| `conf/name_conf.data` | `Host`, `Port` for Redis instance |
| `conf/bfe.conf` | BFE ports and modules (usually no changes needed) |
| `conf/log-reader/` | Kafka broker address, topic names |

Example `conf/ai_gateway_api.toml`:

```toml
[Databases.bfe_db]
Addr   = "192.168.1.3:3306"
User   = "root"
Passwd = "your_password"

[RedisConf]
Bns = "BFE.poc-redis-wx"
```

Example `conf/name_conf.data`:

```json
{
    "Version": "init version",
    "Config": {
        "BFE.poc-redis-wx": [{
            "Host": "192.168.1.4",
            "Port": 6379,
            "Weight": 10
        }]
    }
}
```

2. **Start**:

```bash
docker run -d --name ai-gateway \
  -p 8080:8080 -p 8183:8183 -p 8992:8992 \
  -v $(pwd)/conf/ai_gateway_api.toml:/home/work/api-server/conf/ai_gateway_api.toml \
  -v $(pwd)/conf/name_conf.data:/home/work/api-server/conf/name_conf.data \
  -v $(pwd)/conf/name_conf.data:/home/work/bfe/conf/name_conf.data \
  -v $(pwd)/conf/bfe.conf:/home/work/bfe/conf/bfe.conf \
  -v $(pwd)/conf/log-reader/:/home/work/log-reader/conf/ \
  ghcr.io/yf-networks/ai-gateway:latest
```

Dashboard: `http://localhost:8183` (admin / admin)

### Kubernetes

```bash
kubectl apply -k kubernetes/
kubectl get pods -n ai-gateway-system
```

Dashboard: `http://{NodeIP}:30183` (admin / admin). See [K8s docs](./kubernetes/README.md) for details.

## Build from Source

```bash
make docker-standalone            # Build container image
make docker-standalone VARIANT=debug  # With debug tools
make docker-standalone-push REGISTRY=ghcr.io/your-org  # Multi-arch push
```

Build parameters are read from `VERSIONS.yaml` — no manual version configuration needed.

## Mirror Registry

If `ghcr.io` is not directly accessible, replace image sources with a mirror (`ghcr.nju.edu.cn`):

| Deployment | Config file | How to |
|---|---|---|
| Docker Compose | `docker-compose.yml` | Replace `image:` lines with your mirror registry |
| Kubernetes | `kubernetes/kustomization.yaml` | Replace `newName:` in `images:` section |

See comments in each file for examples.

## Version Management

This repository is the **product-level version entry point**. `VERSIONS.yaml` defines the verified component versions:

```yaml
version: v0.1.0
components:
  bfe:
    version: v1.8.2
    image: ghcr.io/bfenetworks/bfe:v1.8.2
    provides:
      - bfe
      - conf-agent
      - log-reader
  ai-gateway-api:
    version: v0.0.2
    image: ghcr.io/yf-networks/ai-gateway-api:v0.0.2
```

Update `VERSIONS.yaml` → rebuild → tag a new product release.

## Exposed Ports

| Port | Component | Purpose |
|---|---|---|
| 8080 | BFE | HTTP entry |
| 8443 | BFE | HTTPS entry |
| 8421 | BFE | Monitor |
| 8183 | API Server | API + Dashboard |
| 8284 | API Server | Monitor |
| 8992 | Log Reader | Monitor (Kafka counters) |

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development workflow and guidelines.

## License

AI Gateway is released under the [Apache License 2.0](LICENSE).

## References

- [BFE](https://github.com/bfenetworks/bfe) — Data plane engine
- [AI Gateway API](https://github.com/yf-networks/ai-gateway-api) — Control plane
- [AI Gateway Web](https://github.com/yf-networks/ai-gateway-web) — Dashboard frontend
- [Conf Agent](https://github.com/bfenetworks/conf-agent) — Configuration agent
- [Log Reader](https://github.com/bfenetworks/log-reader) — Access log collector
- [Service Controller](https://github.com/bfenetworks/service-controller) — K8s service discovery
