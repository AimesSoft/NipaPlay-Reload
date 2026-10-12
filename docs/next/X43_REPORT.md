# X43：无界面 Next 宿主

日期：2026-10-13（台北）。工作分支：`next/x43-headless`。

## 1. 完成了什么

新增纯 Dart 入口 `bin/nipaplay_headless.dart`，由
`lib/next/headless/core.dart` 组合现有 Next 领域服务。macOS、WSL Ubuntu 24.04 x86_64、
Windows x64 都已运行源码、本机编译的 AOT 程序和 Python `nipa`，完成真实共享媒体
的扫描、身份绑定与 `ui_facts` 读取。运行说明见 [HEADLESS.md](HEADLESS.md)。

这批交付是可运行的片库/任务宿主，目标尚有明确缺口：下载传输、Mesh 和账号配置未
接入；没有播放器或内嵌模型对话。下载任务返回明确的 `unavailable` 失败回执。
GUI/Nipa 可由 MCP 客户端接入回环端点，但现有 GUI 多设备发现还不能连接此宿主。

已提供的 65 个 Action 覆盖 `app.instance`、task、media、metadata、identity、本地
danmaku、settings、state、ui 数据、followup 及保留的 download 契约。
扫描负责枚举和建立文件事实，实验脚本根据文件名与公开 Bangumi 目录作出绑定决定。
没有在代码里自动编排识别判断。

数据必须显式放在独立 `--data` 目录，首次要求为空；不借用 GUI StorageService、
偏好、登录钥匙串、Classic 历史或用户 Codex 目录。独立设备身份、数据库、缓存、
用户 harness、连接凭据和运行标记均在该目录。进程锁保证单一拥有者；媒体根与数据
根解析符号链接后不得相互包含。停止先关闭端点和域工作者，再关闭数据库，删除连接
凭据及运行标记。端点只监听 IPv4 回环，默认随机端口，没有 LAN 开放选项。

### 依赖盘点

“纯 Dart”指本任务中的宿主是否可运行；底层仍可使用系统动态库或子进程。

