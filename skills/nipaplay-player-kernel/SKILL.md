---
name: nipaplay-player-kernel
description: Use when touching player kernel hot-swap, kernel adapters (MDK/MediaKit/Erika), embedded/external subtitle track switching, or diagnosing playback freezes on iOS/WebDAV sources. Documents the hot-swap chain, per-adapter teardown semantics, and the stall patterns that caused real iOS freezes.
---

# Nipaplay 播放内核热切换

播放内核（MDK/fvp、MediaKit、Erika、VideoPlayer）可在播放中热切换。入口
`PlayerFactory.saveKernelType` 广播事件，`VideoPlayerState` 订阅后经
`PlayerKernelManager.performPlayerKernelHotSwap` 单飞排水执行。整条链在主
isolate 上，**只有旧播放器 teardown 有 5s 超时**——链上任何同步阻塞都会直接
冻住 app。

## 不可破坏的不变量（每条对应过一次真实 iOS 事故）

1. **热切换链上禁止同步原生 teardown**。适配器 `dispose()` 里凡是可能在
   原生层等网络/解码器的调用（MDK 的 FFI dispose），必须延迟执行
   （`Future.delayed(16ms)` 后再调，与 MediaKit/MDK 适配器现模式一致）。
   同步等它 = 主 isolate 冻住 = 「切内核 app 卡死」。
2. **热切换不要串行等待弹幕识别**。`initializePlayer` 传
   `deferDanmakuUntilPlayback: true`——WebDAV/SMB 等无 animeId/episodeId
   的来源会同步走 `_recognizeVideo`（HEAD+16MB MD5+匹配 API，20s+）。
   dandanplay 来源有 ID 跳过识别，所以「弹弹随便切、WebDAV 卡」的分水岭
   就在这里。
3. **热切换失败必须显式化**。`_drainPlayerKernelHotSwaps` 的 catch 里有视频
   在播时要置 error 状态；只打日志会让播放器停在 resetPlayer 后的空状态=
   无限加载（用户观感=卡死，只能杀进程）。
4. **MDK 字幕轨切换必须带守卫**。`activeSubtitleTracks` setter：无字幕轨
   不下发、越界索引裁剪（MediaKit 适配器有 CRITICAL CHECK，MDK 曾是纯透传，
   错误索引可让原生管线停死）。切换后挂停滞看门狗：1.2s/3s 两次采样
   position，`state==playing` 但位置冻结 → 用全新原生 player 重建同一媒体
   恢复位置/倍速/音量/字幕选择。
5. **停滞恢复绝不 dispose 卡住的实例**——其 demuxer 锁可能正阻塞，同步
   dispose 会把 isolate 一并冻住（比视频停死更糟）；弃置交给进程回收。
   恢复路径已知限制：外挂音轨（setMedia audio 附加）会丢失。
6. 各适配器异步释放能力不一致：Erika 实现 `AsyncDisposablePlayer`；
   MediaKit/MDK 用延迟 dispose；**LazyPlayerDelegate 对非 AsyncDisposable
   适配器走同步 `dispose()`**——新写适配器时注意这条隐式路径。

## 诊断入口

- 「切内核 app 卡死（UI 无响应）」：查链上有没有同步 FFI/网络等待——
  嫌疑顺序：MDK teardown → 弹幕识别串行 → 时间轴预览 player 同步 dispose。
- 「视频停死但 UI 正常、seek 无效、只能重播」：原生管线停滞（demuxer/字幕
  轨）。seek 无效说明不是 Dart 侧状态错乱；恢复手段=重建原生 player。
- iOS 冻结时**应用内日志不再写入**（isolate 已阻塞），无法靠日志定位，
  必须靠代码路径审计 + 修复后真机盲测。

## 相关代码

- 切换链：`lib/utils/player_kernel_manager.dart`、
  `lib/utils/video_player_state/video_player_state_initialization.dart`
  （drain）、`video_player_state_player_setup.dart`（initializePlayer）
- 适配器：`lib/player_abstraction/mdk_player_adapter_io.dart`（字幕守卫+
  停滞看门狗）、`media_kit_player_adapter.dart`（防御范式参考）、
  `lazy_player_delegate.dart`（dispose 分流）
- 字幕菜单直设点：`lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart`

相关：[[kernel-switch-ios-freeze-2026-10]]
