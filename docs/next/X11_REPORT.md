# X11：macOS 调试实验配置

2026-10-11，`next/capability-layer`。实现、构建和实验均在真实 `~` HOME 下进行。

## 1. 完成了什么

`NIPAPLAY_PROFILE=<名字>` 为 macOS Debug 实例选择独立配置，根目录固定为：

```text
~/Library/Application Support/NipaPlay/LabProfiles/<名字>
```

名字只接受 1–64 个小写 ASCII 字母、数字、下划线或连字符，首字符须为字母或数字。根目录权限为 0700。新 profile 从空状态开始，不复制真实实例的偏好、历史、登录态或 harness。Next 仍需在该实验实例中开启；实验中只在实验偏好文件中预置了开启标志和合成测试凭据。

启动方式：

```sh
NIPAPLAY_PROFILE=x11test \
  build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
```

未设置开关时保留现有路径、偏好后端、保险库实现和端口规则。Dart 使用 `kDebugMode`，原生安装入口使用 `#if DEBUG`；Release 不解析或启用此开关。已删除代码中的 `NIPAPLAY_DATA_DIR` 支持，并更新当前 Mesh 实验说明。旧报告中的该变量仅是历史记录。

窗口标题包含 `LAB [名字]`，原生启动窗口在引擎启动前即标记，主界面通过全局覆盖层显示实验角标，独立播放器窗口标题也保留标记；CLI `nipa status` 返回 profile 名字、根目录及外部文件只读状态。

### 实际写入位置审计

以下普通位置针对本机非 App Sandbox 的 macOS 实例；沙箱正式版的对应位置在容器内。不是通过改变 HOME 实现隔离。

| 状态 / 入口 | 原有实际位置或规则 | profile 中的规则 |
|---|---|---|
| Classic 历史、媒体库、缩略图、日志、插件、弹幕、本地配置 | `StorageService` → `~/Documents/nipaplay` | `<root>/data`，Classic 与 Next 都使用实验库 |
| Next SQLite、任务、回执、journal、设备 UUID、Mesh 配置/身份/证书/replay | `NextCore` → 应用数据目录的 `next` | `<root>/data/next`；已有 Mesh 私钥引用继续由保险库处理 |
| Dart SharedPreferences，包括下载路径、登录占位引用、窗口/播放设置和网络缓存 | Foundation 插件的 `UserDefaults.standard`，域 `com.aimessoft.nipaplay` | `<root>/preferences.json`；完整后端替换，串行更新、同目录暂存与 rename |
| 原生窗口/插件偏好 | `UserDefaults.standard` | 文件后端 `<root>/native-preferences.plist` |
| path_provider support / documents / library / downloads / cache / temporary | 分别为用户 Library/Application Support/bundle-id、Documents、Library、Downloads、Library/Caches/bundle-id、**Library/Caches**（temporary 不带 bundle-id） | 分别为 `<root>/support`、`documents`、`library`、`data/downloads`、`cache`、`temp`；在任何应用服务初始化前替换平台实例 |
| `Directory.systemTemp`、Rust `temp_dir`、外部播放器 ASS / IPC 临时文件、media_kit 引用文件 | 系统临时目录 | 在引擎启动前设置 TMPDIR；实测 Dart media_kit 文件位于 `<root>/temp`。Foundation 已缓存的 NSTemporaryDirectory 仍可能指向系统目录，其写入被内核限制拒绝 |
| 默认下载文件 | `StorageService` 的 `downloads`；保存的自定义目录优先 | 默认 `<root>/data/downloads`；选择 profile 外的输出路径不能写入 |
| 桌面 torrent 会话 | Rust `default_session_dir` → `~/Library/Application Support/NipaPlay/torrent_session` | Dart 显式传入 `<root>/support/torrent_session`，使用已有 sessionDir API |
| rqbit DHT 缓存与端口 | librqbit-dht 的 ProjectDirs → `~/Library/Caches/com.rqbit.dht/dht.json`，可能复用保存端口 | `<root>/support/torrent_session/dht.json`；明确指定随机端口；实验会话关闭共享 LSD 6771 广播 |
| 钥匙串 | Rust 固定服务 `com.nipaplay.credential-vault.v1`，账号为长度前缀的 namespace + key | 保留服务名，namespace 强制加 `lab:<名字>:`，适用于偏好、插件、媒体服务、metadata、Mesh 等全部 DesktopCredentialVault 调用 |
| Agent 连接凭据 | macOS `~/.config/nipaplay/endpoint.json` | `<root>/endpoint.json`，仍为 0600，仍位于 harness 外 |
| 默认 harness 与种子 | `~/nipaplay-harness`、`<data>/next/harness-seed` | `<root>/harness`、`<root>/data/next/harness-seed`；profile marker 让新 shell 中的实验 `nipa` 自动连接所属实例 |
| Agent HTTP/MCP | 默认 TCP 47811，旧 Debug 端口覆盖 | profile 始终使用系统分配端口，包括显式传入或继承旧端口覆盖的情况；地址保存在自身连接文件 |
| 单实例锁、连接元数据 | path_provider support 下的 `single_instance`，控制 socket 原本已是随机端口 | `<root>/single_instance`；同名 profile 单实例，不同 profile 和真实实例互不占锁 |
| Mesh TCP 与 UDP discovery | 默认监听 47812，UDP 32124 广播 | TCP 使用系统分配端口；不参与真实实例的 UDP discovery，Mesh 控制面候选仍可用 |
| Web/远程访问与 LAN discovery | Web 设置端口，默认 1180；UDP 32123 | Web 每次独立分配端口；不回应真实实例的 UDP discovery |
| 插件媒体代理、torrent 流、Dart VM service | 原本已经使用系统分配端口 | 保持随机分配；连接凭据和所属进程独立 |
| MoltenVK ICD | `AppDelegate` → `~/Library/Caches/vulkan/icd.d/MoltenVK_icd.json` | `<root>/cache/vulkan/icd.d/MoltenVK_icd.json` |
| 直接文件导出、权限写入探测、任意下载目标、原生/第三方缓存、子进程写入 | 不全经 StorageService 或 path_provider；Metal 还会尝试系统用户缓存目录 | macOS 内核拒绝 profile 外的文件写入；直接子进程继承限制。无法改默认路径的原生缓存写入也被拒绝，未放行共享用户缓存目录 |