| 部分 | 原有依赖 | 无界面运行现状 | 本次改动 / 仍要改什么 |
|---|---|---|---|
| NextCore / NextRuntime 总装 | Flutter material/services、UI 偏好、StorageService、Classic 服务与播放器 | 原总装不可直接在 Dart VM 加载 | 独立 HeadlessCore 复用领域类，保留 GUI 总装；以后若合并宿主组装，需把剩余服务端口继续分离 |
| MCP / nipa / 公共 harness | Dart HTTP、Python；LabProfile 间接引入 Flutter | 可用，三平台 Python nipa 实测 | LabProfile 条件导出；公共 seed 排除 `.codex`，连接凭据仍在 harness 外 |
| 实例事实 | macOS MethodChannel、window_manager | 可用；窗口/bundle 字段为空 | 条件平台实现；Flutter 分支保留原生窗口查询 |
| 数据库 / 迁移 / 设备身份 | sqflite_common_ffi、SQLite 动态库、Dart IO | 可用，沿用 Next 现有 15 个版本迁移 | 独立目录；数据库结构、依赖和迁移版本未改 |
| 任务 / 回执 / 变更历史 | Dart、SQLite；异常报告借用 FlutterError | 可用 | 条件错误报告；宿主延迟关闭共享 DB，等待执行者退出，不改现有任务实现 |
| 本地文件 / 扫描 / 片库 | Dart IO；MDK 取时长；ClassicMetadataPort | 可用 | 拆出纯 port/投递逻辑；无 Classic 历史；修复 Windows 盘符被当作 URI 的 Next 路径判断 |
| 时长探测 | fvp/MDK 原生播放器 | 可选 ffprobe 子进程，未实测 ffprobe | 条件导出；显式绝对可执行路径、15 秒超时；无配置时为 null |
| 身份 / 批量绑定 / 提供的元数据 | SQLite；历史导入的 WatchHistoryItem/Classic 来源过滤带 Flutter | 可用 | 抽出历史资格判定；Flutter 保持现有实现；headless 禁用 history 导入 |
| 外部资料 / API | HTTP 领域 transport；DandanplayGateway、账号客户端、vault 带 Flutter | Bangumi 公开 API 可用 | 抽出 MetadataGateway 与 credential resolver；复用现有 Bangumi transport/provider，未另写弹弹play客户端 |
| TMDB / 弹弹play登录、网关账号 | CredentialStore、Classic 登录/偏好、平台保险库 | 未配置 | 需要独立凭据注册/账号宿主；不得搬运 GUI 凭据或绕过团队网关 |
| 图片缓存 / 校验 / 色调 | dart:ui instantiateImageCodec | 可用，三平台海报缓存实测 | Flutter 原算法留在 raster_flutter；Dart 使用已存在的 image 依赖，不新增 package |
| UI facts / 卡片 / shelves | Dart/SQLite；Classic 更新日历 | 核心数据可用；没有界面渲染 | 复用 UiDataService；Classic 日历明确 unavailable；不修改 lib/next/ui |
| 同名 XML/JSON 弹幕、绑定、导出 | Classic 文件选择器/native XML 包装、FlutterError、Classic 缓存 | 本地索引可用；无播放器加载 | 纯字节/XML 解析移出 wrapper 并再导出；Classic wrapper 保留；导出限制在 data/exports |
| 弹幕播放 / 播放器 / 截图 | VideoPlayerState、MDK、平台通道和窗口 | 不可用 | 不注册 playback/capture 能力；同名轨道 available=true、loaded=false |
| 下载领域任务 | Next DownloadService/Executor，Dart + SQLite | Action/任务失败回执可用，传输不可用 | 复用 X40 契约，独立 unavailable backend；没有改 X40 代码 |
| Rust librqbit / FRB | 原生库、session 初始化、DHT/发现和用户目录默认值 | 本次未加载 | 当前初始化器有默认 UDP/DHT 持久目录；需 X40 提供跨平台隔离目录与明确监听策略，再接 headless adapter |
| settings / 安全策略 | Classic SharedPreferences、平台 vault、完整 CredentialStore | 仅纯 SQLite 注册项可用 | 复用 registry；秘密键策略纯化并保持 CredentialStore API；不开放 GUI/登录设置 |
| followup | Dart/SQLite；harness location 间接带 Flutter；执行需要 ChatHost | 注册/触发/恢复可用，执行等待宿主 | 抽出 RepositoryLocation；条件到达 ready，理由明确为 chat 未运行 |
| hooks / schedules | Dart Process、文件；Windows 已有 .py/.cmd 分支 | 可用，三平台事件/定时脚本实测 | 不改 hooks 实现；独立用户 harness；只在运行进程内调度 |
| ChatHost | POSIX 登录 shell，Windows 原先拒绝 | Windows 原生 exe 握手已通过 | Windows 直接 Process.start app-server；原 POSIX 分支保留；CLI 尚不创建 ChatHost |
| Mesh | Dart 控制面、FRB/Rust TLS、CredentialVault、账号 JWT、CA；UDP 发现 | 未启用，state 中设备表为空 | 仅抽出设备事实接口；需要独立账号/保险库/信任宿主、禁用广播及明确监听策略；正式 CA 本就未配置 |
| SMB/WebDAV/远端媒体源、Classic 自动同步 | Classic 连接与凭据、GUI 宿主设置 | 未接入 | 本批使用操作系统现有共享挂载和原生路径，不接触 Samba 或已有连接配置 |

## 2. 决策

选择纯 Dart，而非无窗口 Flutter。原因是主体的大部分领域执行、SQLite FFI 与 MCP
已经是 Dart IO；启动 Flutter 仍会加载窗口插件/平台通道，且服务器和 WSL 不应需要
图形桌面。最终活动依赖图为 **1080 个 library、30 个 package（含 nipaplay）**，没有
`package:flutter` 或 `dart:ui`。见 [dependency-graph.json](evidence/x43/dependency-graph.json)。

没有直接重写 NextCore：它同时组合 UI、Classic 登录、媒体源、下载、Mesh、保险库
和播放器附着。本次另建宿主总装，复用其领域服务与相同数据库，条件导出只隔离平台
实现。Classic 的播放器探测、图片算法、凭据读取、XML native wrapper 与历史来源
过滤仍走 Flutter 分支；Next 关闭时没有新增启动逻辑。

下载不加载现有 Rust 初始化器。`rust/src/api/torrent.rs` 的隔离 DHT cache 与关闭
本地发现只针对 macOS Lab；WSL/Windows 默认 DHT 持久路径会落到宿主用户目录，且
DHT 默认 UDP 不符合这批“回环监听、不改用户已有数据”的约束。替换初始化策略属于
并行 X40，不能在本批越界。因此交付可追踪的不可用回执，未声称下载成功。

Mesh 也不自动启用。现有实现要求账号凭据、平台 vault 和 CA，且包含 UDP LAN 广播。
在用户尚未决定无界面账号注册与信任方式前，复制 GUI 令牌或打开广播均不合适。
这不改变已有 Mesh 行为；本批只提供回环接入。

Windows ChatHost 直接启动 `.exe`，可用构造参数或进程环境
`NIPAPLAY_CODEX_EXECUTABLE` 指定，避免登录 shell 和 npm `.cmd` shim。实验强制独立
CODEX_HOME，空配置只做协议握手；无界面 CLI 未把这次握手能力接成自动对话。

