-- if you're trying out Paimon in a distributed environment,
-- the warehouse path should be set to a shared file system, such as HDFS or OSS
CREATE CATALOG my_catalog WITH (
    'type'='paimon',
    'warehouse' = 'file:/tmp/paimon'
);

USE CATALOG my_catalog;

-- create a word count table
CREATE TABLE word_count (
    word STRING PRIMARY KEY NOT ENFORCED,
    cnt BIGINT
);

CREATE TABLE my_table (
    word STRING PRIMARY KEY NOT ENFORCED,
    cnt BIGINT
) WITH (
  'snapshot.time-retained' = '1 h',
  'snapshot.num-retained.min' = '2',
  'snapshot.num-retained.max' = '5'
);

-- create a word data generator table
CREATE TEMPORARY TABLE word_table (
    word STRING
) WITH (
    'connector' = 'datagen',
    'fields.word.length' = '1'
);

-- paimon requires checkpoint interval in streaming mode
SET 'execution.checkpointing.interval' = '10 s';

-- write streaming data to dynamic table
INSERT INTO word_count SELECT word, COUNT(*) FROM word_table GROUP BY word;

INSERT INTO my_table SELECT word, COUNT(*) FROM word_table GROUP BY word;