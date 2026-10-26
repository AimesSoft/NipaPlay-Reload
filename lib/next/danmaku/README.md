# MB 弹幕来源与轨道

`nipa describe danmaku` 返回族说明；单项 schema 仍以实时目录为准。
`fetch_batch`、`attach_batch`、`import_batch` 接收单项 schema 的 `entries`（1–100），
全量 schema 验证后逐项执行，返回 index 与完整 outcome。非原子，后项失败不会
隐藏前项的绑定/任务/回执。无界面来源与 GUI 同用 NipaPlay 网关客户端；凭据是
宿主 `preferences/dandanplay_token` 引用，无播放器时显式指定 entityId/path。

`DanmakuRuntime.create` 接收 NextCore 提供的 MA 身份存储，提供 `executors` 与
`capability`。NextCore 在 `engine.start()` 前调用 `attach` 注入唯一引擎，启动后由
`NextRuntime` 调用 `startRestoring(harness, player)` 绑定宿主播放器；监听播放状态
并从已提交缓存恢复轨道，监听不发网络请求。关闭时 Core 先 `stopRestoring` 停止
恢复及 GUI 控制，再关闭 Task Engine，最后 `close` HTTP client。完整接入顺序见
[应用组合点](../README.md)。

## 来源与宿主边界

`source.dart` 是不依赖 Flutter 的 Dart 插件端口。来源声明契约/实现版本、平台、
能力、域名、请求 profile、访问策略和预算；提供搜索、目录、定位、半开区间段计划、
可取消段获取和计划验证。每个注册来源得到独立 `ScopedDanmakuHost`，不能调用
其他来源的 profile。首期没有把来源端口接入现有 JS 插件清单或渲染桥接。

| 来源 | 定位与目录 | 获取与身份 |
|---|---|---|
| 弹弹play | episode ID、标题搜索、作品目录；未知时长由调用者依据本地媒体补齐 | 原始 comment JSON，withRelated=true；保留条目级 source、sourceVideoId、originalId，cid 单独记为 sourceEntryId |
| local | 授权媒体目录中的明确 XML/JSON 路径；同名/相似名自动发现仍沿用 Classic | 共用 Classic 文件解析入口；从 chatserver/chatid 读取平台与视频身份；未知平台保持 unknown |

弹弹play 未提供条目级来源时保存 `platform=unknown`，不根据格式、cid 或用户 ID
猜平台。未识别的原始 source 仍保留在 originSource；没有原视频/原弹幕 ID 时，
不建立跨源身份等价。测试里的扩展字段是合成输入，不表示已验证真实服务器会返回
这些字段；真实 related 响应的来源字段仍需主控回放验收。

弹弹play 使用 Classic 的 `DandanplayHttpClient` 与
`NipaplayServerRouter`，所有请求经过 NipaPlay 网关的 `/dandanplay` 前缀，
账号认证与主备切换沿用宿主规则。

Next 注册的内置来源只有弹弹play与 local。优酷、B 站在线来源及应用内平台登录
已删除，Action 不再接受平台会话引用，也不返回平台会话状态。钥匙串里已有的
`next.platform-session/<platform>.v1` 条目保持原样；Next 不再读取、更新或删除它们。
删除来源的变更保留既有绑定、外部视频身份、缓存、对齐、事件与任务记录；轨道查询、
播放恢复、属性修改和导出直接使用保存的事实，不依赖来源仍被注册。
旧来源不能再在线刷新，尚未结束的旧获取任务恢复时因来源未注册失败，已提交数据保留。

## Agent 交入弹幕

`danmaku.import` 是写能力，接收 Agent 从任意途径取得的本地文件，不要求注册来源、
媒体目录授权。输入 `filePath`、`platform`、`platformVideoId`；目标
使用 `entityId`（File/Episode）、`path` 或当前播放文件（默认），可附 `note`。
文件复用 Classic 的本地弹幕解析与编码处理：XML、JSON 数组、`comments`/`data`
包装、弹弹play `p`/`m` 格式，以及 UTF-8/BOM、UTF-16 和原有旧编码。
XML 的 32 位 ARGB 和其他 Classic 支持的颜色使用相同颜色转换，存为 24 位 RGB。
同时保留规范化 JSON 数组或 `{ "comments": [...] }`。规范化条目示例：

```json
{"sourceTimeMs":1250,"text":"一条弹幕","mode":1,"colorRgb":16777215,"platformId":"9007199254740993"}
```

