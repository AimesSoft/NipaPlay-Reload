**结论：不能。** Next 已覆盖首页外观设置、已有观看记录的读取、常规播放，以及已知 Bangumi 条目的评分和短评修改；但标签检索、日历、排行榜、推荐换组、首页刷新等操作仍有明显缺口。

审计分支为 `next/capability-layer`。本次仅静态读取代码，没有修改文件、构建或运行应用。详情页、播放器、账户和媒体库内部功能只核对首页入口涉及的调用，不展开审计。

**先列出本块相关的现有能力**

| 能力 | 与本块相关的用途及代码依据 |
|---|---|
| `media.metadata.search`、`media.metadata.search_batch` | 外部元数据关键词搜索；参数为 `provider/query/kind/year`。[定义](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:281)、[批量定义](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:557) |
| `media.metadata.get`、`media.metadata.get_batch` | 按外部身份读取作品、季、集元数据。[定义](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:296) |
| `media.library.search`、`media.library.series` | 查询 Classic 已记录的本地、WebDAV、SMB 作品及文件，不是发现页的外部检索。[定义](~/Desktop/NipaPlay-Reload/lib/next/capabilities/library_capability.dart:113) |
| `media.library.works`、`media.library.work` | 读取 Next 已登记作品。[定义](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:310) |
| `history.continue_watching` | 读取 Classic 当前内存中的继续播放列表。[实现](~/Desktop/NipaPlay-Reload/lib/next/capabilities/history_capability.dart:45) |
| `playback.open` | 按文件路径，或已记录的 `animeId/episodeId` 播放；按剧集选择遇到多个文件会返回决策。[实现](~/Desktop/NipaPlay-Reload/lib/next/capabilities/playback_capability.dart:87) |
| `ui.open` | 打开主页面、已登记实体的 Classic 详情或文件播放；只有 `page/entityId/path` 三种目标。[定义](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:22) |
| `ui.capture` | 截取当前 Flutter 界面，可观察当前可见内容；不提供点击、滚动、输入或刷新。[定义](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_capture.dart:83) |
| `media.sources.list/libraries/browse/query/sync` | 获取远程库候选和元数据；支持 Jellyfin、Emby、SMB、WebDAV、NipaPlay 共享源。`sync` 是文件发现与索引。[定义](~/Desktop/NipaPlay-Reload/lib/next/media_sources/capability.dart:203)、[实现](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:988) |
| `accounts.status/login`、`accounts.collections.get/update` | 发起用户登录，以及按已知作品 ID 读取、修改评分和短评。[定义](~/Desktop/NipaPlay-Reload/lib/next/accounts/capability.dart:36) |
| `media.identity.bind_batch` | 可以创建或复用作品并绑定外部身份，因此能与 `ui.open` 组合打开尚未登记的弹弹play作品。[实现](~/Desktop/NipaPlay-Reload/lib/next/media/media_service.dart:495) |
| `state.describe/query` | 相关视图为 `history.entries`、`history.continue_watching`、`library.classic_series`、`library.classic_episodes`、`library.works/seasons/episodes/files`、`media.entities/identities/bindings`、`settings.changes`。[注册集合](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:323) |
| `settings.describe/get/set/reset/history` | 注册的首页设置包括分区顺序、分区显隐、季度回顾、卡片简介、低清海报晕染、大图和两张小卡片。[首页设置](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:150)、[分区设置](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:325) |
| `appearance.reset_home_sections` | 恢复首页分区顺序与显示状态。[实现](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:345) |

注册入口见 [NextCore](~/Desktop/NipaPlay-Reload/lib/next/next_core.dart:153) 和 [NextRuntime](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:103)。

`danmaku.search` 虽然也能按标题搜索，但实际请求的是 `/api/v2/search/episodes`，不能替代标签搜索、高级搜索或排行榜。[实现](~/Desktop/NipaPlay-Reload/lib/next/danmaku/host.dart:168)

以下将“当前画面能通过截图看到”判为部分覆盖，不据此认定完整列表、筛选和交互已覆盖。

**1. 缺失——按用户影响从大到小排序**

