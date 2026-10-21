-- ============================================================================
-- Rainway AI Gateway - 报表库升级脚本：v0.7.x -> v0.8.0（MySQL 形态）
--
-- 适用：已存在 bfe_report 库（bfe_ai_request_log / bfe_ai_metrics_1m）的环境。
-- 新装环境请直接执行 report_db_ddl_mysql.sql，不要执行本文件。
--
-- 内容与 report_db_ddl_mysql.sql 头部注释中的两段迁移一致：
--   1. 2026-09-27 缓存/镜像/意图字段（10 个明细列 + 3 个聚合列）
--   2. 2026-10-13 issue #1417：幂等键补 logid（需重建唯一键）
--
-- 注意：
--   - MySQL 不支持 ADD COLUMN IF NOT EXISTS，脚本非幂等；已执行过的语句
--     重复执行会报 Duplicate column/key，跳过即可。
--   - 先执行第 3 节的 NULL 回填，再执行 MODIFY NOT NULL，否则 MySQL 严格
--     模式会报 Error 1138（Invalid use of NULL value）。
--   - 建议低峰窗口执行；大表场景先用预发库量测耗时，必要时用
--     pt-online-schema-change。
--   - 脚本自带 USE，直接 `mysql < report_db_ddl_mysql_upgrade_to_0.0.11.sql`
--     即可；若报表库不叫 bfe_report，先改下面这行的库名。
-- ============================================================================

USE `bfe_report`;

-- ---------------------------------------------------------------------------
-- 1. 明细表加列
-- ---------------------------------------------------------------------------
ALTER TABLE bfe_ai_request_log
  ADD COLUMN ai_cache_status VARCHAR(16) NOT NULL DEFAULT '' AFTER ai_auth_hit_quota_plans,
  ADD COLUMN mirror_hit TINYINT NOT NULL DEFAULT 0 AFTER ai_cache_status,
  ADD COLUMN mirror_cluster VARCHAR(128) NOT NULL DEFAULT '' AFTER mirror_hit,
  ADD COLUMN ai_intent_question VARCHAR(64) NOT NULL DEFAULT '' AFTER mirror_cluster,
  ADD COLUMN ai_intent_answer VARCHAR(64) NOT NULL DEFAULT '' AFTER ai_intent_question,
  ADD COLUMN ai_intent_confidence DOUBLE DEFAULT NULL AFTER ai_intent_answer,
  ADD COLUMN ai_intent_source VARCHAR(32) NOT NULL DEFAULT '' AFTER ai_intent_confidence,
  ADD COLUMN ai_intent_latency_us BIGINT DEFAULT NULL AFTER ai_intent_source,
  ADD COLUMN ai_intent_cache_hit TINYINT DEFAULT NULL AFTER ai_intent_latency_us,
  ADD COLUMN ai_intent_questions_version VARCHAR(32) NOT NULL DEFAULT '' AFTER ai_intent_cache_hit;

-- ---------------------------------------------------------------------------
-- 2. 聚合表加列
-- ---------------------------------------------------------------------------
ALTER TABLE bfe_ai_metrics_1m
  ADD COLUMN ai_cache_status VARCHAR(16) NOT NULL DEFAULT '' AFTER ai_auth_reject_quota_plans_slot5,
  ADD COLUMN mirror_hit TINYINT NOT NULL DEFAULT 0 AFTER ai_cache_status,
  ADD COLUMN ai_intent_answer VARCHAR(64) NOT NULL DEFAULT '' AFTER mirror_hit;

-- ---------------------------------------------------------------------------
-- 3. 幂等键补 logid（issue #1417）
-- ---------------------------------------------------------------------------
-- 3.1 回填 NULL（先统计，确认后再改）
SELECT COUNT(*) AS null_logid_rows FROM bfe_ai_request_log WHERE logid IS NULL;
UPDATE bfe_ai_request_log SET logid = 0 WHERE logid IS NULL;

-- 3.2 收紧列属性并重建唯一键
ALTER TABLE bfe_ai_request_log
  MODIFY COLUMN logid BIGINT NOT NULL DEFAULT 0,
  DROP KEY uk_dedup,
  ADD UNIQUE KEY uk_dedup (hostid, log_time, ai_apikey_id, ai_requested_model, logid);

-- 回滚（应急）：先删新键、加回四列键，再放宽列属性
-- ALTER TABLE bfe_ai_request_log
--   DROP KEY uk_dedup,
--   ADD UNIQUE KEY uk_dedup (hostid, log_time, ai_apikey_id, ai_requested_model),
--   MODIFY COLUMN logid BIGINT DEFAULT NULL;
