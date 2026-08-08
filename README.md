# flink-connector-db2-cdc

## Add Classpath
```java
/opt/flink/lib/conn/db2jcc-db2jcc4.jar
/opt/flink/lib/conn/flink-sql-connector-db2-cdc-3.6.0-2.2.jar
/opt/flink/lib/conn/flink-sql-connector-elasticsearch7-4.0.0-2.0.jar
```

## Compose up Container
```bash
docker compose -f data/docker-compose.yml up -d
docker compose -f compute/docker-compose.yml up -d

# Wait for DB2 to be fully ready (may take 2–3 minutes). Verify DB2 initialization completes.
docker logs -f data-db2-1
```

## Submit Job
```bash
# 新建一个容器来执行命令提交，更干净，不干扰现有容器交互
docker compose run sql-client ./bin/sql-client.sh -f scripts/db2_2_es.sql

# 在已经运行的容器中执行命令提交，适合调试、维护
# docker compose exec sql-client ./bin/sql-client.sh -f scripts/db2_2_es.sql
```

## Mock DataChangeEvent - Pure CDC Stream
### 1. Enter DB2 Client
```bash
# docker exec -it ${containerId} /bin/bash
docker exec -it $(docker ps -qf "name=db2") /bin/bash

su db2inst1

db2 connect to testdb

# enter db2 and execute sqls
db2
```

### 2. Check Container and DB Current Timestamp Lag
#### Container Current Timestamp
```bash
docker exec -it $(docker ps -qf "name=db2") date
```
e.g.
```
suntectec@CoffeeCat:~/myspace/flink-connector-db2-cdc/data$ docker exec -it $(docker ps -qf "name=db2") date
Sat Aug  1 04:14:43 CST 2026
```

#### DB Current Timestamp
```bash
# 快速验证 DB2 数据库时间戳
docker exec $(docker ps -qf "name=db2") bash -c "su - db2inst1 -c 'db2 connect to testdb && db2 \"VALUES CURRENT TIMESTAMP\"'"

# 若 DB2 仍然存在时差，因为你设置 TZ=Asia/Shanghai 只影响了容器内 Linux 系统的时区，但 DB2 实例在启动时可能没有正确识别这个变化，或者它仍然使用 UTC 作为默认时区。

# 进入 DB2 交互式命令行（db2 客户端）
docker exec -it $(docker ps -qf "name=db2") bash -c "su - db2inst1 -c 'db2 connect to testdb && db2'"

VALUES CURRENT TIMESTAMP

# 设置数据库时区（需要更新数据库配置）
UPDATE DATABASE CONFIGURATION USING DBTIMEUTC OFF

# 重启数据库使配置生效
db2stop force

db2start

# 重新连接验证
connect to testdb
VALUES CURRENT TIMESTAMP

# 一键设置脚本
docker exec -it $(docker ps -qf "name=db2") bash -c "ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo 'Asia/Shanghai' > /etc/timezone && su - db2inst1 -c 'db2set DB2_DBTIMEUTC=OFF && db2stop force && db2start'"
```

### 3. Enable CDC
```bash
# 检查 ASNCDC 捕获进程是否存在
docker exec -it data-db2-1 bash -c "ps -ef | grep asncdc"

# 进入 DB2 交互式命令行（db2 客户端）
docker exec -it $(docker ps -qf "name=db2") bash -c "su - db2inst1 -c 'db2 connect to testdb && db2'"

# 要查看 PRODUCTS 表（假设它在 DB2INST1 模式下）的 DATA CAPTURE 状态，你可以使用下面这条 SQL。
SELECT TABSCHEMA, TABNAME, DATACAPTURE FROM SYSCAT.TABLES WHERE TABSCHEMA = 'DB2INST1' AND TABNAME = 'PRODUCTS';

SELECT TABSCHEMA, TABNAME, DATACAPTURE FROM SYSCAT.TABLES WHERE DATACAPTURE != 'N';
```

```bash
# check ASNCDC status
VALUES ASNCDC.ASNCDCSERVICES('status','asncdc');

# 开启 ASNCDC
VALUES ASNCDC.ASNCDCSERVICES('start','asncdc');

CALL ASNCDC.ADDTABLE('DB2INST1', 'PRODUCTS');

VALUES ASNCDC.ASNCDCSERVICES('reinit','asncdc');
```

### 4. Mock Source Data Change - Full and Incremental Sync
```bash
# 进入 DB2 交互式命令行（db2 客户端）
docker exec -it $(docker ps -qf "name=db2") bash -c "su - db2inst1 -c 'db2 connect to testdb && db2'"
```

```sql
UPDATE DB2INST1.PRODUCTS SET DESCRIPTION='18oz carpenter hammer' WHERE ID=106;

INSERT INTO DB2INST1.PRODUCTS VALUES (default,'jacket','water resistent white wind breaker',0.2);

INSERT INTO DB2INST1.PRODUCTS VALUES (default,'scooter','Big 2-wheel scooter ',5.18);

DELETE FROM DB2INST1.PRODUCTS WHERE ID=111;


INSERT INTO DB2INST1.PRODUCTS VALUES (default,'jagger','dd',0.001);
UPDATE DB2INST1.PRODUCTS SET DESCRIPTION='bb' WHERE NAME='jagger';
DELETE FROM DB2INST1.PRODUCTS WHERE NAME='jagger';
```


## Add Available Metadata
## Submit Job
```bash
# 新建一个 sql-client 容器来执行命令提交，更干净，不干扰现有容器交互
docker compose run sql-client ./bin/sql-client.sh -f scripts/db2_2_es_metadata.sql
```

```bash
docker compose run sql-client ./bin/sql-client.sh -f scripts/datagen_2_paimon.sql
```