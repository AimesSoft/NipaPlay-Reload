**结论：不能全部做到。** Next 已覆盖查询媒体库、读取历史、管理多数远程来源、搜索识别候选和建立新匹配，但仍缺少 Classic 的目录生命周期管理、历史删除、完整解除匹配、自定义媒体创建，以及若干远程管理和海报墙操作。

仓库分支已核对为 `next/capability-layer`。本次仅静态读取代码，没有修改文件、构建或运行应用。下面以“能取得同样的数据或完成同样的业务结果”为覆盖标准；只打开页面、只写入 Next 数据而未改变 Classic 对应数据，不算完整覆盖。

## 相关能力清单

注册入口见 [next_core.dart:161](~/Desktop/NipaPlay-Reload/lib/next/next_core.dart:161)、[next_runtime.dart:103](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:103)。

| 类别 | 本块相关能力 |
|---|---|
| Classic 库查询 | `media.library.search`、`media.library.series`、`history.continue_watching` |
| Next 索引与查询 | `media.library.scan`、`media.library.import_history`、`media.library.works`、`media.library.work`、`media.files.list` |
| 识别与元数据 | `media.hash.match`、`media.identity.get`、`media.identity.bind_batch`、`media.identity.unbind_batch`、`media.metadata.search`、`media.metadata.get`、`media.metadata.search_batch`、`media.metadata.get_batch`、`media.metadata.import_batch`、`media.metadata.snapshots`、`media.metadata.override`、`media.metadata.refresh` |
| 远程来源 | `media.sources.list`、`media.sources.add`、`media.sources.update`、`media.sources.remove`、`media.sources.login`、`media.sources.check`、`media.sources.libraries`、`media.sources.select`、`media.sources.browse`、`media.sources.query`、`media.sources.sync` |
| 详情页中的账户操作 | `accounts.status`、`accounts.login`、`accounts.collections.get`、`accounts.collections.update`、`accounts.episodes.get`、`accounts.episodes.update` |
| 导航与播放入口 | `ui.open`、`playback.open`；版本、转码选择相关 `playback.stream_options`、`playback.select_stream` |
| 查询视图 | `state.query`：`library.classic_series`、`library.classic_episodes`、`library.works`、`library.seasons`、`library.episodes`、`library.files`、`media.entities`、`media.identities`、`media.bindings`、`history.entries`、`history.continue_watching` |
| 任务观察 | `task.*` 和 `tasks`、`task_events`、`task_receipts` 视图；观察的是 Next 任务，不是 Classic `ScanService` 状态 |
| 设置 | `settings.describe/get/set/reset/history`；相关键包括 `appearance.showMediaLibraryNewBadge`、`danmaku.skipMatching`、`danmaku.autoMatchFirstSearchResultOnHashFail`，以及 `webdavQuick.*` 的目录、排序、快速匹配和搜索设置 |

设置注册表只接受已注册且可见的键，不能凭任意 SharedPreferences 键补齐功能，见 [registry.dart:132](~/Desktop/NipaPlay-Reload/lib/next/settings/registry.dart:132)。`download_settings.dart` 中的下载目录也不是 Classic 扫描目录注册表。

## 1. 缺失：按用户影响排序

### 1. 添加新的 Classic 本地媒体目录

- **界面**：媒体库“添加媒体→本地文件夹”、本地库管理“添加本地文件夹”。
- **Classic**：选择目录后调用 `ScanService.startDirectoryScan`，见 [adaptive_add_media_flow.dart:65](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_add_media_flow.dart:65)、[library_management_tab.dart:522](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:522)。
- **缺口**：没有添加 Classic 扫描根目录的 Action，也不能发起目录选择授权。Next 的可访问根目录直接来自 `scanService.scannedFolders`，见 [service_provider.dart:53](~/Desktop/NipaPlay-Reload/lib/providers/service_provider.dart:53)；`media.library.scan` 只能扫描已经在这些根目录内的原生路径，见 [media_service.dart:73](~/Desktop/NipaPlay-Reload/lib/next/media/media_service.dart:73)。

因此，Agent 无法独立完成“把一个尚未加入 Classic 的目录添加到媒体库”。

