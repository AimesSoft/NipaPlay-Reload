> 历史开发记录：下文保留原始阶段、路径和验证状态，不是当前安装或操作规范。当前指南见 [Headless](../../HEADLESS.md)。

# NipaPlay 无界面宿主（X43 / X45 / X46 / X47c）

## X47c 媒体库与文件

无界面节点是媒体来源，与 GUI 使用同一 `MeshLibrary`、状态视图和文件原语。
`state.query {view:"library.merged"}` 返回本机及 Mesh 全部作品的合并投影；源节点
提供版本化目录、元数据、图像、小型弹幕/字幕附件和文件字节，无须实现 Classic
HTTP 共享库或启动播放器。数据库仍各自保存，不向别的节点复制 `next.db`。

加入 Mesh 是宿主同意同账号有效双向证书设备访问。没有 `shareLibrary` 开关。
`media.mesh_files.*` 可以读写进程能访问的任意绝对文件路径，与媒体扫描根无关。
readable 批量返回本机路径或调用端的回环可读地址；begin/chunk/finish 提供分段写入，
delete 批量预览删除。finish 覆盖已有文件、delete 都返回 NeedsDecision；选择
confirm 的 destructive ActionCall 前目标不变，确认时再次检查预览签名。
可推送字幕或复制下载文件；源数据是否删除由用户决定，没有预编排移动流程。

视频与文件直接经过 Mesh TLS 1.3 双向认证，使用现有 LAN/overlay/SSH 候选；
协调服务不转发字节。HTTP 转换口只在调用/播放端 127.0.0.1 监听，默认随机端口，
不对外开放明文 HTTP；支持 HEAD、Range 和进度定位，回环必须绕开 HTTP_PROXY。
宿主 mesh.json 的 fileProxyPort 可指定 1024–65535 固定端口，0/省略为随机；第一次
发放地址时绑定，占用则退回随机，mesh.file_proxy 状态视图报告请求/实际端口和原因。
该配置不开放 Agent 修改，配置变化需重启。URL 令牌每次使用 256 位安全随机值，
关闭 MeshLibrary/退出即失效；固定端口重启后旧令牌和猜测的地址返回 404。
传输暂存与确认票据目前随进程退出失效，正常停止清除未发布暂存；异常退出的
`.nipa-transfer-*` 可由宿主检查，原目标不会在传输开始时被截断。

目录投影、进度、历史合并 ID 写在自己的 ui_cache；远端图片/播放附件缓存在
mesh-artwork，源端弹幕导出在 mesh-assets。离线仍显示上次目录和缓存图片，
来源 online=false、只能从该源播放的剧集 playable=false。每 5 秒刷新并触发本机
changes；显式刷新和可读地址、进度原语见 [Mesh README](../../../../lib/next/mesh/README.md)。
合并身份、时间和观看进度策略见 [ui_data README](../../../../lib/next/ui_data/README.md)。

X47c 在 macOS 回环上实测独立 Dart AOT + Rust C ABI 源进程，能响应目录、
提供真实 TLS 文件范围并接收字幕。Windows/WSL 的 X45 二进制须重新构建才能具有
这些能力；X47c 没有启动工作站节点，跨设备与实际 GUI 播放验收仍由主控监督。

这是纯 Dart 的 Next 领域服务宿主，入口为 `bin/nipaplay_headless.dart`。
不启动 Flutter 引擎或窗口。已在 macOS、Ubuntu 24.04 WSL x86_64、Windows x64
运行源码和本机编译的 AOT 可执行文件；实验记录见 [X43_REPORT.md](../../X43_REPORT.md)。

当前可用：回环 MCP/`nipa`、独立片库与任务数据库、只读扫描、身份批量绑定、Bangumi
公开资料和提供的元数据、图片缓存与色调、同名 XML/JSON 弹幕索引、数据卡片、hooks、
定时脚本和持久后续事项。片库归属、资料绑定等判断仍由调用者作出。

