# Next 的界面数据

`UiTask.type` 是持久任务类型（download、media.scan_classic 等），与 helper/background
的 `kind` 分开。关联实体已移除时任务仍可读取，图片与作品名为空。
宿主专用的 `core.hostSettings.deviceSettings` 提供 Classic 远程接收设置、受信任设备
移除以及防剧透/TMDB 密钥写入；契约见 `host_settings.dart`。密钥只返回是否已设置，
null 保留、空字符串清除。这些接口不注册 Action；宿主不支持时如实报错。

界面在 `await core.ready` 后使用 `core.uiData`（实现 `NextUiData`）。订阅 `changes` 后重新读取首页、作品、剧集和卡片；`tasks()` 每个订阅先收到完整任务列表，随后在任务修改时收到新列表。界面退出时取消订阅，NextCore 负责关闭服务。

## 按来源的片库（X48）

X56 搜索经 `media.library.search_merged` 读取同一合并目录投影，返回作品摘要和
命中的 `{work,episode}`。作品 ID/剧集 ID 与 `work()/episodes()/ui.open` 一致；
摘要增加 `aliases` 和作品级 `playable`，其他字段沿用 `workJson/episodeJson`。
标题、原名、各设备已有别名/替代标题与年份写在 `next_library_index.facts`，
剧集标题与身份键也随 compose 维护。内存 Unicode 1–3 字符倒排索引只对文字变化
更新 posting，进度/在线事实更新不重建文字 posting；搜索仅交集候选并返回有界结果。
首次读会准备目录，后续随五秒目录刷新；不从 UI 的 library.merged 全量视图筛选。
详细接线说明在 `docs/next/X56_REPORT.md`。

入口是 `core.libraryData`（实现 `NextLibraryData`）和 `core.libraryActions`
（实现 `NextLibraryActions`），后端为 `LibraryDataService`。不需要界面解析 Action
回执。`sources/page/items` 分别读取来源菜单、当前类别和分页；`items` 默认 60、
上限 500，offset 从 0 开始，返回 `total`。订阅同一个 `changes`。合并时将 Y7
的临时数据供应者接到这两个入口；本实现没有修改 `lib/next/ui/`。

本地仍是 X47 的整个合并目录，只有“全部”。其他来源使用 Classic 已有配置、
登录态和客户端：Jellyfin/Emby 只显示已选库，文件夹保留为可继续打开的
`UiFolderItem`，Series 打开作品详情及季/集；SMB/WebDAV 从共享根路径逐层浏览。
服务器原样排序读取 Classic 每库偏好，发现的父关系持久缓存以便子目录继承；
请求中的 sort 不改变 Classic 偏好。SMB/WebDAV 排序为名称或修改时间。

Nipa 的能力与首页摆放同属 `ui.*`：

| 能力 | 输入 |
|---|---|
| `ui.library.sources/page/items` | 与数据接口相同的 sourceId/categoryId 和分页参数 |
| `ui.library.put` | `entries:[{sourceId,categoryId,title,content,coverWorkIds?,sort?}]` |
| `ui.library.configure` | `entries:[{sourceId,form?:shelves或cards,original?:bool}]` |
| `ui.library.move` | `entries:[{categoryId,index}]`，下标从零开始 |
| `ui.library.remove` | `entries:[{categoryId}]`，原始类别在本机隐藏，整理类别从整理中移除 |
| `ui.library.restore` | `entries:[{categoryId}]`，恢复隐藏的原始类别 |

`put` 是完整替换一个类别，保留已有位置；新 ID 追加，ID 全局唯一。整批先验证，
再以一个事务写入布局及 activity。封面由最多三部 `coverWorkIds` 提供，缺少时取
预览作品的已缓存海报/背景。GUI 的四个直接操作调用同一实现，来源 `gui`、actor
`user`，Nipa 保留实际调用来源。切回原始结构保留所有整理；最后一个类别移除后
显示原始结构。布局保存在 `ui_cache` 的 `library:layout:*`，不是可自动清理的图片缓存。

