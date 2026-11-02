# X36：种子外部查询工具

2026-10-12；worktree `x36-tools`，分支 `next/x36-tools`。未 commit、push、pub get 或增加依赖。

## 1. 完成了什么

新增种子 `tools/`：四个直接运行的 Python CLI、一个共享 HTTP 模块和 README。
AGENTS.md 只增加八行工具事实与可演进声明，没有调用顺序、订阅策略或站点选择流水线。
`pubspec.yaml` 增加资产目录登记，现有按 AssetManifest 复制种子的实现即可交付全部工具，
不修改任何 Dart、界面、下载入库、媒体模型、帮手代理或 Classic 行为。

| 种子工具 | 能力 | 写入 NipaPlay |
| --- | --- | --- |
| `mikan.py` | 搜索番组、读取字幕组与 RSS、种子详情；保留原始标题、发布时间、发布者大小和推测字段 | 不自动写入；所选种子由 Agent 交 `download.add` |
| `discovery.py` | Nyaa、AnimeTosho 的公开 RSS 搜索与候选；Nyaa 的做种数是请求时的快照 | 不自动写入；选种由 Agent 判断 |
| `api.py` | 用户明确提供 URL 的公开 JSON API，支持 GET 查询参数与 POST JSON 搜索 | 身份、资料、图片分别交 `media.identity.bind_batch`、`media.metadata.import_batch`、`media.artwork.set` |
| `danmaku.py` | 外部 danmu-api 的搜索、剧集和单集 XML；B 站公开 CID XML | XML 由 Agent 交 `danmaku.import` |

### 私有 harness 静态审读

阅读指定文档、允许范围内的 17 个 Python 源文件、requirements、API 目录及四个测试文件。
没有读取 `config.toml`、`records/`、`.env`、被禁止名称的文件或 macOS 配置，没有运行私有仓库的任何脚本。
下表仅记录源码和允许文档显示的能力，不声称连接或验证了用户的个人部署。