`sourceTimeMs` 是非负整数毫秒，`mode` 是正整数，`colorRgb` 是非负整数，
通过 Classic 颜色转换存为 24 位 RGB；
可选 `platformId`、`sourceEntryId`、`originSource`、`sender`、`sentAt` 为字符串，
`fontSize` 为正整数。平台和视频身份使用调用参数，actor/origin/UTC 时间由宿主
记录在 `provenance`，每次交入追加审计事件。输入文件只读取，内容保存成宿主数据目录
`next/danmaku/<sha256>.json` 文件，数据库记录相对引用、条数、范围、字节数与存储类别，
后续播放恢复不依赖原文件仍存在。空数组或 `<i/>` 表示明确交入空弹幕池。

Classic 格式的条目采用现有解析器的默认值和筛选语义，不再单独检查 XML 根名、
字段数或 24 位颜色上限。无法解析的文件返回 `invalid_input` 与实际解析错误；
非空输入无法产生可解析弹幕时也报告失败。Classic 本地加载仍拒绝空池；只有
交入入口显式允许空 JSON 数组和不含 `<d>` 的 `<i/>`，不把损坏的 XML 当空刷新。

解析、编码与文件写入在独立 isolate 完成；写完 flush、回读验证后原子换名，再用同一个
数据库事务提交文件引用、绑定和来源。相同
平台/视频再次交入即替换，保留启用、偏移和折叠设置；解析或提交失败保留旧轨道。
交入前已启动的抓取任务不能覆盖后来交入的弹幕池。File/Episode 同视频轨道在
播放时合并为一个，重新恢复时优先使用最新交入结果。返回 `bindingId`、`revision`、
`count`、`loaded`、`provenance`；`loaded=false` 表示已保存但目标当前未挂载。
播放中的目标立即挂载；`danmaku.tracks`、`state.query` 的 `danmaku.bindings` 和
`danmaku.tracks` 视图可查询来源。调用参数不承载整集数据，也不沿用在线来源的
响应大小和条目数量上限。数据库 v7 在绑定上追加 `provenance` 字段。

宿主使用固定 URI 模板，拒绝跨域重定向及额外业务参数，逐来源串行限流；HTTP
响应最大 8 MiB，每次计划最多 120 段、两小时、100000 条。超时只取消本次 HTTP，
不会冒充任务取消。429 尊重有界 Retry-After；任务只对限流/传输失败重试三次。
正片范围内的结构变化、宿主账号认证失败和访问拒绝立即停止。
不请求平台历史弹幕。

## 追加存储

数据库 v15 为内容引用追加 `file_path / entry_count / byte_count / storage_kind`。
旧内容在打开数据库时逐行迁移，保留原 JSON 的全部条目、顺序与字段；文件先完成并
验证，事务再清空大 payload（留下 `[]`）并提交引用。中断后继续尚未迁移的行。
全部行完成后执行一次 VACUUM，持久标记在成功后清除；整理中断也会在下次打开时重试。
迁移不删除既有无绑定的导入行，以保留可能仅剩的副本。

`storage_kind=imported` 记录明确交入的内容；`cache` 记录在线分段与
`application:playback` 回写的来源类别。这些名称为历史兼容保留，全部已提交内容都是
持久媒体数据，不能因可联网重新获取而自动删除。两者均存文件，读取校验哈希和条数。
刷新或撤销后，没有其他 accepted 绑定引用的导入池移除；共享文件等到最后一个
数据库引用释放才删除。事务回滚或中断遗留的无引用文件在启动、刷新、撤销及清理时收集。
启动不再按空间预算删除弹幕。`danmaku.cache_prune(maxBytes)` 仅收集数据库没有引用的
遗留文件，`maxBytes` 为兼容参数，不删除任何已保存池，不清空绑定指针。
存在未结束的获取任务时延后；系统 `cache.plan/prune` 同样保留全部弹幕内容。
`cache_delete` 仍是明确指定池的破坏性操作，可以删除交入内容。

现有 `backup.*` 和 WebDAV `sync.*` 只覆盖 Classic 类别（preferences、mediaLibraries、
watchHistory、episodeMatches、accounts），不覆盖 `next.db`、`next/artwork/` 或
`next/danmaku/`。离线备份 Next 必须在退出应用后同时保留数据库与内容目录；只拷
`next.db` 不包含交入弹幕。Mesh 的远程 Action 调用也不复制本机弹幕文件。