### 2. 删除单条观看历史

- **界面**：观看历史页每项的删除按钮及确认对话框。
- **Classic 方法**：`_showDeleteConfirmDialog` → `WatchHistoryProvider.removeHistory`，见 [watch_history_page.dart:740](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/watch_history_page.dart:740)、[watch_history_provider.dart:443](~/Desktop/NipaPlay-Reload/lib/providers/watch_history_provider.dart:443)。
- **缺口**：历史 Action 和视图提供读取，没有删除单条历史的能力。

### 3. 按番剧批量删除观看历史

- **界面**：详情页“清理记录／更多→清理本地记录→批量删除观看记录”。
- **Classic 方法**：`_showEpisodeListCleanupDialog` → `WatchHistoryManager.removeHistoryByAnimeId`，见 [anime_detail_page.dart:3603](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3603)、[watch_history_model.dart:1052](~/Desktop/NipaPlay-Reload/lib/models/watch_history_model.dart:1052)。
- **缺口**：没有按番剧删除历史的 Action。撤销身份绑定不会删除观看记录。

### 4. 移除本地扫描目录并清理关联记录

- **界面**：本地库管理目录菜单“移除文件夹”，需确认。
- **Classic 方法**：`_handleRemoveFolder` → `ScanService.removeScannedFolder`，见 [library_management_tab.dart:722](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:722)。
- **实际效果**：清理该路径前缀的历史、移除扫描目录、清理目录哈希缓存，见 [scan_service.dart:1029](~/Desktop/NipaPlay-Reload/lib/services/scan_service.dart:1029)。
- **缺口**：没有对应 Action。`media.sources.remove` 不支持本地扫描目录，并且明确保留索引和历史。

### 5. 清理不存在的本地扫描目录

- **界面**：本地库管理“清理不存在文件夹”。
- **Classic 方法**：调用 `ScanService.cleanupMissingScannedFolders`，见 [library_management_tab.dart:1904](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:1904)、[scan_service.dart:1090](~/Desktop/NipaPlay-Reload/lib/services/scan_service.dart:1090)。
- **缺口**：没有检查并移除失效 Classic 根目录的能力；Next 来源同步也不会删除失踪文件。

### 6. 创建不依赖外部作品身份的自定义媒体

- **界面**：本地／WebDAV／SMB 库管理，文件或目录菜单“自定义媒体信息”。
- **Classic 方法**：`_showMountedCustomMediaInfo` → `CustomMediaInfoDialog._saveCustomMediaInfo`，见 [library_management_tab.dart:3095](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:3095)。
- **用户可填写**：名称、中文名、简介、播出日期／星期、评分、标签、制作信息、平台、总集数、类型、Bangumi 链接、封面；第二步可包含子目录并指定各文件的剧集编号和标题。
- **实际效果**：生成负数 `animeId`，写入各文件历史，并保存 Classic 自定义番剧详情缓存，见 [custom_media_info_dialog.dart:975](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/custom_media_info_dialog.dart:975)。
- **缺口**：Next 没有创建这一类 Classic 自定义番剧的能力。`metadata.override` 和 `metadata.import_batch` 写入 Next 元数据，不能代替上述创建流程。

### 7. 管理 NipaPlay 共享端上的扫描目录

以下操作分别缺失：

| Classic 操作 | 界面及代码 |
|---|---|
| 添加远端目录并扫描 | [_openAddFolderDialog:1854](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1854) → `addRemoteFolder` |
| 单目录重新扫描 | [shared_remote_library_view.dart:1699](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1699) |
| 移除远端扫描目录 | [shared_remote_library_view.dart:1713](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1713) → `removeRemoteFolder` |
| 全部远端目录智能刷新 | [shared_remote_library_view.dart:300](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:300) → `rescanRemoteAll` |
| 清理远端不存在目录 | [shared_remote_library_view.dart:268](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:268) → `cleanupMissingRemoteFolders` |
| 查询远端目录管理和 Classic 扫描状态 | [shared_remote_library_provider.dart:967](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:967)、[shared_remote_library_provider.dart:1075](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1075) |