原始结构同样支持直接重排与隐藏：`move` 的下标是当前可见类别中的下标，
`originalOrder` 和 `hiddenOriginal` 独立于整理类别持久保存在本机。它们不修改
服务器排序、服务器库或共享目录。隐藏后可从 `page.hiddenCategories` 的
categoryId/title 或 `state.query library.arrangements` 的 hiddenOriginal 取 ID，
用 `ui.library.restore` 批量恢复；恢复保留已保存的位置。切换形式、原样和整理
不会清掉顺序或隐藏记录。activity 分别使用“隐藏原始类别”“恢复原始类别”
和“移除整理类别”。接口只新增 `UiLibraryPage.hiddenCategories`，已有字段和
方法保持兼容；`NextLibraryActions` 的 move/remove 语义与主分支 c1b179e9 一致。

`content` 恰好一种：

```json
{"kind":"condition","filter":{"sourceIds":["local","jellyfin:服务器配置ID"],"types":["anime"],"watch":"unwatched"}}
```

```json
{"kind":"manual","workIds":["作品ID","另一部作品ID"]}
```

```json
{"kind":"original","sourceId":"jellyfin:服务器配置ID","parentId":"服务器库或文件夹ID"}
```

条件还支持 `deviceIds`、`genres`、`yearMin/yearMax`、`ratingMin/ratingMax`、
`addedAfter/addedBefore`（ISO-8601）。数组内任一值匹配，维度之间都须匹配，
维度作用于合并作品整体；所在页面不会暗加来源条件。watch 为
unwatched/watching/watched；年份、标签和评分未知时不满足相应条件。评分采用
作品界面第一项评分，`ratingSource` 保留它的来源；加入时间继承 X47 合并组的
排序事实。作品类型取明确的 anime/series/movie 属性及已接受的弹弹play、Bangumi、
TMDB 身份，不按标题猜测。Jellyfin/Emby 必须有 X47 接受的作品身份才进入条件，
原样浏览不自动接受 ProviderIds；本地/共享的已登记 work 实体也可参加条件。
手选只提供“手选顺序”。本地来源原样引用为 `sourceId:local,parentId:all`。

`state.query library.arrangements` 展示已加载的来源配置和全部持久整理（含已移除
来源的保留布局）；`library.catalogue` 提供本机条件投影中的 sourceIds/deviceIds/
types/watch/genres/year/rating/ratingSource/addedAt。两者不联网、不建立身份或分类。
条件投影是 SQLite v17 新增的 `next_library_index`，由 X47 本机/认证 Mesh 快照及
进度重建。初次条件读取建立投影，随后每五秒/显式刷新更新，新作品不需要 Nipa
在线。分页读取只返回当前页作品，SQL 同时计算总数。X47 快照同步仍有全目录
重建成本；这次没有把其底层同步改为增量。

Jellyfin/Emby 原样内容使用 StartIndex/Limit/TotalRecordCount，一次只读服务器的一页。
SMB/WebDAV 协议没有相同的分页：首屏枚举一层目录，把视频与目录条目缓存到
本机，后续滚动用 SQLite LIMIT/OFFSET，不递归枚举整棵共享。详情 episodes 的
既有接口返回一部作品全部剧集，因此通过服务器分批读取后合成列表。

离线时，`LibrarySourceCache` 返回最近成功读取的库、目录条目、总数和本机图片
路径；从未成功读取的来源返回空页，不添加错误文字。缓存按来源配置与实际
服务器身份隔离。目录观察按排序、过滤、递归方式及条目位置存储，离线仍用
SQL 读取请求范围，limit 改变也能复用已读条目；尚未读过的位置不编造内容。
page 的根目录读取会重新尝试来源，恢复连接后更新缓存。已绑定的条件/手选
作品也检查 next 剧集的本机来源定位；离线来源的 next.playable=false，仍可读
其资料。缓存失败不覆盖上次成功观察，JSON、引用、数据库及程序错误照常报错。

