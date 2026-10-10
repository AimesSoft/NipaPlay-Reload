# NipaPlay Next：多来源元数据识别与 Agent 刮削调研

调研日期：2026-10-10。本文依据当前工作树的静态代码、设计文档及外部服务官方文档；没有修改文件、运行迁移、执行测试或调用真实媒体识别接口。文中的“事实”指可由所列证据确认的行为；“建议”是架构提案；运行后果尚未验证的判断标为“风险推测”。外部配额与许可具有时效性，应以接入时的官方规则和应用授权为准。

## 1. 核心结论与设计边界

1. **现有识别以弹弹play 身份为中心。** 扫描结果将弹弹play `animeId`、`episodeId` 与文件路径、名称、观看进度写进 `WatchHistoryItem`；媒体库和播放器继续消费这些字段。Next 必须分离“媒体身份”“元数据”和“弹幕绑定”，同时保留旧字段的原有含义。证据：`lib/models/watch_history_model.dart:13`、`lib/services/concurrent_video_processor.dart:129`、`lib/app/unified_media_library_sections.dart:205`、`lib/utils/video_player_state/video_player_state_danmaku.dart:302`。

2. **现有“已匹配”不等于经过高置信度识别。** 文件名兜底会将首结果包装成 `isMatched: true`，扫描处理器再取 `matches[0]` 写入历史。不能直接把旧 `isMatched` 或非空 ID 当作 Next 的自动绑定依据。证据：`lib/services/dandanplay_service_io.dart:1431`、`lib/services/dandanplay_service_io.dart:1521`、`lib/services/concurrent_video_processor.dart:129`。

3. **Bangumi 同步存在身份 ID 与集数序号混用。** 当前代码把弹弹play `episodeId` 与 Bangumi `sort` 比较，而且将小数 `sort` 截断为整数。这应先修正，再扩展多来源同步。证据：`lib/services/bangumi_sync_service.dart:399`；弹弹play `episodeId` 的含义见[官方接口说明][ddp-open]，Bangumi `sort` 的含义见[官方 OpenAPI][bgm-api]。

4. **拟统一数据库已有跨来源身份基础，但不满足完整目标。** 它可以让同一共通剧集分别关联一个弹弹play ID、一个 Bangumi ID，并让多个文件资产指向该剧集；不能直接承载同一来源多个身份、一个文件包含多集、季与 cour 的范围映射、候选及绑定证据。证据：`assets/sql/create_dandanplay_episode_table.sql:3`、`assets/sql/create_bangumi_episode_table.sql:3`、`assets/sql/create_asset_episode_table.sql:3`。

5. **建议首期将身份扩展放在 `next.db`，保留 `watch_history.db` 作为 Classic 的兼容存储。** M2 已明确任务、事件、回执、Decision 保存于 `<AppStorage>/next/next.db`。身份表也放入该库是本文建议，可以使候选、绑定与任务事件在同一事务中提交；向 Classic 的投影采用可恢复交付。证据与依据：`docs/next/M2_TASKBOOK.md:67`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:510`。

本文遵循 `DESIGN.md` 的 Agent 刮削目标，以及 M2 的 Job 契约。此前长任务调研中的 `jobs.db` 路径属于草案，本文以 M2 的 `next.db` 为准；`verifying` 使用为 `phase`，不增加 M2 未列出的 Job state。证据：`docs/next/DESIGN.md:408`、`docs/next/M2_TASKBOOK.md:30`、`docs/next/M2_TASKBOOK.md:37`、`docs/next/M2_TASKBOOK.md:67`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:483`。

## 2. 现有识别流水线

### 2.1 本地与远程文件：哈希、文件名、缓存、入库

| 阶段 | 核实到的行为 | 证据 |
|---|---|---|
| 访问入口 | `DanmakuMatchingService` 封装访问检查、文件识别、作品搜索、剧集列表；远程稳定媒体 URI 可以转换成用于探测的 URL。 | `lib/services/danmaku_matching_service.dart:14`、`:44`、`:136` |
| 文件指纹 | 使用文件前 16 MiB 的 MD5；支持本地文件、HTTP 读取及 Android SAF 路径处理。这个哈希不是全文件内容哈希。 | `lib/services/dandanplay_service_io.dart:1123`、`:1535`；[官方哈希定义][ddp-open] |
| 服务端匹配 | POST `/api/v2/match`，输入 `fileName/fileHash/fileSize`，模式固定为 `hashAndFileName`。 | `lib/services/dandanplay_service_io.dart:625` |
| 匹配缓存 | SharedPreferences 保存按 `fileHash` 索引的视频识别结果。未匹配结果有过期和文件名兜底版本失效逻辑；成功结果的读取分支没有同样的 TTL 检查。 | `lib/services/dandanplay_service_io.dart:403`、`:444` |
| 服务端命中 | `isMatched == true` 时缓存结果，并取首个 match 预取弹幕；弹幕获取失败只记录日志，仍返回识别信息。 | `lib/services/dandanplay_service_io.dart:1216` |
| 文件名兜底 | 自动首结果匹配设置默认开启。依次搜索清理后的关键词，找到第一个非空结果列表后停止；无集数时取首作品的首个可解析正整数剧集。 | `lib/services/dandanplay_service_io.dart:1237`、`:1431`、`:1459` |
| 连续编号兜底 | 对搜索结果依次尝试集数；不命中时扣除该条目的最大正整数集号，再尝试后续条目。 | `lib/services/dandanplay_service_io.dart:1470` |
| 扫描写入 | `ConcurrentVideoProcessor` 对已匹配结果取 `matches[0]`，创建或更新 `WatchHistoryItem`，保留已有观看进度。未匹配、缺 ID、超时返回普通失败结果。 | `lib/services/concurrent_video_processor.dart:119`、`:162`、`:224`、`:232` |
| 远程刮削 | 本地媒体管理 API 对远程资源区分稳定路径与 probe URL，识别后仍写入观看历史。管理页另有远程扫描/匹配实现。 | `lib/services/local_media_management_api.dart:519`；`docs/next/research/LONG_RUNNING_OPERATIONS.md:62` |

需要区分两类缓存：

- 扫描差异缓存用于判断哪些路径需要重新处理；Rust 扫描使用大小与修改时间形成变化指纹。
- 弹弹play 识别缓存用于复用 `fileHash → match`。

**风险推测：** 大小与修改时间未变化但内容变化，可能绕过差异扫描；前 16 MiB 相同的不同文件，可能复用同一识别缓存。二者都不能替代完整文件身份验证。证据：`lib/services/scan_service.dart:664`、`rust/src/api/file_scan.rs:190`、`lib/services/dandanplay_service_io.dart:403`。

当前客户端对官方弹弹play 服务实施“登录后才可匹配”的产品策略，自定义服务不必遵循该策略；官方文档则将文件识别、搜索、获取弹幕列为无需用户登录的公开接口。应用凭证与用户 JWT 是不同层级，Next 适配器必须分别处理。证据：`lib/services/dandanplay_service_io.dart:76`、`:89`；[弹弹play 接入与权限说明][ddp-open]。

### 2.2 手动匹配

手动服务负责搜索作品、读取剧集和显示依赖 `BuildContext` 的选择界面，结果由调用方应用。媒体库管理页收到选择后，更新弹弹play ID、名称和剧集标题，保留已有进度，再刷新 Provider；播放器手动选择路径会先更新历史，然后加载所选弹幕。证据：`lib/services/manual_danmaku_matcher.dart:27`、`:45`、`lib/themes/nipaplay/widgets/library_management_tab.dart:4647`、`:4665`、`:4686`、`lib/utils/video_player_state/video_player_state_metadata.dart:411`、`:447`。

由此可得：

