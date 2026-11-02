**结论：没有完全覆盖。** 当前 Next 能完成账号登录发起、退出、指定作品的收藏与评分、观看状态写入及 Bangumi 历史同步；主要缺口是 **WebDAV 多端增量同步、弹弹play内置 Bangumi 绑定流程、账户收藏／评分列表枚举，以及注册、注销账号流程**。

审计对象为 `~/Desktop/NipaPlay-Reload`，分支确认是 `next/capability-layer`。全程仅静态读取代码，未修改文件、未构建或运行应用。以下“已覆盖”允许组合多个 Action 完成；打开账号页面本身不算完成页面内操作。

**相关能力清单**

账号 Action 均注册于 [accounts/capability.dart](~/Desktop/NipaPlay-Reload/lib/next/accounts/capability.dart:36)，并加入实际能力集合：[next_core.dart](~/Desktop/NipaPlay-Reload/lib/next/next_core.dart:161)。

| 能力 id | 本块用途与限制 |
|---|---|
| `accounts.status` | 读取两站本地登录状态、用户名；不是在线连接测试 |
| `accounts.login` | 发起弹弹play密码登录或 Bangumi 令牌授权，返回任务；不传秘密时由用户在窗口输入 |
| `accounts.logout` | 清除指定站点登录信息及保存的凭据 |
| `accounts.collections.get` | 查询指定作品的收藏、评分；必须提供 `workIds` |
| `accounts.collections.update` | 写入收藏状态、评分、评论；弹弹play支持取消收藏，Bangumi支持私密字段 |
| `accounts.episodes.get` | 弹弹play账户观看历史；Bangumi指定作品的剧集收藏状态 |
| `accounts.episodes.update` | 批量写入剧集状态；弹弹play仅允许“已看”，Bangumi允许状态 0–3 |
| `accounts.bangumi.sync` | 本地观看历史同步到 Bangumi；`full` 区分增量、全量 |
| `accounts.bangumi.sync_status` | 上次同步时间、计数、保存的同步摘要及 Bangumi用户信息 |

辅助能力：

- `task.get`、`task.wait`、`task.list`、`task.cancel`：跟踪登录和同步任务。[tasks/actions.dart](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/tasks/actions.dart:6)
- `media.metadata.search`、`media.metadata.get`：查找作品身份、获取剧集目录，用于组合评分和进度操作。[media_capability.dart](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:280)
- `ui.open`：可打开 `account` 页面、已有身份对应的 Classic 详情；没有 URL 或账号子操作参数。[ui_open.dart](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:21)
- `backup.export`、`backup.preview`、`backup.restore`：本报告仅核对 `accounts`、`watchHistory` 类别；`backup.history_export`、`backup.history_restore` 对应观看进度文件。[operations.dart](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:37)
- `playback.open` 接入 Classic `PlaybackService`，保留播放过程中的既有进度回传路径。[next_runtime.dart](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:103)

`state.query` 中相关视图为 `history.entries`、`history.continue_watching`、`tasks`、`task_events`、`task_receipts` 和活动记录。历史视图读取 Classic 内存状态，**不刷新远端历史**；没有账户收藏／评分列表、弹弹play内置 Bangumi 绑定或 WebDAV 增量同步状态视图。[views.dart](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:481)

设置注册表未发现 `AutoSyncSettings`、`auto_sync_*`、`incremental_sync_*` 或 Bangumi 同步缓存的注册项。通用 `settings.*` 只能操作注册项，未知键会返回 `notFound`，不能直接改任意偏好键。[registry.dart](~/Desktop/NipaPlay-Reload/lib/next/settings/registry.dart:132)

**1. 缺失——按用户影响排序**

