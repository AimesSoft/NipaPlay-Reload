# Player Core F 交付报告

工作树：`~/Desktop/nipaplay-next-wt/pc-features`；分支：`next/pc-features`；基线：`bf209633`。

F 线实现已提交，MDK 实机单项证据已完成。跨线成品验收尚未完成：当前基线没有 K/P2/D/S，真实弹幕截图、全部内核及全部动作成功仍需合并验收；可见帧与边看边聊未测。以下按单项证据记录。

## 交付与证据

| 项目 | 实现 | 验证 |
| --- | --- | --- |
| 截图 | 当前场景与可排除弹幕/字幕层、PNG/JPEG、共享保存目录/质量/黑边设置，后台编码，独占输出 | 组件测试逐像素对照包含/排除显示层；已有文件保留 |
| GIF | 独立 Erika 解码与后台导出，30 秒区间，FPS/尺寸校验 | 插件 API 参数、已有文件保护、失败清理测试通过；真实导出见最终实机数据 |
| 时间轴预览 | 按需独立解码，一次执行和一个最新等待请求，一张缓存，跟随设置 | 陈旧请求丢弃和关闭解码器测试通过 |
| 章节与逐帧 | MDK 容器章节与原生双向逐帧；其它驱动可实现 `KernelFrameFeatures` | 章节跳转、双向逐帧、过期会话拒绝测试通过；实机 7 章，Opening 116033 ms，逐帧 116033→116074→116033 ms，暂停意图不变 |
| 重试/信息/失败/音量 | 新建内核，保留位置、暂停、音量/增强/倍速；读取 Next 事实 | 新实例与原状态保留测试通过 |
| 分离窗口/PIP/窗口控制 | Next 画面重挂同引擎窗口，串行进出并恢复原置顶状态 | 注入窗口端口测试恢复/失败回滚；未实际置顶、移动、缩放或进入 PIP |
| 快捷键 | Next 自己的播放、seek、逐帧、全屏、静音、音量，保留文本/菜单保护 | 既有会话界面测试与功能测试 |
| 外部播放器 | 设置路径/类型/UA/续播起点直接交接；如实报告未知遥测和不可控制 | 假播放器实机收到恰好一个完整片源路径；状态 `player:external`，位置/暂停未知，无可用控制；单元测试验证 mpv/VLC 参数 |
| 远控桥 | Next 开启时优先路由到 Next 端口，接收权限保留，章节参数可用 | 单元测试包含权限拒绝；实机桥暂停切换、相对 +11 秒、再次暂停，3 个调用均 success，读取同一 Next session |
| 能力契约 | ID、effect、输入/输出 schema 保持原样，更新描述 | 8 个本地动作逐 schema 对照测试通过；其它动作复用原定义 |

## 数据与命令

Flutter 固定 `~/development/flutter-3.44.6/bin/flutter`；子模块 `third_party/media-kit-upstream` 为 `7a2135661ff37a717f11d6012fefa56cae27ef36`，依赖已初始化。

所有测试均先取消大小写 HTTP/HTTPS/ALL proxy；全量和构建均持有 `~/.nipa-next/mac-heavy.lock`。实验整段持有 `~/.nipa-next/mac-lab.lock`，启动后先执行 `labmute.py`。