- **事实：** 当前“需要选择”的流程主要由 UI 调用栈承载，服务本身没有返回持久 Decision。证据：`lib/services/manual_danmaku_matcher.dart:45`。
- **建议：** 拆成不依赖 UI 的候选查询与绑定服务，Classic 对话框、Agent 和 Next 决策界面共享它们。依据：`docs/next/DESIGN.md:29`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:141`。
- **风险推测：** 当前不同调用方分别更新历史，迁移时如果只替换某个入口，会继续产生缺少来源、绑定者或绑定版本的记录。依据：上述媒体库与播放器的独立写入路径。

### 2.3 Emby/Jellyfin：服务器身份映射到弹弹play

现有匹配器先构造服务器媒体历史，计算视频哈希并匹配弹弹play；失败后使用剧名或集标题搜索，可进入 UI，也可按自动首结果设置选择。最终仍生成带弹弹play ID 的 `WatchHistoryItem`，并保存服务器映射。证据：`lib/services/emby_dandanplay_matcher.dart:149`、`:301`、`:371`、`:402`；`lib/services/jellyfin_dandanplay_matcher.dart:292`、`:360`、`:393`。

两者的兜底行为不同：

| 路径 | 行为与脆弱点 | 证据 |
|---|---|---|
| Emby 剧集选择 | 按服务器 `indexNumber` 匹配；找不到或缺少集号时可取弹弹play 第一集。 | `lib/services/emby_dandanplay_matcher.dart:569` |
| Jellyfin 剧集选择 | 按 `episodeIndex`、标题包含关系匹配；仍失败时可能取末集、数组下标或首集；异常时也回退首集。 | `lib/services/jellyfin_dandanplay_matcher.dart:510` |
| 映射持久化 | 在 `watch_history.db` 中动态创建作品/季映射及 episode 映射表，包含 `confirmed`。 | `lib/services/emby_episode_mapping_service.dart:33`、`lib/services/jellyfin_episode_mapping_service.dart:33` |
| 未确认预测 | 映射服务提供 `参考弹弹play episodeId + 服务器集号差值` 的预测，并保存为 `confirmed: false`；直接映射读取没有以 `confirmed` 为过滤条件。 | `lib/services/emby_episode_mapping_service.dart:260`、`:285`；`lib/services/jellyfin_episode_mapping_service.dart:253`、`:271` |
| 已确认标记 | 自动匹配也会进入统一保存函数，写 `confirmed: true`，所以这个标记不能证明绑定者是用户。 | `lib/services/emby_dandanplay_matcher.dart:149`、`:1034`；`lib/services/jellyfin_dandanplay_matcher.dart:1108` |
| 外部 Provider ID | 部分服务器请求已经要求返回 `ProviderIds`，但当前 `EmbyEpisodeInfo/JellyfinEpisodeInfo` 没有保留该字段，也未形成该字段到多来源身份的识别链路。 | `lib/services/emby_service.dart:770`、`lib/services/jellyfin_service.dart:1782`；`lib/models/emby_model.dart:230`、`lib/models/jellyfin_model.dart:256` |
| 服务器作用域 | 映射表的服务器 episode ID 未附服务器安装/连接身份；媒体 identity resolver 对这两类来源使用 `sourceId: 'default'`。 | `lib/services/emby_episode_mapping_service.dart:52`、`lib/services/jellyfin_episode_mapping_service.dart:52`；`lib/utils/media_identity_resolver.dart:42` |

**风险推测：** 搜索首结果、数组位置和 ID 算术会把季集编排差异扩散为稳定映射；切换服务器时，相同 item ID 也可能落入相同身份作用域。官方弹弹play 契约只定义 episodeId 为弹幕库标识，没有定义“相邻整数代表相邻剧集”。依据：上述映射代码及[弹弹play 身份定义][ddp-open]。

**建议：** 服务器 ProviderIds 应作为候选证据保留，并验证对应来源、作品范围和编排顺序；未验证的 ID 算术预测降级为候选，不能直接成为接受绑定。依据：[TMDB 外部 ID 查询][tmdb-find]、[TVDB API][tvdb-api]及上述现有缺口。

### 2.4 Bangumi 同步中的 subject 与 episode 映射

这里必须区分三个模块：

- `BangumiApiService` 面向 `bgm.tv`。
- `BangumiService` 中的 `/api/v2/bangumi/...` 是弹弹play 番剧接口。
- `AnimeInfoService` 有弹弹play 与 Bangumi 的关系管理实现，但没有接入当前生产启动链路。

证据：`lib/services/bangumi_sync_service.dart:187`、`lib/services/bangumi_service.dart:245`、`:457`、`lib/services/anime_info/anime_info_service_impl.dart:298`；本次 `lib/` 搜索未发现 `DatabaseService.initialize` 调用，见 `docs/next/research/LONG_RUNNING_OPERATIONS.md:481`。

当前同步存在以下问题：

1. **subject 映射只使用标题搜索首结果。** `_findBangumiSubjectId` 虽接收弹弹play animeId，实际以名称搜索动画类型、limit 10，再取第一项；该路径没有将双方 subject 身份持久绑定。证据：`lib/services/bangumi_sync_service.dart:182`。

2. **episode 同步把 ID 当序号。** 本地 `WatchHistoryItem.episodeId` 是弹弹play ID，代码却比较它与 Bangumi `sort`，并截断小数。证据：`lib/services/bangumi_sync_service.dart:399`、`lib/services/concurrent_video_processor.dart:133`；[Bangumi episode schema][bgm-api]。

3. **只读取正篇。** 当前请求固定 `type: 0`，因此该同步路径没有覆盖特别篇、OP、ED 等类型。证据：`lib/services/bangumi_sync_service.dart:343`；[Bangumi EpType][bgm-api]。

4. **完成状态依据本地记录。** 完结判定检查本地有效历史是否均达到观看阈值；同步记账还包含作品级 `anime_$animeId` 标记。**风险推测：** 文件不全、多版本重复记录或后续新增集数，可能使作品完成状态或再次同步范围不准确。证据：`lib/services/bangumi_sync_service.dart:136`、`:560`。

5. **统一库里的另一套关系算法也需要升级。** `AnimeInfoService` 已有弹弹play↔Bangumi 作品查询，并按 `episodeNumber` 与 `sort` 数值建立剧集关系；解析使用 `Map<double, int>`，同 sort 只保留第一项，没有同时用 episode type 区分。**风险推测：** 正篇与 SP 使用相同 sort 时会压掉候选。证据：`lib/services/anime_info/anime_info_service_impl.dart:298`、`:432`、`lib/services/anime_info/util.dart:192`。

### 2.5 季、cour、OVA、合集、多版本及多语言的具体薄弱点

| 情况 | 核实到的薄弱点 | 后果判断 |
|---|---|---|
| `S02E03` | 集号解析只提取 E；关键词提取会删除 S/E 标识。证据：`lib/services/dandanplay_service_io.dart:1328`、`lib/utils/media_filename_parser.dart:50`。 | **风险推测：** 失去季信息后可能搜索到第一季或同名条目。 |
| cour、跨季连续编号 | 兜底按搜索列表顺序扣减最大集号，没有先确认这些条目属于同一作品、正确先后关系和连续编号体系。证据：`lib/services/dandanplay_service_io.dart:1470`。 | **风险推测：** 搜索排序或无关同名条目会改变绑定结果。 |
| OVA、特别篇、小数集 | 自动集号函数返回正整数，候选列表也过滤为正整数集号；Bangumi 同步只取正篇并截断 sort。证据：`lib/services/dandanplay_service_io.dart:1324`、`:1463`、`lib/services/bangumi_sync_service.dart:353`、`:406`。 | 缺少独立类型与原始编号的识别模型，不能保证正确覆盖。 |
| 合集、双集文件 | 自动匹配结果单选；统一库 `asset_episode` 的资产哈希是主键，一个资产只指向一个 episode。证据：`lib/services/concurrent_video_processor.dart:132`、`assets/sql/create_asset_episode_table.sql:3`。 | 无法表达一文件含多集及分段时间关系。 |
| 长番 | 文件名集号解析只接受 1–300。证据：`lib/services/dandanplay_service_io.dart:1340`、`:1361`。 | 超出范围的集号不能通过该函数正确返回。 |
| 字幕组、压制版、修订版 | 关键词清理移除标签，没有输出完整版本结构；成功匹配缓存只按头部哈希查找。证据：`lib/utils/media_filename_parser.dart:44`、`:130`、`lib/services/dandanplay_service_io.dart:403`。 | **风险推测：** 丢失识别版本或弹幕时间轴所需的线索。 |
| 多个可播放版本 | 已有支持：仅清除匹配的旧记录可作为进度迁移来源，仍有效的记录被视为另一版本；M1 播放选择已有 Decision。证据：`lib/services/concurrent_video_processor.dart:145`、`docs/next/DESIGN.md:379`。 | 问题是缺少版本语义、证据与时间轴关系，不能笼统称为“不支持多版本”。 |
| 中英日名称、别名 | 有分隔符、技术词和数字“第 X 话”等清理，但主要输出搜索关键词，没有建立跨语言标题身份或保留各语言别名来源。证据：`lib/utils/media_filename_parser.dart:27`、`:68`、`:95`。 | **风险推测：** 罗马字、译名、简称和标题中的数字仍会造成歧义；解析成功也不证明作品识别成功。 |

## 3. 识别结果存储及现有依赖面

### 3.1 存储并非单一位置

| 存储 | 内容 | 证据 |
|---|---|---|
| `watch_history.db` | 路径、media key、名称、弹弹play anime/episode ID、进度、位置、时长、观看时间、缩略图、扫描标记。 | `lib/models/watch_history_database.dart:48`、`:112` |
| WatchHistory JSON/Web 存储 | `WatchHistoryItem` 的 JSON 序列化还包含 `videoHash`；Web 使用 SharedPreferences 存储实现。 | `lib/models/watch_history_model.dart:49`、`lib/models/watch_history_database.dart:429` |
| SharedPreferences 视频识别缓存 | `fileHash → videoInfo`，包括服务结果或文件名兜底结果。 | `lib/services/dandanplay_service_io.dart:403`、`:444` |
| Emby/Jellyfin 映射表 | 服务器作品/季到弹弹play作品，以及服务器 episode 到弹弹play episode；与历史共用数据库。 | `lib/services/emby_episode_mapping_service.dart:33`、`lib/services/jellyfin_episode_mapping_service.dart:33` |
| Bangumi 同步记账 | 已同步对象等偏好记录；不等于持久 subject/episode 身份映射。 | `lib/services/bangumi_sync_service.dart:102`、`:182`、`:560` |

**重要事实：SQLite 历史没有保存 `videoHash`。** 模型和 JSON 有此字段，但当前 SQL schema、插入映射、数据库反序列化都没有它。不能假定 SQLite 历史重启后仍可提供原识别哈希。证据：`lib/models/watch_history_model.dart:25`、`:62`；`lib/models/watch_history_database.dart:112`、`:429`、`:1238`。

**重要事实：清除可见匹配可能保留旧 ID。** `withoutMatchInfo()` 清空名称和剧集标题，但保留 animeId、episodeId 及进度，用于后续进度恢复。Next 导入不能把所有非空 ID 直接标为接受绑定。证据：`lib/models/watch_history_model.dart:119`。

### 3.2 功能依赖

| 功能 | 依赖方式 | 证据 |
|---|---|---|
| 弹幕读取 | 玩家使用弹弹play episodeId 读取缓存或请求弹幕；服务调用 `/comment/{episodeId}`。 | `lib/utils/video_player_state/video_player_state_danmaku.dart:302`、`:433`；`lib/services/dandanplay_service_io.dart:1671` |
| 播放进度与续播 | 按文件历史保存位置、时长、进度；播放器识别更新复用原记录。 | `lib/models/watch_history_model.dart:13`、`lib/utils/video_player_state/video_player_state_metadata.dart:478`、`:568` |
| 下一集 | 历史数据库的相关查找使用 episodeId 大小排序。 | `lib/models/watch_history_database.dart:1054`、`:1085`、`:1119` |
| 本地/WebDAV/SMB 媒体库 | 要求 animeId 非空、名称非空，并按 animeId 归组。 | `lib/app/unified_media_library_sections.dart:205`、`:238` |
| Next M1 媒体库能力 | 当前能力读取观看历史，按 animeId/episodeId 组织作品、剧集和文件。 | `lib/next/capabilities/library_capability.dart:11`、`:105`、`:129` |
| 弹弹play 播放历史 | 使用 episodeIdList 上报节目。 | `lib/services/dandanplay_service_io.dart:1069` |
| Bangumi 同步 | 从弹弹play 身份历史寻找 subject 并同步观看状态。 | `lib/services/bangumi_sync_service.dart:182`、`:399` |
| Provider 与 UI 刷新 | Provider 直接持有历史数据库，更新后刷新；扫描完成也触发刷新。 | `lib/providers/watch_history_provider.dart:23`、`:72`、`:417` |
| 备份、恢复、自动同步 | 现有备份及同步服务读取、合并或写入历史数据库。 | `lib/services/backup_service.dart:30`、`:362`；`lib/services/full_backup_service.dart:929`、`:991`；`lib/services/auto_sync_service.dart:975`、`:1006` |

**建议：** 新身份模型中显式保存播放顺序，不把任何外部 episode ID 的整数大小当作通用顺序。依据：现有下一集实现，以及 Bangumi、TMDB、TVDB 各自独立的剧集结构，[Bangumi schema][bgm-api]、[TMDB 季接口][tmdb-season]、[TVDB API][tvdb-api]。

## 4. 未接入的统一数据库 `nipaplay.db`

### 4.1 当前状态

本文沿用“`nipaplay.db`”称呼拟统一媒体库。代码实际通过 `DatabaseService.initialize(String dbFilePath)` 接收路径，没有在服务中固定这个文件名。本次搜索发现初始化调用位于测试，未发现 `lib/` 生产初始化接线，因此不能把它视作已启用的媒体库。证据：`lib/services/database/database_service.dart:22`、`test/database/database_test.dart:27`、`test/database/file_to_db_test.dart:64`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:481`。

