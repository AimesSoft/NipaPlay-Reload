---
name: nipaplay-image-mirror
description: Use when cover/poster images fail to load in restricted networks (TLS reset, blank covers), when touching lib/services/media_server_image_loader.dart, or when configuring Bangumi/TMDB image proxies. Documents the single image choke point, the mirror-first pattern, and the measured reachability facts that decide which proxy can actually work.
---

# NipaPlay 封面镜像与受限网络

## 咽喉点唯一

所有封面字节下载都过 `lib/services/media_server_image_loader.dart` 的
`loadNetworkImageBytes`（并发上限 6、单请求 20s 超时，`.dart` 内注释解释了
"封面墙加载一半停住"的成因）。三个消费方：`CachedNetworkImageWidget`、
`ImageCacheManager`、`MediaServerNetworkImage`。**改镜像逻辑只改这里**，
消费方自动受益。媒体服务器（Emby/Jellyfin）图片走 `loadMediaServerImage`
（transport 鉴权），不走镜像改写。

## 镜像优先模式（Bangumi 与 TMDB 同构）

`_loadNetworkImageBytesUncapped` 里两段同构逻辑：
`_isBangumiOfficialImageUri` / `_isTmdbOfficialImageUri` 识别官方域 →
`_bangumiMirrorUri` / `_tmdbMirrorUri` 换 host（保 path+query）→ 镜像失败
回落原地址（带 `[ImageLoader] …镜像取图失败，回退原地址` 日志）。仅非 Web。

- 镜像地址来自用户设置：`NetworkSettings.getBangumiServer()` /
  `getTmdbImageServer()`（key `tmdb_image_server_url`，空串=直连）。
- 设置 UI：设置 → 网络 →「自定义 Bangumi API 服务器」/「自定义 TMDB 图片代理」。

**缓存失效的差别（易错）**：Bangumi 的持久化封面 URL
（`media_library_image_url_<animeId>`）带"当时生效的域"，换服务器必须清
缓存（`_invalidateBangumiCoverCaches`，840e2911）；TMDB 的 URL 是源数据固有
域（image.tmdb.org），改写发生在每次取图，**不需要失效缓存**。

## 受限网络实测事实（2026-10，决定方案选型）

| 目标 | 结果 | 含义 |
|---|---|---|
| `image.tmdb.org` 直连 | **TLS 握手即重置**（curl exit 35 @0.35s；iOS errno 54） | 域级 SNI 阻断，缩略图/原图同域，无"缩略图专用域名" |
| `images.weserv.nl` / `wsrv.nl` / `i0.wp.com` | 同样 TLS 重置 | 公共图片代理不可做内置回退 |
| `www.themoviedb.org` / `media.themoviedb.org` | 可连但对 `/t/p/` 只 301 回 image.tmdb.org | 主站域名救不了图 |
| Cloudflare **pages.dev**（用户自建 worker） | HTTP 200 可达 | 唯一可行通道 = 自建反代 |
| `workers.dev` 域 | 国内常被污染 | 部署选 Pages（Functions）而非 Worker |

诊断套路：先 `curl -sv -m 15 <url>` 分清"TLS 重置（秒拒，阻断）"与"超时
（慢，可重试）"；iOS 日志 `Connection reset by peer, errno = 54` 对应前者。

## CF 侧反代要求

镜像必须**按原路径**反代图床（app 只换 host）。Pages Functions 单文件
`functions/[[path]].js`：取 `url.pathname + url.search` 拼 `https://image.tmdb.org`
（或 lain.bgm.tv 等），`cf: { cacheTtl: 86400, cacheEverything: true }`，回
`Access-Control-Allow-Origin: *`。bgm 专用 worker（只代理 bgm.tv）对
TMDB 路径无效——填了也 404 后回落直连。

## 排查清单（封面裂图）

1. 日志里 `加载基础图片失败` 的 URL 域是谁（bangmi.tv 系 / tmdb.org / 服务器域）。
2. 有无 `[ImageLoader] 镜像取图失败` 日志：有 = 镜像配了但镜像侧不通（worker
   路由没加/填错）；无 = 该域没进镜像逻辑或设置没填。
3. MDK 侧诊断字段陷阱：`getDetailedMediaInfo` 音频字段恒 null（字段名
   bit_rate/sample_rate/name 应为 bitRate/sampleRate/codec，已知缺陷）。
4. 弹幕聚合域名同理可查：`43.142.85.190`（官方国内网关）直连正常不代表
   图床通——网关是 IP 直连，图床是域名。

相关：[[tmdb-image-proxy-fix-2026-10]]、[[bangumi-mirror-cover-fix-2026-10]]
