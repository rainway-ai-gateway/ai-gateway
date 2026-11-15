-- ===========================================================================
-- ai-gateway-api 数据库升级脚本：v0.0.11 -> v0.1.0（MySQL 8+）
--
-- 适用：由 v0.0.11（产品 v0.8.0.0）升级到 v0.1.0（产品 v0.9.0.0）的存量库。
-- 新装库请直接执行 api_db_ddl_mysql.sql（含全部表与种子数据）。
--
-- 本版变更（相对 v0.0.11 母版 db_ddl.sql 的唯一差异）：
--   1. providers 表删除 k8s_instance_pool 列（K8s 实例池只读镜像）。
--      api v0.1.0 不再读写该列：K8s 池的镜像数据由独立的 k8s_pools 资源维护，
--      provider 只保留 instance_source + k8s_pool_name 两个引用键。
--
-- ⚠️ 首次破例说明：升级脚本历来声明「不包含任何 DROP」，本版起出现唯一一处
--    DROP COLUMN。该列在 v0.0.11 中是只读镜像（系统从 /k8s_pools 同步写入，
--      无人工数据），删除不丢业务数据；执行前仍请按第 1 节的建议先备份。
--
-- 使用说明：
--   1. 升级前务必备份数据库。
--   2. MySQL 不支持 DROP COLUMN IF NOT EXISTS，脚本非幂等：列已不存在时
--      重复执行会报 Error 1091（Unknown column），跳过即可。
--   3. 脚本自带 USE，直接 `mysql < api_db_ddl_mysql_upgrade_to_0.1.0.sql`
--      即可；若你的控制面库不叫 open_bfe，先改下面这行的库名。
-- ===========================================================================

USE `open_bfe`;

-- ---------------------------------------------------------------------------
-- 1. providers：删除 K8s 实例池只读镜像列
-- ---------------------------------------------------------------------------
-- 1.1 先确认列存在（返回 1 才需要执行 1.2）
SELECT COUNT(*) AS k8s_instance_pool_exists
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'open_bfe'
  AND TABLE_NAME = 'providers'
  AND COLUMN_NAME = 'k8s_instance_pool';

-- 1.2 删除该列（只读镜像列，无业务数据；ALGORITHM=INPLACE 即可，无需 COPY）
ALTER TABLE `providers`
  DROP COLUMN `k8s_instance_pool`;

-- 回滚（应急）：按 v0.0.11 定义加回（镜像数据不会恢复，由 /k8s_pools 重新同步）
-- ALTER TABLE `providers`
--   ADD COLUMN `k8s_instance_pool` JSON NULL COMMENT 'K8s 实例池只读镜像（系统从 /k8s_pools 同步）'
--   AFTER `k8s_pool_name`;