该服务使用 SQLite FFI、SQL assets、schema version 3、外键与事务；已有数据库类型检查，防止误将旧观看历史库当统一库升级。共通身份合并已有事务、重定向和冲突回滚保护，不能断言当前合并必然丢数据。证据：`lib/services/database/database_service.dart:24`、`:31`、`:44`；`lib/services/database/database_anime_episode_repository.dart:49`、`:76`、`:92`。

### 4.2 schema 能承载什么

| 表/结构 | 能力与限制 | 证据 |
|---|---|---|
| `anime`、`episode` | 共通作品与剧集 ID；episode 属于 anime；有 `merged_into`。没有季、cour、类型或顺序字段。 | `assets/sql/create_anime_table.sql:3`、`assets/sql/create_episode_table.sql:3` |
| 两来源 anime 表 | 每个外部 ID 指向一个 common anime；common anime 列有 UNIQUE，故同一 common anime 在每种来源至多挂一个作品 ID。 | `assets/sql/create_dandanplay_anime_table.sql:3`、`assets/sql/create_bangumi_anime_table.sql:3` |
| 两来源 episode 表 | 同理，一个 common episode 可以分别挂一个弹弹play ID、一个 Bangumi ID，但同一来源不能挂多个 episode ID。 | `assets/sql/create_dandanplay_episode_table.sql:3`、`assets/sql/create_bangumi_episode_table.sql:3` |
| `asset` | 前 16 MiB MD5 是资产主键；包含大小、codec、可选 SHA-256。 | `assets/sql/create_asset_table.sql:3` |
| `asset_episode` | 多个资产可以指向同一 episode；一个资产只能指向一个 episode。 | `assets/sql/create_asset_episode_table.sql:3` |
| `path_asset`、`net_asset` | 路径或 URL 指向资产；路径使用 source、地址、名称、扩展名复合键。 | `assets/sql/create_path_asset_table.sql:3`、`assets/sql/create_net_asset_table.sql:3` |
| 来源枚举与仓储 | 支持 common、dandanplay、bangumi；新增来源需要改枚举和 schema 路由。 | `lib/models/database/anime_episode_relation.dart:16`、`lib/services/database/database_repository_support.dart:10` |
| 元数据 JSON | 作品、剧集、来源缓存、弹幕缓存及视频信息还存于库外 JSON 文件。 | `lib/services/anime_info/util.dart:134`、`:150` |

因此，对“一个文件或剧集挂多个外部 ID”的回答是：**可以支持有限的跨来源一对一关系；不能直接支持任意多来源、多范围、多编排关系。** 一个文件可经 common episode 间接拥有弹弹play和 Bangumi ID，但不是通用的身份绑定图。依据：上述 SQL 的主键与 UNIQUE 约束。

### 4.3 缺少的结构

以下为**建议补充项**，由现有 schema 与外部结构差异推导：

