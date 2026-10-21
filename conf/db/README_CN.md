# 数据库脚本

本目录集中存放网关用到的全部 SQL 文件。正常安装时无需手动执行其中任何一个：两份全量 DDL 会被自动加载，`*_upgrade_to_*` 仅用于升级一个**已经存在**的数据库。

## 文件说明

| 文件 | 数据库 | 用途 |
|---|---|---|
| `api_db_ddl_mysql.sql` | `open_bfe` | 控制面全量 schema + 种子数据，仅用于**全新安装** |
| `report_db_ddl_mysql.sql` | `bfe_report` | 报表面：请求明细表 + 分钟聚合表，仅用于**全新安装** |
| `api_db_ddl_mysql_upgrade_to_0.0.11.sql` | `open_bfe` | 控制面 v0.0.10 / v0.0.10.1 → v0.0.11（产品 v0.7.x → v0.8.0） |
| `report_db_ddl_mysql_upgrade_to_0.0.11.sql` | `bfe_report` | 报表库 v0.7.x → v0.8.0（明细 10 列、聚合 3 列、`logid` 幂等键） |

命名规则：`<面>_db_ddl_<后端>[_upgrade_to_<schema 版本>].sql`，`<面>` 为 `api`（控制面）或 `report`（报表面），`<后端>` 为 `mysql`。报表库的 Doris 形态不在这里，由 `make sync` 生成到 `conf/doris/`。

## 全新安装（默认路径，不需要执行任何脚本）

两种部署方式都会自己初始化空库：

- **Docker Compose** —— entrypoint 检测到 `open_bfe.users` 不存在时执行 `api_db_ddl_mysql.sql`；检测到报表两表不齐时执行 `report_db_ddl_mysql.sql`。两份文件已打进镜像的 `/home/work/db/`。
- **Kubernetes** —— `mysql-init` ConfigMap 携带同样两份文件，`mysql-init-job` 在同样条件下执行。

自动化路径只会碰这两份全量 DDL；`*_upgrade_to_*.sql` 不会被挂载、不会进运行镜像、也不会被 entrypoint 或 init Job 执行。

## 与上游母版 `ai-gateway-api/db_ddl.sql` 的差异

派生副本**不是**逐字复制母版，差异是一个受控白名单——只多 4 条种子、改写 1 条。`scripts/gen-db-ddl.py --check` 会强制这个集合不变，多一条少一条都报错。

| 差异 | 内容 | 原因 |
|---|---|---|
| +1 条 insert | `users` `demo`（id=2，`scopes=Product`，`type=1`，ticket） | 产品维度的演示/测试账号 |
| +1 条 insert | `users` `conf-agent`（id=3，`scopes=System`，`type=1`，ticket） | 数据面 conf-agent 拉配置用的服务账号 |
| +1 条 insert | `user_products` `(2, 2)` | 把 demo 绑到 `AI_product`，缺这条产品维度接口一律 402 |
| +1 条 insert | `epp_instances` `epp-0`（Compose 1 条 / K8s 2 条） | 零配置启动时 EPP 的地址 |
| ~1 条改写 | `products` 母版的两条 insert 合并为一条，显式 `id=1` 与 `id=2` | `user_products` 硬引用 `id=2`，不能依赖自增顺序 |
| 其余全部 | `admin` 种子、`pools`、`bfe_clusters`、`route_rules`、`keyrotate_sweep_lock`、42 张表定义 | 与母版逐字一致，不允许有任何偏差 |

这个白名单从 v0.1.0 一直延续到 v0.7.0（当时的 `api_db_ddl.sql` 就是这么写的），v0.8.0 整理目录时被误裁，已按上游母版恢复。

## 初始化后会自带的数据

`api_db_ddl_mysql.sql` 除了建 42 张表，还会写入一套可直接使用的种子数据。全新安装完成后应当能查到这 7 项，缺任何一项都说明 DDL 被裁过：

| 表 | 内容 | 说明 |
|---|---|---|
| `users` | `admin` / `admin`（`scopes=System`，`type=0`） | Dashboard 登录账号，口令即 `admin`，bcrypt cost=10 存储 |
| `users` | `demo`（`scopes=Product`）、`conf-agent`（`scopes=System`） | 服务账号，`type=1`，无口令，用 `ticket` 认证 |
| `user_products` | `demo` → `AI_product` | 不给这条，Product scope 解析不到产品，所有带产品维度的 OpenAPI 都返回 402 |
| `products` | `BFE`(id=1)、`AI_product`(id=2) | id 是硬编码引用的，不要改成自增 |
| `pools` | `BFE.aipool`（product_id=1） | 默认转发池 |
| `bfe_clusters` | `BFE-AI_product.szyf`（pool=`BFE.aipool`） | 默认集群 |
| `epp_instances` | Compose 1 条 `127.0.0.1:9002`；K8s 2 条 pod FQDN | 唯一允许两侧不同的种子 |
| `route_rules` | `global` 一行，`enabled=0` | 全局路由占位 |
| `keyrotate_sweep_lock` | `id=1` 单行 | 密钥收敛任务的单行锁，缺了收敛任务起不来 |