X45 增加 Rust Mesh 与 librqbit：独立设备身份、同账号加入、心跳、认证远程调用，
磁链/种子下载、预览、文件选择、逐文件校验/登记与事件。Mac 对话发起的远端下载会
持久回传原会话；无界面脚本的 `agent.wake` 可按宿主配置路由到 Mac。
Windows/Linux x64 原生库及 AOT 已编译，X45 运行检查只在 Mac 本机回环进行；
工作站真机运行待主控执行，见 [X45_RUNBOOK.md](../../X45_RUNBOOK.md)。

当前缺口：播放器、Classic 账号与历史、完整弹弹play账号宿主、
Classic 更新日历。Nipa 的对话见下文“Nipa 在无界面主机上”。无界面只接受宿主从 stdin 登记的组网测试 token，
没有登录密码 Action；未配置 Agent 目的设备的后续仍可到达 ready，不运行模型决定。

X53 接入同一 `NipaplayServerRouter`、`DandanplayHttpClient` 和 provider/弹幕来源。
弹弹play token 读取宿主保险库 `preferences/dandanplay_token`，TMDB 读取
`metadata/tmdb`；后者由宿主使用 `--enroll-credential-stdin` 与非秘密的
`--credential-namespace metadata --credential-key tmdb` 登记，没有新的秘密 Action
参数或 settings 键。读取保险库后也支持 TMDB 图片准备。`network.json` 只保存
既有路由器使用的非秘密网络设置及主备缓存；可省略，默认自动选择官方网关。
合法模式为 auto/hongkong/china/custom，键为 dandanplay_server_mode；显式选择
custom 的 dandanplay_server_url 是信任决定，不能含凭据、query 或 fragment。
`app.capabilities` / `nipa describe app` 说明支持、可用前置、来源与 settingsKeys；
目录同时标出缺凭据、未授权程序和 legacyRecovery。无 Classic 的绑定回执明确
投影 not_applicable，Next 身份和资料照常保存。批量弹幕 fetch/attach/import 沿用
单项语义，每项返回完整 outcome；一项失败不会隐藏前项已提交事实。

X46 补充 `subtitle.tracks/import/select`、旁路字幕索引和 activity 视图；可选 ffprobe
记录内嵌轨道，不读取 Classic 偏好或自动决定默认语言。导入的文本字幕检查时序语法，
不是完整的原生解析/可播放核验；idx/sub 与 sup 保留声明事实。UTF-16 等不兼容文本
可由已授权的本地程序转换后交入；此宿主没有 Classic 原生字幕解析器。
新增宿主可授权的 `program.run` 与 Git bundle 接收，详见 [X46_RUNBOOK.md](../../X46_RUNBOOK.md)。
观看记录能力没有注册：这个独立数据库没有 Classic 历史，也没有播放器产生进度，
不会将空的 Next 记录冒充用户历史。

## Linux 安装包

发布附件里有 `NipaPlay-Headless_<版本>_Linux_<amd64|arm64>.tar.gz`（`scripts/next/headless/package.sh <arch> <version>`
构建，CI 在 Ubuntu 22.04 上出包，要求 glibc 2.35 以上）。包内：`libexec/` 里是编译好的主机和 Rust C ABI 库，
`assets/next/harness`（`--seed` 的默认值）和 `assets/next/agent`（`--agent-assets` 的默认值）是运行时读的种子资源，
`bin/nipaplay-headless` 是把安装时的数据目录补给程序的入口，另有 `install.sh`、`uninstall.sh` 和中文 README。
主机按“可执行文件旁的 `../assets/next`、`assets/next`、当前目录的 `assets/next`”的顺序找这些资源，所以从源码运行不受影响。
`install.sh` 默认建 systemd 用户服务（`--system` 建系统服务），升级只替换程序目录，卸载默认保留数据。
`--version` 打印 `nipaplay-headless <应用版本>`，版本由构建时的 `-DNIPAPLAY_VERSION` 传入，不传就是 `dev`。
`--login-dandanplay` 是主机上的人登录弹弹play：账号名一行、密码一行从标准输入读，令牌进保险库，不是 Action。
只有 `libsqlite3.so.0`（没有开发包的 `libsqlite3.so`）的服务器也能运行（`lib/next/sqlite_library.dart`）。
Nipa 的运行环境清单目前不含 Linux arm64，arm64 包上的主机照常工作，Nipa 需要自备运行环境。