| 原工具 | 解决的问题 | 环境与依赖 | 本轮处理 |
| --- | --- | --- | --- |
| `manage.py` | JSON 命令入口；下载、RSS 订阅、限速、删除预览、配额、观察任务、触发同步 | Python 3.11+、个人 TOML 配置、qBittorrent、工作站 SSH/Windows 任务 | 不移植；NipaPlay 已有相应身体能力，个人同步也不适用 |
| `common.py` | qBittorrent 登录、API、种子上传、任务 hash 选择、受约束的远端路径和 SSH 目录创建 | 标准库；个人下载器和 Seedbox SSH、固定主机指纹 | 不移植下载器；仅借鉴传输边界与不暴露请求凭据的语义 |
| `api.py` + `api_catalog.json` | qBittorrent 4.5.2 的 95 接口目录、GET 读接口约束、POST 预览、私有导出 | 依赖 `manage` 的账号、配置和操作日志；不是通用公网 API | 不复制接口目录和登录；另实现无预设主机的公开 JSON 查询 CLI |
| `mikan.py` | Mikan HTML/RSS 搜索、番组、字幕组、候选、详情；标题属性推测 | 标准库、公开 Mikan HTTPS；解析依赖站点结构 | 移植解析与命令，改为共享标准库传输，添加独立 CLI 入口 |
| `discovery.py` | Nyaa/Sukebei、AnimeTosho、apibay、YTS、EZTV、SolidTorrents、1337x、Rutor、RuTracker、PornoLab、FitGirl/DODI、LibGen 的候选发现 | 多数是公开 RSS/JSON/HTML；RuTracker/PornoLab 用登录会话，镜像与 HTML 易变；包含本机代理探测 | 只保留动画相关的 Nyaa/AnimeTosho RSS；省去登录、代理进程探测、游戏/图书和其他站点 |
| `danmaku.py` | 优酷分集和签名分段弹幕转 XML；danmu-api 聚合；按文件名集号上传视频旁 XML | 公开优酷元数据；登录抓取需 aiohttp、可选 browser_cookie3；上传依赖 paramiko/工作站；聚合源需外部服务 | 移植聚合查询语义，删除预设服务地址和访问值、选首项/整季循环/上传；另加公开 CID XML |
| `bootstrap.py` | 新控制设备创建 venv、独立 SSH 密钥、固定工作站指纹 | Python 3.11+、SSH 工具、个人配置、requirements | 个人多设备部署，不移植；NipaPlay 有 Mesh |
| `enroll_device.py` | 将新设备公钥加入工作站授权列表 | paramiko、工作站管理权限、PowerShell | 个人授权部署，不移植 |
| `deploy.py` | 安装 Windows worker、SFTP 连接与权限、计划任务 | paramiko、Seedbox SSH、Windows OpenSSH/PowerShell/任务调度器 | 个人部署，不移植 |
| `worker.py` | 已完成下载单向拉取，SFTP `reget` 续传、`.part`、大小验证、原子发布、回执与并发锁 | Windows 工作站、OpenSSH sftp.exe、paramiko、个人任务/状态/目录；也有 POSIX 锁路径 | 不移植；不会复制个人凌晨任务或轮询/同步策略 |
| `media_server.py` | 生成播放服务 TLS 配置与证书；只读 HTTPS WebDAV | cryptography、WsgiDAV、cheroot、个人媒体目录和服务配置 | 个人播放服务，不移植 |
| `deploy_media.py` | 将独立 WebDAV 服务部署到 Windows，保存连接材料并登记任务 | paramiko、PowerShell、工作站和媒体服务依赖 | 不移植 |
| `setup_samba.py` | 在工作站现有 WSL Linux 上配置只读加密 Samba | WSL、root、Samba、Windows 媒体盘 | 不移植 |
| `deploy_samba.py` | 部署 WSL Samba 和 Windows 持久端口转发/计划任务 | paramiko、PowerShell、WSL/Windows 管理权限 | 不移植 |
| `deploy_mac_mount.py` | 安装用户级静默 SMB 挂载 LaunchAgent | macOS launchctl/mount 工具、个人共享与本地登录材料 | 不移植；本轮不读它引用的 macOS 配置 |
| `verify_media.py` | 登录/TLS、PROPFIND、范围读取、共享边界、写操作拒绝、样本速度验证 | 用户 WebDAV 登录材料、私有 CA 和媒体共享 | 不执行、不移植；包括向共享尝试写入的验证，不适合本轮只读实验 |
| `verify_smb.py` | SMB3 加密/方言、范围读取、写拒绝和样本速度验证 | smbclient/smbprotocol、个人 SMB 登录与共享 | 不执行、不移植；不寻找共享账号或重新挂载 |

原 requirements 仅固定 paramiko，源码其他可选能力另有依赖；种子全部使用标准库，
最低 Python 3.9（XML/运行语法），平台命令以 README 为准。未把源代码中的私人地址、目录、
账号、访问值或私有仓库 URL 搬入种子或实验记录。
审读中的一次工具输出包含了原弹幕脚本的预设访问常量，这是读取方式的失误；没有使用该值、
连接其源服务或写入交付物，后续读取改为结构摘要。此处不重复该常量。

## 2. 决策

1. 种子是小工具集，不是原 harness 的配置移植。没有 qBittorrent 客户端、工作站同步、
   自动选种、自动挑第一个番组、整季弹幕抓取、视频旁 XML 上传、hooks 或 schedules。
   弹弹play 查找与匹配始终经 `nipa` 使用 NipaPlay 网关，没有另写直连弹弹play 客户端。
2. 只给出有来源的候选和证据。保留标题推测为 `inferred`，保留发布者大小、发布时间、
   做种快照和截断事实；错误页、解析失败、无结果是不同情况。
3. 无默认 danmu-api 服务和登录提取。聚合来源必须由用户提供；公共 API 工具不接受带凭据 URL，
   不读取账号文件或浏览器。优酷登录、分段与新站点留作实际任务中的进化空间。
4. 标准库传输有有界时间和响应大小、HTTPS/明确 loopback HTTP、来源内重定向和非零错误。
   XML 不接受 DTD/ENTITY；输出 XML 独占创建，避免覆盖已获取证据；JSON 脱敏保留多条 URL 键。
   文本始终是数据，不编排 Agent 的决定或扩大用户授权。
5. 来源记录在工具 README：用户授权移植的私有源码，没有许可声明；不声称取得开源许可证，
   也没有拉取或引入其他依赖。资产目录登记是交付新 harness 所需的唯一种子目录外运行配置改动。

