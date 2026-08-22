[English](./BUILD_GUIDE.md) | [简体中文](./BUILD_GUIDE_CN.md)

# 从源码编译到 Kubernetes 部署完整指南

## 概述

- 本指南面向需要从源码编译 AI Gateway 核心组件的技术人员;
- 涵盖从源码获取、构建容器镜像，到推送镜像仓库并集成到 Kubernetes 部署的完整工作流程。

### 涵盖的组件

本指南详细说明以下三个核心组件的编译部署流程：

1. **BFE (数据面)** - 负责流量转发与接入控制
   - GitHub: https://github.com/bfenetworks/bfe
   
2. **AI Gateway API (控制面 API)** - 负责策略/配置下发接口
   - GitHub: https://github.com/rainway-ai-gateway/ai-gateway-api

3. **AI Gateway Web (控制面 Dashboard)** - 为控制面提供图形化操作界面 
   - GitHub: https://github.com/rainway-ai-gateway/ai-gateway-web
   
4. **Service Controller** - 负责发现并同步后端服务
   - GitHub: https://github.com/bfenetworks/service-controller

---

## 目录

- [前置条件](#前置条件)
- [BFE 编译](#bfe-编译)
- [AI Gateway API 编译](#ai-gateway-api-编译)
- [AI Gateway Web 编译](#ai-gateway-web-编译)
- [Service Controller 编译](#service-controller-编译)
- [Kubernetes 部署集成](#kubernetes-部署集成)
- [故障排查](#故障排查)
- [日志收集](#日志收集)
- [参考资料](#参考资料)

---

## 前置条件

### 开发环境要求

在开始编译之前，请确保您的系统满足以下要求：

#### Go 环境

- **版本要求**: Go 1.22 或更高版本
- **安装验证**:
  ```bash
  go version
  # 应输出: go version go1.22.x ...
  ```
- **安装指南**: 访问 [Go 官方网站](https://go.dev/dl/) 下载安装

#### Docker 环境

- **版本要求**: 支持 Docker Buildx 的版本（Docker Desktop 20.10+ 或 Docker Engine 19.03+）
- **验证 Docker**:
  ```bash
  docker --version
  # 应输出: Docker version 20.10.x ...
  ```
- **验证 Buildx**:
  ```bash
  docker buildx version
  # 应输出: github.com/docker/buildx vX.X.X ...
  ```
- **安装指南**: 
  - macOS/Windows: 安装 [Docker Desktop](https://www.docker.com/products/docker-desktop)
  - Linux: 参考 [Docker Engine 安装文档](https://docs.docker.com/engine/install/)

#### Git 环境

- **版本要求**: Git 2.0 或更高版本
- **验证安装**:
  ```bash
  git --version
  ```

### 可选工具

#### kubectl（用于验证 Kubernetes 部署）

```bash
kubectl version --client
```

安装指南: [Kubernetes 文档](https://kubernetes.io/docs/tasks/tools/)

#### 镜像仓库账号

如需推送镜像到远程仓库，需要准备以下之一：
- [GitHub Container Registry (ghcr.io)](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Docker Hub](https://hub.docker.com/)
- 私有镜像仓库

登录命令示例：
```bash
# GitHub Container Registry
docker login ghcr.io -u <username>

# Docker Hub
docker login -u <username>
```

---

## BFE 编译

BFE 是数据面核心组件，负责流量转发与接入控制。

### 1. 源码获取

**GitHub 仓库**: [https://github.com/bfenetworks/bfe](https://github.com/bfenetworks/bfe)

克隆源码：

```bash
# 克隆仓库
git clone https://github.com/bfenetworks/bfe.git
```

### 2. 本地镜像构建

在仓库根目录执行：

```bash
make docker
```

**说明**:
- 此命令会构建 **prod（生产）** 和 **debug（调试）** 两个版本的镜像
- 镜像包含 **BFE** 和 **conf-agent** 两个组件（配置管理代理）
- 镜像 tag 来自仓库根目录的 `VERSION` 文件
- tag 会自动规范化为 `v` 前缀（例如：`1.8.0` → `v1.8.0`）

**构建产物**（以 VERSION=1.8.0 为例）:

```
bfe:v1.8.0        # 生产版本
bfe:v1.8.0-debug  # 调试版本
bfe:latest        # 始终指向最新的生产版本
```

### 3. 验证镜像

#### 查看构建的镜像

```bash
docker images | grep bfe
```

应显示类似输出：
```
bfe    v1.8.0        <image-id>   <size>   <time>
bfe    v1.8.0-debug  <image-id>   <size>   <time>
bfe    latest        <image-id>   <size>   <time>
```

#### 运行镜像验证

```bash
docker run --rm \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 8421:8421 \
  bfe:latest
```

**验证服务**:
- 访问监控端点: http://127.0.0.1:8421/monitor
- 访问服务端点: http://127.0.0.1:8080/ （如配置未命中可能返回 500，属正常）

### 4. 多架构镜像构建与推送

如需将镜像推送到远程仓库供 Kubernetes 集群使用，执行：

```bash
make docker-push REGISTRY=<your-registry> CONF_AGENT_VERSION=v0.0.3
```

**必填参数**:
- `REGISTRY`: 镜像仓库前缀（如 `ghcr.io/your-org`）

**可选参数**:
- `PLATFORMS`: 构建平台（默认 `linux/amd64, linux/arm64`）
- `CONF_AGENT_VERSION`: 已 release 的 conf-agent 版本号
  - 参考: [https://github.com/bfenetworks/conf-agent/tags](https://github.com/bfenetworks/conf-agent/tags)
 
**示例**:

```bash
# 推送到 GitHub Container Registry（多架构）
make docker-push REGISTRY=ghcr.io/cc14514 CONF_AGENT_VERSION=v0.0.3

# 推送到私有仓库（仅 amd64）
make docker-push \
  REGISTRY=registry.example.com \
  CONF_AGENT_VERSION=v0.0.3 \
  PLATFORMS=linux/amd64
```

### 5. 镜像内部结构

BFE 镜像的关键目录：

```
/home/work/bfe/conf/           # BFE 配置目录
/home/work/bfe/log/            # BFE 日志目录
/home/work/conf-agent/conf/    # conf-agent 配置目录
/home/work/conf-agent/log/     # conf-agent 日志目录
```

**自定义配置（测试/验证）**:

```bash
docker run --rm \
  -p 8080:8080 -p 8443:8443 -p 8421:8421 \
  -v $(pwd)/bfe-conf:/home/work/bfe/conf \
  -v $(pwd)/confagent-conf:/home/work/conf-agent/conf/ \
  bfe:latest
```

---

## AI Gateway API 编译

AI Gateway API 是控制面核心组件，负责策略和配置下发接口。

### 1. 源码获取

**GitHub 仓库**: [https://github.com/rainway-ai-gateway/ai-gateway-api](https://github.com/rainway-ai-gateway/ai-gateway-api)

克隆源码：

```bash
git clone https://github.com/rainway-ai-gateway/ai-gateway-api.git
cd ai-gateway-api
git checkout v0.0.1
```

### 2. 本地镜像构建

在仓库根目录执行：

```bash
make docker
```

**说明**:
- 镜像包含 **AI Gateway API** 后端服务和 **Dashboard** Web 前端界面
- Dashboard 前端资源会在构建时自动嵌入到镜像的 `static/` 目录

**关键参数**: `DASHBOARD_VERSION`（可选）

指定 Dashboard 前端资源的版本（来自 [rainway-ai-gatewa/ai-gateway-web](https://github.com/rainway-ai-gateway/ai-gateway-web) 的 release）：

```bash
make docker DASHBOARD_VERSION=v0.0.1
```

**构建产物**:
```
ai-gateway-api:v<Version>  # 版本镜像
ai-gateway-api:latest      # 最新版本
```

### 3. 验证镜像

#### 查看构建的镜像

```bash
docker images | grep ai-gateway-api
```

#### 运行镜像验证

```bash
docker run -d \
  --name ai-gateway-api \
  -p 8183:8183 \
  ai-gateway-api:latest
```

**验证服务**:

- 检查日志: `docker logs ai-gateway-api`

- 访问 Dashboard（需要正确配置数据库）: 
  - 默认URL：`http://localhost:8183`
  - 默认账号：admin
  - 默认密码：admin

### 4. 镜像推送

推送到远程仓库：

```bash
make docker-push REGISTRY=<your-registry> DASHBOARD_VERSION=v0.0.1
```

### 5. 镜像内部结构与配置

**工作目录**: `/home/work/api-server`

**目录结构**:
```
/home/work/api-server/
├── api-server          # 服务二进制
├── conf/               # 配置目录（可通过 volume 覆盖）
├── static/             # 静态资源（Dashboard 前端）
└── log/                # 日志目录
```

**推荐配置挂载**:

```bash
docker run -d \
  --name ai-gateway-api \
  -p 8183:8183 \
  -v $(pwd)/conf:/home/work/api-server/conf \
  -v $(pwd)/log:/home/work/api-server/log \
  ai-gateway-api:latest
```

**配置文件说明**:
- `conf/` 目录包含数据库连接、Redis 配置等

---

## AI Gateway Web 编译

构建 `ai-gateway-api` 镜像时，会自动从 `ai-gateway-web` 的 release 列表中按指定的版本拉取，**通常不需要单独编译**。

### 源码编译

如有需要从源代码构建，请参见 `ai-gateway-web` 项目的编译指南：

**GitHub 仓库**: [https://github.com/rainway-ai-gateway/ai-gateway-web](https://github.com/rainway-ai-gateway/ai-gateway-web)

**编译文档**: [BUILD_GUIDE.md](https://github.com/rainway-ai-gateway/ai-gateway-web/blob/develop/BUILD_GUIDE.md)

---

## Service Controller 编译

Service Controller 负责 Kubernetes 服务发现，自动将符合条件的 Service 资源注册到控制面中。

### 1. 源码获取

**GitHub 仓库**: [https://github.com/bfenetworks/service-controller](https://github.com/bfenetworks/service-controller)

克隆源码：

```bash
git clone https://github.com/bfenetworks/service-controller.git
```

### 2. 本地镜像构建

在仓库根目录执行：

```bash
make docker
```

**构建产物**:
```
service-controller:latest
```

### 3. 验证镜像

#### 查看构建的镜像

```bash
docker images | grep service-controller
```

#### 在 Kubernetes 中验证

Service Controller 设计为在 Kubernetes 集群中运行，本地验证建议直接部署到集群：

```bash
# 应用部署清单（需提前配置 AI Gateway API 地址与 Token）
kubectl apply -f ./examples/service-controller-endpoints.yaml

# 检查部署状态
kubectl get deployment bfe-service-controller
kubectl get pods | grep service-controller

# 查看日志
kubectl logs -f <pod-name>
```

**健康检查端点**:
- Readiness: `GET /ready`
- Liveness: `GET /healthz`

### 4. 多架构镜像推送

推送到远程仓库供 Kubernetes 集群使用：

```bash
make docker-push REGISTRY=<your-registry>
```

### 5. Kubernetes 部署配置要点

**前置依赖**:
- Kubernetes 集群版本 >= v1.20

**关键配置** (`examples/service-controller-endpoints.yaml`):

```yaml
......
          args:
            - '-bfe-api-addr=http://ai-gateway-api.ai-gateway-system.svc.cluster.local:8183'
            - '-bfe-api-token=Token eT5QWkLhQmp6lO4NWxAc'
            - '-k8s-cluster-name=szyf'
            - '-namespace=default'
......
```

- `bfe-api-addr`: AI Gateway API 地址（控制面）
- `bfe-api-token`: API 认证 Token（需从 Dashboard 创建）
- `namespace`: 监听的 Kubernetes 命名空间（监听哪些命名空间的 Service）
  - 在本示例中，后端测试服务（llm-d inference simulator）部署在 `default` 命名空间，因此此项填写为：`default`
  - 说明：控制面/数据面部署在 `ai-gateway-system`，但被发现/同步的后端服务可以在其他命名空间（通过此参数指定）


**后端服务注解要求**:

Service Controller 通过监听 Kubernetes Service 的 **labels** 来发现后端服务，并将符合条件的服务同步到 AI Gateway 控制面。

要让 Service Controller 发现并注册您的后端服务，Service 必须满足以下要求：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  labels:
    bfe-product: AI_product      # 必须：固定值（见下方说明）
spec:
  ports:
    - name: http                 # 必须：端口必须有命名（name 字段）
      port: <port>
      targetPort: <targetPort>
```

**注解说明**:
- `bfe-product`: **必填且固定值为 `AI_product`**
  - AI Gateway 控制面在数据库初始化时默认创建一个固定的产品线 `AI_product`
  - 目前 AI Gateway 不提供在 Dashboard 中创建新产品线的功能
  - 因此所有后端 Service 必须使用 `bfe-product: AI_product` 这个固定值
  - Service Controller 将发现的所有 Service 同步到这个 `AI_product` 产品线
- `spec.ports[].name`: **必填**，端口必须有名称
  - Service Controller 仅同步有命名的端口
  - 命名可以是任意字符串，如 `http`、`https`、`grpc` 等

---

## Kubernetes 部署集成

本章节演示如何将上述编译的三个组件镜像集成部署到 Kubernetes 集群中。

### 1. 前置准备

#### 确认集群环境

```bash
# 检查 kubectl 配置
kubectl cluster-info

# 检查节点状态
kubectl get nodes
```

#### 创建命名空间

按照项目规范，使用独立命名空间隔离资源：

```bash
kubectl apply -f kubernetes/namespace.yaml
```

验证命名空间：
```bash
kubectl get namespace ai-gateway-system
```

### 2. 更新镜像引用

**使用您编译的镜像替换示例配置**

编辑 `kubernetes/kustomization.yaml`，将示例镜像替换为您刚才编译并推送的镜像：

```yaml
# Centralized image override.
#
# Mirror usage:
# - Replace `newName` with your mirror registry/repo path, and optionally set `newTag`.
# - `name` MUST match the image name used in the YAML resources (without the tag).
#
# Example (ghcr -> ghcr.nju.edu.cn):
#   - name: ghcr.io/bfenetworks/bfe
#     newName: ghcr.nju.edu.cn/bfenetworks/bfe
#     newTag: v1.8.0-debug
images:
  # 1. BFE 数据面镜像（包含 conf-agent）
  - name: ghcr.io/bfenetworks/bfe
    newName: ghcr.io/<your-org>/bfe       # 替换为您的镜像地址
    newTag: <your-vsn>            # 替换为您编译的版本

  # 2. AI Gateway API 控制面镜像（包含 Dashboard）
  - name: ghcr.io/rainway-ai-gateway/ai-gateway-api
    newName: ghcr.io/<your-org>/ai-gateway-api    # 替换为您的镜像地址
    newTag: <your-vsn>                    # 替换为您的镜像地址

  # 3. Service Controller 服务发现组件
  - name: ghcr.io/bfenetworks/service-controller
    newName: ghcr.io/<your-org>/service-controller    # 替换为您的镜像地址
    newTag: <your-vsn>                        # 替换为您的镜像地址

  # 其他镜像（如 mysql/redis）按需配置，示例略
```

### 3. 配置镜像拉取凭证（私有仓库）

- 如果您的镜像存储在私有仓库，需要先创建 `imagePullSecrets`：

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<your-username> \
  --docker-password=<your-token> \
  --namespace=ai-gateway-system
```

然后在部署清单中引用凭证（编辑 `kubernetes/*-deploy.yaml`）：

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-secret
```

### 4. 配置外部数据库

**使用示例数据库（默认）**:
- 示例配置使用集群内的 MySQL，数据存储在 `emptyDir`（重启后丢失）
- 适合演示和开发环境，**不推荐生产使用**

**使用外部数据库（推荐生产环境）**:
- 如果您有独立的 MySQL 资源，并已执行了[db初始化脚本](./db_ddl.sql)，需要修改 AI Gateway API 的数据库配置

#### 4.1 调整 ai-gateway-configmap.yaml 配置

编辑 `kubernetes/ai-gateway-configmap.yaml`，更新数据库连接信息：

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

#### 4.2 调整 `kustomization.yaml` 配置

禁用示例数据库部署，编辑 `kubernetes/kustomization.yaml`，注释掉数据库资源：

```yaml
resources:
  - namespace.yaml
  # - mysql-deploy.yaml          # 使用外部 MySQL 时注释此行
  - redis-deploy.yaml          
  - bfe-configmap.yaml
  - bfe-deploy.yaml
  - ai-gateway-configmap.yaml
  - ai-gateway-deploy.yaml
  - service-controller-deploy.yaml
```


### 5. 一键部署

执行以下命令一键部署所有组件：

```bash
kubectl apply -k kubernetes/
```

**说明**:
- `-k` 参数使用 Kustomize 自动处理资源编排
- 自动应用 `kustomization.yaml` 中的镜像替换配置
- 按正确顺序创建所有资源（命名空间、ConfigMap、Deployment、Service 等）

**部署的资源** (Namespace: ai-gateway-system):
- ✅ MySQL 数据库（或跳过，如使用外部数据库）
- ✅ Redis 缓存服务（数据面、控制面均依赖此服务）
- ✅ BFE 数据面（包含 conf-agent）
- ✅ AI Gateway API 控制面（包含 Dashboard）
- ✅ Service Controller 服务发现

### 6. 部署测试服务（验证路由转发）

**示例后端服务（llm-d inference simulator）说明**:

本仓库提供了一个示例后端服务清单，用于验证 Service 发现与 BFE 路由转发能力。该清单会在 `default` 命名空间部署一个 LLM 推理模拟服务（Deployment: `vllm-llama3-8b-instruct`，Service: `vllm-llama3-8b-instruct-svc`）。

**部署示例后端服务**:

```bash
kubectl apply -f kubernetes/llm-d-inference-sim-deploy.yaml
```

**关键配置说明**:

示例后端服务部署在 `default` 命名空间，其 Service 配置了必需的标签：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vllm-llama3-8b-instruct-svc
  namespace: default
  labels:
    bfe-product: AI_product  # 必须：Service Controller 依赖此标签发现服务
spec:
  ports:
    - name: http             # 必须：端口必须命名
      port: 8000
      targetPort: 8000
  selector:
    app: vllm-llama3-8b-instruct
```

**注意事项**:
- 示例后端服务部署在 `default` 命名空间，而不是 `ai-gateway-system`
- 如需替换镜像/模型参数，请直接编辑 `kubernetes/llm-d-inference-sim-deploy.yaml` 文件
- 必须在 Dashboard 中配置转发规则后才能通过 BFE 访问后端服务

### 7. 验证部署状态

#### 检查所有 Pod 状态

```bash
kubectl get pods -n ai-gateway-system
```

预期输出：
```
NAME                                READY   STATUS    RESTARTS   AGE
ai-gateway-api-xxx                  1/1     Running   0          5m
bfe-xxx                             1/1     Running   0          5m
mysql-xxx                           1/1     Running   0          6m
redis-xxx                           1/1     Running   0          6m
service-controller-xxx              1/1     Running   0          5m
```


#### 访问控制面（配置转发规则）

浏览器访问: `http://<NodeIP>:30183`

- 默认账号：admin
- 默认密码：admin

#### 测试转发规则

未正确配置转发规则时，将返回 500 错误

```bash
curl http://<NodeIP>:30080/
```

---

## 故障排查

### 1) Pod 拉取镜像失败（ImagePullBackOff / ErrImagePull）

```bash
kubectl get pods -n ai-gateway-system
kubectl describe pod -n ai-gateway-system <pod-name>
```

常见原因：
- `kubernetes/kustomization.yaml` 的 `images:` 未正确替换（镜像仓库/Tag 不存在）
- 私有仓库未配置 `imagePullSecrets`（或 Secret 创建在错误的 namespace）

### 2) 控制面无法正常启动（ai-gateway-api CrashLoopBackOff）

```bash
kubectl logs -n ai-gateway-system -l app=ai-gateway-api --tail=200
kubectl get pods -n ai-gateway-system -l app=mysql
kubectl get pods -n ai-gateway-system -l app=redis
```

常见原因：
- MySQL/Redis 未就绪或连接信息不匹配（使用外部数据库时更常见）
- 未执行数据库初始化脚本（外部 MySQL 场景）

### 3) Service Controller 未发现/同步示例后端服务

```bash
# Service 是否有 Endpoints
kubectl get endpoints vllm-llama3-8b-instruct-svc -n default

# Service 是否带有固定标签
kubectl get svc vllm-llama3-8b-instruct-svc -n default -o yaml | grep -A3 "labels:"

# Service Controller 日志
kubectl logs -n ai-gateway-system -l app=service-controller --tail=200
```

检查点：
- 后端 Service 必须带 `bfe-product: AI_product`
- Service Controller 的监听 namespace 必须覆盖示例后端服务所在的 `default`（本项目清单默认监听 `default`）

### 4) BFE 访问返回 500

```bash
curl -v http://<NodeIP>:30080/
kubectl logs -n ai-gateway-system -l app=bfe --tail=200
```

说明：
- 未在 Dashboard 配置转发规则时返回 500 属于预期现象
- 若已配置规则仍 500，请优先确认后端是否已被 Service Controller 同步（见上一节）

## 日志收集

```bash
# 创建日志目录
mkdir -p /tmp/ai-gateway-logs

# 收集各组件日志
kubectl logs -n ai-gateway-system -l app=bfe > /tmp/ai-gateway-logs/bfe.log
kubectl logs -n ai-gateway-system -l app=ai-gateway-api > /tmp/ai-gateway-logs/api.log
kubectl logs -n ai-gateway-system -l app=service-controller > /tmp/ai-gateway-logs/controller.log
kubectl logs -n ai-gateway-system -l app=mysql > /tmp/ai-gateway-logs/mysql.log
kubectl logs -n ai-gateway-system -l app=redis > /tmp/ai-gateway-logs/redis.log

# 收集事件
kubectl get events -n ai-gateway-system --sort-by='.lastTimestamp' > /tmp/ai-gateway-logs/events.log
```

**查看实时日志**:
```bash
kubectl logs -f -n ai-gateway-system -l app=bfe --all-containers=true --tail=100
```

---

## 参考资料

### 官方文档

- **BFE 项目**
  - GitHub: https://github.com/bfenetworks/bfe
  - 官方文档: https://www.bfe-networks.net/
  - 配置参考: https://www.bfe-networks.net/en_us/configuration/overview/

- **AI Gateway API**
  - GitHub: https://github.com/rainway-ai-gateway/ai-gateway-api
  - Dashboard 前端: https://github.com/rainway-ai-gateway/ai-gateway-web

- **llm-d inference simulator（示例后端模拟器）**
  - GitHub: https://github.com/llm-d/llm-d-inference-sim

- **Service Controller**
  - GitHub: https://github.com/bfenetworks/service-controller
  - Kubernetes 集成指南: https://github.com/bfenetworks/service-controller/blob/main/README.md

### 技术栈文档

- **Kubernetes**
  - 官方文档: https://kubernetes.io/docs/
  - Kustomize: https://kubectl.docs.kubernetes.io/references/kustomize/

- **Docker**
  - Docker Buildx: https://docs.docker.com/buildx/working-with-buildx/
  - 多架构构建: https://docs.docker.com/build/building/multi-platform/