## 准备程序

在依赖已经解析的本 worktree 操作；不要在主仓库构建，不运行 `pub get`。
开发使用 Flutter 3.44.6 随带的 Dart 3.12.2。运行时不需要 Flutter。

```sh
cd ~/Desktop/nipaplay-next-wt/x46-remote-run
~/development/flutter-3.44.6/bin/dart compile exe \
  --packages=.dart_tool/package_config.json \
  bin/nipaplay_headless.dart -o build/headless/nipaplay-headless
```

`build/headless` 必须先存在。Mesh/下载还需要构建原生库：

```sh
cargo build --offline --locked --manifest-path rust/headless/Cargo.toml
cp rust/headless/target/debug/libnipaplay_headless_native.dylib build/headless/
```

Linux 库名为 `libnipaplay_headless_native.so`，Windows 为
`nipaplay_headless_native.dll`；默认从可执行文件旁加载，`--native-library` 可覆盖。
Portable C ABI 复用现有 Rust 实现与依赖，不需要 Flutter 引擎或 FRB 初始化。
可执行文件按目标机器的系统与架构编译，不能把 macOS
二进制拿到 Windows/WSL 使用。SQLite FFI 仍需要系统 SQLite 动态库；这次三个平台
都直接可用。其他 Linux 服务器若缺少它，需在自己的工作目录准备库及进程级加载路径。

移交到未解析依赖的机器时，用以下脚本打包已经解析的纯 Dart 分支，无需下载新依赖。
包内包含领域源码、相关 package 的库及许可证、重定位后的 package config 和公共
harness seed，不包含 `.codex` seed 或任何运行数据、连接凭据。

```sh
python3 tool/next/headless_bundle.py --output /tmp/nipa-next/x43-headless.zip
```

解压到自己的目录，安装相同版本的独立 Dart SDK 到自己的工具目录。在包的根目录
执行上面的编译命令，替换 Dart 路径；Windows 输出名加 `.exe`。
必须显式传 `--packages=.dart_tool/package_config.json`。便携包不带项目根 pubspec，
避免 Dart CLI 自动对完整 Flutter 项目解析依赖。不要使用 `dart run`。

本次工作站已留下可复用程序与本地工具：

| 平台 | 源码/公共 seed | Dart | AOT 程序 |
|---|---|---|---|
| Windows | `D:\nipaplay-next\x43-headless` | `D:\nipaplay-next\x43-tools\dart-sdk\bin\dart.exe` | `x43-headless\build\headless\nipaplay-headless.exe` |
| WSL | `~/nipaplay-next/x43-headless` | `~/nipaplay-next/x43-tools/dart-sdk/bin/dart` | `x43-headless/build/headless/nipaplay-headless` |

## 启动：服务器、macOS、WSL

宿主以前台进程运行。数据目录必须是独立的绝对路径；首次使用空目录。程序拒绝已有
内容但没有 `headless.json` 标记的目录。数据目录不能位于媒体根目录之内，也不能包含
媒体根目录；通过符号链接解析后仍检查此约束。

例如 WSL，在一个终端启动：

```sh
cd "$HOME/nipaplay-next/x43-headless"
./build/headless/nipaplay-headless \
  --data "$HOME/nipaplay-next/headless-data" \
  --media-root '/mnt/d/Anime/躲在超市后门抽烟的两人'
```

服务器/macOS 同样执行本机二进制，替换 `--data` 与 `--media-root`。可以重复指定
`--media-root`。没有媒体根也能启动，随后重启时指定根目录，或调用
`media.library.roots.add/list/remove` 动态登记现有绝对路径。根目录始终只读，登记
不扫描、绑定、移动或重命名媒体。
源码运行方式为 `dart --packages=.dart_tool/package_config.json bin/nipaplay_headless.dart ...`。
默认 seed 是当前目录的 `assets/next/harness`；从其他目录启动时，显式指定
`--seed /absolute/path/to/assets/next/harness`。

