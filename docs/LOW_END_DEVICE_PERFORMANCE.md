# 低端设备性能优化（32 位安卓电视 / 联发科方案）

面向低性能平台的非播放路径优化记录。目标设备画像：Mali-450 级别 GPU、1–2GB 内存、
32 位地址空间、慢速 eMMC、Cortex-A53 级 CPU，输出 1080p。

每一项都标注了**为什么在目标硬件上贵**、**改了什么**、以及**风险与验证方式**。

---

## 1. 海报按原始分辨率解码

**问题.** `CachedNetworkImageWidget` 的 `hybrid` 模式在 `_loadBasicImage` /
`_loadOriginalImage` 里调用 `ui.instantiateImageCodec(bytes)` 时**不带 target 尺寸**，
因此一张 1000px+ 的番剧封面会解码成约 4–8MB 的 RGBA 位图，却只显示在
190×286 的格子里。解码本身是 A53 上几十毫秒的主 isolate CPU 开销，
位图还全部落在 32 位地址空间里。`AnimeCard` 的网络分支更是完全没有传
`memCacheWidth`。

**改动.**
- `CachedNetworkImageWidget` 新增 `_resolveDecodeTarget()`：优先用调用方显式的
  `memCacheWidth/Height`（约定为物理像素）；两者都缺时按
  「布局尺寸 × 设备像素比」推导，并受 `_maxAutoDecodeEdge`（1080）上限约束。
  该目标尺寸统一作用于 legacy 路径、hybrid 基础图、hybrid 高清图、
  `_loadOriginalImage` 以及低清重试路径。
- 上限取 1080 而非更小的原因：首页 hero 横幅是整屏宽（1080p 电视即 1080 物理像素），
  再低会明显损失画质，而 1080 已足以挡住 2000px+ 的原始海报。
- `AnimeCard` 新增 `imageDecodeWidth/imageDecodeHeight` 透传参数；
  电视网格显式传 `400×560`，hero 横幅传 `1280×720`，
  标签搜索的 80×45 缩略图传 `160×90`。
- `AnimeCard` 的网络分支不再强制 `legacy`，默认走 `hybrid`
  （`useLegacyImageLoadMode` 仍可显式回退）。

**风险.** 降采样会轻微损失锐度。所有显式值都按约 2 倍槽位尺寸给出；
若某处发现模糊，调大该调用点的 `memCacheWidth` 即可，不影响其它页面。

---

## 2. `ImageCacheManager` 内存只进不出

**问题.** 这是本次最严重的一项。

- `_cache` 没有任何数量或字节上限（全文件搜不到 `maxSize` / LRU）。
- 引用计数方向是反的：`loadImage` 命中缓存时 `_refCount[key]++`，
  而唯一的递减点 `releaseImage` 全仓库只有 1 处调用
  （`new_series_page.dart`）。
- 于是 2 分钟一次的 `_cleanupExpiredImages` 的淘汰条件
  `(_refCount[url] ?? 0) <= 0` **永远不成立**，缓存单调增长。
- `clearCache()`（用户点「清空图片缓存」）也跳过所有 refCount > 0 的条目，
  等于点了没反应。

解码后的 `ui.Image` 像素属于 native/external 内存，Dart GC 不管理，
在 32 位设备上会直接耗尽地址空间导致 OOM。

**改动.**
- 新增 `_bytes` / `_totalBytes` 做字节记账，`_estimateImageBytes` 按
  `stride × height`（4 字节像素、4 字节对齐）估算。
- 新增 `maxBytes` 预算：Android 与 Web 为 32MB，其它平台 64MB。
  可用 `ImageCacheManager.maxBytes` 在测试中覆盖。
- 新增 `_enforceByteBudget()`：超出预算时按**最后访问时间 LRU** 淘汰，
  淘汰到预算的 80% 以避免抖动。**刻意无视 refCount**（原因见上），
  但对 2 秒内访问过的条目设保护窗，避免淘汰正在绘制的位图。
- `releaseImage` 现在会匹配同一 URL 的所有尺寸变体
  （键形如 `url_w<w>_h<h>`），修掉「传裸 URL 命中不到条目」的问题。
- `clearCache()` 现在真正清空，并重置字节统计。
- 新增 `handleMemoryPressure()`，由 `ImageCacheMemoryPressureHandler`
  在 `didHaveMemoryPressure` 与 App 进入后台时调用。
- 新增 `currentCacheBytes` / `currentCacheCount` 便于观测。

