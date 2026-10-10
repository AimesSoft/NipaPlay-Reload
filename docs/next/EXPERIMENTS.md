# 实验记录

每条记录：日期、假设、做了什么、观察到什么（包括意外和失败）、因此改了什么。v1 时期的真机验收记录见 `archive/v1/ACCEPTANCE_LOG.md`。

---

## 2026-10-11 · X3：用户拥有的 harness

假设：普通用户仓库、外置连接凭据和一个标准库 CLI，足以让 Agent 操作现有 Harness；事件程序可以复用同一任务与回执系统。

从种子创建临时 git 仓库，在生产回环端点与 SQLite 任务系统上用 macOS Python 3.9.6 运行 `./nipa status/list/call/watch`。写入实际 24 字节文件；删除仅预览，文件仍在。下载成功事件运行可执行 hook，回执退出码 0、耗时 376 ms，cookie 输出脱敏。改写用户 AGENTS 后重开，45 个条目的内容、权限和 mtime 不变。无 git 时保留全部 5 个种子文件。Codex 0.144.1 复验确认完整权限、联网、live web search 实际生效。

意外：路径设置在 Core 构造时读取 SharedPreferences，破坏了未启用 Labs 的纯 Core 测试；改为按需读取。文件事件改为提交后仅发送新增项。主包和包测试需分别从各自 package config 运行。Next/安全 365 项、Harness 包 87 项通过。实验没有访问真实下载站点；Windows 与去沙箱后的桌面真机行为待实测。完整命令、输出及范围见 [X3_REPORT.md](X3_REPORT.md)。

## 2026-10-11 · 去沙箱：真机迁移

假设：GitHub 版去掉 App Sandbox 后，现有用户的数据零丢失，Classic 照常可用。

做了什么：退出 NipaPlay，用 APFS 克隆完整备份容器与普通位置的旧数据（`~/NipaPlay-backup-20261011`），记录迁移前指纹，构建并签名非沙箱 Debug 版后启动。

观察到：
- 迁移日志 `complete: true`。`watch_history.db` 哈希与容器完全一致；`next.db` 各表行数完全一致（331 个媒体实体、2474 条绑定、71 个任务……），仅 schema 从 v6 升到 v7。
- 偏好 436 个键全部来自容器，无缺失、无多余；2 个不同的键都是启动时刷新的弹弹play 缓存。
- **意外（合并前拦下）**：本机普通位置有六月底一次短暂非沙箱运行留下的 `~/Documents/nipaplay`（23 MB，只有缓存）和旧偏好。X2 原规则是“普通位置非空就整组保留”，会让过期数据成为活动数据。改为容器优先，普通位置原数据整组归档。
- Classic 首页正常：媒体库里的《炒翻天》、自定义背景、继续播放、弹弹play 排行榜都在。
- 开启着 Next 的情况下启动，`~/nipaplay-harness` 被创建并初始提交，凭据在 `~/.config/nipaplay/endpoint.json`（0600），`./nipa status` 返回实时状态。
- 历史回执里的路径仍指向容器（迁移不改写绝对路径，容器保留，文件仍可访问）。`./nipa status` 输出很长，留给 Agent 自己发现。

## 2026-10-11 · 实验 1：第一次见面

假设：只靠种子 harness（AGENTS.md + `nipa`），Agent 能在第一次对话中摸清用户的环境，写进 AGENTS.md 并提交。

做了什么：DeepSeek V4.1 flash，`codex exec` 在 `~/nipaplay-harness` 中运行，只用 harness 自己的 `.codex/config.toml`（完全权限）。用户消息：“你好！我刚开启了 NipaPlay Next，先熟悉一下我的环境吧。”

观察到：
- 照 AGENTS.md 先 `./nipa status`、`./nipa list`，然后探索 NipaPlay 状态和文件系统，共 81 条命令。写下的环境基本准确：`/Volumes/Media` 是工位机的 SMB 共享（3.6 TB、约 170 个视频，动画、日剧、国产剧、电影混装）、本机下载、已装软件（qBittorrent、mpv、ffmpeg、yt-dlp、Clash Verge、Tailscale 等）、播放与弹幕偏好。提交为一条 commit，没有写入秘密。
- 发现了真实问题：内置 B 站弹幕获取 5 次全部 `schemaChanged`；媒体库分成两层且不一致（Classic 9 部 / 53 集，Next 作品层 2 部）；367 条文件位置中 284 条未识别。
- 最后列出要用户确认的问题（在哪看、下载来源、是否补识别），合理：exec 模式下无法来回对话。
- 授权边界：只 `ls` 了 Chrome Cookie 库是否存在，没有读取内容。读了旧工作区残留的 `.codex/config.toml`（含一个早已轮换失效的令牌）。

摩擦（身体的问题，归我们改）：
1. **输出过大**：`./nipa list` 362 KB，`./nipa status` 107 KB。整次会话 790 万输入 token（绝大部分命中缓存）。Agent 用 Python 过滤绕过，但没有改进 `nipa`。
2. **`state.query` 翻页不可靠**：`state_read_failed` 5 次、`query_concurrency_limit` 2 次、超时 5 次，Agent 只好写带重试的分页脚本。这是 v1 预设的并发与耗时护栏在真实使用中成了阻碍。
3. **两层媒体库**：`media.library.search`（Classic）与 `library.works`（Next）内容不同，Agent 必须自己弄懂两套视图。
4. **辅助脚本写在 `/tmp`**：分页与统计脚本都没有留在 harness 里，下次会话要重写。

因此改了：清走旧工作区、旧 `endpoint.json` 和 Mesh 测试数据（移入备份）；1、2、4 与种子更新通道交给 X4，3 交给 X5。
