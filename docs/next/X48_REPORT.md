# X48：按来源的片库后端

2026-10-13，worktree `x48-library`，分支 `next/x48-library`。未提交、未 push、未改依赖。

## 完成了什么

- `LibraryDataService` 实现原有 `NextLibraryData`、`NextLibraryActions`，入口为
  `await core.ready` 后的 `core.libraryData`、`core.libraryActions`。接口约定
  原接口名称保留；审查补充只新增 `UiLibraryPage.hiddenCategories`，并同步
  c1b179e9 的注释。`lib/next/ui/` 未改。Y7_REPORT 在本 worktree 中不存在。
- 本地原样只有 X47 合并库“全部”；Jellyfin/Emby 使用 Classic 已选服务器库，
  保留库、文件夹、季、集和服务器排序；SMB/WebDAV 按共享文件夹浏览。
- `ui.library.sources/page/items/put/configure/move/remove/restore` 提供读取及批量整理。
  类别可完整替换、排序、移除，来源可设置 shelves/cards、切回原样。
  支持条件、手选作品列表、来源原样引用三种内容，以及最多三部封面作品。
  用户四个直接操作与 Nipa 共用修改实现，布局与 activity 同事务写入，GUI
  来源记录为 `gui`、actor 为 `user`。
- 条件支持来源、设备、作品类型、观看状态、类型标签、年份、评分、加入时间，
  在本机 SQLite 投影分页查询及计数；Mesh 目录使用 X47 的本机缓存。
  新作品随目录刷新进入条件，不依赖 Nipa 在线。
- `state.query` 增加 `library.arrangements` 与 `library.catalogue`；HeadlessCore
  同样注册本地整理能力和状态视图。种子 AGENTS.md 已补片库事实。
- 未绑定身份的服务器作品可以通过 `NextUiData.work/episodes` 打开，来源剧集
  可经 `ui.open` 播放。已绑定服务器剧集也通过同一 `MediaSourcesService.play`
  激活正确服务器并调用原播放入口。服务器图片缓存为真实本机文件路径。
- 入口、条件语义、ID、分页和持久化约定见
  [ui_data README](../../lib/next/ui_data/README.md)，来源接线见
  [media_sources README](../../lib/next/media_sources/README.md)。

## 决策

1. 片库整理与首页摆放同属 `ui.*`，命名为 `ui.library.*`，不引入另一套策展
   概念。类别 ID 全局唯一，put 保留已有位置，新类别追加。整理保存在
   `ui_cache` 的 `library:layout:*`，这些行属于持久布局，不能随图片缓存清理。
   切回原样保留整理；删除最后一个整理类别时显示原样，不删除媒体或身份。
   原始类别的顺序和隐藏列表独立保存，只影响本机；restore 恢复隐藏类别。
2. 条件的数组内为 OR，各维度间为 AND，针对合并作品整体判断。所在页面不
   暗加来源限制，因此同一类别能收本地和 Jellyfin 的作品。服务器作品须有
   已接受身份才参加条件；浏览不自动接受服务器 ProviderIds。没有身份的
   服务器作品仍可原样打开，也可按来源 ID 手选。评分取作品显示的第一项，
   状态保留 ratingSource；未知年份、标签、评分不会满足相应条件。
3. SQLite v17 只新增可重建的 `next_library_index` 与时间索引。原有任务、绑定、
   历史、回执和设置不改写。X47 compose 生成投影，条件 items 使用 COUNT 与
   LIMIT/OFFSET，不调用原 `library()` 取得整个作品列表后截页。
4. 原样作品/剧集/文件夹分别使用 `source-work:`、`source-episode:`、
   `source-folder:`，编码来源配置 ID、条目 ID、实际服务器 ID。来源重配到
   另一实际服务器后旧 ID 报 conflict。原样保留完整来源作品；条件使用 X47
   合并 ID，部分绑定不会隐藏原样中的未绑定剧集。
5. 剧集作品的 next 使用服务器 IsResumable、IsUnplayed、第一集的有界查询，
   每次最多一条，按季/集号排序，不为每张作品卡读取全部集。ChildCount 可能
   是季数，不能冒充集数；没有观看位置时不补进度 0。
6. Jellyfin/Emby 的 StartIndex/Limit/TotalRecordCount 由原 Classic 客户端的新
   `catalogPage` 入口提供。原 `browseCatalog` 行为未改。SMB/WebDAV 无对应
   协议分页，首屏枚举一层并缓存，后续在 SQLite 分页，不递归扫描整棵共享。
7. 图片沿用认证客户端，解码后原子发布。缓存键包括实际服务器和图片 tag。
   来源快照缓存也使用现有脱敏器，带认证参数的 URL 保存为 credentialRef，
   不将传输凭据放进缓存、状态或回执。

## 实验与检查

证据在 [evidence/x48](evidence/x48/)。功能观察使用显式实验文件；自动测试
覆盖事务、引用、迁移及 Classic 回归。