| 顺序 | Classic 中的位置、操作 | Classic 实际方法与位置 | Next 缺口 |
|---|---|---|---|
| 1 | 设置→备份与恢复：启用／禁用“多端增量同步” | `_toggleAutoSync` → `AutoSyncService.enable/disable`：[界面](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:106)、[服务](~/Desktop/NipaPlay-Reload/lib/services/auto_sync_service.dart:122) | 无对应 Action、设置项 |
| 1 | WebDAV多端同步对话框：配置服务器地址、用户名、远端目录并保存 | `_showSyncSettingsDialog` → `AutoSyncSettings.saveWebDavConfiguration`：[界面](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:134)、[持久化](~/Desktop/NipaPlay-Reload/lib/utils/auto_sync_settings.dart:132) | 无配置入口；即使密码由用户输入，Agent也无法发起此配置流程 |
| 1 | 同一对话框：选择同步间隔、切换“记录变化时就同步” | 下拉框提供 5、15、30、60、180、360 分钟；开关随配置保存：[间隔](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:748)、[控件](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:941) | 两项均未注册 |
| 1 | 同一对话框：逐项选择偏好设置、媒体库、观看历史、剧集匹配、账户绑定同步类别 | 类别复选框：[backup_restore_page.dart](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:984) | 无同步类别参数或设置项 |
| 1 | 同一对话框：“测试连接” | `_testConnection` → `AutoSyncService.testConnection`：[界面](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:791)、[服务](~/Desktop/NipaPlay-Reload/lib/services/auto_sync_service.dart:176) | 无对应能力 |
| 1 | 备份与恢复：“手动同步” | `_manualSync` → `AutoSyncService.manualSync`：[界面](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:177)、[服务](~/Desktop/NipaPlay-Reload/lib/services/auto_sync_service.dart:140) | 无增量仓库拉取、合并、上传能力 |
| 1 | 查看多端同步配置、上次时间、失败信息及本次补丁／变更数量 | `_loadAutoSyncSettings`、`_manualSync`：[状态读取](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:73)、[结果显示](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:183) | 无相应状态视图；通用任务视图也没有该服务任务 |
| 2 | 账号→弹弹play内置 Bangumi：“绑定／重新授权” | `requestBangumiOauthByDandanplay` → `getBangumiOAuthLoginUrl`，随后打开浏览器：[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:551)、[界面](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:550)、[服务](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:767) | `accounts.login(provider=bangumi)`走独立令牌授权，不能发起这条 OAuth绑定路径 |
| 2 | 同一区域：“管理Bangumi同步设置” | `requestDandanBangumiManageUrl` → `startBangumiManageProcess`：[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:581)、[服务](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:2780) | 无管理页发起能力 |
| 2 | 同一区域：“我已完成网页操作，刷新状态”；查看绑定账号及授权过期状态 | `refreshDandanBangumiLinkStatus` → `refreshLinkedBangumiStatus`：[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:594)、[绑定状态](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:75) | 无刷新能力；`accounts.status`只返回登录状态、用户名，没有此绑定信息 |
| 3 | 账号活动：“我的收藏”“我的评分”，以及刷新／失败后重试 | `loadUserActivity` 调用 `getUserFavorites`，分别生成收藏和评分列表：[控制器](~/Desktop/NipaPlay-Reload/lib/controllers/user_activity_controller.dart:54)、[分类](~/Desktop/NipaPlay-Reload/lib/controllers/user_activity_controller.dart:118)、[界面](~/Desktop/NipaPlay-Reload/lib/widgets/user_activity/desktop_user_activity.dart:87) | `accounts.collections.get`必须预先知道作品 ID，且仅返回指定作品，无法枚举账户列表；本地媒体库不是云端收藏全集 |
| 4 | 弹弹play账号：“注销账号”→确认→打开注销网页 | `startDeleteAccount` → `startDeleteAccountProcess`：[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:269)、[服务](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:2748)、[确认框](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:166) | 无注销流程发起能力；`accounts.logout`只退出登录 |
| 4 | 手机注销确认框：“已完成注销”后的本地清理 | `completeAccountDeletion`，除登录信息外还处理过期弹幕缓存：[按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:191)、[服务](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:2809) | 无对应完成／清理能力，退出登录不是完整替代 |
| 5 | 弹弹play未登录：“注册新账号”，填写用户名、邮箱、昵称、密码后提交 | `showRegisterDialog` → `performRegister` → `DandanplayService.register`：[表单](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:110)、[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:176)、[服务](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:915) | 无注册能力，也不能发起由用户填写秘密的注册窗口 |
| 6 | Bangumi同步操作：“测试连接” | `testBangumiConnection` → `BangumiSyncService.testBangumiConnection` → 在线API测试：[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:504)、[服务](~/Desktop/NipaPlay-Reload/lib/services/bangumi_sync_service.dart:714) | 本地登录状态、保存的同步摘要都不能替代实时令牌／连接测试 |
| 6 | Bangumi同步操作：“清除同步缓存” | `clearBangumiSyncCache` → `clearSyncCache`，删除已同步集合和同步摘要：[控制器](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:536)、[服务](~/Desktop/NipaPlay-Reload/lib/services/bangumi_sync_service.dart:666) | 无清除能力；`full=true`执行全量同步，但不等价于仅清除缓存 |
| 7 | Bangumi：“前往创建访问令牌”；两套同步说明帮助按钮 | `_openBangumiAccessTokenPage`、`_showBangumiSyncHelpDialog`：[令牌链接](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:538)、[帮助](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:478) | 无打开外部链接或指定帮助对话框的 Action；Agent可以文字说明，但不能完成这些界面操作 |