这些调用确实进入远端管理 API，最终调用远端 `ScanService`，见 [local_media_management_api.dart:637](~/Desktop/NipaPlay-Reload/lib/services/local_media_management_api.dart:637)、[local_media_management_api.dart:672](~/Desktop/NipaPlay-Reload/lib/services/local_media_management_api.dart:672)、[local_media_management_api.dart:1032](~/Desktop/NipaPlay-Reload/lib/services/local_media_management_api.dart:1032)。

`media.sources.sync` 只发现内容并写入本机 Next 索引，不能执行这些远端管理操作，见 [service.dart:988](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:988)。

### 8. 使用弹弹play远程媒体库

分别缺失：配置远程地址、发起 API 密钥输入／连接、刷新库、查询番剧及剧集列表。

- **Classic 入口**：[adaptive_add_media_flow.dart:132](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_add_media_flow.dart:132)、[dandanplay_remote_library_view.dart:994](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dandanplay_remote_library_view.dart:994)。
- **实际服务**：`DandanplayRemoteProvider.connect/refresh`，见 [dandanplay_remote_provider.dart:96](~/Desktop/NipaPlay-Reload/lib/providers/dandanplay_remote_provider.dart:96)、[dandanplay_remote_provider.dart:184](~/Desktop/NipaPlay-Reload/lib/providers/dandanplay_remote_provider.dart:184)。
- **缺口**：`media.sources.add` 的来源枚举没有此类型，见 [capability.dart:120](~/Desktop/NipaPlay-Reload/lib/next/media_sources/capability.dart:120)。`accounts.login(provider=dandanplay)` 是账户登录，不是弹弹play远程媒体库连接。

秘密输入可以交给用户，但连发起这个远程连接流程的能力也缺失。

### 9. Classic 扫描维护和故障查看

以下操作没有对应能力：

| 操作 | Classic 方法及位置 |
|---|---|
| 清理智能扫描哈希缓存 | `clearAllFolderHashCache`，[library_management_tab.dart:1833](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:1833) |
| 查看扫描失败文件及原因 | `_showFailedScanFilesDialog`，[library_management_tab.dart:1486](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:1486) |
| 查看检测到的目录变化并“扫描变化” | `_scanAllDetectedChanges`，[library_management_tab.dart:2521](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:2521) |
| 忽略已检测变化 | `ScanService.clearDetectedChanges`，[library_management_tab.dart:2537](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:2537) |

Next 任务查询不能读取 `ScanService.failedScanFiles`、`detectedChanges` 或它的扫描消息。

### 10. 手动刷新 Classic 海报墙数据及无效路径缓存

- **界面**：本地／WebDAV／SMB 海报墙同步按钮、下拉刷新。
- **Classic 方法**：`_sync` 调用 `WatchHistoryProvider.clearInvalidPathCache`、`refresh`，见 [adaptive_media_collection_view.dart:725](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_media_collection_view.dart:725)。
- **缺口**：`state.query` 读取当前内存；`media.library.import_history` 导入数据库记录到 Next。两者都没有执行这一刷新和路径重新验证流程。

### 11. 同一 Jellyfin／Emby 配置的多地址管理

分别缺失：新增地址、删除地址、选择已有地址、调整地址优先级。

Classic 调用见 [network_media_server_dialog.dart:490](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:490)、[524](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:524)、[551](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:551)、[581](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:581)。

`media.sources.update` 只能更新当前地址，没有 `addressId`、地址列表或优先级参数，见 [service.dart:295](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:295)。

### 12. 详情页社区评论和标签检索

- **评论**：查看、加载更多、失败重试；Classic 实际请求 `BangumiApiService.getSubjectComments`，见 [bangumi_comments_widget.dart:87](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_comments_widget.dart:87)、[243](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_comments_widget.dart:243)。
- **标签**：点击标签、打开标签检索、修改筛选并查询；入口见 [anime_detail_page.dart:3529](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3529)，实际进入 `SearchService.searchAnimeByTags/searchAnimeAdvanced`，见 [tag_search_controller.dart:34](~/Desktop/NipaPlay-Reload/lib/search/tag_search_controller.dart:34)。
- **缺口**：没有社区评论读取能力，也没有标签／高级检索参数。`accounts.collections.get` 读取自己的收藏短评，不能读取社区评论。