| 观察 | 结果与证据 |
|---|---|
| 5000 部缓存作品条件分页 | 总数 3749，两页各 60，首次实验约 36ms；新增符合条件作品后总数 3750，无 Nipa 调用。`focused.txt` |
| 真 Jellyfin 原样打开 | colima `nipa-test` 中一次性 Jellyfin 10.10.7，自制 CC0 两集纯色视频；未绑定 Series 打开，episodes 为 1、2，海报为已存在的本机文件。`jellyfin.txt` |
| 原样剧集播放路径 | `ui.open` → 来源播放回调 → 真服务器 HTTP 206 Range，读取 128 字节，无身份绑定。`jellyfin.txt`、`source-play-final.txt` |
| 跨来源条件与部分绑定 | 本地与 Jellyfin 接受同一测试 TMDB 身份后条件只返回一部，原样第二集仍可打开；绑定服务器单集读取 64 字节，错误 serverId 在播放前拒绝。`source-play-final.txt` |
| 服务器真实分页 | offsets 0、1、2，limit 1，返回条数 1、1、0，total 2。`jellyfin-paging.txt` |
| 作品卡 next 与脱敏收尾 | next 为可播放第 1 集，实际读取 64 字节，episodeCount 未伪造；脱敏、重配引用、批次原子性、用户归属等 5 项通过。`constraints-next-final.txt` |
| X47 回归 | 真 TLS、2,808,032 字节视频、Range/HEAD/416、ffprobe、8 秒 seek MD5、进度 .75→.25、离线缓存全部通过。`mesh-progress-fixed.txt` |
| 构建 | Headless AOT 和 macOS Debug 构建成功。`headless-final.txt`、`macos-final.txt` |
| 静态检查 | `lib/next`、改动的 Classic 客户端和相关测试：0 error、0 warning，176 条 info。`analyze-final.txt` |

### 意外、失败及修复

- 初次 Core 定向检查因建立条件目录时加载测试图片而触发宿主没有的 Rust
  框架/网络下载；调整准备时机后同一 Core 的 4 项通过，见
  `focused.txt`、`focused-core-fixed.txt`。
- 初次 Jellyfin 绑定实验的时长探测加载 MDK，测试宿主没有该框架。实验改为
  注入固定测试片的时长供应者，绑定和视频字节观察随后通过。它没有启动 GUI
  播放器；不据此宣称真实播放器画面/音频验收完成。
- 一次 Classic/约束/X47 组合运行结果为 62 passed、1 skipped、1 failed。
  失败来自缓存优化在 compose 后重新记 stamp，遮蔽了新进度；去掉该写入后
  X47 原真实实验定向通过，见 `constraints-classic.txt`、`mesh-progress-fixed.txt`。
- 首次交付阶段完整 `flutter test --no-pub test/next` 按 TEAM 运行一次，结果为
  **483 passed、7 skipped、8 failed**，见 `next-full.txt`。七项 download_runtime
  失败来自来源状态指纹在无 Flutter binding 的启动阶段初始化 Classic 配置；
  改为显式读取来源后观察，状态查询不初始化来源。另一项旧迁移 fixture
  rewind 到 v14 时仍留下 v17 投影表，修正 fixture；生产迁移仍严格建表。
  修复后相关 download_runtime、迁移、state 文件 **35 项通过**，见
  `full-failures-fixed.txt`；最终 26 视图及只读/脱敏检查 **19 项通过**，见
  `state-final.txt`。首次交付没有重跑全量；本次审查补跑记录见下文。
- 来源重配测试曾错误假定初次读取只有一次，实际 work/episodes 各读一次；
  改为验证重配后不再读取旧来源。脱敏测试曾期待 `[redacted URL]`，实际约定
  为 credentialRef；令牌始终已被移除。两项最终通过。
- 另一次全仓库 analyze 扫描到既有 Classic、third_party 和 build 产物，报告
  6194 条问题；输出保留在 `analyze-repository.txt`。改动范围的最终检查如上。

### 复现与清理

测试使用 Flutter 3.44.6、`--no-pub`，按 `/tmp/nipa-next/flutter-test.lock` 排队并
移除代理。`library_page_experiment.dart` 可独立运行。服务器实验用
`jellyfin_setup.py` 在本 worktree `.dart_tool` 建临时目录和 mode 0600 session；
`NIPA_X48_SESSION` 指向该文件，`NIPA_X48_PHASE=bound/paging/next` 可只跑对应
观察。setup 不输出密码或令牌。首次 setup 曾因 Startup/User 初始化顺序以及
Colima 无法读取 `/tmp` 挂载失败，成功版本使用 `~` 下的临时目录。

本轮没有读真实账号、登录钥匙串或用户媒体库，没有在工作站操作，没有启动
用户应用。只清理自己创建的 `nipa-x48-jellyfin`、session 和失败临时目录；
`nipa-test-smb/emby/jellyfin` 是其他实例，保留它们及 Colima profile。证据中的
测试令牌扫描无命中。构建生成的 Podfile.lock 恢复到原版本，初始已有的
GeneratedPluginRegistrant.swift 修改保留。