`media.sources.sync`仅递归发现媒体文件并登记索引，不能替代上述多端同步。[capability.dart](~/Desktop/NipaPlay-Reload/lib/next/media_sources/capability.dart:263)

**2. 部分覆盖**

| 操作 | 已有覆盖 | 缺少的部分 |
|---|---|---|
| Bangumi同步过程中查看当前步骤、正在同步的作品及“当前／总数” | `accounts.bangumi.sync`、`task.get/wait`能看到任务状态及最终结果 | Classic传入 `progressCallback`、`countCallback`更新界面；Next执行器调用相同服务时没有传这两个回调，只设置固定 `phase=sync`。[Classic](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:456)、[Next](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:326) |
| 通过 `state.query`查看 Bangumi同步结果 | `tasks`、`task_receipts`包含公共任务投影 | 公共回执白名单没有同步计数、`syncResults`等字段。应改用 `task.get/wait`获取最终任务，或 `accounts.bangumi.sync_status`读取保存的汇总；后者也不保存逐作品结果。[投影](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:88)、[汇总保存](~/Desktop/NipaPlay-Reload/lib/services/bangumi_sync_service.dart:629) |
| iOS通过系统文件导出器转移账户备份／观看进度文件 | `backup.export`、`backup.history_export`能生成文件 | Action不调用 Classic iOS的 `SystemShareService.exportFile`，缺少进入系统保存／分享流程这一步。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:494)、[Next](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:124) |

**3. 已覆盖——一行一个操作**