**已知取舍.** 若「受保护 + 正在加载」的位图总和本身就超过预算，
缓存会暂时高于预算而非强行 dispose 在用句柄（宁可占内存也不渲染崩溃）。

---

## 3. 无用的纯 Dart 解码

**问题.** `_processImageInIsolate` 用 `package:image` 完整解码一遍，
然后**原样返回原始字节**，产出为零。每次网络图缓存未命中都要付一次
「isolate 启动 + 转移数 MB 字节缓冲 + A53 上几百毫秒纯 Dart 解码
+ 一次整图 RGBA 临时分配」。

**改动.** 删除该函数与 `compute` 跳转，直接把下载到的字节写盘并交给
`ui.instantiateImageCodec`（它本身是流式的、支持降采样）。同时移除
不再需要的 `package:image` 导入。

---

## 4. 电视界面铺满全屏的 `BackdropFilter`

**问题.** `BackdropFilter` 必须每帧重新捕获并模糊其下方已渲染内容，
无法缓存。以下位置在电视上**无条件每帧执行**：

| 位置 | σ |
|---|---|
| `large_screen_view_container.dart` | 26（每个 TV 二级页面） |
| `large_screen_scaffold_layout.dart` | 25（侧栏打开时全屏） |
| `large_screen_top_status_overlay.dart` / `bottom_hint_overlay.dart` | 25（两条常驻横条） |
| `large_screen_page_scaffold.dart` | 22（设置卡片等复用） |
| `large_screen_player_menu_panel.dart` | 28 |
| `large_screen_anime_detail_page.dart` | 40 + `Opacity` |
| `media_server_detail_page.dart` | 34，且 `blurImage == false` 时仍挂一个 σ0 图层 |

外加 `large_screen_view_container.dart` 的 `blurRadius: 54, spreadRadius: 4`
面板阴影（又是一次全尺寸遮罩模糊）。

**改动.**
- 新增 `TvSafeBackdropFilter`：在电视设备（`globals.isTelevision`）上
  直接返回 `child`，只在非电视设备上挂 `BackdropFilter`。这些面板自身
  都有半透明底色，关掉模糊后配色与布局不变，只是失去毛玻璃质感。
- 上述 6 处 σ22–40 全部替换；面板阴影在电视上从 `54/4/@0,22` 收敛到 `12/0/@0,8`。
- `media_server_detail_page.dart`：`blurImage == false` 时不再挂 σ0 图层。
- 番剧详情页的 σ40 封面氛围层：电视上直接省略，非电视上把解码宽度压到 240px
  （反正会被 σ40 抹平）。

---

## 5. Emby / Jellyfin 整库响应在主 isolate 解析

**问题.** 媒体库接口用 `Recursive=true&Limit=99999`（部分路径甚至 `999999`），
响应体可达几十 MB，`json.decode` + 逐条 `fromJson` 同步跑在唯一的 UI isolate 上，
造成数秒整段卡死与很大的瞬时堆峰值。

**改动.** 两个 service 各新增
`_decodeXxxItemsMaybeIsolated(body)`：小于 64KB 的响应仍在主 isolate 解析
（避免为小请求白付 isolate 启动开销），超过则走 `compute`。
共替换 7 处大列表解析点。

**未做.** 没有改 `Limit` 的具体数值——那会改变返回结果集的语义。
`compute` 返回列表需要跨 isolate 复制，但这个开销远小于在主线程解析几十 MB JSON。

---

## 6. 首页 rebuild 风暴

**改动.**
- `_upgradeToHighQualityImages`：原来每个推荐位各自 `setState`，首页 7 个位置
  就是 7 次整棵 eager 树重建。改为 `Future.wait` 收集结果后**一次性 setState**
  （新增 `_UpgradedRecommendation` 承载结果，`_upgradeItemToHighQuality`
  改为返回值而不是自己 setState）。
- `_fetchLocalAnimeImagesInBackground` 的进度刷新从「每 5 个」改为
  **按时间节流**（200ms 上限），慢设备上不再退化成高频重建。
- 新增 `_animeDetailsFuture(animeId)` 备忘。原来 `FutureBuilder` 的 future
  在 build 里现场创建，每次重建都重新发请求并丢掉已解析的快照
  （表现为简介反复闪回空态）。失败时从缓存移除以便重试。

**未做.** 首页仍是 `SingleChildScrollView + Column`（eager）。改成
`CustomScrollView` + 每区块一个 sliver 是结构性改动，会牵动
`_mainScrollController`、下拉刷新与各区块的 padding 逻辑，
风险明显高于前面几项。建议在实测确认区块构建仍是瓶颈后再单独做。

