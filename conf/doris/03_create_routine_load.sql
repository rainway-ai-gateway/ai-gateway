CREATE ROUTINE LOAD bfe_ai_log_load ON bfe_ai_request_log
COLUMNS(
    logid, timestamp, log_time = FROM_UNIXTIME(timestamp),
    product, hostid, client_ip, is_trust_src_ip,
    err_code, err_msg, req_header_len, req_body_len,
    proto, header_host, origin_uri, final_uri, method,
    content_type, x_forward_for, accept_language, authorization,
    transfer_encoding, cluster, sub_cluster, backend_info,
    backend_retry, res_status_code, res_header_len,
    res_body_len, res_content_type, all_time,
    read_client_time, cluster_serve_time, backend_serve_time,
    write_client_time, connect_backend_time, proxy_delay_time,
    ai_apikey, ai_apikeytags, ai_requested_model, ai_mapped_model,
    ai_stream, ai_prompt_tokens, ai_output_tokens, ai_total_tokens,
    ai_ttft_us, ai_tpot_us, ai_rate_limit_hits,
    ai_auth_reject_reason, ai_auth_reject_quota_plans
)
PROPERTIES (
    "desired_concurrent_number" = "2",
    "max_batch_interval" = "20",
    "max_batch_rows" = "250000",
    "max_error_number" = "1000",
    "format" = "json"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka.ai-gateway-system:9092",
    "kafka_topic" = "bfe_ai_log",
    "property.group.id" = "doris_bfe_ai_log",
    "property.client.id" = "doris_bfe_ai_log"
);