- 专项：`flutter test --no-pub test/next/player/features_test.dart test/next/player/feature_schema_test.dart`，13 项通过；日志 `/tmp/pc-features-gif-checkpoint.log`。另有首批会话与接缝专项 32 项通过：`/tmp/pc-features-targeted.log`。
- 首轮并发全量：1,274 项通过、7 跳过、1 失败。大配置 idle 累计 117.6 ms，阈值 110.2 ms；没有修改阈值。
- 串行全量中大配置性能测试通过。播放层预算：`session.kernel` p99 43 μs、`facade.sync` 4 μs、`facade.transport` 15 μs、pause 380 μs、play 100 μs、seek 427 μs、snapshot 724 μs（外层 813 μs），隐藏控件重建帧 0。该轮截图测试加载了修改前的编译产物，按字符串读取质量整数而失败，已在固定版本的最终回归中重跑。
- F 相关增量静态分析：`/tmp/pc-features-analyze-features.log`，`No issues found!`。较大范围仅保留原 `next_runtime.dart` 的 braces info。
- 首次 macOS Debug 构建并签名成功：`/tmp/pc-features-build.log`。更新构建：`/tmp/pc-features-build-2.log`。
- 最终 macOS Debug 构建并签名成功：`/tmp/pc-features-build-final.log`。GIF 使用 `ErikaPlayer.exportGif`，macOS 插件 `DispatchQueue.global` 执行解码/编码，主队列只回传结果；不再依赖旧 Classic GIF 加载器。修复专项静态分析 `No issues found!`：`/tmp/pc-features-gif-analyze.log`。
- 最终固定版本完整回归退出码 **0**：**1278 通过、7 跳过、0 失败**，耗时5分37秒。包括整个 `test/next` 与下列7个受影响的 Classic 测试文件。大配置主线程预算通过；最终播放层预算 p99：session.kernel39 μs、facade.sync5 μs、facade.transport19 μs、pause569 μs、play110 μs、seek421 μs、snapshot682 μs（外层771 μs），隐藏控件重建帧0。未修改任何阈值。

最终全量命令：

```zsh
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy
lockf -k $HOME/.nipa-next/mac-heavy.lock zsh -c '
  ~/development/flutter-3.44.6/bin/flutter test --no-pub --concurrency=1 test/next \
    test/remote_control_settings_test.dart test/remote_control_access_guard_test.dart \
    test/external_player_settings_test.dart test/external_player_console_service_test.dart \
    test/external_player_window_service_test.dart test/media_capture_dialog_input_test.dart \
    test/erika_gif_export_contract_test.dart'
```

日志：`/tmp/pc-features-regression-release.log`。最终结果尾部：

```text
05:36 +1276 ~7: ~/Desktop/nipaplay-next-wt/pc-features/test/media_capture_dialog_input_test.dart: Android GIF export saves directly to the gallery
05:37 +1277 ~7: loading ~/Desktop/nipaplay-next-wt/pc-features/test/erika_gif_export_contract_test.dart
05:37 +1277 ~7: ~/Desktop/nipaplay-next-wt/pc-features/test/erika_gif_export_contract_test.dart: Erika headless GIF export covers every native plugin platform
05:37 +1278 ~7: All tests passed!
```

固定版本之前的 `/tmp/pc-features-regression-accepted.log` 为1277通过、7跳过、1失败：新增GIF测试加载到修复前的实现，调用了旧FFI加载器；最终固定版本已完整通过。最终全量、构建、专项及静态分析日志另存于 `~/.nipa-next/player-core-f-runs/final-validation-20261023/`。

最终构建命令（同工作树）：

```zsh
lockf -k $HOME/.nipa-next/mac-heavy.lock zsh -c '
  ERIKA_MACOS_CAPI_DYLIB=$HOME/.nipa-next/erika-wt/agent-diagnostics/target/release/liberika_capi.dylib \
  ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
  ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub \
    --dart-define-from-file=$HOME/.nipa-next/defines.json &&
  codesign --force --deep --sign "Apple Development: RONGGUANG LIANG (JB76WG94SN)" \
    --entitlements macos/Runner/DebugProfile.entitlements \
    build/macos/Build/Products/Debug/NipaPlay.app'
```

结果尾部：

```text
✓ Built build/macos/Build/Products/Debug/NipaPlay.app
build/macos/Build/Products/Debug/NipaPlay.app: replacing existing signature
```

实机命令：

```zsh
lockf -k $HOME/.nipa-next/mac-lab.lock zsh scripts/next/player_core_f_lab.zsh
```

实验使用 `core-lab-f`，只读 e2e42b 下载片源绝对路径；不读写运行实例 `next.db`。窗口截图通过该 profile 的 `harness/nipa call ui.capture '{}'`，从未截全屏。

### 首轮完整实机证据

目录：`~/.nipa-next/player-core-f-runs/acceptance-20261023-d/`。

