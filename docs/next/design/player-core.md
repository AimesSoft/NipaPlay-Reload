# NipaPlay Next 播放会话层设计（next-player-core）

- 日期：2026-10-23
- 基线：分支 `next/capability-layer`，提交 f5e43362
- 性质：只读调研，没有改代码，没有构建
- 引用格式：路径相对仓库根目录 `~/Desktop/NipaPlay-Reload`。VideoPlayerState 的 part 文件都在 `lib/utils/video_player_state/` 下，下文省略前缀 `video_player_state_`：setup=`player_setup.dart`、ctrl=`playback_controls.dart`、nav=`navigation.dart`、dm=`danmaku.dart`、meta=`metadata.dart`、init=`initialization.dart`、pref=`preferences.dart`、sub=`subtitles.dart`、strm=`streaming.dart`、cap=`capture.dart`、tl=`timeline_preview.dart`、intro=`intro_skip.dart`。其余缩写：VPS=`lib/utils/video_player_state.dart`、pkm=`lib/utils/player_kernel_manager.dart`、mdk=`lib/player_abstraction/mdk_player_adapter_io.dart`、mk=`lib/player_abstraction/media_kit_player_adapter.dart`、er=`lib/player_abstraction/erika_player_adapter.dart`、vp=`lib/player_abstraction/video_player_adapter.dart`、pa=`lib/player_abstraction/player_abstraction.dart`、fvp=`third_party/fvp/lib/src/player.dart`、mkreal=`packages/media_kit/lib/src/player/native/player/real.dart`。

---

## 决定（用户，2026-10-23）

这些决定优先于下文 §0.2 和 §8.1 的建议；与本节冲突的内容，一律以本节为准。

- **D1 Classic 界面里没有 Nipa。** 不允许在 Classic 界面使用 agent：Next 界面关着时，Nipa 的运行器、agent 端点和所有能力都不运行，Classic 里也不出现任何 Nipa 的入口。所以不存在“Classic 界面 + `playback.*`”的组合，`VideoPlayerStatePort` 那条路随之删除。
- **D1 补充**：关闭 Next 界面时，Nipa 已在运行的程序进程也一并取消，不只是不再启动新的。
- **D2 切换是彻底的。** 在 Next 和 Classic 之间切换，当前会话关闭并保存进度，另一边不接着播，内存里的会话状态也不带过去。
- **D3 两边隔离，只共用数据层。** 设置（同一批偏好键）、续播进度、观看记录共用，其他一概不共用。Next 不走 Classic 的播放器、不走 `VideoPlayerState`，也不借用 Classic 的播放界面和叠层。
- **D5 不回退到 Classic 播放器。** 新层还不支持的来源或内核，返回 unavailable，并在事实里说明原因。Next 还没发布，迁移期间可用范围暂时变窄可以接受。§7 里“不支持就走 Classic 播放器”的分流和 `route` 事实作废；`ClassicBackedPlayback` 只作为 P0 的过渡接缝，P1 起 Next 一律走新层。
- **D4 弹幕透明度按线性应用。** Classic 那一行平方也改成线性，单独给 main 发 PR。
- **D6** 每个会话新建内核实例。**D7** macOS 先做。**D8** 按建议：能力层能改的设置都要在新层生效，过渡期如实标注。
- **性能要求不打折扣**：卡顿修复不能得过且过，主线程上随数据增长的工作要全部消除。

## 0. 先看这里

### 0.1 五条核心结论

1. **状态分成意图和观测两层。** 意图是"最后一次要求播还是停、跳到哪"，收到命令立刻改。观测是内核说的状态，只在内核确认后改。按钮显示意图，画面、时间轴和给 Nipa 的事实以观测为准，两者都报告。打开计划和换内核只搬运意图，从不根据观测猜"ready 算不算暂停"。第 3、4 类竞态因此从结构上消失。
2. **整个进程只有一个内核租约。** Next 开着时，Classic 的 `VideoPlayerState` 对象还在：它是全局 Provider（`lib/main.dart:673`），构造时会建一个空闲的 `Player()`（VPS:1037）。但它拿不到租约，就不能打开媒体。`initializePlayer` 开头加一个转交钩子，Classic 的约 30 个打开入口都会转给 Next。Next 自己的层完全不引用 `VideoPlayerState`。
3. **内核驱动包住现有适配器，对上只暴露事件流和可等待的命令。** 释放时先立栅栏，界面只读 Dart 快照、永远不读原生；拆除顺序固定为"摘画面 → 等一帧 → 放渲染上下文 → 销毁核心 → 还租约"。每个媒体会话新建内核实例。第 1、2、7 类缺陷因此不会再出现。
4. **推送，不轮询。** 内核事件进入会话，用 O(1) 的归约生成按主题拆开的 `ValueListenable` 和一条带序号的事件流。位置由 `PlaybackClock` 外推，弹幕和时间轴在各自的 vsync 里读时钟，不再依赖 Classic 每 120 ms 一次的全量 notify。弹幕时间线、字幕解析、片头识别、热度、entries/cues 分页都放到后台 isolate，必要时下沉到 Rust。主线程上播放层的单次任务不超过 2 ms。
5. **先立接缝，再换芯。** P0 先把 `lib/next` 里 20 个直接依赖 VPS 的文件收进一个 `NextPlayback` 接口，这个接口暂时由 Classic 实现。之后每个阶段把实现的一部分换成新层，`playback.*` 的动作 ID 和 schema 保持不变。一共 7 个阶段，每个都能单独交付，每个阶段结束时 Next 都能用。

### 0.2 需要你拍板的问题（详见 §8.1）

| # | 问题 | 我的建议 |
|---|---|---|
| D1 | Next 界面关闭、但 Nipa 开着（Classic 界面）时，`playback.*` 驱动谁 | 驱动 Classic 播放器。沿用现有端口，冻结不再加功能 |
| D2 | 播放中在 Next 和 Classic 界面之间切换 | 关闭当前会话并保存进度，不在另一边自动重开 |
| D3 | 设置、续播进度、观看记录是否和 Classic 共用 | 共用同一套存储键和表 |
| D4 | 弹幕透明度在 Classic 里被平方 | 已定：两边都按线性（见开头“决定”） |
| D5 | 迁移期间，新层还不支持的来源或内核怎么办 | 继续走 Classic 播放器，事实里写明走的是哪条路 |
| D6 | 每个媒体会话都新建内核实例 | 是。切集多出的耗时在 P1 实测 |
| D7 | 平台顺序 | macOS 先；Windows 从 P4 开始，前提是先修 media_kit 在 Windows 上的释放竞态 |
| D8 | 只在 Classic 界面出现的功能（防剧透 AI、CRT、Anime4K、发送弹幕等） | 能力层能改的设置都要在新层生效；过渡期允许如实标注"只作用于 Classic 播放器"，清单逐项由你勾选 |

---

## 0.3 现状与根因

### Next 现在怎么播放

- `NextUiGate` 在 Next 开着时仍然挂载整个 Classic，只在有视频时把它露出来（`lib/next/ui/shell/next_ui_gate.dart:13-25, 80-87`）。画面、字幕、弹幕、点画面暂停、右键菜单和快捷键都是 Classic 的。Next 只在上面画控件（`lib/next/ui/player/player_layer.dart:32-47`）。
- 打开视频走 `ui.open` → `playback.open` → `PlaybackService().play` → `VideoPlayerState.initializePlayer`（`lib/next/ui/data/core_connect.dart:199-213`；`lib/next/next_runtime.dart:157-169`；`lib/services/playback_service.dart:96-120`）。
- 能力层通过三个端口接口访问播放器：`PlayerPort`（`lib/next/capabilities/playback_capability.dart:14-19`）、`PlaybackControlsPort`（`playback_controls_capability.dart:5-16`）、`PlaybackInspectionPort`（`playback_inspection.dart:13-15`）。现在的实现全部是对 VPS 的薄包装：`video_player_state_port.dart`、`classic_playback_controls.dart`、`playback_inspection.dart`。`KernelControl` 直接持有 VPS（`kernel_control.dart:86-102`）。
- 字幕库、弹幕服务和 mesh 通过注入到 VPS 的钩子和监听器接入：`lib/next/subtitles/library.dart:534-593`、`lib/next/danmaku/runtime.dart:129-167`、`lib/next/mesh/playback.dart:23-34`。

### 7 个缺陷的结构根因