| 缺项 | 为什么需要 |
|---|---|
| 通用外部对象命名空间 | 用 `provider + objectType + externalId(TEXT)` 区分作品、季、剧集、电影及字符串 ID；来源不能继续写死在两套表中。依据：`lib/services/database/database_repository_support.dart:10`；[弹弹play 当前 schema][ddp-schema]、[TMDB 外部 ID][tmdb-find]。 |
| 范围与编排映射 | 保存 season、release/cour、episode type、原始集号、order 和覆盖范围；多个 Bangumi subject 不应强行合并成一个 exact alias。依据：现有 UNIQUE 约束；[Bangumi schema][bgm-api]、[Anime-Lists 映射格式][anime-lists]。 |
| 文件—剧集多对多 | 表达合集、双集和分段；保留顺序与可选时间范围。依据：`assets/sql/create_asset_episode_table.sql:3`；[Anime-Lists 拆分/合并映射][anime-lists]。 |
| 候选、证据与绑定生命周期 | 保存候选、置信度、规则版本、来源、绑定者、接受/撤销状态、Decision 引用和修订号。依据：`docs/next/DESIGN.md:409`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:571`。 |
| 独立弹幕绑定 | 文件版本、episodeId、偏移和时间轴兼容性不等于作品元数据身份。依据：`lib/services/dandanplay_service_io.dart:1513`；[弹弹play match schema][ddp-schema]。 |
| 文件身份与内容版本 | 不把头部 MD5 当唯一文件实体键；分别保存稳定 location、内容修订和多种指纹。依据：`assets/sql/create_asset_table.sql:3`、`rust/src/api/file_scan.rs:190`。 |
| 观看与兼容投影 | 现有统一 schema 没有承接 `WatchHistoryItem` 的整套进度与 Classic 查询语义。依据：`lib/services/database/sql.dart:9`、`lib/models/watch_history_model.dart:13`。 |
| SQL/JSON 一致性协议 | SQL 事务不能自动原子提交库外 JSON；需要产物校验、版本引用或可恢复写入。依据：`lib/services/anime_info/util.dart:134`、`lib/services/database/database_service.dart:106`。 |

### 4.4 启用代价与风险

**启用为旁路身份库**需要启动初始化、路径管理、升级策略、多平台 SQLite 验证、备份边界和仓储适配；**替换 `watch_history.db`**还需要迁移播放器、媒体库、Provider、服务器映射、备份恢复和同步。两者工作量不能混为一谈。依据：`lib/services/database/database_service.dart:22`及第 3 节依赖面。

主要风险：

- **平台风险，待验证：** 统一服务直接使用 FFI，SQL 使用 STRICT 表；现有历史则按平台选择实现，Web另有存储。不能仅依据桌面测试认定所有目标平台可用。证据：`lib/services/database/database_service.dart:24`、`assets/sql/create_asset_episode_table.sql:9`、`lib/models/watch_history_database.dart:101`、`:429`。
- **身份语义风险：** 旧 animeId/episodeId 是弹弹play ID，新 common ID 不能原样替换它们。证据：`lib/services/concurrent_video_processor.dart:133`、`lib/services/database/database_service.dart:94`。
- **数据完整性风险，推测：** 缺失 SQLite videoHash、清除后残留 ID、自动也标 confirmed，会使导入时错误赋予“已验证”“用户确认”属性。证据：`lib/models/watch_history_database.dart:112`、`lib/models/watch_history_model.dart:119`、`lib/services/emby_dandanplay_matcher.dart:1034`。
- **恢复风险：** 统一 SQL、JSON、任务库和历史库分属不同提交边界，不能假设一次事务全部完成。依据：`lib/services/anime_info/util.dart:134`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:515`。

## 5. 外部元数据来源对比

### 5.1 搜索、结构、图片与标题

| 来源 | 搜索与适用范围 | 季集结构 | 图片、多语言标题 | 官方证据 |
|---|---|---|---|---|
| TMDB | 搜索后读取详情；分别建模电影和 TV。 | TV series→season→episode；另有 Episode Groups。 | language 本地化；图片以 configuration、尺寸和 file path 构造 URL。 | [查询流程][tmdb-search]、[季详情][tmdb-season]、[Episode Groups][tmdb-groups]、[语言][tmdb-language]、[图片][tmdb-images] |
| Bangumi | subject 搜索可按类型、日期、标签等筛选；动画 type 2，真人类 type 6。新搜索接口标为实验性。 | subject 下有 episodes 和相关 subject；episode 有独立 ID、type、数值 sort/ep。没有统一的 TV season 层级。 | name、name_cn、infobox；images 提供不同尺寸。不能保证每个条目都有完整中英日标题。 | [官方 OpenAPI][bgm-api] |
| AniList | GraphQL Media 搜索及按 ID 查询，面向动画/漫画。 | Media 有 format、关系、总集数和放送信息；`season` 是首播季度，不是电视剧 S1/S2。不提供与 TMDB/Bangumi 同等的通用逐集身份目录。 | romaji、english、native、synonyms；coverImage、bannerImage。 | [Media 查询][anilist-query]、[Media schema][anilist-media] |
| TVDB | 标题搜索、别名/翻译搜索、remote ID 查询。 | series、season、episode；支持不同 season type/编排顺序，不能默认所有列表是同一顺序。 | 翻译记录、artworks 与 episode 图片。 | [官方 API][tvdb-api]、[官方说明][tvdb-readme] |
| 弹弹play | 文件匹配、作品和剧集搜索，直接获得弹幕库身份。 | 传统番剧按季度分别建条目；当前 schema 部分来源另有 seasons。 | 海报；当前详情有 language/title 列表。 | [接口说明][ddp-open]、[当前 schema][ddp-schema] |

补充两项直接影响适配器的事实：

- Bangumi `sort` 是同类排序与集数，`ep` 对非正篇没有同样含义；类型包括正篇、SP、OP、ED、PV、MAD、其他。因此排序键至少需要来源、subject、type 和原始编号。证据：[Bangumi Episode/EpType][bgm-api]。
- 弹弹play 当前 `bangumiId` 可为字符串，`episodeNumber` 也是可能含字母的字符串；旧代码的正整数解析不能作为完整源模型。证据：[弹弹play 当前 schema][ddp-schema]、`lib/services/dandanplay_service_io.dart:1463`。

### 5.2 外部 ID 映射能力

| 来源/机制 | 已核实能力 | 边界 |
|---|---|---|
| TMDB `external_ids` | TV series 提供 IMDb、TVDB、Wikidata 等外部 ID。 | 官方列表没有 Bangumi 或 AniList；series 外部 ID不能自动证明逐集对应。[官方接口][tmdb-external] |
| TMDB `find` | 支持按外部 ID 找对象；TVDB/Wikidata 可涉及 TV season、episode，IMDb也支持 episode。 | 必须带正确 external source，并检查返回对象层级。[官方接口][tmdb-find] |
| Bangumi | subject关系可辅助识别前后篇、续作等；schema没有统一的 TMDB/AniList ID字段。 | infobox/网页链接不能直接当规范、完整的映射目录。[官方 schema][bgm-api] |
| AniList | Media 有 `idMal`、relations、externalLinks。 | externalLinks 不是完整跨数据库映射保证；没有通用逐集外部 ID表。[官方 schema][anilist-media] |
| TVDB | `remoteIds`、remote ID搜索，以及动态来源类型接口。 | 需要检查来源类型、对象类型和编排方式，不宜硬编码所有 source ID。[官方 API][tvdb-api] |
| 弹弹play↔Bangumi | `/api/v2/bangumi/bgmtv/{bgmtvSubjectId}`；项目已有正反向查询实现。 | 官方明确映射由人工维护，可能错误、缺失或变更。[官方 schema][ddp-schema]；`lib/services/anime_info/anime_info_service_impl.dart:298` |
| Anime-Lists | 社区数据将 AniDB 关联至 TVDB、TMDB、IMDb，支持 season、offset、范围及显式逐集拆分/合并。 | 不是服务商官方映射，不能假定完整或始终正确。[项目格式说明][anime-lists] |
| Fribb anime-lists | 汇合 anime-offline-database 与 Anime-Lists，经 AniDB ID 合并，并补充部分映射；覆盖 AniList/MAL/AniDB/TVDB/TMDB 等。 | 派生结果与上游不是独立证据；不能假定含 Bangumi/弹弹play。复杂逐集映射应查原始数据。[项目说明][fribb] |

**建议：** 社区映射作为候选证据导入，记录仓库、commit、条目键、校验摘要和上游链路；应用时保留 TV/movie 命名空间、季和范围。不能将“两个派生数据集一致”计为两次独立佐证。依据：[Anime-Lists 格式][anime-lists]、[Fribb 生成过程][fribb]。

### 5.3 认证、配额与使用限制

