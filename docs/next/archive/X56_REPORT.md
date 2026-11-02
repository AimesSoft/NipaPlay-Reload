# X56：Next 共用的只读搜索

2026-10-13，worktree `x56-search`，分支 `next/x56-search`。没有 commit、push、改依赖或改种子；没有改 `lib/next/ui/`。

## 1. 完成了什么

- 新增 `media.library.search_merged`：本机与认证 Mesh 合并片库的标题、原名、已有别名/其他语言标题、年份和剧集标题。结果使用与 Next 作品页、剧集播放一致的 canonical `workId/episodeId`，带年份、本机图片路径、设备、进度、可播放事实。
- 新增 `media.sources.search`：Jellyfin/Emby 使用原 Classic 客户端的服务器 SearchTerm 和有界分页；SMB/WebDAV 仅查已登记文件的名字与来源内路径，不枚举目录、不登记新文件。来源各自返回结果或错误，失败不会丢掉其他来源。
- `media.metadata.search` 与 `search_batch` 的每个候选增加 nullable `workId`。依据已接受 exact/contains 作品或发行身份，包括 Mesh；同名、候选、拒绝和撤销的身份不算入库。
- 对应 Action 的 schema/描述及 `family_descriptions.dart` 中 `media.library`、`media.metadata`、`media.sources` 族事实已更新。`nipa describe` 从实时目录读这些说明；种子没有修改。
- 补充只读、身份状态、投影替换与 Classic 契约约束测试；完成合成片库、一次性 Jellyfin、真实认证 Mesh 实验和 Headless AOT 构建。

## 2. 决策

1. **新增合并搜索，保留旧搜索。** `media.library.search` 的 Classic 观看记录范围、animeId 和返回格式均不变。将它改成合并 ID 会破坏现有调用者；新能力直接服务 Next 与 Nipa 的同一份目录，不经过界面筛选或 Agent。
2. **复用 X48 投影，建立内存 Unicode 倒排索引。** `MeshLibrary.compose` 给 `next_library_index.facts` 追加标题集合、年份集合、剧集搜索事实和已接受身份键。内存索引记录连续 1、2、3 个 Unicode 字符的 posting，查询先交集，再校验字面子串；中文单字、日文及大小写英文都可用。不依赖 SQLite 的可选 FTS tokenizer，不改数据库版本。文字没变时只更新展示事实与排序，不重建 posting；删作品/改名会移除旧 posting。
3. **查询语义。** 空白分词为 AND，不分大小写，`%`/`_` 按文字匹配。作品匹配标题集合或年份，剧集匹配自己的标题集合。完整标题优先，其次前缀、子串，再按最近加入及稳定 ID 排序。默认作品/剧集各最多 12，可分别指定 `limit/episodeLimit`（1–100），另给出各自总数。
4. **更新与冷启动。** 首次搜索准备合并目录，此后搜索不调用 `library()` 或逐作品读取数据库；目录每五秒刷新，显式 `media.library.refresh` 立即刷新。接受身份后的在线搜索会准备最新投影再查身份，避免把刚接受的身份误报为 null。X47 的底层全量目录构建仍保留，这次没有改成增量同步。
5. **来源搜索沿用现成客户端。** Classic 的 `catalogPage` 只增加可选 `searchTerm/includeItemTypes`，不传时请求的类型过滤与分页行为不变；原 `browseCatalog` 没有修改。沿用既有 serial 避免搜索不同配置时串服务器会话。服务器搜索不调用 `browse`；结果中不会保存认证图片或播放地址。
6. **连接事实。** 服务器连接/认证失败给该来源 `connectionState=failed`、`total=null` 和 error，不能伪装成“没有找到”。共享只读索引不主动探测连接；`connected/unverified/failed` 是已保存的最近观察，未知连通时 `playable=false`。已记录失败的共享仍保留索引结果并同时返回 error。
7. **ID。** 已绑定来源条目返回 canonical workId/episodeId。服务器另给带来源配置及实际 serverId 的 `sourceWorkId/sourceEpisodeId`，可打开 X48 原样作品/剧集。Series 不返回某个任意子集的 episodeId。未绑定共享文件保留 `sourceId/itemId`，使用原 `media.sources.play`。

