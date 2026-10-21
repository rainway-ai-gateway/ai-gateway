# Database schemas

Every SQL file the stack needs, in one place. Nothing here is executed by hand
during a normal install — the two full DDLs are picked up automatically, and the
`*_upgrade_to_*` files are only for migrating a database that already exists.

## Files

| File | Database | Purpose |
|---|---|---|
| `api_db_ddl_mysql.sql` | `open_bfe` | Control plane: full schema + seed data. Used on **fresh install** only. |
| `report_db_ddl_mysql.sql` | `bfe_report` | Report plane: request detail + 1-minute aggregate tables. Used on **fresh install** only. |
| `api_db_ddl_mysql_upgrade_to_0.0.11.sql` | `open_bfe` | Migrates a v0.0.10 / v0.0.10.1 control plane to the v0.0.11 schema (product v0.7.x → v0.8.0). |
| `report_db_ddl_mysql_upgrade_to_0.0.11.sql` | `bfe_report` | Migrates a v0.7.x report schema to v0.8.0 (10 detail columns, 3 aggregate columns, `logid` dedup key). |

Naming: `<plane>_db_ddl_<backend>[_upgrade_to_<schema version>].sql`, where
`<plane>` is `api` (control plane) or `report`, and `<backend>` is `mysql`.
The Doris variant of the report schema is not here — it is generated into
`conf/doris/` by `make sync`.

## Fresh install (default path, nothing to run)

Both deployment modes initialize an empty database by themselves:

- **Docker Compose** — the entrypoint runs `api_db_ddl_mysql.sql` when
  `open_bfe.users` is missing, then `report_db_ddl_mysql.sql` when either report
  table is missing. Both files are baked into the image at `/home/work/db/`.
- **Kubernetes** — the `mysql-init` ConfigMap carries the same two files and
  `mysql-init-job` runs them under the same conditions.

These are the only files any automated path touches. An `*_upgrade_to_*.sql`
file is never mounted, never baked into the runtime image and never executed by
the entrypoint or the init Job.

## Delta against the upstream master `ai-gateway-api/db_ddl.sql`

The derived copy is **not** a verbatim copy. The delta is a controlled whitelist:
four extra seed rows and one rewritten row. `scripts/gen-db-ddl.py --check`
enforces it — one row more or less fails the check.

| Delta | Content | Why |
|---|---|---|
| +1 insert | `users` `demo` (id=2, `scopes=Product`, `type=1`, ticket) | Product-scoped demo/test account |
| +1 insert | `users` `conf-agent` (id=3, `scopes=System`, `type=1`, ticket) | Service account the data plane uses to pull config |
| +1 insert | `user_products` `(2, 2)` | Binds demo to `AI_product`; without it every product-scoped call answers 402 |
| +1 insert | `epp_instances` `epp-0` (one row on Compose, two on K8s) | EPP address for a zero-config start |
| ~1 rewrite | the master's two `products` inserts merged into one with explicit `id=1` and `id=2` | `user_products` references `id=2` literally, so it cannot rely on auto-increment |
| everything else | the `admin` seed, `pools`, `bfe_clusters`, `route_rules`, `keyrotate_sweep_lock`, all 42 table definitions | Byte-identical to the master, no deviation allowed |

This whitelist has been in place since v0.1.0 through v0.7.0 (that is exactly how
`api_db_ddl.sql` was written then). It was trimmed by accident while reorganizing
the directory for v0.8.0 and has been restored from the master.

## What a fresh install already contains

`api_db_ddl_mysql.sql` creates 42 tables and seeds a working default dataset.
After a fresh install these seven items must be present; a missing one means the
DDL was trimmed.

| Table | Content | Notes |
|---|---|---|
| `users` | `admin` / `admin` (`scopes=System`, `type=0`) | Dashboard login, password stored as bcrypt cost=10 |
| `users` | `demo` (`scopes=Product`), `conf-agent` (`scopes=System`) | Service accounts, `type=1`, no password, ticket auth |
| `user_products` | `demo` → `AI_product` | Without it the Product scope resolves to no product and scoped OpenAPI calls answer 402 |
| `products` | `BFE` (id=1), `AI_product` (id=2) | The ids are referenced literally; do not make them auto-increment |
| `pools` | `BFE.aipool` (product_id=1) | Default forwarding pool |
| `bfe_clusters` | `BFE-AI_product.szyf` (pool=`BFE.aipool`) | Default cluster |
| `epp_instances` | Compose: one row `127.0.0.1:9002`; K8s: two pod FQDNs | The only seed allowed to differ between the two |
| `route_rules` | one `global` row, `enabled=0` | Global routing placeholder |
| `keyrotate_sweep_lock` | one row, `id=1` | Single-row lock for the key rotation sweep; the task cannot start without it |