| 来源 | 认证 | 配额与限制 |
|---|---|---|
| TMDB | 应用 API key 或 API Read Access Token Bearer；Bearer 可用于 v3/v4。 | 旧 40次/10秒限制已取消；官方仍描述约 40次/秒的可变保护上限，需处理429。非商业使用有署名要求，商用需授权。[认证][tmdb-auth]、[限流][tmdb-rate]、[许可FAQ][tmdb-faq] |
| Bangumi | 公共读取与用户数据权限分别处理；用户授权采用OAuth/Bearer。客户端应提供带应用、开发者及版本信息的User-Agent。 | 本次未核实统一数字配额，不写固定QPS；按接口权限、错误响应和缓存策略实施。新搜索API可能变化。[授权][bgm-auth]、[User-Agent规则][bgm-ua]、[OpenAPI][bgm-api] |
| AniList | 公共数据读取无需用户OAuth；私有数据和写入需用户授权。 | 文档标称90次/分钟，同时提示当前降级为30次/分钟；还有突发限流，使用响应header和Retry-After。禁止大规模囤积及特定非互补服务，商用存在许可条件。[授权][anilist-auth]、[限流][anilist-rate]、[使用条款][anilist-terms] |
| TVDB | `/login` 提交apikey；用户支持型key还需订阅PIN，返回有效期一个月的Bearer token。 | 提供商业协商授权和用户订阅两种模式；本次未核实统一数字QPS，不应称无限调用。费用与许可可能变化。[API认证][tvdb-api]、[授权模式][tvdb-readme] |
| 弹弹play | 应用凭证：签名header或AppSecret模式；公开匹配不要求用户JWT，用户数据接口另需JWT及权限。 | 文档保留“不限制频率”的表述，同时注明2026-06-25启用应用分层额度管理；还有异常调用检测，禁止规模抓库、批量下载弹幕及未经授权商用。[官方说明][ddp-open] |

**建议：** Provider 端口分别实现限流、按需缓存、429重试和认证错误分类，不设置一个跨来源通用并发值；401/403、额度不足、没有匹配和暂时网络失败也不能合并成“无法识别”。依据：上述官方认证及限流规则、`docs/next/M2_TASKBOOK.md:41`。

### 5.4 TMDB 与 Bangumi 的季/cour 错位

**核实到的结构差异：** TMDB 使用 series/season/episode 和 Episode Groups；Bangumi 使用 subject/episode、related subjects，没有等价的 TV season 编号契约。社区 Anime-Lists 明确使用季、区间偏移与显式逐集映射解决跨数据库编排差异。因此“标题相同、集数相同”不足以证明整条目同一范围。证据：[TMDB 季][tmdb-season]、[Episode Groups][tmdb-groups]、[Bangumi schema][bgm-api]、[Anime-Lists][anime-lists]。

以下是**假设示例，不对应已核验的具体作品**：

| 数据库 | 假设结构 |
|---|---|
| TMDB | 作品 T 的 S1 共24集 |
| Bangumi | subject A 对应前12集，subject B 对应后12集，B从1重新编号 |
| 发布文件 | 使用1–24连续编号 |
| 正确关系 | A1–12→T/S1/E1–12；B1–12→T/S1/E13–24 |

**建议的处理方式：**

1. 先验证作品和发布范围，再选择 aired、absolute、DVD或其他来源顺序；文件名中的 season 与“首播季度”分别保存。依据：[AniList Media][anilist-media]、[TVDB API][tvdb-api]。
2. 映射显式保存 `subject → season/range` 和逐集 ID；offset 只在已验证的连续区间内生效。依据：[Anime-Lists 映射格式][anime-lists]。
3. OVA、总集篇和特别篇单独建 release/episode 类型关系，不能只靠减去前一季集数。依据：[Bangumi 类型][bgm-api]、`lib/services/dandanplay_service_io.dart:1470`。
4. 拆集或合集使用关系表，不能强行转成一对一身份；需要播放时间段或弹幕偏移时，再单独验证。依据：[Anime-Lists 拆分/合并][anime-lists]、[弹弹play偏移字段][ddp-schema]。
5. 社区映射、来源内关系与发布日期可提供证据；发生冲突、范围缺失或编号体系不明时生成 Decision。依据：`docs/next/DESIGN.md:409`。

## 6. 多来源身份模型提案

本节全部为**建议**。核心依据是 Agent 刮削要求、当前 schema 限制及外部来源的对象层级差异。证据：`docs/next/DESIGN.md:409`、`assets/sql/create_asset_episode_table.sql:3`、`assets/sql/create_bangumi_anime_table.sql:3`及第5节官方资料。

### 6.1 实体层级

```text
文件位置 FileLocation → 文件内容版本 File
                              │ 多对多、可含时间段
                              ▼
                           Episode
                              │
                              ▼
                    Release / EpisodeOrder
                              │
                              ▼
                            Work
```

`Release` 表达实际发布范围，例如某一季、某个 cour、OVA组或电影；`EpisodeOrder` 表达来源/用户选择的编排。它们是内部模型，不宣称所有来源都有对应实体。依据：[TMDB季][tmdb-season]、[Bangumi subject][bgm-api]、[TVDB编排][tvdb-api]。

| 实体 | 建议字段与语义 |
|---|---|
| `Work` | 本地稳定ID、作品类别；可代表系列或独立作品。系列与续作关系显式保存，避免同一IP全部合并。 |
| `Release` | workId、发布类型、日期范围、显示季名/cour名；编号可以未知，不以外部S编号作本地主键。 |
| `Episode` | 本地ID、归属、类型、标题和时长；外部集号另存，不让它决定身份。 |
| `EpisodeOrder` | provider/orderKind、release、原始编号、排序键；支持小数和字母编号。 |
| `File` | 本地稳定ID、内容修订、size、头部MD5、可选完整哈希、探测信息、版本标签。 |
| `FileLocation` | source/connection/ownerDevice、稳定路径或服务器itemId、可达状态；签名URL只用于访问。 |
| `FileEpisode` | fileId、episodeId、关系类型、顺序、可选start/end；表达一文件多集和一集多文件。 |

文件层可挂 Emby/Jellyfin item ID 等来源对象；剧集层挂 Bangumi episode、TMDB episode、TVDB episode、弹弹play episode；作品或 release 层挂对应范围的作品对象。不能为了“每层多个ID”把作品ID误挂成文件ID。依据：`lib/utils/media_identity_resolver.dart:42`、[TMDB对象查询][tmdb-find]、[Bangumi schema][bgm-api]。

### 6.2 外部对象与绑定分开保存

建议至少区分：

- `external_objects`：唯一键为 provider、objectType、externalId及必要来源作用域；ID保存为TEXT。
- `identity_bindings`：本地实体到外部对象的关系；包含覆盖范围，不限制为全局一对一。
- `binding_evidence`：支撑或反对某次绑定的证据。
- `metadata_snapshots`：某外部对象、语言、抓取时间与版本的元数据快照。

同一个TMDB series可以覆盖多个release；不同Bangumi subject可以分别覆盖同一work的不同release。它们是 `contains/part_of/covers_range` 关系，不能全部称为 `exact`。依据：第5.4节结构差异、[Anime-Lists范围映射][anime-lists]。

绑定建议包含：

| 字段 | 语义 |
|---|---|
| `relation`、`scope` | exact、part_of、contains、split、combined、version；必要的季、类型、集范围和时间范围。 |
| `status` | proposed、accepted、rejected、revoked；候选与生效绑定分离。 |
| `confidence` | 可空的算法分数，并附规则/模型版本；未经校准不称“正确概率”。 |
| `source` | 哈希请求、文件名规则、服务器ProviderId、来源映射、社区快照、网页证据等。 |
| `boundBy` | automatic、agent、user；从宿主调用上下文产生，不让模型自行宣称“用户已确认”。 |
| `evidenceIds` | 请求参数摘要、原始候选、日期、类型、标题、编排、网页链接等。 |
| `revision`、`supersedes` | 乐观并发、审计和撤销；不覆盖掉旧判断依据。 |
| `decisionId`、`invocationId`、时间戳 | 关联判断、调用与变更事件。 |

依据：`docs/next/DESIGN.md:26`、`:52`、`:409`；现有confirmed来源混用见`lib/services/emby_dandanplay_matcher.dart:1034`。用户绑定表示权威选择，不代表统计置信度必须为1。

元数据合成建议按字段进行：标题、简介、海报分别保留provider、语言和更新时间，用户覆盖字段优先；刷新元数据不能悄悄改身份。依据：多语言能力见[TMDB语言][tmdb-language]、[AniList Media][anilist-media]，现有身份与名称耦合见`lib/models/watch_history_model.dart:13`。

### 6.3 弹弹play episodeId 的位置

