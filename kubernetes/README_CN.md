[English](README.md) | 简体中文

# AI Gateway Kubernetes 部署

## 架构图

![Kubernetes](../.images/ai-gateway-k8s.png)

本部署在 `ai-gateway-system` 命名空间中演示了各关键组件的交互：

- **数据面**（bfe + conf-agent + log-reader）：流量转发、接入控制与访问日志采集
- **控制面**（ai-gateway-api）：策略/配置下发接口
- **基础依赖**（MySQL、Redis、Kafka）：为控制面提供存储与消息服务
- **服务发现**（service-controller）：发现并同步后端服务
- **示例后端**（llm-d inference simulator）：验证路由

可选可观测栈（单独部署在 `default` 命名空间）：
- **Doris**（FE + BE）：明细表存储 + 分钟级预聚合
- **Grafana**：预配看板（QPS、延迟、Token 用量、限流、认证拒绝等）

### 组件间 Service/DNS 通信

| 消费者 | 目标服务 | DNS |
|---|---|---|
| conf-agent | ai-gateway-api | `ai-gateway-api.ai-gateway-system.svc.cluster.local:8183` |
| ai-gateway-api | MySQL | `mysql.ai-gateway-system.svc.cluster.local:3306` |
| bfe（SessionCache） | Redis | `redis.ai-gateway-system.svc.cluster.local:6379` |
| log-reader | Kafka | `kafka.ai-gateway-system.svc.cluster.local:9092` |
| Doris Routine Load | Kafka | `kafka.ai-gateway-system.svc.cluster.local:9092` |
| Grafana | Doris FE | `doris-fe.default.svc.cluster.local:9030` |

> 注意：MySQL / Redis / Kafka / Doris 演示环境均使用 `emptyDir` 存储，**Pod 重启后数据全部丢失**。仅用于演示和联通性验证。生产环境建议见下文。

## 清单概览

| 文件 | 说明 |
|---|---|
| `namespace.yaml` | 命名空间定义（ai-gateway-system） |
| `kustomization.yaml` | Kustomize 资源汇总与镜像覆盖 |
| `bfe-configmap.yaml` | BFE 配置（bfe.conf、conf-agent.toml、log-reader 配置） |
| `bfe-deploy.yaml` | BFE 数据面 Deployment（单容器内含 bfe + conf-agent + log-reader） |
| `ai-gateway-configmap.yaml` | AI Gateway API 配置（DB/Redis、鉴权） |
| `ai-gateway-deploy.yaml` | AI Gateway API Deployment 与 Service |
| `mysql-deploy.yaml` | MySQL（Deployment、Service、初始化 ConfigMap、初始化 Job） |
| `redis-deploy.yaml` | Redis Deployment 与 Service |
| `kafka-deploy.yaml` | Kafka（StatefulSet、KRaft 单节点、Service） |
| `service-controller-deploy.yaml` | 服务发现控制器 |
| `llm-d-inference-sim-deploy.yaml` | 示例后端推理模拟服务（单独 apply） |
| `doris.yaml` | Doris FE + BE + 初始化 Job（单独 apply，可选） |
| `grafana.yaml` | Grafana + 预配看板（单独 apply，可选） |

## 快速开始

### 前置条件

- kubectl >= 1.20，支持 `-k`
- 集群管理权限（Namespace、Deployment、Service、ConfigMap、Secret）
- 集群节点可拉取镜像

### 1. 配置镜像（可选）

如需使用自定义镜像地址或版本，修改 `kustomization.yaml` 中的 `images:` 配置：

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

### 2. 一键部署

```bash
kubectl apply -k .
```

部署：bfe（含 conf-agent + log-reader）、ai-gateway-api（含 Dashboard）、mysql、redis、kafka、service-controller。

### 3. 部署测试服务（可选）

```bash
kubectl apply -f deploy/llm-d-inference-sim-deploy.yaml
```

> 部署在 `default` 命名空间。如需替换镜像/模型参数，直接编辑该文件。

### 4. 部署可观测栈（可选）

```bash
kubectl apply -f deploy/doris.yaml
kubectl apply -f deploy/grafana.yaml
```

部署到 `default` 命名空间：Doris FE + BE + 自动 SQL 初始化、Grafana 预配"BFE AI Gateway 可观测仪表盘"看板。

> `observability-init` Job 自动创建数据库、明细表、聚合表、Routine Load（消费 Kafka `bfe_ai_log` topic）、INSERT JOB（分钟级聚合）。初始化约需 2 分钟。

### 5. 验证

```bash
kubectl get pods -n ai-gateway-system
kubectl get svc -n ai-gateway-system
kubectl get pods -n default  # Doris + Grafana
```

访问 Dashboard：`http://{NodeIP}:30183`（admin / admin）

访问 Grafana：`http://{NodeIP}:30300`（admin / admin）

## 暴露的 NodePort

| 端口 | 组件 | 命名空间 | 用途 |
|---|---|---|---|
| 30080 | bfe | ai-gateway-system | HTTP 流量入口 |
| 30443 | bfe | ai-gateway-system | HTTPS 流量入口 |
| 30421 | bfe | ai-gateway-system | BFE 监控 |
| 30183 | ai-gateway-api | ai-gateway-system | API + Dashboard |
| 30092 | kafka | ai-gateway-system | Kafka 客户端（调试） |
| 30300 | grafana | default | Grafana 看板 |
| 30803 | doris-fe | default | Doris FE Web 管理界面 |

## 使用外部数据库

演示用的 MySQL 使用 `emptyDir` 存储（Pod 重启后数据丢失）。生产环境可选：

**方案 A — 持久卷（PVC）**（保留集群内 MySQL）：