未绑定作品使用 `source-work:` ID，剧集使用 `source-episode:`，文件夹使用
`source-folder:`；内容为来源配置 ID、原始条目 ID 和实际服务器 ID 的不透明编码。
不同服务器互不碰撞，来源改指另一实际服务器后旧引用报 conflict。原样详情保持
服务器作品 ID，已绑定条件内容使用 X47 合并 ID，因此部分绑定不会藏掉原样中
尚未绑定的剧集。`core.uiData.work/episodes` 接受这些作品 ID，`ui.open` 对剧集
激活正确来源后调用现有 `media.sources.play`；条件中的已绑定服务器剧集也保留
sourceInfo 并走同一个播放入口和续播位置。来源原样引用自动保存实际服务器 ID。
服务器剧集作品的 `next` 按续看、未看、第一集的顺序查询，每次最多一条，
按服务器季/集号排序；书架不会为每部剧读取全部集。服务器的 ChildCount 对剧
可能是季数，因此不充当 episodeCount；缺少观看位置时进度保持未知。

服务器图片经原客户端的认证请求取回，解码后原子发布到 `source-artwork`，
缓存键包含来源、实际服务器、条目、图片种类和 tag。海报、背景和 still 都为本机
路径；缓存及回执不保存认证图片/播放 URL。证据和限制见 X48_REPORT.md。

`workId / episodeId / taskId` 和书架 `id` 用于点击、定位和调用能力，不是显示文字。其余文字为作品元数据、简短的观看提示或 Agent 的短句。普通任务标题由任务类型与关联作品生成；还不知道作品的下载用它自己的名字（种子名或磁链显示名，原样，去掉 `.torrent`），名字只是 info hash 时只写“下载”；帮手使用 Agent 给的简短标题。

## 一个媒体库（X47c）

`library()` 是本机和同账号 Mesh 设备的全部作品，合并后的一份，最近添加在前。
不从首页书架反推全部作品，不增加分类、筛选或分区。`work()`、`episodes()`、
首页最近添加/继续观看及卡片引用均接受合并 ID；界面沿用原 `ui.open {entityId:剧集ID}`。
`UiWork.devices` 标注作品所在的其他设备，`UiEpisode.device` 是当前优先播放来源；
本机来源为 null。`playable` 表示现在能播，包括在线远端。离线作品保留上次事实、
`UiDevice.online=false`，仅远端来源的剧集 `playable=false`。

作品按已接受 exact/contains 的弹弹play、TMDB 或 Bangumi 外部身份合并，候选和标题
相似度不算身份。已接受 release 上的作品身份也参与；无共同身份时，相同文件摘要可
连接两份目录。剧集在同一作品内按已接受单集身份、明确季/集号，或相同文件摘要加
时间段做传递合并，未知集号不猜。同一文件在本机与远端重复时优先可播放本机，
其后在线远端，最后上次记录。文件摘要为大小及首尾各 64 KiB 的 SHA-256；按大小/mtime
缓存，避免每次扫描 SMB 整部视频。它是去重观察，不是完整内容校验；极端的相同首尾
不同中段文件可能误判。文件传输的最终校验另使用完整 SHA-256。

外部身份与来源引用生成 `mesh-work:` / `mesh-episode:` / `mesh-ref:` ID。本机原始 ID
仍接受；历史合并 ID 的来源引用保存在 `ui_cache`，接受新身份或重启后继续解析。
作品添加时间取已有最早绑定时间，无该事实时用首次观察时间，并持久保留。
没有原始入库时间的旧目录只能按首次观察排序。

每 5 秒刷新经过认证的目录并检查本机文件，显式 `media.library.refresh` 可立即刷新；
新版本、进度、连通状态改变会触发本机 `changes`。每个节点只存自己的 `next.db`；
其他节点的目录投影（不是数据库）、ID 别名、进度存在 `ui_cache`，图片和小型播放
附件存在 `mesh-artwork` / `mesh-assets`。远端 `UiArtwork` 和 still 均转换成本机文件路径。
`media.metadata.ui_facts` 也读合并投影的资料/来源及弹幕字幕事实。