建议保留独立 `DanmakuBinding`：

```text
File/文件版本
  → 对应的内部 Episode 或 episode集合
  → 选定的弹弹play episodeId
  → shift / 时间轴规则 / 证据 / 绑定版本
```

- 弹弹play episodeId仍直接决定弹幕库，不能换成内部episodeId或TMDB/Bangumi ID。依据：`docs/next/DESIGN.md:409`、`lib/services/dandanplay_service_io.dart:1671`。
- 一个内部episode可有多个文件版本；是否共用弹幕及偏移另作判断。依据：`lib/services/concurrent_video_processor.dart:145`、[弹弹play偏移schema][ddp-schema]。
- 已识别TMDB/Bangumi身份但没有弹弹play对应项，应标为“元数据已识别、弹幕未绑定”；不能归为整个文件识别失败。依据：现有扫描要求两个弹弹playID才能成功，`lib/services/concurrent_video_processor.dart:141`，以及多来源目标`docs/next/DESIGN.md:409`。
- 合集未确认时间段前，只建立内容关系；Classic投影最多提供明确选定的单个弹幕库，不能自动拼接多集弹幕。依据：现有单episode播放链路、[弹弹play单文件绑定约定][ddp-open]。

### 6.4 存储选择与 Classic 过渡

**推荐：首期身份、证据、候选和兼容投影队列放入 `next.db`；不立即启用统一库替换历史库。** M2只明确了任务存储，身份表位置是本报告建议。理由是可将“接受候选、关闭Decision、写绑定、追加事件、生成投影任务”置于同一事务，减少跨库协调。依据：`docs/next/M2_TASKBOOK.md:67`、`:68`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:515`。

建议过渡契约：

1. **旧库导入旁路索引。** 建立file/local ID与历史行的对应；保留旧ID来源为legacy，不推断绑定者。清除名称但残留ID的记录作为恢复线索，不直接生效。依据：`lib/models/watch_history_model.dart:119`、`lib/services/emby_dandanplay_matcher.dart:1034`。
2. **Classic继续写进度。** 首期观看位置以原历史存储为准；身份变更只更新匹配字段，避免用旧快照覆盖正在播放的新进度。依据：`lib/utils/video_player_state/video_player_state_metadata.dart:478`、`lib/themes/nipaplay/widgets/library_management_tab.dart:4676`。
3. **可靠投影。** next事务写binding与outbox，兼容执行器读当前历史并合并匹配字段，回读确认后标记交付；崩溃后按稳定键重试。依据：`docs/next/research/LONG_RUNNING_OPERATIONS.md:504`、`:515`。
4. **Classic手动匹配回流。** 经共享绑定服务写Next；尚未迁移的入口通过变更检测导入，并用origin/revision防止回流循环。依据：第2.2节多个写入入口。
5. **多版本进度分开。** 文件位置保留独立播放位置；episode完成状态可聚合，但不同剪辑版不直接复制毫秒位置。依据：现有逐文件进度模型、[TVDB对不同剪辑/顺序的说明][tvdb-readme]。
6. **旧Action语义保持。** M1中的animeId/episodeId继续表示原有弹弹play身份；新增workId/localEpisodeId通过明确的新参数契约或新Action暴露。依据：`docs/next/DESIGN.md:372`、`lib/next/capabilities/library_capability.dart:105`。

**必须处理的展示限制：** 当前Classic本地媒体库过滤要求animeId非空。仅有TMDB/Bangumi身份的条目不会自然显示。应增加读取Next投影的展示适配器，或明确分阶段提供Next视图；不能把TMDB ID塞入旧animeId来绕过过滤。证据：`lib/app/unified_media_library_sections.dart:210`、`:238`。

后续若决定将身份存储移入`nipaplay.db`，应先让其满足第4.3节结构，并通过RepositoryPort迁移唯一权威存储；不长期维护两套可独立修改的common identity。依据：当前统一库固定来源/一对一约束，以及跨库恢复要求。

## 7. 识别算法分层

本节为**建议**，实现应将“证据提取、候选生成、决策、绑定、元数据抓取”分开。现有`getVideoInfo`会预取弹幕，不能直接作为没有附带网络成本的批量识别原语。依据：`lib/services/dandanplay_service_io.dart:1185`、`:1221`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:141`。

### 7.1 确定性信号与自动绑定条件

| 信号 | 建议用法 | 限制与依据 |
|---|---|---|
| 未变化文件上的已接受绑定 | 验证file revision一致后复用；用户固定绑定优先，冲突另报Decision。 | 依据：`docs/next/research/LONG_RUNNING_OPERATIONS.md:571`、`lib/models/watch_history_model.dart:119`。 |
| 弹弹play哈希命中 | 使用可区分的hashOnly请求或保留足以确认哈希来源的响应；唯一精确结果、无已知冲突时自动接受。 | 当前请求是hashAndFileName，客户端fallback也返回isMatched；不能仅读boolean判断哈希命中。依据：`lib/services/dandanplay_service_io.dart:658`、`:1521`；[匹配模式schema][ddp-schema]。 |
| 文件名解析＋已确定release＋集号 | 在编号体系明确、类型一致、来源目录存在唯一对应episode时自动接受。 | 文件名解析本身不证明作品身份；当前首结果与累计减集数不足。依据：`lib/services/dandanplay_service_io.dart:1431`、`:1470`。 |
| 目录结构 | 已接受目录作品/release与明确Season/Specials目录可提供上下文，和文件信号联合使用。 | 普通目录名只作弱证据；目录中文件可能混杂。依据：当前扫描根与路径机制`lib/services/scan_service.dart:287`，及现有季信息丢失`lib/utils/media_filename_parser.dart:50`。 |
| Emby/Jellyfin ProviderIds | 验证目标对象存在、对象层级和season/order后使用；来源记录保留服务器作用域。 | series ID不能自动绑定某集；当前模型尚未保存ProviderIds。依据：`lib/models/emby_model.dart:230`、[TMDB find][tmdb-find]。 |
| 官方跨来源映射 | 获取对方详情，检查范围、类型、日期与编排，生成或接受对应关系。 | 弹弹play明确提示人工映射可能错误；作品级映射不是逐集证明。[官方schema][ddp-schema]。 |
| 社区映射 | 固定快照，按显式范围/逐集规则应用，并检查目标目录。 | 缺项、派生同源与更新冲突需保留；不能仅靠项目数量增加信心。[Anime-Lists][anime-lists]、[Fribb][fribb]。 |
| 集数、年份、日期、时长 | 用来排除冲突或佐证候选。 | 相同总集数不证明同作品；发布日期/时长可能缺失。依据：[Bangumi schema][bgm-api]、[AniList Media][anilist-media]。 |

**建议：** 首期采用可解释规则门槛，例如“唯一候选＋已确认release＋明确编号体系＋无冲突”；不要先设未经验证的0.9阈值。后续用人工标注样本评估自动接受的错误率，再校准分数。依据：`docs/next/DESIGN.md:409`与现有fallback混淆证据。

### 7.2 何时需要 Agent

以下情况建议持久化Decision：

- 多个同名作品、不同年份重制版、季/cour归属不清；
- 中英日别名搜索结果冲突；
- absolute与季内编号冲突，OVA/SP/总集篇类型不明确；
- 合集、拆集、剪辑版没有范围或时间轴证据；
- 哈希结果与用户绑定、服务器元数据冲突；
- 来源映射缺失、失效或社区数据互相矛盾；
- 多来源都无法生成可接受候选。

依据：第2.5节代码缺口、[Anime-Lists复杂映射][anime-lists]、`docs/next/research/LONG_RUNNING_OPERATIONS.md:562`。

