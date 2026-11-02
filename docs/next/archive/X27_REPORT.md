# X27：播放与本机能力

工作目录：`~/Desktop/nipaplay-next-wt/gaps-a`，分支 `next/gaps-a`。已阅读 TEAM、RESEARCH、2026-10-12 复审 SUMMARY 和 m1/m2/m3/m8 报告。本报告区分接口实现、真实效果和未完成验证；测试通过不等于功能成立。

## 1. 完成了什么

| 范围 | 能力与行为 |
|---|---|
| 发送弹幕 | `danmaku.send`：内容、滚动／顶部／底部、RGB 自选颜色、当前视频时间；复用 Classic 发送服务及成功后的本地轨道回显。登录仍由用户完成。 |
| 普通音量、亮度 | `playback.levels` 批量读写；同时注册 `player.volume`、`player.brightness`，播放状态带对应字段。0–1，桌面音量沿用 `player_volume`，手机使用系统音量和应用亮度；桌面亮度为 null，写入明确失败。 |
| 窗口 | `window.state`、`window.control`：主窗口、独立播放器、外部控制台／弹幕列表；全屏、置顶、显示、最小化、最大化／还原、视频尺寸适配、独立播放、画中画、关闭、托盘。macOS 独立窗口全屏加 Next 专用原生适配。 |
| 退出 | `app.quit`：先返回并记录计划回执，一秒后调用 Classic 正常退出。描述明确：结束的是服务当前 Agent 连接的实例，其端点也会消失。 |
| 外部会话弹幕 | `playback.external.danmaku_state`、`playback.external.danmaku`：样式、任意有限秒数偏移、批量关键词／正则／发送者屏蔽及移除、与用户设置双向同步；读接口返回分页弹幕及屏蔽状态。 |
| 扫描目录 | `media.library.roots.list/add/remove/cleanup`：批量注册、Classic 权限选择器、移除关联历史和目录 hash 缓存、清理失效目录。保留视频文件。 |
| Classic 扫描 | `media.library.scan_classic`：复用 Classic 智能目录扫描、识别、历史持久化、跳过已匹配未看文件选项；返回各目录的状态和失败文件。现有 `media.library.scan` 的 Next 索引语义不变。 |
| 删除历史 | `history.remove`：路径和作品 ID 的并集，批量、去重，支持负数自定义作品 ID。单条调用 Classic Provider，整部调用 Classic 作品删除和同步墓碑；保留视频文件。 |
| 复审部分覆盖 | 修复外部程序路径只能位于媒体授权目录、偏移被限于 ±30 秒、外部控制台窗口模式只保存值、Classic 本地扫描没有识别语义这四项。新增 `playback.external_player_path`，可检测 mpv 或发起 Classic 程序选择器。 |

所有新增写能力走现有 invocation/journal，回执投影进 activity。音量及写回用户样式经设置来源记录，保留 origin、reason、invocationId 和前后值。活动标题使用“调整窗口完成”“删除观看历史完成”等短句。Next 开启时外部控制台隐藏剧集 ID、进程号、文件路径、发送者 ID 和生成加载过程说明；Next 关闭时使用原有 Classic 展示。

没有新增确认参数或删除文件能力。历史、目录登记、样式和窗口操作直接执行。文件实体删除的确认机制交给 D 批次，本批没有绕过它的入口。

## 2. 决策与边界