| # | 缺陷 | 结构根因（代码依据） | 新层怎样消除 |
|---|---|---|---|
| 1 | MDK 在另一个 isolate 被删除时，界面还在读 `mediaInfo`，SIGSEGV | 界面和能力层直接读同步的原生 getter：`NextPlayback.subtitles()` 读 `state.player.mediaInfo`（`lib/next/ui/player/playback.dart:198`），`audio()` 在第 326 行，诊断在 `next_runtime.dart:405`，换内核在 `kernel_control.dart:1189`。MDK 的 `mediaInfo` 和 `position` 每次都直接调原生（mdk:439-442, 461）。而热切换期间，`state.player` 仍然指向正在释放的旧实例（pkm:204-221） | I3：界面永不碰原生；I2：释放栅栏 |
| 2 | media_kit 先回复释放、晚一步才释放渲染上下文，mpv abort | 拆除顺序不由适配器保证；`setMedia` 会清掉 `_isDisposed`，让播放器"复活"（a789943e 的说明） | I4：固定拆除顺序；I5：不复活。Windows 还有同类风险（§3.3） |
| 3 | 续播 seek 被取消，内核从 0 开始播，界面显示保存的位置 | 打开顺序：`prepare` 之后内核自己就开播了（setup:565-566）→ 选字幕轨（setup:804）→ 再 `seekAndWait` 续播（setup:876）。MDK 把换轨实现为"seek 到当前位置"，正好把续播 seek 取消掉 | 打开计划在驱动的串行队列里执行：带起点打开（fvp 支持 `prepare(position:)`，fvp:456；适配器没用，mdk:533），换轨确认后再定位，定位确认后才开播 |
| 4 | 换内核发生在 ready 阶段时，媒体被当成暂停带过去 | `play()` 要等 `playDirectly()` 返回才把状态设为 playing（ctrl:624-627）；换内核读的是这个观测状态；`KernelControl._settle` 每 50 ms 轮询一次（`kernel_control.dart:1175-1186`） | 意图和观测分离；换内核只搬意图 |
| 5 | 弹幕晚到时不再补做片头识别 | 弹幕片头检测只挂在 `loadDanmaku` 完成之后（dm:343-346）；自动识别路径直接写轨道，不会触发它（meta:215-283） | 片头事实是输入（弹幕版本、章节、时长）的函数，任一输入变化就重算 |
| 6 | 弹幕透明度按平方应用 | `mappedDanmakuOpacity => danmakuOpacity * danmakuOpacity`（pref:351-354），交给 Flutter 渲染器；而 Erika 原生弹幕用的是线性值（dm:75, 100） | 只在一处定义，值即 alpha（D4） |
| 7 | Next 改了内核设置，播放器不重建 | VPS 跨多次打开复用同一个 Player，只有热切换才重建（pkm:227） | 每个会话新建实例；创建时快照配置，并作为事实报告 |

### 性能根因（只列播放层相关的）

**Classic 的 notify 被 5 个 Next 监听者放大**

VPS 在播放时用一个 Ticker 每帧轮询原生位置（nav:882），并且每 120 ms 调一次 `notifyListeners`（VPS:1207-1215）。Next 有 5 处挂在这个 notify 上：
- `DanmakuRuntime._changed` → `refreshCurrent`。每次都会 `ensureFile`、查询 `media_locations`、遍历 bindings（`lib/next/danmaku/runtime.dart:145-167` → `lib/next/danmaku/service.dart:499-583`）。
- `NextRuntime._playbackChanged`（`next_runtime.dart:723, 751-783`）。
- `_Watch`（`player_layer.dart:382`）。
- `KernelControl`，在持有覆盖时（`kernel_control.dart:149`）。
- `DesktopPlayerWindowService`（`lib/services/desktop_player_window_service.dart:310-341`）。

此外，播放层里十几个 `Selector` 每次 notify 都要求值一遍。

**主线程上的重活**

- 弹幕合并、过滤、排序（dm:635-771）。屏蔽规则对每条弹幕、每条规则都新建一个 RegExp（sub:667, 688）。
- 把文件前 16 MB 读成 `List<int>` 再算 md5（meta:625-628）。仓库里其实已有 Rust 版 `hashFileHead`（`rust/src/api/media_probe.rs:147`）。
- `danmaku.entries` 遍历全量弹幕（`playback_inspection.dart:439`）；`subtitle.cues` 没有缓存时在主线程解析（同文件 369-370）。
- 热度在 build 里计算（`lib/next/ui/player/playback.dart:176-195`）。
- `playback.wait` 每 50 ms 轮询一次（`playback_inspection.dart:147-175`）。
- 观看记录每个 10 秒分桶对全表排序一次并 notify（`lib/providers/watch_history_provider.dart:417-434`）。
- 读续播位置时，在主线程 `json.decode` 整张表（init:429-431）。

---

## 1. 边界

### 1.1 负责什么、不负责什么

**负责：**
- 一次播放从打开到关闭的完整生命周期，包括：解析来源（复用现有服务）、取得租约、创建并释放内核、打开计划、传输控制（播停、跳转、倍速、音量、逐帧、章节）、轨道、字幕呈现、弹幕呈现、片头片尾事实、播完动作、换内核、错误与重试。
- 续播进度和观看记录的写入，Jellyfin/Emby/共享库/mesh 的进度回报。
- 把以上一切作为带来源、带时间的事实提供给能力层、界面和 hooks，并提供对应的原语。
- 守住不变量：单租约、栅栏、拆除顺序、呈现的字幕等于所选的字幕、命令不跨会话。

**不负责：**
- 认片、绑定、挑弹幕源、决定跳不跳片头、决定看哪一集。这些判断都归 Nipa；认片和绑定归 media/danmaku 能力；字幕选择的持久化归字幕库。
- 从各平台抓取弹幕（归弹幕服务或 Nipa），下载，界面布局。
- media.frames 的私有解码器。它不是播放内核，不经过租约，也不碰会话（`lib/next/capabilities/media_frames_mdk.dart:13-137`）。

### 1.2 模块与依赖方向

```
lib/next/player/                     ← 新层，不 import utils/video_player_state*
  core/    arbiter.dart  session.dart  host.dart  clock.dart  events.dart  intent.dart  facts.dart
  kernel/  driver.dart  op_queue.dart  mdk_driver.dart  mpv_driver.dart  erika_driver.dart  video_player_driver.dart
  source/  resolver.dart              ← 包装 PlaybackSourceService / Jellyfin / Emby / WebDAV / SMB / mesh
  subtitles/ controller.dart  cue_index.dart
  danmaku/ controller.dart  timeline_build.dart  session_port.dart
  progress/ recorder.dart  remote_report.dart
  worker/  playback_worker.dart
  perf/    budget.dart
  ports/   session_ports.dart  kernel_host.dart   ← 实现能力层现有的端口
lib/next/ui/player/                  ← 界面只依赖 core 的公开类型
lib/player_abstraction/              ← 复用，只做增补（§3.3）
```

依赖方向：界面 → core ← 能力端口；core → 驱动 → 适配器；core → worker。core 不依赖界面和 harness。

### 1.3 接口草案

```dart
// ---- core/arbiter.dart ----
enum KernelOwner { classic, next }

/// 进程里唯一的播放内核租约。只有持有者可以创建和打开播放内核。
final class KernelArbiter {
  static final KernelArbiter instance = KernelArbiter._();
  KernelOwner? get owner;
  Stream<ArbiterEvent> get events;      // acquired / released / evicted / violation
  /// 对方持有时先调用它登记的 evictor（Classic 用它自己的关闭路径），
  /// 等它完全交还后才返回。
  Future<KernelLease> acquire(KernelOwner who, {required String reason});
  void registerEvictor(KernelOwner who, Future<void> Function(String reason) evict);
  List<ArbiterViolation> get violations;   // 例如租约之外调用了 initializePlayer
}

final class KernelLease {
  KernelOwner get owner;
  int get id;
  bool get held;
  Future<void> release();               // 只在内核完全释放（或已栅栏且已停）后调用
}
```

```dart
// ---- Classic 侧唯一的钩子（lib/utils/globals.dart，Classic 只多一个 typedef）----
typedef NextPlaybackRedirect = Future<bool> Function(PlayableItem item, String via);
NextPlaybackRedirect? nextPlaybackRedirect;   // Next 持有播放时非空

// VideoPlayerState.initializePlayer 开头（setup:19 之后）加 3 行：
//   if (nextPlaybackRedirect case final r? when await r(item, 'classic.initializePlayer')) return;
```

```dart
// ---- kernel/driver.dart ----
enum KernelId { mdk, mediaKit, erika, videoPlayer }

/// 创建时的配置快照，作为事实报告。之后不变，要改就换实例。
final class KernelConfig {
  final KernelId kernel;
  final String? httpProxy, userAgent, erikaOutputMode;
  final int? bufferMb;
  final bool platformVideo;              // macOS/Windows 原生视频或 Erika 覆盖层
  final Map<String, String> options;      // 硬解、像素格式等
}

abstract interface class KernelDriver {
  KernelId get kernel;
  int get instance;                       // 每个事件都带它
  KernelConfig get config;
  KernelCapabilities get capabilities;    // 静态能力表：seekConfirm、trackConfirm、chapters、
                                          // frameStep、assByKernel、nativeDanmaku、gif、bufferingTelemetry…
  Stream<KernelEvent> get events;         // 状态只从这里出来
  ValueListenable<VideoSurface?> get surface;

  /// 完成条件：KernelReady。带起点和起始轨道打开，打开后保持暂停。
  Future<KernelOpened> open(ResolvedSource source,
      {Duration start = Duration.zero, TrackRequest? tracks});
  Future<void> setPaused(bool paused);    // 完成条件：观测到对应状态，否则抛 KernelTimeout
  Future<SeekOutcome> seek(Duration target, {SeekMode mode = SeekMode.keyframe});
  Future<TrackSelection> selectTracks(TrackRequest request);   // 完成条件：内核回报的激活轨道
  Future<KernelTrackRef> mountSubtitle(String path);           // 由内核渲染的外挂字幕
  Future<void> unmountSubtitle(KernelTrackRef ref);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setChapter(int index);
  Future<void> step(int frames);
  Future<KernelFrame?> snapshot({int? width, int? height});    // 带真实尺寸、像素格式、是否占位
  Future<JsonMap> readMediaFacts();       // playback.info 用，走串行队列
  KernelAccess get access;                // 原生属性、命令、invoke、日志，给 kernel_control
  NativeDanmakuSink? get nativeDanmaku;   // Erika
  Future<void> release();                 // 幂等；第一次调用时同步立栅栏
}

sealed class KernelEvent {
  int get instance;
  int get seq;
  Duration get at;                        // 单调时钟
}
final class KernelReady extends KernelEvent { final MediaFacts media; }
final class KernelTransportChanged extends KernelEvent { final KernelTransport transport; } // playing/paused/stopped
final class KernelPositionSample extends KernelEvent { final Duration position; final double rate; final bool advancing; }
final class KernelBuffering extends KernelEvent { final bool buffering; final double? percent; final Duration? bufferedTo; }
final class KernelSeekSettled extends KernelEvent { final Duration target; final Duration? landed; final SeekResult result; } // done/superseded/rejected
final class KernelTracksChanged extends KernelEvent { final List<KernelTrack> tracks; final TrackSelection active; }
final class KernelVideoSize extends KernelEvent { final int width, height; final double aspect; }
final class KernelEnded extends KernelEvent {}
final class KernelFailed extends KernelEvent { final String stage, message; final bool? retryable; }
final class KernelLog extends KernelEvent { final String level, source, text; }

/// 取代 pa:390-478 里的 dynamic 调用。
sealed class VideoSurface {}
final class TextureSurface extends VideoSurface { final int textureId; }
final class PlatformViewSurface extends VideoSurface { final Widget Function(BuildContext) build; }
final class WindowOverlaySurface extends VideoSurface {   // Erika、macOS 原生视频，画在窗口下面
  final Future<void> Function(Rect rect) place;
}
```