### 13. 修改或恢复详情背景图

- **界面**：沉浸详情“更多→修改背景图”；填写 HTTP(S) URL，留空恢复海报背景。
- **Classic 方法**：`_changeImmersiveBackdrop` → `BangumiService.updateBackgroundImageUrl`，见 [anime_detail_page.dart:3060](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3060)。
- **缺口**：`media.metadata.override` 没有 `backgroundImageUrl` 字段；其 `imageUrl` 是封面，不是背景图。

### 14. 海报墙和库管理的界面状态设置

下列状态没有 Action 或注册设置：

- 选择并持久化具体媒体库分区：[adaptive_media_library_page.dart:135](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_media_library_page.dart:135)。
- 拖动调整分区顺序并保存：[adaptive_media_library_controls.dart:912](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_media_library_controls.dart:912)。
- 切换库管理图标／列表布局：[library_management_tab.dart:2701](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:2701)。
- 改变并保存本地文件排序的六种选项：[library_management_tab.dart:192](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:192)、[1244](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:1244)。
- 保存 Jellyfin／Emby 全局及分库排序：[network_media_library_view.dart:2394](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:2394)。
- 持久化共享库、网络库“只看未观看”开关：[shared_remote_library_view.dart:72](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:72)、[network_media_library_view.dart:267](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:267)。

Agent 可以排列自己取得的查询结果，但不能据此改变这些 Classic 界面状态。

### 15. Android 存储辅助操作

分别缺失：

- 重置自定义存储路径：`_clearCustomStoragePath` → `StorageService.clearCustomStoragePath`，[library_management_tab.dart:1541](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:1541)。
- 检查存储权限、发起申请权限：[library_management_tab.dart:1582](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:1582)。
- 目录访问失败后打开系统设置：[library_management_tab.dart:607](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:607)。

### 16. 发现共享客户端

- **界面**：“切换共享客户端→扫描局域网／扫码连接”，见 [shared_remote_host_selection_sheet.dart:250](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart:250)。
- **Classic**：局域网发现、停止／重新扫描、从结果添加主机，见 [shared_remote_lan_scan_dialog.dart:149](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart:149)；扫码入口见 [shared_remote_host_selection_sheet.dart:620](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart:620)。
- **缺口**：`media.sources.add` 可以添加已知地址，但没有上述发现或扫码流程。

### 17. 操作已打开的详情界面

缺少直接关闭详情／评论面板、执行 Escape 语义、切换详情中的剧集正倒序的能力。

Classic 见 [anime_detail_page.dart:2858](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:2858)、[3119](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3119)。Next 的 `ui.open` 只有页面、实体、路径三个目标，没有关闭或详情控件操作参数。查询返回数据可以排序，但不能改变已经打开的详情列表。

## 2. 部分覆盖

