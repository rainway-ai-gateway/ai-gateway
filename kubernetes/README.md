[English](README.md) | [简体中文](README_CN.md)

# AI Gateway Kubernetes Deployment

## Architecture

![Kubernetes](../.images/ai-gateway-k8s.png)

This deployment demonstrates the interaction of several key components in the `ai-gateway-system` namespace:

- **Data plane** (bfe with conf-agent + log-reader): traffic forwarding, access control, and access log collection
- **Control plane** (ai-gateway-api): configuration/policy delivery API
- **Base dependencies** (MySQL, Redis, Kafka): storage and messaging services
- **Service discovery** (service-controller): discovers and syncs backend services
- **Demo backend** (llm-d inference simulator): validates routing

Optional observability stack (applied separately to `default` namespace):
- **Doris** (FE + BE): detail table storage + minute-level pre-aggregation
- **Grafana**: pre-provisioned dashboard for QPS, latency, tokens, rate limiting, etc.

### Component communication via K8s Service/DNS

| Consumer | Target | DNS |
|---|---|---|
| conf-agent | ai-gateway-api | `ai-gateway-api.ai-gateway-system.svc.cluster.local:8183` |
| ai-gateway-api | MySQL | `mysql.ai-gateway-system.svc.cluster.local:3306` |
| bfe (SessionCache) | Redis | `redis.ai-gateway-system.svc.cluster.local:6379` |
| log-reader | Kafka | `kafka.ai-gateway-system.svc.cluster.local:9092` |
| Doris Routine Load | Kafka | `kafka.ai-gateway-system.svc.cluster.local:9092` |
| Grafana | Doris FE | `doris-fe.default.svc.cluster.local:9030` |

> Note: MySQL / Redis / Kafka / Doris use `emptyDir` for storage in this example. **Data will be lost on Pod restart.** This is for demo/connectivity validation only. See production recommendations below.

## Manifest Overview

| File | Description |
|---|---|
| `namespace.yaml` | Namespace definition (ai-gateway-system) |
| `kustomization.yaml` | Kustomize resource aggregation and image overrides |
| `bfe-configmap.yaml` | BFE config (bfe.conf, conf-agent.toml, log-reader config) |
| `bfe-deploy.yaml` | BFE data plane Deployment (bfe + conf-agent + log-reader in single container) |
| `ai-gateway-configmap.yaml` | AI Gateway API configuration (DB/Redis, auth) |
| `ai-gateway-deploy.yaml` | AI Gateway API Deployment and Service |
| `mysql-deploy.yaml` | MySQL (Deployment, Service, init ConfigMap, init Job) |
| `redis-deploy.yaml` | Redis Deployment and Service |
| `kafka-deploy.yaml` | Kafka (StatefulSet, KRaft single-node, Service) |
| `service-controller-deploy.yaml` | Service discovery controller |
| `llm-d-inference-sim-deploy.yaml` | Demo backend inference simulator (apply separately) |
| `doris.yaml` | Doris FE + BE + init Job (apply separately, optional) |
| `grafana.yaml` | Grafana + pre-provisioned dashboard (apply separately, optional) |

## Quick Start

### Prerequisites

- kubectl >= 1.20 with `-k` support
- Cluster admin permissions (Namespace, Deployment, Service, ConfigMap, Secret)
- Cluster nodes can pull images

### 1. Configure Images (Optional)

To use custom image addresses or versions, modify `images:` in `kustomization.yaml`:

```yaml
images:
  - name: ghcr.io/bfenetworks/bfe
    newName: ghcr.io/your-org/bfe
    newTag: v1.8.2
  - name: ghcr.io/yf-networks/ai-gateway-api
    newName: ghcr.io/your-org/ai-gateway-api
    newTag: v0.0.2
  - name: ghcr.io/bfenetworks/service-controller
    newName: ghcr.io/your-org/service-controller
    newTag: v0.0.1
```

### 2. Deploy

```bash
kubectl apply -k .
```

Deploys: bfe (with conf-agent + log-reader), ai-gateway-api (with Dashboard), mysql, redis, kafka, service-controller.

### 3. Deploy Test Service (Optional)

```bash
kubectl apply -f deploy/llm-d-inference-sim-deploy.yaml
```

> Deployed to the `default` namespace. Edit the file to change image or model args.

### 4. Deploy Observability Stack (Optional)

```bash
kubectl apply -f deploy/doris.yaml
kubectl apply -f deploy/grafana.yaml
```

Deploys to `default` namespace: Doris FE + BE + automatic SQL initialization, Grafana with pre-provisioned "BFE AI Gateway 可观测仪表盘" dashboard.

> The `observability-init` Job automatically creates the database, detail table, aggregate table, Routine Load (consumes from Kafka `bfe_ai_log` topic), and INSERT JOB (minute-level aggregation). Wait ~2 minutes for initialization to complete.

### 5. Verify

```bash
kubectl get pods -n ai-gateway-system
kubectl get svc -n ai-gateway-system
kubectl get pods -n default  # Doris + Grafana
```

Access Dashboard: `http://{NodeIP}:30183` (admin / admin)

Access Grafana: `http://{NodeIP}:30300` (admin / admin)

## Exposed NodePorts

| Port | Component | Namespace | Purpose |
|---|---|---|---|
| 30080 | bfe | ai-gateway-system | HTTP traffic entry |
| 30443 | bfe | ai-gateway-system | HTTPS traffic entry |
| 30421 | bfe | ai-gateway-system | BFE monitor |
| 30183 | ai-gateway-api | ai-gateway-system | API + Dashboard |
| 30092 | kafka | ai-gateway-system | Kafka client (debug) |
| 30300 | grafana | default | Grafana dashboard |
| 30803 | doris-fe | default | Doris FE web UI |

