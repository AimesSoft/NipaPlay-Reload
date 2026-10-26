---
name: nipaplay-player-kernel
description: Use when touching player kernel hot-swap, kernel adapters (MDK/MediaKit/Erika), embedded/external subtitle track switching, or diagnosing playback freezes on iOS/WebDAV sources. Documents the hot-swap chain, the upstream disposeAsync/seekAndWait teardown architecture (1.11.11), and the stall patterns that caused real iOS freezes.
---

# Nipaplay 播放内核热切换

播放内核（MDK/fvp、MediaKit、Erika、VideoPlayer）可在播放中热切换。入口
`PlayerFactory.saveKernelType` 广播事件，`VideoPlayerState` 订阅后经
`PlayerKernelManager.performPlayerKernelHotSwap` 单飞排水执行。整条链在主
isolate 上，**只有旧播放器 teardown 有 5s 超时**——链上任何同步阻塞都会直接
冻住 app。

> **版本裁定（2026-10 合并 4078366d，上游 1.11.11）**：MDK 适配器的
> teardown 被上游重写为 **disposeAsync 幂等架构**（`_disposeAsyncFuture`
> 单飞 + `_released()` 守卫 + `PlayerKernelManager.traceHotSwapStage` 分段
> 埋点 + `seekAndWait` 带代数重试）。本文不变量已按新架构改写；本地的字幕
> 停滞看门狗整体保留并叠挂在 `_disposeAsyncInternal` 里。

## 不可破坏的不变量（每条对应过一次真实 iOS 事故）

1. **teardown 必须走 `disposeAsync()`，且幂等**。热切换主路径与 finally
   兜底会先后调用 dispose，`_disposeAsyncFuture ??= _disposeAsyncInternal()`
   保证合并为同一次原生释放（杜绝 double `mdkPlayerAPI_delete`）。新适配器
   禁止同步 FFI dispose 出现在 dispose() 直呼路径上（MDK 旧 16ms 延迟方案
   已被 disposeAsync 取代，不要恢复）。
2. **teardown 后一切访问走 `_released()` 守卫**。MDK 适配器所有成员
   （volume/state/mediaInfo/position/setMedia/prepare/seek/snapshot…）开头
   都有 `if (_released('xxx')) return;`；新加成员必须跟上，否则 double-
   teardown 会在已释放句柄上崩溃。
3. **热切换不要串行等待弹幕识别**。`initializePlayer` 传
   `deferDanmakuUntilPlayback: true`（合并后签名多了
   `episodeFileSelectionHandled`，两参并存）——WebDAV/SMB 等无 ID 来源会
   同步走 `_recognizeVideo`（HEAD+16MB MD5+匹配 API，20s+）。「弹弹随便切、
   WebDAV 卡」的分水岭在这里。
4. **热切换失败必须显式化**。`_drainPlayerKernelHotSwaps` 的 catch 里有视频
   在播时要置 error 状态；只打日志会让播放器停在空状态=无限加载。
5. **MDK 字幕轨切换必须带守卫 + 停滞看门狗**。`activeSubtitleTracks`
   setter：`_released` 守卫 → 无字幕轨不下发 → 越界索引裁剪 → 设置成功且
   实际变化才 `_armSubtitleStallWatchdog()`（1.2s/1.8s 两次采样 position，
   playing 但冻结 → `_recoverFromSubtitleStall` 用全新原生 player 重建，
   重放位置/倍速/音量/**sticky 属性（`_reapplyStickyProperties`，含代理与
   UA）/字幕选择**）。这套本地逻辑叠在上游架构上，合并时容易丢——
   `_reapplyStickyProperties` 曾被上游重写吞掉需手工补回。
6. **停滞恢复绝不 dispose 卡住的实例**——其 demuxer 锁可能正阻塞；弃置交给
   进程回收。恢复路径已知限制：外挂音轨（setMedia audio 附加）丢失。
7. **seek 失败要等内核自己 settle**。上游 `seekAndWait`：seek 返回 <0 时按
   `_seekGeneration` 代数最多重试 3 次，`_untilSeekSettled` 等 seeking 位清
   除（2s 超时）；`_mediaStatusSubscription` 监听状态变化调 `_settleSeek()`。
   不要改回"一次 seek 裸调"——MDK reopen 期间 seek 会静默丢失（上游
   fix/mdk-reopen-hang）。
8. **默认内核选择**：tvOS/iOS 强制 Erika；上游 1.11.11 起 Linux 在
   `ErikaPlayerAdapter.linuxBuildEnabled` 门控下默认 Erika；其余 MDK。
   合并两侧语义时保留 iOS 分支的注释与 Linux 门控（`player_factory.dart`
   `_defaultKernelType`）。

## 诊断入口

- 「切内核 app 卡死（UI 无响应）」：查链上同步 FFI/网络等待——嫌疑顺序：
  MDK teardown → 弹幕识别串行 → 时间轴预览 player 同步 dispose。
- 「视频停死但 UI 正常、seek 无效、只能重播」：原生管线停滞。恢复手段=
  看门狗重建（已在代码里）；若复现，先看 `traceHotSwapStage` 埋点停在哪段。
- iOS 冻结时**应用内日志不再写入**（isolate 已阻塞），必须靠代码路径审计 +
  修复后真机盲测。

## 相关代码

- 切换链：`lib/utils/player_kernel_manager.dart`、
  `lib/utils/video_player_state/video_player_state_initialization.dart`
  （drain）、`video_player_state_player_setup.dart`（initializePlayer）
- 适配器：`lib/player_abstraction/mdk_player_adapter_io.dart`（disposeAsync
  架构 + 字幕守卫/看门狗 + `_reapplyStickyProperties`）、
  `media_kit_player_adapter.dart`（防御范式参考）、
  `lazy_player_delegate.dart`（dispose 分流）
- 字幕菜单直设点：`lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart`
  （上游已收敛为 `videoState.selectEmbeddedSubtitleTrack`，内部记录
  `_lastSelectedEmbeddedTrackIndex`）

相关：[[kernel-switch-ios-freeze-2026-10]]