| 操作 | 已有能力 | 具体缺口及依据 |
|---|---|---|
| **重新手动匹配已有 Classic 匹配的文件** | `media.metadata.search/get`、`media.identity.bind_batch` | Classic 手动选择后可直接覆盖原匹配字段，[library_management_tab.dart:4661](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4661)。Next 投影遇到不同的完整 Classic 匹配会返回冲突，[classic_projection.dart:182](~/Desktop/NipaPlay-Reload/lib/next/media/classic_projection.dart:182)。因此能建立新匹配，不保证能纠正已有 Classic 错配。 |
| **清除单文件扫描匹配；清除整部番剧所有匹配** | `media.identity.unbind_batch` | Classic 单文件清除显示信息并保留进度，[library_management_tab.dart:4731](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4731)；整部番剧调用 `clearMatchInfoByAnimeId`，[anime_detail_page.dart:3650](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3650)。Next 排除 `source='classic_match'` 的绑定，只撤销显式绑定，[identity_store.dart:1377](~/Desktop/NipaPlay-Reload/lib/next/media/identity_store.dart:1377)，并恢复投影前字段，不能清除所有独立 Classic 匹配。 |
| **扫描／重新扫描本地目录并识别** | `media.library.scan`＋哈希、搜索、绑定能力 | Agent 可以组合原语完成部分识别，但 `scan` 本身只索引，不调用 Classic 识别流程，[media_capability.dart:334](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:334)。Classic 调用 `ConcurrentVideoProcessor.processVideoPaths`，并支持智能变化检测和 `skipPreviouslyMatchedUnwatched`，[scan_service.dart:917](~/Desktop/NipaPlay-Reload/lib/services/scan_service.dart:917)。这些扫描语义和状态未覆盖；SAF／Harmony URI 也被 Next 原生路径检查排除。 |
| **WebDAV／SMB 文件夹自动刮削** | `media.sources.browse/sync`、元数据搜索、`bind_batch` | Classic `_scrapeRemoteFiles` 探测远程视频、调用匹配服务、写历史并迁移已清除旧路径的进度，[library_management_tab.dart:5825](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:5825)。Next 来源同步只索引；`media.hash.match` 要求本机文件位置，[media_service.dart:207](~/Desktop/NipaPlay-Reload/lib/next/media/media_service.dart:207)。能显式指定远程匹配，缺少同等远程字节匹配、进度迁移流程。 |
| **目录批量匹配：包含子目录、勾选文件／剧集、拖动映射顺序** | `media.files.list`、`media.sources.browse`、`media.metadata.get`、`bind_batch` | 显式 `entries` 可以表达所选映射，并非缺少批量能力。但 Classic 会从已清除旧路径迁移进度并删除该旧记录，[library_management_tab.dart:4365](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4365)；Next 新历史投影初始化进度为零，不执行迁移，[classic_projection.dart:225](~/Desktop/NipaPlay-Reload/lib/next/media/classic_projection.dart:225)。另 `media.files.list(root)` 不返回 `.3gp`、`.m2ts`，而 Classic 批量匹配包含它们，[library_management_tab.dart:201](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:201)。 |
| **浏览本地库管理目录树、非视频文件及当前层目录** | `media.files.list`、`state.query(library.files)` | Classic 枚举当前目录的文件系统条目，[library_management_tab.dart:2963](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:2963)。Next `files.list(root)` 只返回递归视频文件，没有目录行或普通非视频文件，[media_service.dart:179](~/Desktop/NipaPlay-Reload/lib/next/media/media_service.dart:179)。已索引视图不能补齐未索引目录树。 |
| **打开海报卡片详情，并影响 NEW／最近打开排序** | `ui.open` | Classic 点击卡片记录打开时间并清除 NEW 基线，[adaptive_media_collection_view.dart:781](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_media_collection_view.dart:781)。Next 直接调用 `ThemedAnimeDetail.show`，[classic_ui_open.dart:68](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_ui_open.dart:68)，绕过这些副作用。查询视图也没有首次发现时间或最近打开时间，不能还原综合／最近打开排序。 |
| **打开自定义、共享或媒体服务器详情** | `ui.open`、元数据与来源查询 | `ui.open(entityId)` 要求唯一已接受的正数弹弹play作品身份，[ui_open.dart:153](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:153)。Classic 支持负数自定义番剧，以及带共享剧集／播放上下文的详情。查询数据可以覆盖一部分，但不能保证打开同一个详情及来源上下文。 |
| **远程库“只看未观看”** | `media.sources.browse/query`、历史视图 | Classic 依据服务器项目的 `isPlayed` 过滤，[network_media_library_view.dart:238](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:238)。Next `serverMetadata` 白名单没有 `UserData`／已看状态，[metadata.dart:9](~/Desktop/NipaPlay-Reload/lib/next/media_sources/metadata.dart:9)。本机历史不能代表服务器账户全部已看状态。 |
| **查看完整详情元数据** | `media.metadata.get`、库与来源查询 | 能读取标题、简介、封面、剧集等。Next Bangumi provider 的转换没有保留 Classic 详情中的标签、评分等全部字段，[providers.dart:156](~/Desktop/NipaPlay-Reload/lib/next/media/providers.dart:156)；Classic 库查询主要是摘要和文件记录，也不是完整 `BangumiAnime` 视图。 |
| **服务器设置中的转码开关、默认画质；播放前选择 Emby 版本／音轨／字幕** | `playback.stream_options/select_stream` | 可以在当前播放会话中选择并保存转码默认值。但 `select_stream` 要求已有视频，[classic_playback_controls.dart:281](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_playback_controls.dart:281)。Classic 能在服务器设置里独立配置，以及在详情页播放前打开选择器，[network_media_server_dialog.dart:1194](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:1194)、[media_server_detail_page.dart:488](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:488)。 |
| **详情页一次提交评分、收藏、短评、进度，并同步两个账户** | `accounts.collections.update`、`accounts.episodes.update` | 各账户的业务写入可分别组合完成，包括批量剧集状态；但没有调用 Classic 详情提交编排，也没有刷新已打开详情的本地状态。Classic 编排见 [anime_detail_page.dart:3775](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3775)。账户数据写入已覆盖，原界面同步行为部分覆盖。 |

