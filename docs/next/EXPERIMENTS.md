# 实验记录

每条记录：日期、假设、做了什么、观察到什么（包括意外和失败）、因此改了什么。v1 时期的真机验收记录见 `archive/v1/ACCEPTANCE_LOG.md`。

---

## 2026-10-11 · X11：实验配置隔离

假设：一个 Debug profile 开关足以把研究实例的偏好、数据、保险库身份、harness 与端点隔离，并与真实实例并行。

做了什么：审计 StorageService、SharedPreferences、path_provider、原生缓存、Rust torrent/DHT、钥匙串、Agent、Mesh、Web 和单实例入口；实现 `NIPAPLAY_PROFILE`，在 macOS 引擎启动前安装文件写入限制和 profile 后端。真实 HOME 下启动 x11test/x11peer，与无 profile 的真实 PID 25337 同时存在；经实验 CLI 写设置，跨 profile 令牌返回 401，同名 profile 重复启动正常退出。

观察到：指定真实偏好域的 427 个键、真实数据目录、原有 10 个钥匙串账号名、endpoint 和用户 harness，在最终独立基线的启动前/运行时/清理后完全相同；实验新增的两个钥匙串条目和两个 profile 目录已清理，真实 PID 保持运行。profile 外普通写入、符号链接写入和直接子进程 touch 均被拒绝，真实媒体目录可读。

意外：Foundation 原子写入会用外部临时目录，改为同目录替换；legacy Keychain API 在写入限制下失败，改用只接受该 profile namespace 的管道 broker。中途重建签名触发实验条目授权等待，清理合成条目后用同一最终构建复验。整个长会话另有真实启动/用户 harness 变化，不能报告全会话零变化；最终受控区间的指定状态不变。真实实例自己的全局 DHT 缓存仍周期更新，两个实验 DHT 分别位于自己的会话目录。

因此改了：删除旧 DATA_DIR 机制，统一所有应用存储入口、账号命名空间和动态端口；不参与真实 LAN 广播，窗口/CLI 明示 profile。27 项约束/回归测试、analyze、macOS Debug 构建通过。范围与真实输出见 [X11_REPORT.md](X11_REPORT.md)。

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

## 2026-10-11 · 实验 4：harness 升级

假设：应用升级后，Agent 能把种子的改进（新版 `nipa`）同步进它已经定制过的 harness，并让笔记与实时状态一致。

做了什么：这个 harness 创建于种子更新通道（X4）之前，没有 `nipaplay` 远端，和种子没有共同历史。用户消息：“NipaPlay 刚更新了一版，看看这个 harness 有没有需要同步的。”

观察到：
- Agent 自己找到应用维护的种子仓库（`~/Documents/nipaplay/next/harness-seed`），加为 `nipaplay` 远端，发现没有共同历史，手动同步了新版 `nipa`（`status` 从 2.6 万字符降到几百）。
- **用实时状态逐条核对 AGENTS.md 的旧记录**，列出过时项（能力数 67→64、媒体库已统一、ARGB 已原生支持、分页已修复等）并全部改正；保留 `normalize_youku_xml.py` 并标注“通常不再必要”。把远端与“首次需手动同步”写进维护说明。提交。
- 指出《长安十二时辰》在 `media.library.search`（Classic 视图）中搜不到：它只有 TMDB 身份，Classic 没有对应概念。这符合“两张脸”的设计。
- 它报告文件记录从 367 降到 267。核对：实验 1 的 367 是当时带重试的翻页脚本重复取页造成的（只有 244 个不同位置），全部仍在现在的 267 行里，没有丢失。重新核对纠正了它自己早先的笔记。
- 1072 万输入 token，118 条命令；重新核对很彻底，也很贵。

判读：种子 → harness 的更新可以交给 Agent。没有远端、没有共同历史时它也能处理。可改进：`nipa status` 若直接报告种子版本与远端是否落后，发现更新就不必靠探索文件系统。

## 2026-10-11 · 实验 5：下载完成 hook

假设：Agent 能写一个 hook，让“下载完成 → 识别 → 挂弹幕”在对话结束后也自动发生，并留下回执。