可选 `--ffprobe /absolute/path/to/ffprobe`，只调用该程序读取时长，每文件上限 15 秒。
未配置时 `durationMs` 为 null，不伪造时长。此次未安装或使用 ffprobe。

连接始终监听 `127.0.0.1`。`--port` 默认为 `0`（操作系统分配端口），可指定固定端口。
没有向局域网开放的启动选项。启动首行输出 PID、URL、数据目录与连接文件位置，
不输出令牌。

## 启动：Windows cmd

```bat
cd /d D:\nipaplay-next\x43-headless
build\headless\nipaplay-headless.exe --data D:\nipaplay-next\headless-data --media-root D:\Anime
```

选择实际需要授权读取的目录即可，不必授权整个盘。
Windows 与 WSL 是不同的实例：使用各自的数据目录、数据库、设备身份及连接文件。
不要让二者同时打开同一数据目录。不要将现有 GUI 的数据目录用作 `--data`。

## 用 Python nipa 连接

启动后在另一个终端指定该实例的连接文件，避免误连 GUI。

```sh
export NIPAPLAY_ENDPOINT_FILE="$HOME/nipaplay-next/headless-data/endpoint.json"
python3 "$HOME/nipaplay-next/headless-data/harness/nipa" status
python3 "$HOME/nipaplay-next/headless-data/harness/nipa" list
python3 "$HOME/nipaplay-next/headless-data/harness/nipa" describe media.library.scan
```

Windows cmd：

```bat
set NIPAPLAY_ENDPOINT_FILE=D:\nipaplay-next\headless-data\endpoint.json
python D:\nipaplay-next\headless-data\harness\nipa status
python D:\nipaplay-next\headless-data\harness\nipa list
```

`nipa call ACTION @/absolute/path/to/input.json` 可读取 JSON 文件，省去 Windows shell
转义。例如扫描输入为 `{"root":"/mnt/d/Anime/某部剧","requestId":"scan-1"}`；Windows
路径在 JSON 中写作 `D:\\Anime\\某部剧`。用返回的 jobId 调用 `nipa watch JOB_ID`，
查看任务状态及回执。扫描建立文件记录，身份判断与批量绑定由 Agent/用户用
`media.identity.bind_batch` 完成；`media.metadata.ui_facts` 读取资料可用性。

远程操作优先通过 SSH 在目标机器上执行 Python nipa，这样连接文件和令牌始终留在
目标机器。需要 MCP 客户端跨机接入时，由用户在目标机器配置客户端认证及 SSH 隧道，
不要把连接文件纳入源码包或日志。X45 接入 Mesh 后，Mac 可以直接通过自己的
`nipa --device <唯一设备名或ID> list/describe/call/watch` 使用目标节点，
无需复制目标 endpoint 凭据；各设备加入与转发步骤见运行说明。

## Mesh 与下载宿主配置

同账号 Mesh 默认启用，协调服务地址内置为 `https://nipaplay.aimes-soft.com/mesh`；
只有宿主改过高级设置才有 `<data>/mesh.json`，里面写不同于默认的部分（`"enabled": false` 关闭）。
coordinator、roles、storage、Agent 目的设备、广播由宿主配置，不向 Agent 开放网络授权。
登录弹弹play 之前不会加入。
`broadcastDiscovery` 默认 true，可设 false。

