# flink-connector-db2-cdc

## Add Classpath
```java
/opt/flink/lib/conn/db2jcc-db2jcc4.jar
/opt/flink/lib/conn/flink-sql-connector-db2-cdc-3.6.0-2.2.jar
/opt/flink/lib/conn/flink-sql-connector-elasticsearch7-4.0.0-2.0.jar
```

## Compose up Container
```bash
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

## Mock DataChangeEvent
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
![alt text](image.png)

#### DB Current Timestamp
```bash
# 快速验证 DB2 数据库时间戳
docker exec $(docker ps -qf "name=db2") bash -c "su - db2inst1 -c 'db2 connect to testdb && db2 \"VALUES CURRENT TIMESTAMP\"'"
```

DB2 仍然存在时差，因为你设置 TZ=Asia/Shanghai 只影响了容器内 Linux 系统的时区，但 DB2 实例在启动时可能没有正确识别这个变化，或者它仍然使用 UTC 作为默认时区。

```bash
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
```

```bash
## 推荐的一键修复命令（完整版）
docker exec -it $(docker ps -qf "name=db2") bash -c "su - db2inst1 -c 'source ~/.profile 2>/dev/null; db2set DB2_DBTIMEUTC=OFF; db2set -all | grep DBTIMEUTC; db2stop force; db2start; sleep 3; db2 connect to testdb; db2 \"VALUES CURRENT TIMESTAMP\"'"
```

### 3. Enable CDC
```bash
# 检查 ASNCDC 捕获进程是否存在
ps -ef | grep asncdc

# 要查看 PRODUCTS 表（假设它在 DB2INST1 模式下）的 DATA CAPTURE 状态，你可以使用下面这条 SQL。
SELECT TABSCHEMA, TABNAME, DATACAPTURE FROM SYSCAT.TABLES WHERE TABSCHEMA = 'DB2INST1' AND TABNAME = 'PRODUCTS';

SELECT TABSCHEMA, TABNAME, DATACAPTURE FROM SYSCAT.TABLES WHERE DATACAPTURE != 'N';
```

```bash
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


INSERT INTO DB2INST1.PRODUCTS VALUES (default,'jagger','AAA',0.001);
UPDATE DB2INST1.PRODUCTS SET DESCRIPTION='AAAAAA' WHERE NAME='jagger';
DELETE FROM DB2INST1.PRODUCTS WHERE NAME='jagger';
```