## 3. 已覆盖：一行一个操作

以下均限定在上述缺口之外，不把“首次匹配”扩展成“能覆盖任何旧匹配”。

| 操作及 Classic 位置 | 对应能力 |
|---|---|
| 列出本地／WebDAV／SMB 已记录番剧，[unified_media_library_sections.dart:238](~/Desktop/NipaPlay-Reload/lib/app/unified_media_library_sections.dart:238) | `media.library.search`；`state.query` → `library.classic_series` |
| 按标题查找已记录番剧，[adaptive_media_collection_view.dart:638](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_media_collection_view.dart:638) | `media.library.search`；剧集标题可从 `library.classic_episodes` 查询 |
| 查看番剧已记录剧集及同集多个文件，[anime_detail_page.dart:1957](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1957) | `media.library.series`；`state.query` → `library.classic_episodes` |
| 查看文件观看进度、位置、时长和最后观看时间，[watch_history_page.dart:264](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/watch_history_page.dart:264) | `state.query` → `history.entries`、`library.classic_episodes` |
| 查看继续观看列表，[watch_history_provider.dart:93](~/Desktop/NipaPlay-Reload/lib/providers/watch_history_provider.dart:93) | `history.continue_watching`；同名视图 |
| 点击历史记录继续播放，[watch_history_page.dart:512](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/watch_history_page.dart:512) | `playback.open` |
| 点击库管理中的已知文件播放，[library_management_tab.dart:3040](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:3040) | `playback.open(path=...)` |
| 从详情选择某集播放，[anime_detail_page.dart:1019](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1019) | `playback.open`；同集多文件返回可执行选择 |
| 手动匹配对话框搜索番剧，[manual_danmaku_matcher.dart:27](~/Desktop/NipaPlay-Reload/lib/services/manual_danmaku_matcher.dart:27) | `media.metadata.search(provider=dandanplay)` |
| 手动匹配时取得候选作品的剧集目录，[manual_danmaku_matcher.dart:38](~/Desktop/NipaPlay-Reload/lib/services/manual_danmaku_matcher.dart:38) | `media.metadata.get(provider=dandanplay)` |
| 为没有冲突旧匹配的文件接受指定作品／剧集，[library_management_tab.dart:4628](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4628) | `media.identity.bind_batch`，弹弹play精确匹配可投影回 Classic |
| 表达批量勾选后、按指定顺序配对的文件与剧集，[batch_danmaku_dialog.dart:410](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/batch_danmaku_dialog.dart:410) | `media.identity.bind_batch(entries=...)` |
| 添加 WebDAV 来源并发起用户登录，[adaptive_add_media_flow.dart:95](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_add_media_flow.dart:95) | `media.sources.add`、`media.sources.login` |
| 修改 WebDAV 非秘密连接参数，[library_management_tab.dart:6441](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6441) | `media.sources.update` |
| 测试 WebDAV 连接，[library_management_tab.dart:6534](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6534) | `media.sources.check` |
| 删除 WebDAV 连接，[library_management_tab.dart:6498](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6498) | `media.sources.remove`；确认机制见风险项 |
| 添加 SMB 来源并发起用户登录，[adaptive_add_media_flow.dart:107](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_add_media_flow.dart:107) | `media.sources.add`、`media.sources.login` |
| 修改 SMB 主机、端口、域、名称、用户名，[library_management_tab.dart:452](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:452) | `media.sources.update` |
| 测试／刷新 SMB 连接，[library_management_tab.dart:6384](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6384) | `media.sources.check` |
| 删除 SMB 连接，[library_management_tab.dart:6350](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6350) | `media.sources.remove`；确认机制见风险项 |
| 浏览 WebDAV／SMB 指定目录并重新取目录内容，[library_management_tab.dart:2980](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:2980) | `media.sources.browse(parentId=...)` |
| 添加 Jellyfin／Emby 来源并发起用户登录，[adaptive_add_media_flow.dart:119](~/Desktop/NipaPlay-Reload/lib/media_library/adaptive_add_media_flow.dart:119) | `media.sources.add`、`media.sources.login` |
| 列出 Jellyfin／Emby 可用媒体库，[network_media_server_dialog.dart:941](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:941) | `media.sources.libraries` |
| 勾选并保存 Jellyfin／Emby 媒体库范围，[network_media_server_dialog.dart:621](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:621) | `media.sources.select` |
| 浏览 Jellyfin／Emby 媒体库及文件夹，[network_media_library_view.dart:2024](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:2024) | `media.sources.browse` |
| 查看服务器项目、季、剧集的实时元数据，[media_server_detail_page.dart:287](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:287) | `media.sources.query`、`media.sources.browse` |
| 刷新远程媒体内容，[network_media_library_view.dart:276](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:276) | 重调 `media.sources.libraries/browse/query` |
| 断开当前 Jellyfin／Emby 并移除该配置，[network_media_server_dialog.dart:613](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_server_dialog.dart:613) | `media.sources.remove`；底层同样调用 Classic `disconnect` |
| 添加已知地址的 NipaPlay 共享客户端，[shared_remote_host_selection_sheet.dart:559](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart:559) | `media.sources.add(type=nipaplay)` |
| 选择已有 NipaPlay 共享客户端，[shared_remote_host_selection_sheet.dart:242](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart:242) | 对目标调用 `media.sources.libraries/browse/check`，服务会 `setActiveHost` |
| 刷新共享番剧列表、读取指定番剧共享剧集，[shared_remote_library_view.dart:256](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:256) | `media.sources.libraries`、`media.sources.browse(parentId=animeId)` |
| 查看自己的收藏、评分、短评和收藏状态，[anime_detail_page.dart:745](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:745)、[851](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:851) | `accounts.collections.get` |
| 收藏／取消收藏弹弹play番剧，[anime_detail_page.dart:3556](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3556) | `accounts.collections.update` |
| 提交弹弹play评分，[anime_detail_page.dart:3858](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:3858) | `accounts.collections.update(provider=dandanplay)` |
| 修改 Bangumi 收藏状态、评分及自己的短评，[anime_detail_page.dart:1073](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1073) | `accounts.collections.update(provider=bangumi)` |
| 查看账户剧集已看状态，[anime_detail_page.dart:745](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:745) | `accounts.episodes.get` |
| 标记弹弹play剧集已看，[anime_detail_page.dart:2416](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:2416) | `accounts.episodes.update(state=2)` |
| 更新 Bangumi 已看剧集进度，[anime_detail_page.dart:1163](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1163) | 取得剧集 ID 后调用 `accounts.episodes.update` |
| 发起详情相关账户登录，由用户输入秘密，[manual_danmaku_matcher.dart:45](~/Desktop/NipaPlay-Reload/lib/services/manual_danmaku_matcher.dart:45) | `accounts.login` |
| 设置媒体库 NEW 标识是否显示，[appearance_settings_provider.dart:360](~/Desktop/NipaPlay-Reload/lib/providers/appearance_settings_provider.dart:360) | `settings.set/reset`：`appearance.showMediaLibraryNewBadge` |
| 设置跳过匹配、哈希失败后自动采用搜索首项 | `settings.set/reset`：`danmaku.skipMatching`、`danmaku.autoMatchFirstSearchResultOnHashFail`；注册见 [application_settings.dart:925](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:925) |
| 配置 WebDAV 快速入口的目录、排序、季目录规则、bgmid／tmdbid 匹配、剧集偏移及搜索规则 | `settings.set/reset`：相应 `webdavQuick.*`；复用 Classic provider setter，见 [classic_settings.dart:601](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:601) |

