# GlassCraft 公共 API v0.1

Base URL: `https://aarongame.com/glasscraft/api`。GET，无需 API key。只读公开数据，跨域 GET 可用。

| 路径 | 参数 | 返回 |
| --- | --- | --- |
| `/health` | 无 | 服务版本与原生构建状态 |
| `/versions` | 无 | Mojang 原始 version_manifest_v2 |
| `/search` | `q` 搜索词，`type=mod/modpack/shader`，可选 `version` | Modrinth 原始 hits，最多 20 项 |
| `/projects/{id}/versions` | 可选 `version` | Modrinth 原始版本数组，含 files 下载链接与哈希 |

例：`curl 'https://aarongame.com/glasscraft/api/search?type=shader&q=Complementary'`

错误为 JSON：400 参数错误、404 路径不存在、405 方法不支持、429 上游限流、502 上游不可用。上游请求 12 秒超时，成功结果缓存 5 分钟。无任意 URL 代理；下载来自 Mojang / Modrinth 返回的源站，下载器应校验哈希。未来可能调整限流，不承诺 SLA。

资源搜索不保证 iOS 兼容性。没有 Java 桌面安装 API、账号密码 API 或浏览器启动游戏 API；Java 安装与游戏启动由 iOS 原生引擎完成。源代码 service/glasscraft-api.mjs 可单独作为 Cloudflare Worker 部署。
