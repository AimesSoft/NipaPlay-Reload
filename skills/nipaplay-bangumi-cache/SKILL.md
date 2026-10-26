---
name: nipaplay-bangumi-cache
description: Use when changing Bangumi/dandanplay synopsis loading, detail caching, the quarterly review cache, or anything that makes anime cards/detail pages refetch metadata. Documents the on-demand cache contract introduced by upstream PR #1004 (adopted in merge 4078366d) and the traps that previously caused restart refetch storms.
---

# Nipaplay Bangumi 元数据缓存与加载

简介/剧集元数据的唯一入口是 `BangumiService`（`lib/services/bangumi_service.dart`）。
媒体库卡片、详情页、首页全部经由 `getAnimeDetails`；剧集列表与简介在**同一个
API 响应**里（`BangumiAnime.episodeList`），所以详情页速度 ≈ 简介缓存命中率。

> **版本裁定（2026-10 合并 4078366d）**：本文件原描述 42a57e77 的自研 SWR
> 实现；上游 PR #1004（综合性能优化）是同一目标的更完整演进且自带契约测试
> `test/bangumi_lazy_cache_test.dart`，合并时**整体采用上游实现**。本文件已
> 改写为 #1004 契约。历史方案见 git 历史（42a57e77）。

## #1004 契约（`test/bangumi_lazy_cache_test.dart` 是行为规格）

1. **initialize() 不解码任何详情**。详情按需经 `_loadDetailFromCache` 解码；
   不要在 initialize 里恢复"启动预载全部详情到内存"（会直接打挂
   "startup decodes no details" 测试，也拖慢冷启动）。
2. **读路径绝不删缓存，允许过期**。`getAnimeDetails` 读磁盘固定
   `allowExpired: true`（`_loadDetailFromCache(animeId, allowExpired: true)`）：
   过期数据立即返回、后台回源。任何"过期即 `prefs.remove`"的代码都会在重启
   后引发整页重取。
3. **in-flight 去重与编辑保护**。请求以 `(animeId, forceRefresh)` 为键进
   `_detailRequests` 共享；请求飞行中 `saveCustomAnimeDetail` 写入
   `_pendingDetailEdits`，API 返回后 `!identical(_pendingDetailEdits[id],
   editToken)` 则放弃覆盖——**用户编辑不被并发回源冲掉**。不要把去重改回
   "forceRefresh 不共享"（旧实现），上游语义是共享的。
4. **热缓存有界（`_maxHotDetails = 100`，`_rememberDetail` LRU 淘汰）**。
   自定义条目的持久化在磁盘（`bangumi_detail_<id>`），被内存淘汰后仍可从
   磁盘恢复——不要"修复"这个淘汰逻辑。
5. **启动期清扫有预算**。`checkAndRefreshCacheWithoutTags` 每启动最多 5 条
   补 tags，且**绝不启动期扫描删除全部 SharedPreferences 详情**（注释原文
   即此约束）。旧名 `revalidateExpiredCacheOnStartup` 已删除，调用方（main）
   不再显式调用。
6. **quarterly_review_cache**（`lib/services/quarterly_review_cache.dart`）：
   API 拉到详情即 `QuarterlyReviewCache.instance.recordAnime` 异步记录，
   失败静默（`catchError((Object _) {})`）。import 指向
   `package:nipaplay/services/quarterly_review_cache.dart`。

## 包路径铁律（合并后修复过一轮）

`bangumi_model` 在 `package:nipaplay_core/models/`、`network_settings` 在
`package:nipaplay_core/utils/`、`web_remote_access_service` 在
`package:nipaplay_core/services/`。上游新代码引用 `package:nipaplay/...`
旧路径时必须重指向，否则整包编译失败（本次合并 quarterly_review_cache 与
多个测试文件均踩过）。

## 新增读取方的正确姿势

- 展示优先：`getAnimeDetailsFromMemory(id)` 同步拿（可能 null）先渲染。
- 保证新鲜度的维护动作：`getAnimeDetails(id, forceRefresh: true)`，自己吞错。
- 打开详情页统一走 `ThemedAnimeDetail.show`（路由转场期预取）。

## 调试入口

- "重启后几部番剧重新获取"：先查是否有人把 `allowExpired` 改回 false / 恢复
  了启动期删除；再看 `checkAndRefreshCacheWithoutTags` 是否被改回无预算重取。
- "简介永远转圈"：查 `_detailRequests` 是否有永不完成的 future 残留（
  `identical` 清理逻辑被删）。
- "用户自定义简介被网络数据冲掉"：查 `_pendingDetailEdits` 的 editToken
  比对是否还在。

相关：[[bangumi-swr-optimization-2026-10]]（旧方案根因记录，实现已被 #1004 取代）