```dart
// ---- core/session.dart ----
enum SessionPhase { resolving, starting, loading, preparing, active, swapping, failed, closing, closed }

final class MediaRequest {
  final String locator;                 // 和 playback.open 的 path 同义：本地路径、jellyfin://、smb://…
  final int? animeId, episodeId;
  final Duration? start;                // 显式起点；为空时用保存的进度
  final bool? paused;                   // 显式要求打开后暂停
  final PlaybackDetailContext? detail;
  final String origin;                  // gui / agent / classic_redirect / mesh / download / auto_next
}

final class Transport {
  final bool playIntent;                // 最后一次要求：播还是停
  final String intentBy;                // gui / agent / plan / swap / end_action
  final KernelTransport observed;       // 内核说的
  final Duration observedAt;
  final bool buffering;
  final Duration? seekTarget;           // 有跳转在途时非空
  final double rate;                    // 用户选择的倍速
  final double appliedRate;             // 内核正在用的（长按加速时两者不同）
  final double volume;
  final bool ended;
}

/// 位置外推的锚点。只在不连续处更新：跳转、播停、倍速变化、漂移超过 40 ms。
final class PlaybackClock extends ChangeNotifier {
  Duration get anchorPosition;
  Duration get anchorAt;
  double get rate;
  bool get advancing;
  Duration now();                       // 纯计算，不碰原生
}

final class PlaybackSession {
  String get id;                        // 每次打开一个；换内核时不变
  int get kernelGeneration;
  MediaRequest get request;
  ValueListenable<SessionPhase> get phase;
  ValueListenable<Transport> get transport;
  PlaybackClock get clock;
  ValueListenable<MediaFacts?> get media;      // 时长、宽高、章节、容器
  ValueListenable<TrackState> get tracks;
  SubtitleController get subtitles;
  DanmakuController get danmaku;
  ValueListenable<SkipState> get skip;
  ValueListenable<PlaybackFault?> get fault;
  ValueListenable<VideoSurface?> get surface;
  Stream<PlaybackEvent> get events;            // 带序号；hooks、wait、库进度都订阅这里
  SessionSnapshot snapshot();                  // O(1)，每个事实都带 source 和 at

  Future<CommandReceipt> setPaused(bool paused, {required String origin});
  Future<CommandReceipt> seek(Duration to, {SeekMode mode, required String origin});
  Future<CommandReceipt> setRate(double rate, {required String origin});
  Future<CommandReceipt> setVolume(double volume, {required String origin});
  Future<CommandReceipt> selectTracks(TrackRequest request, {required String origin});
  Future<CommandReceipt> step(int frames, {required String origin});
  Future<CommandReceipt> seekChapter(int index, {required String origin});
  Future<CommandReceipt> skip(SkipKind kind, {required String origin});
}

/// outcome：applied（观测已与意图一致）/ pending（在超时内还没确认）/ superseded / rejected
final class CommandReceipt {
  final int seq;
  final String command, outcome;
  final SessionSnapshot after;
}

// ---- core/host.dart ----
final class NextPlayerHost {
  ValueListenable<PlaybackSession?> get current;
  Stream<PlaybackEvent> get events;                    // 跨会话
  Future<PlaybackSession> open(MediaRequest request);  // 先关掉当前会话
  Future<void> close({required String reason, required String origin});
  Future<void> swapKernel(KernelId kernel, {required String origin});
  Future<void> retry({bool preservePosition = true, required String origin});
  PlayerSettings get settings;     // 共享设置键的读模型，变化即应用或标 reload_required
}
```

```dart
// ---- 字幕 ----
final class SubtitleController {
  /// 正在显示的字幕：轨道、渲染方（kernel / overlay）、谁选的（user / agent / library_selection / default）
  ValueListenable<List<PresentedSubtitle>> get presented;
  ValueListenable<CueFrame> get cues;      // 叠层此刻要画的行，只在行边界变化
  Future<void> choose(SubtitleChoice choice, {required String origin});   // 不变量：呈现的 == 选择的
  Future<String> mount(String pathOrUrl, {bool activate = true, required String origin});
  Future<void> unmount(String path, {required String origin});
  Future<CuePage> read({Duration? at, int context = 2, Duration? start, Duration? end,
      int limit = 100, int cursor = 0});   // subtitle.cues，在后台分页
}

/// 字幕库对播放的接口。取代 library.dart:534 的 attachPlayer(VideoPlayerState)，mesh 也用它。
abstract interface class SubtitleTarget {
  String? get path;
  Future<void> offer(String playbackPath, String title);
  Future<void> applyEmbedded(int index);
  Future<void> applyExternal(String playbackPath, String title);
  Future<void> clear();
}

// ---- 弹幕 ----
final class DanmakuController {
  ValueListenable<DanmakuTimeline?> get timeline;   // 版本、条数、分轨、渲染输入（后台构建）
  ValueListenable<DanmakuLook> get look;            // 可见、透明度（线性）、区域、字号、屏蔽…
  ValueListenable<List<double>?> get heat;          // 后台计算
  ValueListenable<double> get timeMs;               // 给现有渲染器的 playbackTimeMs，由时钟在 vsync 驱动
  Future<EntryPage> read(EntryQuery q);             // danmaku.entries，在后台分页
}

/// 弹幕服务现有的三个接口（lib/next/danmaku/service.dart:23-41）改由会话实现，取代 VideoDanmakuPort
final class SessionDanmakuPort
    implements DanmakuPlayerPort, DanmakuTrackRegistry, DanmakuTrackUpdater { /* … */ }
```

```dart
// ---- 能力端口：接口不变，实现换掉 ----
final class SessionPlayerPort implements PlayerPort { SessionPlayerPort(NextPlayerHost host); }
final class SessionControls implements PlaybackControlsPort, PlaybackInspectionPort { /* … */ }

/// 让 KernelControl 不再依赖 VideoPlayerState（kernel_control.dart:86-102）
abstract interface class KernelHost {
  String? get sessionId;
  String? get path;
  KernelDriver? get driver;
  Stream<KernelHostChange> get changes;          // 媒体换了 / 实例换了 / 会话关了
  Future<void> reopen(KernelId? kernel, {required String origin});
}

// ---- worker ----
final class PlaybackWorker {
  Future<DanmakuBuild> buildDanmaku(DanmakuInputs inputs);   // Isolate.run，结果经 Isolate.exit 零拷贝回来
  Future<CueIndex> parseSubtitle(String path);
  Future<List<SkipSegment>> detectSkip(SkipInputs inputs);
  Future<List<double>> heat(DanmakuTimeline t, Duration duration, int bins);
  Future<EntryPage> entries(DanmakuTimeline t, EntryQuery q);
}
```

**界面**

- `NextPlayerScope`（InheritedWidget，持有 host）。
- `NextVideoStage`：画面、字幕叠层、弹幕层、手势。它只订阅 session 的 listenable。
- `ClockText`（每秒对齐，只重建一个 Text）和 `ClockPainter`（时间轴的进度点，由 Ticker 读时钟重绘，不重建）。

现有的 `NextPlayback` 门面（`lib/next/ui/player/playback.dart:126`）保留它对菜单的方法签名，内部改为调用 session。

### 1.4 与 Classic 的关系：同一时刻只有一套在驱动内核

**Next 开着时 Classic 的播放器还在不在？** 在，但只作为空闲对象存在，永远拿不到媒体：

1. VPS 依旧由 `main.dart:673` 创建。很多 Classic 组件和设置读写依赖它，Classic 保持原样。构造时建的 `Player()`（VPS:1037）没有媒体，也不算在驱动内核。
2. Next 界面打开且新层承接播放时，`nextPlaybackRedirect` 非空。Classic 的 `initializePlayer` 开头就会把请求转给 `NextPlayerHost.open`，然后返回。这一个钩子覆盖了 Classic 的全部约 30 个入口：
   - 播放列表菜单、媒体服务器页、WebDAV 浏览、拖放、打开方式（`lib/utils/launch_file_handler.dart:33`、`main.dart:1320, 2312`）、Classic 的切集、热切换（pkm:244）。
   - Classic 里已经有同类钩子作为先例：`nextSubtitleLoader`、`nextLocalDanmakuLoader`（VPS:319-324）。
3. `KernelArbiter` 是硬约束：
   - Next 的驱动在构造时断言租约已持有。
   - `acquire(next)` 发现 Classic 正在播放时，调用它登记的 evictor，即 Classic 自己的 `resetPlayer()`（ctrl:60 起，会保存进度和观看记录），并等到 VPS 的 `hasVideo == false` 才返回。
   - 租约之外的 `initializePlayer` 记为 violation，在 `playback.state` 的诊断里可见。