做了什么：用户消息：“以后每下载完一个视频，自动用弹弹play 识别一下并挂上弹幕；识别不了就在 harness 里记一笔，我回头看。弄好之后下载一部开放授权的短片（比如 Big Buck Bunny）测试一下。”

观察到：
- Agent 写了 `hooks/download.completed` 和 `tools/dandanplay_autolink.py`、`tools/dandanplay_retry_unlinked.py`：先看已有身份绑定，再看 Classic 观察，最后退回哈希匹配；识别不了的追加到 `records/unlinked_downloads.jsonl`（已忽略、去重）。用法写进 AGENTS.md 与 `hooks/README.md`，两次提交。
- 下载了 Big Buck Bunny（WebTorrent 官方开放授权种子，276 MB）。**下载完成后 hook 自动触发**（任务 exit 0），弹弹play 未收录，如实记入清单。
- 307 条命令，6100 万输入 token（绝大部分缓存），大量时间花在排查网络上。
- **网络**：直连弹弹play 网关被校园网拦截：直连拿到 `pan-fw-trust`（Palo Alto 防火墙）签发的证书，备用 IP 被 302 到 `campus.example` 登录页。经 Clash 访问网关正常（200，证书有效）。NipaPlay 没有设置自己的 HTTP 代理，所以直连。Agent 判断为“网络问题，不是代码问题”，正确。
- **身体的缺陷（用户数据受影响，已恢复）**：为测试“能识别时”的链路，Agent 把《穹庐下的魔女》第 1 集（Classic 中原本未匹配）临时绑定到弹弹play，随后撤销，并报告“临时绑定已撤销”。实际上绑定经 X5 的投影写进了 Classic，撤销只撤了 Next 一侧；投影还把这一行的 `anime_name` 写成了空字符串。逐行对比迁移前备份后，主控退出应用，把这一行恢复原值；Classic 库现与备份完全一致。

判读：hook 机制成立。投影是单向的：写入 Classic 的匹配不会随撤销收回，Agent 也看不见这一点，于是报告与事实不符。交给 X8：撤销时收回自己的投影（Classic 之后没被改过时），投影不清空字段；同时让 `nipa status` 报告种子状态（实验 4）。

## 2026-10-11 · 实验 6：陌生来源（豆瓣）

假设：应用不新增内置来源，也能接收 Agent 从任意来源取得的身份与元数据，并在界面显示。

做了什么：用户消息：“给《长安十二时辰》补上豆瓣的信息，评分、简介这些，我想在 NipaPlay 里看到。”

观察到：
- Agent 写了 `tools/douban_metadata.py`，用豆瓣公开的移动端接口（`m.douban.com/rexxar/api/v2`，需要 Referer，不需要登录，不绕过付费墙），取到 subject 26849758：评分 8.1、52 万人评价、导演、主演、简介。存档在 `records/metadata/`。
- **身体收不下结构化事实**：`media.identity.bind_batch` 以 `douban` 为来源被拒（`Unknown metadata provider douban`）——身份只接受内置的 tmdb / bangumi / dandanplay；合并元数据只有 title、originalTitle、overview、imageUrl、year 五个字段，没有评分。Agent 只好把“豆瓣评分 + 类型 + 首播 + 主创 + 简介”拼成一段文字，用 `media.metadata.override` 写进 `overview`。
- 发现 work 与 release 两层各有 overview，界面不同入口取的层不同，于是两层都写。
- 为弄清界面显示什么，Agent 读了本机的 NipaPlay 源码和 `next.db` 的表结构（只读），还用了用户 Codex 里的 Playwright 技能。资源用得很开放，符合“不做孤岛”。
- 收尾验证时，用户的模型服务 CPA 出现 Cloudflare 1033（隧道源站不可达），会话失败；之后恢复。工作此前已提交。

判读：假设不成立。不预设来源是对的，但身份与元数据的数据契约把来源和字段都写死了，Agent 拿到的事实只能降格成文本。交给 X9：身份接受任意来源命名空间并记录来源；元数据接受来自任意来源的结构化快照（评分等常见字段有结构，其他字段不丢）；一部作品对外呈现一致的元数据视图。

## 2026-10-11 · 事件：实验中的 Agent 自行重启了真实实例