便携源码由 `tool/next/headless_bundle.py` 根据已经解析的条件导入图打包。只有公共
源码/package/许可证/seed，保留重定位 package config，不携带完整项目根 pubspec，
避免 Dart CLI 自动解析 Flutter 项目，也不带 `.codex`、运行数据库或端点凭据。
工作站只安装了工作目录内的 Dart 3.12.2 和 Windows Codex 原生包；不需要 Flutter
SDK/Rust 的全局安装。

## 3. 实验与验证

### 真实共享媒体

三平台都只读同一部剧 `躲在超市后门抽烟的两人` 的 9 个 MP4，枚举/读首段/建立文件
事实，没有复制整部媒体。Bangumi 公开 subject `571784` 及 episode refs 来自实际 API；
脚本验证文件名集数与目录后批量绑定 9 个文件，再读取 `ui_facts`。

| 平台 | 媒体路径 | 扫描 / 绑定 | UI facts | 最后主体实验 PID / 退出 |
|---|---|---|---|---|
| macOS | `/Volumes/Media/躲在超市后门抽烟的两人` | 9 / 9 | 9 集标题、海报可用 | 18723 / 0 |
| WSL Ubuntu-24.04 x86_64 | `/mnt/d/Anime/躲在超市后门抽烟的两人` | 9 / 9 | 同上 | 223772 / 0 |
| Windows x64 | `D:\Anime\躲在超市后门抽烟的两人` | 9 / 9 | 同上 | 21040 / 0 |

具体事实：title、originalTitle、overview、year、episodeCount、poster 为 available；
genres、studio、ratings、backdrop、logo 缺失，未补造。episodes.total=9、titles=9、
stills=0、danmaku=0，heroImage=poster，三平台 tint=4279769365。没有 ffprobe，文件
durationMs 均为 null。证据：[macos.json](evidence/x43/macos.json)、
[wsl.json](evidence/x43/wsl.json)、[windows.json](evidence/x43/windows.json)。

同名弹幕使用各自 data/downloads 内的合成索引文件与 XML，未写共享盘：索引发现
Bilibili 来源、videoId=4243、count=1、available=true、loaded=false。文件加入事件
hook 与定时 hook 均生成 succeeded/verified/exitCode=0 回执。后续从 waiting 到 ready，
reason=`Embedded chat host is not running.`；threadId/turnId 为空，没有模型请求。
三平台都明确运行了 `python nipa status`，不只使用实验脚本的 Client。

### 最终 AOT 与生命周期

只补做最终程序启动/重启与已存资料读取，没有重复扫描媒体。每平台两次启动；第一次
写入媒体配置并提交合成无 tracker magnet，第二次不带 media-root，确认从配置恢复。

| 平台 | 两次 PID | 身份 / 配置 / 已存 UI facts | 停止 |
|---|---|---|---|
| macOS | 46797、46814 | 保留 | 两次 exit=0，endpoint 删除 |
| WSL | 234112、234142 | 保留 | 同上 |
| Windows | 20860、6760 | 保留 | 同上 |

下载最终任务 state=failed、error.code=unavailable、retryable=false；receipt 为
unverified/files=[]，原因明确要求隔离 DHT 持久目录与监听策略。没有实际 torrent
传输、Rust 初始化、LAN 下载监听。证据：[macos-final.json](evidence/x43/macos-final.json)、
[wsl-final.json](evidence/x43/wsl-final.json)、
[windows-final.json](evidence/x43/windows-final.json) 及同名 host.log。

### Windows Codex app-server

工作站原来没有可用 codex 路径。原生 npm 平台包安装在指定工作目录，SHA-512
integrity 与 npm 元数据一致。Codex `0.162.1-win32-x64` 通过新 Windows ChatHost 分支
直接启动，initialize/initialized 成功，available=true，transport=stdio，PID=23700
已由 ChatHost.close 关闭。threadCreated=false、turnStarted=false；没有模型凭据、
CPA 配置、用户 Codex 配置或真实对话。
证据：[windows-chat.json](evidence/x43/windows-chat.json)。

### 测试

按 TEAM.md 使用锁排队、取消代理、固定 Flutter 3.44.6、`--no-pub`。

- 迭代相关测试：Classic 投递、sidecar、UI 数据约束、credential store，28 项通过。
- 数据约束：拒绝未标记的已有目录而不写入；同目录第二实例不改端点；重启身份与
  媒体配置不丢；停止删除端点。2 项通过，纯 Dart 子进程实测。
- 报告前完整 `test/next` **只跑一次**，另加 credential store 与 Classic XML 测试：
  **476 passed、4 skipped、0 failed**。四项为原有 X12/X13/X17/X20 opt-in 实验。
