# aihot-lzcapp

[AIHOT](https://github.com/KKKKhazix/AIHOT) 的懒猫微服打包：自己找热点、自己写日报的资讯站（看板、事件页、日报、RSS、后台、MCP）。

- **镜像**：上游不发版也不推镜像（compose 里现构建），所以由 [dockers-x/AIHOT](https://github.com/dockers-x/AIHOT) 的定时工作流构建：每 6 小时比对上游 `main`，有变化就构建并推 `ghcr.io/dockers-x/aihot:1.0.<n>`，版本与上游 commit 记在 `upstream.json`。官方商店交付时由 Action 转存到懒猫镜像源。
- **服务结构**：`db`（postgres:17-alpine）+ `app`（一个容器里跑 migrate → seed → api + worker + web）。上游 compose 是 setup/api/worker/web 四个容器，这里合并的原因：
  - 懒猫 `depends_on` 只接受 healthy 依赖，一次性 setup 容器当不了门；
  - `scripts/migrate.ts` 幂等但没有锁，只能有一个容器跑（否则撞 `schema_migrations` 主键）；
  - worker 必须单实例（pg-boss 定时任务与信源调度非并发安全）；
  - api 与 worker 需要共享 `AIHOT_DATA_DIR`，一个容器天然共享。
- **路由**：只有一个入口 `/` → `app:3000`（web）。api(3001) 只在容器内回环，与上游一致（api 无条件信任 `X-Forwarded-For`，靠 web 把它收敛成单个访客地址）。
- **`public_path: [/]`**：这是给人看的公开站点，访客不该先过微服登录；后台 `/admin` 由 `ADMIN_PASSWORD` 把门；RSS、分享图、`llms.txt`、MCP 也要能被站外客户端直接取。
- **环境**：`SITE_URL=https://<应用域名>`（RSS/分享图/MCP/会话 Cookie 都用它）、`TRUST_PROXY=true`（微服入口是反代）、`MCP_ALLOWED_HOSTS` 兜底容器内名字；数据库密码、会话密钥、图片代理签名密钥都由 `stable_secret` 生成；管理员密码与模型参数来自安装向导。
- **持久化**：`/lzcapp/var/db`（数据库）、`/lzcapp/var/data`（上传、图片缓存、本地备份）。
- **截图**：`.github/screenshots/` 三张取自上游仓库 `docs/assets`（MIT），用于官方商店应用信息。

## 已知取舍

- 容器内以 root 运行：镜像里是 `node(1000)`，而 `/lzcapp/var/*` 由平台以 root 创建，用 root 起才能写 `/data`。
- 上游给 worker 配了 210s 停止宽限（付费调用在途时别被砍掉）；懒猫 manifest 没有对应的字段，这里只能依赖应用自身的“结果未知”回执处理。
- `GET /api/mcp` 是 SSE（15s keepalive，带 `X-Accel-Buffering: no`）：微服入口不要缓冲、空闲超时别低于 15s。