主要改动在 `ui_data/library_search.dart`、`mesh/library.dart/library_capability.dart`、`media_sources/search.dart/service.dart/capability.dart`、`media/media_service.dart/media_capability.dart` 及能力族说明。共享 `next_core.dart` 只有一行：接上来源条目的 canonical ID 解析。Mesh 构造时为 MediaService 接身份查询，因此 GUI 与 Headless 使用相同合并身份映射；Headless core、runtime、nipa 脚本和种子不改。

## 3. 实验与检查

证据在 [evidence/x56](evidence/x56/)。Flutter 3.44.6，test/analyze 均 `--no-pub`，按 TEAM 的 lockf 排队并去掉代理。没有启动 NipaPlay GUI，真实服务器客户端实验运行在本 worktree 的 Flutter test 宿主内，使用空 mock 偏好、内存保险库和临时 SQLite；没有接入真实账号。

### 5000 部作品、60000 集

`search_performance_experiment.dart` 写入真实 X48 SQLite 投影，再从该表读取并建索引。包含中文、原名、两个别名、年份、十二集标题及在线/离线设备；热路径调用真实 `MeshLibraryCapability`，以 `origin:gui` 经 Harness 校验并 JSON 序列化，每种查询 100 次。没有用伪造的搜索函数。这里衡量的是投影搜索，不是 5000 部文件的首次扫描或完整 X47 compose。

最终数据见 [index-final.txt](evidence/x56/index-final.txt) 与 [performance.json](evidence/x56/performance.json)。时间单位 ms。

| 查询 | 命中作品 / 剧集 | 索引中位数 | Harness + JSON 中位数 | Harness + JSON P95 |
|---|---:|---:|---:|---:|
| 奇（中文单字） | 5000 / 0 | 4.037 | 4.329 | 4.906 |
| 奇幻 | 5000 / 0 | 4.044 | 4.254 | 4.402 |
| 奇幻作品 4999 | 1 / 0 | 0.008 | 0.044 | 0.072 |
| original ADVENTURE 4999 | 1 / 0 | 0.007 | 0.049 | 0.130 |
| 别名 4999 | 1 / 0 | 0.004 | 0.041 | 0.070 |
| 異世界物語 4999 | 1 / 0 | 0.004 | 0.041 | 0.068 |
| 2026 | 186 / 12 | 0.119 | 0.582 | 0.701 |
| 旅行章节 12 · 4999 | 0 / 1 | 0.005 | 0.054 | 0.075 |
| Chapter 12 Adventure 4999 | 0 / 1 | 0.005 | 0.050 | 0.063 |
| 作品 2026 | 186 / 0 | 0.149 | 0.340 | 0.383 |
| 不存在 | 0 / 0 | <0.001 | 0.017 | 0.025 |

年份作为同一查询词：`2026` 也会命中标题中含 2026 的那一部作品及其十二集，不是独立的 year filter。宽匹配的候选集有 5000 条，仍须校验/排序这些候选；具体词先交集少量 posting，不逐次遍历 65000 个文档。

SQLite 投影写入 **189.337 ms**；读投影并首次建立 posting **1401.972 ms**；文字未变的投影替换 **200.096 ms**。测试进程 RSS 从读投影前约 **468 MiB** 到建完约 **661 MiB**，包含 Flutter 宿主、SQLite isolate、合成输入、解码后的第二份目录及索引，不能把差值当成生产索引的独立内存占用。首次准备不具备热查询的毫秒延迟；这轮没有测 5000 部真实文件的冷扫描时间。

### 一次性 Jellyfin

colima `nipa-test` 的自有容器 `nipa-x56-jellyfin`，Jellyfin 10.10.7，127.0.0.1:28756。两段自行生成的纯色视频及海报声明 CC0-1.0，禁用互联网元数据提供方，配置/缓存/媒体位于本 worktree `.dart_tool` 的临时目录。setup 只输出 session 文件路径，临时密码/令牌不输出或进入证据。