**监听范围。** 无界面主机和桌面一样，默认监听所有网卡，并把网卡上的局域网地址（不含 docker、
utun 等虚拟网卡）报给协调服务、通过 UDP 32124 广播和 mDNS（`_nipaplay-mesh._tcp`）让同一网络里的
设备找到它：放在工作站或机柜里的主机要服务 iPad 和 MacBook，就必须能被它们连上。端口上没有
明文服务，每个连接都要先通过双向 TLS 1.3（同账号设备证书，吊销立即生效）；没有证书的连接在握手时
就被拒绝，读不到任何东西。要把它限制在本机，在 `<data>/mesh.json` 里写 `"loopbackOnly": true`
（此时不报局域网地址，只能经 SSH 转发、手填地址等候选连接），修改后重启生效。固定端口用 `port`，
不想广播用 `"broadcastDiscovery": false`。macOS 上开着“应用防火墙”时，系统会问是否允许这个程序接收传入连接；不允许的话，局域网里的连接会在 TLS 握手处超时（本机回环不受影响），需要在“系统设置 → 网络 → 防火墙”里放行。Linux 与 Windows 按各自防火墙放行监听端口（`mesh.json` 的 `port`，不写则每次随机，建议固定）。
无界面版和 GUI 一样读内置的信任根（主根加备用根两段 PEM，`lib/next/mesh/trust.dart`）；
只有设置了 `NIPAPLAY_MESH_DEV_CA` 的无界面构建才改用那份开发证书。不能从协调服务响应自动信任新 CA。
证书到期前一天起，设备只凭设备私钥向协调服务续证；弹弹play 令牌过期的无界面主机不会因此在 7 天后掉线，
只是在令牌更新前读不到新的设备名单。

宿主可在启动前初始化 headless.json 标记，用
`--enroll-token-stdin --data <独立目录>` 从 stdin 登记已登录测试账号 token。
该命令只登记并退出；没有账号密码、命令行 token 或 Agent 凭据输入能力。
私钥和 token 留在本目录的 vault，POSIX 目录 0700、文件 0600，Windows 限当前用户 ACL。

`<data>/download.json` 为宿主配置，默认 DHT、tracker、本地发现开启，公网 peers 和
PEX 按 librqbit 正常工作。可选布尔键 `dht`、`localDiscovery`、`trackers` 及初始
peer 地址数组 `peers`。配置在引擎首次初始化时固定，修改须重启。
空任务启动不初始化 BT；下载 Action 或恢复未完成任务时初始化。
下载会话及 DHT 状态在 `<data>/torrent-session`，默认下载目录在 `<data>/downloads`。
自选目录不能与只读媒体根相交，包括符号链接祖先。
`download.preview` 返回磁链元数据并释放临时预览；`download.directories` 返回默认
目录与空的 recentDirectories（本宿主不维护 Classic 最近目录）。
无界面不提供播放器和磁盘删除 Action；保留任务取消、会话移除与已下载文件。

`<data>/qbittorrent.json` 列出本宿主可用的 qBittorrent 后端：
`{"entries":[{"id":"seedbox","name":"Seedbox","address":"http://host:8080","local":false,"hasLogin":true}]}`；
`local` 为 true 表示 qBittorrent 与本宿主在同一台机器上，路径可直接读取。登录（用户名和密码）
以 JSON `{"username":…,"password":…}` 经 `--enroll-credential` 写入 vault，
命名空间 `qbittorrent`、键为条目 id。`download.add` 带 `backend: {kind: "qbittorrent", id}` 使用；
实现不依赖 Flutter（见 `lib/next/downloads/README.md`）。

## 数据、hooks 与停止

所有持久文件都位于 `--data`：