- 工具按原语提供：目录登记和扫描分开，历史删除接受并集批量，外部会话控制与写回设置分开。没有自动登录、自动选播放器、自动改内核或编排任务流程。
- `close` 的语义明确：主窗口隐藏并保留端点；独立播放器关闭后回到主窗口；外部控制台关闭不结束 mpv。结束实例单独用 `app.quit`。Agent 的操作不弹退出选择框。
- 画中画退出后仍保留独立窗口；关闭独立窗口或 `detached:false` 才回主窗口。复用同一个 Classic player，播放进度不复制。
- 窗口状态返回的是调用结束时的实际状态；原生全屏、关闭和显示可能仍在动画中，因此紧随回执的状态可能尚未变化。实验通过后续读取和原生窗口观察核验。
- 外部样式先校验所有数值和规则，再改会话。非法正则不会先修改 opacity。`sync:to_user` 用 Classic setter，轮廓宽度保留 Classic 归一化；同步写入排空来源记录后才返回。
- 音量与亮度组合在桌面预先拒绝亮度，避免先改音量再失败。普通音量控制的是内部播放／手机系统，外部 mpv 音量不在本工具语义中。
- 初次真实实验发现冷配置下 Provider 已写 SQLite，但 WatchHistoryManager 仍按旧 JSON 读取；表现为播放身份消失、删除返回零。修正为仅在 **Next 端点启用前** 调用现有 Classic 初始化／迁移并切换 Manager，关闭 Next 的启动路径不变。
- macOS 独立窗口原本是非激活无标题窗口，直接调用 Flutter 全屏没有效果。新增 `setAgentFullscreen`，仅 Next 调用时临时调整窗口 style/collectionBehavior；退出全屏恢复原配置，Classic 的原有入口未改。
- 实验辅助 VM 扩展只在 Debug 且 `NIPAPLAY_PROFILE` 生效时注册。它只创建配置内的合成历史／缓存和读取 Classic 状态，拒绝向配置外植入媒体记录，不接触登录凭据。

## 3. 真实实验与证据

复现脚本：[experiment.py](evidence/x27/experiment.py)，原生观察器：[windows.swift](evidence/x27/windows.swift)。脚本直接启动本 worktree Debug 可执行文件，用新的实验配置写沙盒、合成 120 秒视频、四条历史和两条缓存弹幕。mpv 使用实验目录中的 wrapper，以 `--no-config --hwdec=no` 启动。代理变量移除，回环直连；没有读取服务器凭据、真实账号、真实媒体库或登录钥匙串。每轮按记录的 PID 结束进程并删除实验目录。

`operations.json` 保存逐次真实 `nipa` 输出及独立 Classic 观察；先前失败及修正前的轨迹单独保留。以下 JSON 为真实输出的字段节选，完整结构见证据文件，不把节选当完整接口 schema。

### 3.1 音量、登录条件、参数约束

实际调用 `playback.levels {"volume":0.25,"reason":"实验音量"}`，Classic 独立观察：

```json
{"volume":0.25,"playerVolume":0.25,"savedVolume":0.25}
```

随后调到 0.8，`playback.state` 也返回 `volume:0.8`；设置来源为：

```json
{"key":"player.volume","previousValue":0.25,"value":0.8,"origin":"harness_cli","reason":"实验音量回读","revision":2}
```

组合传入 `volume:0.2, brightness:0.4` 在 macOS 返回 `unavailable`，音量保持 0.8。

播放已识别实验视频时发送顶部黄色弹幕，真实结果：

```json
{"status":"failed","error":{"code":"unavailable","message":"Complete Dandanplay login through accounts.login first.","retryable":false}}
```

非法颜色返回 `invalid_input`。没有登录、没有向线上发布测试弹幕。因此这证明了真实播放身份和登录门槛，**没有证明线上发布成功和成功回显**。

### 3.2 外部会话的实际弹幕及 ASS

首轮错误地保留 `skipMatching:true`，弹幕数为零；单读样式不足以证明功能。修正实验开关后装载两条缓存弹幕。早期实验名过长还令 Unix socket 长度达到 104 字节、遥测失败；缩短实验名后同一个 Classic mpv 会话真实返回：

```json
{"active":true,"player":"mpv","processId":86606,"paused":false,"positionMs":400,"telemetryAvailable":true,"durationMs":120000}
```

初始弹幕实际为：

```json
{"total":2,"items":[{"text":"蓝色的天空","timeMs":3000,"blocked":false,"senderId":"fixture-one"},{"text":"实验弹幕","timeMs":5000,"blocked":false,"senderId":"fixture-two"}]}
```