## 3. 验证与真实实验

边界验证见 `evidence/x36/verification.json`：17 项通过，包含挑战页与声明拒绝、种子身份一致性、
脱敏条目不合并、XML 原字节/计数、已有输出不覆盖、服务路径前缀和四个独立 CLI。
这是数据与输出边界验证，不作为真实功能成立的替代证据。

相关 Flutter 测试 `harness_repository_test.dart`：3 项通过。最后仅运行一次完整
`flutter test --no-pub test/next`：438 项通过、4 项跳过，耗时 1:56；按 TEAM 的 lockf 锁排队并去掉代理。
没有改 Classic Dart 代码或行为，因此未扩大运行无关 Classic 测试。
macOS Debug 构建成功，使用固定 Flutter 3.44.6、`--no-pub` 和 Erika 预编译缓存。
`codesign --verify --deep --strict` 及 entitlement 检查通过（allow-jit、无 app-sandbox）。
Pod install 随现有解析结果改写了 Podfile.lock，已按原 diff 恢复，不交付依赖变更。
GeneratedPluginRegistrant.swift 是任务开始已有的生成改动，保留。
六个工具/说明资产逐字节与构建包一致（`bundle-tools.json`）；真实实例的新 harness 也收到这六个文件。

### 实验环境

直接运行本 worktree 的 `Contents/MacOS/NipaPlay`，两个一次性 profile：
`x36-tools-15967`（进度/弹幕）与 `x36-tools-35354`（推荐）。真实 header 均为
`deepseek-v4.1-flash / cpa`。没有启动正式应用、查找应用名、激活窗口、像素点击或截图；
实例使用默认安静模式。实验 CODEX_HOME 中复制现有 provider 配置/认证并仅修改实验模型，
权限保留；复制公共 `/etc/ssl/cert.pem` 并设置 CA 环境变量、provider 与回环 NO_PROXY。
没有改用户 `~/.codex` 配置或读取登录钥匙串。

通过 `nipa` 在实验配置登记 `/Volumes/Media/躲在超市后门抽烟的两人` 为片库根目录，
作为空白实验实例的上下文；没有预绑定身份、预置弹幕或给模型步骤。共享只读，未重新挂载、
寻找账号、写文件、改名、删除或复制视频。用户看到的 ui-demo 与主控实例未触碰。

### 真实对话与工具轨迹

| 原话 | 实际观察 | 工具演进 |
| --- | --- | --- |
| “无职转生第三季最近更新到第几集了？” | 65.042 秒 completed；主动 `ls tools` 和阅读 README，用 `api.py` POST 查询 Bangumi（返回 JSON）；结合 web 搜索、TOKYO MX 节目结果回答第 14 集。没有调用 Mikan。 | 没有修改种子工具。先因 zsh here-document 和 `/tmp/q.json` 在 lab 中写入被拒绝，改在 harness 建临时 JSON 文件后成功。 |
| “给《躲在超市后门抽烟的两人》补上弹幕” | 720.234 秒仍 inProgress；预设 12 分钟观察窗结束后驱动中断，history 实际为 interrupted。88 个命令、4 个搜索调用；`api.py` 成功找到 Bangumi 571784 的 12 话资料，但没有 XML 获取或 `danmaku.import` 回执。最终 `query danmaku.tracks` 返回 `rows:[]`。 | 阅读了 `danmaku.py --help`、未实际调用其获取功能；没有修改工具或留下 git 改动。 |
| “蜜柑里《无职转生 第三季》最近有哪些版本？给我推荐一个。” | 新隔离实例，192.942 秒 completed；主动 `mikan.py search` 找到番组 3995，`releases 3995 --limit 0` 返回 315 条；从发布标题整理 13 个字幕组及近期版本，推荐 LoliHouse 01–14 合集并附来源。没有下载或订阅调用。 | 没有修改工具；把 `/tmp/s3.json` 改为 `records/mikan-3995.json` 后成功。 |

推荐轮的事实字段有源记录支持，但“画质与体积平衡最好”“最高还原”等总结没有媒体实测支持。
这属于 Agent 超出候选证据的表达，不能据此声称工具验证了画质。结果表的当前响应条数和字幕组数
也不等于所有站点或所有历史发布。第一轮的“完结”回答是 Agent 结合放送搜索给出的判断，
不是单独依据本地片库或 RSS 得出的事实。