- 新宿主及相关平台文件 analyze 无 error/warning；ChatHost 原有单行 if 的一条 info
  保留，没有为此改动无关代码。`git diff --check` 通过。

证据：[full-tests.log](evidence/x43/full-tests.log)、
[headless-tests.log](evidence/x43/headless-tests.log)、
[targeted-tests.log](evidence/x43/targeted-tests.log)、[analyze.log](evidence/x43/analyze.log)。

### 意外与失败

1. 早期纯编译遇到 FFI compiler crash。追踪发现秘密键 denylist 间接加载完整 Flutter
   CredentialStore；抽出相同纯键策略后，活动导入图和编译恢复。
2. 初次扫描因未创建 data/downloads 而无法校验授权根。总装改为先创建自己的目录。
3. Windows `D:\...` 被旧 Next 路径代码当作 URI scheme 拒绝；修正为优先认原生绝对
   路径，随后真实扫描/绑定完成。
4. 实验脚本曾使用错误 Action/任务类型并尝试未公开的任务字段，修正后用 resume
   补做剩余部分，未重新扫描或绑定。期间定时器产生过多条成功回执，随后删除定时配置。
5. 生命周期测试读第一行后取消 stdout，导致宿主关闭时 broken pipe；测试持续消费
   输出后通过。未把此测试脚本故障当成宿主停机失败。
6. Windows npm 平台依赖实际上是版本 alias，最初独立包名查询 404；改用正式平台
   版本元数据后完成握手。最终证据脚本默认 GBK 读取 UTF-8 配置失败，finally 已停止
   PID=28228；修正 encoding 后只补做最终收尾。
7. 便携包早期携带完整 pubspec，Dart compile 会尝试自动解析不存在的 Flutter path
   dependency并报失败，显式 package config 的 AOT 编译仍完成；没有更新依赖。
   最终包不带项目根 pubspec，重新编译三平台均成功，无该解析提示。
8. Windows 清理实验 harness 的 Git pack 遇到只读文件。确认实验 PID 已退出后，仅
   对该实验目录内文件清除只读属性并删除；没有更改机器配置或其他仓库。

### 结束与边界核对

按记录 PID 核实退出后，已删除 macOS、WSL、Windows 主体实验数据及 Windows 空
Codex 实验目录。没有留下服务、计划任务或实验监听；源码/本地工具保留用于复用。
证据：[macos-cleanup.json](evidence/x43/macos-cleanup.json)、
[wsl-cleanup.json](evidence/x43/wsl-cleanup.json)、
[windows-cleanup.json](evidence/x43/windows-cleanup.json)。

未启动任何 GUI 或 `/Applications/NipaPlay.app`，未触碰 ui-demo、主控实例、
download-harness、Samba 配置、系统 PATH/防火墙/服务、用户钥匙串或 `~/.codex`。
媒体仅只读。工作站无模型/CPA/端点凭据复制；证据不包含 endpoint.json、配置、数据库
或带认证链接，进行了秘密模式扫描。未改 lib/next/ui、X40 下载实现或 X41 字幕，
未改依赖，未 commit/push。生成的 macOS plugin registrant 初始改动按任务说明保留。

中断恢复后只做交付核对，没有重新启动宿主、读取共享媒体或重跑完整测试。
macOS、WSL、Windows 的实验数据目录仍不存在，源码与 AOT 程序保留；当前纯 Dart
依赖图与已存证据一致，报告链接均可读取，秘密模式扫描无命中。补上 X43 证据目录
的局部忽略例外，避免报告引用的日志被仓库通用 `*.log` 规则漏掉。
核对证据：[resume-audit.json](evidence/x43/resume-audit.json)。

## 4. 需要主控决定的问题

1. **下载宿主契约**：请与 X40 协调 Rust 初始化器的跨平台 session/DHT 目录、关闭发现
   与回环监听策略。当前版本不能真实传输；接入后还需三平台下载/恢复/停止验收。
2. **无界面账号和信任**：决定凭据由本机何种用户流程注册/保管，Mesh 的 CA、加入方式
   和回环默认之上的显式网络授权。现有 GUI 自动发现/多设备调用尚未满足。
3. **Agent 部署**：决定由工作站 download-harness 外部 Agent 调 nipa，还是由无界面宿主
   创建 ChatHost 并执行 ready 后续；若要真实对话，先决定目标机器如何提供模型认证。
   本批不复制现有密钥，不运行真实对话。

播放器属于 GUI 能力，本批明确不提供；服务器/工作站磁盘由宿主负责事实与执行，
Agent 的身份判断和下载选择仍在工具调用之外。