批量修改 opacity 0.55、字号 36、描边 2、堆叠 true、偏移 40.125 秒，加关键词“蓝色”、正则 `^实验` 和发送者规则。回读的起始时间为 43125／45125 ms，两条都 `blocked:true`；读取 Classic 实际生成文件：

```json
[{"name":"danmaku_1791741593014.ass","dialogueCount":0}]
```

再传 `style.opacity:0.1` 和非法正则 `[`，调用失败，回读 opacity 仍为 0.55，ASS 仍为零条。写回用户设置后，Classic 观察和设置来源都得到字号 36、opacity 0.55、偏移 40.125，reason 为“保存实验会话样式”。改用户 opacity 为 0.75，再 `sync:from_user`、偏移置零、批量移除三个规则：

```json
[{"name":"danmaku_1791741593014.ass","dialogueCount":2,"hasFixtureOne":true,"hasFixtureTwo":true}]
```

证据：[external-operations.json](evidence/x27/external-operations.json)。这轮有实际 mpv 遥测和实际 ASS 改写，结束前关闭控制台后 mpv 仍在播放。末轮另记录无屏蔽时的 Style／Dialogue 行，验证样式和延时进入生成文件。

### 3.3 历史和扫描目录

真实注册三个实验目录，空目录 Classic 扫描完成。冷配置修正后，Manager 能读到四条刚植入的 SQLite 历史，`playback.state` 正确带 `animeId:2701, episodeId:270101`。

单条历史删除返回 `removedCount:1`，按作品 2702 删除返回 `removedCount:2`。独立 Classic 观察分别剩三条和一条，未选中记录的续播位置保留；移除目录 a 后剩余关联记录消失，视频仍在磁盘。删除实验空目录后 `roots.cleanup` 清掉该失效登记，内存和偏好仅保留目录 b。脚本对每个视频实体做存在性断言。

证据：[second-operations.json](evidence/x27/second-operations.json)、[external-operations.json](evidence/x27/external-operations.json)，最终版本也重复这些调用。

### 3.4 窗口、画中画和退出

真机已调用主窗口全屏、置顶、尺寸适配、最小化、显示、最大化、还原、托盘、隐藏；独立播放器显示／置顶／适配／全屏／关闭和画中画进入退出；外部控制台及列表显示关闭。全屏适配修正后，独立 `window.state.player.fullscreen` 为 true，原生窗口为 1512×949。末轮画中画回读 true、alwaysOnTop true，Classic 内容尺寸 517×291，退出后恢复 960×540，关闭后主窗口继续显示同一视频。

但是窗口连续切换期间出现了进程崩溃，不能把“调用完成”都算作稳定通过，详见下节。

最终版本以 Erika 原生视频内核完整运行所有动作，实际回执与进程观察：

```json
{"scheduled":true,"processId":5776,"delayMs":1000}
{"pid":5776,"exitCode":0,"journalHasQuit":true}
```

这验证了回执落入 journal 后当前实验实例正常结束。`state.query(view:activity)` 返回“删除观看历史完成”“移除扫描目录完成”“清理失效目录完成”等标题，来源为 `harness_cli`。整轮输出见 [operations.json](evidence/x27/operations.json)、[experiment.log](evidence/x27/experiment.log)，节选见 [results.json](evidence/x27/results.json)。

截图已实际查看：[独立窗口全屏](evidence/x27/detached-fullscreen-49693.jpg) 看到了铺满窗口的视频；[外部控制台](evidence/x27/external-windows-49798.png) 不显示剧集 ID／PID／路径；[弹幕列表](evidence/x27/external-windows-49800.png) 能看到两条弹幕和颜色。另有 `ui.capture` 的 playback/fullscreen/returned/final 图；Erika 视频是原生层，`ui.capture` 明确不包含它，因此视频效果以本实例所属窗口的原生截图补证。

### 3.5 意外、失败与尚缺的实验