## Using External Database

The demo MySQL uses `emptyDir` storage (data lost on Pod restart). Production options:

**Option A — PersistentVolumeClaim** (keep in-cluster MySQL):

```bash
kubectl apply -f deploy/mysql-pvc.yaml     # create PVC (once)
```

Then in `deploy/mysql-deploy.yaml`, replace `emptyDir: {}` with the commented `persistentVolumeClaim` block.

The PVC is NOT included in `kustomization.yaml`, so `kubectl delete -k .` will not delete it — your data survives uninstall / re-apply cycles.

**Option B — External MySQL**:

1. Run `db_ddl.sql` on your external MySQL instance
2. Update database connection in `deploy/ai-gateway-configmap.yaml`
3. Comment out `mysql-deploy.yaml` in `kustomization.yaml`

## Production Kafka Recommendations

The demo Kafka is a single-node KRaft deployment with `emptyDir` storage. For production:

| Option | Description | Suitability |
|---|---|---|
| **External managed Kafka** | MSK, Confluent Cloud, self-managed cluster | Production environments |
| **In-cluster Kafka + PVC** | Replace `emptyDir` with PVC in `kafka-deploy.yaml`, increase replicas | Small-scale production |
| **In-cluster Kafka cluster** | 3-node StatefulSet + proper replication | Medium+ scale |

**External Kafka setup**:

1. Comment out `kafka-deploy.yaml` in `kustomization.yaml`
2. Update `Brokers` in `bfe-configmap.yaml` (log-reader-config section) to your external Kafka address
3. Update `kafka_broker_list` in `doris.yaml` (routine load SQL)
4. Ensure topics `bfe_ai_log` and `bfe_ai_log_dlq` are pre-created

**Topic planning** (reference from log-reader howto guide):

| Scale | Daily Requests | bfe_ai_log Partitions | Replicas | Retention |
|---|---|---|---|---|
| Demo | < 10K | 1 | 1 | 7 days |
| Small | 1M | 2 | 2 | 7 days |
| Medium | 10M | 4 | 3 | 7 days |
| Large | 50M | 8 | 3 | 3 days |

## Production Doris Recommendations

The demo Doris is a single-node FE + BE deployment with `emptyDir` storage. **Data will be lost on Pod restart.** For production:

| Option | Description |
|---|---|
| **External Doris cluster** | Self-managed Doris cluster or SelectDB Cloud. Recommended for production. |
| **In-cluster Doris + PVC** | Replace `emptyDir` with PVC in `doris.yaml`. Use 3 FE + 3+ BE for high availability. |
| **Skip Doris, use external consumer** | If you already have a Kafka consumer pipeline (e.g., ELK, ClickHouse), skip Doris and consume `bfe_ai_log` topic directly. |

**External Doris setup**:

1. Do not apply `doris.yaml`
2. Create the detail table and routine load manually on your external Doris cluster (SQL templates in `doris.yaml` ConfigMap `doris-init-sql`)
3. Update Grafana datasource (`grafana.yaml` ConfigMap `grafana-config`) to point to your external Doris FE

**Aggregate table design note**: The demo aggregate table `bfe_ai_metrics_1m` is an example with 8 dimension columns. For production, split by query scenario (see `log-reader/doc/howto/01AI Gateway 可观测性链路打通指南.md` §7 for detailed recommendations).

## Backend Service Requirements

Service Controller discovers backend services by watching Kubernetes Service labels:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  labels:
    bfe-product: AI_product  # required: fixed value
spec:
  ports:
    - name: http             # required: port must be named
      port: 8080
      targetPort: 80
```

- `bfe-product`: Must be exactly `AI_product`
- `spec.ports[].name`: Required, any meaningful name (http, https, grpc, etc.)

## Cleanup

```bash
kubectl delete -f deploy/llm-d-inference-sim-deploy.yaml
kubectl delete -f deploy/grafana.yaml
kubectl delete -f deploy/doris.yaml
kubectl delete -k .
```

> Delete the demo backend and observability components first to avoid finalizers hanging.

## Troubleshooting

### Image pull failures

```bash
kubectl describe pod -n ai-gateway-system <pod-name>
```

Common causes: incorrect image overrides in `kustomization.yaml`, missing `imagePullSecrets`.

### Control plane CrashLoopBackOff

```bash
kubectl logs -n ai-gateway-system -l app=ai-gateway-api --tail=200
```

Common causes: MySQL/Redis not ready, incorrect connection settings, DB init script not applied.

### BFE returns 500

Expected when no forwarding rule is configured. Configure rules in Dashboard, then verify with:

```bash
curl -v http://{NodeIP}:30080/
```

### log-reader shows "file not exit" errors

Normal during initial startup — the `pb_access3.log` file is created when BFE processes its first request. log-reader tails the file automatically once it appears. Check log-reader Kafka counters:

```bash
kubectl exec -n ai-gateway-system deploy/bfe -- wget -qO- http://127.0.0.1:8992/monitor/mod_kafka
```

Look for `SENT_TO_KAFKA > 0` and `SEND_KAFKA_FAILED = 0`.

### Kafka topic not created

The demo Kafka has `AUTO_CREATE_TOPICS_ENABLE=true`. Topics `bfe_ai_log` and `bfe_ai_log_dlq` are auto-created when log-reader sends its first message. Verify:

```bash
kubectl exec -n ai-gateway-system kafka-0 -- /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

### Doris Routine Load not consuming

```bash
kubectl exec -n default doris-fe-0 -- mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "USE bfe_observability; SHOW ROUTINE LOAD FOR bfe_ai_log_load\G" | grep -E "State|Error|loadedRows"
```

Common causes: Kafka broker unreachable, dynamic partition not covering data timestamps, JSON format mismatch.