MA 的 v2 身份迁移保持原样，MB 在 `next_database.dart` 的迁移序列末尾追加 v3
（`migrateDanmaku`），不改已发布位置。新库与旧库共用同一序列，都执行到最新版本。

| 表 | 语义 |
|---|---|
| danmaku_bindings | 引用 MA File/Episode 与 media_external_objects；记录实体修订、启用、去重、绝对偏移、对齐、证据、宿主绑定者、绑定修订和已提交缓存 |
| danmaku_cache_chunks | 来源/视频/版本/网关域名/public/内容选项组成新获取的 cache key；旧 key 按原值读取；保存各段内容文件引用、条数、范围、覆盖及抓取时间；在线缓存新鲜期两小时 |
| danmaku_alignment_candidates | 存量对齐任务的锚点、固定偏移候选、残差、置信说明和显式选择；关联绑定修订 |
| danmaku_binding_events | 追加的 attach、控制、解绑与对齐选择审计记录；不抹去旧证据 |

MB 绑定不写入 MA 的元数据 bindings，也不投影 Classic 匹配字段，避免元数据解绑
意外撤销弹幕来源。文件内容修订变化会使旧 MB 绑定失效。Episode 通过 MA
FileEpisode 关系挂到播放器；一文件多集缺少明确 start/end 时不编造时间轴。

每段落盘后回读验证。获取完成只证明指定范围的当前弹幕池结构和缓存覆盖，
不证明完整历史、平台是否筛掉弹幕或身份语义正确。失败/取消回执列出已完成和缺失段。
整个正片范围验证后才给绑定赋已提交缓存并加载轨道。attach 自动记录当前本地视频时长，
fetch 也可明确传 `localDurationMs`。起点超出该时长的段失败时继续获取，其错误保留在
`outOfRangeFailures`；成功回执为 `status=localRangeComplete,localRangeComplete=true,
complete=false,partial=true`。与正片相交的段仍必须完整成功；未提供本地时长时仍要求
整个计划成功。失败来源保留可恢复缓存，不把空字段当成功。不同来源各自有 Job 和回执。

Task Engine 禁止提交副作用后进入 cancelled。MB 在取消前尚无提交时以 cancelled
结束；已有缓存/候选提交时停止调度，回读已提交部分，以 failed + verified receipt
结束，details.stopped=true、partial=true，并保留引擎的取消元信息。重启/暂停恢复
重新核对缓存和绑定，不依赖仅存在于内存的段计数。

## 对齐、显示与 GUI

原始 sourceTimeMs 永不累积改写。正 offsetMs 提前，负数延后；显示时间减去
offsetMs，GUI 秒数在宿主换成整数毫秒。`analyze_alignment` 只读当前绑定修订，
从最多 100 个手工锚点计算偏移的中位数（偶数个取上中位数），返回输入顺序的
偏移、绝对残差、最大残差、源时间跨度、证据、置信标签及限制。空锚点返回空数组和
null 估计；不修改绑定、不写候选、不创建任务或 Decision。至少三个锚点、源时间跨度
至少 60000 ms 且最大残差不超过 250 ms 时标记 consistentAnchors，否则为
insufficientEvidence。标签只表示锚点一致性，不证明集身份或语义对齐；首期只实现固定平移。

`update` 接受 1–100 个 changes，按输入顺序批量设置 enabled、offsetMs、displayFold。
每项指定 bindingId 或当前播放器 trackId，至少设置一个属性。绑定及有绑定的轨道
必须携带 expectedRevision；同一项的多属性和审计原子保存，修订只增加一次。
可采用估计，也可设置任何已有范围内的明确整数毫秒值（±7200000），无须 apply/keep。
返回每项 index、status 与 result/error；一个业务失败不回滚之前成功的项，后续项继续。
整个请求先做 schema 校验；结构/类型不合法时不执行任何项。reason 可选，记录到绑定
审计中；actor/origin 来自宿主 Invocation。未绑定轨道只修改当前播放状态，无持久绑定
revision；live timeline 不支持固定偏移。displayFold 只控制显示折叠，原始缓存不变。

旧 `set_enabled`、`set_dedup`、`offset` 保留原输入输出，分别转到同一属性更新实现。
`tracks` 同时提供 displayFold 与兼容字段 deduplicate。

### 旧对齐任务的恢复