进度是观察事实：Classic 本机历史和 Mesh 播放观察合并，最近 UTC 时间戳优先，同时间
按 writer 设备 ID 排序。允许回退/未看，不取历史最大值。Mesh 播放每 3 秒记录并在
结束宿主时补一次观察；批量写入先全部验证，不部分提交。按单集来源引用和文件摘要+
时间段传播到各节点缓存，断网保留并在恢复后交换。`media.library.progress` 和
已有 watched-history Action 都接受合并 ID。依赖设备时钟，不能替代精确跨节点时间同步。

Agent 从 `state.query {view:"library.merged"}` 读取同一库；本机事实视图
`library.works/episodes/files` 保留原语义。`media.library.readable` 批量给出剧集可读地址，
任意路径读写能力、仅回环 HTTP 与双向 TLS 字节通道见 [Mesh README](../mesh/README.md)。

回环 URL 每次带 256 位安全随机令牌，MeshLibrary 关闭或进程退出即失效，未发放的
地址返回 404。默认随机端口，宿主可在 mesh.json 设置 fileProxyPort（1024–65535）；
固定端口占用时回退随机端口，`state.query mesh.file_proxy` 如实展示请求/实际端口、
状态与原因，不暴露令牌。该配置没有 Agent 设置/修改入口，配置变化需重启宿主。

## 首页与移除

`ui.shelves.put` 替换一处摆放：

```json
{"placement":"hero","note":"今晚一起看。","items":[{"workId":"本地作品 ID"}]}
```

```json
{"placement":"shelf","id":"tonight","title":"适合今晚","items":[{"workId":"本地作品 ID","note":"听一场热闹的演出。"}]}
```

`items:[]` 移除。书架保留稳定的 Agent 自定 ID；`hero / continue / recent` 为保留 ID。书架项的 note 映射为 caption，缺省时按下一集及观看进度生成。继续观看读取合并进度与现有 `history.continue_watching`；尚未接入历史供应者时不制造观看记录。最近添加读取上述合并库，最多二十部。

GUI 可用 `core.uiData.removeShelf(id, workId: ...)` 移除一项，省略 workId 移除整处摆放。能力入口为 `ui.shelves.remove`，保留调用者来源。用户移除写入 `body_changes`，activity 中有自然标题、用户来源及关联作品。

`airing` 是保留书架 ID。今天更新位于继续观看之后，空时省略。作品需要已接受的弹弹play作品身份，并出现在收藏日历中，或已有在看/继续观看历史。复用 X29 的 Classic 日历和详情缓存，以单集 `airDate` 的本地日期为准；只有星期没有剧集日期时不猜。缓存不足且已登录时，经原 BangumiService 取得日历/详情。一天多集展示目录中最后一集；有明确时间才显示“今天 23:30”。日历由运行时供应给 Core，Core 单独使用时没有 Flutter 设置服务依赖。

主视觉优先采用 Agent 的 hero。否则读取成功任务关联的可播放作品，再取本机最近可播放入库；这两项是“最近准备好”的事实。其后取继续观看作品的可播放新集，最后取继续观看首部。自动主视觉没有 note。

## 对话卡片

`ui.present` 输入 `cards` 数组，每次调用追加在当前回合。`NIPAPLAY_CHAT` 的来源字符串对应已有 journal 的最新回合边界；无活动回合报错，不猜测线程。省略 `cards()` 的 turnId 读取整个线程，提供 turnId 则只读指定回合。