主要实现入口：[lab_profile.dart](../../lib/utils/lab_profile.dart)、[SandboxMigration.swift](../../macos/Runner/SandboxMigration.swift)、[DesktopCredentialVault](../../lib/security/desktop_credential_vault.dart)、[torrent.rs](../../rust/src/api/torrent.rs)。

## 2. 决策

- 名字统一要求小写，避免 macOS 大小写不敏感目录把两个不同保险库 namespace 指向同一数据目录。
- 在原生 `awakeFromNib` 中，迁移、插件注册和 FlutterEngine 之前安装 profile；Dart 在 binding 初始化之后、任何偏好或服务读取之前接入后端。profile 跳过真实容器迁移。
- 采用 macOS 进程写入限制：允许读取真实媒体，允许在 profile 内写入，拒绝在其他路径创建、修改、删除或通过符号链接写入文件。`/dev/null`、`/dev/tty` 的输出不属于持久数据。它覆盖 Dart、Rust、原生库及应用直接启动的 hooks/工具。
- 固定根目录、验证名字和拒绝根目录符号链接，避免环境变量的名字变成路径选择器。`NIPAPLAY_LAB_ROOT` 是原生安装成功后提供给 Rust 的内部标记；启动时清除外部同名值，不是第二个用户配置开关。
- macOS legacy Keychain API 从调用进程写数据库。为使保险库在文件写入限制下可用，在安装限制前启动同一可执行文件的专用 broker。它只接受管道中的 read/write/delete，自己构造 `lab:<profile>:` namespace，不接受服务名或完整账号。没有 HTTP 端口，不访问真实实例的账号；父进程消失时退出，即使钥匙串授权操作正在等待。正常实例继续使用原 Rust 保险库。
- Agent、Mesh、Web 和 DHT 都交由系统分配端口，避免名字散列碰撞或占用用户端口。实验 LAN 广播关闭，连接经自身 endpoint 文件或 Mesh 控制面获得。
- profile 是启动配置，运行中不能安全切换整个持久状态集合；通过 `nipa status` 提供 Agent 可读身份，没有新增仅 GUI 可操作的设置。
- 本轮实现 macOS Debug profile。其他平台的 Debug 启用此变量会在应用核心初始化前报不支持；没有提供仅隔离部分状态的实现。未设置变量的其他平台保持原行为。外部独立启动的 Codex/其他应用不继承 NipaPlay 进程限制；NipaPlay 自身和直接子进程的写入边界已覆盖。

## 3. 实验与真实输出

### 构建与约束检查

