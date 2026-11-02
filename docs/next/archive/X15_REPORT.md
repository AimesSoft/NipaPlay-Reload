# X15：播放期间的 Agent 悬挂与 windowed 启动

2026-10-11，worktree `~/Desktop/nipaplay-next-wt/playback-hang`，分支 `next/playback-hang`。

## 1. 完成了什么

定位并修复了本机能够复现的播放悬挂：**macOS 平台主线程同步等待弹幕渲染线程，不是 MDK 的 pause 请求本身在等待，也不是 Agent 端口失效。** 未修改构建在可见窗口播放本地文件后，`playback.open` 返回成功，随后 `playback.state` 超过实验客户端的 8 秒期限。采样时，主线程停在 `RustLibNipaplayPlugin.setFrame → next2_engine_set_frame → reply_rx.recv()`；弹幕线程停在同步 MSDF 字形请求上。

现在 `setFrame` 的阻塞 FFI 调用在已有后台串行队列执行，结果回到主线程交给 Flutter。播放和端点不再被字形生成占住。本次四组真实播放实验共 642 次请求全部返回，包含 MDK / erika × 本地 MP4 / 临时 Jellyfin；每组 25 轮暂停、恢复、seek 和状态读取。

修复了 Classic 和 Next 共用的 windowed 启动路径：直接使用现有屏幕插件的原生通道，显式传入窗口的缩放比例，避免插件 Dart 包装层的 `views.single`。保留现有窗口尺寸、鼠标所在显示器选择、主显示器回退与五种启动位置。Next 关闭的 Classic 实验实例正常显示 960×600 主窗口，右下角启动位置生效。

没有更改依赖、播放器内核默认值、Classic 播放控制和持久数据格式。没有 commit、push 或在主仓库构建。

## 2. 决策

### 从线程阻塞处修复

Agent 的 `playback.state` 读取应用快照；`playback.set_paused` 和 `playback.seek` 经 Classic 播放入口提交控制。它们没有等待弹幕 `setFrame`。原生桥却在 Flutter 平台线程同步等待 Rust 渲染队列，阻碍该线程继续处理事件和平台请求。

`next2_engine_set_frame` 把输入发到渲染队列，然后以无期限的 `recv()` 等待确认。渲染队列还要绘制前一帧；首次遇到未预热的字符时，`MsdfWorkerPool.rasterize_sync` 逐字等待，单次等待上限 2 秒，多个字符及工作队列会累计长时间停顿。采样中的 MSDF 工作线程正在计算字形。这是可观测的长时间阻塞链，证据不足以称它为互相等锁的死锁，也没有把历史 X14 的每一次超时都认定为完全相同的调用栈。

使用现有 `initQueue`，让帧提交与初始化、resize、dispose 的原生调用依次执行；C 字符串在队列闭包内创建和使用，FlutterResult 回主线程调用。没有提前返回 `true`，没有把失败吞掉，也没有用客户端超时或重启掩盖阻塞。

需要等待的**内部渲染更新**仍以 Dart `Future<bool>` 等待原来的原生确认，它表示 renderer 接受并更新了输入，不表示 GPU 已经显示了这一帧。它无需占住平台线程。动画帧不是用户的持久任务，因此没有给每帧创建 TaskEngine 任务，也没有让 Agent 控制等待绘制。已有账号/来源登录等用户任务仍按原来的 jobId / `task.wait` 协议处理；本次没有新增长等待的 Agent 操作或修改任务协议。

### 分别检查两个播放内核

MDK 的视频解码线程在悬挂采样中继续工作，阻塞处属于应用自有的 Next2 弹幕纹理桥。erika 默认在内核内合成弹幕；`VideoPlayerState.isNativeDanmakuActive` 为真时，`DanmakuOverlay` 跳过 Flutter 弹幕纹理层。它的 Dart adapter 经 erika 的原生 play/pause/seek 通道工作。本次 erika 两组实验没有复现超时，没有更改或替换 erika 依赖。

最初按两个内核共用播放器界面追查，补查实际渲染分支后明确了这个区别。不能把 erika 的成功实验当成它曾发生相同阻塞、现在被本次桥修复的证明。

### 保持 Classic 的操作语义

修复位于原生调度边界与共用启动定位边界。Classic 的暂停、恢复、seek、播放加载、历史与截图路径没有改写。

实验还观察到现有异步快照语义：erika 的暂停/恢复响应有时仍带上一刻的状态，随后读取才反映新状态；暂停时 seek 也沿用 Classic 的先播放、稍后恢复暂停行为。即时快照没有被当作原生解码或暂停完成的独立验证。实验每轮保留控制之后的真实读取，实际状态、时间进度及 Jellyfin 暂停报告都能变化。这里没有为了让回执看起来成功而改写播放器快照。