4. 新层完全不引用 VPS。远程控制桥（`lib/services/player_remote_control_bridge.dart:18-35`）在 P6 改为按租约持有者路由。
5. Next 关闭或切回 Classic 界面：先关闭 Next 会话，保存进度，归还租约（D2）。

---

## 2. 状态机

### 2.1 会话阶段

| 阶段 | 由谁触发 | 做什么 | 完成条件 | 失败去向 |
|---|---|---|---|---|
| resolving | `host.open`（界面、Nipa、Classic 转交、播完动作） | 读保存的进度和观看记录；解析来源（Jellyfin/Emby 播放会话、WebDAV/SMB URL、插件源、mesh 直连）；读字幕库的选择和弹幕绑定（只读） | 得到 `ResolvedSource` | failed，stage 取 file_check / stream_session / remote_path |
| starting | resolving 完成 | 拿租约（必要时逐出 Classic）；按当前设置创建驱动并快照配置 | 驱动已创建 | failed（kernel_create） |
| loading | starting 完成 | `driver.open(source, start, tracks)` | 收到 `KernelReady` | failed（media_open / media_ready_timeout） |
| preparing | `KernelReady` | 执行打开计划（§2.3） | 计划走完 | 媒体可播但某一步失败：进入 active，在事实里记下这一步（例如 `subtitle.applyFailed`）；否则 failed（prepare） |
| active | preparing 或 swapping 完成 | 正常播放；传输子状态见 §2.2 | close、swap 或出错 | — |
| swapping | `swapKernel` | 见 §2.5 | 新驱动的 preparing 完成 | failed（swap），意图保留，可以 retry |
| failed | 任一步 | 保留请求和意图；写入 `PlaybackFailures`（`player_facts.dart:476-541`）；发 `playback.failed` | retry 回到 resolving；close 进入 closing | — |
| closing | close、打开新媒体、离开播放页、Next 关闭 | 最后一次写进度和观看记录；远端停止回报；释放驱动（§3.2）；归还租约 | 租约已归还 | 某步超时：记 fault；实例已栅栏且已停止，照样进入 closed |
| closed | — | 终态 | — | — |

### 2.2 传输状态：意图与观测

- **意图**（`playIntent`、`seekTarget`、`rate`、`volume`、轨道选择）在命令到达时同步修改，同时记下 `intentBy`。按钮图标读意图，所以下一帧就有反馈。
- **观测**（`observed`、`buffering`、`ended`、轨道的激活状态、位置样本）只由 `KernelEvent` 修改。时间轴、画面状态、给 Nipa 的事实以观测为准。
- **命令何时返回。** 会话把意图交给驱动，驱动在串行队列里执行；等观测和意图一致，或超时（默认 2 秒）后返回 `CommandReceipt`：
  - 一致时 outcome 为 `applied`；
  - 超时时为 `pending`，附上当时的快照。
  
  Nipa 读回执就知道结果，不用轮询。这同时取代了 `_settle` 的 50 ms 轮询（`kernel_control.dart:1175-1186`）和 `playback.wait` 的 50 ms 轮询。
- **从不乐观地改观测。** 现在 Classic 有一个反例：`seekTo` 在暂停时先把内核设成播放，100 ms 后再暂停（ctrl:956-987），于是内核真的播了约 100 ms。如果某个内核需要靠这种方式刷新画面，这件事放在驱动内部做，不报告为传输变化。

### 2.3 打开计划（在驱动的串行队列里执行）

1. `open(source, start: S, tracks: T)`，打开后保持暂停：
   - MDK：在 prepare 之前设置激活轨道，然后 `prepare(position: S)`（fvp:452-458）。
   - mpv：把 `start=S` 和 `aid`/`sid` 作为 file-local 选项。
   - Erika：先打开，再 `seekAndWait`（er:963-971）。
   - video_player：先 initialize，再 `seekTo`。
   - 完成条件：`KernelReady`。
2. 打开时没能满足的轨道选择，调用 `selectTracks(T)`，并等待 `KernelTracksChanged` 确认。MDK 换轨时会自己做一次 seek，驱动要等这次 seek 落定。
3. 如果落点离 S 超过 1 秒（例如 MDK 换轨把位置拉回了 0），就 `seek(S)` 并等待 `KernelSeekSettled(done)`，最多 3 次。cdf0db61 的重试逻辑搬到这里，从"兜底"变成计划里一个有序的步骤。
4. 挂载外挂字幕：ASS 在支持的内核上交给内核，其余交给叠层。然后应用倍速、音量、字幕样式。
5. **读取此刻的意图。** loading 期间用户按了暂停、或者 Nipa 发了 `paused:true`，都已经记在意图里。如果 `playIntent` 为真，就 `setPaused(false)` 并等待观测到 playing。
6. 进入 active。第一次观测到 playing 时发 `playback.started`。

打开时的默认意图：`playIntent = request.paused != true`。preparing 期间对外报告的位置是 `S`，`source` 标为 `seek_target`，所以界面不会先显示 0。

### 2.4 跳转、换轨与竞态

- **跳转只有一个槽位，后到的覆盖先到的。** 前一个跳转的回执标为 `superseded`。在途期间，时钟锚在目标位置并且 `advancing = false`，时间轴不会弹回原位。落定后按 `landed` 重新锚定。
- **MDK 换轨 = seek 到当前位置。** 驱动的处理顺序：
  1. 先记下时钟位置 P；
  2. 发换轨，等它内部那次 seek 落定；
  3. 如果在这期间用户又发了跳转，就按用户的目标重发；
  4. 否则检查落点，离 P 超过 1 秒就补一次 seek。
  
  第 3 类竞态（续播 seek 被取消）在这一步之后无从发生，因为所有原生操作都在同一个串行队列里，不会有两个 seek 并行。
- **暂停与跳转同时到达。** 两者都按队列顺序执行，暂停的意图在跳转落定之后应用。
- **长按加速**只改 `appliedRate`，不改 `rate`。松手后恢复 `rate`，同时重新锚定时钟（Classic 的对应逻辑在 pref:662-722）。

### 2.5 换内核

1. **冻结意图 I**，包括：
   - `playIntent`；
   - 位置：有跳转在途时取 `seekTarget`，否则取 `clock.now()`；
   - `rate`、`volume`；
   - 轨道身份：类型、语言、标题、编码，外挂字幕取路径；
   - 已挂载的外挂字幕；字幕样式。

   叠层字幕和弹幕属于应用侧，不受影响。
2. phase 置为 swapping。画面的 surface 置空，界面显示片名和脉冲（沿用现有的 `_Loading`，`player_layer.dart:1372-1404`）。
3. 按 §3.2 释放旧驱动，等待完成。
4. 在目标内核上创建新驱动，进入 loading，然后用 I 执行打开计划。轨道按身份匹配（语言 + 标题，音轨再加编码）；找不到时，若两边轨道数相同就用同一个索引，否则如实报告"没有匹配的轨道"。这段逻辑从 `kernel_control.dart:1228-1302` 搬过来。
5. `kernelGeneration++`，回到 active，发 `kernel_swapped` 事件，内容为 `{from, to, preserved:{位置、暂停、倍速、轨道 的前后值}}`。

会话 id 保持不变。I 从不读取观测状态，所以即使在 preparing 期间发起换内核，播放意图也会原样带过去，第 4 类竞态不会再出现。

在播放中保存 `player.kernel` 设置不会触发换内核，下一个会话会用新内核。事实里分别报告 `kernel.running` 和 `kernel.configured`。这样就不再需要 Next 自己的 `DeferredReloads` 跟踪（`lib/player_abstraction/player_factory.dart:30-90`；Classic 仍在用它）。

### 2.6 错误、重试、播完

- **出错。** `KernelFailed`，或计划中某个关键步骤失败，会进入 failed，记下 stage 和 category。分类沿用 `playbackFailureCategory`（`player_facts.dart:410`）和 `errorTextCategory`（同文件 382）。错误进入 `PlaybackFailures` 并触发 hook `playback.failed`。网络源的打开重试属于基础设施，上限沿用 `networkMediaLoadMaxAttempts = 5`（`lib/player_abstraction/abstract_player.dart:9`），每次尝试都记成事实。
- **播完。** 收到 `KernelEnded` 后，按 `player.playbackEndAction` 设置执行：下一集倒计时、循环、停在本集或退出。
  - 倒计时由会话持有，只在计数时每秒跳一次，可以通过 `playback.cancel_auto_next` 取消。
  - "下一集是哪一集"由库的事实决定：已有的 `PlayingWork.of`（`player_layer.dart:866`）或详情上下文。不加任何猜测。
  - Classic 的播完检测在 Ticker 里用"连续两次采样"和"末尾位置停滞"来判断（nav:6-15, 1437-1509）。新层改由驱动产生 `KernelEnded`：mpv 有 eof 事件；MDK 用 `MediaStatus.end`；Erika 用 Ended 状态。只有内核不报告时，驱动才在内部用停滞判断补上，并在事件里标 `inferred: true`。

---

## 3. 内核生命周期

### 3.1 不变量