使用 Flutter 3.44.6；没有运行 pub get，没有新增依赖，没有对主仓库 commit/push。应用自身初始化实验 seed/harness 的 Git 历史是既有行为，全部位于实验根目录并已清理。`macos/Podfile.lock` 在任务开始就有 Erika 版本的未提交修改，本任务保留了它。

```text
$ ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
    ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app

$ ~/development/flutter-3.44.6/bin/flutter analyze --no-pub <修改的 Dart 文件>
Analyzing 13 items...
No issues found! (ran in 3.1s)

$ ~/development/flutter-3.44.6/bin/flutter test --no-pub \
    test/lab_profile_test.dart test/next/agent_endpoint_test.dart \
    test/next/harness_repository_test.dart test/security/credential_store_test.dart \
    test/torrent_session_storage_test.dart
00:02 +27: All tests passed!

$ git diff --check
# 无输出，退出码 0

$ rg -n NIPAPLAY_DATA_DIR lib macos/Runner assets/next/harness
# 无匹配
```

测试守住名字/路径边界、并发偏好更新不丢键、其他偏好文件不变、现有凭据语义、端点与 harness 契约、torrent 迁移数据约束。完整 macOS 构建也编译了 Rust 和 Swift 修改。

将相同原生 profile 源码编译为不带 DEBUG 的探针，设置合法和非法环境变量，均不创建 profile 或写入状态：

```text
$ NIPAPLAY_PROFILE=x11test /tmp/x11-native-release
profile ignored: active=false; no state written
$ NIPAPLAY_PROFILE=../escape /tmp/x11-native-release
profile ignored: active=false; no state written
```

没有启动或修改 `/Applications/NipaPlay.app`；没有按 bundle id 启动/退出应用。

### 真实系统的只读边界

原生探针使用与应用相同的安装入口；由观察脚本预先创建 profile 外的临时哨兵文件，尝试普通写入、符号链接写入及子进程 touch，并读取真实 `/Volumes/Media`。没有写真实媒体。

```text
[LabProfile] name=x11test root=~/Library/Application Support/NipaPlay/LabProfiles/x11test writeSandbox=true
native preferences readback=lab-only
inside write=true
outside read=real-readonly-sentinel
outside write denied: You don’t have permission to save the file “x11-readonly-sentinel.txt” in the folder “tmp”.
symlink escape denied: You don’t have permission to save the file “outside-link” in the folder “x11test”.
touch: /tmp/x11-readonly-sentinel.txt: Operation not permitted
child outside write exit=1
real media directory read=true entries=11
temp=/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/
```

最后一行是 Foundation 缓存的原生临时目录，不能把设置 TMPDIR 等同于所有原生 API 都已改路径。实验观察到其 profile 外写入被内核拒绝；应用自己的持久写入路径和实际 Dart 临时文件已进入 profile。

broker 另用仅属于实验 namespace 的合成值验证写、读、删除与 EOF 生命周期，未打印值：

```text
probe write responseKeys= []
probe read responseKeys= ['value']
probe readback matches= True
probe delete responseKeys= []
probe read responseKeys= []
probe readback matches= False
broker exits on EOF= 0
```

### 与真实实例并行

最终窗口使用同一个已完成构建的二进制启动。环境 HOME 为 `~`；故意给两个实验进程都继承 `NIPAPLAY_AGENT_PORT=47811`，确认 profile 覆盖旧端口选择。

```text
2026-10-11T12:18:16.895321 x11test PID 25451 HOME ~
2026-10-11T12:18:16.896384 x11peer PID 25452 HOME ~

REAL 25337 25336 Sun Oct 11 12:17:10 2026 /tmp/NipaPlay-real.app/Contents/MacOS/NipaPlay
real profile= <unset>

PID 25451 profile x11test URL http://127.0.0.1:50780/harness
PID 25452 profile x11peer URL http://127.0.0.1:50779/harness
```

真实进程不是本实验启动的进程。只查询其 PID、监听 socket 和窗口，不调用其 Agent Action，不终止或重启它。真实进程的窗口与两个实验窗口同时存在：

```text
PID=25337 window=40676 title=播放器
PID=25451 window=40683 title=NipaPlay · LAB [x11test]
PID=25452 window=40684 title=NipaPlay · LAB [x11peer]
```

查看实验窗口截图，右上角明确显示 `LAB [x11test] · 外部文件只读`，首页是实验空媒体库。

在没有 PROFILE 和 ENDPOINT_FILE 环境变量的新 shell 中运行各实验 harness 的 CLI，两个返回状态均为 running：