- 《躲在超市后门抽烟的两人》第 10 集，MDK 真播放后跳到 70% 之后，截图位置 1005240 ms。`midpoint.png` 为 3024×1701、3952321 字节；与 `midpoint-ui.png` 逐图看过，同一帧超市后门人物画面一致。基线没有 D 的真实弹幕层，收据 `danmakuIncluded:false`；含/排除弹幕由组件中真实绘制的文字层像素测试验证，未宣称实机真实弹幕通过。
- `preview.jpg` 9542 字节，独立预览解码成功，`preview.json` 为 enabled。`remote.json` 保存三个真实桥调用；`external-args.txt` 和 `external-ui.png` 保存交接参数和界面。
- 重试 instance 1→2，旧会话完成释放，位置与暂停保留；完整生命周期见 `host.json`。
- `catalog.json` 为 35 个 `playback.*`，`coverage.json` 的 missing 为空；每个动作收据均保存在 `actions.json`。其中 14 个跨线动作仍返回 `not_in_playback_layer`，见下文，不能记作全部成功。
- 唯一 F 功能故障是 GIF 旧加载器不能定位插件内嵌动态库，已在 `4bc422062` 修复，并加入真正输出文件和帧数断言。
- `perf.json`：冷启动在内，`facade.sync` n=58，p99/max=3436 μs，超过 2 ms 硬线，保留此失败证据。其它主要项：runtime.playbackChanged 1157 μs、mdk.status 1136 μs、session.kernel 831 μs、snapshot 78 μs。Debug 离屏 frame build p99 191436 μs、raster 369210 μs，loop 超 16 ms 32 次、超 50 ms 19 次，最大迟到 290424 μs。实验窗口自然不可见，**可见帧验收未测**，这些离屏数据不能作为可见帧合格依据。
- `main-isolate-blocked.txt` 为空，结束时 nx status 返回；`exit.txt` 确认实验实例已退出。前/中/后 front 均为 `ASN:0x0-0x5adaad5:`，未抢前台。运行记录确认 quiet profile、不进 Dock。

### 修复后 GIF 实机证据

目录：`~/.nipa-next/player-core-f-runs/acceptance-20261023-e/`，运行 `4bc422062` 的签名 Debug app。

- `sample.gif` 32226 字节；`gif-probe.json` 为 320×180、1.000000 秒、6 帧；`ffmpeg -v error -i sample.gif -f null -` 返回 0、`gif-decode.log` 为空，全部帧可解码。已看过导出首帧 `gif-first.png`。
- `midpoint.png` 3974622 字节，3024×1701，1005172 ms（70% 后）；与 `midpoint-ui.png` 再次逐图核对一致。原生章节/双向逐帧、远控、预览、重试复验成功。
- 冷启单独保存在 `perf-cold.json`：最大播放层任务为 facade.sync 1505 μs；预热后完整动作窗口 `perf.json` 5229 ms，所有已埋点播放层任务 p99≤199 μs（facade.sync 191 μs，session.kernel 147 μs，snapshot 65 μs）。此轮没有覆盖掉上一轮冷启 3436 μs 的失败。
- 窗口自然不可见，可见帧仍未测。冷启离屏 build/raster p99 为 100169/305893 μs；动作窗口为 48803/145753 μs，loop 超16 ms 8 次、超50 ms 0 次，最大迟到47661 μs。不据此宣称全局无卡顿。
- 参数记录由假播放器进程异步写入；这一轮脚本在子进程第一次写入前读取文件，导致脚本失败，之后 finally 收集到了正确参数文件。实例已 TERM 退出、假播放器 PID 7964 也已退出。修正脚本增加最多5秒等待，并将假进程清理移到 finally，再运行完整验收。
- `main-isolate-blocked.txt` 为空，结束 nx 状态返回，前/中/后 front 均保持上述同一 ASN。

### 最终完整脚本验收

```zsh
lockf -k $HOME/.nipa-next/mac-lab.lock zsh scripts/next/player_core_f_lab.zsh \
  $HOME/.nipa-next/player-core-f-runs/acceptance-20261023-g
```