| # | 不变量 | 对应的教训和依据 |
|---|---|---|
| I1 | **单租约**：只有租约持有者能创建和打开播放内核；驱动在构造时检查 | 两套状态各自驱动内核；热切换和 Classic 的打开交错 |
| I2 | **栅栏**：`release()` 在任何 await 之前同步设置 `fenced = true`。此后所有成员返回冻结的最后值或什么也不做，绝不调用原生；被栅栏实例的原生回调直接丢弃，并计入 `lateCallbacks` | 92a0025d 只给 MDK 补了 `_released`（mdk:376-389）；media_kit 只保护了 setMedia（mk:2264-2281）；Erika 有缺口（er:766-771, 869-885, 1130-1135）；video_player 完全没有 |
| I3 | **界面不碰原生**：组件只拿到 `VideoSurface` 和会话的 listenable。`Player` 不会逃出驱动；`KernelAccess` 同样走串行队列并检查栅栏 | 缺陷 1 的直接原因（`playback.dart:198, 326`） |
| I4 | **拆除顺序**：① 栅栏 → ② 在队列里停止传输 → ③ surface 置空，等 `SchedulerBinding.endOfFrame`，确保 Texture 组件已卸载、Erika 覆盖层先隐藏再按代数 detach（er:301-332）、mpv 原生视图已 detach（mk:3333-3398）→ ④ 释放视频输出和渲染上下文，等回复 → ⑤ 销毁核心并等待（MDK 在另一个 isolate 上 delete，fvp:178-185；mpv_terminate_destroy，mkreal:110-111）→ ⑥ 归还租约。每步超时 3 秒；超时后记 `release_timeout{step}`，只要 ①–③ 已完成就继续归还租约 | a789943e：先回复释放、晚一步才放渲染上下文，导致 mpv abort。Classic 的热切换只把 surface 代数加一，并不等界面真正销毁（pkm:94-105） |
| I5 | **不复活**：被栅栏的驱动永远不再接受 open；没有任何代码路径能清除栅栏 | a789943e：`setMedia` 清掉 `_isDisposed` |
| I6 | **一个会话一个实例**：每次会话和每次换内核都新建驱动，不跨打开复用；配置在创建时快照 | 缺陷 7（d43501d2） |
| I7 | **延迟回调绑定实例**：所有延迟闭包都捕获驱动实例和代数，不通过 getter 取"当前播放器" | 反例：ctrl:272-275 在 50 ms 后通过 `player` getter 再执行一次 `media=''`，热切换期间可能落到正在释放的实例上（MDK 会抛 StateError，mdk:428） |
| I8 | **串行**：每个驱动只有一个操作队列。打开计划、跳转、换轨、截图、属性读写都在队列里依次执行；界面命令从不直接调原生 | 缺陷 3 |
| I9 | **命令不跨会话**：带 `sessionId` 的命令遇到会话已变时返回 `conflict`；发给已关闭会话的命令返回 `session_closed` 并附快照，绝不转给下一个会话 | 现有的 `_session` 检查（`playback_inspection.dart:130-136`）保留下来并推广到所有命令 |

### 3.2 顺序

- **创建**：拿到租约 → 读 `PlayerSettings` 快照 → `PlayerFactory` 按内核构造适配器（复用，`player_factory.dart:517-555`）→ 驱动订阅原生事件 → surface 出现 → 界面挂上画面。
- **打开**：见 §2.3。
- **关闭和释放**：见 I4。Next 退出时（`next_runtime.dart:825-851`）先关闭会话，再做其余清理。
- **换内核**：旧驱动完成 I4 的全部步骤之后，才创建新驱动。中间有 0.5–1.5 秒的黑场，这是可以接受的，因为不允许两个实例同时存在。

### 3.3 四个内核的差异怎么收敛

| 维度 | MDK | media_kit (mpv) | Erika | video_player | 驱动怎么统一 |
|---|---|---|---|---|---|
| 事件 | 位置每次都同步调原生（mdk:461）；只有 MediaStatus/Event 回调，没有状态或错误事件（mdk:255-301） | 多条 Stream，用 Ticker 插值（mk:1094-1114, 3552-3614） | 一条 events 流，按墙钟外推（er:888-895, 1756-2019） | controller listener，Ticker 插值且不修正（vp:73-86） | 驱动统一产出 `KernelEvent`。MDK 的位置由驱动在队列里每秒采样 4 次，偏离时钟超过 40 ms 才发样本。三套插值器都由 `PlaybackClock` 替代 |
| 就绪 | 没有就绪信号；包装层回退为 `duration > 0`，`waitUntilMediaReady` 立即返回（pa:190-227） | 有（mk:2167-2215） | 没有 | initialize 有 15 秒超时 | 统一由 `KernelReady` 表示。MDK 用 prepare 的回调 + 视频尺寸；Erika 用第一个视频参数或时长事件 |
| seek | 可等待；新 seek 会以 -2 取消旧的，原生拒绝时为 -10（fvp:564-581） | 发出即不管，内部串行（mkreal:707-719） | 可等待，1.5 秒围栏（er:963-971, 1893-1911） | 不等待 | 统一 `Future<SeekOutcome>`，结果为 done / superseded / rejected。mpv 通过 `seeking` → false 加 `playback-restart` 确认 |
| 换轨 | 内部实现为 seek（cdf0db61） | 设属性，由事件回写（mk:2014-2146） | 字幕可等待，音轨不可（er:835-885） | 不支持 | 统一 `Future<TrackSelection>`，按 §2.4 串行 |
| 字幕 | 内核渲染；外挂用 `setMedia(subtitle)`（mdk:526）；**这版 MDK 是否内置 libass 尚未核实** | libass 渲染（mk:367, 931-933）；轨道列表不含外挂（mk:1309-1310） | 原生合成；外挂可等待（er:1137-1217） | 不支持 | `capabilities.assByKernel` 决定 ASS 交给内核还是叠层；SRT/VTT 一律叠层（沿用 `lib/utils/subtitle_manager.dart:939-960` 的事实规则） |
| 截图 | RGBA；失败时给黑帧，宽高可能为 0（mdk:609-627） | PNG/JPEG 编码数据（mk:2673-2717） | RGBA，带校验（er:1016-1052） | 封面或占位帧（vp:557-799） | `KernelFrame` 带格式、真实尺寸和 `placeholder` 标记 |
| 视频输出 | fvp 纹理 | 纹理，或 macOS/Windows 原生视图（mk:3144-3398） | 没有纹理：窗口覆盖层或平台视图（er:224-573, 1295-1322） | 纹理 | sealed `VideoSurface` |
| 释放 | fvp 已修好（761f06aa） | Darwin 已修好（a789943e）；**Windows 很可能还有同类竞态**（推断：`packages/media_kit_video/windows/video_output.cc:144-146` 把渲染上下文的释放投递到线程池异步执行） | 原生 dispose 会等创建完成（erika_flutter 0.2.1） | `controller.dispose` 不等待（vp:211-244） | 走 I4；Windows 在 P4 前要先修 |

**适配器需要补的能力。** 都是增补，不改 Classic 已有的语义：

1. MDK：暴露 onStateChanged 和 invalid 状态（不再只是写日志）；`open` 支持起点和起始轨道；`media=` 在栅栏后不再抛异常（mdk:428）。
2. media_kit：除 setMedia 外，其余成员都加 `_released` 保护；`seek` 改为可等待；外挂字幕返回轨道引用；修 Windows 渲染上下文的释放顺序。
3. Erika：给 volume、rate、音轨加保护；提供就绪和 seek 结果的信号。Erika 是我们自己的内核，可以在 liberika 里直接补。
4. video_player：加栅栏，dispose 改为可等待，补上就绪信号。
5. 统一用静态能力表，取代 `try/catch + dynamic`（pa:390-478, 550-805）。

---

## 4. 线程与性能

### 4.1 主线程上允许做什么

**允许：**
- build、layout、paint；
- 把内核事件归约成快照，每个事件 O(1)；
- 往驱动队列派发操作，这些 FFI 调用都很快返回，慢的（截图）在原生侧异步完成；
- 路由能力调用，格式化一个快照（几百个字段以内）；
- 修改 `ValueNotifier`。

**禁止：**
- 任何对弹幕、字幕行、观看记录的 O(n) 遍历；
- 解析文件；
- 对超过 1 千项的列表做 jsonEncode 或 jsonDecode；
- 同步文件 IO（`existsSync`、`listSync`）；
- 对超过 100 行的数据库结果做后处理；
- 图片编解码；
- 周期短于 250 ms 的轮询；
- 以位置更新的频率调用覆盖面很广的 `notifyListeners`。

### 4.2 后台 isolate 与 Rust 分工

| 工作 | 放在哪 | 理由和依据 |
|---|---|---|
| 弹幕时间线构建：合并多轨、轨道偏移、折叠去重、屏蔽词、类型屏蔽、随机色 | 后台 isolate（`Isolate.run`，结果经 `Isolate.exit` 零拷贝回到主线程，可以直接交给渲染器的 `List<Map>`）；如果屏蔽词匹配或折叠超出预算，再下沉到 Rust（已依赖 aho-corasick，`rust/Cargo.toml`） | 现在全在主线程（dm:635-771） |
| 热度 | 在后台调用 Rust 的 `analyzeDensity`（`rust/src/api/danmaku_analytics.rs:25`） | 现在在 build 里同步调用（`playback.dart:184`） |
| 片头识别（弹幕报点） | 后台，复用 `lib/services/intro_skip/danmaku_intro_detector.dart` | Classic 在 2 万条以内时在主线程算（intro:106-127） |
| 字幕解析和行索引 | 后台，复用 `SubtitleParser.parseSubtitleFile`（`lib/utils/subtitle_parser.dart:779-802`） | 叠层只拿"此刻的行" |
| `danmaku.entries`、`subtitle.cues` 分页 | 后台，基于时间线快照 | 现在在主线程遍历全量 |
| 文件头哈希（弹弹play 匹配） | Rust `hashFileHead`（`lib/src/rust/api/media_probe.dart:21`） | 替代 meta:625-628 |
| 续播进度 | 主线程只交出 (path, ms)。`PlaybackPositionStore` 已在 compute 里编码（`lib/services/playback_position_store.dart:41-53`）。写入时机：每 5 秒，以及暂停、跳转落定、关闭时 | — |
| 观看记录 | 通过 sqflite ffi 直接写库（它有自己的 isolate），每 10 秒一次，以及打开和关闭时。播放过程中不刷新 `WatchHistoryProvider`，只在打开和关闭时刷新一次 | 避免每 10 秒一次的全表排序加 notify |
| 媒体信息 | 打开时由内核事件带出一次；`playback.info` 通过驱动队列异步读取 | 不再让界面读原生 |
| 远端回报（Jellyfin/Emby/共享库/mesh） | 异步 HTTP：每 10 秒一次，以及暂停、跳转、停止时；主线程只组装小 JSON | 修掉 Classic 稀疏回报的问题（dm:1536, 1550 的 `% 1000 < 100` 条件） |
| 截图编码、时间轴缩略图 | 后台。缩略图用 media.frames 的独立解码器（`media_frames_mdk.dart`），取代 Classic 在第二个播放器实例上 seek → 播 70 ms → 截图 → 在主线程编码的做法（tl:210-362） | — |

