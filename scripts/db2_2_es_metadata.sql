SET execution.checkpointing.interval = 3s;
SET 'table.local-time-zone' = 'Asia/Shanghai';

CREATE TABLE products (
    -- 业务数据列
    ID INT NOT NULL,
    NAME STRING,
    DESCRIPTION STRING,
    WEIGHT DECIMAL(10,3),
    -- CDC 元数据列 (只读虚拟列)
    database_name STRING NOT NULL METADATA FROM 'database_name' VIRTUAL,
    table_name STRING NOT NULL METADATA FROM 'table_name' VIRTUAL,
    schema_name STRING NOT NULL METADATA FROM 'schema_name' VIRTUAL,
    op_ts TIMESTAMP_LTZ(3) NOT NULL METADATA FROM 'op_ts' VIRTUAL,
    PRIMARY KEY (ID) NOT ENFORCED
  ) WITH (
    'connector' = 'db2-cdc',
    'hostname' = 'db2',
    'port' = '50000',
    'username' = 'db2inst1',
    'password' = 'admin',
    'database-name' = 'TESTDB',
    'table-name' = 'DB2INST1.PRODUCTS',
    'server-time-zone' = 'Asia/Shanghai'
  );
  
CREATE TABLE es_products_metadata (
    -- 业务数据列
    ID INT NOT NULL,
    NAME STRING,
    DESCRIPTION STRING,
    WEIGHT DECIMAL(10,3),
    -- 元数据字段
    database_name STRING,
    table_name STRING,
    schema_name STRING,
    -- 保持 TIMESTAMP_LTZ 直写：ES connector 序列化为标准 ISO8601 UTC（...Z）。
    -- 索引需先用 data/init/init-es.sh 建立 explicit mapping（date 类型），
    -- 否则 dynamic mapping 会存成 text，Kibana 时区设置对 text 无效。
    -- Kibana 显示：Advanced Settings → Date timezone → Asia/Shanghai
    op_ts TIMESTAMP_LTZ(3),
    write_time TIMESTAMP_LTZ(3),
    PRIMARY KEY (ID) NOT ENFORCED
 ) WITH (
     'connector' = 'elasticsearch-7',
     'hosts' = 'http://elasticsearch:9200',
     'index' = 'enriched_products_metadata'
 );

INSERT INTO es_products_metadata SELECT *, CURRENT_TIMESTAMP AS write_time FROM products;