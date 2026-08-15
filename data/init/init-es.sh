#!/bin/bash
# 为 enriched_products_metadata 建立 explicit mapping 的 ES 索引（幂等，可重复执行）。
# 必须在提交 Flink 作业【之前】执行：ES connector 首次写入会 dynamic mapping，
# 把 op_ts/write_time 存成 text，Kibana 时区设置对 text 无效。
#
# 在宿主机（WSL）上执行，不进容器：
#   bash data/init/init-es.sh
#
# op_ts / write_time 为 date 类型（内部存 UTC 毫秒）：
#   - curl 直接看 _source 是 ISO8601 UTC（带 Z 后缀，语义明确）
#   - Kibana 显示北京时间：Stack Management → Kibana → Advanced Settings
#     → Date timezone → Asia/Shanghai
set -u

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX=enriched_products_metadata

# 幂等：索引已存在则跳过（已存在时无法改 mapping，需先 DELETE）
if curl -sf -o /dev/null -I "$ES_HOST/$INDEX"; then
  echo "索引 $INDEX 已存在，跳过（如需重建：curl -X DELETE $ES_HOST/$INDEX 后重跑本脚本）"
  exit 0
fi

# date 字段格式说明（Flink ES connector 对 TIMESTAMP_LTZ 的序列化是空格分隔，非 ISO 的 'T'，
# 且 snapshot 阶段 op_ts 默认值 "1970-01-01 00:00:00Z" 无毫秒；注意：时区占位符必须用 X 而非 Z，
# Joda 的 Z 只解析 "+0000" 数字偏移，不认字面量 "Z"，X 才能匹配 "Z" 后缀）：
#   yyyy-MM-dd HH:mm:ss.SSSX   增量阶段（带毫秒）
#   yyyy-MM-dd HH:mm:ssX       snapshot 阶段（无毫秒）
#   strict_date_optional_time  标准 ISO8601（T 分隔），兼容外部写入
#   epoch_millis               毫秒时间戳
curl -sf -X PUT "$ES_HOST/$INDEX" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "ID":            {"type": "long"},
      "NAME":          {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
      "DESCRIPTION":   {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
      "WEIGHT":        {"type": "double"},
      "database_name": {"type": "keyword"},
      "table_name":    {"type": "keyword"},
      "schema_name":   {"type": "keyword"},
      "op_ts":         {"type": "date", "format": "yyyy-MM-dd HH:mm:ss.SSSX||yyyy-MM-dd HH:mm:ssX||strict_date_optional_time||epoch_millis"},
      "write_time":    {"type": "date", "format": "yyyy-MM-dd HH:mm:ss.SSSX||yyyy-MM-dd HH:mm:ssX||strict_date_optional_time||epoch_millis"}
    }
  }
}' && echo "索引 $INDEX 已创建（op_ts/write_time 为 date 类型）" || {
  echo "ERROR: 创建索引失败，请确认 ES 可达：$ES_HOST"
  exit 1
}