脚本退出码 **0**；日志 `/tmp/pc-features-lab-g.log`，证据目录 `~/.nipa-next/player-core-f-runs/acceptance-20261023-g/`。脚本改动已提交 `ebd66418e`，app 仍为上述最终签名构建。

- `catalog.json` 35 个播放动作，`coverage.json` missing=[]；F 动作正常执行，无内部错误。14 个其它线未合入结果原样保留。原生目录选择仅输入校验，不能算人工授权通过。
- 截图在观测暂停并等最后一帧提交后读取；`midpoint.png` 3024×1701、3974622 字节，position=1005161 ms；与 `midpoint-ui.png` 逐图核对同一帧、画面一致。真实 D 弹幕仍未合入，收据为 false。
- `sample.gif` 320×180、6 帧、1 秒、32226 字节；`gif-probe.json` 及空 `gif-decode.log` 确认 FFmpeg 全帧解码成功。独立 `preview.jpg` 成功。
- 章节 Opening 跳转与原生逐帧前后恢复、重试新实例/旧释放通过；`remote.json` 的 3 个桥调用均 success。外部参数文件恰好一个完整片源路径，外部事实的位置和暂停为 null、controlAvailable=false；关闭交接不会冒充外部播放控制。
- 冷启窗口3302 ms：已埋点播放层任务 p99最大883 μs（mdk.status），facade.sync707 μs、session.kernel649 μs；预热后5884 ms动作窗口 p99最大216 μs（mdk.state），facade.sync130 μs、session.kernel165 μs、snapshot61 μs。上一轮3436 μs冷启失败仍保留，不能据有限短窗断言所有冷启动合格。
- 离屏冷启 build/raster p99=72262/151528 μs，动作窗口=61121/297461 μs；动作窗口 loop 超16 ms 9次、超50 ms 2次，最大迟到60015 μs。窗口自然不可见，**可见帧和边看边聊验收未测**；不报告“无超过16 ms帧”。
- `main-isolate-blocked.txt` 为空，最终 nx status 调用返回；`exit.txt` 确认退出，另用 signal0 确认 app PID12970、假播放器 PID13100均已退出。前/中/后 front 均为上述同一ASN，没有前台、置顶、移动、缩放或实际PIP操作。

## 改动文件及公共文件清单

F 自有新增文件如下（完整路径）：

```text
lib/next/player/features/README.md
lib/next/player/features/capture.dart
lib/next/player/features/debug_features.dart
lib/next/player/features/external_handoff.dart
lib/next/player/features/kernel_features.dart
lib/next/player/features/local_operations.dart
lib/next/player/features/navigation.dart
lib/next/player/features/operation_specs.dart
lib/next/player/features/remote_control.dart
lib/next/player/features/settings_adapter.dart
lib/next/player/features/timeline_preview.dart
lib/next/player/features/windows.dart
lib/next/ui/player/detached_stage.dart
lib/next/ui/player/gif_dialog.dart
scripts/next/player_core_f_lab.py
scripts/next/player_core_f_lab.zsh
test/next/player/features_test.dart
test/next/player/feature_schema_test.dart
docs/next/PLAYER_CORE_F_REPORT.md
```

公共文件全部为增量，由主控合并时保留其它线实现：