## How the two derived copies are maintained

`conf/db/api_db_ddl_mysql.sql` and the `api_db_ddl_mysql.sql` block embedded in
`kubernetes/deploy/mysql-deploy.yaml` are **generated** from the upstream
`ai-gateway-api/db_ddl.sql`. Do not hand-edit them — hand-trimming once silently
dropped the seed rows and the last four tables.

```bash
python3 scripts/gen-db-ddl.py --check   # run before every release: derived copies vs master
python3 scripts/gen-db-ddl.py --write   # regenerate after an upstream change (only the epp seed differs)
```

`--check` compares the table count, the presence of every critical table and
every seed row. Forgetting `--write` after an upstream change must fail the
build.

## Upgrading an existing deployment

Schema upgrades are a deliberate manual step. The DDL is not idempotent (MySQL
has no `ADD COLUMN IF NOT EXISTS`) and DDL cannot be rolled back inside a
transaction, so the stack refuses to silently half-migrate a database.

### 1. Prepare

- Read the **Upgrade notes** of the release you are installing; they name the
  script(s) for that version and any ordering constraints.
- Back up both databases:

  ```bash
  mysqldump -h<host> -u<user> -p --single-transaction --routines \
      open_bfe bfe_report > backup-$(date +%F).sql
  ```

- Stop the data plane so nothing writes while the schema changes:
  `docker compose stop ai-gateway` (Compose) or
  `kubectl -n ai-gateway-system scale deploy/ai-gateway-api deploy/bfe --replicas=0` (Kubernetes).

### 2. Apply, control plane first, then report

Each script starts with `USE <database>;`, so no database argument is needed.
If your databases are named differently, edit that line first.

**Docker Compose** (run from the repository root):

```bash
docker compose exec -T mysql \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/api_db_ddl_mysql_upgrade_to_0.0.11.sql

docker compose exec -T mysql \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/report_db_ddl_mysql_upgrade_to_0.0.11.sql
```

**Kubernetes:**

```bash
kubectl -n ai-gateway-system exec -i deploy/mysql -- \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/api_db_ddl_mysql_upgrade_to_0.0.11.sql

kubectl -n ai-gateway-system exec -i deploy/mysql -- \
    sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    < conf/db/report_db_ddl_mysql_upgrade_to_0.0.11.sql
```

**External MySQL:**

```bash
mysql -h<host> -P<port> -u<user> -p < conf/db/api_db_ddl_mysql_upgrade_to_0.0.11.sql
mysql -h<host> -P<port> -u<user> -p < conf/db/report_db_ddl_mysql_upgrade_to_0.0.11.sql
```

### 3. Verify

```sql
SELECT COUNT(*) FROM information_schema.columns
 WHERE table_schema='open_bfe' AND table_name='providers'
   AND column_name='instance_source';           -- expect 1

SELECT COUNT(*) FROM information_schema.columns
 WHERE table_schema='bfe_report' AND table_name='bfe_ai_request_log'
   AND column_name='ai_intent_questions_version'; -- expect 1
```

Both must return `1`. The Compose entrypoint and the Kubernetes init Job run
exactly these two probes at startup and `exit 1` when either returns `0`, so a
missed upgrade fails fast instead of producing a data plane that logs nothing.

### 4. Start the new version

`docker compose up -d ai-gateway`, or re-apply the manifests and scale the
workloads back up. If the Kubernetes `mysql-init-job` was left in a failed
state by the guard, delete it so it re-runs after the migration:
`kubectl -n ai-gateway-system delete job mysql-init-job`.

## Things that bite

- **Not idempotent.** Re-running a script reports `Duplicate column` /
  `Duplicate key` errors. That is expected; skip those statements.
- **Report script order matters.** It backfills `NULL` `logid` values *before*
  `MODIFY ... NOT NULL`, and rebuilds `uk_dedup`. Running section 3 out of order
  fails with error 1138.
- **`api_keys.api_key_hash` is not filled by SQL.** The hash is
  HMAC-SHA256 with an application constant, so existing rows must be backfilled
  by an external script (see the "manual steps" section at the end of the
  control-plane script) before the unique key is switched.
- **`epp_assignments.primary_instance_id` is dropped.** Collapse the EPP pool
  into one-instance groups on the old version first, otherwise the group's
  first instance is derived by `id` order and a one-time target switch can occur.
- **Large tables.** Run in a low-traffic window, or use
  `pt-online-schema-change`. Every script carries its emergency rollback
  statements at the end, commented out.

## Adding a schema change

Ship two files in the same release: the updated full DDL (so fresh installs get
it) and a new `<plane>_db_ddl_mysql_upgrade_to_<version>.sql` (so existing
databases can get there). Reference both from the release notes' upgrade notes
and from the table above.