## 还缺什么

- 主控合并 Y7 后把临时供应者接到 `core.libraryData/core.libraryActions`，再做
  真实界面打开、播放和切换验收；本轮没有操作界面代码。
- 本轮新起了真 Jellyfin，没有新起 Emby/SMB/WebDAV 实例。它们复用已有客户端
  且相关 Classic 回归通过，但不能替代各协议的真实界面验收。
- X47 的底层目录同步仍全量重建；本轮消除了片库 items 的全量返回和重复
  compose，但不是 X47 增量同步改造。旧 Mesh 快照没有 sourceIds 时保留未知，
  不猜为本地；新快照补齐后才能满足相应来源条件。
- SMB/WebDAV 第一页仍有单层完整枚举成本；来源详情 episodes 沿用既有接口，
  按服务器页抓取后返回一部作品的全部剧集。作品卡 next 查询最多三次，
  大书架仍可能受服务器延迟影响。

## 需要主控决定的问题

没有。接口兼容；Y7 数据接线与真实界面验收是已约定的后续集成。

## 主控审查补充（2026-10-13）

已先读取主分支 c1b179e9 的 `library.dart`，按其中注释补齐三处行为。

- 原始页类别现在可直接 move/remove：顺序保存为本机 originalOrder，隐藏
  保存为 hiddenOriginal，不改服务器或共享。与整理类别的顺序、删除互不覆盖。
  隐藏可通过新能力 `ui.library.restore {entries:[{categoryId}]}` 批量恢复，
  ID 可从新增 `UiLibraryPage.hiddenCategories` 或状态中的 hiddenOriginal
  读取。恢复保留原位置；切换形式、原样/整理及重建服务均保留布局。
- 用户与 Nipa 仍共用批次验证和事务。动态区分“已隐藏原始类别”与
  “已移除整理类别”，恢复记为“已恢复原始类别”；facts.operations 保留各项
  操作。能力描述明确隐藏仅在本机生效、恢复入口以及整理删除不属于恢复范围。
- 新增 `LibrarySourceCache`，最近成功的根目录、分页条目和图片路径都保存到
  本机 ui_cache，缓存范围包含实际服务器身份。离线返回已读条目与最后总数，
  缺少观察时返回空页；不加错误文字，封面继续使用本机文件。分页缓存按条目
  位置读取，可跨此前的分页大小取回已读范围，不为未读页编造内容。
- 服务器或共享传输失败时保留缓存并将来源标为不可播放；原样 Series 的 next
  与已读剧集也保留。条件/手选类别中的绑定作品检查 next 的本机来源定位，
  不再沿用缓存中已经过时的 playable=true。page 读取根目录会重新尝试连接。
  新增 Mesh 的本机剧集 ID 解析只读方法，供此项定位，无网络请求。
- 共享根类别只有成功枚举后才进入最近观察，所以首次离线也是空页。Classic
  SMB 的传输异常部分继承 Error，缓存边界专门识别它们；JSON、引用、数据库、
  文件落盘和程序错误继续向上传递，不被当作离线状态。

### 本次验证及意外

四种来源均新增“在线读取 → 断开 → 重建服务 → 读取”的测试，核对类别、封面、
跨分页大小的内容、总数与不可播放标志，另验证恢复连接、首次离线空页、
隐藏恢复持久化、非法批次不写布局/activity、Series 剧集缓存及服务器身份隔离。
本次使用隔离的来源供应者及传输异常夹具，没有访问真实账号或重启前次测试服务器。
定向片库/状态/Core 回归 36 项通过，见 `review-focused-fixed.txt`。

初次缓存测试发现根列表和图片路径被当成 ObjectSchema 顶层值脱敏后变为空，
改为在对象字段中脱敏并保留原类型；默认排序与显式排序的目录缓存键也已统一。
记录见 `review-focused.txt`。后续绑定作品测试夹具遗漏 NOT NULL 的 relation /
ordinal，且旧夹具的集号类型不符合本地接口，已修正；保留失败记录
`review-focused-final.txt`、`review-focused-complete.txt`。

按主控要求，本次完整 `flutter test --no-pub test/next` 运行一次：
**506 passed、7 skipped、0 failed**，见 `review-next-full.txt`。前次 8 项失败
不再出现，绑定作品修正后的单项也通过（`review-bound-fixed.txt`）。

全量之后复查发现相同分页缓存仍重复写库，可能通过 changes 触发界面持续刷新。
补为按指纹只更新变化的缓存行，共享目录投影也只更新差异；追加相同在线/离线
观察保持 total_changes 不变的约束。最后相关片库测试 **19 项全部通过**，见
`review-cache-final.txt`。该收尾修改后没有再次跑全量。

最终 Headless AOT 编译成功（`review-headless-final.txt`）；本次相关静态检查 0 error、
0 warning、93 条 info（`review-analyze-final.txt`），`git diff --check` 通过。
未启动任何真实用户实例，未使用
真实账号，未修改 UI、依赖或提交代码。
