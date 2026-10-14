---
name: nipaplay-bangumi-cache
description: Use when changing Bangumi/dandanplay synopsis loading, the request queue, detail caching, or anything that makes anime cards/detail pages refetch metadata. Documents the stale-while-revalidate invariants in lib/services/bangumi_service.dart and the traps that previously caused restart refetch storms.
---

# Nipaplay Bangumi 元数据缓存与加载

简介/剧集元数据的唯一入口是 `BangumiService`（`lib/services/bangumi_service.dart`）。
媒体库卡片、详情页、首页全部经由 `getAnimeDetails`；剧集列表与简介在**同一个
API 响应**里（`BangumiAnime.episodeList`），所以详情页速度 ≈ 简介缓存命中率。

## 不可破坏的不变量（每条都对应过一次线上事故）

1. **读路径绝不删缓存**。内存/磁盘过期数据立即返回（stale-while-revalidate），
   只有超过 `_staleRetention`（30 天）才真正删除。任何"过期即 `prefs.remove`"
   的代码都会在重启后引发整页重取。
2. **回源必须 forceRefresh**。`_scheduleRefreshFromMemory` / 启动清扫调
   `getAnimeDetails(id, forceRefresh: true)`；普通读取会再次命中同一份过期
   缓存直接返回，后台"刷新"永远触达不到网络（SWR 的 revalidate 靠强制路径）。
3. **启动期清扫有预算**。`revalidateExpiredCacheOnStartup`（原
   `checkAndRefreshCacheWithoutTags`）每启动最多强制回源 4 条、200ms 节流、
   不删旧数据。不要恢复"逐条串行重取"或把预算条件绑到 tags（API 永不返回
   tags 的番剧会永久占满预算）。
4. **build 里的请求必须去重 + 失败冷却**。`_ensureDetail`
   （`adaptive_media_collection_view.dart`）失败后 30s 冷却；catchError 里直接
   移除 in-flight 标记会让下一次 build 立刻重试，形成逐帧重试风暴。
5. **in-flight 去重在 `getAnimeDetails` 包装层**，`_fetchAnimeDetailsInternal`
   不碰 `_inflightDetails`。不要在 internal 里塞 Completer——历史上残留的
   未完成 Completer 会永久挂死后续所有读取。
6. **调度器是泵式**（`_pumpQueue`，6 并发槽，12s 首试超时，抖动指数退避）。
   不要改回"取满一批 `Future.wait` 全等再取下一批"的批量屏障——单个慢日历
   请求会把简介并发压到 0。

## 新增读取方的正确姿势

- 展示优先：`getAnimeDetailsFromMemory(id)` 同步拿旧数据先渲染（详情页
  `_fetchAnimeDetails` 的温启动快路径、媒体库 `_ensureDetail` 都是这个模式）。
- 需要保证新鲜度的维护动作：`getAnimeDetails(id, forceRefresh: true)`，
  必须自己吞错并保留旧数据。
- 打开详情页的入口统一走 `ThemedAnimeDetail.show`（内部已在路由转场期间
  预取缓存），不要绕过它直接 push `AnimeDetailPage`。

## 新鲜度语义（有意为之的取舍）

- 新番 TTL 24h、旧番 7 天；TTL 只决定回源频率，不决定用户能否看到内容。
- 媒体库卡片**不会**为过期数据主动回源（旧行为=用户抱怨的慢）。新鲜度由
  两处保证：打开详情页时的强制后台回源 + 启动清扫（4 条/启动）。
- tags 缺失是 API 合法状态：读路径直接返回、不做任何重取；详情页标签位
  随之隐藏。

## 调试入口

- 现象"重启后几部番剧重新获取"：先查 `_preloadDetailsCacheFromDisk` 是否
  又在按 TTL 删条目，再查 `revalidateExpiredCacheOnStartup` 是否被改回删缓存。
- 现象"简介永远转圈/请求挂死"：查 `_inflightDetails` 是否有永不完成的
  future 被塞入（Completer 残留类 bug）。
- 现象"网络断开时列表卡死/请求风暴"：查 build 路径上的 `_ensureDetail` 类
  逻辑有没有失败冷却。

相关：[[bangumi-swr-optimization-2026-10]]（本次优化的根因记录）
