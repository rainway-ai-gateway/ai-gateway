# Changelog

## [v0.2.0] — 2026-07-24

### Updated Components

| Component | Version |
|---|---|
| BFE | v1.8.4 (develop build) |
| AI Gateway API | [v0.0.5](https://github.com/yf-networks/ai-gateway-api/releases/tag/v0.0.5) |
| Dashboard | [v0.0.5](https://github.com/yf-networks/ai-gateway-web/releases/tag/v0.0.5) |
| conf-agent | v0.0.4 ([yf-networks](https://github.com/yf-networks/conf-agent)) |
| log-reader | [v1.0.0](https://github.com/bfenetworks/log-reader) |

### Changed

- Bump AI Gateway API to v0.0.5 — API endpoint simplification, InstancePool auto-creation, breaking URL path changes (see [upgrade notes](https://github.com/yf-networks/ai-gateway-api/releases/tag/v0.0.5)).
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
| Dashboard | [v0.0.4](https://github.com/yf-networks/ai-gateway-web/releases/tag/v0.0.4) |
| conf-agent | v0.0.4 ([yf-networks](https://github.com/yf-networks/conf-agent)) |

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
| AI Gateway API | [v0.0.3](https://github.com/yf-networks/ai-gateway-api/releases/tag/v0.0.3) |
| Dashboard | v0.0.3 ([ai-gateway-web](https://github.com/yf-networks/ai-gateway-web)) |
| conf-agent | v0.0.3 ([yf-networks](https://github.com/yf-networks/conf-agent)) |
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
