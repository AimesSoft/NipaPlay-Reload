# Next 界面、书架与图片能力

本文按当前源码描述能力契约，不等于所有平台已完成实机验收。运行时以 `nipa list` / `nipa describe` 和目标设备返回为准。`UiDataCapability` 与 `LibraryCapability` 分别在 [capability.dart](../../../lib/next/ui_data/capability.dart)、[library_capability.dart](../../../lib/next/ui_data/library_capability.dart) 定义，由 [next_core.dart](../../../lib/next/next_core.dart) 注册；[headless/core.dart](../../../lib/next/headless/core.dart) 也注册数据能力，但没有可见窗口。界面数据主要服务 Next，不应把这些首页摆放解释为 Classic 界面变化。`ui.open` 根据可见界面选择 Next 详情或 Classic 路径；Classic 设置和对话框仍使用原有表单，具体可见性以回执为准（[ui_open.dart](../../../lib/next/capabilities/ui_open.dart)）。

## 首页摆放

| Action | 输入与效果 |
| --- | --- |
| `ui.shelves.put` | `placement=hero` 或 `shelf`、`items:[{workId,note?}]`；hero 最多一部，shelf 还需稳定 `id` 和 `title`。同 ID 完整替换，空 items 移除。作品须存在；标题和注释是给观众看的短句。 |
| `ui.shelves.remove` | `id`，可选 `workId`；删除一项或整个摆放，保留调用来源。它不删除作品、身份或文件。 |

实现见 [service.dart](../../../lib/next/ui_data/service.dart) 的 `putShelf`、`removeShelf`、`home`。保留 ID 有 `hero`、`continue`、`airing`、`recent`、`recently-played`，不能作为自建书架 ID。自建书架按保存顺序展示，作品按输入顺序；系统书架有自己的位置与数据，不提供任意排序所有首页区块的 Action。

主视觉固定选择优先于自动选择；没有固定项时依次查看成功任务关联的可播作品、最近可用本地作品，再看继续观看中可播更新或首项。固定 hero 是单作品，不是多图轮播配置。首页悬停书架约 600 毫秒可暂时预览作品，离开恢复；减少动态效果时不预览。展开对话时还可能展示会话相关作品，固定 hero 优先。具体逻辑见 [home_page.dart](../../../lib/next/ui/home/home_page.dart)、[tokens.dart](../../../lib/next/ui/theme/tokens.dart)。这些是界面行为，不是 Agent 可配置的轮播或悬停 Action。

## 按来源整理片库

Action 的定义与校验见 [library_capability.dart](../../../lib/next/ui_data/library_capability.dart)、[library_service.dart](../../../lib/next/ui_data/library_service.dart)。

| Action | 输入与效果 |
| --- | --- |
| `ui.library.sources` | 读取合并本地目录及已配置来源和在线状态。 |
| `ui.library.page` | `sourceId`；读取类别、隐藏原始类别、预览和各类别可用 sort。离线显示最后成功观察，未读过的内容不编造。 |
| `ui.library.items` | `categoryId`、可选 `offset`、`limit`（1–500，默认 60）、`sort`；返回当前页及总数，sort 须是该类别公布的 ID。 |
| `ui.library.put` | `entries` 批量完整替换分类：每项 `sourceId,categoryId,title,content`，可选 `coverWorkIds`（至多 3）、`sort`。ID 全局唯一，原有分类保留位置，新分类追加；先校验后事务写入。 |
| `ui.library.configure` | `entries:[{sourceId,form?,original?}]`；form 是 `shelves` 或 `cards`，切原始/整理保留整理。 |
| `ui.library.move` | `entries:[{categoryId,index}]`；index 是当前可见类别的零基位置。原始类别顺序只影响本机。 |
| `ui.library.remove` | `entries:[{categoryId}]`；移除整理分类或在本机隐藏原始分类，不删除作品、身份、媒体文件、服务器库或共享目录。 |
| `ui.library.restore` | 同样的 entries；恢复隐藏的原始分类及保存位置，不重建已移除的整理分类。 |

`content` 恰好选择一种：`condition` 加 `filter`；`manual` 加有序 `workIds`；`original` 加 `sourceId,parentId`（本地 parentId 为 `all`，可带服务器身份）。条件支持 `sourceIds,deviceIds,types,watch,genres,yearMin,yearMax,ratingMin,ratingMax,addedAfter,addedBefore`；类型为 anime/series/movie，观看状态为 unwatched/watching/watched，时间使用 ISO-8601。数组内部 OR，维度之间 AND，作用于合并作品整体，页面不会自动加来源限制。未知年份、标签或评分不满足对应条件；评分取界面第一项评分。服务器作品进入条件投影须有已接受身份，原样浏览不会自动接受身份。没有任意自然语言条件或任意字段筛选的内建语义。

条件分类可用 `added`、`title`、`year`、`rating`；手选分类只用 `manual`。服务器原始分类提供名称 `SortName:Ascending`、最近添加 `DateCreated:Descending`、上映 `PremiereDate:Descending`、评分 `CommunityRating:Descending`，也可能显示已有服务器排序；SMB/WebDAV 仅名称和修改时间。条件名称升序、年份/评分/添加时间降序；不要假定支持任意升降序。来源实际排序以 `page` 返回为准。

