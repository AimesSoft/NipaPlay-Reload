---
name: nipaplay-media-research
description: Use when diagnosing danmaku problems (missing/few danmaku, wrong match), answering audio format compatibility questions (DDP/E-AC-3, passthrough, external MKA), or planning player codec work. Documents the danmaku source architecture, the match cache, and the per-kernel audio capability matrix measured on 1.11.x.
---

# NipaPlay 弹幕与音频能力调研结论

## 弹幕：来源与匹配（决定"为什么没弹幕"）

- **弹幕不来自视频源**（Netflix/B站原盘都无关），全部来自弹弹play 聚合库：
  `POST /api/v2/match`（`matchMode: hashAndFileName`，`dandanplay_service_io.dart`）
  → episodeId → `GET /api/v2/comment/{episodeId}?withRelated=true`（聚合
  B站/巴哈/ACFun/爱奇艺等 + 用户上传）。
- **客户端零截断**：全量解析+去重（`_parseDanmakuBody`）。只显示几条 =
  聚合池就只有几条。网飞独占番（国内无正版平台）聚合池近乎空是正常现象。
- **匹配结果缓存在观看历史**（`watch_history_model.dart` 的
  episodeId/animeId），错配不会自愈——纠正入口：播放页 → 弹幕设置 →
  「手动匹配弹幕」（`ManualDanmakuMatcher`）。
- 弹幕极少的典型形态：仅有的几条是"进度条吐槽"，均匀分布在 25/50/75/100%
  ——这不是 bug，是池子小。
- 弹幕来源 UI 占位：Cupertino 弹幕轨道面板的 Bilibili/AcFun 磁贴未启用，
  实际只有 DandanPlay 聚合。扩弹幕三途径：本地 XML/JSON 文件加载（弹幕
  轨道菜单）、第三方弹弹play 兼容服务器（API 设置）、换匹配。

## 音频：能力矩阵（"DDP 能不能放"的标准答案）

- 四内核：MDK(FVP，桌面/Android 默认)、Erika(自研 Rust，iOS/tvOS 强制)、
  Media Kit(libmpv，可选)、VideoPlayer(Web 唯一，能力最弱)。
- **全内核无比特流直通**（passthrough/spdif/iec61937 在 MDK SDK 头文件、
  media_kit、仓库源码零命中），输出一律解码后 PCM。DDP(E-AC-3) 的预期
  路径 = FFmpeg 软解成 PCM（MDK/MediaKit 高置信；Erika 原生包解码器清单
  不可查，待真机验证）。
- **MKV + 同名 MKA 外挂音轨**：仅 MDK 与 Media Kit 支持
  （`AudioTrackManager`，同目录同名 `.mka` 自动发现；MediaKit 走 mpv
  `audio-add` 1.5s 延迟+代数校验；MDK 走 `setMedia(audio)` +
  `_internalAudioTrackCount` 区分内外挂）。**Erika 与 VideoPlayer 不支持**
  （iOS/tvOS 强制 Erika → 无外挂音轨）。无手动选择外挂音频文件的 UI。
- 已知限制：MDK 字幕轨切换触发重建会丢外挂音轨（适配器注释明写）；
  本地切音轨不重挂字幕；Jellyfin/Emby 流切音轨=整流重载。
- 容器≠编码：Rust 媒体库扫描只认 mp4/mkv（`rust/src/api/file_scan.rs`），
  AVI/TS 能直接播但扫不进媒体库。
- 排查工具：Erika 诊断有 `audioFailures/audioLastErrorCode/audioRecoveryState`
  （播放信息面板）；MDK 的 `decoder.audio` error 事件**未被消费**（只当
  解码器名读取）——DDP 无声时应用内无自证，需外部取证。

## 调研方法（可复用）

- 查上游 Issue：`curl -sk "https://api.github.com/search/issues?q=repo:AimesSoft/NipaPlay-Reload+<kw>&per_page=15"`
  （本机 WebFetch 证书链失败、gh 未装，curl -sk 是唯一通道）。
- 网络可达性一手证据：`curl -sv -m 15` 区分 TLS 秒拒（阻断）与超时（慢）。
- 内核能力以代码为准：`player_factory.dart` 工厂、各 adapter、
  `mdk-sdk/include/mdk/Player.h` 属性表。

相关：[[danmaku-matching-2026-10]]、[[audio-compatibility-audit-2026-10]]
