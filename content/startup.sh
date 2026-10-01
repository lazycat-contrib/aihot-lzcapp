#!/usr/bin/env bash
# 一个容器跑三个角色（上游 docker-compose 里是 setup/api/worker/web 四个容器）。
#
# 为什么合成一个：
#   - 懒猫的 depends_on 只接受 healthy 依赖，一次性 setup 容器没法给 api/worker 当门；
#   - scripts/migrate.ts 幂等但没有锁，两个容器同时跑会撞 schema_migrations 主键，所以只能跑一次；
#   - worker 必须单实例（pg-boss 的定时任务与信源调度不是并发安全的）；
#   - api 与 worker 需要共享 AIHOT_DATA_DIR（上传、图片缓存、本地备份）。
# 一个容器天然满足以上四条：迁移只跑一次、worker 只有一个、/data 天然共享。
set -euo pipefail

node scripts/migrate.ts
node scripts/seed.ts

pids=()
node apps/api/src/main.ts & pids+=($!)
node apps/worker/src/main.ts & pids+=($!)
node apps/web/server.ts & pids+=($!)

shutdown() {
  kill "${pids[@]}" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

# 任一进程退出（崩溃）就收掉其余进程、让容器退出，交给平台重启整组
wait -n || true
kill "${pids[@]}" 2>/dev/null || true
wait 2>/dev/null || true
exit 1