## 4. 反方向风险及额外行为

### 1. 删除连接的“确认”可以由 Agent 自行提供

Classic 删除 SMB／WebDAV 连接，必须取得确认对话框结果，见 [library_management_tab.dart:6350](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6350)、[6498](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6498)。

Next `media.sources.remove`：

- 未提供 `confirm:true` 时仅预览；
- 提供后立即调用服务删除；
- 没有检查确认是否来自用户，也不返回需要用户决定的 `NeedsDecision`。

执行分支见 [capability.dart:306](~/Desktop/NipaPlay-Reload/lib/next/media_sources/capability.dart:306)。Harness 的 `Effect.destructive` 是记录属性，执行路径未据此增加确认，见 [harness.dart:123](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/harness.dart:123)。

**代码层结论**：具备调用权限的 Agent 可以自行填入 `confirm:true`，绕过 Classic 的交互确认。外部 Agent 宿主是否另外要求用户批准，静态代码未证明。

### 2. 撤销 Next 匹配并恢复 Classic 字段，不要求确认

Classic 的单文件“移除扫描结果”和整部番剧清理均有确认界面。Next `media.identity.unbind_batch` 是 `Effect.write`，没有确认参数，见 [media_capability.dart:496](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:496)。

对于 Next 曾成功投影的匹配，撤销可以直接恢复 Classic 的投影前字段，见 [classic_projection.dart:111](~/Desktop/NipaPlay-Reload/lib/next/media/classic_projection.dart:111)。