### 不升级屏幕依赖

`windowManager.setAlignment` 使用 `calcWindowPosition`，后者调用 `screen_retriever` 的 Dart 包装层，其 `_defaultArguments` 执行 `platformDispatcher.views.single`。本机启动时已有 implicit view 0 和主窗口 view 1，与是否启用 Next 无关。异常发生在 `show()` / `focus()` 之前，因此确实影响选择 windowed 启动的 Classic 用户。

应用内新增 `desktopStartupWindowPosition`，按现有插件协议查询 primary display、all displays 与 cursor point，保留定位计算，再用现有 `windowManager.setPosition`。缩放比例沿用 window_manager 的现有来源，与设置窗口尺寸和位置使用同一比例。没有更改 pub-cache、vendored 插件或依赖约束。

## 3. 实验

### 环境、命令与隔离

先读 `TEAM.md`、实验 7 与 X14 的「意外」。初始 worktree 干净。只在这个 worktree 构建：

```sh
ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
  ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub

NIPAPLAY_PROFILE=x15-fixed-mdk \
  ./build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay

NIPAPLAY_PROFILE=x15-fixed-erika \
  ./build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
```

运行前只在对应新建实验目录写入实验偏好：开启端点、选择内核以及 windowed 1280×720。erika 的实验偏好另开启其 Labs 内核开关。Classic 启动实验关闭 Next、设为 windowed / bottomRight / 960×600。

本地文件使用只读目录中的第 1 集 MP4。Jellyfin 地址为 `127.0.0.1:8096`，连接秘密仅从 `/tmp/nipa-next/testservers.json` 读到 Python 内存，经实验实例的 `media.sources.add/login/browse` 调用，再用 `jellyfin://itemId` 播放。测试请求用 `ProxyHandler({})`，应用进程同时设置 `NO_PROXY` / `no_proxy` 为 `127.0.0.1,localhost`。没有访问用户真实偏好、数据目录或登录钥匙串，没有启动 Applications 里的应用，没有使用 open/osascript。

基线构建与修复构建都成功。构建内置 pod install 把已解析的 erika pod 版本元数据刷新到 Podfile.lock；最终恢复该文件，依赖文件没有留下变化。没有运行 pub get。构建与检查日志在 `/tmp/nipa-next/x15-build-baseline.log`、`x15-build-fixed.log`、`x15-tests.log`、`x15-danmaku-tests.log`、`x15-analyze.log`。

### 基线：窗口异常和播放悬挂

先用 windowed 基线 PID 41821，确实出现以下输出，完整堆栈见 [baseline-windowed-stack.txt](evidence/x15/baseline-windowed-stack.txt)：

```text
[DesktopMultiWindow] main FlutterView=1, implicit=0,
views=0:Size(0.0, 0.0), 1:Size(3024.0, 1680.0)
Unhandled Exception: Bad state: Too many elements
#0 Iterable.single
#1 MethodChannelScreenRetriever._defaultArguments
#4 calcWindowPosition
#5 WindowManager.setAlignment
```

该隐藏窗口中的首轮 MDK 调用返回了，没有把它当作可见播放的有效悬挂验证。按 PID 结束，改同一临时 profile 为 maximized，直接运行基线 PID 42278。可见播放的真实输出：

```text
playback.open 1550.89 completed {'status': 'playing', 'positionMs': 52, 'durationMs': 140036, 'paused': False}
playback.state 8001.39 transport_error {}
RuntimeError: probe failed; playback.state
```

实验客户端使用 8 秒期限，以便出现悬挂后及时采样；没有更改生产客户端的期限。[baseline-local.log](evidence/x15/baseline-local.log) 保留了失败输出。之后的单独目录探测返回 HTTP 200，说明端口和凭据没有失效；它不表示整个阻塞期间目录请求始终可用。

`sample 42278 3` 的真实栈摘录见 [baseline-stacks.txt](evidence/x15/baseline-stacks.txt)：

```text
DispatchQueue_1: com.apple.main-thread (serial)
  RustLibNipaplayPlugin.handle(_:result:)
  RustLibNipaplayPlugin.setFrame(arguments:result:)
  next2_engine_set_frame
  std::sync::mpsc::Receiver<T>::recv
  semaphore_wait_trap

Thread: next2-engine
  run_engine_loop
  Next2Renderer::draw_to_present
  Next2Renderer::build_vertices
  Next2GlyphAtlas::glyph_from_fonts
  MsdfWorkerPool::rasterize_sync
```