| kind | 引用与短句 |
|---|---|
| work | workId，或片库外作品的 ref（二选一） |
| episode | episodeId，作品从父关系解析 |
| candidates | items: [{workId 或 ref, reason?}] |
| task | taskId，使用任务的 jobId |
| preparation | title、可选 workId、steps: [{label, detail?, 三选一 taskId / entityId / followupId}] |
| choices | question?、options: [{label, detail?, recommended?}]，2–6 项，label 不重复；用户点一项，界面在对话里说出这项的 label |

引用在整个批次写入前验证；缺失引用的错误说明应查询的视图及 ID 语义。步骤不可提交 state/progress，实时读取任务或后续；实体步骤表示已经找到该作品/剧集。没有额外的状态常量或第二份任务状态。接口的 failed 合并失败和取消，paused 合并暂停、等待决定及中断；等待重试映射为 queued。remaining 无可靠估计时为 null。

X37 的帮手同样使用 `ui.present`，其活动来源为 `harness_cli:helper:<jobId>`。
原卡片位于帮手线程的实际回合；帮手结果的后续派发时，引用也追加到发起线程的实际后续回合。
重复对账不会重复复制。卡片中的任务仍实时解析，不保存第二份任务状态。

### 片库外作品（ref）

`ref` 是作品级的来源对象 `{provider, objectType, externalId, scope}`，与
`media.metadata.search/get` 返回的 ref 相同；支持 tmdb 的 tv/movie、bangumi 的 subject、
dandanplay 的 anime，scope 只能是空字符串（可省略）。存进 `ui_presentations` 的是规范化后的
ref，不存资料。

- 提交时先查片库：`MediaService.acceptedWorkIds` 按已接受的 exact/contains 作品或 release
  绑定查本机与 Mesh 合并目录（与 `media.metadata.search` 的 workId 相同，不按标题推断）。
  有则这一项就是片库作品，不访问来源。
- 否则调用该来源的 `get`（即 `media.metadata.get` 的服务层），标题、原名、年份、简介、集数、
  评分、海报地址写入 `ui_cache`，行 ID 是片库外作品 ID；海报经 `ArtworkCache.picture`
  下载到同一图片缓存并取 tint，同一地址只下载一次。读不到（不存在、类型不符、无标题）报
  invalidInput，来源暂不可用报 unavailable（限流/网络为 retryable），整批不写入。资料只在整批
  验证通过后与 presentation 同一事务写入。
- 返回值增加 `refs:[{ref, workId, title?, year?}]`，workId 为 null 表示片库外。
- 读取 `cards()` 时每次先查片库，有同一身份就给片库作品（之后入库也随之变化）；否则从
  `ui_cache` 组出 `UiWork`，不访问网络。缓存被清掉时才向来源再读一次；海报文件不在时用原始
  地址，由界面自己加载。读不到的项不显示。

片库外作品 ID 定义在 `found.dart`：`found:dandanplay:<id>`、`found:bangumi:<id>`、
`found:tmdb:tv|movie:<id>`；界面据此打开发现页同款的作品页（“让 Nipa 准备”），页面打开时经
`media.metadata.get` 补简介。`MetadataRecord` 的作品记录在来源提供时带 `rating`
（value/max/count）和 `episodeCount`，`media.metadata.get/search` 同样返回。

## 后台任务契约（X37）

`UiTask` 原字段保持兼容；新增字段默认可省略。

| 字段 | 含义 |
|---|---|
| taskId | 持久任务号，可用于 `task.get/cancel`，不是显示文字 |
| title | 观众看到的短标题；帮手使用调用者提供的 title |
| state | queued/running/paused/finished/failed；容量等待是 queued，取消仍映射 failed |
| kind | `UiTaskKind.background`（默认）或 `helper`，区分普通任务与帮手 |
| startedAt | 实际开始处理的 UTC 时间；帮手进入线程时记录，尚未开始或没有该事实时 null |
| currentActivity | 一句现在在做什么；帮手可用 `agent.helper.report` 更新，否则显示宿主的简短状态；其他任务可为空 |
| summary | 结束回执里的结果摘要；尚未结束或没有摘要时 null；是帮手的报告，业务结果需查对应回执 |
| threadId | 帮手的 Codex 线程号，可打开其对话；排队尚未建线程或普通任务为 null |
| parentThreadId | 结果返回的发起会话线程号；普通任务为 null |
| cancelled | 是否确实取消，默认 false；可区分 failed 中的取消与错误 |
| source | 可选来源：`codexNative` 为原生子代理，`host` 为 `agent.dispatch` 的宿主派发；原任务兼容 null |
| artwork | 已缓存的关联作品图片，无关联或缓存时 null |
| progress | 可核实的 0–1 进度；未知为 null，帮手始终 null，包括完成后 |
| remaining | 有可靠估计时的剩余时长，否则 null |

