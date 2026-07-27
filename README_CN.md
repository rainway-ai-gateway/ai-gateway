[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg)](https://go.dev/)

[English](README.md) | 简体中文

# YF AI Gateway

AI Gateway 是基于 [BFE](https://github.com/bfenetworks/bfe) 构建的开源 AI 流量网关，为多个 AI 模型提供商提供统一的 API 管理、认证、限流和智能路由能力，让开发者通过单一入口访问所有 AI 服务。

## 架构概述

![架构](./.images/deploy_architecture_ai.png)

AI Gateway 包含如下核心组件：

| 组件 | 角色 | 说明 | 仓库 |
|---|---|---|---|
| **AI Gateway API** | 控制面 | 对外提供 Open API，完成策略/配置的变更、存储和下发 | [yf-networks/ai-gateway-api](https://github.com/yf-networks/ai-gateway-api) |
| **Dashboard** | 管理控制台 | Web 可视化管理界面（内置在 API 镜像中） | [yf-networks/ai-gateway-web](https://github.com/yf-networks/ai-gateway-web) |
| **BFE** | 数据面 | 负责流量转发与接入控制 | [bfenetworks/bfe](https://github.com/bfenetworks/bfe) |
| **Conf Agent** | 配置代理 | 获取最新配置并触发 BFE 热加载 | [bfenetworks/conf-agent](https://github.com/bfenetworks/conf-agent) |
| **Log Reader** | 日志采集 | 读取 BFE 访问日志并发送至 Kafka | [bfenetworks/log-reader](https://github.com/bfenetworks/log-reader) |
| **Service Controller** | 服务发现 | 发现并同步 K8s 后端服务（仅 K8s 部署） | [bfenetworks/service-controller](https://github.com/bfenetworks/service-controller) |

## 主要功能

- **AI 路由管理**：支持多 AI 模型提供商（OpenAI、DeepSeek、千问等）的路由配置
- **API Key 管理**：AI 服务的 API Key 创建、删除与校验
- **域名管理**：域名绑定与路由规则配置
- **集群/子集群管理**：后端服务集群的配置管理
- **流量管理**：流量分配与调度
- **Dashboard**：Web 可视化管理界面（内置在 API 镜像中）
- **配置导出**：为 BFE 数据面和 Conf Agent 提供配置导出接口

## 部署方式

| 方式 | 命令 | 适用场景 |
|---|---|---|
| **容器部署** | `docker compose up -d` | 开发、演示、小规模部署 |
| **Kubernetes** | `kubectl apply -k kubernetes/` | 生产环境、集群部署 |

## 快速开始

### Docker Compose（推荐，免配置）

`docker-compose.yml` 集成 MySQL 8 + Redis 6.2 + AI Gateway（含 BFE + Conf Agent + Log Reader），配置已预置 Docker 网络 DNS，开箱即用。

| 容器 | DNS 名称 (预置) | 端口 |
|---|---|---|
| MySQL 8 | `mysql.ai-gateway-system` | 3306 |
| Redis 6.2 | `redis.ai-gateway-system` | 6379 |
| AI Gateway | — | 8080, 8183, 8992 |

> **前置要求**：需要安装 Docker Compose 插件。如果 `docker compose` 不可用：
> 1. 从 https://github.com/docker/compose/releases 下载对应版本
> 2. 放入 `$HOME/.docker/cli-plugins/docker-compose`
> 3. `chmod +x $HOME/.docker/cli-plugins/docker-compose`
>
> 或使用独立二进制：`docker-compose up -d`

```bash
git clone https://github.com/yf-networks/ai-gateway.git
cd ai-gateway
docker compose up -d
```

> **如遇到 "not a directory" 挂载错误**：请确认 `conf/` 目录下的文件存在。如果缺少任何文件，Docker 会创建一个目录占位，导致挂载冲突。执行 `git status` 并用 `git checkout conf/` 恢复文件。

访问 Dashboard：`http://localhost:8183`（admin / admin）

**附带测试模拟器**（端到端路由验证）：

```bash
docker compose --profile test up -d
```

额外启动 `vllm-sim`（模拟 LLM 后端，端口 8000），在 Dashboard 中配置转发规则即可验证路由。

> `vllm-sim` 仅用于功能测试。compose 中的 MySQL 无持久化存储，生产环境请取消 `docker-compose.yml` 中 `volumes` 的注释以挂载数据目录，或使用外部 MySQL。

```bash
# 常用操作
docker compose stop                     # 停止所有服务
docker compose start                    # 重启所有服务
docker compose down                     # 停止并删除容器
docker compose --profile test up -d     # 初始部署后追加模拟器
docker compose restart ai-gateway       # 修改配置后重启
```

### 可观测性栈（可选）

一键启用 Kafka + Doris + Grafana 全链路可观测：

```bash
docker compose --profile observability up -d
```

| 容器 | DNS 名称 | 端口 | 用途 |
|---|---|---|---|
| Kafka 3.7.1 | `kafka.ai-gateway-system` | 9092 | 消息队列（KRaft 单节点） |
| Doris FE 4.1.3 | `doris-fe.ai-gateway-system` | 8030, 9030 | Doris 前端（SQL + Web） |
| Doris BE 4.1.3 | `doris-be.ai-gateway-system` | 8040 | Doris 后端（存储） |
| Grafana 11.5.1 | `grafana.ai-gateway-system` | 3000 | 看板（预配仪表盘） |


- `doris-init` 容器在首次启动时自动创建数据库、表、Routine Load 和 INSERT JOB
- Grafana 预配"BFE AI Gateway 可观测仪表盘"看板
- 所有可观测服务使用临时存储，重启后数据丢失

Grafana：`http://localhost:3000`（admin / admin）
Doris FE Web：`http://localhost:8030`

> Log Reader 内置于 AI Gateway 镜像中，作为第 3 个进程与 BFE、Conf Agent 并行运行。它读取 `pb_access3.log` 并发送至 Kafka，配置位于 `conf/log-reader/`。若 Kafka 不可用，Log Reader 静默重试，不影响流量路由。

### 手动部署（自行准备 MySQL / Redis）

1. **修改配置** — 编辑 `conf/` 文件，填入实际地址：

| 文件 | 配置项 |
|---|---|
| `conf/ai_gateway_api.toml` | `[Databases.bfe_db]` 下的 `Addr`、`User`、`Passwd` |
| `conf/name_conf.data` | Redis 实例的 `Host`、`Port` |
| `conf/bfe.conf` | BFE 端口和模块（通常无需修改） |
| `conf/log-reader/` | Kafka broker 地址、topic 名称 |

`conf/ai_gateway_api.toml` 示例：

```toml
[Databases.bfe_db]
Addr   = "192.168.1.3:3306"
User   = "root"
Passwd = "your_password"

[RedisConf]
Bns = "BFE.poc-redis-wx"
```

`conf/name_conf.data` 示例：

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

2. **启动**：

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

Dashboard：`http://localhost:8183`（admin / admin）

### Kubernetes

```bash
kubectl apply -k kubernetes/
kubectl get pods -n ai-gateway-system
```

Dashboard：`http://{NodeIP}:30183`（admin / admin）。详见 [K8s 部署文档](./kubernetes/README.md)。

## 从源码构建

```bash
make docker-standalone               # 构建容器镜像
make docker-standalone VARIANT=debug # 含调试工具
make docker-standalone-push REGISTRY=ghcr.io/your-org  # 多架构推送
```

构建参数从 `VERSIONS.yaml` 自动读取，无需手动配置版本号。

## 镜像加速

如果无法直接访问 `ghcr.io`，可将镜像源替换为国内镜像 `ghcr.nju.edu.cn`：

| 部署方式 | 配置文件 | 操作 |
|---|---|---|
| Docker Compose | `docker-compose.yml` | 替换 `image:` 行中的 registry（如 `ghcr.nju.edu.cn/...`） |
| Kubernetes | `kubernetes/kustomization.yaml` | 替换 `images:` 中的 `newName` |

详见各文件中的注释示例。

## 版本管理

本仓库是 AI Gateway 的**产品级版本入口**。`VERSIONS.yaml` 定义了经过验证的组件版本组合：

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

更新 `VERSIONS.yaml` → 重新构建 → 打产品 tag 发布。

## 暴露端口

| 端口 | 组件 | 用途 |
|---|---|---|
| 8080 | BFE | HTTP 流量入口 |
| 8443 | BFE | HTTPS 流量入口 |
| 8421 | BFE | 监控端口 |
| 8183 | API Server | API 服务 + Dashboard |
| 8284 | API Server | 监控端口 |
| 8992 | Log Reader | 监控端口（Kafka 计数器） |

## 贡献

请参阅 [CONTRIBUTING.md](./CONTRIBUTING.md) 了解开发流程和规范。

## 许可证

AI Gateway 基于 [Apache License 2.0](LICENSE) 发布。

## 参考资料

- [BFE](https://github.com/bfenetworks/bfe) — 数据面引擎
- [AI Gateway API](https://github.com/yf-networks/ai-gateway-api) — 控制面
- [AI Gateway Web](https://github.com/yf-networks/ai-gateway-web) — Dashboard 前端
- [Conf Agent](https://github.com/bfenetworks/conf-agent) — 配置代理
- [Log Reader](https://github.com/bfenetworks/log-reader) — 访问日志采集
- [Service Controller](https://github.com/bfenetworks/service-controller) — K8s 服务发现