- `align` 停止创建任务；已有 requestId/绑定/锚点组合仍返回原 jobId，新请求返回
  unavailable 并指明 `analyze_alignment` 与 `update` 的迁移入口。
- 已保存的 needs_decision 快照、选项和候选继续可读；`align_apply/align_keep` 只恢复
  这些存量选项，保持任务 revision、精确 ActionCall 和应用时的绑定 revision 检查。
  应用与审计仍原子写入，重启后已提交的 apply/keep 不会重复提交。
- 未选择的 queued/interrupted/恢复任务直接完成为分析回执，包含原 proposal、analysis、
  observedRevision 与 migration，不再产生 Decision，不改变偏移；已保存候选保留。
  暂停、取消及有 choice checkpoint 的任务继续按原引擎恢复与提交验证处理。
- 不迁移内核 JobState/Decision API，也不删除历史任务、候选和回执。

只使用播放器现有多轨注册表：Classic 与 Next 共用唯一的 `dandanplay` 轨道，
其余在线轨道使用 `next:<bindingId>`。每条来源轨道记录 origin、platform、
platformVideoId、文件路径或 bindingId。tracks 同时返回 Classic、本地和持久绑定；
同一平台/视频的 File 与 Episode 绑定也合为一条轨道，`bindingIds` 保留关联绑定 ID。
输入可以是 entityId、path 或 current，默认当前文件。缺少身份索引时只登记 File 与
FileLocation，不猜作品或剧集。同一平台/视频复用已有轨道，本地池存在时不重复在线获取；
弹弹play 复用会写入绑定，返回 `status=reused,jobId=null`。`refresh=true` 才获取并替换。
显式刷新使用独立的任务缓存，验证成功后才替换绑定的已提交缓存；失败不覆盖旧池。
自动加载策略仍由 Classic 设置决定，持久在线绑定在播放时从缓存恢复。
复用的弹弹play 绑定没有 Next 缓存时，可从现有 Classic 弹幕缓存恢复同一轨道，
不发网络请求、不重新触发识别或自动匹配。
装载校验播放路径与代次，接受合法空池；GUI 的轨道开关、偏移和删除通过宿主
调用相同 Harness Action，持久化成功后重建轨道。源专属映射抵消 Classic 全局
自动匹配偏移，只继续受用户全局手动偏移影响。

源内获取重复按来源条目 ID、原平台 ID 或有明确发送者的稳定指纹消重；匿名无 ID
条目不删除。跨轨显示只按可靠原身份折叠；未知 related 重叠对至少八个字符的
完全相同文本，在对齐后 100 ms 窗口内保守折叠。一个显示组最多接收同一轨道
的一条成员，保留成员与数量；可以用 set_dedup 关闭，原始缓存始终不变。
Classic 与 Next 的弹弹play 原始响应共用 `dandanplay_comments.dart` 解析；Classic
缓存和后续播放器解析保留 related 的平台、视频与原弹幕 ID。没有这些证据的旧缓存
仍按 unknown 处理，不猜平台。Classic 单独播放时仍走原合并逻辑。

## 播放时自动准备

Next 本地播放在打开视频前复用持久弹幕。遵循 `danmaku.autoLoadStrategy` 与
`danmaku.skipMatching`；既有弹弹play 绑定缺少正文时按原视频号补取，不重新猜匹配。
没有绑定的本地文件使用既有 `media.hash.match` 相同的头部 16 MiB MD5 与 hashOnly
提供方，只接受唯一剧集候选。无匹配、多匹配、显式解绑、手动绑定或网络失败均不自动
选择标题搜索结果。获取通过同一持久任务引擎执行；失败保留原记录，下一次播放可重试。
准备最多等待 12 秒，超时不阻断播放，已提交的获取任务可在后台完成并保存。

Mesh 在视频文件所在设备执行同一准备，再生成播放弹幕包。接收端不对临时串流地址
求哈希，不另存一份与源设备脱离的匹配。所有取得的正文长期保存；表名与 API 中的
`cache` 是历史兼容名称，不代表自动删除策略。

## Action 目录

输入/输出 schema 的唯一事实来源是 `capability.dart`。视频引用包括 sourceId、
videoId、objectType、title、durationMs；durationMs=0 可以出现在定位结果中，
获取前必须由调用者补充有依据的时长。fetch 的 requestId 用于幂等重试；align 的
requestId 只用于存量任务查找。