- 查看两站本地登录状态、用户名：`accounts.status`；Classic：[loadLoginStatus](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:64)、[loadBangumiStatus](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:333)。
- 发起弹弹play登录，用户输入密码：`accounts.login(provider=dandanplay)`＋`task.wait`；Classic：[performLogin](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:91)；Next窗口已连接：[next_runtime.dart](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:92)。
- 发起 Bangumi令牌保存／授权，用户输入令牌：`accounts.login(provider=bangumi)`＋`task.wait`；Classic：[saveBangumiToken](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:358)。
- 退出弹弹play登录：`accounts.logout(provider=dandanplay)`；Classic：[performLogout](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:254)。
- 删除 Bangumi令牌、解除独立授权：`accounts.logout(provider=bangumi)`；Classic：[clearBangumiToken](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:409)。
- 查看／刷新账号活动中的最近观看列表：`accounts.episodes.get(provider=dandanplay)`；Classic：[loadUserActivity](~/Desktop/NipaPlay-Reload/lib/controllers/user_activity_controller.dart:56)。
- 查看指定作品的弹弹play收藏状态、评分：`accounts.collections.get`；Classic：[详情数据加载](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:775)。
- 查看指定作品的 Bangumi收藏、评分、评论、进度：`accounts.collections.get`；Classic：[评论初值读取](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_comment_prompt_controller.dart:74)。
- 详情页收藏按钮／沉浸模式菜单“收藏”：`accounts.collections.update(status=favorited)`；Classic：[_toggleFavorite](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3556)、[菜单分派](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3113)。
- 同一按钮／菜单取消收藏：`accounts.collections.update(remove=true, provider=dandanplay)`；Classic：[removeFavorite调用](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3573)。
- 提交弹弹play 1–10分评分：`accounts.collections.update(rating=…)`；Classic：[_handleRatingSubmitted](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3858)。
- Bangumi收藏对话框选择“想看／看过／在看／搁置／抛弃”：`accounts.collections.update(status=wish/done/doing/onHold/dropped)`；Classic：[_syncBangumiCollection](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1073)。
- Bangumi收藏／短评对话框提交评分、评论：`accounts.collections.update(rating=…, comment=…)`；Classic：[_handleBangumiCollectionSubmitted](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3775)。
- 季度回顾修改短评与评分，并保留收藏状态：`accounts.collections.update`，省略 `status`；Classic：[_editQuarterlyReviewComment](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:250)。
- 评分同步两站：分别调用两次 `accounts.collections.update`；Classic：[评分联动](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3866)、[Bangumi表单联动](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3811)。
- 收藏对话框通过输入框、加减按钮、滑块设置“已看N集”的远端标记：`media.metadata.get`取得正片剧集 ID，再分批 `accounts.episodes.update(state=2)`；Classic：[_syncBangumiEpisodeProgress](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1163)、[进度控件](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_collection_dialog.dart:557)；Next可取得完整目录：[providers.dart](~/Desktop/NipaPlay-Reload/lib/next/media/providers.dart:193)。
- 剧集列表将未看单集标为已看：`accounts.episodes.update(provider=dandanplay,state=2)`；Classic：[按钮](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:2401)、[服务调用](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1245)。
- 上述标记同时更新 Bangumi进度：组合 `accounts.collections.get/update`、`media.metadata.get`、`accounts.episodes.update`；Classic：[跨站联动](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1260)。
- 查看远端观看／剧集状态：`accounts.episodes.get`；Classic：[弹弹play状态服务](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:2237)、[Bangumi状态服务](~/Desktop/NipaPlay-Reload/lib/services/bangumi_api_service.dart:575)。
- Bangumi“增量同步”：`accounts.bangumi.sync(full=false)`；Classic：[performBangumiSync](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:437)。
- Bangumi“全量同步”：`accounts.bangumi.sync(full=true)`；Classic：[按钮绑定](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/account/material_account_page.dart:281)。
- 查看上次 Bangumi同步时间及保存的统计：`accounts.bangumi.sync_status`；Classic：[loadBangumiStatus](~/Desktop/NipaPlay-Reload/lib/pages/account/account_controller.dart:333)。
- 导出账户／观看历史完整备份，选择相应类别：`backup.export(categories=[accounts/watchHistory…])`；Classic：[_showFullBackupDialog](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:207)。
- 预览完整备份并选择恢复账户／观看历史类别：`backup.preview`＋`backup.restore`；Classic：[_showFullRestoreDialog](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:336)。
- 导出观看进度 `.nph`：`backup.history_export`；Classic：[_backupHistory](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:470)。
- 恢复观看进度 `.nph`：`backup.history_restore`，沿用实际服务的本地文件检查；Classic：[_restoreHistory](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:517)。
- Agent发起 Classic播放后，保留既有弹弹play观看记录回传及 Jellyfin／Emby／共享主机进度同步：`playback.open`间接覆盖；Classic：[弹弹play回传](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_streaming.dart:575)、[远端进度路径](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1599)。是否远端接受仍取决于原有登录、匹配与会话条件。