| 路径 | 含义 |
|---|---|
| `headless.json` | 格式标记；持久 mediaRoots、port、ffprobe，CLI 指定值覆盖后保存 |
| `device.json`、`next.db` | 设备身份、任务、片库、绑定、元数据、弹幕、设置、后续 |
| `mesh.json`、`download.json` | 独立宿主的组网/下载配置 |
| `program.json` | 宿主的普通用户程序授权，默认关闭，`{"enabled":true}` 后须重启；没有 Agent 设置入口 |
| `vault/`、`mesh-identity.json`、`mesh-certificate.json` | 私有凭据、Mesh 公钥身份和设备证书；不复制为第二个身份 |
| `mesh-return-targets.json`、`mesh-replay.jsonl` | 已签发原会话回传票据与防重放记录 |
| `mesh-delegations.json` | 别的设备交给本机 Nipa 的委托：每台发起设备的委托对话、每次委托的状态与回复 |
| `mesh-known-devices.json` | 本机见过的同账号设备和第一次见到的时间（无界面主机只记录，不弹窗） |
| `torrent-session/` | librqbit 会话、续传及 DHT 持久状态 |
| `harness/`、`harness-seed/` | 用户脚本与公共上游 seed；升级遵循已有 seed 合并契约 |
| `artwork/`、`downloads/`、`exports/`、`torrent_sources/` | 本宿主缓存、下载目标、弹幕导出与种子缓存 |
| `journal.jsonl`、`download-audit.jsonl` | 现有调用记录与审计文件 |
| `instance.lock` | 数据目录的进程锁；不要手动删除正在使用的锁 |
| `endpoint.json` | 本地连接地址与令牌，正常停止后删除，不可分享 |
| `running.json`、`stop.request` | 运行 PID 与该 PID 的停止请求，正常停止后删除 |

`harness/hooks/` 使用现有事件约定；POSIX 脚本要有执行权限。Windows 可以使用 `.py`
（调用已有 `python`）、`.exe`、`.cmd`、`.bat`，无需安装 POSIX shell。
定时配置在 `harness/hooks/schedules.json`，例如：

```json
[{"id":"tick","everySeconds":60,"program":"hooks/tick.py"}]
```

这些脚本按宿主进程权限运行，用户应只放自己的脚本。宿主内建扫描只读取媒体，弹幕
导出只允许写入本数据目录的 `exports`。脚本自行访问文件的权限由操作系统决定。

推荐从第二个终端停止：

```sh
./build/headless/nipaplay-headless --stop --data "$HOME/nipaplay-next/headless-data"
```

Windows 使用同一个 `.exe --stop --data D:\nipaplay-next\headless-data`。
启动终端的 Ctrl+C 也可停止；POSIX 支持 SIGTERM。等待启动终端输出 `stopped` 并退出，
域工作者、hooks 和数据库按顺序关闭。没有运行实例时 `--stop` 报错。
只有正常停止失败时，按启动日志/`running.json` 中核对过的 PID 用 `kill PID` 或
`taskkill /PID PID`；不要按程序名批量结束进程。

## 升级与回退

1. 停止自己的 PID，确认进程已退出、`endpoint.json` 已删除。
2. 在同一机器本地备份整个数据目录，保留设备身份、数据库、用户 harness、后续和回执。
3. 在新的源码目录解压新包或更新源码，以显式 package config 编译本机二进制。
4. 从新源码目录用原 `--data` 启动。Next 数据库沿用已有版本迁移；配置未指定时从
   `headless.json` 恢复，用户修改的 harness 遵循现有合并规则。
5. 若需回退程序而数据库已迁移，停止后使用升级前的整目录备份；不要用旧程序直接
   打开较新数据库，也不要单独替换 `device.json`。

源码运行不创建系统服务、计划任务或改防火墙（安装包的 `install.sh` 才建服务）。X43 实验用的数据目录已清理，留下的源码和
工具不会自行运行。

## Windows 对话宿主

`ChatHost` 的 Windows 分支直接启动原生 `codex.exe app-server`，stdio JSON-RPC，
不经过 POSIX 登录 shell，也不使用 npm 的 `.cmd` shim。可由宿主传
`codexExecutable`，或设置进程环境 `NIPAPLAY_CODEX_EXECUTABLE`；否则查找 `codex.exe`。
无需修改全局 PATH。

本次原生程序位于 `D:\nipaplay-next\x43-tools\codex\package\vendor\x86_64-pc-windows-msvc\bin\codex.exe`。
可手工准备独立目录（以下是后续操作说明，本次没有配置模型）：

```bat
set CODEX_HOME=D:\nipaplay-next\my-codex-home
set NIPAPLAY_CODEX_EXECUTABLE=D:\nipaplay-next\x43-tools\codex\package\vendor\x86_64-pc-windows-msvc\bin\codex.exe
"%NIPAPLAY_CODEX_EXECUTABLE%" app-server
```