没有进度也是正常后台任务。不得把 null 补成 0%、完成时补成 100% 或用思考/命令次数估算帮手进度。

X38 原生子代理复用上述字段：标题取 prompt 的短句，currentActivity 取最新助手短句或实际工具阶段，summary 保留最后完整回答；取消仍是 failed + cancelled=true。没有修改作品或图片投影。
两个帮手同时运行，更多的按创建顺序等待；这个上限不限制主会话。

## 图片与热度

`media.metadata.ui_facts {workId}` 直接读取同一个 `NextUiData.work/episodes`，返回所有作品资料和逐集标题/截图的 `available/value/path/source`、简介与标题语言、截图覆盖数量、优先主视觉图与 tint。没有假名证据时语言采用声明值，缺少声明就是 unknown；发现日文假名时 language=ja，保留 declaredLanguage 与 languageBasis，避免把中文请求参数误当简介的实际语言。生成的集数注明来自本地剧集目录。读取可能填充可删除的图片缓存。

`media.artwork.set` 输入 `entries:[{entityId,kind,url或file,source:{label,url?}}]`。backdrop/poster/logo 的 entityId 是作品，still 的 entityId 是单集；url 是无 userinfo 的 HTTP(S)，file 是本机绝对路径，两者恰好一个。整批图片解码、复制/缓存成功后，原子写入既有 `media_overrides/media_metadata_edits`，activity 的 metadata.edited 保留来源、调用者与 invocationId。四种图片独立覆盖；来源快照、身份与旧编辑全部保留。文件以内容哈希复制，原文件可删除；URL 沿用 X26 的 URL 哈希下载缓存。覆盖不需要平台身份或平台凭据，并在来源刷新后保留。

标题与简介仍用 `media.metadata.override`：field=title 是显示标题，field=overview 是简介，支持 language:"zh-CN"。语言与文字采用相同的 persistent/correction/clear 生命周期，替换文字时未声明语言就恢复 unknown，不继承旧语言。来源文字优先简体中文，显式用户/Agent 编辑仍优先。

没有图片覆盖时，从作品/剧集已接受的身份取得，沿用现有作品/发行的 contains 关系与单集的 exact 关系。TMDB 复用原 MetadataTransport、正常凭据解析和应用的系统代理；支持保险库的 API key 与 Bearer 读取令牌。没有 TMDB 身份时沿用已有来源的 imageUrl；没有 TMDB 凭据时仍能读取已保存的图片事实和独立覆盖。

TMDB 的图片 URL、语言选择、评分、类型、集数、制作公司和单集时长追加到原 `media_snapshots`，保留对象身份、来源、抓取时间和收到时间；本地图片是可删除的投影。背景优先语言为 null 的图；Logo 为中文、日文、英文、中性图。文件按 URL 哈希存到 Next 数据目录的 artwork，解码验证后原子发布。tint 将背景（缺少时使用海报）缩到 64 像素宽，对 RGB 色箱计数，并取最多色箱的平均色，包含 ARGB alpha。

普通公开 URL 包括非秘密查询参数会原样进入 Agent 输出；userinfo、令牌、签名查询/片段和已知秘密仍脱敏。服务端和种子 nipa 同时应用此约束。`ui.capture` 默认 PNG 长边至多 1280 像素，不放大小图；originalSize:true 返回原尺寸。输出同时包含 originalWidth/originalHeight，与 instance 一起确定截图来自当前连接实例。

