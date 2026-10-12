# NipaPlay 无界面宿主（X43）

这是纯 Dart 的 Next 领域服务宿主，入口为 `bin/nipaplay_headless.dart`。
不启动 Flutter 引擎或窗口。已在 macOS、Ubuntu 24.04 WSL x86_64、Windows x64
运行源码和本机编译的 AOT 可执行文件；实验记录见 [X43_REPORT.md](X43_REPORT.md)。

当前可用：回环 MCP/`nipa`、独立片库与任务数据库、只读扫描、身份批量绑定、Bangumi
公开资料和提供的元数据、图片缓存与色调、同名 XML/JSON 弹幕索引、数据卡片、hooks、
定时脚本和持久后续事项。片库归属、资料绑定等判断仍由调用者作出。

当前缺口：Rust 下载传输、Mesh、播放器、Classic 账号与历史、TMDB 凭据配置、
弹弹play网关账号宿主、Classic 更新日历、内嵌 Agent 对话。下载 Action 保留现有任务
契约，但实际任务以 `unavailable` 失败，回执说明需要隔离的 Rust 初始化器；不会加载
Rust 下载库。后续条件可以到达 `ready`，没有对话宿主时不会执行模型决定。
GUI/Nipa 可以通过 MCP 客户端接入；现有 GUI 多设备列表还不能发现这个宿主。

## 准备程序

在依赖已经解析的本 worktree 操作；不要在主仓库构建，不运行 `pub get`。
开发使用 Flutter 3.44.6 随带的 Dart 3.12.2。运行时不需要 Flutter。

```sh
cd ~/Desktop/nipaplay-next-wt/x43-headless
~/development/flutter-3.44.6/bin/dart compile exe \
  --packages=.dart_tool/package_config.json \
  bin/nipaplay_headless.dart -o build/headless/nipaplay-headless
```

`build/headless` 必须先存在。可执行文件按目标机器的系统与架构编译，不能把 macOS
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
`--media-root`。没有媒体根也能启动，随后重启时指定根目录。
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
不要把连接文件纳入源码包或日志。X43 没有实现 GUI Mesh 接入与账号注册。

## 数据、hooks 与停止

所有持久文件都位于 `--data`：

| 路径 | 含义 |
|---|---|
| `headless.json` | 格式标记；持久 mediaRoots、port、ffprobe，CLI 指定值覆盖后保存 |
| `device.json`、`next.db` | 设备身份、任务、片库、绑定、元数据、弹幕、设置、后续 |
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

不用创建系统服务、计划任务或改防火墙。X43 实验用的数据目录已清理，留下的源码和
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
模型密钥或真实对话。无界面入口当前不创建 ChatHost；集成对话与自动执行后续是另一步。
