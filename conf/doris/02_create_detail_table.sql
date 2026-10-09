USE bfe_observability;

CREATE TABLE bfe_ai_request_log (
    hostid                  VARCHAR(256)    COMMENT '主机标识，格式 hostname_netns',
    log_time                DATETIME        COMMENT '日志产生时间',
    ai_apikey_id            VARCHAR(256)    COMMENT 'API Key ID',
    ai_requested_model      VARCHAR(128)    COMMENT '请求模型名',

    logid                   BIGINT          COMMENT 'BFE 请求唯一标识',
    product                 VARCHAR(64)     COMMENT '产品标识',
    log_tag                 VARCHAR(64)     COMMENT '日志标签：req_<product> / req_err_<product>',

    -- 客户端连接
    client_ip               VARCHAR(64)     COMMENT '客户端 IP',
    client_network          VARCHAR(16)     COMMENT '客户端网络类型：Ipv4/Ipv6',
    is_trust_src_ip         TINYINT         COMMENT '是否可信源 IP',
    req_num                 INT             COMMENT '会话内请求序号（从 1 开始）',
    session_id              BIGINT          COMMENT '会话 ID',
    bfe_ip                  VARCHAR(64)     COMMENT 'BFE 服务器 IP',
    sock_src_ip             VARCHAR(64)     COMMENT 'Socket 源 IP',
    vip                     VARCHAR(64)     COMMENT '目的 VIP',
    vip6                    VARCHAR(128)    COMMENT '目的 VIP6',

    -- 错误信息
    err_code                VARCHAR(64)     COMMENT '错误码',
    err_msg                 VARCHAR(512)    COMMENT '错误详情',

    -- 请求头
    proto                   VARCHAR(16)     COMMENT 'HTTP 协议版本',
    header_host             VARCHAR(256)    COMMENT '请求 Host',
    origin_uri              VARCHAR(2048)   COMMENT '原始请求 URI',
    final_uri               VARCHAR(2048)   COMMENT '最终路由 URI',
    method                  VARCHAR(16)     COMMENT 'HTTP 方法',
    content_type            VARCHAR(128)    COMMENT '请求 Content-Type',
    x_forward_for           VARCHAR(1024)   COMMENT 'X-Forwarded-For',
    accept_language         VARCHAR(256)    COMMENT 'Accept-Language',
    authorization           VARCHAR(1024)   COMMENT 'Authorization 头',
    transfer_encoding       VARCHAR(64)     COMMENT 'Transfer-Encoding',
    referrer                VARCHAR(2048)   COMMENT 'Referer 头',
    user_agent              VARCHAR(1024)   COMMENT 'User-Agent 头',
    delegation              VARCHAR(256)    COMMENT '委托域名',
    uid                     VARCHAR(256)    COMMENT 'UID 头',
    cookie                  VARCHAR(4096)   COMMENT 'Cookie 头',
    req_headers             ARRAY<STRUCT<
        `key`   : VARCHAR(128),
        value   : VARCHAR(2048)
    >>                                      COMMENT '请求头列表',
    req_header_len          INT             COMMENT '请求头长度（字节）',
    req_body_len            INT             COMMENT '请求体长度（字节）',

    -- 路由
    cluster                 VARCHAR(256)    COMMENT '目标集群',
    sub_cluster             VARCHAR(256)    COMMENT '目标子集群',
    backend_info            VARCHAR(256)    COMMENT '后端 IP:Port',
    backend_retry           TINYINT         COMMENT '后端重试次数',

    -- 响应
    res_status_code         SMALLINT        COMMENT '响应状态码',
    res_header_len          INT             COMMENT '响应头长度（字节）',
    res_body_len            INT             COMMENT '响应体长度（字节）',
    res_content_type        VARCHAR(128)    COMMENT '响应 Content-Type',
    res_location            VARCHAR(2048)   COMMENT '响应 Location（3xx）',
    res_transfer_encoding   VARCHAR(64)     COMMENT '响应 Transfer-Encoding',
    res_headers             ARRAY<STRUCT<
        `key`   : VARCHAR(128),
        value   : VARCHAR(2048)
    >>                                      COMMENT '响应头列表',

    -- 耗时（毫秒）
    all_time                INT             COMMENT '请求总耗时',
    read_client_time        INT             COMMENT '读客户端耗时',
    cluster_serve_time      INT             COMMENT '集群层耗时',
    backend_serve_time      INT             COMMENT '后端耗时',
    write_client_time       INT             COMMENT '写客户端耗时',
    connect_backend_time    INT             COMMENT '连接后端耗时',
    proxy_delay_time        INT             COMMENT '代理延迟',
    session_offset_time     INT             COMMENT '会话内时间偏移（毫秒）',

    -- AI 可观测 — API Key 标签（按层级打平，v1.1）
    level1Name              VARCHAR(128)    COMMENT 'Level1 标签名',
    level1                  VARCHAR(128)    COMMENT 'Level1 标签值',
    level2Name              VARCHAR(128)    COMMENT 'Level2 标签名',
    level2                  VARCHAR(128)    COMMENT 'Level2 标签值',
    level3Name              VARCHAR(128)    COMMENT 'Level3 标签名',
    level3                  VARCHAR(128)    COMMENT 'Level3 标签值',
    level4Name              VARCHAR(128)    COMMENT 'Level4 标签名',
    level4                  VARCHAR(128)    COMMENT 'Level4 标签值',
    level5Name              VARCHAR(128)    COMMENT 'Level5 标签名',
    level5                  VARCHAR(128)    COMMENT 'Level5 标签值',

    -- AI 可观测 (v0.2.0)
    ai_target_model         VARCHAR(128)    COMMENT '实际路由模型名',
    ai_stream               TINYINT         COMMENT '是否流式：0=非流式, 1=流式',
    ai_input_tokens         BIGINT          COMMENT '输入 Token 数',
    ai_output_tokens        BIGINT          COMMENT '输出 Token 数',
    ai_total_tokens         BIGINT          COMMENT '总 Token 数',
    ai_cache_read_tokens    BIGINT          COMMENT '缓存读取 Token 数',
    ai_cache_write_tokens   BIGINT          COMMENT '缓存写入 Token 数',
    ai_audio_input_tokens   BIGINT          COMMENT '音频输入 Token 数',
    ai_audio_output_tokens  BIGINT          COMMENT '音频输出 Token 数',
    ai_image_count          BIGINT          COMMENT '图片数量',
    ai_ttft_us              BIGINT          COMMENT '首 Token 延迟 TTFT（微秒）',
    ai_tpot_us              BIGINT          COMMENT '每 Token 延迟 TPOT（微秒）',
    ai_provider             VARCHAR(64)     COMMENT '上游模型提供商',
    ai_protocol             VARCHAR(64)     COMMENT 'AI 协议',
    ai_mode                 VARCHAR(64)     COMMENT 'AI 模式',
    ai_retry_count          INT             COMMENT '模型调用层重试次数',
    ai_cost_value           BIGINT          COMMENT '成本固定点整数值',
    ai_cost_currency        VARCHAR(16)     COMMENT '成本币种',
    ai_route_rule_hits      ARRAY<STRUCT<
        rule_owner       : VARCHAR(128),
        rule_owner_type  : VARCHAR(64),
        rule_name        : VARCHAR(128)
    >>                                      COMMENT 'AI 路由规则命中记录',
    ai_cluster_key_names    ARRAY<STRUCT<
        cluster_name : VARCHAR(128),
        key_name     : VARCHAR(128)
    >>                                      COMMENT '尝试过的集群与 Key 名称组合',
    ai_rate_limit_hits      ARRAY<STRUCT<
        rate_limit_policy_id : VARCHAR(128),
        rate_limit_type      : VARCHAR(32),
        rule_names           : ARRAY<VARCHAR(128)>
    >>                                      COMMENT '限流命中列表',
    ai_auth_reject_reason   VARCHAR(256)    COMMENT '认证拒绝原因',
    ai_auth_reject_quota_plans ARRAY<VARCHAR(128)> COMMENT '被拒绝的配额计划',
    ai_auth_hit_quota_plans ARRAY<VARCHAR(128)> COMMENT '成功请求时命中的配额计划'
)
UNIQUE KEY(hostid, log_time, ai_apikey_id, ai_requested_model)
PARTITION BY RANGE(log_time) (
    PARTITION p_init VALUES LESS THAN ('2026-08-29')
)
DISTRIBUTED BY HASH(ai_apikey_id) BUCKETS 32
PROPERTIES (
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "32",
    "compression" = "zstd"
);