| 优先级 | Classic 用户操作、入口与实际方法 | 缺失内容 |
|---|---|---|
| 1 | **按一个或多个文本标签检索。** 首页“今日新番”的搜索按钮、新番时间表搜索按钮 → 搜索弹窗 → `performTextSearch()` → `SearchService.searchAnimeByTags()`。[首页入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:4)、[Controller](~/Desktop/NipaPlay-Reload/lib/search/tag_search_controller.dart:217)、[服务](~/Desktop/NipaPlay-Reload/lib/services/search_service.dart:101) | 没有接受 `tags` 列表并调用标签检索的 Action，也没有标签搜索结果视图。把标签拼进 `query` 会走另一种检索，不能认定等价。 |
| 2 | **设置最低评分、最高评分并搜索；与关键词、年份组合搜索。** 弹窗滑块、年份菜单、搜索按钮或关键词回车 → `performAdvancedSearch()` → `searchAnimeAdvanced()`。[界面](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/tag_search_widget.dart:1159)、[Controller](~/Desktop/NipaPlay-Reload/lib/search/tag_search_controller.dart:245)、[服务](~/Desktop/NipaPlay-Reload/lib/services/search_service.dart:165) | 缺少高级搜索入口及 `minRate/maxRate` 参数。现有元数据搜索不返回评分字段，也不能通过返回结果本地过滤来补齐这一流程。[返回结构](~/Desktop/NipaPlay-Reload/lib/next/media/metadata_provider.dart:59) |
| 3 | **浏览完整新番时间表及今日新番名单、星期分组、日期待定条目。** `NewSeriesPage._loadAnimes/_groupAnimesByWeekday`；首页 `_loadTodayAnimes` → `BangumiService.getCalendar()`，实际请求 `/api/v2/bangumi/shin`。[时间表](~/Desktop/NipaPlay-Reload/lib/pages/new_series_page.dart:100)、[分组](~/Desktop/NipaPlay-Reload/lib/pages/new_series_page.dart:171)、[首页](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:99)、[服务](~/Desktop/NipaPlay-Reload/lib/services/bangumi_service.dart:223) | 没有日历 Action 或视图；已有作品库视图不能回答完整的当期播出名单。 |
| 4 | **切换排行榜种类和维度。** 排行榜筛选窗口选择“全站热播／全站飙升／新番热播”；前两者选择周／月／季度，后者选择本季／上季；应用或取消。完整榜单窗口还可直接切换筛选。[筛选窗口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart:202)、[完整榜单切换](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart:986)、[枚举与 API 路径](~/Desktop/NipaPlay-Reload/lib/models/trending_bangumi.dart:3) | 没有榜单查询 Action、查询视图或筛选设置项；不能选择这些种类、周期和季度范围。 |
| 5 | **查看完整排行榜、排名、热度／增长指标和统计日期；刷新排行榜及失败重试。** “完整榜单”“刷新”按钮 → `_showFullTrendingList/_loadTrendingQuery` → `TrendingBangumiService.fetch()`。[入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart:155)、[完整榜单](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart:410)、[服务](~/Desktop/NipaPlay-Reload/lib/services/trending_bangumi_service.dart:37) | 没有取得完整榜单及指标的能力，也不能执行 `forceRefresh`。当前可见预览只能通过截图观察。 |
| 6 | **取得官方随机推荐并“换一组”。** 随机推荐刷新按钮 → `_loadRandomRecommendations(forceRefresh:true)`；已有分组时调用 `_showNextRandomRecommendationGroup()`，循环换组。[入口与分支](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_random_recommendations.dart:9)、[换组](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_random_recommendations.dart:159)、[实际服务](~/Desktop/NipaPlay-Reload/lib/services/random_recommendation_service.dart:26) | 没有读取每日推荐分组、标签和生成日期的能力，也没有换组 Action。这里的“刷新”通常是切换已有分组，不能用普通关键词搜索替代。 |
| 7 | **刷新首页整体内容。** 桌面浮动刷新按钮、大屏刷新按钮、手机下拉刷新 → `_handleManualRefresh/_refreshCupertinoHome`，刷新推荐、最近内容、今日新番、随机推荐、排行榜及继续播放。[桌面调用](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:70)、[手机调用](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_home_page_controls.dart:4) | 没有首页刷新 Action。`state.query` 明确不做来源刷新或网络请求；`media.sources.sync` 只发现并索引文件，不能替代这条调用链。 |
| 8 | **浏览季度回顾完整名单、开播／放送日期、我的评分、短评更新时间；改变回顾排序。** 排序菜单支持开播日期、评论最新／最早、评分最高／最低 → `_setQuarterlyReviewSort()`，持久化 `quarterly_review_sort_v1`。[列表读取](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:97)、[菜单](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review.dart:82)、[排序与持久化](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:300)、[缓存实际组装](~/Desktop/NipaPlay-Reload/lib/services/quarterly_review_cache.dart:355) | 没有回顾视图；`quarterly_review_sort_v1` 未注册。账户查询能读取已知 subject 的收藏，不能直接给出这份回顾名单、日期选择和本地短评时间。 |
| 9 | **加载搜索配置、失败后重试。** 搜索弹窗重试按钮；手机配置未加载时点击年份 → `loadConfig()` → `SearchService.getSearchConfig()`。[桌面入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/tag_search_widget.dart:1139)、[手机入口](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_tag_search_view.dart:137)、[服务](~/Desktop/NipaPlay-Reload/lib/services/search_service.dart:22) | 没有搜索配置查询或重试能力，包括界面使用的有效年份范围。 |
| 10 | **操作搜索草稿。** 添加标签、删除标签、点击已添加标签填回输入框；搜索按钮／回车提交；“加载更多”按钮和高级结果滚动加载。[草稿操作](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/tag_search_widget.dart:280)、[回填和删除](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/tag_search_widget.dart:740)、[加载更多](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/tag_search_widget.dart:1556) | 没有搜索会话或草稿能力，没有完整结果分页入口。Classic 的“加载更多”实际上分批展示已经取得的结果，不是再次请求外部搜索。[实现](~/Desktop/NipaPlay-Reload/lib/search/tag_search_controller.dart:276) |
| 11 | **打开／关闭搜索弹窗；打开观看记录窗口。** `_showTagSearchModal()`、`NewSeriesPage._showSearchModal()`、`_showWatchHistoryDialog()`。[搜索](~/Desktop/NipaPlay-Reload/lib/pages/new_series_page.dart:60)、[观看记录](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_build_sections.dart:296) | `ui.open` 没有搜索弹窗、观看记录窗口或新番时间表目标。记录数据可读，窗口入口缺失。 |
| 12 | **改变日历显示方向、强制刷新和失败重试。** 排序按钮 → `_toggleSort()`；大屏刷新 → `_loadAnimes(forceRefresh:true)`；错误页重试 → `_loadAnimes()`。[排序](~/Desktop/NipaPlay-Reload/lib/pages/new_series_page.dart:53)、[大屏按钮](~/Desktop/NipaPlay-Reload/lib/pages/new_series_page.dart:369)、[重试](~/Desktop/NipaPlay-Reload/lib/pages/new_series_page.dart:663) | 没有对应 Action 或排序设置。 |
| 13 | **切换首页轮播页、横向翻动各栏目。** 点击轮播圆点、滑动轮播；今日新番、随机推荐、继续播放、回顾、最近内容的前／后翻页按钮及拖动列表。[轮播圆点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:464)、[滑动轮播](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_build_hero.dart:99)、[横向翻页](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_image_helpers.dart:609) | 没有当前轮播索引、栏目滚动或翻页能力；截图也不能取得屏幕外的这些条目。 |
| 14 | **关闭／取消窗口、拖动窗口、双击标题区切换窗口显示模式。** 搜索和排行榜的关闭／取消入口；观看记录窗口的拖动、双击；通用窗口标题区同样支持拖动和双击。[搜索关闭](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/tag_search_widget.dart:189)、[榜单取消](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart:372)、[记录窗口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_build_sections.dart:320)、[通用窗口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/nipaplay_window.dart:535) | 没有关闭指定弹窗、取消编辑草稿、移动窗口或切换该窗口显示模式的能力。 |