**边界**：这不是任意删除历史或任意清除 Classic 匹配。独立 Classic 匹配被排除，投影后被修改的字段也会冲突保护。但对它能够撤销的匹配，确实没有 Classic 式确认步骤。

### 3. Next 允许 Classic 批量匹配界面不能表达的多剧集文件关系

Classic 批量匹配要求所选文件数与剧集数相等，每个文件配一个剧集，见 [batch_danmaku_dialog.dart:417](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/batch_danmaku_dialog.dart:417)。

Next `bind_batch(kind=file)` 允许一个文件关联多个 `episodeRefs`，并允许时间区间参数，见 [media_capability.dart:406](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:406)。

这是有代码依据的能力扩展。它不会自动成为同等的 Classic 匹配：Classic 投影只处理单个精确弹弹play关系，见 [identity_store.dart:1583](~/Desktop/NipaPlay-Reload/lib/next/media/identity_store.dart:1583)。不能把“Next 接受成功”解释成“Classic 已接受相同关系”。

## 5. 没能审完的部分与待确认项

- **运行时和平台原生实现未验证**：Android SAF 授权、Harmony 目录访问、iOS 文件选择、各平台实际窗口和服务器响应。已审 Dart 入口和 Next 路径限制；没有运行或构建。
- **Emby 播放前选择的全部偏好继承规则未审完**：已确认 Classic 有播放前选择入口、Next 对应能力依赖当前会话；系列级偏好、轨道指纹继承和每种版本切换效果没有完整追到所有底层分支。
- **待确认：“清除评分”是否是有效业务操作。** Classic 对话框有“清除评分”，但选择零分后提交按钮禁用，且详情提交会把非 1–10 分转换为不提交评分。见 [bangumi_collection_dialog.dart:683](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/bangumi_collection_dialog.dart:683)、[anime_detail_page.dart:1106](~/Desktop/NipaPlay-Reload/lib/pages/anime_detail_page.dart:1106)。因此没有直接把 Next 的评分下限 1 判成缺失。
- **待确认：Web 客户端的 Next 能力可用范围。** `ServiceProvider` 在 `!kIsWeb` 分支创建 NextCore，见 [service_provider.dart:40](~/Desktop/NipaPlay-Reload/lib/providers/service_provider.dart:40)。本报告不能把原生宿主中已注册的覆盖项推广到 Web 客户端。
- **未对其他块做完整审计**：播放内控制、下载、弹幕轨道、账户全流程、远程访问配置、备份。只读取它们与本块操作直接相连的接口，未据此给其他块下覆盖结论。