### 4.3 推送与订阅

```
原生回调/流 ─► 驱动（串行队列、栅栏、过滤） ─► KernelEvent
                                                  │
                                       会话归约（O(1)，记 source/at）
                ┌──────────────┬──────────────┬───┴──────────┬───────────────┐
           transport       PlaybackClock     tracks/media  subtitles.cues   events（带序号）
          （按钮/状态）   （只在不连续时变）   （打开/换轨时）  （行边界时）     │
                │              │                                          ├─ hooks: playback.started/state_changed/
                │     时间轴进度点：Ticker 读 clock 重绘，不重建            │   ended/seek_requested/failed
                │     时间文字：ClockText 每秒对齐重建一个 Text           ├─ playback.wait：订阅事件，按条件完成
                │     弹幕：DanmakuController.timeMs 由 vsync 驱动        ├─ 弹幕服务：只在 media_changed/binding 事件时 refresh
                │          （控件隐藏或弹幕关闭时停掉）                     ├─ ui_data：progressSaved / watchRecordChanged
                └─ Nipa 的事实：snapshot() O(1)                            └─ mesh 进度：progressSaved
```

- 界面不使用总的 ChangeNotifier，每个组件只订阅自己要的那一片。控件隐藏时，播放层每秒的重建次数是 0；字幕叠层只在行变化时重建。
- **弹幕渲染器原样复用。** next2、DFM+ 等渲染器本来就接收 `ValueListenable<double> playbackTimeMs` 和 `danmakuList`（`lib/danmaku_next/nipaplay_next2_overlay.dart:14-47`、`lib/danmaku_dfm/dfm_plus_overlay.dart:17-45`），所以只需要把这两个输入换成会话提供的。
- 发给 hooks 的事件名和现在一致：`playback.started`、`playback.state_changed`、`playback.ended`、`playback.seek_requested`、`playback.failed`（`lib/next/harness_hooks.dart:39-40`）。

### 4.4 预算

| # | 指标 | 预算 |
|---|---|---|
| B1 | 播放层单次主线程任务（事件归约、命令派发、监听回调、能力处理） | p99 ≤ 2 ms，最大 ≤ 4 ms |
| B2 | 稳态播放、无交互时，播放层占用主线程的时间 | ≤ 3% |
| B3 | 控件隐藏时播放层的组件重建 | 0 次/秒（字幕换行除外）；控件显示时 ≤ 2 次/秒 |
| B4 | 帧耗时：120 Hz、3000 条弹幕（DFM+ 或 next2） | build p95 ≤ 4 ms，raster p95 ≤ 8 ms |
| B5 | 播放期间，归因到播放层的事件循环卡顿 | 0 次超过 16 ms（全局卡顿归修卡顿的子代理，但同一个探针一并报告） |
| B6 | 延迟 | 命令到按钮反馈 ≤ 1 帧；本地跳转确认 p95 ≤ 300 ms；本地打开到首帧 p95 ≤ 800 ms（P0 先量基线）；换内核 ≤ 2.5 s；关闭到归还租约 ≤ 500 ms |
| B7 | 后台 | 3 万条弹幕重建时间线 ≤ 150 ms；字幕解析 ≤ 100 ms |

### 4.5 怎么自动测

1. **`lib/next/player/perf/budget.dart`。** 播放层每个主线程入口都包一层 `PlayerPerf.span(name, fn)`，用 Stopwatch 计时，profile 构建里同时打 `Timeline.timeSync`。按名字记录直方图（p50/p95/max）和最慢的 20 次。另外：
   - 播放层组件挂 `RebuildProbe` 计数；
   - `SchedulerBinding.addTimingsCallback` 记录帧耗时；
   - 实验配置下再加一个 4 ms 精度的事件循环延迟探针。
   
   这些都通过 `ext.nipaplay.player.perf`（read/reset）暴露，汇总也写进 `runtime.diagnostics`。
2. **单元预算测试** `test/next/player/budget_test.dart`：用 FakeDriver 按真实内核的频率模拟 10 分钟事件，加上 3 万条弹幕，断言 B1–B3；CI 上阈值放宽 3 倍，用来防回归。
3. **成品验收脚本** `scripts/next/player_accept.py`：在实验配置（`NIPAPLAY_PROFILE`）的 profile 构建上，经端点和 VM service 跑每个阶段的场景，期间同时跑一个 Nipa 回合；结束时拉取 perf 数据，超出预算就判失败；结果记入 `docs/next/EXPERIMENTS.md`。

---

## 5. 事实与原语

### 5.1 Nipa 能读到的事实（都带来源和时间）

- **会话**：`sessionId`（换内核时不变）、`kernelGeneration`、`phase` 及进入时刻、`route`（next_core / classic，D5）、请求（路径已脱敏、origin）、打开时刻。
- **传输**：
  - `paused`：`{intent, intentBy, observed, observedAt, source:'kernel'}`；
  - `buffering`：`{value, since, source: kernel | unsupported}`；
  - 倍速：`{chosen, applied, kernel}`；
  - `volume`；
  - `seek`：`{target, issuedAt, outcome, landed}`；
  - `ended`。
- **位置**：`{ms, at, source: kernel_sample | clock | seek_target}`；时长：`{ms, source: kernel | library}`。
- **内核**：
  - id、name、instance、版本；
  - `config`（创建时的快照）；
  - `configured` 和 `running`；
  - 栅栏与释放记录（`lateCallbacks`、`release_timeout`）；
  - `playback.info` 的完整媒体事实，从驱动队列读取，带 `observedAt`。
- **轨道**：稳定 id、kind、origin（embedded / external / server）、`renderer`（kernel / overlay）、`selected`、`selectedBy`（user / agent / library_selection / default）、对应的字幕库选择 id。
- **字幕**：正在呈现的列表，以及此刻的行（`subtitle.cues` 分页）。
- **弹幕**：
  - 轨道：bindingId、条数、偏移、是否启用、来源；
  - 时间线版本；
  - 渲染器；
  - 实际应用的外观：透明度是线性值，事实里写明；
  - entries 分页。
- **片头片尾**：kind、来源（aniskip / danmaku_reports / chapters）、证据数、计算时刻、所依据的输入版本（弹幕版本、时长、章节）。
- **故障**：stage、category、内核原话、`kernelRetryable`、`failureId`。
- **租约**：持有者、`violations`。
- **性能**（诊断）：§4.5 的汇总。

### 5.2 原语

- `open`（起点、起始暂停、来源）、`close`、`set_paused`、`seek`（绝对或相对，精确或关键帧）、倍速、音量。
- `select_track`、`load_subtitle`、`remove_subtitle`，字幕样式（经 settings）。
- 弹幕轨道：启用、偏移、折叠（经现有 danmaku.* 动作）。
- 章节、逐帧、跳过片段、`cancel_auto_next`、`switch_episode`。
- `reopen_with_kernel`，以及内核属性 set/restore/command/invoke/watch。
- 截图和 GIF、`retry`、`wait`（由事件驱动）。

### 5.3 现有 `playback.*` 怎么迁移

原则：动作 ID、输入 schema、输出主体保持不变。新层通过实现现有端口接入，即 `PlayerPort`、`PlaybackControlsPort`、`PlaybackInspectionPort`，以及新的 `KernelHost`（替换 `KernelControl` 的构造参数）。

| 动作 | 现在的实现 | 新实现 | 行为变化 |
|---|---|---|---|
| `playback.open/state/set_paused/seek/switch_episode` | `video_player_state_port.dart`，`playback_capability.dart:43-352` | `SessionPlayerPort` | 等观测确认后才返回；`startPositionMs` 并入打开计划，不再"打开之后补一次 seek"（`playback_capability.dart:173-175`），不会再和续播打架 |
| `playback.wait` | 50 ms 轮询（`playback_inspection.dart:147-175`） | 订阅事件 | 语义不变 |
| `playback.retry/info/failures/cancel_auto_next/chapters/navigate/playlist` | `PlaybackInspection` | `SessionControls.inspect` | `retry` 只走 `host.retry`，不再"重开后补 seek 和暂停"（同文件 221-242） |
| `subtitle.cues`、`danmaku.entries` | 主线程遍历和解析 | 后台分页 | 输出不变；`listVersion` 改为时间线版本 |
| `playback.tracks/select_track/load_subtitle/remove_subtitle` | `classic_playback_controls.dart:78-260` | `SessionControls` | 按"呈现的 == 选择的"执行，结果带 renderer 和 selectedBy |
| `playback.stream_options/select_stream` | 同上 261-530 | P5 接入新的来源解析 | 换清晰度时，会话内重开并保持意图 |
| `playback.capture/close/external/external_state/authorize_directory` | 同上 536-708 | P6 | — |
| `playback.kernel/set_kernel_properties/restore_kernel_properties/kernel_command/kernel_invoke/watch_kernel_properties/reopen_with_kernel` | `kernel_control.dart`，直接持有 VPS | 同一个 `KernelControl`，构造参数换成 `KernelHost` | `reopen_with_kernel` 之后 `sessionId` 不变（以前会变），`preserved` 字段照旧。`_settle` 和 `DeferredReloads` 监听改为订阅事件和每会话新建实例 |
| `playback.levels`、`window.*`、`danmaku.send`、`playback.external.danmaku*` | `local_playback_operations.dart` | 读写会话的音量和窗口 | — |
| `settings.*` 中的播放项 | 通过 `ApplicationSettings.video` 调 VPS 的 setter（`lib/next/settings/application_settings.dart:203-209`，约 80 个） | 写共享键，由 `PlayerSettings` 读模型应用到会话；VPS 的 setter 照旧写 prefs（D3） | effective 值以会话实际应用的为准（`lib/next/settings/effective.dart:36`） |