```bash
kubectl apply -f deploy/mysql-pvc.yaml     # 创建 PVC（只需一次）
```

然后在 `deploy/mysql-deploy.yaml` 中将 `emptyDir: {}` 替换为其下方注释中的 `persistentVolumeClaim` 块。

PVC 未加入 `kustomization.yaml`，因此 `kubectl delete -k .` 不会删除它——反复卸载重装数据不丢失。

**方案 B — 外部 MySQL**：

1. 在外部 MySQL 实例上执行 `db_ddl.sql`
2. 修改 `deploy/ai-gateway-configmap.yaml` 中的数据库连接信息
3. 在 `kustomization.yaml` 中注释掉 `mysql-deploy.yaml`

## Kafka 生产环境建议

演示 Kafka 为 KRaft 单节点 + `emptyDir` 存储。生产环境：

| 方案 | 说明 | 适用场景 |
|---|---|---|
| **外部托管 Kafka** | MSK / Confluent Cloud / 自建集群 | 生产环境 |
| **集群内 Kafka + PVC** | `kafka-deploy.yaml` 中将 `emptyDir` 替换为 PVC，增加副本数 | 小规模生产 |
| **集群内 Kafka 集群** | 3 节点 StatefulSet + 多副本 | 中大规模 |

**外部 Kafka 接入步骤**：

1. 在 `kustomization.yaml` 中注释掉 `kafka-deploy.yaml`
2. 修改 `bfe-configmap.yaml`（log-reader-config 部分）中的 `Brokers` 为外部 Kafka 地址
3. 修改 `doris.yaml`（Routine Load SQL）中的 `kafka_broker_list`
4. 确保 `bfe_ai_log` 和 `bfe_ai_log_dlq` topic 已创建

**Topic 规划建议**（参考 log-reader howto 文档）：

| 规模 | 日均请求量 | bfe_ai_log 分区数 | 副本数 | 保留时间 |
|---|---|---|---|---|
| 演示 | < 1 万 | 1 | 1 | 7 天 |
| 小规模 | 100 万 | 2 | 2 | 7 天 |
| 中规模 | 1000 万 | 4 | 3 | 7 天 |
| 大规模 | 5000 万 | 8 | 3 | 3 天 |

## Doris 生产环境建议

演示 Doris 为单节点 FE + BE + `emptyDir` 存储。**Pod 重启后数据全部丢失。** 生产环境：

| 方案 | 说明 |
|---|---|
| **外部 Doris 集群** | 自建 Doris 集群或 SelectDB Cloud。生产环境首选。 |
| **集群内 Doris + PVC** | `doris.yaml` 中将 `emptyDir` 替换为 PVC。高可用需 3 FE + 3+ BE。 |
| **跳过 Doris** | 如已有 Kafka 消费链路（ELK、ClickHouse 等），跳过 Doris，直接消费 `bfe_ai_log` topic。 |

**外部 Doris 接入步骤**：

1. 不 apply `doris.yaml`
2. 在外部 Doris 集群上手动创建明细表和 Routine Load（SQL 模板见 `doris.yaml` 中 `doris-init-sql` ConfigMap）
3. 修改 `grafana.yaml` 中 `grafana-config` ConfigMap 的数据源地址，指向外部 Doris FE

## 后端服务要求

Service Controller 通过监听 Kubernetes Service 的标签来发现后端服务：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  labels:
    bfe-product: AI_product  # 必须：固定值
spec:
  ports:
    - name: http             # 必须：端口必须命名
      port: 8080
      targetPort: 80
```

- `bfe-product`：必须为 `AI_product`
- `spec.ports[].name`：必填，可为任意有意义的名称（http、https、grpc 等）

## 清理

```bash
kubectl delete -f deploy/llm-d-inference-sim-deploy.yaml
kubectl delete -f deploy/grafana.yaml
kubectl delete -f deploy/doris.yaml
kubectl delete -k .
```

> 建议先删除示例后端和可观测组件再删 `ai-gateway-system`，避免 finalizers 导致卡住。

## 故障排查

### 镜像拉取失败

```bash
kubectl describe pod -n ai-gateway-system <pod-name>
```

常见原因：`kustomization.yaml` 中镜像配置错误，缺少 `imagePullSecrets`。

### 控制面 CrashLoopBackOff

```bash
kubectl logs -n ai-gateway-system -l app=ai-gateway-api --tail=200
```

常见原因：MySQL/Redis 未就绪，连接配置错误，未执行数据库初始化脚本。

### BFE 返回 500

未配置转发规则时该返回值符合预期。在 Dashboard 中配置规则后验证：

```bash
curl -v http://{NodeIP}:30080/
```

### log-reader 反复打印 "file not exit" 错误

正常现象——`pb_access3.log` 文件在 BFE 收到第一个请求后才创建，log-reader 会自动 tail。检查 log-reader 的 Kafka 投递计数器：

```bash
kubectl exec -n ai-gateway-system deploy/bfe -- wget -qO- http://127.0.0.1:8992/monitor/mod_kafka
```

确认 `SENT_TO_KAFKA > 0` 且 `SEND_KAFKA_FAILED = 0`。

### Kafka topic 未创建

演示 Kafka 已开启 `AUTO_CREATE_TOPICS_ENABLE=true`，启动后无需手动创建。确认 topic 已存在：

```bash
kubectl exec -n ai-gateway-system kafka-0 -- /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

### Doris Routine Load 未消费数据

```bash
kubectl exec -n default doris-fe-0 -- mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "USE bfe_observability; SHOW ROUTINE LOAD FOR bfe_ai_log_load\G" | grep -E "State|Error|loadedRows"
```

常见原因：Kafka broker 不可达、动态分区未覆盖数据时间戳、JSON 格式不匹配。