Next 在 macOS 使用 `databaseFactoryFfi`，不是 SQLite 插件的 MethodChannel 数据库。`FileIndexingCapability` 在播放快照返回前还会 await 文件位置注册；这里的异步结果也需要 Flutter/Dart 事件调度继续前进。本次没有发现数据库事务互锁，也没有修改文件索引或数据库锁规则。根因证据是平台主线程被原生渲染确认等待占用。

### 修复：同一等待转到后台，主线程继续处理事件

在修复后的 MDK 本地播放期间执行 `sample 45325 2`，[fixed-stacks.txt](evidence/x15/fixed-stacks.txt) 显示：

```text
Thread: Main Thread
  NSApplication.run
  __CFRunLoopRun
  __CFRunLoopServiceMachPort

DispatchQueue: nipaplay.next2.engine-init (serial)
  RustLibNipaplayPlugin.setFrame(arguments:result:)
  next2_engine_set_frame
  std::sync::mpsc::Receiver<T>::recv
```

字形生成仍可能慢，但其等待已不占住平台主线程。没有用关闭弹幕或换播放器来完成 MDK 验证。

### 四组真实连续调用

每组先 open，播放 2 秒后读取进度，然后执行 25 轮：state → 暂停 → 150 ms → state → seek → 200 ms → 恢复 → 250 ms → state。seek 目标从 10000 ms 每轮增加 2000 ms，每五轮读取 tracks，最后 close。当前实际 Action 名为 `playback.set_paused`，没有 `playback.pause` 别名。

全部逐次耗时和原始脱敏响应见：

- [MDK 本地调用](evidence/x15/mdk-local-calls.json) / [逐次输出](evidence/x15/mdk-local.log)
- [MDK Jellyfin 调用](evidence/x15/mdk-jellyfin-calls.json) / [逐次输出](evidence/x15/mdk-jellyfin.log)
- [erika 本地调用](evidence/x15/erika-local-calls.json) / [逐次输出](evidence/x15/erika-local.log)
- [erika Jellyfin 调用](evidence/x15/erika-jellyfin-calls.json) / [逐次输出](evidence/x15/erika-jellyfin.log)

每组 playback.state 76 次、set_paused 50 次、seek 25 次、tracks 5 次，open 和 close 各 1 次。本地每组 158 次请求；Jellyfin 每组另有 5 次来源/登录任务请求，共 163 次。下表为各 Action 的真实最大耗时，单位 ms；[summary.json](evidence/x15/summary.json) 另含每项最小值和中位数。

| 内核 / 媒体 | 请求数 / 失败 | open | state | 暂停/恢复 | seek | tracks | close |
|---|---:|---:|---:|---:|---:|---:|---:|
| MDK 本地 | 158 / 0 | 1527.48 | 78.32 | 48.73 | 27.76 | 3.78 | 13.69 |
| MDK Jellyfin | 163 / 0 | 1437.62 | 4.74 | 56.85 | 27.41 | 15.65 | 36.87 |
| erika 本地 | 158 / 0 | 1855.43 | 18.70 | 33.04 | 19.32 | 7.01 | 4.30 |
| erika Jellyfin | 163 / 0 | 1567.88 | 6.44 | 23.43 | 19.21 | 18.82 | 18.03 |

MDK Jellyfin 的一轮真实输出：

```text
playback.open 1437.62 completed {'status': 'playing', 'positionMs': 229, 'durationMs': 140036, 'paused': False}
playback.state 3.63 completed {'status': 'playing', 'positionMs': 2220, 'durationMs': 140036, 'paused': False}
playback.set_paused 48.09 completed {'status': 'paused', 'positionMs': 2231, 'durationMs': 140036, 'paused': True}
playback.state 4.74 completed {'status': 'paused', 'positionMs': 2231, 'durationMs': 140036, 'paused': True}
```

erika Jellyfin 的异步状态变化也保留原样：

```text
playback.open 1567.88 completed {'status': 'playing', 'positionMs': 112, 'durationMs': 140035, 'paused': False}
playback.state 4.15 completed {'status': 'playing', 'positionMs': 2056, 'durationMs': 140035, 'paused': False}
playback.set_paused 22.16 completed {'status': 'playing', 'positionMs': 2064, 'durationMs': 140035, 'paused': False}
playback.state 2.72 completed {'status': 'paused', 'positionMs': 2064, 'durationMs': 140035, 'paused': True}
playback.seek 4.03 completed {'status': 'playing', 'positionMs': 10000, 'durationMs': 140035, 'paused': False}
playback.set_paused 7.08 completed {'status': 'paused', 'positionMs': 10000, 'durationMs': 140035, 'paused': True}
playback.state 3.03 completed {'status': 'playing', 'positionMs': 10205, 'durationMs': 140035, 'paused': False}
```

