SET execution.checkpointing.interval = 3s;

CREATE TABLE products (
    ID INT NOT NULL,
    NAME STRING,
    DESCRIPTION STRING,
    WEIGHT DECIMAL(10,3),
    PRIMARY KEY (ID) NOT ENFORCED
  ) WITH (
    'connector' = 'db2-cdc',
    'hostname' = 'db2',
    'port' = '50000',
    'username' = 'db2inst1',
    'password' = 'admin',
    'database-name' = 'TESTDB',
    'table-name' = 'DB2INST1.PRODUCTS'
  );
  
CREATE TABLE es_products (
    ID INT NOT NULL,
    NAME STRING,
    DESCRIPTION STRING,
    WEIGHT DECIMAL(10,3),
    PRIMARY KEY (ID) NOT ENFORCED
 ) WITH (
     'connector' = 'elasticsearch-7',
     'hosts' = 'http://elasticsearch:9200',
     'index' = 'enriched_products'
 );

INSERT INTO es_products SELECT * FROM products;