- `X`、`X56`、`X56 Open`、`Open` 分别找到一部 Series 和两集 Episode；不存在的词返回 0。含失败的另一个来源时，成功来源仍给结果。五次响应为 **35.498、12.834、11.628、9.987、3.176 ms**。
- `limit=1` 返回一条，服务器 total=3，确认实际服务器的有界分页。
- **六次搜索前后 SQLite total_changes 完全相同，media_entities/media_locations/media_bindings 均为空**：没有新文件索引、位置或身份。证据 [jellyfin.txt](evidence/x56/jellyfin.txt)。
- 搜索返回的原样 sourceWorkId 经真实 `LibraryDataService.sourceWork/sourceEpisodes` 打开为 “X56 Open Series”、两集，确认不是不可打开的外部编号。
- 按自己的容器名停服后，搜索返回 failed、total=null、error；文件索引保持原值。独立重跑停服阶段通过，见 [jellyfin-offline.txt](evidence/x56/jellyfin-offline.txt)。

### 真实 Mesh 与约束

- 在既有 X47 真 CA/mTLS 实验中加入真实快照的原名、别名、年份查询，完整 test/next 已通过。远端目录搜索的 workId/episodeId 与 `work()/episodes()` 一致；停掉自己的远端节点后，命中剧集保留 device.online=false、playable=false；accepted anime/work 身份都解析为同一合并 ID，未知身份为 null。
- X47 Range/HEAD/416、2808032 字节真实测试视频、ffprobe、8 秒 seek 的解码 MD5、进度 .75→.25、离线图片/目录保留均继续通过。定向证据 [focused-final.txt](evidence/x56/focused-final.txt)，最终加入原名/别名/年份的版本见 [next-full.txt](evidence/x56/next-full.txt)。
- 共享索引连续输入中文及 `%/_` 不写数据库、不能连接的地址也不触发网络枚举，另一个不存在来源独立报错；proposed/rejected/revoked 身份的在线 workId 均为 null，accepted release 身份能返回作品；改名、删除、offline→online 的索引替换不保留旧 posting/身份/播放事实。

### 最终检查

| 检查 | 结果 |
|---|---|
| 完整 `flutter test --no-pub test/next`，仅跑一次 | **544 passed，7 skipped，0 failed**；`next-full.txt` |
| 索引约束 + 最终性能实验 | **4 passed**；`index-final.txt` |
| 来源/身份/真实 Mesh 定向 | **10 passed**；`focused-final.txt` |
| Classic service base、分页、Jellyfin/Emby 隔离 | **23 passed**；`classic-final.txt`，含新增的默认过滤不变约束 |
| 初次定向中的旧片库及其他 Classic 测试 | 通过；`focused.txt`，其唯一失败是新 fixture 缺字段，见下文 |
| Headless AOT，本 worktree 内构建 | 成功；`headless-build.txt` |
| 改动范围 analyze | 0 error；已有 Classic test 的五条 protected-member warning，其他为 info；`analyze-verified.txt` |
| `git diff --check` | 通过 |

### 意外与失败

1. 第一次定向测试的在线身份 fixture 忘填 `media_bindings.revision`，触发真实 NOT NULL 约束。补齐 fixture 后相关测试通过，没有改变生产约束。
2. Jellyfin 首次实验的六次只读搜索已通过。随后**打开来源详情**的既有 X48 路径调用 browse，会登记两集文件；实验最后错误断言“索引仍为空”而失败。这是实验边界的错误，搜索阶段的 total_changes 断言已证明零写入。改成比较停服搜索前后索引一致，独立重跑停服阶段通过；没有改 X48 的详情发现语义，也没有重复此前的服务器搜索阶段。
3. 第一次 analyze 有新实验文件的一条无效非空断言 warning；已去掉。最后 analyze 还有 Classic 测试原先直接调用 protected `isAllowedRedirectTarget` 的五条 warning，确认基线已有，不做无关改写。

### 清理与边界

