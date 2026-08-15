#!/bin/bash
# 自动开启 DB2 CDC 捕获（幂等，可重复执行）
# 用法（容器内执行，脚本内部自行 su 到 db2inst1）：
#   docker exec -it $(docker ps -qf "name=db2") bash /init/init-cdc.sh
#
# 规避的两个坑（重要，勿改回同一 shell 连续执行的方式）：
#   1. ASNCDCSERVICES 是外部 UDF，调用后当前 CLP 会话的连接即失效，
#      同一 shell 里后续 db2 命令（即使重新 connect）全部报
#      SQL1024N A database connection does not exist。
#      —— 对策：每条 SQL 都在独立的 su 登录 shell 中执行，
#         db2 connect + 单条命令一次完成，用完即弃，不依赖连接保持
#         （与 Debezium 官方 setup_db2.sh 的做法一致）
#   2. asncap 启动是异步的（需数秒），start 后立即注册/reinit 会报
#      ASN0506E Capture was not running。
#      —— 对策：就绪判断不依赖 status UDF，直接轮询 asncap 进程
#
# 捕获注册表位于 ASNCDC.IBMSNAP_REGISTER（ASNCDC schema，不是 ASN）

set -u

DBNAME=${1:-testdb}
SCHEMA=DB2INST1
TABLE=PRODUCTS

# 在独立登录 shell 中执行一条 SQL，原样输出结果
run_sql() {
  su - db2inst1 -c "db2 connect to $DBNAME >/dev/null 2>&1; db2 \"$1\"" 2>/dev/null
}

# 同上，但只返回结果值（去掉 CLP 的回车与空白）
getval() {
  su - db2inst1 -c "db2 connect to $DBNAME >/dev/null 2>&1; db2 -x \"$1\"" 2>/dev/null \
    | tr -d '\r' | xargs
}

echo "[1/3] 启动 asncdc 捕获服务..."
run_sql "VALUES ASNCDC.ASNCDCSERVICES('start','asncdc')" | grep -E "ASN[0-9]|SQL[0-9]|running" | head -3

# 轮询 asncap 进程就绪（最多 60 秒），不依赖 status UDF（其调用会断开连接）
echo "  等待 asncap 进程就绪..."
ok=""
for i in $(seq 1 30); do
  if ps -ef | grep -v grep | grep -q asncap; then ok=1; break; fi
  sleep 2
done
if [ -z "$ok" ]; then
  echo "ERROR: asncap 60 秒内未启动。请手动检查："
  echo "  docker exec -it \$(docker ps -qf \"name=db2\") ps -ef | grep asncap"
  exit 1
fi
echo "  asncap 已运行"

echo "[2/3] 注册捕获表 ${SCHEMA}.${TABLE}（已注册则跳过）..."
cnt=$(getval "SELECT COUNT(*) FROM ASNCDC.IBMSNAP_REGISTER WHERE SOURCE_OWNER='${SCHEMA}' AND SOURCE_TABLE='${TABLE}'")
if [ -z "$cnt" ]; then
  echo "ERROR: 查询注册表 ASNCDC.IBMSNAP_REGISTER 失败"
  exit 1
fi
if [ "$cnt" = "0" ]; then
  run_sql "CALL ASNCDC.ADDTABLE('${SCHEMA}', '${TABLE}')" | tail -2
else
  echo "  已注册，跳过"
fi

echo "[3/3] reinit 使注册生效..."
run_sql "VALUES ASNCDC.ASNCDCSERVICES('reinit','asncdc')" | grep -E "ASN[0-9]|SQL[0-9]" | head -3

echo
echo "完成：CDC 捕获已开启，可直接提交 Flink 作业。当前捕获状态："
run_sql "VALUES ASNCDC.ASNCDCSERVICES('status','asncdc')" | tail -4