每集热度汇总当前有效绑定的所有缓存，包含剧集轨道及关联文件轨道，不因播放时关闭轨道而遗漏已有弹幕。相同缓存/时间范围/偏移只计一次；每个来源内部沿用原缓存读取的去重。文件轨道按剧集范围裁剪，偏移后映射到剧集时间轴；没有范围的多集文件不猜测。60 个等宽桶按最高桶归一化，无弹幕为 null；无时长时用最后一条弹幕的时间作为跨度。绑定、修订、偏移、范围、时长、缓存内容/收到时间进入缓存指纹，变化后重算。

`UiWork.danmaku` 只读取上述有效缓存和剧集范围。先取目录第一集的前 180 秒，不足六句时依次扩到第二、第三集的开头；不会扩到单集后段。时间窗可用 `settings.set {key:"next.heroOpeningSeconds", value:180}` 调整（30–300 秒），GUI 可读取同一设置 schema。每句 2–18 个 Unicode 字符，合并空白、排除网址/域名、控制字符、四个以上连续重复字符及重复三次以上的短字符组；去标点和空白、转小写后跨剧集去重。按剧集、时间排序，同刻按原文排序，最多六句。保留真实原文，没有短语白名单，不做剧情语义判断；开头也可能含其他集的剧透。不会为这份投影发起网络请求。

`ui.open {entityId:作品}` 或 `{workId:作品}` 在 Next 外壳可见时打开 Next 详情，返回 `interface:"next"`；外壳未显示时沿用原 Classic 详情入口并返回 `interface:"classic"`。连接仅为 `WorkDetailBridge` 的挂载回调，界面调用已有 `openWork`。直接 animeId、页面、对话框、文件与剧集播放入口保持原语义。

## 本地观看状态与界面开关

界面和 Agent 都调用 `history.mark_watched_batch`：

```json
{"entries":[{"episodeId":"本地剧集 ID","watched":true},{"fileId":"本地文件 ID","watched":false}]}
```

每项恰好一个 episodeId/fileId。整批先解析并验证，Classic 观看历史事务只更新 progress、position 和 lastWatchTime；无历史、状态矛盾或多集文件会拒绝整批，保留匹配、时长、缩略图等字段。看过为进度 1、位置等于时长；没看过为进度和位置 0。成功后刷新原 WatchHistoryProvider，写入带调用者来源的 activity。Next 能力开启时，Classic 详情页的本地勾选走同一个 Action；原有账号观看状态同步保持原入口。

`labs_use_next_interface` 已注册到 `settings.describe/get/set/reset/history`。注册表读取原存储键，写入实际的 NextUiPreference；界面写入仍经 SettingsStorage/SettingsAccess，只有一个值，并保留两边调用来源。

SQLite v12 增加 `media_file_aliases`，事务合并历史的通用 remote 文件和唯一来源范围下的同 URL 文件；保留旧 ID、观察、回执与合并前的行存档。运行时登记也执行相同合并，重复执行不再改变结果。不同服务器范围继续独立。

SQLite v11 只追加 `ui_presentations / ui_shelves / ui_cache`。任务提交后即时通知 changes；其余数据库和 Classic 内存历史每 250ms 观察一次（同连接 total_changes、其他连接 data_version、现有历史供应者），变动后通知。通知可能合并同一观察窗口或因缓存落盘多一次，不承诺每条领域事件一条通知。后台任务变化与轻量缓存投影无网络请求；首次作品/剧集读取可能等待图片下载。

Debug 且临时 profile 才注册 `ext.nipaplay.uiData`，供实验读同一界面接口、采样流、模拟会话边界、触发真实 hook 和通过正常保险库写入固定测试文件。该入口不在 Agent 能力目录，不在生产启用。
