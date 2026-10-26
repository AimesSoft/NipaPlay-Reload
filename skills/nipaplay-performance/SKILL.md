---
name: nipaplay-performance
description: Use when optimizing startup time, poster-wall scrolling, image memory, or UI jank in NipaPlay, and before shipping performance-sensitive changes. Documents the established optimization patterns (image cache budget, constraint decode, startup deferral, panel-local rebuild) and the evaluation rig.
---

# NipaPlay 性能优化惯例

## 已落地的模式（改代码时保持，别回退）

1. **图片内存预算**（`lib/main.dart`）：Flutter 默认 100MiB/1000 条会让海报
   墙独吃内存；受约束面（Web/AndroidTV/TV 盒）32MiB/200 条，桌面/ohos
   64MiB/400 条（docs/LOW_END_DEVICE_PERFORMANCE.md）。淘汰图从磁盘缓存
   重取，代价可接受。
2. **约束解码**（`CachedNetworkImageWidget`）：无显式尺寸时等首次布局再按
   显示框约束解码（同帧内发生），避免"原图解码一次→约束版替换"的双重开销；
   海报 1500×2250 全尺寸解码 ~13.5MB vs 400×600 ~1MB。仅解码尺寸变化时保留
   旧图只重解码（防闪占位）。
3. **启动延后**（`main.dart`）：非首帧服务全部进 `addPostFrameCallback` +
   `_runDeferredStartupTask`（上游 1.11.11 的带预算任务队列，打印
   `[Startup] <name> <ms> (after first frame)`）；弹幕识别走
   `deferDanmakuUntilPlayback`；ServiceProvider `deferBackground: true` +
   `initializeAfterFirstFrame`。**别把网络初始化塞回首帧等待列表**——上游
   1.11.11 曾把 BangumiService.initialize() 放回阻塞列表，合并时已按需解码
   契约改回不阻塞（见 [[nipaplay-bangumi-cache]]）。
4. **面板局部重建**：弹幕区用 `Selector`/`danmakuUiSnapshot`
   （`lib/playback/player_ui_snapshot.dart`）+ RepaintBoundary 隔离；大屏
   菜单焦点索引用 `ValueNotifier<int>`（面板自听自建），**禁止 scaffold 级
   setState**（整棵 Stack 连带重建）。
5. **图片生命周期**：`ImageCacheManager.lifecycleGeneration` 监听统一释放；
   常驻 Opacity（opacity>=1.0）在 raster 线程强制整块 saveLayer，全不透明时
   直接返回 content（dfm_plus_overlay 模式）。
6. **插件索引延后**（plugin_service）：首帧后才加载插件索引 +
   `PerformanceTrace.measure('plugins.index', …)` 埋点。

## 评估工具（交付前跑）

- `DevPerfStatsLogger`（开发期遥测，`video_player_state.dart` start/stop）
  + `EvalScenarios`（合成弹幕/自动挂字幕等评估场景自动化）——对应已删除的
  `tools/perf` 流程（历史报告在 docs/refactor/）。启用入口与快照结构见
  `video_player_state.dart` 中的调用点。
- 交付前基准：docs/UI_PERFORMANCE_AUDIT_2026-10.md（焦点节拍器/面板局部
  重建/TV 模糊通道三招的原始审计）。

## 陷阱

- mdk 适配器 `getDetailedMediaInfo` 音频字段恒 null（字段名拼写错，已知
  缺陷）——做性能面板时别拿它当数据源。
- `MediaKit` 音量是三次方缩放（volume=45 → 实际 9%），与 MDK 线性语义
  不同；Windows WASAPI AO 首帧就绪后有音量重同步逻辑（`_volumeResyncNeeded`）。
- iOS 上 isolate 冻结时日志停写——性能问题必须用真机 Instruments/埋点，
  不能靠应用内日志。

相关：[[ui-perf-optimization-2026-10]]、[[loading-performance-optimization-2026-10]]
