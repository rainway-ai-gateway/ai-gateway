-- ============================================================================
-- Rainway AI Gateway - 报表库升级脚本：v0.0.11 -> v0.1.0（MySQL 形态）
--
-- 适用：已存在 bfe_report 库（v0.8.0.0 时代的 99 列明细表）的环境。
-- 新装环境请直接执行 report_db_ddl_mysql.sql（101 列），不要执行本文件。
--
-- 本版变更（与 report_db_ddl_mysql.sql 头部注释中的迁移段一致）：
--   1. 明细表新增缺价信号两列（2026-10-30 issue #1479，bfe-access-pb v0.3.17
--      字段 763/766）：ai_price_miss / ai_price_warn。两列可空且无默认值——
--      NULL = 该行未发生缺价（bfe 缺价时才写出）；ai_price_miss 在非 2xx 的
--      reject 行也会出现（bfe 写出时机为请求级）。
--
-- 注意：
--   - MySQL 不支持 ADD COLUMN IF NOT EXISTS，脚本非幂等；已执行过的语句
--     重复执行会报 Duplicate column，跳过即可。
--   - bfe_ai_metrics_1m 的 TTFT/TPOT 流式口径（issue #315）由 ai-gateway-api
--     v0.1.0 的分钟聚合 JOB 在代码侧收敛（仅 ai_stream=1 行贡献），
--     聚合表结构无变化，本脚本无需处理。
--   - 脚本自带 USE，直接 `mysql < report_db_ddl_mysql_upgrade_to_0.1.0.sql`
--     即可；若报表库不叫 bfe_report，先改下面这行的库名。
-- ============================================================================

USE `bfe_report`;

-- ---------------------------------------------------------------------------
-- 1. 明细表加列（缺价信号，issue #1479）
-- ---------------------------------------------------------------------------
ALTER TABLE bfe_ai_request_log
  ADD COLUMN ai_price_miss TINYINT DEFAULT NULL AFTER ai_intent_questions_version,
  ADD COLUMN ai_price_warn VARCHAR(32) DEFAULT NULL AFTER ai_price_miss;

-- 回滚（应急）：
-- ALTER TABLE bfe_ai_request_log
--   DROP COLUMN ai_price_warn,
--   DROP COLUMN ai_price_miss;