布局保存在执行设备 `ui_cache` 的 `library:layout:*`，首页摆放在该设备 `ui_shelves`；Mesh 调用目标设备的 Action 时修改的是目标设备本地投影，而不是修改来源服务器或自动同步所有设备布局。合并目录可以包含其他设备的作品；这不改变布局写入位置。参见 [README](../../../lib/next/ui_data/README.md) 和 [Mesh README](../../../lib/next/mesh/README.md)。

## 图片与资料

| Action | 输入与效果 |
| --- | --- |
| `media.metadata.ui_facts` | `workId`；读取界面实际资料、来源、缺项、图片路径与剧集信息。读取可能填充可丢弃图片缓存。 |
| `media.metadata.ui_facts_batch` | `workIds`；逐项返回事实或错误，`atomic:false`。 |
| `media.artwork.set` | `entries:[{entityId,kind,url或file,source:{label,url?}}]`；kind 为作品的 `backdrop/poster/logo` 或剧集的 `still`。HTTP(S) URL 无 userinfo，或本机绝对文件路径，恰好选一个；先解码和缓存/复制，再原子写入覆盖及来源审计。 |
| `media.artwork.clear` | `entries:[{entityId,kind}]`；清除显式覆盖、露出来源图片，保留缓存副本和编辑记录，不删除磁盘文件。 |
| `media.metadata.put` | `requestId,workId,source:{label,url?,ref?}`，可选 `language,work,episodes`；一次原子提交标题、简介、年份、类型、作品三类图及剧集标题、简介、日期、时长、截图。缺省字段不变；可按集 ID 或季/集号定位或创建本地目录集。图片使用 HTTPS URL 或本机绝对路径（此接口拒绝 HTTP），先获取解码；任一失败不提交。相同 requestId 和输入可重放，不同输入冲突。来源 ref 只记录溯源，不创建身份。 |
| `media.metadata.override` | `entityId,field,value`，可选 `language,mode`；field 为 title/originalTitle/overview/legacy imageUrl；persistent 跨刷新保留，correction 被新快照替代，clear 清除覆盖。`media.metadata.override_batch` 提供批量编辑，见 [catalog_capability.dart](../../../lib/next/media/catalog_capability.dart)。 |

覆盖优先于来源快照并可跨刷新保留；不保证来源本身有全部元数据。作品 `imageUrl` 是海报、剧集 `imageUrl` 是截图，并非背景或 Logo。已有 TMDB 身份与凭据可取对应来源图，显式覆盖无需平台身份。图片输入是已有 URL 或文件；这些 Action 不提供模型生图、生成肖像或自动选图工具，外部生成的图片仍可通过上述输入交入。实现见 [artwork.dart](../../../lib/next/ui_data/artwork.dart)、[metadata_put.dart](../../../lib/next/ui_data/metadata_put.dart)、[media_capability.dart](../../../lib/next/media/media_capability.dart)。

## 对话与窗口

`ui.present` 的 `cards` 追加到当前内嵌对话回合；支持 `work`（workId 或来源 ref）、`episode`、`candidates`、`task`、`preparation`、`choices`。选项卡 2–6 项；引用先整批验证，同回合重复卡只显示一次，状态实时解析。片库外 ref 限 TMDB tv/movie、Bangumi subject、弹弹play anime。需要当前 `NIPAPLAY_CHAT`，无活动回合失败；子助手卡片属于其会话，交回结果时已有卡片复制到主会话。见 [capability.dart](../../../lib/next/ui_data/capability.dart) 和 [service.dart](../../../lib/next/ui_data/service.dart)。

`ui.open` 接受一个目标，如 `page`、`dialog`、`entityId/workId` 或 `path`，回执 `opened` 表示当前接口能否打开；多个可播位置需先选择。`ui.close` 仅在宿主提供关闭接口时注册（[ui_capability.dart](../../../lib/next/capabilities/ui_capability.dart)）。`ui.capture` 在支持的宿主截取本应用界面为临时 PNG，可选 `originalSize`；回执说明捕获方式及是否包含原生视频，外部窗口和播放器不包含（[ui_capture.dart](../../../lib/next/capabilities/ui_capture.dart)）。这些能力的可用性依宿主而异，headless 不应假定有窗口。

## 测试证据

约束与行为测试包括 [ui_data_constraints_test.dart](../../../test/next/ui_data_constraints_test.dart)、[library_arrangement_constraints_test.dart](../../../test/next/library_arrangement_constraints_test.dart)、[metadata_put_test.dart](../../../test/next/metadata_put_test.dart)、[ui_home_hero_test.dart](../../../test/next/ui_home_hero_test.dart) 和 [ui_found_cards_test.dart](../../../test/next/ui_found_cards_test.dart)。这些测试作为源码行为的证据，不代表本次各平台实机回归已通过。
