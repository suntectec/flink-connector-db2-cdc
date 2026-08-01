SET sql-client.execution.result-mode=tableau;

CREATE VIEW my_view AS 
SELECT 
    LOCALTIME, 
    LOCALTIMESTAMP, 
    CURRENT_DATE, 
    CURRENT_TIME,
    CURRENT_TIMESTAMP,
    CURRENT_ROW_TIMESTAMP(),
    NOW(),
    PROCTIME();

DESC my_view; 

SET table.local-time-zone = 'Asia/Shanghai';

SELECT * FROM my_view;