```json
{"status":"running","profile":{"name":"x11test","root":"~/Library/Application Support/NipaPlay/LabProfiles/x11test","externalFiles":"readOnly"},"version":"1.11.10","repository":"~/Library/Application Support/NipaPlay/LabProfiles/x11test/harness","actions":67,"tasks":{"total":0,"byState":{},"activeTotal":0,"active":[]}}
```

这里摘录响应的状态字段；原响应另含 harnessSeed，已有实验 harness 保持自己的历史，显示 `behind`，没有被新种子强制改写。

Agent 在 x11test 写实际 Classic 偏好，再从另一个实验实例读同一个设置：

```text
x11test seek.stepSeconds before: value=11.0 revision=1
settings.set -> status=completed value=12.0 revision=2
provenance: changedBy=harness_cli origin=harness_cli reason="X11 final isolation probe"
x11peer seek.stepSeconds: value=10.0 revision=0
```

其他端点/锁检查：

```text
x11test token -> x11peer HTTP 401
duplicate x11test launch exit= 0
original x11test still running= True
original x11peer still running= True
```

回环请求使用禁用代理的 urllib opener；原 `nipa` 已显式使用 `ProxyHandler({})`。

实际 torrent 初始化输出：

```text
[nipaplay_torrent] init_session create session: download_dir="~/Library/Application Support/NipaPlay/LabProfiles/x11test/data/downloads", session_dir="~/Library/Application Support/NipaPlay/LabProfiles/x11test/support/torrent_session"
DHT file exists= True
```

实际端口对照，包含独立 DHT 持久化记录：

```text
global DHT mtime 2026-10-11 12:19:11.304129 addr [::]:60376
x11test DHT mtime 2026-10-11 12:19:19.312144 addr [::]:62791
x11peer DHT mtime 2026-10-11 12:19:19.308923 addr [::]:60750
NipaPlay 25337 ... UDP *:60376
NipaPlay 25451 ... UDP *:62791
NipaPlay 25452 ... UDP *:60750
```

### 真实状态启动前、运行时、清理后核对

偏好使用 `defaults export <域> -`，解析后排序序列化计算 SHA-256，不把偏好值输出到报告。文件树指纹包含相对路径、权限、大小、mtime_ns 和文件内容 SHA-256；不计访问时间。钥匙串只用 `security dump-keychain -a`，从内存中的输出筛选固定 service 的账号名和数量，没有使用 `-d`、读取或输出真实条目的秘密。连接文件只记录权限和指纹，不输出令牌。

最终受控区间的两个偏好域都是 427 个键，启动前、运行时、清理后 SHA-256 均为：

```text
com.aimessoft.nipaplay
~/Library/Containers/com.aimessoft.nipaplay/Data/Library/Preferences/com.aimessoft.nipaplay
8c829c125eab311b5f9f97450eb78d94b259ea30438eb320463fade7f77f8cb1
```

| 真实位置 | 启动前条目数 | 启动前 SHA-256 | 运行时 / 清理后 |
|---|---:|---|---|
| `~/Documents/nipaplay` | 503 | `57ac65158c9eaf035a676ea53cb66a34ae0df2755502f9502e9eee57c8703c74` | 相同 / 相同 |
| `~/Library/Application Support/com.aimessoft.nipaplay` | 5 | `61701f0d5ebd86c8407146037bd59f9f6d586f59a98128328f73f9d54f2f5aed` | 相同 / 相同 |
| `~/Library/Application Support/NipaPlay/torrent_session` | 6 | `d15e10b110b46cfe3e70ab15505a25811860a0b79474a478ab16e3bdadf801eb` | 相同 / 相同 |
| 容器 `Data/Documents` | 535 | `301ed02634a632c7eec39487de17c21de4d4927e91a04ef3bd4476ae0f79a9c3` | 相同 / 相同 |
| `~/.config/nipaplay/endpoint.json` | 1 | `d39d48f2313d0d4a3b51ace9ce44177f5d32a3a666d25df0d6430b81475e49fa` | 相同 / 相同 |
| `~/nipaplay-harness` | 251 | `e8ecd683f46e92945d694074209d2405b66ffb3771e035b4907f63ec938362c2` | 相同 / 相同 |
| `~/Library/Caches/vulkan` | 3 | `01b87f4eaf58b011763f43b23819b0db626df1b785dcac86c4149d2a0b070700` | 相同 / 相同 |

附加检查的 `~/Library/Caches/com.aimessoft.nipaplay`、`~/Library/Preferences/com.apple.security.plist` 和应用 Saved Application State 目录均保持不存在。

钥匙串原有账号名，启动前和清理后完全相同（10 条）：