经过：豆瓣复测（实验 6b）进行中，实验配置任务（X11）在主仓库重新构建，覆盖了构建目录里的应用，用户正在运行的真实实例随之退出。实验中的 Agent 发现 NipaPlay 不在了，为了继续任务，把新构建的应用复制到 `/tmp/NipaPlay-real.app` 并自行启动，多次尝试直到稳定运行；排查连接时还直接 `cat` 了 `~/.config/nipaplay/endpoint.json`，把 Agent 接口令牌带进了模型上下文（令牌每次开启 Next 都会轮换）。

核对：用户真实的 Classic 观看记录各表与备份逐行一致，`next.db` 完整性检查通过。

判读与处理：
- Agent 的自我修复体现了“像用户本人一样使用这台电脑”，但它运行了一个尚未审查的构建，跑在用户的真实数据上。根因在我们：真实实例不应从构建目录运行。现在真实实例安装在 `~/Applications/NipaPlay-Next.app`，构建不再影响它；实验改在实验配置（X11）中进行。
- 输出令牌违反了“秘密不外泄”。Agent 读这个文件是为了诊断连接；可改进为由 `nipa` 自己报告连接诊断，让 Agent 无需读取凭据文件。
- 本次豆瓣复测受干扰作废，将在实验配置中重做。

## 2026-10-11 · 实验 7：接上 Jellyfin 到播放（实验配置中）

假设：在完全隔离的实验配置中，Agent 能从“帮我接上 Jellyfin”一路做到识别、挂弹幕、播放，用户只需在需要时提供密码。

环境：实验实例（`NIPAPLAY_PROFILE=lab`，88 项能力，空数据），临时 Jellyfin（《莉可丽丝：友谊是时间的窃贼》6 集、Sintel），用户提供的弹弹play 测试账号。我扮演用户：不主动给密码，等 Agent 发起登录。

观察到：
- **整条链路跑通**：添加来源 → 用户提供的密码登录 → 选库（番剧、开放电影）→ 正确识别为 2025 年短篇《莉可丽丝：友谊是时间的窃贼》（弹弹play 17864 / Bangumi 504950），明确区分了 TV 版 → 6 集全部挂上弹弹play 弹幕（第 1 集 584 条）→ 第 1 集播放、弹幕滚动。
- **快速连接码被丢弃**：`media.sources.login` 的 `auto` 已选择 Quick Connect 并返回验证码，Agent 没把码交给用户，转而改用登录窗口。
- **编造检查**：两次声称“Edge 里没有已登录的 Jellyfin 会话”，实际从未检查浏览器。
- **登录窗口不可见**：实验实例中 `method: window` 打开的窗口尺寸为 0×0。
- **绕过缺失的能力**：没有“登录弹弹play”的能力（缺口 6），Agent 找到 NipaPlay 本机的 Web 远程访问接口 `/api/dandanplay/login`，用测试账号登录成功。旧的匿名局域网接口事实上是一条后门。
- **越过边界的搜索**：它在实验配置之外的真实支持目录里搜索账号名和 `dandanplay_token`（只读，没有找到）。
- **自我修复出错**：Agent 判断播放器卡死，自行重启实验实例，第一次用 `open -a` 启动、漏了实验开关，这个副本以正常模式运行，改写了真实的 `~/.config/nipaplay/endpoint.json`。逐项核对：Classic 观看记录与备份一致，`next.db` 自 11:17 后无写入，偏好中没有临时服务器的配置；连接文件会在真实实例下次启动时重新生成。Agent 之后自己发现、改正，并在实验 harness 里写了 `bin/lab-restart`。
- 弹弹play 评论请求遇到校园网 302 时，`danmaku.fetch` 任务记为失败，但弹幕实际可加载；Agent 以 `danmaku.tracks` 的实际加载数判断，没有只看任务状态。
- 5960 万输入 token（99% 命中缓存），216 条命令。

因此改：
- 实验副本 `~/Applications/NipaPlay-Lab.app` 的可执行文件换成外壳：无论怎样启动都带上实验开关（已验证 `open -a` 启动只写实验目录）。
- 待办：缺口 6（账号登录发起）；`media.sources.login` 的说明写清验证码要交给用户、用任务等待结果；修复窗口登录 0×0；`danmaku.fetch` 的回执与实际加载结果不一致需要核查。