两秒正常播放期间位置增长，控制后状态变化，seek 后位置继续增长；本地/串流都有有效时长。Jellyfin 通过实际来源客户端协商并播放，不是直接塞一条静态测试 URL。应用日志另确认服务器接受了播放开始和暂停状态报告，见 [MDK 摘录](evidence/x15/mdk-app-excerpts.log) / [erika 摘录](evidence/x15/erika-app-excerpts.log)。

实验脚本 [probe.py](evidence/x15/probe.py) 只读连接文件和测试服务器文件，不输出其秘密；调用必须指定临时 `NIPAPLAY_PROFILE`。它是本次实验记录，不是用户 harness 的修改。

### windowed 与 Classic

修复后的 MDK、erika 都在同样的两个启动 FlutterView 下使用 windowed，日志没有 `Too many elements`。按实验 PID 查询原生窗口，erika 的真实输出为：

```json
{"bounds":{"Height":720,"Width":1280,"X":116,"Y":110},"layer":0,"onscreen":true,"pid":45691,"windowId":42225}
```

Next 关闭的 Classic 实验实例没有 endpoint.json，窗口实际可见，右下角定位的输出为：

```json
{"bounds":{"Height":600,"Width":960,"X":552,"Y":309},"layer":0,"onscreen":true,"pid":45861,"windowId":42234}
```

完整窗口查询见 [erika-window.jsonl](evidence/x15/erika-window.jsonl)、[classic-window.jsonl](evidence/x15/classic-window.jsonl)。[Classic 截图](evidence/x15/classic-windowed.png) 只捕获 PID 45861 的实验主窗口，已视觉检查；窗口显示 Classic 首页和实验标记。

### 回归检查与限制

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/desktop_startup_window_placement_test.dart \
  test/desktop_player_multiview_test.dart \
  test/next/playback_capability_test.dart \
  test/next/playback_controls_constraints_test.dart \
  test/mdk_disposal_test.dart
```

```text
00:07 +70: All tests passed!
```

启动回归守住五种位置、鼠标所在的第二显示器、负坐标和主显示器回退；其余检查覆盖原有多视图、播放能力/输入约束与 MDK teardown。

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/dfm_overlay_lifecycle_test.dart \
  test/native_danmaku_visibility_test.dart \
  test/dfm_continuous_payload_test.dart
```

```text
00:00 +4: All tests passed!
```

新增启动 service/test 静态检查：

```text
No issues found! (ran in 0.8s)
```

包含 main.dart 的检查仍报告其原有 13 条 info（empty_catches、BuildContext async、print 等），新增启动 service 无问题，没有为了清零而改无关代码。`git diff --check` 通过。

意外与范围：基线隐藏窗口未复现悬挂，显示窗口后复现；初次实验脚本寻找 MKV 时没有文件，实际测试改用目录中的 MP4。应用日志还出现既有 gamepad / audioplayers 的 MissingPluginException 和窄布局 RenderFlex overflow，未修改这些任务范围外问题。MSDF 工作量仍可能造成弹幕出帧延迟，本次修复的是它占住平台主线程并连带阻塞端点的问题。实验仅覆盖这台 macOS 主机、两种内核、上述本地文件和临时 Jellyfin，没有声称所有平台和所有媒体都已验证。

### 脱敏与清理

公开证据检查所有测试服务器文件里的已知密码/令牌，以及三份实验端点令牌，没有出现实际秘密：

```text
public evidence files: 20 knownPasswordAndTokenScanPassed: True
total verified calls: 642 failures: 0
```

基线 PID 41821 在重启为 maximized 前已按 PID 结束。其他实验进程与目录的实际清理结果见 [cleanup.json](evidence/x15/cleanup.json)：

```text
x15-baseline-mdk    PID 42278 processStopped=true profileDeleted=true
x15-fixed-mdk       PID 45325 processStopped=true profileDeleted=true
x15-fixed-erika     PID 45691 processStopped=true profileDeleted=true
x15-classic-windowed PID 45861 processStopped=true profileDeleted=true
```

最后 `ps -p 41821,42278,45325,45691,45861` 没有应用进程。四个实验目录连同实验偏好、历史、任务、保险库、harness 和 endpoint 已删除。没有保留秘密连接文件；测试服务器输入文件保持原样。只保留 worktree 内的修改与脱敏公开证据。

## 4. 需要主控决定的问题

没有。