网络超时、429、暂时不可达由执行器重试；登录授权或系统权限由宿主处理；普通进度不唤醒Agent。依据：`docs/next/M2_TASKBOOK.md:41`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:557`、`:566`。

Agent可以联网查证，但应通过Action添加候选/证据及提交选择。网页内容只能成为证据，不能直接改数据库或授予权限；无法确认时可交用户、暂缓或跳过。依据：`docs/next/DESIGN.md:50`、`:52`、`:58`、`:409`。

### 7.3 持久 Decision 与候选结构

M2要求`job.decision`保持Harness的`prompt/options`结构，选项携带可执行`ActionCall`。丰富上下文另存在内部记录，并通过读取Action提供。证据：`docs/next/DESIGN.md:227`、`docs/next/M2_TASKBOOK.md:42`。

**建议的内部记录：**

```text
decisionId、jobId、itemId、reason、contextVersion
fileId、fileRevision、当前绑定revision
解析信号、来源请求摘要、候选列表、冲突列表
证据引用、已尝试方法、解决状态、绑定者、解决调用ID
```

候选至少包含：

```text
candidateId
内部work/release/episode或待创建对象
外部对象refs及其覆盖范围
编号体系、类型、原始集号
支持证据、反对证据、缺失信息
规则分数及规则版本
拟提交的绑定差异
```

依据：`docs/next/research/LONG_RUNNING_OPERATIONS.md:571`及第6.2节身份模型建议。

以下JSON是**契约示例，ID均为占位符**：

```json
{
  "prompt": "文件的连续编号与两个发布范围均可能对应，请选择或补充证据。",
  "options": [
    {
      "label": "采用候选 A",
      "detail": "候选 A 使用已核对的季内编号。",
      "call": {
        "action": "media.identity.bind",
        "input": {
          "decisionId": "decision-example",
          "candidateId": "candidate-a",
          "expectedRevision": 7
        }
      }
    },
    {
      "label": "采用候选 B",
      "detail": "候选 B 使用连续编号及明确的区间映射。",
      "call": {
        "action": "media.identity.bind",
        "input": {
          "decisionId": "decision-example",
          "candidateId": "candidate-b",
          "expectedRevision": 7
        }
      }
    },
    {
      "label": "本次跳过",
      "call": {
        "action": "media.identification.skip",
        "input": {
          "decisionId": "decision-example",
          "expectedRevision": 7
        }
      }
    }
  ]
}
```

建议宿主检查候选属于当前Decision、file revision和binding revision仍一致，再原子提交；过期选择返回新的Decision。Agent新增候选先入候选表，不能通过自由填写一个ID绕过校验。相同`jobId/item/reason/contextVersion`不重复生成判断；“本次跳过”“等待补证”“固定忽略”分别保存。依据：`docs/next/DESIGN.md:18`、`:55`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:571`。

### 7.4 文件名解析库与 Dart 路径

**已核实：** Anitomy是动画文件名解析C++库/CLI，能提取标题、年份、集号、发布版本、字幕组及技术字段，支持UTF-8；它仍使用启发式推断。当前默认develop分支处于重写，README说明C++23要求，不能不固定版本就接入。证据：[Anitomy官方仓库][anitomy]。

**项目现状：** 已有Rust元数据桥接及Dart/Web fallback，但接口主要输出basename和搜索关键词，没有完整结构化解析结果。证据：`lib/utils/media_filename_parser.dart:11`、`:27`、`:84`。本次未核实可直接替换的成熟Dart Anitomy等价实现，不据此宣称Dart生态不存在此类库。

**建议实施路径：**

1. 定义纯Dart `FilenameParserPort`与结构化输出：原始标题、别名候选、year、season、episode/range、type、version、releaseGroup、技术字段及解析证据。依据：现有解析缺口与[Anitomy示例][anitomy]。
2. 首期改造已有规则，保留S/E、cour/Part、SP/OVA和原始编号；支持小数、集范围，不能继续限制至300。依据：`lib/services/dandanplay_service_io.dart:1324`、`lib/utils/media_filename_parser.dart:50`。
3. native实现可经现有Rust桥接或新增FFI包装接入固定版本解析库；Web保留规则实现，并显式报告解析能力。平台构建成本需要验证。依据：`lib/utils/media_filename_parser.dart:11`；[Anitomy构建要求][anitomy]。
4. 解析只产生信号，随后核对作品目录；保留原始文件名，避免清理后无法追溯真实数字标题和版本。依据：`lib/utils/media_filename_parser.dart:130`、`:150`。

## 8. 建议的 Action 目录

下表是**新增提案**。effect遵循“read无副作用、write可恢复修改、destructive不可恢复删除”；ActionSpec统一驱动schema与权限。证据：`docs/next/DESIGN.md:18`、`:38`。

| id | effect | 语义 |
|---|---|---|
| `media.metadata.search` | read | 按来源、名称、类型、年份查询候选；不接受绑定。 |
| `media.metadata.get` | read | 读取指定外部对象或已缓存快照，并返回来源/语言/时间。 |
| `media.identity.get` | read | 读取本地实体、外部绑定、修订与证据。 |
| `media.identification.get` | read | 读取识别项、Decision完整上下文、候选和冲突。 |
| `media.library.scan` | write | 创建/复用扫描Job；输入已授权root/source、模式和幂等键，立即返回job。 |
| `media.identification.start` | write | 对稳定文件ID及内容修订启动识别Job，可限定来源。 |
| `media.identification.add_evidence` | write | 添加Agent/用户查得证据及候选，不自动接受身份。 |
| `media.identity.bind` | write | 接受已存候选，验证修订，写绑定、关闭对应Decision并安排兼容投影。 |
| `media.identity.unbind` | write | 撤销指定绑定，保留审计记录，修复兼容投影；不删除媒体。 |
| `media.identification.skip` | write | 明确记录本次跳过，并恢复任务处理其余项。 |
| `media.identification.defer` | write | 保存待补证状态和后续触发条件；不等同识别成功。 |
| `media.metadata.refresh` | write | 启动已绑定对象的元数据刷新Job；不隐式重识别或替换用户字段。 |
| `media.identity.purge` | destructive | 可选后续能力：不可恢复删除指定身份及证据；不能作为普通纠错手段。 |

read查询若需要持久写入候选、证据或元数据，应通过相应write Action提交，避免“搜索”暗中接受绑定。上述Action建议依据是`DESIGN.md:42`的无副作用契约及第7节识别分层。

单项绑定可以是短事务，返回已验证的`Completed`；批量绑定或需要跨库交付时运行Job。现有`task.list/get/wait/cancel`直接复用，`task.wait`上限60秒。依据：`docs/next/DESIGN.md:21`、`docs/next/M2_TASKBOOK.md:75`。

## 9. Task Engine Job 设计

### 9.1 四类 Job

以下为**建议的执行分工**，均沿用M2固定Job字段。证据：`docs/next/M2_TASKBOOK.md:30`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:141`。

| type | phase | 检查点与验证 |
|---|---|---|
| `media.scan` | enumerate→diff→schedule→verify | 保存root/source、枚举游标、扫描快照、文件修订与项状态；验证发现项均已记录，不能把识别成功数当扫描发现数。 |
| `media.identify` | probe→parse→match→reconcile→decide→verify | 保存指纹、解析版本、请求/候选、来源快照；高置信项交绑定，歧义项持久Decision，暂时网络错误进入waiting_retry。 |
| `media.bind` | validate→commit→project→verify | 校验输入修订；提交身份及outbox；回读绑定及必要Classic投影，记录每项结果。 |
| `media.metadata.refresh` | fetch→normalize→merge→verify | 保存provider、对象、语言、抓取版本；验证快照与字段投影，用户覆盖和身份保持独立。 |

扫描Job可以组织子识别Job，或者使用`job_items`；实现应先选择一种方式，避免双重计数。一个歧义文件不必阻塞其余文件枚举和识别：可让项等待Decision，主任务继续，最终汇总未决项。Job处于`needs_decision`时必须提供可执行Decision。依据：`docs/next/M2_TASKBOOK.md:42`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:499`。

### 9.2 幂等、恢复、取消与重试

建议规则：

