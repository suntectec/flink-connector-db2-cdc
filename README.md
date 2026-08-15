# flink-connector-db2-cdc

基于 Docker Compose 的 DB2 CDC 演示：Flink SQL 将 DB2 变更数据同步到 Elasticsearch，另附 Datagen → Paimon 示例。

## 架构

```
DB2 (ASNCDC) ──> Flink SQL (db2-cdc) ──> Elasticsearch 7 / Kibana
Datagen      ──> Flink SQL ──> Paimon (file:/tmp/paimon)
```

## 目录结构

```
data/               DB2 + Elasticsearch + Kibana
  init/init-db.sql  建 PRODUCTS 表 + 种子数据（幂等）
  init/init-cdc.sh  开启 CDC 捕获（幂等）
  init/init-es.sh   建 ES 索引 explicit mapping（幂等）
compute/            Flink 2.3 集群（jobmanager / taskmanager / sql-client）
scripts/            Flink SQL 作业脚本
jars/               依赖 jar（见 jars/README.md，需自行下载放入）
docs/               补充文档
tmp/paimon/         Paimon warehouse（git 忽略）
```

## 前置条件

1. Docker & Docker Compose v2
2. 下载依赖 jar 到 `jars/`（须与镜像 `flink:2.3.0` 匹配，详见 `jars/README.md`）：

```
db2jcc-db2jcc4.jar
flink-shaded-hadoop-2-uber-2.8.3-10.0.jar
flink-sql-connector-db2-cdc-3.6.0-2.2.jar
flink-sql-connector-elasticsearch7-4.0.0-2.0.jar
paimon-flink-2.2-2.0.0.jar
```

## 快速开始

> 除第 1 步外，2–4 步均需手动执行，compose 不会自动调用。

### 1. 启动环境

```bash
docker compose -f data/docker-compose.yml up -d
docker compose -f compute/docker-compose.yml up -d
docker logs -f data-db2-1    # 等 DB2 就绪，约 2–3 分钟
```

两个 compose 通过共享网络 `data_default` 互通。DB2 时区已通过挂载宿主机
`/etc/localtime`、`/etc/timezone` 自动初始化为 Asia/Shanghai，无需手动修正
（验证：`docker exec $(docker ps -qf "name=db2") env -u TZ date`）。

### 2. 初始化 DB2

```bash
# 建表 + 种子数据
docker exec -it $(docker ps -qf "name=db2") bash -c \
  "su - db2inst1 -c 'db2 connect to testdb && db2 -tf /init/init-db.sql'"

# 开启 CDC 捕获（脚本内部已处理 su 及独立 shell 执行）
docker exec -it $(docker ps -qf "name=db2") bash /init/init-cdc.sh
```

### 3. 建立 ES 索引

```bash
bash data/init/init-es.sh
```

> **必须在提交 Flink 作业之前执行**：作业首次写入会触发 dynamic mapping，
> 把 `op_ts`/`write_time` 存成 `text`，Kibana 时区设置对 `text` 无效。

### 4. 提交 Flink 作业

```bash
docker compose -f compute/docker-compose.yml run --rm sql-client ./bin/sql-client.sh -f scripts/db2_2_es.sql           # 纯 CDC 流
docker compose -f compute/docker-compose.yml run --rm sql-client ./bin/sql-client.sh -f scripts/db2_2_es_metadata.sql  # 含 CDC 元数据列
docker compose -f compute/docker-compose.yml run --rm sql-client ./bin/sql-client.sh -f scripts/datagen_2_paimon.sql   # Datagen -> Paimon
```

## 验证 CDC

进入 DB2 命令行制造变更：

```bash
docker exec -it $(docker ps -qf "name=db2") bash -c \
  "su - db2inst1 -c 'db2 connect to testdb && db2'"
```

```sql
INSERT INTO DB2INST1.PRODUCTS VALUES (default,'jagger','dd',0.001);
UPDATE DB2INST1.PRODUCTS SET DESCRIPTION='bb' WHERE NAME='jagger';
DELETE FROM DB2INST1.PRODUCTS WHERE NAME='jagger';
```

在 Kibana（http://localhost:5601）查看 `enriched_products` / `enriched_products_metadata` 索引。

### 时间字段说明

- `_source` 中 `op_ts`/`write_time` 为 ISO8601 **UTC**（带 `Z` 后缀），+8 即北京时间
- Kibana 显示北京时间：**Stack Management → Advanced Settings → Date timezone → Asia/Shanghai**
- snapshot 阶段 `op_ts` 为 `1970-01-01 00:00:00Z` 是 Debezium 默认值；增量阶段为真实变更时间

### CDC 状态检查（可选）

```sql
VALUES ASNCDC.ASNCDCSERVICES('status','asncdc');  -- 应返回 Running
SELECT SOURCE_OWNER, SOURCE_TABLE FROM ASNCDC.IBMSNAP_REGISTER WHERE SOURCE_TABLE = 'PRODUCTS';
```

异常时手动恢复：

```sql
VALUES ASNCDC.ASNCDCSERVICES('start','asncdc');
CALL ASNCDC.ADDTABLE('DB2INST1', 'PRODUCTS');
VALUES ASNCDC.ASNCDCSERVICES('reinit','asncdc');
```

## 彻底重置

`down` 不加 `-v` 会保留 `db2-data` 卷，ASNCDC 变更日志（CDL）持续累积，
重提作业时初始同步会多于表当前行数。干净重来：

```bash
docker compose -f data/docker-compose.yml down -v && docker compose -f data/docker-compose.yml up -d
```

DB2 就绪后，按「快速开始」2 → 3 → 4 依次执行。初始同步应正好 9 条。

## 重建 ES 索引（mapping 变更时）

```bash
curl -X DELETE http://localhost:9200/enriched_products_metadata
bash data/init/init-es.sh
```

然后到 Flink Web UI（http://localhost:8081）取消旧作业，重新提交（见「快速开始」第 4 步）。

## Paimon 查询

见 [docs/paimon-queries.md](docs/paimon-queries.md)。