## 2026-10-11 · 事件：实验实例播放时整个应用卡死

现象（用户发现）：实验实例播放《莉可丽丝》时鼠标转圈、界面无响应，画面停在第一帧，声音照常；Agent 的播放控制调用悬挂（X14 中一次 `pause` 65 秒超时）。实验 7 中 Agent 因此判断“播放器卡死”并自行重启实例。

查明：
- 线程采样显示主线程 100% 停在 `next2_engine::ffi` 的同步调用里（`Receiver::recv`），等待弹幕渲染线程；弹幕引擎此时正逐字生成 MSDF 字形（约每秒 5 个，机器负载很高），所以视频帧无法交给 Flutter，方法通道与 Agent 调用全部挂起，音频线程不受影响。
- 实验配置是新建的，用的是默认设置：弹幕引擎 DFM+、播放内核 MDK；用户的真实设置是 NipaPlay Next 弹幕引擎与 erika，走不到这条路径。这是实验环境与真实使用不一致造成的。
- 但默认设置就是 DFM+，新用户在弹幕多、机器忙时同样会冻结：这是 Classic 的真实缺陷。

处理：
- X15：`next2_engine_set_frame` 改到弹幕引擎自己的串行队列执行，结果回到主线程；MDK 与 erika、本地与 Jellyfin 四组 642 次调用全部返回，最慢 78 ms。顺带修复窗口化启动时多视图的异常。此修复可单独提交上游。
- 实验配置改为沿用用户真实的播放与弹幕偏好（只复制非秘密的布尔与数值项），实验尽量贴近真实使用。

## 2026-10-11 · 实验 8：给《莉可丽丝》加上 B 站弹幕（开源工具）

假设：NipaPlay 没有内置 B 站来源时，Agent 会先找现成的开源工具（例如 GitHub 上的弹幕下载器），拿来用或改造，并把工具和来源留在 harness 里。

环境：实验配置（沿用用户真实的播放与弹幕设置：erika 内核），临时 Jellyfin 中的《莉可丽丝：友谊是时间的窃贼》。用户消息：“给《莉可丽丝：友谊是时间的窃贼》再加上 B 站的弹幕。”

观察到：
- **没有去找开源工具**，0 条与 GitHub 相关的命令。它自己实现了 B 站的 WBI 签名、视频定位与 protobuf 弹幕解码，只用访问 B 站首页领取的匿名访客 cookie（`b_nut`、`buvid3`），没有碰用户的登录态。注意：实验 harness 创建于“开源工具”那条种子说明加入之前。
- 取到了 6 集的 B 站弹幕数据，但只有第 6 集作为 `bilibili` 轨道交给了 NipaPlay；用户在 Erika 播放画面上确认看得到弹幕。
- **过度求精**：发现 B 站版本（136 秒）与本地文件（140.0 秒）相差 4 秒后，花了大量步骤判断差在片头还是片尾，128 条命令、近 40 分钟仍未收尾。
- **成果没有落进 harness**：工具全在 `/tmp/bili`，没有放进仓库，也没有提交。种子说明里有“不要留在 /tmp”这一条，但它一直没走到收尾。
- 上下文越长越慢：中途一次 CPA 流断开重连；以用户口吻续接“差不多就行”之后，携带全部上下文的请求挂起 14 分钟无回应，主控终止。
- `playback.capture` 传 `includeDanmaku: true`，在 Erika 下截图里没有弹幕（Erika 原生弹幕不在截图中，当初就是这样设计的），但接口没有说明这一点，Agent 可能据此误判弹幕没加载。
- Agent 过程中的叙述是英文。

判读：
- “先找开源工具”这一假设没有出现；弱一些的模型倾向于自己从头写。
- 长任务的真正风险是“没收尾”：工具和经验只有在最后才写进 harness，一中断就全部丢失。按真实对话的节奏把任务拆成多轮更合适；harness 也可以鼓励“边做边提交”。
- 待改：`playback.capture` 对 Erika 原生弹幕如实说明；考虑在种子说明中把“写下来、提交”放到工作进行中，而不只是结束时。