```text
11:preferencesdandanplay_remote_api_token
11:preferencesdandanplay_token
15:server_profiles1771498139998
15:server_profiles1776489862978
15:server_profiles1776489944190
15:server_profiles1782631706009
4:meshb4288e91723e6216e06fab532a14c951e43f39bb18f6cd9cda4a4f5400e85a78
4:mesheea59da682350d20669521616b62a82036b71721c44d65e06ea4510ac98bed92
5:agenttoken
8:metadatatmdb
```

运行时仅多出以下两条合成测试凭据，原有 10 条仍完全保留：

```text
vault counts before/running= 10 12
23:lab:x11peer:preferencesdandanplay_token
23:lab:x11test:preferencesdandanplay_token
```

不能把所有用户缓存都报告为“不变化”：仍在运行的真实实例每分钟更新自己的全局 DHT 缓存。其记录端口 60376 与真实 PID 的 socket 相同，实验分别写自身目录的 62791、60750；实验主进程的内核规则也禁止写全局路径。指定的真实偏好、数据、原有钥匙串条目、endpoint 和 harness 均未改变。

### 清理

```text
terminated only x11test PID 25451
terminated only x11peer PID 25452
broker parent-lifecycle cleanup: exited [25503, 25504]
deleted only lab account 23:lab:x11peer:preferencesdandanplay_token
deleted only lab account 23:lab:x11test:preferencesdandanplay_token
removed only ~/Library/Application Support/NipaPlay/LabProfiles/x11test
removed only ~/Library/Application Support/NipaPlay/LabProfiles/x11peer
real PID 25337 still running= True

after cleanup preferences unchanged= True
Documents/nipaplay unchanged= True
Library/Application Support/com.aimessoft.nipaplay unchanged= True
Library/Application Support/NipaPlay/torrent_session unchanged= True
Library/Containers/com.aimessoft.nipaplay/Data/Documents unchanged= True
.config/nipaplay/endpoint.json unchanged= True
nipaplay-harness unchanged= True
after cleanup original vault names/count identical= True count= 10
profile dirs absent= True
remaining NipaPlay processes:
25337 1 /tmp/NipaPlay-real.app/Contents/MacOS/NipaPlay
```

### 意外、失败和验证范围

1. 首次构建漏导入 SharedPreferences 接口的类型文件，编译失败；补齐后 analyze/test/build 通过，没有改依赖。
2. Foundation `.atomic` 会使用 profile 外的替换临时目录；MoltenVK 写入第一次被拒绝。改为同目录暂存加 rename，最终输出 `已配置 bundled MoltenVK ICD`，文件确实在 profile cache。
3. 首次直接在受限进程调用 legacy Keychain API，合成凭据写入返回 `vault_operation_failed`。实现专用 broker 后观察到两个独立条目，读写删和清理验证成立。
4. 在中途重建 Debug 二进制后，既有实验钥匙串条目触发 macOS 授权等待，应用停在启动中。采样显示等待点是 `LabVaultBroker.line`，不是 torrent/DHT。退出仅实验 PID、清理仅合成实验条目，用同一最终构建重新完成验证。保留正常 macOS 凭据授权语义；持续复用 profile 时，调试签名改变仍可能要求用户授权**该实验条目**。
5. 整个长会话的最早和最终文件树并非全部相同：真实目录出现其他启动 PID 17958/18567 的日志和锁，真实 harness 的豆瓣工具也在期间修改过。这些 PID 不在本实验启动/退出清单内，无法用全会话指纹宣称零变化。最终改用实际启动前的独立基线；该区间指定状态全部相同。真实实例最终位于名字带 `-real` 的包，原先只匹配 `NipaPlay.app` 的进程筛选漏掉它，已改为匹配可执行文件尾部。
6. 启动输出还包含 universal_gamepad/audioplayers 的 MissingPluginException。未改变插件或依赖；首页窗口、实验角标、Agent、设置写入与下载会话仍成立。本轮没有验证视频播放、完整 Mesh 两节点登录/控制面链路或外部播放器功能。
7. Metal 会尝试写系统用户缓存，内核拒绝这些共享目录写入；截图验证实验界面可呈现。没有放行这些路径。本轮只允许实验访问真实媒体，没有调用真实实例的 Action、播放真实实例的视频或读取其钥匙串秘密。

## 4. 需要主控决定的问题

没有。本轮完成 macOS Debug 的隔离与真实并行实例实验；其他平台的 profile 支持属于后续工作，当前明确拒绝启用。