`CODEX_HOME` 内的 provider 配置和认证须由用户决定并在目标机器准备。实验宿主传
`labRoot` 时，会强制使用该根内的 `codex-home/config.toml` 和 `temp`，不采用用户的
`~/.codex`。X43 只用空配置验证 initialize/initialized 握手及关闭，没有 thread/turn、
模型密钥或真实对话。无界面入口现在创建的是 DSH 的对话宿主（见“Nipa 在无界面主机上”），Windows 原生 Codex 的这条路径仍不接入无界面。

## Nipa 的运行环境（DeepSeek Harness）

无界面宿主可以准备并验证 Nipa 用的运行环境（运行它见下一节）：与桌面版同一份清单（`assets/next/agent/dsh-runtime.json`，Linux x64、
Windows x64、macOS arm64 已追踪），装在 `<data>/dsh-runtime/`，不动全局。

```sh
nipaplay_headless --dsh-install --data DIR   # 下载 Node.js 与精简 DSH；官方源，连不上改 npmmirror
nipaplay_headless --dsh-status  --data DIR   # 将要启动的是哪一份
nipaplay_headless --dsh-check   --data DIR   # 带 NipaPlay 插件启动，开一个线程，不调用模型
```

默认在当前目录找 `assets/next/agent`，可用 `--agent-assets` 指定。选择顺序：环境
`NIPAPLAY_AGENT_RUNTIME=dsh` 加 `NIPAPLAY_DSH_NODE` 与 `NIPAPLAY_DSH_ROOT`（自备安装）优先，
否则用 `<data>/dsh-runtime/` 里装好的；`NIPAPLAY_AGENT_RUNTIME=codex` 在此宿主被拒绝。
主程序暂时还不能编译（见交付说明），这三条命令也可不经主程序运行：
`dart run scripts/next/dsh_runtime/headless_dsh.dart install|status|check --data DIR`。

## Nipa 在无界面主机上

无界面主机和有界面的桌面一样可以运行 Nipa：宿主创建 `ChatHost`，在本机装好的 DSH 上
运行她，有自己的 harness（`<data>/harness`）、记忆、钩子和线程，各台设备上的 Nipa 各记各的。
对话宿主与桌面共用同一份实现：同一套线程存储（`harness_sessions`，键为 `dsh:<harness>`）、
回合过程存储（`<data>/turn-process/`）、后续与帮手；DSH 的数据在 `<data>/dsh-home`，
NipaPlay 的 DSH 插件由每次启动从 `--agent-assets` 写到 `<data>/agent/dsh/`。

**什么时候运行。** 同时满足才运行，缺哪一项都如实报告，不会半起：

1. 这台主机的 agent 开关开着（`<data>/agent.json`，没有这个文件就是开）。
2. 模型已设置，密钥在保险库里。
3. DSH 运行环境已装（`--dsh-install`）或由环境变量指定。
4. `--agent-assets` 指向的目录里有清单和 DSH 插件（默认当前目录的 `assets/next/agent`）。

三个文件变化（`agent.json`、`model.json`、`dsh-runtime/`）由正在运行的宿主监听，改完立即生效，
不需要重启；已在运行的宿主在下一回合开始时采用新的模型。宿主启动不等运行环境起来：
Nipa 在后台起，`app.runtime` 里 `conversationHost` 说明她现在是 `disabled`、`missing`、
`starting`、`running` 还是 `failed`，`missing` 列出缺的（`model`、`key`、`runtime`、`agentAssets`），
`reason` 给一句话。`mesh/describe` 的 `conversationHost` 和 `agent` 同样是实时的。
agent 开关关掉时宿主停掉对话进程，所有对话入口都说明原因。

