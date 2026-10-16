# aihot-lzcapp

[AIHOT](https://github.com/KKKKhazix/AIHOT) 的懒猫微服打包：自己找热点、自己写日报的资讯站（看板、事件页、日报、RSS、后台、MCP）。

- **镜像**：由 [dockers-x/AIHOT](https://github.com/dockers-x/AIHOT) 的轻量构建仓库自动拉取并锁定上游 `main`：每 6 小时检查更新，构建并同时推送 `ghcr.io/dockers-x/aihot:1.0.<n>` 与 `latest`，版本与上游 commit 记在 `upstream.json`。本 LPK 的发布 Action 按不可变版本标签追踪升级，并在官方商店交付时转存到懒猫镜像源。
- **服务结构**：`db`（postgres:17-alpine）+ `app`（一个容器里跑 migrate → seed → api + worker + web）。上游 compose 是 setup/api/worker/web 四个容器，这里合并的原因：
  - 懒猫 `depends_on` 只接受 healthy 依赖，一次性 setup 容器当不了门；
  - `scripts/migrate.ts` 幂等但没有锁，只能有一个容器跑（否则撞 `schema_migrations` 主键）；
  - worker 必须单实例（pg-boss 定时任务与信源调度非并发安全）；
  - api 与 worker 需要共享 `AIHOT_DATA_DIR`，一个容器天然共享。
- **路由与入口**：`/` → `site:3000`（web），另提供启动器“管理后台”入口直达 `/admin`。api(3001) 只在容器内回环，与上游一致。管理登录页通过 `simple-inject-password` 自动填充安装时生成的管理员密码，但不会自动提交。
- **`public_path: [/]`**：这是给人看的公开站点，访客不该先过微服登录；后台 `/admin` 由 `ADMIN_PASSWORD` 把门；RSS、分享图、`llms.txt`、MCP 也要能被站外客户端直接取。
- **环境**：`SITE_URL=https://<应用域名>`（RSS/分享图/MCP/会话 Cookie 都用它）、`TRUST_PROXY=true`（微服入口是反代）、`MCP_ALLOWED_HOSTS` 兜底容器内名字；数据库密码、会话密钥、图片代理签名密钥由 `stable_secret` 生成；管理员密码由安装向导自动生成至少 20 位随机值；新版上游默认关闭的 `COLLECT_ENABLED`、`MODEL_CALLS_ENABLED` 在 LPK 中显式开启。
- **持久化**：`/lzcapp/var/db`（数据库）、`/lzcapp/var/data`（上传、图片缓存、本地备份）。
- **截图**：`.github/screenshots/` 三张取自上游仓库 `docs/assets`（MIT），用于官方商店应用信息。

## 模型接口配置与排障

`LLM_BASE_URL` 必须是 **AIHOT 的 `site` 容器能够直接连接的 OpenAI-compatible 后端 API**，通常以 `/v1` 结尾。

正确示例：

```text
https://api.deepseek.com/v1
https://dashscope.aliyuncs.com/compatible-mode/v1
https://你的模型网关后端地址/v1
```

不要填写需要先登录懒猫微服的网页入口，例如：

```text
https://tokenhub.example.heiyu.space/v1
```

这类 `*.heiyu.space` 地址可能在浏览器中可打开，但会跳转到懒猫登录页，或者只解析到应用内部网络地址；AIHOT 后端容器不一定能直接访问。使用同一台懒猫微服上的 TokenHub 或其他模型网关时，请填写该应用提供的**专用后端 API 地址**，而不是网页入口。

如果模型接口不可达，通常会出现以下连锁现象：

1. 信源已经抓到文章，但文章一直停在 `processing_state=new`；
2. `analyses` 和 `publications` 数量为 0；
3. 日报任务每半小时重试，并报告：

   ```text
   daily YYYY-MM-DD: nothing judged in its window
   ```

这个错误表示日报时间窗口内没有任何完成模型判定的内容，通常不是数据库初始化或 `/admin` 登录失败。应优先检查模型地址、API Key、模型 ID，以及容器到模型接口的网络连通性。

## 已知取舍

- 容器内以 root 运行：镜像里是 `node(1000)`，而 `/lzcapp/var/*` 由平台以 root 创建，用 root 起才能写 `/data`。
- 上游给 worker 配了 210s 停止宽限（付费调用在途时别被砍掉）；懒猫 manifest 没有对应的字段，这里只能依赖应用自身的“结果未知”回执处理。
- `GET /api/mcp` 是 SSE（15s keepalive，带 `X-Accel-Buffering: no`）：微服入口不要缓冲、空闲超时别低于 15s。