| 文件 | 增量内容 |
| --- | --- |
| `lib/next/player/core/host.dart` | `open` 接受 `initialLevels`，供重试保留状态 |
| `lib/next/player/core/session.dart` | 只读 `source` 与 `volumeBoost` getter |
| `lib/next/player/kernel/driver.dart` | `MediaFacts.chapters` 与序列化 |
| `lib/next/player/kernel/mdk_driver.dart` | 容器章节、栅栏队列中的 native step/snapshot |
| `lib/next/player/ports/session_playback.dart` | 功能对象、窗口/快捷键/设置/外部交接/截图 UI 接入 |
| `lib/next/player/ports/session_ports.dart` | F 动作实现、过期会话防护、重试、外部事实；保留其它线接缝 |
| `lib/next/next_runtime.dart` | 注入 Next 本地动作和外部交接，绑定/解绑远控与 F 设置写入，lab debug 接入 |
| `lib/next/settings/application_settings.dart` | 新增 `nextFeatureWrite` 回调；Next 开启且 F 处理该键时绕过 Classic setter；独立时间轴预览设置对所有内核可见 |
| `lib/next/capabilities/playback_controls_capability.dart`、`playback_inspection.dart` | 只更新 F 功能描述，schema 不变 |
| `lib/services/player_remote_control_bridge.dart` | Next 活跃时优先读取/控制 Next；Classic 分支保留 |
| `lib/services/playback_service.dart` | 外部播放设置开启时，Classic 打开入口也先服从 Next redirect |
| `lib/next/ui/player/video_stage.dart` | 显示画面 fit、截图场景、叠层入口、外部交接状态 |
| `lib/next/ui/player/player_layer.dart`、`timeline.dart` | 按需预览接入及 hover 防抖 |
| `lib/next/ui/player/player_more.dart` | 章节、逐帧、GIF、分离窗口入口 |
| `lib/next/ui/shell/next_ui_gate.dart` | 跟随 Next 窗口状态，分离时摘下主窗画面 |
| `test/next/player/fake_driver.dart` | 可注入媒体事实与可扩展驱动，用于功能测试 |

未删除 `ClassicBackedPlayback`。没有提交生成的 Podfile.lock、pubspec.lock 或插件注册文件；没有修改测试阈值、主工作树或 Erika 工作区，没有 push 或派代理。

## 提交

- `bb476cdae`：实现 F 会话功能及首批 32 项针对性回归。
- `38cbda830`：共享设置修正、schema 对照、远控完善、实机脚本和接合说明。
- `4bc422062`：实机 GIF 加载修复、插件 API 与输出保护测试、预览设置与实机脚本修正。
- `ebd66418e`：验收等待观测暂停与外部参数落盘、finally 清理假进程，完整 G 实机脚本通过。

## 遗留与主控接合

以 `features/README.md` 为接合契约：K 驱动提供 `KernelFrameFeatures`；D/P2 将真实弹幕/字幕层交给 `NextVideoStage.overlays`，主窗和分离窗使用同一叠层构造；S 重试保留来源/剧集上下文。变帧率媒体仅按报告帧率 seek 的路径不能宣称精确逐帧。

当前基线未合入 K/P2/D/S。全 `playback.*` 对真实会话全部成功、带真实 D 弹幕的实机截图和所有内核的逐帧/原生叠层，需要合并后验收。目录授权的 native 人工选择步骤未自动操作；脚本只调用输入校验，避免留下模态框或向用户桌面发系统按键。

性能遗留：D 轮一次冷启 facade.sync p99/max3436 μs 的超线尚未定位；E/G 复验已埋点任务低于2 ms，但不能据短窗替代稳定性证明。离屏 Debug 构建/光栅帧与事件循环存在长尾，不能归因成某一播放任务，也不能宣称满足可见帧16 ms硬线。需在窗口自然可见时继续定位并完成边看边聊验收，不能通过改阈值消除。

14 个跨线结果具体为：K 的 kernel、kernel_command、kernel_invoke、set_kernel_properties、restore_kernel_properties、reopen_with_kernel、watch_kernel_properties；P2 的 tracks、select_track、load_subtitle、remove_subtitle；S 的 stream_options、select_stream、playlist。switch_episode 无下一集时 unavailable、外部播放器弹幕不可控时 external_player 是当前上下文的事实；目录空路径为 invalid_input。这些不应通过包装收据隐藏。合并前不满足 common/F 的“全部动作正确且没有新层不支持”整体验收条件。

本任务全部实验实例已退出，运行日志没有 `main isolate blocked`。最后一轮 app 与假播放器的独立退出检查见上文。Podfile.lock 构建改写已还原，没有提交生成文件；完整回归和最终签名构建均已完成。

需要主控决定：合并 K/P2/D/S 的顺序，以及跨线全部动作、真实弹幕截图、冷启长尾和自然可见帧/边看边聊的最终验收安排。