搜索按钮的键盘激活，以及大屏评分滑块左右键调整，分别调用同一添加／搜索或评分变更操作，因此归入上述缺失，不另算业务能力。[键盘激活](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/keyboard_activatable.dart:25)、[滑块按键](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/large_screen_editable_slider.dart:76)

**2. 部分覆盖**

| 操作 | 已有能力 | 还缺什么 |
|---|---|---|
| 搜索弹窗按作品标题关键词搜索、限定年份 | `media.metadata.search/search_batch` | Classic 走 `/search/adv`，Next 弹弹play实现走 `/search/anime`，且忽略传入的 `year/kind`。Bangumi 实现仅对当前返回结果按年份过滤。返回集合是否等价**待确认**，不能认定完整覆盖。[Classic](~/Desktop/NipaPlay-Reload/lib/search/tag_search_controller.dart:255)、[Next](~/Desktop/NipaPlay-Reload/lib/next/media/providers.dart:229)、[Bangumi](~/Desktop/NipaPlay-Reload/lib/next/media/providers.dart:142) |
| 读取当前画面上的今日新番、榜单预览、随机推荐、轮播、季度回顾 | `ui.capture` | 只能观察当前可见部分；不能查询完整集合、筛选、滚动、换组、读取后台缓存或强制刷新。 |
| 首页“继续播放”手动刷新 | `history.continue_watching`；`state.query` → `history.continue_watching/history.entries` | 能读已有内存状态；不能主动执行 Classic 的 Jellyfin Resume 拉取、Emby Resume 拉取及 `WatchHistoryProvider.refresh()`。[Classic 调用链](~/Desktop/NipaPlay-Reload/lib/pages/dashboard_home_page.dart:725)、[实际拉取服务](~/Desktop/NipaPlay-Reload/lib/services/server_history_sync_service.dart:56) |
| 浏览首页本地及远程“最近添加”、获取推荐候选 | 媒体库 Action、相关 state 视图、`media.sources.browse/query` | Jellyfin／Emby 可读取条目和 `DateCreated` 等字段后自行排序；但没有首页实际展示列表或当前七个轮播候选的视图，也不能触发 Classic 推荐刷新。Classic 推荐还使用服务器 `SortBy=Random`。[首页候选](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:198)、[最近添加](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:775)、[Next 字段](~/Desktop/NipaPlay-Reload/lib/next/media_sources/metadata.dart:3) |
| 首页弹弹play远程库的最近内容、推荐卡片 | 已记录历史／截图可提供部分信息 | Next 来源列表未包含弹弹play远程库类型，不能据此取得其完整分组、剧集和来源上下文。[Classic 分组](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:898)、[Next 来源列表](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:110) |
| 点击 Jellyfin／Emby 首页推荐或最近添加卡片，打开其详情 | `media.sources.query/browse` 可读元数据，`playback.open` 可播放文件 | 缺少打开 `MediaServerDetailPage.showJellyfin/showEmby` 的能力。`ui.open` 的作品详情分支只打开弹弹play详情。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:185)、[Next](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:142) |
| 点击 NipaPlay 共享库或弹弹play远程库推荐卡片，打开带远程剧集的详情 | 共享源可通过 `media.sources.browse` 浏览；普通弹弹play详情可组合打开 | `ui.open` 未传递 Classic 所需的 `sharedSummary/sharedEpisodeLoader/sharedEpisodeBuilder/sharedSourceLabel`，不能认定来源专属详情及剧集入口已覆盖。[共享入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:71)、[弹弹play远程入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:159)、[Next 实际打开](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_ui_open.dart:65) |
| 从季度回顾定位作品并编辑短评 | `accounts.collections.get/update` | 已知 Bangumi subject ID 后能读写；回顾名单、弹弹play ID 到 subject ID 的回顾上下文，以及按卡片发起编辑的流程没有暴露。[Classic 定位](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:250) |
| 短评编辑对话框内“清除评分”、取消草稿 | `accounts.collections.update` 支持保存 1–10 分及短评 | 没有编辑草稿。Classic “清除评分”只把草稿设为 0，随后禁用“确定”；**不能据此认定 Classic 支持持久清零而 Next 缺失**。[对话框](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_comment_dialog.dart:421) |

