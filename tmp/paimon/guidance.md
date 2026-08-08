chmod -R 777 tmp

      - ../tmp/paimon:/tmp/paimon # 持久化 Paimon 数据 warehouse file 挂载 

# LOAP Query
```sql
-- use tableau result mode
SET 'sql-client.execution.result-mode' = 'tableau';

-- switch to batch mode
RESET 'execution.checkpointing.interval';
SET 'execution.runtime-mode' = 'batch';

-- olap query the table
SELECT * FROM word_count;
```

# Streaming Query
```sql
-- switch to streaming mode
SET 'execution.runtime-mode' = 'streaming';

-- track the changes of table and calculate the count interval statistics
SELECT `interval`, COUNT(*) AS interval_cnt FROM
    (SELECT cnt / 10000 AS `interval` FROM word_count) GROUP BY `interval`;
```