已删除自己的 Jellyfin 容器以及 session/config/cache/CC0-media 临时目录；Flutter/SQLite/Mesh 测试的目录由各自 teardown 清理，见 [cleanup.txt](evidence/x56/cleanup.txt)。没有启动 `/Applications/NipaPlay.app`、没有 open/激活/像素点击、没有访问登录钥匙串或真实数据目录、没有改 `~/.codex` 或用户的 harness、没有使用真实媒体来源账号、没有读写 `/Volumes/Media`。没有接触 ui-demo 或其他人的实验容器/进程。构建只在当前 worktree；`GeneratedPluginRegistrant.swift` 是任务开始前已有的生成改动，保留。

## 4. 给主控与 Y9 的接线说明

以下均经 runtime.harness 的 `Invocation(origin:'gui')` 调用；不用 Nipa 或 Agent。本任务没有修改 UI。

### 片库

把 `CoreSearch.library` 的 `state.query library.merged` 换为：

```json
{"action":"media.library.search_merged","input":{"query":"词","limit":12,"episodeLimit":4}}
```

返回：

```text
{
  works: [workJson + {aliases:[String], playable:bool}],
  episodes: [{work:同样的作品摘要, episode:episodeJson}],
  workTotal:int, episodeTotal:int
}
```

`works` 解码为 UiWork；`episodes` 解码为 `(UiWork,UiEpisode)`，直接填 Y9 已有 `UiLibraryHits`。继续用作品的 workId 打开作品页、剧集的 episodeId 经 `NextUiActions.play` 播放。不要再从 episodes 数组估集数；返回的 episodeCount/year/originalTitle/artwork/devices 是合并目录事实。episodeJson.device 是优先播放设备，null 表示本机；playable 已包含远端离线状态。

### 在线

仍调用 `media.metadata.search {provider:'dandanplay',query:词}`。每个 record 的 `workId` 为 null 时沿用 `Found.id(provider,externalId)`；非 null 时直接使用该 Next workId 打开本地/合并作品页。在线组和片库组按 workId 去重，替换标题相等的推断。如果已入库候选没有在当前片库结果中出现，保留它并打开对应作品页，避免不同译名导致结果消失。UI 需保留这个身份事实，而不是仅构造 Found ID。

### 来源

打开搜索面板后读取 `media.sources.list`，对支持的 Jellyfin/Emby/SMB/WebDAV 来源逐个调用：

```json
{"action":"media.sources.search","input":{"query":"词","sourceIds":["来源 ID"],"limit":6}}
```

也支持一次传多个来源；返回 `sources:[{sourceId,name,type,basis,connectionState,entries,total,error?}]`。GUI 逐来源请求即可分别处理各自结果/错误；服务器会话操作沿用既有串行保护。查询失败的 total 是 null，不能显示为“没有找到”。共享失败时可能同时有缓存 entries 和 error；保留不可播放的缓存事实。`unverified` 是未知，不是已证实离线。

- 作品优先使用 `entry.workId`，无绑定时使用服务器的 `entry.sourceWorkId`；经 Next 作品页打开。Series 的 playable=false 表示该行本身不是播放单元，不等于其子集不可播放。
- 剧集优先使用 `entry.episodeId`，否则服务器 `entry.sourceEpisodeId`；按 Y9 剧集规则播放。服务器提供 `sourceWorkId` 作为所在作品页。
- 未绑定 SMB/WebDAV File 没有可造出的作品页：调用 `media.sources.play {sourceId:该组sourceId,itemId:entry.itemId}`。Y9 当前 `UiSourceHit` 只有 work，需要主控为直接来源文件/来源剧集补承载方式；不要把 itemId 当 workId。
- 名字显示该组 `name`，已入库的设备事实来自作品；不要显示 ID。服务器 metadata 含已有 ProductionYear、OriginalTitle、ImageTags 等事实，不返回认证图片 URL；需要海报时复用 X48 图片供应者，不为每个输入词主动打开全部详情。

## 5. 还缺什么、需要主控决定的问题

还缺 Y9 的上述接线与真实界面验收；这属于已约定的主控集成。没有新起真实 Emby/SMB/WebDAV 服务，Emby 搜索复用同一个已验收分页接口，共享验证的是已有索引的真实 SQLite 只读路径。这轮没有做 GUI 视频画面/音频验收，也没有改 X47 首次全量构建的成本。

需要主控决定的问题：**没有**。
