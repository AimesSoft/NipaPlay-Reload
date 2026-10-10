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

## 2026-10-11 · 实验 2：刷新优酷弹幕（基线）

假设：应用不需要内置优酷支持，Agent 会用用户浏览器的登录态自己取到弹幕，交给 NipaPlay。

做了什么：DeepSeek V4.1 flash 在 `~/nipaplay-harness` 中，用户消息：“帮我刷新一下《长安十二时辰》第 1 集的优酷弹幕。”

观察到：
- 51 条命令，330 万输入 token。准确定位了第 1 集的文件、时长（ffprobe 47:02），在视频旁找到优酷 XML（`chatserver=youku`，chatid 4244626952，16203 条），解出了优酷视频 ID。
- **没有走浏览器登录态。** 它直接使用 NipaPlay 内置的优酷来源：`danmaku.resolve`、`danmaku.fetch` 返回 `authenticationRequired`，随后调用 `ui.open_platform_login` 在 NipaPlay 里弹出优酷登录窗口，请用户在那里登录；另提出可以先导入本地 XML。
- 没有写任何工具进 harness，也没有提交。

判读：冻结的内置功能成了轨道。只要存在“优酷来源”和与之配套的“打开登录窗口”，Agent 就沿着现成的路径走，AGENTS.md 里“使用浏览器登录态”的事实压不过一条现成的工具链。这不是加说明能解决的；按纲领，“碍事时删除”。

因此改：消融实验——删除内置的优酷、B 站来源与应用内平台登录（保留弹弹play、本地文件与 `danmaku.import`），再跑同一个任务比较（X6）。

## 2026-10-11 · 实验 2b：删除内置来源后重跑

假设：没有内置的优酷来源和登录窗口之后，Agent 会用浏览器登录态自己在线取弹幕。

做了什么：X6 删除了 Next 内置的优酷、B 站来源与应用内登录，重新构建。harness 仍是旧版 `nipa`（只改变一个变量）。同一条用户消息。

观察到：
- **没有在线获取。** Agent 确认“NipaPlay 没有在线优酷源”后，把“刷新”解释为重新导入视频旁的本地优酷 XML。最后如实说明这不是联网抓取，并问用户是否要在线拉最新的。
- **身体的缺陷**：`danmaku.import` 拒绝了这份 XML（`Invalid comment at index 3263`）：135 条颜色是 32 位 ARGB（`0xFFRRGGBB`）。Classic 加载同一份文件没有问题，导入校验比 Classic 自己的解析器更严，又是一条预设得过紧的护栏。
- **harness 自己长出了工具**：Agent 写了 `tools/normalize_youku_xml.py` 去掉 alpha 位，导入 16203 条成功；清洗后的副本放在 `records/`（已忽略）；把颜色问题、`danmaku.import` 的刷新语义写进 AGENTS.md，并提交。这是期望中的“缺什么就在仓库里写”。
- 也写下了一条它自己推断的约定：“刷新一集优酷弹幕 = 重新导入本地 XML”。这条经验是错的（用户说刷新，本意是取最新），以后的会话可能照着做。harness 积累经验，也会积累误解。
- 406 万输入 token（旧版 `nipa` 输出仍然很大）。

判读：删除内置来源去掉了轨道，但本地文件又成了最省力的路径。“优先用浏览器登录态在线获取”在一次性的 exec 里没有发生；真实对话中用户会追问一句。下一步：续接同一会话，用用户的口吻澄清，观察 Agent 能否自己写出在线获取工具。

因此改：`danmaku.import` 应与 Classic 加载本地弹幕的解析一致（X7）。

## 2026-10-11 · 实验 2c：用户澄清后在线获取

假设：用户说清楚“要在线最新的”之后，Agent 能在 harness 里自己写出在线获取工具。

做了什么：续接实验 2b 的同一会话（`codex exec resume`），用户消息：“不是，我要的是从优酷在线拉最新的弹幕。我的浏览器里登录着优酷，你直接用就行。”

观察到：
- Agent 自己写出 `tools/youku_danmaku.py`（纯标准库，多线程）：从 `<chatid>` 解出优酷 vid，调用 `acs.youku.com` 的 MTOP 弹幕接口，按 60 秒分段抓取。
- **发现这个接口不需要登录**：先发一次空签名请求拿到 `_m_h5_tk`，再签名请求即可。因此没有读取浏览器 cookie，也没有触发钥匙串授权。v1 和 download-harness 都假设“优酷需要登录态”，这条假设在真实接口上不成立（至少对弹幕列表）。
- 第 1 集在线 16192 条，含 2026-10-10 当天的新弹幕；经 `danmaku.import` 原子替换了原轨道（绑定 revision 2），轨道设置保留。
- 把接口签名流程、vid 规则、实测每段约 360 条的上限写进 AGENTS.md，提交。主动说明了每段上限导致总量可能略少于完整历史。
- 45 个分段并发抓取；对“请求要有节制”这条边界，并发度值得以后观察。
- 733 万输入 token（旧版 `nipa` 输出仍大）。

判读：去掉内置来源的轨道之后，harness 的核心循环成立：缺能力 → Agent 在仓库里写工具 → 交给身体 → 记下经验 → 下次复用。一次性指令里 Agent 会选最省力的路径；用户的一句澄清就足以让它走到正确的路径上。

## 2026-10-11 · 一个媒体库（X5）真机

假设：把 Classic 的匹配物化进共享身份层后，Agent 只需要一套媒体库视图，且不改动任何既有数据。

观察到：重新构建启动后 `library.works` 恰好 10 部（Classic 的 9 部加《长安十二时辰》，《炒翻天》复用），与 X5 只读推算一致。`next.db` 升到 v8，完整性检查通过；新增 57 个实体、100 条绑定（来源 `classic_match`）；原有历史 215 行、位置 267 行、任务 71 个不变；Classic 的 `watch_history.db` 哈希与迁移前一致（还没有需要回写 Classic 的 Agent 弹弹play 匹配）。

## 2026-10-11 · 实验 3：新会话复用工具

假设：上一个会话留在 harness 里的工具和经验，新会话会找到并复用。

做了什么：全新的 DeepSeek 会话，用户消息：“把《长安十二时辰》其余各集的优酷弹幕也在线更新一下。”

观察到：
- 读 AGENTS.md 找到了 `tools/youku_danmaku.py` 和上次记下的 vid 规则，直接复用；第 2–48 集全部在线刷新并导入，零失败。48 集共 699,192 条。逐集核对 `platformVideoId` 与 XML 的 `<chatid>` 一致。
- **在复用的基础上又长出更高一层的工具** `tools/youku_refresh_work.py`：整部作品逐集抓取并导入，`--episodes` 限定范围，**默认 dry-run，加 `--execute` 才写入**。这正是 download-harness 的风格，种子里没有教过。
- 请求节制：每集 8 个并发、集与集之间停 1 秒，共约 2100 次请求。
- 更新 AGENTS.md 的现状与用法并提交。560 万输入 token（旧版 `nipa` 仍在）。

判读：harness 的积累跨会话成立。工具从“一集”长到“一部”，是使用自然推出来的，而不是预先设计的。