- **稳定执行键：** 识别使用fileId＋fileRevision＋策略版本；刷新使用external object＋语言＋刷新策略；重复提交返回已有工作，必要强制刷新显式产生新修订。依据：M2已有重复任务复用原则`docs/next/M2_TASKBOOK.md:85`。
- **项级恢复：** 保存候选和已提交绑定，重启先对账再继续，不从头重复搜索或绑定。依据：`docs/next/M2_TASKBOOK.md:50`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:514`。
- **并发校验：** 文件变化、目录改归属或用户手动重绑后，旧Decision和旧抓取结果不得覆盖新状态。依据：Decision版本建议`docs/next/research/LONG_RUNNING_OPERATIONS.md:571`。
- **取消边界：** 停止未开始项；已提交绑定继续回读核对，回执注明取消时已生效项，不自动撤销用户选择。依据：`docs/next/M2_TASKBOOK.md:49`。
- **跨库交付：** next提交成功但Classic写入未完成时，保持可恢复projection状态；通过回读和幂等交付确认，不声称两库原子提交。依据：`docs/next/research/LONG_RUNNING_OPERATIONS.md:515`。
- **来源调度：** 每provider独立限流和retryAt；429遵循服务header，业务未匹配直接形成识别结果，不无限重试。依据：第5.3节官方限流规则。
- **不批量预取弹幕：** 扫描/识别只取得身份所需数据，弹幕按播放或明确缓存任务获取。依据：现有预取`lib/services/dandanplay_service_io.dart:1221`及[弹弹play按需使用约定][ddp-open]。

### 9.3 回执的真实性

建议回执保存发现数、识别数、自动绑定数、Agent/用户绑定数、跳过数、失败数、未决数、元数据刷新数，以及文件修订、绑定修订、Classic投影状态和验证依据。依据：`docs/next/M2_TASKBOOK.md:48`、`:54`、`:62`。

`verified`表示已经回读核对**约定产物**，不表示已证明识别在语义上绝对正确。扫描枚举完成可以成功；“全部文件完成识别”的Job若仍有未决项，不能成功。允许跳过的批任务可以在验证跳过状态后成功，但回执必须列出未识别项。依据：`docs/next/M2_TASKBOOK.md:48`、`:56`。

## 10. 迁移顺序、风险与验证重点

以下为**实施建议**，不是已完成工作。

| 顺序 | 工作与完成条件 | 依据 |
|---|---|---|
| 1 | 先建立M2任务持久化、事件、回执和Decision恢复；统一Job状态与next.db位置。 | `docs/next/M2_TASKBOOK.md:30`、`:67` |
| 2 | 从现有匹配服务抽出probe/parse/provider match；返回完整候选与证据，分离首结果选择和弹幕预取。Classic原入口通过适配器继续工作。 | `lib/services/dandanplay_service_io.dart:1185`、`:1431`；`docs/next/research/LONG_RUNNING_OPERATIONS.md:141` |
| 3 | next身份表旁路导入旧历史及服务器映射，保留legacy未知来源；只读比对，先不批量覆盖旧绑定。 | `lib/models/watch_history_model.dart:119`、`lib/models/watch_history_database.dart:112` |
| 4 | 扫描接入Job并补Classic进度显示；加入高置信规则和持久Decision，其余文件继续处理。 | `docs/next/DESIGN.md:408`、`:409`、`lib/services/concurrent_video_processor.dart:232` |
| 5 | 接入弹弹play/Bangumi桥及TMDB adapter，保存对象类型、scope与episode order；AniList用于作品信息补充，TVDB按用户授权接入。 | 第5节官方能力与许可资料 |
| 6 | 接通绑定事务、outbox和Classic投影；修复Bangumi同步，使用已接受subject及明确Bangumi episode ID，不再比较episodeId与sort。 | `lib/services/bangumi_sync_service.dart:182`、`:399`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:515` |
| 7 | 引入Agent补证与选择流程；加入版本校验、去重、审计和撤销。 | `docs/next/DESIGN.md:52`、`:409`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:571` |
| 8 | 扩展Classic多来源展示和本地ID播放契约；评估是否迁移身份Repository至改造后的统一库。 | `lib/app/unified_media_library_sections.dart:210`、`docs/next/DESIGN.md:372`、第4节schema缺口 |

优先控制的风险及建议验证：

| 风险 | 建议验证重点 | 证据基础 |
|---|---|---|
| 自动误绑定被当作精确命中 | 区分hashOnly、hashAndFileName、客户端fallback与legacy缓存；使用同名、重制、季/cour、小数/SP、长番样本评估。 | `lib/services/dandanplay_service_io.dart:658`、`:1324`、`:1531` |
| 旧数据被错误赋予权威 | 覆盖清除名称但留ID、confirmed自动写入、SQLite无hash等导入场景。 | `lib/models/watch_history_model.dart:119`、`lib/services/emby_dandanplay_matcher.dart:1034`、`lib/models/watch_history_database.dart:112` |
| 来源粒度和编号错位 | 测试一个series对应多个subject、不同order、拆集/合集及同sort不同type。 | [Anime-Lists][anime-lists]、[Bangumi schema][bgm-api] |
| 崩溃导致重复或半交付 | 在next事务提交后、Classic写入后、回执前分别模拟中断，验证可对账恢复。 | `docs/next/M2_TASKBOOK.md:50`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:515` |
| 旧Decision覆盖新选择 | 文件修订变化和用户重绑后执行旧候选，必须拒绝并刷新上下文。 | `docs/next/research/LONG_RUNNING_OPERATIONS.md:571` |
| 进度在重绑时回退 | 播放与元数据绑定同时写入时保留最新进度；不同剪辑版不复制原始毫秒位置。 | `lib/utils/video_player_state/video_player_state_metadata.dart:478`、[TVDB说明][tvdb-readme] |
| 多来源条目Classic不可见 | 验证无弹弹playID条目的显示、播放与弹幕空状态；旧Action继续使用原ID语义。 | `lib/app/unified_media_library_sections.dart:210`、`docs/next/DESIGN.md:372` |
| 配额、授权与平台差异 | 验证429/认证失败分类、按来源缓存、Web与各native平台持久化；不把不可访问当未匹配。 | 第5.3节官方规则、`docs/next/research/LONG_RUNNING_OPERATIONS.md:508` |

现有数据库安全测试可作为回归资产，但本文没有执行，不能据此声明迁移或新方案已经验证通过。证据：`test/database/data_safety_test.dart:61`、`:304`、`:328`。

## 11. 待实施时确认的事项

以下是本次调研的明确未验证项：

- 各目标平台启用统一库或Next SQLite实现的实际兼容性，尤其Web持久化与native运行时；依据：`lib/services/database/database_service.dart:24`、`docs/next/research/LONG_RUNNING_OPERATIONS.md:508`。
- 当前应用的弹弹play接入层级、实际额度、受限接口权限，以及TVDB选用哪种许可；依据：[弹弹play权限与额度说明][ddp-open]、[TVDB授权模式][tvdb-readme]。
- Bangumi和TVDB针对该应用的实际限流阈值；本报告没有填入未核实的数字，参考[BGM官方规则][bgm-api]、[TVDB API][tvdb-api]。
- 固定版本文件名解析库的跨平台编译、Dart/Web接口及中文日文样本表现；依据：[Anitomy当前状态][anitomy]、`lib/utils/media_filename_parser.dart:11`。
- 社区映射快照的覆盖率、许可适用性和错误率，以及自动接受规则的实测精度；依据：[Anime-Lists][anime-lists]、[Fribb][fribb]。

[ddp-open]: https://doc.dandanplay.com/open/
[ddp-schema]: https://api.dandanplay.net/swagger/v2/swagger.json
[bgm-api]: https://github.com/bangumi/api/blob/master/open-api/v0.yaml
[bgm-auth]: https://github.com/bangumi/api/blob/master/docs-raw/How-to-Auth.md
[bgm-ua]: https://github.com/bangumi/api/blob/master/docs-raw/user%20agent.md
[tmdb-search]: https://developer.themoviedb.org/docs/search-and-query-for-details
[tmdb-season]: https://developer.themoviedb.org/reference/tv-season-details
[tmdb-groups]: https://developer.themoviedb.org/reference/tv-series-episode-groups
[tmdb-language]: https://developer.themoviedb.org/docs/languages
[tmdb-images]: https://developer.themoviedb.org/docs/image-basics
[tmdb-external]: https://developer.themoviedb.org/reference/tv-series-external-ids
[tmdb-find]: https://developer.themoviedb.org/reference/find-by-id
[tmdb-auth]: https://developer.themoviedb.org/docs/authentication-application
[tmdb-rate]: https://developer.themoviedb.org/docs/rate-limiting
[tmdb-faq]: https://developer.themoviedb.org/docs/faq
[anilist-query]: https://github.com/AniList/docs/blob/master/docs/guide/graphql/queries/media.md
[anilist-media]: https://github.com/AniList/docs/blob/master/docs/reference/object/media.md
[anilist-auth]: https://github.com/AniList/docs/blob/master/docs/guide/auth/index.md
[anilist-rate]: https://github.com/AniList/docs/blob/master/docs/guide/rate-limiting.md
[anilist-terms]: https://github.com/AniList/docs/blob/master/docs/guide/terms-of-use.md
[tvdb-api]: https://thetvdb.github.io/v4-api/
[tvdb-readme]: https://github.com/thetvdb/v4-api
[anime-lists]: https://github.com/Anime-Lists/anime-lists#format
[fribb]: https://github.com/Fribb/anime-lists
[anitomy]: https://github.com/erengy/anitomy