| Action | Effect | 结果 |
|---|---|---|
| sources / search / episodes / resolve / tracks | read | 瞬时声明/候选/目录/明确视频/全部轨道与覆盖；tracks 可登记缺失文件位置，不建绑定、任务或弹幕缓存 |
| fetch | write | 立即返回 jobId；获取并持久保存正文，不改播放轨道 |
| attach | write | 明确绑定及获取任务，或复用已有轨道；复用/已存在时 jobId=null，回执带 status/trackId |
| set_enabled / set_dedup / offset / detach | write | 绑定修订 CAS；绝对设置；解绑释放无引用的交入池，保留来源审计 |
| analyze_alignment | read | 估计、逐锚点偏移/残差、证据、置信与限制；无持久化或任务 |
| update | write | 批量绝对属性修改，逐项结果；绑定 CAS、轨道播放状态、显示折叠 |
| align / align_apply / align_keep | write | 仅存量任务查找/恢复；新任务迁移到只读分析加属性更新 |
| export | write | 授权媒体目录中的新 JSON 文件；raw 或 mapped，按 bytes/SHA-256 回读；不覆盖现有文件 |
| cache_delete | destructive | 删除明确 cacheKey；活动获取任务引用该缓存时返回 conflict，先停止任务 |
| cache_prune | write | 仅清理没有数据库引用的遗留内容文件；已保存弹幕全部持久保留，有活动获取任务则延后 |

上表各项带 `danmaku.` 前缀。export 的 mapped 指一条绑定映射后的源数据，不是
播放器经过过滤的最终显示列表，也不包含其他轨道。

## 离线验收

`test/next/danmaku_*_test.dart` 使用测试源码构造的 JSON、MockClient 和回环 HTTP 网关、
临时 SQLite 与内存播放器端口；没有真实平台录制、账号内容或线上请求。
播放器原生内核与真实浏览器取弹幕场景留给主控端到端验收。
`danmaku_ergonomics_test.dart` 验证分析无写入、估计后一次 update 设置不同值、批量
失败、轨道/绑定属性、空与矛盾证据、旧任务重启恢复和退役错误。覆盖率基线保留旧
actions，另增 primaryActions、compatibility（alias/legacyRecovery）和 behaviorScenarios；
验收同时检查旧入口 Effect、新入口 Effect 和能力映射。

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next lib/utils/danmaku_source_merge.dart test/next
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next test/danmaku_track_timing_test.dart test/danmaku_track_dialog_windowing_test.dart test/danmaku_track_overlay_entry_test.dart test/danmaku_track_popup_barrier_test.dart
git diff --check
```


## 视频旁的弹幕与播放取得的池

本地文件入索引（含扫描、下载登记和已有路径的重新索引）会通知单读者后台队列。队列和 Classic 共用 `localDanmakuCandidates` 的排名、八候选上限及解析入口；保存第一份可播放的 XML/JSON。应用启动和每 30 秒复核已索引本地位置：大小、修改时间与文件内容修订未变就不重读；改变就刷新原绑定；消失或解析失败保留上次读到的事实并标为不可用。文件恢复仍使用原绑定 ID，用户的开关和偏移保留。

`danmaku_bindings.local_file` 是本地路径引用，含声明的平台/视频号、条数、大小、修改与读取时间及无正文的时间计数。`cache_key=sidecar:<bindingId>` 表示路径池；不写 `danmaku_cache_chunks`。热度使用持久时间计数；主视觉与播放器按引用读取正文，最多四个池留在进程内。公开 `danmaku.bindings.localFile`、`danmaku.tracks`、`danmaku.tracks(entityId)` 和 `media.metadata.ui_facts.episodes.items[].danmaku` 提供同一绑定的覆盖事实，时间计数不进入公开查询。不可用轨道不会进入热度、主视觉候选或播放挂载；上次读取时间、条数和错误仍可查询。

Next 连接播放器后，同名自动加载进入这些绑定，不再调用 Classic 的第二次目录查找。`playback.tracks` 额外列出已有绑定的弹幕轨道，含 `bindingId`、来源与条数。Next 未连接时，Classic 沿用原先自动加载的策略与排名。Next 播放期间成功加载的弹弹play Classic 原始缓存也保存为 `automatic` 绑定，保留聚合池里显式的平台来源、复用当前播放器轨道；后续播放及界面能读取同一池。此路径不发出新的网络请求，也不代替 Classic 的自动匹配设置。
