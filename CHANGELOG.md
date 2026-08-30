# Changelog

## [v0.5.0] — 2026-08-30

### Updated Components

| Component | Version |
|---|---|
| BFE | [v1.8.6](https://github.com/bfenetworks/bfe/releases/tag/v1.8.6) |
| AI Gateway API | [v0.0.8](https://github.com/rainway-ai-gateway/ai-gateway-api/releases/tag/v0.0.8) |
| Dashboard | [v0.0.8](https://github.com/rainway-ai-gateway/ai-gateway-web/releases/tag/v0.0.8) |
| Observability | [v0.0.1](https://github.com/rainway-ai-gateway/ai-gateway-observability/releases/tag/v0.0.1) |
| conf-agent | [v0.0.6](https://github.com/rainway-ai-gateway/conf-agent/releases/tag/v0.0.6) |

### Added

- **Observability stack restored**: full pipeline re-integrated against `bfe-access-pb` v0.2.0 schema (unavailable in v0.4.0).
- Enriched Doris schema: ~30 new detail-table columns, 13 new aggregate-table dimensions/metrics (provider, protocol, mode, cost, cache, audio/image tokens, retry count, `level1`–`level5` tag slots).
- `scripts/sync-grafana.sh` and `scripts/sync-doris.sh`: pull configs from `ai-gateway-observability` by tag, render templates for both Docker Compose and K8s targets. `make sync-grafana`, `make sync-doris`, `make sync` targets. `OBS_VERSION` added to `VERSIONS.yaml`.
- K8s manifests split into auto-generated ConfigMap files (`doris-configmap.yaml`, `grafana-configmap.yaml`) and manually-maintained workload files.
- Doris FE healthcheck in Docker Compose with `service_healthy` ordering — fixes cold-start deadlock.
- Grafana datasource now declares explicit `uid: doris` for stable panel binding.

### Changed

- Bump BFE to v1.8.6, AI Gateway API to v0.0.8, Dashboard to v0.0.8.
- K8s `kustomization.yaml` image tags bumped to match (previously stale at v1.8.4 / v0.0.6 since v0.3.0).
- K8s deploy commands now two-step (ConfigMap + workload).

### Breaking Changes

- **Doris schema incompatible with v0.4.0**: field renames (`ai_apikey_id`, `ai_target_model`, `input_tokens`, `level1`–`level5`) plus many new columns. Upgrades require dropping and re-creating `bfe_observability`.
- **Grafana datasource** now requires `uid: doris`; old name-only references show "No data" until updated.

### Fixed

- Doris FE/BE cold-start deadlock in Docker Compose (FE `waitForReady` vs BE wait-for-9030) — fixed by FE healthcheck + `service_healthy` gating.

---

## [v0.4.0] — 2026-08-21

### Updated Components

| Component | Version |
|---|---|
| BFE | [v1.8.5](https://github.com/bfenetworks/bfe/releases/tag/v1.8.5) |
| AI Gateway API | [v0.0.7](https://github.com/rainway-ai-gateway/ai-gateway-api/releases/tag/v0.0.7) |
| Dashboard | [v0.0.7](https://github.com/rainway-ai-gateway/ai-gateway-web/releases/tag/v0.0.7) |
| Log Reader | [v1.1.0](https://github.com/bfenetworks/log-reader/releases/tag/v1.1.0) |
| conf-agent | v0.0.5 (unchanged) |

### ⚠️ Observability not available

Log Reader v1.1.0 upgraded to `bfe-access-pb` v0.2.0 with field renames; Kafka / Doris / Grafana were not re-integrated. Compose `--profile observability` and K8s `doris.yaml` / `grafana.yaml` do not work in this release. Core gateway functionality unaffected; observability restored in v0.5.0.

### Added

- **Model pricing**: new Model Pricing module (Dashboard + API) backed by `model_prices` table; `quota_plan.unit` supports `RMB`.
- **Multi-API-Key routing**: clusters support `keys` (name/key/weight) + `key_policy`, with weighted routing across a cluster's keys.
- **Provider/model prefix routing**: `match_prefix` / `strip_prefix` for aggregated providers (e.g. OpenRouter).
- **Route-rule fallbacks** + `req_body_json_prefix_in` condition primitive.
- **Rebrand**: org / image registry → `rainway-ai-gateway`; route-rule fields renamed to `snake_case`.

### Changed

- Bump BFE to v1.8.5, AI Gateway API to v0.0.7, Dashboard to v0.0.7, Log Reader to v1.1.0.

### Breaking Changes

- **Database schema**: new `model_prices` table; `quota_plans.quota` and `quota_balances.used/remaining` changed from `BIGINT → DECIMAL(18,8)`. New deployments auto-init via `api_db_ddl.sql`; **v0.3.0 upgrades require manual migration**.
- **Log Reader field renames** (`bfe-access-pb` v0.2.0): `ai_apikey → ai_apikey_id`, `ai_mapped_model → ai_target_model`, `ai_prompt_tokens → ai_input_tokens`.

### Fixed

- BFE: RMB cost calculation for streaming responses, token-auth default rule path.
- API: route-rule reference deletion checks, quota/Redis sync, model-pricing validation.
- Dashboard: port sync, secret masking, pricing validation.

---

## [v0.3.0] — 2026-08-07

### Updated Components

| Component | Version |
|---|---|
| BFE | [v1.8.4](https://github.com/bfenetworks/bfe/releases/tag/v1.8.4) |
| AI Gateway API | [v0.0.6](https://github.com/rainway-ai-gateway/ai-gateway-api/releases/tag/v0.0.6) |
| Dashboard | [v0.0.6](https://github.com/rainway-ai-gateway/ai-gateway-web/releases/tag/v0.0.6) |
| conf-agent | v0.0.5 ([rainway-ai-gatewa](https://github.com/rainway-ai-gateway/conf-agent)) |

### Added

- Per-key / per-entity / global routing rules: new `route_rules` table supports three routing tiers (`api_key`, `entity`, `global`), with `route_rules_id` FK added to `api_keys` and `entities` tables.
- `mod_ai_route` BFE module enabled in `conf/bfe.conf` and K8s ConfigMap, with conf-agent hot-reload (`ai_route.data`) wired in `Dockerfile.standalone`.

### Changed

- Bump AI Gateway API to v0.0.6, Dashboard to v0.0.6, conf-agent to v0.0.5.
- BFE tagged as official release v1.8.4 (previously tracked as develop build).
- `EnableAiGateway` default reset to `false` in `conf/bfe.conf` and K8s `bfe-configmap.yaml` — must explicitly enable for AI traffic gateway mode.
- **Database schema changes**: `api_keys`/`api_key_tokens` api_key narrowed (1024→128), unique index added; `certificates` columns removed; `route_rules_id` added to `api_keys`/`entities`; new `route_rules` table. New deployments auto-init via DDL; existing v0.2.0 upgrades need manual migration.
- Grafana dashboard legend placement moved from right to bottom for all panels.

---

## [v0.2.0] — 2026-07-24

### Updated Components

| Component | Version |
|---|---|
| BFE | v1.8.4 (develop build) |
| AI Gateway API | [v0.0.5](https://github.com/rainway-ai-gateway/ai-gateway-api/releases/tag/v0.0.5) |
| Dashboard | [v0.0.5](https://github.com/rainway-ai-gateway/ai-gateway-web/releases/tag/v0.0.5) |
| conf-agent | v0.0.4 ([rainway-ai-gatewa](https://github.com/rainway-ai-gateway/conf-agent)) |
| log-reader | [v1.0.0](https://github.com/bfenetworks/log-reader) |

### Changed

- Bump AI Gateway API to v0.0.5 — API endpoint simplification, InstancePool auto-creation, breaking URL path changes (see [upgrade notes](https://github.com/rainway-ai-gateway/ai-gateway-api/releases/tag/v0.0.5)).
- Bump Dashboard to v0.0.5 — reduced module scope, cluster/consumer management enhancements, navigation reorganization.

### Added

- Full-stack observability: log-reader → Kafka → Doris → Grafana (Compose + K8s).
  - **Log Reader** integrated into BFE/ai-gateway image, reads `pb_access3.log`, sends JSON to Kafka.
  - **Kafka** (KRaft single-node) with pre-created topics `bfe_ai_log` / `bfe_ai_log_dlq`.
  - **Doris** FE + BE + init Job: detail table + 33-dimension aggregate table + Routine Load + INSERT JOB.
  - **Grafana** pre-provisioned "BFE AI Gateway Dashboard".
  - Compose: `docker compose --profile observability up -d`, fully automated.
  - K8s: `kubectl apply -f deploy/doris.yaml -f deploy/grafana.yaml`.
- MySQL persistent storage guide for K8s (`deploy/mysql-pvc.yaml`).

### Fixed

- Fix `Exec format error` on amd64 servers when image is built on Apple Silicon.
- Fix missing `[Loggers.exception]` in config template causing API server crash.
- Fix BFE startup failure due to missing `QuotaPlans` in default `token_rule.data`.
- Fix entrypoint to dump process logs to `docker logs` on startup failure.
- Fix `docker compose` prerequisite instructions for Linux users.
- Fix Kafka single-node consumer group timeout via `offsets.topic.replication.factor=1`.
- Fix aggregate table schema mismatch with Grafana dashboard (33 dimension columns).

---

## [v0.1.1] — 2026-07-15

### Updated Components

| Component | Version |
|---|---|
| BFE | v1.8.4 (develop build) |
| AI Gateway API | v0.0.4 (develop build) |
| Dashboard | [v0.0.4](https://github.com/rainway-ai-gateway/ai-gateway-web/releases/tag/v0.0.4) |
| conf-agent | v0.0.4 ([rainway-ai-gatewa](https://github.com/rainway-ai-gateway/conf-agent)) |

### Changed

- Bump BFE to v1.8.4 (fix token calculation, allow_models check, session_sticky redis unmarshal).
- Bump AI Gateway API to v0.0.4 (mod_body_process config export, PATCH/PUT Entity, allow_models intersection optimization).
- Bump Dashboard to v0.0.4 (certificate management, grouped model selectors, i18n improvements).

---

## [v0.1.0] — 2026-07-10

First official release of AI Gateway — a product-level entry point that unifies version management across all sub-components. Replaces `ai-gateway-demo`, adding all-in-one container deployment alongside existing K8s manifests.

### Component Versions

| Component | Version |
|---|---|
| BFE | [v1.8.3](https://github.com/bfenetworks/bfe/releases/tag/v1.8.3) |
| AI Gateway API | [v0.0.3](https://github.com/rainway-ai-gateway/ai-gateway-api/releases/tag/v0.0.3) |
| Dashboard | v0.0.3 ([ai-gateway-web](https://github.com/rainway-ai-gateway/ai-gateway-web)) |
| conf-agent | v0.0.3 ([rainway-ai-gatewa](https://github.com/rainway-ai-gateway/conf-agent)) |
| Service Controller | v0.0.1 |

### Added

- All-in-One container deployment via `Dockerfile.standalone` + `docker-compose.yml`.
- One-command startup: `docker compose up -d` launches MySQL + Redis + AI Gateway.
- Automatic database initialization on first boot (`api_db_ddl.sql` with full seed data).
- Docker network DNS using the same naming convention as K8s Service DNS.
- Test simulator via `docker compose --profile test up -d`.
- Multi-arch images: `linux/amd64` and `linux/arm64`.
- `VERSIONS.yaml` as single source of truth for component versions.
- Kubernetes deployment manifests migrated from `ai-gateway-demo`.
- Bilingual README (EN/CN), BUILD_GUIDE, K8s documentation, CONTRIBUTING.