`sessionId` 的格式保持 `internal:<pid>:<n>:<m>` 这种不透明字符串。工具描述里补一句"换内核后不变"。

---

## 6. 复用与重写清单

| 项 | 处置 | 理由 |
|---|---|---|
| 内核适配器（`lib/player_abstraction/*_adapter*.dart`）、`Player`、`PlayerFactory` | **复用，并包一层驱动**；按 §3.3 增补 | 平台差异和原生细节都在里面，其中 4130 行 media_kit 适配器尤其不该重写；它们缺的是统一的事件和生命周期契约 |
| `PlayerKernelManager` 热切换 | **不用**，由 `swapKernel` 重写 | 先 `resetPlayer` 清空一切，再 `initializePlayer` 重新决定轨道（pkm:204-254），丢失了用户的选择 |
| `VideoPlayerState` 及其 part 文件 | **不用** | 用户的决定 |
| `SubtitleManager`（2311 行） | **不用**，由 `SubtitleController` 重写（约 600 行） | 和 Player 绑定，而且外挂叠层与内嵌轨会同时显示（`subtitle_manager.dart:962-967`），正是 e2e 里"中文外挂和德语内嵌同时显示"的原因 |
| `SubtitleParser`、`subtitle_service.dart`、`remote_subtitle_service.dart` | **复用**，放在后台运行 | 纯解析和存取 |
| `ExternalSubtitleOverlay`（1080 行，Consumer\<VPS\>） | **重写**为精简的 `NextSubtitleLayer`；文字描边和阴影的绘制函数抽出来复用 | 耦合 VPS，并且自带编辑交互；Next 的字幕编辑走能力层 |
| 弹幕渲染器：next2、nipaplayNext、DFM+、GPU、canvas | **复用**（这些不依赖 VPS） | 输入就是 `List<Map>` 加时间 listenable |
| `DanmakuOverlay`（Consumer\<VPS\>，`lib/widgets/danmaku_overlay.dart:53`） | **重写**为 `NextDanmakuLayer` | 它只是按 VPS 做分发 |
| CPU `DanmakuContainer` | **包一层**（去掉 Provider 读取，`danmaku_container.dart:445, 833`），或在 Next 中不提供 | 在组件里做合并，主线程负担重 |
| 插件 WebView 弹幕渲染器 | **包一层**适配接口（目前收 `videoState`，`plugin_danmaku_webview_overlay.dart:234`） | 涉及插件 API |
| Classic 弹幕合并和过滤逻辑（dm:635-771） | **移植**到后台构建，规则逐条保持一致 | 语义要和 Classic 相同 |
| `DanmakuMatchingService` 哈希匹配、`DanmakuCacheManager`、`dandanplay` 服务 | **复用** | NipaPlay 自己唯一的匹配就是这个哈希匹配；结果写成带来源的绑定 |
| Next 弹幕服务和仓库（`lib/next/danmaku/*`） | **复用**；`VideoDanmakuPort` 换成 `SessionDanmakuPort`；`_HostPlayerPort` 不再挂在 VPS 的 notify 上 | 接口本来就和 VPS 无关（service.dart:23-41） |
| 片头服务（aniskip、danmaku_intro_detector、skip_segment、skip_id_resolver） | **复用**，触发方式改为"输入变化即重算" | 和 VPS 无关 |
| `PlaybackSourceService`、Jellyfin/Emby 服务、`*_playback_sync_service`、SMB 代理、WebDAV | **复用**，`source/resolver.dart` 包一层 | 和 VPS 基本无关（只有注释提到它） |
| `PlaybackPositionStore`、`WatchHistoryDatabase`、`WatchHistoryManager` | **复用**，和 Classic 共用（D3） | 继续观看在两边一致 |
| `AutoNextEpisodeService`（耦合 VPS） | **重写**为会话的播完动作 | 下一集由库的事实决定 |
| 截图（cap，在主线程用 RepaintBoundary 加编码） | **重写**：驱动截图，加上叠层合成，编码放后台 | — |
| 时间轴预览（tl，第二个播放器实例） | **重写**：用 media.frames 的引擎在后台生成 | 不再占用第二个播放内核 |
| `DesktopPlayerWindowService`（画中画、分离窗口，用 GlobalKey 重挂 Classic 播放页） | **包一层**，P6 改为重挂 `NextVideoStage` | 同引擎多窗口的机制可以复用 |
| `ExternalPlayerConsoleService` | **复用**，作为"外部会话"的一种 | — |
| `HotkeyService`、Classic 右键菜单和点按手势 | **重写**为 Next 自己的（少量） | 现在还在借 Classic 的 |
| `media.frames`、`kernel_facts`、`player_facts` 中的纯函数 | **复用** | — |
| `NextPlayback` 门面和 Next 播放界面（`lib/next/ui/player/*`，约 3.9k 行） | **保留**结构，数据来源换成会话 | 菜单已经全部通过门面访问 |
| `NextUiGate` | **改**：新层承接时不再露出 Classic，在 `NextStageRoom` 里放 `NextVideoStage` | — |

---

## 7. 迁移阶段

**通用规则：**
- Labs 里加一个开关"Next 播放层"（`next.playerCore`）。
- 开关打开且（来源，内核）已被新层支持时，走新层；否则走 Classic 的播放器（D5），即今天的路径。走哪条路写在事实 `route` 里。
- 每个阶段都按成品验收：在实验配置下用真实片源，在 App 里真的播放、跳过中点、看画面。媒体服务器一律用一次性容器（colima nipa-test）。

### P0 接缝与量尺

**交付物：**
1. `NextPlayback` 接口扩展为会话的公开形状（§1.3），先由 `ClassicBackedPlayback` 实现，把 `lib/next` 里 20 个文件对 VPS 的直接引用收进去。
2. Next 模块只订阅"状态或路径变化"这类低频事件，不再挂在 VPS 每 120 ms 一次的 notify 上：DanmakuRuntime、KernelControl、`_Watch`、NextRuntime hook。
3. `KernelArbiter` 骨架、Classic 的转交钩子（此时还不启用）、perf 探针和 `ext.nipaplay.player.perf`。

**验收：**
- Next 现有的播放全部照常：打开本地剧集、跳到 70% 后位置继续前进、`reopen_with_kernel` 到 mpv 再回来、关闭后重开能续播。
- 稳态播放 1 分钟，`refreshCurrent` 被调用的次数从约 480 次降到 ≤ 2 次。
- 记录 B1–B6 的基线。

**规模：** 新增约 6 个文件、1.3k 行；改动约 14 个文件、600 行。

### P1 核心与 MDK 本地播放

**交付物：**
- core（会话、host、租约、时钟、事件、意图）；
- `KernelDriver` 和 MDK 驱动，包括 MDK 适配器的增补（`prepare(position:)`、状态事件、栅栏）；
- `NextVideoStage`（画面加手势）；
- 进度和观看记录；
- Next 播放界面的传输控制、时间、音量、倍速、全屏接入会话；
- 能力：`playback.open/state/set_paused/seek/wait/close`；
- 启用转交钩子。

**验收：**
1. 开关打开后，从界面和从 Nipa CLI 各打开一个本地剧集，有画面、有声音。
2. `playback.seek` 到 70%，1 秒内位置从那里继续前进。
3. 暂停后恢复。
4. 关闭再重开，从保存的位置续播（±2 秒），连续 20 次 0 次从头开始。
5. 打开过程中连续 100 次快速打开和关闭，0 次崩溃，租约日志里 Classic 一次都没拿到媒体。
6. 从 Classic 的入口（拖放文件）打开，会转进 Next。
7. B1–B3 达标。
8. 实测 MDK 每会话新建实例的耗时（D6）。

**规模：** 新增约 16 个文件、3.8k 行；改动约 8 个文件、400 行。

### P2 轨道与字幕

**交付物：**
- 内嵌音轨和字幕轨的列表与选择（等待确认）；
- 外挂字幕：叠层或内核渲染；
- `NextSubtitleLayer`；后台解析和行索引；
- 字幕样式、延迟、缩放设置；
- 字幕库和 mesh 通过 `SubtitleTarget` 接入；
- `playback.tracks/select_track/load_subtitle/remove_subtitle`、`subtitle.cues`。

**验收：**
1. 一个带多语言内嵌字幕、外加中文 SRT 的视频：打开时只显示字幕库记录的那一条（截图核对，没有德语内嵌轨同时出现）。
2. 从菜单和从 Nipa 切换字幕，都立即生效。
3. 调整延迟和缩放，画面上看得到变化。
4. `subtitle.cues` 返回的就是画面上那一行。
5. 选了内嵌字幕的视频在 MDK 上续播，20 次都从保存的位置开始。

**规模：** 新增约 8 个文件、2.4k 行；改动约 6 个文件、300 行。

### P3 弹幕