**3. 已覆盖——一行一个操作**

以下 GUI 操作均以 Classic 界面已挂载、相关服务可用为前提；接线见 [NextRuntime](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:103)。

- 返回／打开首页：`ui.open(page:"home")`，由 `ClassicUiOpen.page()` 导航。[实现](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_ui_open.dart:31)
- 读取首页继续播放条目的标题、集名、进度、位置、时长和观看时间：`history.continue_watching`；`state.query` → `history.continue_watching`。[Classic 列表](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_build_sections.dart:146)
- 读取观看记录数据：`state.query` → `history.entries`；对应观看记录窗口的数据入口。[Classic 窗口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_build_sections.dart:296)
- 对已确定可播放文件发起播放／续播：`playback.open(path:...)`；对应首页继续播放的常规播放结果。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:336)
- 为已记录剧集选择多个候选文件之一后播放：`playback.open(animeId,episodeId)` 返回决策，随后执行候选路径调用。[Classic 选择](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:217)、[能力实现](~/Desktop/NipaPlay-Reload/lib/next/capabilities/playback_capability.dart:129)
- 点击今日新番、日历、随机推荐、排行榜、回顾或本地卡片，打开普通弹弹play作品详情：已有绑定时 `ui.open(entityId)`；尚未登记时可组合 `media.identity.bind_batch(kind:"work",workRef)` → `ui.open`。组合会新增／复用作品绑定，Classic 点击本身没有这一步。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_build_sections.dart:432)、[创建绑定](~/Desktop/NipaPlay-Reload/lib/next/media/identity_store.dart:1146)
- 读取已知 Bangumi subject 的我的评分、短评和收藏：`accounts.collections.get`。[Classic 回顾读取](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:198)
- 保存已知 Bangumi subject 的 1–10 分评分：`accounts.collections.update`，省略状态字段可保留状态。[Classic 保存](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:277)
- 修改／清空已知 Bangumi subject 的短评：`accounts.collections.update(comment:...)`，走同一 `BangumiApiService.updateUserCollection()`。[Next 实现](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:261)
- 发起弹弹play或 Bangumi 用户登录：`accounts.login`，不传秘密时打开用户登录窗口；符合本题例外。[接线](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:92)
- 拖动调整六个首页分区的顺序：`settings.set` → `appearance.homeSectionsOrder`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:462)
- 显示／隐藏任一首页分区：`settings.set` → `appearance.homeSectionsDisabled`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:463)
- 恢复首页分区默认顺序及显示状态：`appearance.reset_home_sections`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:475)
- 显示／隐藏季度新番回顾：`settings.set` → `appearance.showQuarterlyAnimeReview`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:386)
- 显示／隐藏推荐轮播大图：`settings.set` → `appearance.showHomeHeroBanner`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:404)
- 显示／隐藏上方推荐小卡片：`settings.set` → `appearance.showHomeHeroSideCardTop`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:423)
- 显示／隐藏下方推荐小卡片：`settings.set` → `appearance.showHomeHeroSideCardBottom`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:442)
- 显示／隐藏番剧卡片简介：`settings.set` → `appearance.showAnimeCardSummary`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:290)
- 切换低清推荐海报晕染：`settings.set` → `appearance.diffuseLowResolutionPosters`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:326)