## 两份派生副本怎么维护

`conf/db/api_db_ddl_mysql.sql` 与 `kubernetes/deploy/mysql-deploy.yaml` 里内嵌的 `api_db_ddl_mysql.sql` 都是从上游 `ai-gateway-api/db_ddl.sql` 派生的**生成物**，不要手工编辑——手工裁剪曾导致种子和尾部 4 张表被静默丢掉。

```bash
python3 scripts/gen-db-ddl.py --check   # 发版前必跑：两份派生是否与母版一致
python3 scripts/gen-db-ddl.py --write   # 上游有变更时同步生成（只改种子段的 epp 地址）
```

`--check` 会比对表数量、关键表是否存在、每一条种子是否还在。上游 `db_ddl.sql` 更新后忘了跑 `--write`，CI 里应当直接失败。

## 升级已有部署

数据库升级是有意保留的人工步骤。DDL 非幂等（MySQL 没有 `ADD COLUMN IF NOT EXISTS`），且 DDL 无法在事务里回滚，所以宁可拒绝启动，也不做"半升级"。

### 1. 准备

- 先看目标版本的 release note 的「升级须知」，确认该版本需要哪个脚本、有无执行顺序要求。
- 备份两个库：

  ```bash
  mysqldump -h<host> -u<user> -p --single-transaction --routines \
      open_bfe bfe_report > backup-$(date +%F).sql
  ```

- 停掉数据面，避免升级期间继续写入：
  Compose 执行 `docker compose stop ai-gateway`；K8s 执行
  `kubectl -n ai-gateway-system scale deploy/ai-gateway-api deploy/bfe --replicas=0`。

### 2. 执行（先控制面，后报表库）

两个脚本开头都自带 `USE <库名>;`，命令行不需要再指定库；库名不同的先改那一行。

**Docker Compose**（在仓库根目录执行）：

```bash
docker compose exec -T mysql \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/api_db_ddl_mysql_upgrade_to_0.0.11.sql

docker compose exec -T mysql \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/report_db_ddl_mysql_upgrade_to_0.0.11.sql
```

**Kubernetes：**

```bash
kubectl -n ai-gateway-system exec -i deploy/mysql -- \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/api_db_ddl_mysql_upgrade_to_0.0.11.sql

kubectl -n ai-gateway-system exec -i deploy/mysql -- \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/report_db_ddl_mysql_upgrade_to_0.0.11.sql
```

**外部 MySQL：**

```bash
mysql -h<host> -P<port> -u<user> -p < conf/db/api_db_ddl_mysql_upgrade_to_0.0.11.sql
mysql -h<host> -P<port> -u<user> -p < conf/db/report_db_ddl_mysql_upgrade_to_0.0.11.sql
```

### 3. 校验

```sql
SELECT COUNT(*) FROM information_schema.columns
 WHERE table_schema='open_bfe' AND table_name='providers'
   AND column_name='instance_source';           -- 期望 1

SELECT COUNT(*) FROM information_schema.columns
 WHERE table_schema='bfe_report' AND table_name='bfe_ai_request_log'
   AND column_name='ai_intent_questions_version'; -- 期望 1
```

两条都必须返回 `1`。Compose 的 entrypoint 与 K8s 的 init Job 启动时跑的正是这两条探测，返回 `0` 即 `exit 1` —— 漏升级会直接启动失败，而不是数据面跑着却一行日志都写不进去。

### 4. 启动新版本

`docker compose up -d ai-gateway`，或重新 apply 清单并把副本数拉回。如果 K8s 的 `mysql-init-job` 因为守卫停在失败状态，迁移完成后删掉它让其重跑：
`kubectl -n ai-gateway-system delete job mysql-init-job`。

## 容易踩的点

- **脚本非幂等。** 重复执行会报 `Duplicate column` / `Duplicate key`，属预期，跳过该语句即可。
- **报表脚本有顺序要求。** 它先把 `NULL` 的 `logid` 回填，再 `MODIFY ... NOT NULL`，并重建 `uk_dedup`；顺序颠倒会报 1138。
- **`api_keys.api_key_hash` 不由 SQL 填充。** 该值是带应用级 pepper 的 HMAC-SHA256，存量行必须先由外部脚本回填（见控制面脚本末尾「手动步骤」），再切唯一键。
- **`epp_assignments.primary_instance_id` 会被删除。** 旧版本上要先把 EPP 实例池收敛成单实例组，否则组内实例按 `id` 序派生，可能出现一次指向切换。
- **大表。** 放低峰窗口做，或用 `pt-online-schema-change`。每个脚本末尾都附了注释掉的应急回滚语句。

## 新增 schema 变更时

同一版本要提交两个文件：更新后的全量 DDL（新装用户拿到新结构）和新的 `<面>_db_ddl_mysql_upgrade_to_<版本>.sql`（存量库能升上去）。两者都要写进 release note 的升级须知，并更新上面这张表。