**别的设备交来的任务。** 同账号设备上的 Nipa 可以用 `mesh.delegate` 把一件事交给这台主机上的
Nipa（见 [Mesh README](../../../../lib/next/mesh/README.md) 的“委托”）。主机在本机 `<data>/harness` 里开一段
对话，开头写明来自哪台设备上的 Nipa 的委托，用本机的工具做完，最后一条回复交回去；这段对话和
别的对话一样在 `chat.session.list` 里，主机上的人可以用 `./nipa chat read/say` 读它、插话。Nipa
没有运行（agent 开关关着、没设模型或密钥、没装运行环境）时，委托立即失败，原因就是上面
`conversationHost.reason` 那句话。无界面主机上的 Nipa 同样可以把事交给别的设备。
主机只记录有新设备加入（`mesh.devices` 每台设备的 `firstSeenAt`），不弹窗；要移除设备，在任何
有屏幕的设备的设置里操作。

**模型与密钥（只有主机上的人能设，Nipa 不能）。** 提供方、地址、模型名、接口（responses 或 chat）
和思考强度存在 `<data>/model.json`（与桌面同一格式），密钥进 `<data>/vault`。
命令行一次录入，密钥只从标准输入读，不出现在参数、shell 历史、日志或任何事实里：

```sh
printf %s "$KEY" | ./nipaplay-headless --data DIR --model-set \
  --provider NAME --base-url https://example/v1 --model NAME [--api responses|chat] \
  [--reasoning low|medium|high] --key-stdin
./nipaplay-headless --data DIR --model-status     # 提供方、地址、模型、有没有密钥；不含密钥
./nipaplay-headless --data DIR --model-check      # 向模型发一次很小的请求，看地址和密钥能不能用
./nipaplay-headless --data DIR --model-clear      # 删掉设置和密钥
./nipaplay-headless --data DIR --agent-disable    # 或 --agent-enable、--agent-status
```

密钥与提供方、地址绑定（与桌面同一个保险库引用）：改了地址而没有重新录入，旧密钥不会被发到新地址，
状态里 `missing` 会出现 `key`。

**对话入口。** 在主机的 harness 目录里用 `./nipa chat`（harness 的 `nipa` 会在 `headless.json`
旁找到 `endpoint.json`，不必设环境变量）：

```sh
./nipa chat say "告诉我这台机器的磁盘还剩多少" --wait 120   # 发话、等回合结束、打印回复和她执行的命令
./nipa chat say "…"                                        # 只发起，回合在后台跑
./nipa chat status --wait 55   # 回合状态（starting/inProgress/completed/failed/interrupted）；--wait 在宿主事件上等，不轮询
./nipa chat read --turns 3     # 最近几个回合：你说的、她回的、她执行的命令
./nipa chat process TURN_ID    # 一个回合的步骤：命令、退出码、输出、推理摘要（脱敏）
./nipa chat stop               # 中止正在跑的回合
./nipa chat new | main | list | switch THREAD_ID
```

它们是 Action：`chat.send`、`chat.status`、`chat.read`、`chat.stop`，加上桌面原有的
`chat.session.main/new/list/switch` 与 `chat.turn.process`、`agent.dispatch`、`agent.wake`、
`followup.*`（不再从无界面目录里过滤掉）。`chat.send` 和 `chat.stop` 是替主机上的人说话，
所以来自 Nipa 自己、帮手、钩子或别的设备的调用被拒绝并说明（她要起一个回合用 `agent.dispatch`，
稍后用 `agent.wake` 或 `followup.register`）。同一对话里已有回合时 `chat.send` 返回 `conflict`。
无界面脚本和钩子的 `agent.wake` 在本机运行 Nipa 时送到本机的主对话；宿主配置了
`agentDeviceId` 时仍按配置送到那台设备。

**主线程。** 无界面只有一个主 isolate。运行环境每条消息的读取、拆行、解码、脱敏、
回合过程的写入都在后台 isolate 里（与桌面共用的 `ChatLineReader`、`TurnProcessStore`），
主 isolate 只收结果。`headless_nipa_host_test.dart` 在回合进行期间不断调用宿主，量到的最慢一次回应记在断言里。