**4. 反方向的风险**

发现以下有代码依据的界面约束差异：

1. **Agent 可以只修改短评、保留未评分状态，Classic 回顾编辑器要求先选评分才能提交。**  
   Classic 在评分为 0 时禁用“确定”；Next 的 `rating` 是可选字段，已有收藏可以只传 `comment`，服务直接更新短评。该行为超出此编辑器可提交的组合。[Classic 限制](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_comment_dialog.dart:440)、[Action 参数](~/Desktop/NipaPlay-Reload/lib/next/accounts/capability.dart:9)、[服务检查与写入](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:255)

2. **首页设置的能力可操作范围大于当前设备界面。**  
   Classic 手机隐藏推荐小卡片设置，电视隐藏分区拖动、显隐和恢复默认控件；对应 Next 设置和恢复 Action 没有这些平台可见性条件，默认可见。这会允许修改当前 Classic 界面没有提供的配置；代码尚不能证明其造成破坏。[Classic 手机条件](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:406)、[电视条件](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:446)、[Next 注册](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:172)、[默认可见](~/Desktop/NipaPlay-Reload/lib/next/settings/registry.dart:34)

在本块已检查的首页、日历、推荐和榜单直接操作中，**未发现删除确认被能力绕过的实例**。观看记录窗口内部删除等操作属于其他审计块，本报告不据此作结论。

**5. 没能审完／待确认的部分**

- **新番时间表的当前可达性待确认。** 已按要求审计 `home_page.dart` 和 `new_series_page.dart` 的实现；当前统一主页面注册的是 `DashboardHomePage`，未找到 `NewSeriesPage` 的现行统一导航入口。因此上文日历结论针对该页代码，不能证明当前产品入口仍可到达。[旧 HomePage](~/Desktop/NipaPlay-Reload/lib/pages/home_page.dart:35)、[现行注册](~/Desktop/NipaPlay-Reload/lib/app/adaptive_app_page_content.dart:46)
- **继续播放未匹配条目的完整副作用待确认。** Classic 首页会先调用 `WatchHistoryAutoMatchHelper`；Next 直接进入共享播放服务。常规播放已覆盖，但自动匹配、映射写入和 iOS 替代路径行为是否完全等价，需要播放器审计继续核对。[Classic 前处理](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_actions.dart:295)、[Next 接线](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:105)
- **未将 Controller／服务独有参数当成用户操作。** `selectedType/tagIds`、服务的 `month/restricted/sort` 等虽存在，但本次搜索界面未找到对应可操作控件；没有据此扩大缺失清单。同样，`global_filter_adult_content` 在本块找到的是读取，没有找到用户修改入口。
- **未展开其他块。** 包括作品详情内部收藏、下载、剧集管理、观看记录窗口内部管理、媒体服务器配置和播放器控制。
- **运行时可用性未经验证。** 用户要求不运行应用，因此 GUI 是否挂载、接口返回、平台交互和搜索结果集合等价性均未实测；上述覆盖结论依据注册及调用链。