**交付物：**
- 后台构建弹幕时间线（规则从 Classic 移植）；
- `NextDanmakuLayer` 承载复用的渲染器；Erika 原生弹幕走驱动；
- 时钟驱动；线性透明度（D4）；
- 后台计算热度；`danmaku.entries` 后台分页；
- `SessionDanmakuPort`；
- 片头识别在输入变化时重算。

**验收：**
1. 用 e2e55 那集（3227 条弹幕）：跳过中点后弹幕同步，截图和那个时刻的 `danmaku.entries` 一致。
2. 改屏蔽、显示区域、透明度，下一帧就生效；透明度 0.5 的实际 alpha 是 0.5（像素取样核对）。
3. 同时跑一个 Nipa 回合，B5 达标。
4. 模拟网关慢 30 秒、弹幕晚到：之后片头事实出现，"跳过片头"按钮出现。
5. B7 达标；如果超标，把屏蔽和折叠下沉到 Rust 后复测。

**规模：** 新增约 9 个文件、2.8k 行 Dart，可选约 400 行 Rust；改动约 6 个文件、300 行。

### P4 其余内核、换内核、内核控制、设置

**交付物：**
- media_kit 驱动（纹理和 macOS 原生视图）、Erika 驱动（覆盖层）、video_player 驱动，以及它们的适配器增补；Windows 上的 media_kit 释放修复；
- `swapKernel`；
- `KernelControl` 改为接收 `KernelHost`；
- `PlayerSettings` 读模型：共享键变化时应用到会话，或标为 `reload_required`。

**验收：**
1. 在 40% 处播放，挂着外挂字幕和弹幕。`reopen_with_kernel` 切到 mpv：画面在同一位置（±1 秒），播放或暂停状态和切换前一致，音轨和字幕轨一致，弹幕继续。
2. MDK、mpv、Erika 之间循环换 50 次，中间穿插跳转：0 次 SIGSEGV 或 abort，0 次从 0 开始。
3. 播放中 `settings.set player.kernel`：当前播放不受影响，下一次打开用新内核，`settings.get` 的 effective 值如实。
4. 如果 D7 选了 Windows，在 Windows 上重复第 2 项。

**规模：** 新增约 6 个文件、2.8k 行；改动约 8 个文件、700 行。

### P5 网络源与剧集

**交付物：**
- Jellyfin/Emby（播放会话、服务端轨道、版本、清晰度、转码、换流）、WebDAV、SMB、弹弹play 远程、NipaPlay 共享库、mesh（每次打开直连、对端进度、资源包）；
- 按真实间隔做远端回报；
- 剧集菜单、上一集和下一集、播完动作与倒计时；
- `playback.playlist/switch_episode/stream_options/select_stream/cancel_auto_next`。

**验收：**
1. 一次性容器里的 Jellyfin 和 Emby：播放、跳过中点、切服务端音轨、改清晰度后在同一位置重开；服务端显示的进度和本地一致（±10 秒）。
2. WebDAV 和 SMB 的文件能播放、能续播。
3. 通过 mesh 播对端的剧集，进度记到对端。
4. 一集播完后倒计时进入下一集；取消倒计时有效。

**规模：** 新增约 7 个文件、2.6k 行；改动约 5 个文件、300 行。

### P6 其余对等功能与收尾

**交付物：**
- 截图和 GIF、时间轴预览、章节、逐帧；
- 画中画和分离窗口、外部播放器会话、窗口控制、Next 自己的快捷键、远程控制桥；
- `playback.capture/retry/failures/info/levels/navigate/chapters`；
- 删除 `ClassicBackedPlayback`：Next 界面下不再走 Classic 播放器；`VideoPlayerStatePort` 只在 D1 的场景下使用；
- Labs 开关默认打开，或者直接移除这个开关。

**验收：**
1. 能力目录前后对比：0 个动作丢失，schema 一致。
2. 一个脚本把每个 `playback.*` 动作对会话真实调用一遍，全部通过。
3. 含弹幕的截图和屏幕上看到的一致。
4. 进出画中画，播放不中断。
5. 完整重做一次"边看边聊"实验（参照 e2e53、e2e55）：答案都对，没有归因到播放层的卡顿超过 16 ms。

**规模：** 新增约 8 个文件、2.8k 行；改动约 10 个文件；删除约 1.5k 行。

### 合计

新增约 1.8–2 万行，与 Classic 播放相关代码的规模相当（VPS 约 1.65 万行，加上 SubtitleManager 和热切换约 0.3 万行）。区别在于：主线程上的部分小得多，生命周期和竞态由结构保证。

---

## 8. 风险与未决问题

### 8.1 需要你拍板

- **D1　Next 界面关闭、Nipa 开着（Classic 界面）时，`playback.*` 驱动谁？**
  - 建议：驱动 Classic 播放器，沿用现有端口，冻结不加新功能；新能力只在 Next 界面下提供。
  - 备选：这种模式下播放类原语一律返回"需要打开 Next 界面"。
  - 背景：Next 界面只在桌面，而且需要 `enableAgentEndpoint` 和偏好同时打开（`next_ui_gate.dart:61-62`）；移动端只有 Classic。
- **D2　播放中切换 Next 和 Classic 界面。**
  - 建议：关闭当前会话并保存进度，另一边的"继续观看"里能看到。
  - 备选：在另一边自动从同一位置重开，会多一次 0.5–1.5 秒的打开。
- **D3　共用存储。**
  - 建议：设置（同一批 SharedPreferences 键）、续播进度（`video_positions`）、观看记录表都和 Classic 共用。
  - 后果：D4 的取值语义要统一。
- **D4　弹幕透明度。**
  - 建议：Next 按线性应用。
  - 如果 Classic 不改，同一个设置值在 Classic 里看起来更淡；`settings.describe` 会如实写明。要不要把 Classic 的那一行平方（pref:353）也改掉，由你决定。改的话会碰 Classic，但 Classic 的 Erika 原生弹幕和 ASS 导出本来就是线性的。
- **D5　迁移期间的分流。**
  - 建议：新层还不支持的（来源，内核）继续走 Classic 播放器，Next 的控件照样盖在上面，`route` 写进事实。
  - 备选：只开放已支持的，其余返回 unavailable。这样每个阶段的可用范围会缩小。
- **D6　每个媒体会话新建内核实例。**
  - 建议：是。代价是切集时多出建实例的时间，P1 实测；粗估 MDK 几十毫秒、mpv 100–300 ms。
  - 备选：配置没变时复用。但第 7 类缺陷就是复用造成的，不建议。
- **D7　平台顺序。**
  - 建议：P1–P3 只验收 macOS；P4 起加 Windows，前提是先修 media_kit 在 Windows 上的释放竞态；Linux 跟着 Erika 走。
- **D8　冷门功能的范围。** 涉及：防剧透 AI、CRT、Anime4K 和双倍分辨率、发送弹幕、时间轴弹幕、插件渲染器设置、大屏模式、移动端亮度。
  - 原则："能力层能改的都要生效"，这些在 `settings.*` 里都已经能改。
  - 建议：P6 前允许在 `settings.describe` 里如实标"只作用于 Classic 播放器"，我列出清单，由你逐项勾选哪些必须在新层做。

### 8.2 技术风险

1. **MDK 能否在 `prepare(position:)` 之前设置激活轨道，以及之后换轨是否还会触发自己的 seek。** 这一点未验证，是 P1 的第一个实验。不行的话，退回 §2.3 第 2–3 步的顺序（换轨 → 确认 → 定位），仍然可以保证正确。
2. **media_kit 在 Windows 上的释放竞态。** 这是推断，没有复现过（`packages/media_kit_video/windows/video_output.cc:144-146`、`video_output_manager.cc:41-48`）。P4 前要修。
3. **Erika。**
   - 适配器的释放保护不全（er:766-771, 869-885, 1130-1135）；
   - 窗口覆盖层有一个 250 ms 的周期同步（er:334-344）；
   - 与 `NextStage` 的 stepped 布局要配合（`stage.dart:15-18`）。
   
   Erika 是我们自己的内核，补就绪信号和 seek 结果信号需要发 liberika 的新版本，发版要你同意。
4. **fvp 的同步 FFI 在主线程。** 驱动只在队列里低频调用，但最坏情况下的耗时还要在 P1 实测；如果超出 B1，就把采样移到原生侧的回调里。
5. **弹幕渲染器的输入是 `List<Map>`。** 3 万条时构建和传递的成本依赖 `Isolate.run` 的零拷贝，P3 实测。
6. **画中画和分离窗口。** 要在同引擎多窗口里重挂 `NextVideoStage`（`desktop_player_window_service.dart:52-108`）。
7. **插件弹幕渲染器。** 它的接口绑着 VPS，改成适配接口可能影响插件作者。
8. **与修卡顿子代理的边界。**
   - 首页数据服务的 250 ms 轮询（`lib/next/ui_data/service.dart:85-108`）、DSH 消息处理、其他周期定时器都归它。
   - 播放层提供 `progressSaved`、`watchRecordChanged` 事件，供它的数据服务订阅，以替代轮询。
   - P0 第 2 项（Next 模块不再挂在 VPS 的 notify 上）动手前要先和它对齐，避免重复修改同一处。
9. **工作量。** 合计约 2 万行，分 7 个阶段，每个阶段单独交付。

### 8.3 待查清的技术事实（不需要你决定）

- 当前的 MDK 构建是否内置 libass。这决定 ASS 字幕在 MDK 上由内核渲染是否成立。现在 Classic 的规则默认成立（`subtitle_manager.dart:952-954`）。
- 在后台 isolate 里调用 Rust（flutter_rust_bridge）的初始化成本。这决定弹幕和热度的 Rust 计算放在哪个 isolate。
- 每个内核的"播完"信号是否可靠，用来取代 Classic 的停滞判断（nav:6-15）。