---

## 7. 启动关键路径

**改动.**
- `DandanplayService.initialize()` 中的 `loadToken()` → Token 续期网络请求
  加 5 秒超时护栏。超时则沿用本地已缓存 token 继续启动。
- `main.dart` 里 `while (!isLoaded) await Future.delayed(16ms)` 的忙等改为
  `await provider.loaded.timeout(3s)`。原写法在加载失败时 `isLoaded`
  永远是 false，会变成**永不退出的 60Hz 轮询**直接卡死启动。
  `DownloaderSettingsProvider` 相应新增 `loaded`（内部 `Completer`），
  并在 `finally` 中收敛，保证成功或失败都会唤醒等待方。
- `iOSContainerPathFixer.validateAndFixFilePath` /
  `validateAndFixDirectoryPath` 的 `existsSync()` 改为异步 `exists()`。
  这两个方法在启动时对**每一条**观看历史各调用一次，同步 stat 在慢速
  eMMC 上每次数百微秒，上千条就是数秒的主线程阻塞。
- `WatchHistoryProvider._validateFilePaths` 每处理 50 条
  `await Future.delayed(Duration.zero)` 让出一次事件循环，保持界面可响应。
- `manageExternalStorage` 权限：原来只在 `isDenied` 时请求，
  而 Android 在用户拒绝后返回 `permanentlyDenied`，导致
  「拒绝过一次就再也不弹窗」；同时永远拒绝的用户每次都白跑一次状态查询。
  现在只在 `!isGranted && !isPermanentlyDenied` 时请求。

**未做.** 没有把权限链、`ServiceProvider.initialize()` 等整体挪到首帧之后。
那会改变启动架构（首帧时这些状态必须已就绪），风险不可控。

---

## 8. 其它

- 电视上隐藏「超级 / 梦幻」模糊档位（σ50 / σ100，glassmorphism 还会把纵向
  σ 再乘 2，即全屏 σ200），并在 `SettingsProvider` 里做**加载时 clamp**，
  防止用户在别的设备上存过的更大值被带过来。
- 电视上跳过图片淡入动画（`fadeDuration` 默认 300ms → 0），避免每张图
  一次 `OpacityLayer` 合成。调用方显式指定时长时仍尊重。
- 电视网格卡片关闭 `BoxShadow`（一屏十几张、滚动时逐帧重绘的遮罩模糊）。
- `MediaServerNetworkImage` 新增 `cacheWidth/cacheHeight` 并透传到
  `Image.memory`，同时给原本只有 200 条上限的字节缓存加上 12MB 字节预算
  与 LRU（命中时重新插入以维持插入序）。

---

## 验证状态

- `flutter analyze lib`：改动文件无新增 error / warning。
  仓库中剩余的 33 个 error 全部来自 `lib/settings/pages/dashboard_home_page.dart`
  —— 该文件在 HEAD 中就已损坏（`part` 路径指向不存在的
  `package:nipaplay/settings/themes/...`）且**没有任何 importer**，
  属于既有的死代码，本次未触碰。
- `flutter test`：全量通过（702+ 用例）。

## 尚未验证的部分

以下数值来自代码审计与静态推理，**没有在真机测量**，上机前请按
`docs/` 之外的 profiling 建议实测：

- 各 `BackdropFilter` 具体省下多少毫秒（建议逐个 ablation：临时换成
  `ColoredBox`，对比 DevTools Raster 时间线）。
- 32MB 的图片缓存预算是否适合目标机型（`adb shell dumpsys meminfo` 看
  native/graphics heap 峰值）。
- `_maxAutoDecodeEdge = 1080` 对 hero 横幅的画质是否可接受。
- 字节预算淘汰逻辑**没有单元测试**：`ImageCacheManager` 的 `loadImage`
  依赖真实网络与编解码，难以在 widget test 里隔离。`maxBytes` 与
  `currentCacheBytes` 已暴露，便于后续补一个注入式测试。

## 建议的实测清单

在目标联发科盒子上 `flutter run --profile`（**不要用 `--debug`**），
并临时关闭文件日志：

1. DevTools 性能页看 UI / Raster 拆分，分别滚媒体库网格、开设置侧栏。
2. 内存 → Diff Snapshots：浏览 30 张海报前后对比 external/native 内存，
   确认不再单调增长。
3. `flutter run --profile --trace-startup` 归因首帧前的各段耗时。
4. `adb shell dumpsys gfxinfo <pkg> framestats` 观察掉帧分布。