对话框“清除评分”需特别区分：实际只把**草稿选分**设为 0，随后确定按钮禁用，不是删除服务器评分。不能据此认定 Next缺少远端清评分能力。[rating_dialog.dart](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/rating_dialog.dart:305)、[bangumi_collection_dialog.dart](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_collection_dialog.dart:680)

取消未提交表单、关闭说明框、切换列表标签不产生账号写入；Agent可不提交写入。已发起的登录窗口可用 `task.cancel`终止。[login_dialog.dart](~/Desktop/NipaPlay-Reload/lib/next/accounts/login_dialog.dart:27) 大屏焦点激活复用同一操作回调；所查账号界面没有额外的账号右键菜单、拖放或独立快捷键操作。[desktop_user_activity.dart](~/Desktop/NipaPlay-Reload/lib/widgets/user_activity/desktop_user_activity.dart:497)

**4. 反方向风险／操作边界扩大**

1. **恢复账户、观看记录可绕过 Classic确认。**  
   Classic恢复完整备份和 `.nph`均在确认后才调用导入服务：[完整备份确认](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:385)、[观看进度确认](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:545)。  
   `backup.restore`、`backup.history_restore`没有 `confirm`字段或 `NeedsDecision`，直接调用导入：[operations.dart](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:84)。虽然标为 `Effect.destructive`，HTTP `/harness`仅要求调用方传 `execute=true`；MCP路径没有等价确认门槛：[HTTP](~/Desktop/NipaPlay-Reload/lib/next/agent_endpoint.dart:297)、[MCP初始化](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/mcp/endpoint.dart:28)、[MCP调用](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/mcp/rpc.dart:74)。这是确认流程缺口，不代表绕过凭据或文件访问授权。

2. **Agent能直接修改 Bangumi单集为未收藏、想看、抛弃。**  
   Next允许 `state=0/1/2/3`，直接调用单集 PUT：[service.dart](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:290)。所查 Classic进度界面只生成前 N集“看过”请求，批量服务还明确跳过 `type=0`：[界面逻辑](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1201)、[批量服务](~/Desktop/NipaPlay-Reload/lib/services/bangumi_api_service.dart:652)。因此 Agent具有这组界面未提供的远端修改能力；不是服务层新增权限。

3. **Agent可跳过 Classic表单“必须选择评分”的提交限制。**  
   Classic收藏／短评对话框选分为 0时禁止提交：[收藏对话框](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_collection_dialog.dart:698)、[短评对话框](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_comment_dialog.dart:439)。Next允许只传 `status`或 `comment`，不要求 `rating`：[能力输入](~/Desktop/NipaPlay-Reload/lib/next/accounts/capability.dart:9)、[执行校验](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:209)。

弹弹play取消收藏、退出登录、删除 Bangumi令牌，在所查 Classic路径本来就没有额外确认；没有依据将其列为确认绕过。

**5. 没能审完／待确认**

- **外部网页中的具体操作待确认。** 仓库能证明会打开注销页、Bangumi绑定管理页；管理服务注释提到“播放历史同步开关／解绑”，但没有网页实现证据，无法逐项审计网页内控件或最终注销约束。[服务入口](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:2779)
- **远端真实效果未验证。** 包括登录、收藏写入、单集状态、跨站同步和共享主机回传；本次禁止运行应用及在线验证，覆盖结论仅表示代码路径与输入表达能力成立。
- **播放自动同步、服务器恢复观看记录只核对到相关调用链。** 未扩展审计播放器控制、媒体源配置或远程控制界面；这些属于其他审计块。服务器历史服务的自动就绪同步也未被误算成独立的 Agent刷新能力。[server_history_sync_service.dart](~/Desktop/NipaPlay-Reload/lib/services/server_history_sync_service.dart:33)
- **降低“已看N集”不是已证实的远端撤销操作。** Classic循环只为目标前缀生成“看过”请求，未生成后续集数撤销请求；不能把界面数字降低推断为服务器取消已看，也不能据此报告 Next缺少等价撤销。[anime_detail_page.dart](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1201)