- 冷历史 Manager/SQLite 不一致已修复；旧轨迹 `initial-operations.json` 保留。
- 外部弹幕为零和实验 Unix socket 路径过长均是实验条件错误，分别保留早期轨迹，没有以空列表或失败遥测冒充验证成功。
- MDK 和 mediaKit 的视频纹理窗口连续切换均复现崩溃：典型退出码 `-11`，Flutter raster 栈 `EmbedderExternalTextureMetal::ResolveTexture`，另有 `NSInvalidArgumentException`，向已失效对象发送 `width`。MDK 硬解／软解、mediaKit 都有失败记录，分别见 `fourth-operations.json`、`mdk-software-operations.json`、`mediakit-operations.json`。后两次失败均在窗口动作链中，没有触及真实用户配置。本批未修改播放器依赖或为 Agent 自动切换内核。
- 实验脚本早期把内核偏好写成字符串，实际存储要求枚举索引；日志确认早期运行的是默认 MDK。修正脚本后分别使用索引 2 的 mediaKit 和索引 3 的 Erika。Erika 的最终版本整轮通过，说明窗口工具在该原生视频路径中成立；不能外推成 MDK／mediaKit 稳定。
- 发送弹幕的成功线上路径需用户在一次性测试账号中完成登录，目前未做。手机音量／亮度、Android SAF、Harmony 目录权限，以及其他桌面系统需对应设备复验。
- Classic 识别扫描实际只验证了空目录；需要已登录账号才能进一步验证真实识别。目录选择器和程序选择器已接 Classic，但无人操作的实验仅验证显式路径登记和自动检测 mpv。

## 4. 验证、共享文件及需要主控决定的问题

最终验证结果：**461 通过、4 跳过**，完整日志 [tests.log](evidence/x27/tests.log)；11 个相关 Dart 文件 analyze **No issues found**，见 [analyze.log](evidence/x27/analyze.log)；最终 Debug 构建成功，见 [build.log](evidence/x27/build.log)。完整 Next 及下列 Classic 回归一起运行，覆盖本批涉及的持久化、设置和现有窗口服务；不使用模拟测试判定 GUI 成立：

```sh
flutter test --no-pub test/next \
  test/volume_controller_numeric_result_test.dart \
  test/external_player_settings_test.dart \
  test/external_player_console_service_test.dart \
  test/external_player_window_service_test.dart \
  test/desktop_player_multiview_test.dart \
  test/desktop_exit_handler_test.dart \
  test/watch_history_model_test.dart \
  test/watch_history_database_migration_test.dart \
  test/watch_history_startup_test.dart \
  test/watch_history_legacy_startup_test.dart \
  test/torrent_completed_scan_test.dart \
  test/danmaku_style_test.dart \
  test/danmaku_outline_width_level_test.dart \
  test/danmaku_track_timing_test.dart
```

使用 Flutter 3.44.6，回环绕过代理。构建使用 worktree、`--debug --no-pub` 和 `/tmp/nipa-next/x2-erika-cache`；没有在主仓库构建、没有运行 pub get。缺少 package graph/Swift Package 生成物时仅复制与相同 lock 匹配的已生成文件，未改依赖声明。构建自动改写的 `macos/Podfile.lock` 在交付前恢复。没有 commit/push。

共享文件的改动尽量局部：`next_runtime.dart` 仅注册能力、端点启动前的 Classic 历史接合、实验扩展；`application_settings.dart` 仅本批设置；`activity.dart` 仅本批动作白名单和标题；播放 snapshot/port 仅追加 levels。Classic 的 `video_player_state.dart` 增加严格 setter，原音量保存仅加来源记录；`desktop_exit_handler.dart` 仅公开原有三个动作；`external_player_console_page.dart` 的文字显示以 Next 开关为条件；`MainFlutterWindow.swift` 只新增 Next 全屏方法和原窗口配置恢复。没有修改 B/C/D 的业务能力。

需要主控决定的问题：窗口动作已可调用并观察到效果，但 Flutter 视频纹理在连续切换后仍有崩溃。是否另开 Classic／播放器运行时修复任务（可能需要修改依赖实现），并将此问题作为窗口能力稳定性验收的阻塞？本批不能在禁止改依赖和要求 Classic 行为不变的约束下将该风险宣称已解决。其余产品决策：没有。