弹幕轮的主要阻塞与意外：

- 空白实验片库只有已登记根目录；她找到了目录与第 1 集文件，但作品尚无身份绑定。
  对 `nipa call` 的 Action 与 `nipa query` 的 view 有持续混淆，重复得到 Unknown field/unknown_view；
  这不是预制脚本的解析失败。本轮只记录，不改跨任务契约。
- 外部 danmu-api 没有已配置服务，所以没有自动选择一个默认主机。她转向网页寻找 BV/CID，
  B 站公开接口出现风控 HTML、`-404`、`62002`（稿件不可见）等结果；工具本身只接收 CID，
  不承担网页搜索、BV 转 CID、登录或分段协议。字幕/时长的候选判断也没有形成绑定/导入回执。
  实例日志明确显示临时配置未登录弹弹play，内置服务报“请先登录弹弹play账号后再使用弹弹play服务”；
  本轮没有复制用户的 NipaPlay 登录材料。这是实验条件，不能据此认为登录后的网关不可用。
- 她尝试浏览器技能，在实验目录内下载 npm 工具；浏览器 daemon/cache 和 Chrome Crashpad 默认
  指向 profile 外部，遭 Operation not permitted。她自行把 npm cache、TMPDIR、daemon 目录移入
  `records/tmp`，但 Chrome 启动仍受外部 Crashpad 路径限制。没有放松 lab、操作真实浏览器登录态
  或把这些临时下载带入项目依赖。here-document 与复杂 shell 引号也多次失败。
- 她也直接探测了外部弹弹play API，没有产生可用获取回执；这条路径未写入种子。
  种子仍使用 NipaPlay 既有弹弹play入口。后续应观察她为何从调用失败转向直连，而非将它产品化。
- “B 站大陆投稿几乎没有弹幕”等中间回复，轨迹没有实际 XML 条数证据支持，本报告不采纳为事实。
  回合中断时 lastEventAgo=57 ms、lastContentAgo=16,916 ms、latestError=null，仍有事件，
  不能将这次观察窗结束解释为模型或 provider 断流。没有重跑这一模一样的实验。

单独的一次来源冒烟：Mikan 搜索返回 1000 条页面候选，按 `--limit 3` 截断并保留截断事实；
同一搜索给出第三季番组 3995。Nyaa 在当前终端 TLS 环境报
`Provider request failed: SSLCertVerificationError`；保留失败证据，没有关闭 TLS 验证或宣称在线通过。
AnimeTosho、实际远端 danmu-api 和 B 站 CID 获取没有在本轮声称在线验证；单集 XML 获取只用
临时 loopback 服务守住输出/路径边界。

证据：`operations.json`、`operations-recommendation.json` 保存真实 header、原话、回合历史及
`chat.turn.process` 命令/退出码/输出；`checks.json` 保存检查结果；`source-inventory.json` 只保存
允许源码的文件名、行数与 SHA256，没有复制个人源码或配置。

两个回合实例都先经自身 VM service 核对 PID，再调用 chat close、按各自进程号退出；
两个完整实验目录（配置/认证副本、CA、harness、临时 npm/浏览器文件、数据库）均已删除。
采样到的各自子进程也全部退出，没有额外进程需要终止，见 `cleanup.json`。
保留的 app log 已脱敏，其中有 sqflite 默认工厂警告和未登录弹弹play导致的排行榜请求失败；
实例端点与真实聊天仍工作，本任务没有改这些模块。

### 尚未覆盖

工具发现与通用 API、Mikan 候选查询已观察到成功，弹幕实际写入仍未完成；工具没有被 Agent 改进。
登录平台、BV/CID 搜索、分段弹幕、更多站点、用户自己的聚合服务保留为进化空间。
当前 Nyaa TLS 环境以及 Windows 实际运行也未验证通过；不把边界测试包装成这些环境的在线验证。

## 4. 问题

需要主控决定的问题：没有。弹幕来源获取、Action/view 混淆、推荐措辞和 lab 浏览器限制是本轮
留下的后续实验问题；本交付不新增调用流水线、不扩展下载/媒体/聊天/界面模块来替 Agent 做判断。
