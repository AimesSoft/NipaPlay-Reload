# NipaPlay 能力层覆盖调研（X51）

日期：2026-10-13。worktree：`~/Desktop/nipaplay-next-wt/x51-coverage`；分支：`next/x51-coverage`；代码基线：`c1b179e9cd74d8445cb971a0dc8b9026d4a3a02d`。

## 结论与边界

能力层已经覆盖播放打开/暂停/定位、音轨与字幕轨、倍速、弹幕参数、截图/GIF、桌面窗口、下载管理、媒体服务器、收藏评分、备份、插件和基本日志。主要短板是**没有外部身份的自定义入库、播放器真实状态与内容读取、持久附件的撤销、后台任务控制、无界面后端覆盖，以及跨设备可调用范围**。不能把“注册了 Action”“实际宿主支持它”“Mesh 允许调用它”视为同一件事。

只做工具调研，没有评估 Next 页面布局或交互完成度。`ui.*` 仅作为已注册工具对照；涉及图片/字幕等的是身体的数据控制能力。本次没有改变代码、构建、启动应用、联网调用服务或执行 Flutter 测试。只读取仓库源文件，没有读取用户偏好、数据库、日志、保险库、endpoint 文件或登录态；证据不含秘密值或带认证链接。

先读了任务指定的七份文档，随后检查应用入口、领域服务、provider、播放器抽象、Action schema、执行实现和宿主组装。静态目录核对得到 **GUI 宿主 196 个 Action ID；无界面宿主注册其中 89 个；GUI 目录中 158 个通过 Mesh 的 ID 白名单**。这些是当前代码的静态组装数量，**不是运行中的 `nipa list` 实测**；平台、挂载状态、权限、凭据和原生库会继续限制执行。完整逐 Action 清单见 [actions.tsv](../evidence/x51/actions.tsv)，复核方法见 [证据说明](../evidence/x51/README.md)。

判定标签：**C = 读代码确认**（入口/schema/组装或实现事实）；**I = 推断**（真实任务影响、可能出现的用户结果）；**P = 建议**（新契约与工作量估计，尚未实现）。以下未特别标注的“有/无/部分”均为 C；“无”指当前注册和实现中未找到相应领域入口，不声称 Agent 通过 shell、外部软件或自行编写 harness 工具永远做不到。

## 功能与控制总表

“应用”含 Classic 用户流程及已有服务；“能力层”指带界面宿主；“无界面”指 `HeadlessCore`。✓=有，△=部分/依赖条件，—=没有；“不适用”表示宿主没有该身体部件。所有行均附应用与能力实现路径。表中的 `settings` 指 `settings.describe/get/set/reset/history`，不是任意原始键写入。

| 功能或控制项 | 应用里有没有 | 能力层有没有 | 无界面版有没有 | 代码证据（应用；Action/组装） |
|---|---|---|---|---|
| 本地文件播放、续播、暂停、绝对/相对定位、上一/下一集 | ✓ | ✓ `playback.open/state/set_paused/seek/switch_episode` | 不适用，无播放器 | `lib/services/playback_service.dart`；`lib/next/capabilities/playback_capability.dart`、`video_player_state_port.dart` |
| 当前播放是否真正就绪、缓冲、失败原因与重载 | ✓ 内核与状态有事实/恢复逻辑 | △ 快照只有粗粒度 status、位置等，没有 readiness/buffering/error/retry | 不适用 | `lib/player_abstraction/abstract_player.dart:33`；`lib/next/capabilities/media_models.dart:263`；`lib/utils/video_player_state/video_player_state_playback_controls.dart:630` |
| 倍速、音量、移动端亮度、音量增强 | ✓ | ✓ `settings`：`playback.rate`、`player.volume/brightness/volumeBoost`；`playback.levels` | 不适用；设置未注册 | `lib/utils/video_player_state/video_player_state_preferences.dart`；`lib/next/settings/application_settings.dart:650`；`local_playback_operations.dart:351` |
| 内嵌/服务器音轨与字幕轨读取及切换 | ✓ | ✓ `playback.tracks/select_track` | 不适用；文件字幕事实仍有 | `lib/themes/nipaplay/widgets/audio_tracks_menu.dart`、`subtitle_tracks_menu.dart`；`lib/next/capabilities/classic_playback_controls.dart:75` |
| 字幕运行时挂载、卸载 | ✓ | ✓ `playback.load_subtitle/remove_subtitle` | 不适用 | `lib/services/subtitle_service.dart`；`lib/next/capabilities/playback_controls_capability.dart:46` |
| 每文件持久字幕导入、默认选择、来源/语言/可用状态 | ✓，Next 共用事实 | ✓ `subtitle.tracks/import/select` | ✓；嵌入轨探测需宿主 ffprobe，校验/默认选择算法与 GUI 有差异 | `lib/next/subtitles/capability.dart`、`library.dart`、`library_io.dart:92` |
| 持久字幕移除、修正语言/标题/来源、恢复“自动选择” | △ Classic 列表可移除/切换，Next 导入记录未有删除入口 | —；`select {trackId:null}` 是禁用，不是清除显式选择 | — | `lib/services/subtitle_service.dart`；`lib/next/subtitles/capability.dart:87`、`library.dart:415` |
| 字幕延迟、字号、颜色、对齐、字体与样式接管 | ✓ | ✓ `settings` 的 `subtitle.*` | — 设置未注册 | `lib/themes/nipaplay/widgets/subtitle_settings_menu.dart`；`lib/next/settings/application_settings.dart` |
| 正在显示/指定时段的字幕文本 | ✓ 字幕解析与渲染 | — 无结构化 cue/current-text 工具；截图只能间接观察 | — 无 cue 工具，可读附件后用外部解析器 | `lib/utils/subtitle_parser.dart`、`lib/services/subtitle_service.dart`；`lib/next/subtitles/capability.dart` |
| 画面比例、画质 shader/超分、硬解、缓存参数、内核 | ✓ | ✓ `settings`：`player.videoAspectMode/kernel/hwdecMode/anime4kProfile/crtProfile/erikaUpscalerMode` 等，平台/内核限制 | 不适用 | `lib/player_abstraction/player_factory.dart`；`lib/next/settings/application_settings.dart` |
| 逐帧前进/后退 | ✓ | —；只注册“显示逐帧按钮”设置 | 不适用 | `lib/player_abstraction/abstract_player.dart:167`、`lib/utils/video_player_state/video_player_state_playback_controls.dart:1643`；`lib/next/settings/application_settings.dart:530` |
| 章节列表、当前章节、按章节跳转 | ✓ | —；`chapterMarkersEnabled` 只控制标记，seek 不提供章节事实 | 不适用 | `lib/utils/video_player_state/video_player_state_chapters.dart:10`、`lib/themes/nipaplay/widgets/video_progress_bar.dart:749` |
| 播放列表的准确来源/顺序/当前项 | ✓ 多种来源 | △ 可以查询库/浏览来源并逐项 open，不能读当前播放器实际列表 | 不适用 | `lib/themes/nipaplay/widgets/playlist_menu.dart:74`、`lib/services/episode_navigation_service.dart`；`playback.state` 仅 canNext/canPrevious |
| 片头片尾识别结果、执行当前 skip | ✓ | △ 有 `player.introSkipEnabled`、`seek.skipSeconds`，没有识别段读取/skip Action | 不适用 | `lib/utils/video_player_state/video_player_state_intro_skip.dart`、`lib/themes/nipaplay/widgets/skip_button.dart`；`lib/next/settings/application_settings.dart` |
| 播放器截图/GIF、保存结果路径、弹幕是否实际包含 | ✓ | ✓ `playback.capture`；已有明确 danmakuRequested/Included/Reason | 不适用；可借 `program.run` 调 ffmpeg，须宿主授权 | `lib/utils/video_player_state/video_player_state_capture.dart`；`lib/next/capabilities/playback_controls_capability.dart:122`、`classic_playback_controls.dart:590` |
| 分享截图/GIF、导出文件至系统分享面板、复制到剪贴板 | ✓ | △ capture 有文件/部分平台保存目标，没有通用分享/clipboard Action | 不适用 | `lib/services/system_share_service.dart:13`、`clipboard_image_service.dart`、`photo_library_service.dart`；`lib/next/capabilities/playback_controls_capability.dart` |
| 外部播放器选择/探测、打开/关闭、遥测、暂停/定位 | ✓ | ✓ `playback.external_player_path/external/external_state`；遥测/控制依播放器 | 不适用 | `lib/services/external_player_console_service.dart`；`lib/next/capabilities/local_playback_operations.dart:257`、`playback_controls_capability.dart:100` |
| 外部播放器弹幕样式、偏移、规则和弹幕列表 | ✓ | ✓ `playback.external.danmaku_state/danmaku` | 不适用 | `lib/pages/external_player_console_page.dart`；`lib/next/capabilities/local_playback_operations.dart` |
| 内置播放器弹幕显示、透明度、字号、速度、区域、描边、合并、屏蔽规则、字体、渲染器 | ✓ | ✓ `settings`：`danmaku.*`，含 Titan 分项与运行时 manualOffset | 不适用；绑定设置仍可改 | `lib/providers/settings_provider.dart`；`lib/next/settings/application_settings.dart` |
| 弹幕来源搜索、剧集目录、解析、获取、导入、轨道绑定 | ✓ | ✓ `danmaku.sources/search/episodes/resolve/fetch/import/attach/tracks`；当前内建在线来源是弹弹play | △ 同名 Action 在，但只装 LocalDanmakuSource，无在线搜索/下载后端 | `lib/next/danmaku/runtime.dart:94`、`capability.dart`；`lib/next/headless/core.dart:164` |
| 弹幕逐轨开关、偏移、显示折叠、撤销绑定、对齐分析 | ✓ | ✓ `danmaku.update/detach/analyze_alignment`；旧 align 系列仅恢复旧任务 | ✓ 持久绑定；无 current-player 目标 | `lib/themes/nipaplay/widgets/danmaku_tracks_menu.dart`；`lib/next/danmaku/capability.dart:399`、`lib/next/headless/ports.dart:34` |
| 内部播放弹幕文本列表/时段内容、单条屏蔽/规则 | ✓ Classic 列表与规则 | △ blockWords 设置可控制规则，tracks/热度/导出不能直接分页读当前有效条目；外部控制台有列表 | △ 缓存导出/附件读取可组合，没有统一 entries 工具 | `lib/themes/nipaplay/widgets/danmaku_list_menu.dart:465`；`lib/next/danmaku/capability.dart:324`；`local_playback_operations.dart` |
| 在线发送弹幕 | ✓ | ✓ `danmaku.send`，要求已识别内部播放+用户登录 | 不适用，无播放宿主 | `lib/services/danmaku_matching_service.dart`；`lib/next/capabilities/local_playback_operations.dart:284` |
| 弹幕防剧透 AI 开关/非秘密配置 | ✓ | ✓ `settings`；秘密仍由用户输入 | — 设置未注册/没有过滤播放器 | `lib/services/danmaku_spoiler_filter_service.dart`；`lib/next/settings/application_settings.dart` |
| 启动清空 Classic 弹幕缓存、立即清空 Classic 弹幕缓存/图片缓存 | ✓ | —；Next cache_prune/delete 不等于 Classic clearAllCache/ImageCacheManager | — 同样缺缓存分类工具 | `lib/settings/pages/storage_settings_content.dart:251`；`lib/services/danmaku_cache_manager.dart:54`、`lib/utils/image_cache_manager.dart` |
| Next 弹幕缓存预算清理、单池删除、JSON 导出 | ✓ 领域服务 | ✓ `danmaku.cache_prune/cache_delete/export` | ✓；导出目录只允许 data/exports | `lib/next/danmaku/capability.dart:452`；`lib/next/headless/core.dart:170` |
| 全屏、置顶、独立播放器/画中画、显示/隐藏、托盘、退出 | ✓ | ✓ `window.state/control`、`app.quit`；移动端/独立窗有平台限制 | 不适用；没有退出/宿主关机 Action | `lib/services/desktop_player_window_service.dart`、`desktop_exit_handler.dart`；`lib/next/capabilities/local_playback_operations.dart:379` |
| 任意窗口位置/尺寸读取与设置 | ✓ 主窗用户可拖动/缩放 | △ state 有主窗 size；只有 fit_video/最大化，没有当前位置、精确 set_bounds | 不适用 | `lib/next/capabilities/local_playback_operations.dart:105`、`lib/themes/nipaplay/widgets/nipaplay_window.dart` |
| 通知/提示发送、撤回、投递状态、免打扰 | △ Classic Snackbar/启动提示；未发现通用 OS 通知服务 | △ ui.present/agent.wake 可呈现或唤醒，非通知生命周期工具 | △ 后续可转交对话；无 OS 通知宿主 | `lib/themes/nipaplay/widgets/startup_notification_controller.dart:61`、`blur_snackbar.dart`；`lib/next/followups/service.dart` |
| 注册/删除本地媒体目录、清理缺失目录 | ✓ | ✓ `media.library.roots.list/add/remove/cleanup` | △ list/add/remove，另一个实现；无 cleanup | `lib/services/scan_service.dart:1006`；`lib/next/capabilities/local_library_operations.dart`、`lib/next/headless/library_roots.dart` |
| Classic 自动识别扫描、读取失败文件 | ✓ | ✓ `media.library.scan_classic`、roots.list；长调用同步等待，不是 task | — | `lib/services/scan_service.dart:779`；`lib/next/capabilities/local_library_operations.dart:179` |
| Next 文件索引扫描、文件枚举、哈希候选、作品/剧集绑定与解绑 | ✓ | ✓ `media.library.scan/files.list/hash.match/identity.bind_batch/unbind_batch` | △ 索引/绑定有；hash.match 无弹弹play provider | `lib/next/media/media_capability.dart:333`、`media_service.dart:410`；`lib/next/headless/core.dart:111` |
| 启动自动扫描开关、附件自动探测开关 | △ 有自动行为；未发现现成可配置开关 | — 不能关闭启动 refresh、30 秒同名弹幕/字幕 reconcile | — 附件 reconcile 同样自动 | `lib/services/scan_service.dart:229`；`lib/next/danmaku/sidecar.dart:89`、`lib/next/subtitles/library.dart:84`、`library_io.dart:62` |
| 自动匹配弹幕/加载策略/下载完成自动入库开关 | ✓ | ✓ `danmaku.autoLoadStrategy/skipMatching/autoMatchFirstSearchResultOnHashFail`、`download.autoScanCompletedTasks` | △ 无这些设置；下载文件自动索引，未识别则 pending | `lib/providers/settings_provider.dart`；`lib/next/settings/application_settings.dart:1023`、`download_settings.dart`；`lib/next/headless/downloads.dart:324` |
| 没有平台身份的自定义作品、季/集、文件对应关系 | ✓ 自定义媒体信息，负数 Classic animeId | — 没有本地-only 实体创建；bind_batch 的目录模式要可获取的 workRef，direct 模式要已存在实体 | — | `lib/themes/nipaplay/widgets/custom_media_info_dialog.dart:975`；`lib/next/media/media_capability.dart:405` |
| 元数据查询/批量查询、快照导入、来源事实、标题/简介修正 | ✓ | ✓ `media.metadata.*`，保留来源与编辑历史 | △ 搜索/get 默认仅 Bangumi；可导入已有身份快照和修改文字 | `lib/next/media/media_runtime.dart:55`、`media_capability.dart`；`lib/next/headless/core.dart:112` |
| 海报/背景/Logo/剧集截图独立设置和完整情况读取 | ✓ 领域数据 | ✓ `media.artwork.set/metadata.ui_facts` | △ 可以交入公开 URL/本地图片；NoVault 不能读取 TMDB 保险库凭据 | `lib/next/ui_data/capability.dart:46`、`metadata_facts.dart:169`；`lib/next/headless/ports.dart:64` |
| 撤销某一种图片覆盖，恢复平台图片 | △ 底层编辑存储能 clear | — artwork.set 只能 persistent；metadata.override 字段枚举不含 artwork.* | — | `lib/next/ui_data/metadata_facts.dart:192`；`lib/next/media/media_capability.dart:620` |
| 种子/磁力预览、添加、选文件、暂停/恢复、读进度/磁盘空间、移除任务 | ✓ | ✓ `download.preview/add/select_files/set_paused/read/remove`，控制支持 jobIds 批量 | ✓；原生库/宿主网络配置前提 | `lib/services/torrent_download_service.dart`；`lib/next/capabilities/download_capability.dart`、`lib/next/headless/downloads.dart` |
| 删除下载磁盘文件 | ✓ | ✓ `download.delete`，磁盘删除经过用户决定 | — 此 ID 被过滤；但 `media.mesh_files.delete/confirm` 可以操作进程可写路径 | `lib/next/tasks/user_consent.dart`；`lib/next/headless/ports.dart:62`、`lib/next/mesh/files.dart:168` |
| 边下边播/已完成文件播放、手动入库、最近下载目录管理 | ✓ | ✓ `download.play/import/directories/forget_directories`，read 区分 playable/streamable/pending | △ 无 play/forget_directories；import 只索引；directories 最近列表为空 | `lib/next/capabilities/download_playback_capability.dart`、`download_metadata_capability.dart`；`lib/next/headless/downloads.dart:278` |
| 下载带宽限制、做种策略、文件优先级、后台并发预算 | △ 有引擎/固定调度；未发现用户可调整的普通限速/优先级 API | — 不能调；read 的健康事实/速率不等于控制 | — 宿主 download.json 仅网络初始化配置，非动态预算工具 | `lib/next/downloads/README.md`、`lib/services/concurrent_video_processor.dart:29`、`rust/src/api/torrent.rs`、`lib/next/chat/helpers.dart:15` |
| 统一媒体服务器 WebDAV/SMB/Jellyfin/Emby/共享/弹弹play远程的配置、登录、浏览、扫描 | ✓ | ✓ `media.sources.*`；登录窗口/Quick Connect 不接受密码参数 | — 整族未组装 | `lib/media_library/adaptive_add_media_flow.dart`、`lib/services/*service.dart`；`lib/next/media_sources/capability.dart`、`lib/next/headless/core.dart:258` |
| 服务器备用地址、选择的库、排序、共享端管理目录/连接 | ✓ | ✓ `media.sources.addresses/select/sort/remote_admin.*` | — | `lib/services/multi_address_server_service.dart`、`lib/providers/shared_remote_library_provider.dart`；`lib/next/media_sources/remote_admin.dart:30` |
| LAN 发现共享 NipaPlay 主机 | ✓ | — media.sources.add 需要已知地址；Mesh 自动发现是另一协议 | △ Mesh 有发现，不是 Classic LAN 来源发现 | `lib/services/nipaplay_lan_discovery.dart`、`lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart`；`lib/next/media_sources/capability.dart:198` |
| 多端 WebDAV 增量同步配置、登录、启停、测试、立即同步 | ✓ | ✓ `sync.status/configure/login/enable/test/run`、sync 设置 | — | `lib/services/auto_sync_service.dart`；`lib/next/media_sources/sync.dart:230` |
| 本地观看历史、继续观看、标记看过/未看、删除记录 | ✓ | ✓ `history.continue_watching/mark_watched_batch/remove`；多集文件有约束 | △ 无 Classic 历史 Action；合并进度可用 media.library.progress | `lib/providers/watch_history_provider.dart`；`lib/next/capabilities/history_capability.dart`、`watched_history.dart`、`local_library_operations.dart:225` |
| 弹弹play/Bangumi 登录态、收藏、评分/评论、单集观看状态、同步 | ✓ | ✓ `accounts.*`，支持集合/剧集批量；对外评论不是缺口 | — 无账号业务宿主，Mesh 身份用的 token 不等于账号服务 | `lib/pages/account/account_controller.dart`；`lib/next/accounts/capability.dart`、`service.dart:206`；`lib/next/headless/core.dart:133` |
| 搜索/标签/排行/放送日历/推荐/Classic 首页事实 | ✓ | ✓ `discover.*`，搜索和排行有 batch | —；home/refresh 还依赖 mounted Classic home | `lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart`、`lib/services/search_service.dart`；`lib/next/capabilities/discover_capability.dart:42` |
| 应用统一 HTTP 代理、播放器 UA、GitHub 代理 | ✓ | ✓ `network.httpProxy/player.customUserAgent/plugins.githubProxyUrl` | — 无对应设置；程序可用宿主网络环境但没有统一控制 | `lib/services/app_http_proxy.dart`；`lib/next/settings/classic_settings.dart:517`、`application_settings.dart:1110` |
| 媒体服务器 API/图片/同步的独立 UA | ✓ | — `media_server_connection_user_agent_v1` 未注册 | — 无媒体来源后端 | `lib/services/media_server_transport.dart:38`、`lib/settings/widgets/media_server_connection_user_agent_setting.dart` |
| 官方弹弹play网关模式/故障转移状态、连通性检测、Bangumi API 地址 | ✓ | — 无 network routing/diagnostics 工具与设置 | — 默认 Bangumi transport 固定地址 | `lib/utils/network_settings.dart`、`lib/services/nipaplay_server_router.dart`、`server_connectivity_service.dart`；`lib/next/settings/classic_settings.dart` |
| 无效证书全局允许 | ✓ | ✓ `network.allowInvalidCertificates` | —；Mesh 自己仍使用 mTLS 验证 | `lib/providers/developer_options_provider.dart`；`lib/next/settings/classic_settings.dart` |
| 应用存储目录/各缓存用量/剩余空间/迁移状态 | ✓ 服务与开发者页 | △ download.read 有任务盘 free bytes、Mesh 自描述部分存储；没有统一 status/usage/migrate | △ 自描述含 library/download storage；非任意卷的查询 | `lib/utils/storage_service.dart`、`lib/settings/pages/developer_options_settings_content.dart:727`；`lib/next/headless/core.dart:147`、`lib/next/downloads/builtin_download_backend.dart` |
| Linux 存储迁移/误迁移个人文件恢复 | ✓ | — | — | `lib/settings/pages/developer_options_settings_content.dart:635`、`:782`、`lib/utils/linux_storage_migration.dart` |
| 日志收集开关、内存日志读/导出/清空、日志目录 | ✓ | ✓ diagnostics settings；`diagnostics.logs/export/clear/directory`，支持 operations 批量 | — 未组装；journal/任务事实仍可读 | `lib/services/debug_log_service.dart`、`file_log_service.dart`；`lib/next/settings/operations.dart:310` |
| 播放器详细媒体/解码信息、资源指标、构建/依赖版本、持久文件日志查询 | ✓ Classic 信息菜单与开发者页 | △ app.instance/日志有部分；没有结构化完整诊断工具，showSystemResources 只是显示开关 | △ app.instance/任务，不是完整宿主诊断 | `lib/themes/nipaplay/widgets/playback_info_menu.dart:158`、`system_resource_display.dart`、`lib/settings/pages/developer_options_settings_content.dart:459` |
| 将日志上传生成分享链接 | ✓ | — diagnostics.export 只写本地文件，不能上传 | — | `lib/services/log_share_service.dart:48`、`lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:638` |
| 检查应用更新、读取发布说明、打开发布页 | ✓ | △ `general.autoCheckUpdates` 和 app.instance 有；没有立即检查/读最新结果/打开更新入口 | —；app.instance 只有宿主版本事实 | `lib/services/update_service.dart:37`、`lib/settings/pages/about_settings_content.dart`；`lib/next/settings/classic_settings.dart` |
| 应用自动安装更新 | — 当前更新流程是打开外部发布页 | — 不算“应用有、工具无” | — | `lib/settings/pages/about_settings_content.dart`、`lib/services/update_service.dart` |
| 完整/历史备份导出、预览、恢复 | ✓ | ✓ `backup.*`；不导出登录秘密，新登录不能从工具恢复 | — | `lib/services/full_backup_service.dart`、`backup_service.dart`；`lib/next/settings/operations.dart:39` |
| 插件市场、安装/更新/删除/启停/执行插件动作、非秘密配置 | ✓ | ✓ `plugins.*` 和动态 settings；支持 operations 批量 | — 插件宿主未组装 | `lib/plugins/plugin_service.dart`；`lib/next/settings/operations.dart:165`、`classic_settings.dart:802` |
| 设置读取/修改/重置/历史（含大部分 Classic 偏好） | ✓ | ✓ 物理键映射、平台可见性；仍有逐键缺口见后表 | △ 仅 mesh.addressCandidates、next.heroOpeningSeconds | `lib/utils/settings_storage.dart`；`lib/next/settings/registry.dart`；`lib/next/headless/core.dart:162`、`:252` |
| 任务查询/等待/取消、领域暂停/恢复 | ✓ | △ task.list/get/wait/cancel；download 可暂停/恢复，通用 task.pause/resume 没注册 | △ 同样缺通用 pause/resume | `packages/nipa_harness/lib/src/tasks/actions.dart:5`、`engine.dart:271`；`lib/next/capabilities/download_capability.dart` |
| 事件 hooks/后续/唤醒/定时程序/宿主帮手 | ✓ Next 基础设施 | △ 已有 4 种领域 hook 事件和任务条件；更多变化没有外部事件 | △ hooks/定时/转交有；无 chat/dispatch，宿主无对话执行 | `lib/next/harness_hooks.dart:32`、`followups/capability.dart`；`lib/next/headless/ports.dart:62` |
| Mesh 设备、自描述、远程调用、合并库/跨节点进度、分块读写/删除文件 | ✓ | ✓ mesh.*、media.library.readable/refresh/progress、media.mesh_files.* | ✓；文件父目录须存在，传输暂存/票据不跨重启 | `lib/next/mesh/runtime.dart`、`library_capability.dart`、`files.dart`；`lib/next/headless/core.dart` |
| Mesh 远程改设置、控制窗口/退出、读诊断/备份/插件、state.describe | ✓ 本机工具有这些 | △ 本机有，Mesh 白名单不放行；部分是刻意边界 | △ 目标还受自身目录限制；无远程 settings.set/reset | `lib/next/mesh/runtime.dart:19`；完整 allowlist 对照见 actions.tsv |
| 网络加入/签发者/监听/程序执行授权/Next 端点开关/用户输入登录秘密 | ✓ 宿主/用户 | — 刻意不作为 Agent 自授权设置；可发起已有登录窗口 | △ 由宿主文件/私有 vault 配置，无代理录入秘密工具 | `lib/next/settings/denylist.dart`、`lib/next/mesh/README.md`、`lib/next/headless/vault.dart` |

## 按真实任务影响排序的缺口与建议

P0 表示可能直接阻断“拿到片后能看/识别/修好”的任务；P1 表示完成与持续管理成本高；P2 表示低频控制与便利性。这里的优先级是 I，需主控选择真实任务实验。难度：小=已有服务适配/schema；中=跨域持久化/回执/事件接线；大=新后端、原生平台或数据生命周期设计。不是工期承诺。

### G01 · P0：无界面节点能下载，但不能完成同样的在线识别与资料/弹幕准备

- **缺什么（C）**：没有 media.sources、accounts、discover、sync、Classic settings/operations；metadata 默认只装 Bangumi，danmaku 只装 local。`media.hash.match` 虽在目录中，`MediaService.matchHashes` 会因缺弹弹play provider 报 unavailable。`media.artwork.set` 仍可交入图片，不能把 NoVault 理解为图片能力全无。
- **代码**：`lib/next/headless/core.dart:111`、`:164`、`:258`；`lib/next/headless/ports.dart:64`；GUI 对照 `lib/next/media/media_runtime.dart:55`、`lib/next/danmaku/runtime.dart:94`。
- **建议（P）**：先增加 `app.capabilities {}` → `{host,features:[{id,supported,reason,requiredHostSetup}],providers,sources}`；为现有 `media.metadata.*`、`media.hash.match`、`danmaku.*` 接入同一网关/客户端抽象与宿主保险库引用，输入输出保持现有契约。再按任务需要复用 `media.sources.*`，不能另写上游签名客户端。GUI 与 headless 的 capability facts 应明确“只有导入/只有某 provider”。
- **难度**：大（平台无关客户端、凭据宿主、Classic 耦合拆接）；capability facts 中。
- **用户决定的效果**：读取公共元数据/弹幕通常没有删除或发布；媒体来源登录、秘密录入和网络权限仍由用户/宿主完成，不开放新秘密输入参数；付费来源按实际请求披露。
- **影响（I）**：远端第一集下载完后，Nipa 还得在 GUI 节点获取资料与弹幕，再搬附件；“同名工具可用”的目录会误导工作分配。

### G02 · P0：没有外部身份的本地作品/剧集无法直接建立目录

- **缺什么（C）**：Classic 的自定义媒体流程可以给文件命名、填资料、分配集号并保存历史；能力层没有 local-only create/link 原语。`bind_batch` 两种模式都要求真实外部 ref 或既有本地实体，不能用编造 provider ID 绕过。
- **代码**：`lib/themes/nipaplay/widgets/custom_media_info_dialog.dart:975`、`:1063`；`lib/next/media/media_capability.dart:405`；`lib/next/media/identity_store.dart`。
- **建议（P）**：`media.entities.put_batch {requestId,entries:[{kind,entityId?,parentId?,title,season?,number?,metadata?,fileIds?,reason}]}` → `{entries:[{entityId,created,linkedFiles,classicProjection}],conflicts}`；读取复用 identity.get/state.query；补 `media.entities.remove_batch {entityIds,mode:"unlink"|"remove_metadata",expectedRevision,reason}` → 预览影响与保留文件事实。更新保留观看进度和来源，Classic 负 ID 由宿主生成。
- **难度**：中到大（父子关系、重试幂等、Classic 投影和进度保留）。
- **用户决定的效果**：新建目录事实不删除文件；改写匹配/重编集号/移除元数据要预览旧关系与进度影响，明确需求后执行；不发布、不花钱。
- **影响（I）**：家庭视频、数据库未收录节目、特典或自编合集无法完成“整理一下”；外部身份不应成为入库的前提。

### G03 · P0：播放返回“已打开”之后，无法可靠判断成功或找出失败点

- **缺什么（C）**：`PlaybackSnapshot` 没有内核 readiness、buffering、mediaLoadError、实际 bufferedPosition/加载时间；没有明确 retry Action。open 返回当前快照，pause/seek 等也读即时快照，不是已观察到目标状态的证明。外部播放的顶层 position=0、paused=false、rate=1 是填充值，嵌套 external 才保留未知。
- **代码**：`lib/next/capabilities/playback_capability.dart:164`、`media_models.dart:263`、`video_player_state_port.dart:16`；`lib/player_abstraction/abstract_player.dart:33`；`lib/utils/video_player_state/video_player_state_playback_controls.dart:630`。
- **建议（P）**：扩展 `playback.state {}` → `{sessionId,fileId?,deviceId?,requestedState,observedState,ready,buffering,bufferedPositionMs,error:{code,retryable,recoveryAction}?,supportedControls,observedAt}`；`playback.wait {sessionId,until,timeoutMs}` → 有界观察结果；`playback.retry {sessionId,preservePosition:true}` → `{attempt,observedState,error}`。外部未知值统一 nullable，不暴露 authenticated actualUrl。
- **难度**：中（异步状态、外部 IPC、多内核适配）。
- **用户决定的效果**：重载会打断当前播放，应尊重用户已要求的修复意图；不删除、不发布、不花钱。
- **影响（I）**：Nipa 很难回答“为什么不能播”，也可能在 seek 尚未完成时继续截图或分析字幕。

### G04 · P0：字幕持久导入缺少改、删和清除显式默认选择

- **缺什么（C）**：有 tracks/import/select，但没有更正 language/title/source、移除导入关联、删除未引用副本、reset_selection。`playback.remove_subtitle` 处理 Classic 当前挂载列表，不删除 Next 的导入事实；`subtitle.select trackId:null` 固定禁用。
- **代码**：`lib/next/subtitles/capability.dart:10`、`:87`；`lib/next/subtitles/library.dart:323`、`:415`；`lib/next/capabilities/classic_playback_controls.dart:231`；`lib/next/subtitles/library_io.dart:139`。
- **建议（P）**：`subtitle.update {entries:[{fileId,trackId,patch:{language?,title?,source?},expectedRevision}]}`、`subtitle.remove {entries:[{fileId,trackId}],deleteUnreferencedCopy:false}`、`subtitle.reset_selection {fileIds}` → 每项 `{updated/removed,remainingTracks,selection,copyRetained,affectedFiles,error}`。默认只解绑，文件副本按全局引用判断；播放器与持久事实一起更新。
- **难度**：中（内容哈希共享、副本引用、GUI/headless 两实现）。
- **用户决定的效果**：删除导入副本是磁盘删除，必须明确区分；修改默认字幕可逆；不删除视频，不发布、不花钱。
- **影响（I）**：拿错语言/版本后 Nipa 只能继续叠加新字幕；卸载后重新发现旧导入的风险需真实播放验证。

### G05 · P1：后台扫描、元数据等任务无法统一暂停/恢复/管理容量

- **缺什么（C）**：TaskEngine 有 pause/resume 方法，TaskCapability 只注册 list/get/wait/cancel。Classic scan_classic 是等待整个扫描的同步 Action，不返回 jobId；roots.list 只能轮询状态。识别并发上限 4、帮手上限 2 写死；未发现动态下载限速/普通文件 priority API。
- **代码**：`packages/nipa_harness/lib/src/tasks/actions.dart:5`、`engine.dart:271`；`lib/next/capabilities/local_library_operations.dart:179`；`lib/services/concurrent_video_processor.dart:29`；`lib/next/chat/helpers.dart:15`；`lib/next/downloads/README.md`。
- **建议（P）**：`task.control {entries:[{jobId,command:"pause"|"resume"|"cancel",expectedRevision?}]}` → `{results:[{job,controlSupported,reason}]}`；scan_classic 改为提交现有任务系统的入口（原有名字可保留），结果 `{jobId}`，回执含逐文件结果。`task.resources {scope}` → 容量/占用；`settings` 补 `tasks.scanConcurrency/tasks.metadataConcurrency/tasks.helperConcurrency`。`download.limits {downloadBytesPerSecond?,uploadBytesPerSecond?,scope}` 只有后端可实现时注册支持，并返回 actual/appliesTo；不能伪造已限速。
- **难度**：通用控制中，扫描接入中到大；动态下载预算大，须查原生引擎能力。不能直接导出 engine.pause 并假设所有执行器已支持安全恢复。
- **用户决定的效果**：暂停/限速不删除、不发布；降低吞吐影响其他进行中任务；修改服务器限流约束不在本建议授权范围。
- **影响（I）**：用户说“先别扫了，马上看第一集”时，Nipa 不能精确控制全部后台工作或降低本机资源占用。

### G06 · P1：身体变化的事件不足，Agent 只能轮询

- **缺什么（C）**：hook 事件白名单只有 download.completed/file_completed、library.file_added、playback.started。没有播放 ended/failed/paused/seeked、settings.changed、字幕/弹幕事实变化、来源失联、盘空间阈值或扫描结果事件。内部 Listenable、数据库观察、uiData.changes 和 task.wait 已存在，不能说“完全没有事件”。
- **代码**：`lib/next/harness_hooks.dart:32`；`lib/next/next_runtime.dart:464`；`lib/next/ui_data/service.dart`；`lib/next/followups/service.dart`；`packages/nipa_harness/lib/src/tasks/engine.dart:313`。
- **建议（P）**：扩展同一事件管道，增加 `playback.ended/failed/state_changed`、`settings.changed`、`media.assets.changed`、`media.sources.state_changed`、`media.scan.completed`，统一 `{eventId,entityId,revision,occurredAt,changedFields,facts}`；`events.describe {}` → 名称/schema/可重放性；`events.wait {afterCursor,filters,timeoutMs}` → `{events,nextCursor,truncated}`；followup.when 复用同一 schema。高频 position 不逐帧叫醒 Nipa，按显式订阅阈值/状态变化触发。
- **难度**：中到大（持久游标、重启/去重、事件与来源一致性）。
- **用户决定的效果**：事件只报告事实；主动订阅/持续监控由用户需求决定，不能替用户建立新订阅；不删除、不发布、不花钱。
- **影响（I）**：后台出错不能及时触发修复；Agent 为等一个条件占用许多查询或定时脚本。

### G07 · P1：Nipa 能看到图片，却不能读“刚才那句话”和当前弹幕内容

- **缺什么（C）**：内部字幕/弹幕列表的文本没有统一结构化读取工具。danmaku.export 可导出绑定、外部控制台可列条目、media.library.readable 可给附件读取基础，但不等于当前渲染结果/可检索 cue API。
- **代码**：`lib/themes/nipaplay/widgets/danmaku_list_menu.dart:465`、`lib/utils/subtitle_parser.dart`；`lib/next/danmaku/capability.dart:324`、`:464`；`lib/next/subtitles/capability.dart`；`lib/next/ui_data/heat.dart`。
- **建议（P）**：`subtitle.cues {fileId?,trackId?,sessionId?,startMs,endMs,limit,cursor}` → `{cues:[{id,startMs,endMs,text,language,source}],nextCursor,unsupportedReason}`；`danmaku.entries {bindingIds?,sessionId?,startMs,endMs,view:"raw"|"mapped"|"display",filter,limit,cursor}` → 含来源时间、映射时间、轨道、文本、被过滤原因。位图字幕返回需 OCR/不可文本读取的明确事实；OCR 若另行添加，应标注观察方法。
- **难度**：字幕/缓存原文中，真正“正在渲染”与位图 OCR 大。
- **用户决定的效果**：本地读取不花钱；把内容送往外部翻译/OCR/AI 服务属于独立对外发送，必须按用户意图与实际费用决定。
- **影响（I）**：“解释刚才那句”“对齐这条弹幕”目前需要导出、外部解析或截图识别，调用链长且丢失时间轴上下文。

### G08 · P1：部分本机工具未开放远程，缺少支持范围和限制原因说明

- **缺什么（C）**：window.*、app.quit、diagnostics.*、backup.*、plugins.*、settings.set/reset、state.describe、chat/agent.dispatch 不在 Mesh 放行集合。远程 tools/list 已按同一白名单过滤，并非列出不可调用工具；缺的是跨宿主支持与限制原因的完整说明，以及其中可安全开放的远程能力。`playback.authorize_directory` 可调用也仍需要目标机的用户 picker。对照的是静态 ID allowlist，不是当前连接实测授权。
- **代码**：`lib/next/mesh/runtime.dart:19`、`:710`、`lib/next/mesh/capability.dart:26`；`packages/nipa_harness/lib/src/mcp/rpc.dart:14`；`lib/next/headless/core.dart:258`；`lib/next/settings/denylist.dart`。
- **建议（P）**：设备目录给每个 Action `{registered,remoteCallable,reason,effect,requiredUserPresence}`；先补只读 `state.describe`、脱敏 diagnostics.status/logs 及运行状态查询。需要远程写的非秘密设置由主控按 key/effect 决定，不盲目将整个 settings.set 加白。窗口控制由宿主授权现有 window 原语；登录、签发者、监听与执行授权仍留给宿主。
- **难度**：目录事实小到中；逐族远程策略中，用户在场与决定转交中到大。
- **用户决定的效果**：远端窗口会抢焦点/中断播放，app.quit 结束端点；备份恢复/插件安装可改写数据或执行代码；不应一次开放所有写能力。读取自身状态不发布、不花钱。
- **影响（I）**：Nipa 在 Mac 上无法用同一工具排查服务器日志、关闭客厅窗或调整后台节点策略；远程目录可以知道工具缺席，但还无法统一分辨宿主未实现、后端不可用与权限策略限制。

### G09 · P1：网络故障的可观察性不足，独立媒体服务器 UA 未暴露

- **缺什么（C）**：已有统一代理、播放器 UA、GitHub 代理和证书全局开关；缺路由模式/实际官方网关/故障转移状态、可达性/失败阶段、媒体服务器连接 UA。Classic 连通性只返回 bool，不能直接包装成完整故障诊断。
- **代码**：`lib/utils/network_settings.dart:11`、`:62`；`lib/services/nipaplay_server_router.dart`、`server_connectivity_service.dart:31`、`media_server_transport.dart:38`；`lib/settings/pages/network_settings_content.dart:221`。
- **建议（P）**：`network.status {targets?}` → `{effectiveProxy:{mode,host,port},routes:[{provider,mode,effectiveGateway,failoverUntil}],observedAt}`；`network.check {targets:[...],timeoutMs}` → 每目标 `{dns,tls,httpStatus,latencyMs,error:{code,retryable,recoveryAction}}`；`settings` 补 `network.mediaServerUserAgent`、官方模式 `network.dandanplayMode`。自定义地址切换单独发起用户决定，返回来源信任影响，不暴露头/密码/完整认证 URL。
- **难度**：UA/官方模式小；阶段诊断中。
- **用户决定的效果**：切到第三方兼容服务器可能把账号凭据发给新 origin（源码明确将 custom 选择视为信任决定），必须由用户决定；不能建议直接开放 custom URL 作为普通 Agent 设置。官方主备沿用现有限流与网关。
- **影响（I）**：Agent 无法区分代理问题、媒体服务器 UA 拒绝、网关故障和未登录，容易错改 unrelated 设置。

### G10 · P1：缓存/空间管理没有全局事实与分类回收

- **缺什么（C）**：download.read 已有真实 disk.availableBytes；Mesh 自描述也有部分存储 facts。缺 app/cache/library 分区用量、Classic 弹幕/图片清理入口、Next artwork/mesh-assets/subtitles 的统一引用感知清理。当前 cache_prune 仅 Next 可恢复弹幕池，唯一导入副本排除。
- **代码**：`lib/settings/pages/storage_settings_content.dart:283`、`:340`；`lib/utils/storage_service.dart`、`image_cache_manager.dart`；`lib/next/danmaku/capability.dart:452`；`lib/next/headless/core.dart:147`。
- **建议（P）**：`storage.status {paths?}` → `{volumes:[{path,availableBytes,error}],directories:[{role,path,bytes,disposable,uniqueData}]}`；`cache.plan {kinds,maxBytes?}` → `{planId,entries,reclaimableBytes,preservedImports,activeReferences}`；`cache.prune {planId}` → `{removedBytes,retained,failures}`；补 `storage.clearDanmakuOnLaunch` 设置。read/plan 不改持久数据。
- **难度**：状态中，分类引用回收中到大。
- **用户决定的效果**：不可恢复的导入字幕/弹幕不是 disposable cache；清理会删除磁盘文件，须区分可重取缓存与唯一内容、预览实际路径/影响。不能按“都叫缓存”统一清空。
- **影响（I）**：低空间时 Nipa 只能暂停下载或观察任务盘，不能判断“清哪里能腾出多少且不丢附件”。

### G11 · P1：缺自动行为的独立开关与可生效状态

- **缺什么（C）**：autoLoadStrategy/skipMatching、下载完成自动入库已经有；缺 Classic startup refresh、Next sidecar/subtitle 30 秒 reconcile 的启停/状态。headless 下载 import 是文件索引，不是 GUI 同样的智能匹配。
- **代码**：`lib/services/scan_service.dart:229`、`:264`；`lib/next/danmaku/sidecar.dart:89`；`lib/next/subtitles/library.dart:84`、`library_io.dart:62`；`lib/next/headless/downloads.dart:324`。
- **建议（P）**：`settings` 补 `library.startupScanEnabled/library.sidecarIndexEnabled/library.subtitleProbeEnabled`，schema 返回默认行为、是否停止正在执行工作和生效时机；`media.indexers.status {}` → `{workers:[{kind,enabled,running,lastRun,nextRun,queue,error}]}`；一次扫描/探测保持独立 `media.library.scan/subtitle.inspect`。不新增代码内自动判断“何时该匹配”。
- **难度**：中（定时器生命周期、关闭后不丢队列、状态与事实一致）。
- **用户决定的效果**：开关本身不删除/发布；自动线上获取消耗网络配额，开启必须符合用户任务，不能放松网关限流。
- **影响（I）**：长片库/慢共享盘上无法区分是用户扫描还是应用自动探测，也不能明确“只登记，不自动匹配”。

### G12 · P1：图库覆盖只有 set，无法清除；通用文字编辑缺批量

- **缺什么（C）**：四种图片可原子批量设置，底层编辑支持生命周期；artwork.set 只写 persistent，没有 clear。metadata.override 虽有 clear，但 field 枚举只有 title/originalTitle/overview/imageUrl；一次只能改一个字段/实体。
- **代码**：`lib/next/ui_data/metadata_facts.dart:169`、`:192`；`lib/next/media/media_capability.dart:620`；`lib/next/media/identity_store.dart`。
- **建议（P）**：`media.artwork.clear {entries:[{entityId,kind}],reason}` → `{entries:[{cleared,effectiveArtwork,source,retainedFile}]}`；扩展 `media.metadata.override_batch {entries:[{entityId,field,value,language?,mode}],requestId?}` → 逐项或整批结果，schema 明确原子性；保留旧编辑审计。复用 metadata.ui_facts 读有效资料。
- **难度**：小到中。
- **用户决定的效果**：清覆盖不是删原图；自动 GC 如删除唯一副本另做决定。替换用户资料要保留旧值/来源；不发布、不花钱。
- **影响（I）**：取错封面后无法“恢复平台图”；整理整季标题需许多单项调用。

### G13 · P2：章节、逐帧、识别跳过与播放列表只有 GUI 可操作事实

- **缺什么（C）**：应用有 chapter、frame-step、识别 skip 与多来源列表；现有 seek/open 可组合一部分，但不提供同样的语义/事实。
- **代码**：`lib/player_abstraction/abstract_player.dart:152`、`:167`；`lib/utils/video_player_state/video_player_state_chapters.dart`、`video_player_state_intro_skip.dart`；`lib/themes/nipaplay/widgets/playlist_menu.dart`。
- **建议（P）**：`playback.chapters {}` → `{items,index,supported}`；`playback.navigate {chapterIndex?|frameDelta?|skipKind?}` → `{positionMs,method,observedAt,unsupportedReason}`；`playback.playlist {}` → `{source,items:[{fileId?,path?,episodeId?,playable,reason}],currentIndex}`。只暴露应用已支持的列表选择，不凭空增加可编辑队列语义。
- **难度**：中（多内核与多个来源的精确对应）。
- **用户决定的效果**：只中断当前观看位置；不删除、发布或花钱。

### G14 · P2：详细诊断、文件日志与恢复工具不足

- **缺什么（C）**：已有日志读/导出/目录与开关；缺完整播放器详细信息、资源指标、构建/依赖版本、持久 file-log 分页读、Linux 迁移状态/恢复入口。diagnostics.logs 读内存缓冲，directory 不是文件内容读取。
- **代码**：`lib/next/settings/operations.dart:310`；`lib/themes/nipaplay/widgets/playback_info_menu.dart:158`、`system_resource_display.dart`；`lib/settings/pages/developer_options_settings_content.dart:459`、`:635`、`:782`。
- **建议（P）**：`diagnostics.status {sections}` → `{build,dependencies,resources,storageMigration,player:{kernel,codec,dimensions,decoder,buffering,error},observedAt}`；`diagnostics.file_logs {fileId?,cursor,limit,filter}` → 脱敏行与 nextCursor；`storage.migration.preview {operation}` / `storage.migration.apply {planId}` → 逐文件源/目标/覆盖冲突与回执。播放诊断不要照搬 GUI 的 actualUrl 字段。
- **难度**：状态中；迁移/个人文件恢复大，需要数据约束和恢复预览。
- **用户决定的效果**：日志包含隐私，输出只可操作事实与脱敏内容；迁移可能移动/覆盖用户文件，需明确决定；本地查看不发布/花钱。

### G15 · P2：没有立即检查应用更新的工具

- **缺什么（C）**：有 autoCheck 设置，缺 check/status；Classic 当前只取发布信息并打开外部链接，没有应用内自动安装更新，不能把自动安装列为已存在功能。
- **代码**：`lib/services/update_service.dart:37`；`lib/settings/pages/about_settings_content.dart`；`lib/next/settings/classic_settings.dart`。
- **建议（P）**：`app.update.check {}` → `{currentVersion,latestVersion,hasUpdate,releaseNotes,publishedAt,publicReleaseUrl,checkedAt,error}`；`app.update.open {releaseId}` → `{opened}`，由宿主仅打开已核对的公开发布页。更新错误保留 stage/code，不能把失败读成“没有更新”。
- **难度**：小到中；未来下载安装另立能力和实验。
- **用户决定的效果**：查版本没有删除/发布/付费；下载/安装/重启如果新增，会覆盖程序并中断会话，另由用户决定。

### G16 · P2：分享/通知/LAN 发现与精确窗口控制缺领域入口

- **缺什么（C）**：Classic 有系统分享、日志上传、启动 Snackbar、LAN 找共享来源、主窗拖动/缩放。window.control 已有 full screen/PiP/托盘，不应重做；缺精确 bounds 与变化事件。未发现通用 OS 通知基础设施，因此通知工具是新增身体能力。
- **代码**：`lib/services/system_share_service.dart:13`、`log_share_service.dart:48`、`nipaplay_lan_discovery.dart`；`lib/next/capabilities/local_playback_operations.dart:105`；`lib/themes/nipaplay/widgets/startup_notification_controller.dart:61`。
- **建议（P）**：`media.sources.discover {timeoutMs}` → `{candidates:[{address,kind,name}],observedAt}`，只发现不自动加来源；`window.bounds {target,bounds?}` → 实际 bounds；`share.prepare {kind,fileIds}` → 预览对象/目标方式，`share.open {planId}` 打开用户系统面板；日志公开上传用独立 `diagnostics.publish {planId}`。`notification.send/cancel/list` 必须先实现宿主后端与 `{deliveryState,reason}`，低优先级，不以 ui.present 成功冒充系统已通知。
- **难度**：LAN/窗口小到中；分享中；OS 通知大（平台/权限/投递状态）。
- **用户决定的效果**：移动/聚焦窗口影响用户工作；分享/上传可能对外发布隐私，需指定目标与内容；发现本身不发布、不花钱。

## 现有工具的质量缺口

以下是现有契约或实现问题，和“完全没有 Action”分开。修复建议仍为 P；运行行为没有实测。

| 类别/问题 | 代码确认的事实 | 对真实任务的影响（I） | 建议与相关缺口 |
|---|---|---|---|
| 有加没有完整改/删：持久字幕 | tracks/import/select；没有 remove/update/reset_selection；运行时 remove 不删 Next 导入事实 | 无法彻底换错字幕/恢复自动语言偏好 | G04 |
| 有 set 没 clear：分项图片覆盖 | `setArtwork` 将 artwork.kind 固定写为 persistent；metadata.override 枚举不含 artwork.kind | 无法恢复平台原图 | G12 |
| 任务控制覆盖不全 | TaskEngine 有 pause/resume，目录无这两项；download 的领域暂停已覆盖 | 扫描、取资料、帮手控制语义碎片化 | G05；不得把所有 executor 都视为已支持安全恢复 |
| 扫描不是持久任务 | `scan_classic` await 完成，roots.list 提供即时进度；没有 jobId/任务回执 | 长调用掉线后无法按任务号跟踪；并发调用冲突需轮询 | G05、G06 |
| 事件只覆盖 4 种 hook | 内部 changes/任务等待有，外部 hook 没有播放结束/失败/设置与附件变化 | Agent 要额外写定时轮询 | G06 |
| 持久默认字幕选择只有单文件 | `subtitle.select` 一个 fileId/trackId；import 和 tracks 已支持批量 | 为一整季默认字幕需 N 次调用 | 加 `entries` 并返回逐项结果；不将所有 subtitle 工具误记为无批量 |
| 资料文字修正、刷新、完整情况读取单对象 | override 一实体一字段；refresh 一个 ref；ui_facts 一个 workId；search/get/import/bind/unbind 已有 batch | 整季准备成本随对象数放大 | G12；补 override/refresh/ui_facts 批量，不重造已有 batch |
| 弹幕获取/附着/导入、缓存删除/导出单对象 | `danmaku.fetch/attach/import/cache_delete/export` 单目标；update 为 1–100 changes，hash.match 可批量 | 批量准备整季弹幕要多次调用、多个等待号 | `danmaku.fetch_batch/attach_batch/import_batch` → 每项 bindingId/jobId/status/error；cache delete/export 以 entries，明确删除影响 |
| 缺可观测执行完成事实 | open、pause、seek 返回即时快照；内核实际加载/seek 与命令受理非同一事实 | 误说“已播放/已跳到” | G03；结果区分 accepted/observed，不统一返回虚构 succeeded |
| 外部未知值被顶层默认数值掩盖 | `video_player_state_port.dart:16` 用 position??0、paused??false、rate:1；external 子对象才保留 null | Agent 看顶层以为从零播放/当前非暂停/1 倍速 | G03；顶层 nullable + availability；外部倍速和音量无 Action 后端，必须显式不支持 |
| `subtitle.import` 批量失败信息弱 | `capability.dart:60` 失败只给 fileId/saved:false/error.message，没有 index/trackId/error.code/retryable；同 fileId 多项难区分 | 无法知道失败项该改语言、补 pair、换路径还是重试 | 统一 `{index,fileId,inputTrackRef,error:{code,message,retryable,recoveryAction}}`，保留批量部分成功语义 |
| 部分批量失败丢掉前面成功回执 | `media.sources.addresses/remote_admin.folders` 顺序执行，任一项 throw 后顶层失败；描述承认前项保留 | Agent 不知道哪些已改变，重试可能重复操作 | `lib/next/media_sources/remote_admin.dart:166`：全量验证、逐项回执或失败返回 appliedResults，明确 atomic=false |
| state.query 的安全归一错误欠恢复提示 | `lib/next/state/query.dart` 将来源原始异常归一 state_read_failed，Failure 消息也为 state_source_failed；保护认证信息有必要 | 查询失败时只得 code，不知道缺宿主/provider/权限/重试条件 | 返回脱敏 stage/source/status/recoveryAction/correlationId；不给原始认证 URL/异常转储 |
| 泛化错误不可操作 | playback.open “window may not be ready”；plugins.install “could not load”；地址 add “could not add” | 每次都得猜下一步查日志/登录/换源 | `playback_capability.dart:164`、`settings/operations.dart:240`、`media_sources/remote_admin.dart:173`：沿现有 Failure 加 reasonCode、当前支持/下一查询入口；禁止自动重试发布 |
| 图片设置回执缺已保存事实 | `metadata_facts.dart:205` 只回 entityId/kind/saved:true，路径/source/effective image 得再 ui_facts | 一批交图后无法立即确认实体实际呈现哪张图 | 补受限本地 path/hash/source/effectiveKind，保留 ui_facts 的完整核对 |
| `media.library.progress` 写后只回计数 | `lib/next/mesh/library_capability.dart:71` 只回 updated，底层有时间戳/设备写入与合并规则 | 不知道跨节点写入是否为当前胜出的观察 | 返回每项 persisted observation 与 effective progress/writer/observedAt，不承诺已送达所有离线设备 |
| 相同名称、不同宿主语义 | roots.remove：GUI 删除 Classic 历史/hash，headless 只改 root 配置；download.import：GUI 识别、headless 索引；settings 同 ID 但 headless 只有 2 个条目 | 远程工作误以为效果和默认策略相同 | schema 加 semantic role/appliesTo/affectedData，app.capabilities 明示；G01 |
| 时间单位/方向与名词不一致 | danmaku.offset/update 为整数 ms，正值提前；manualOffset/external offsetSeconds 用播放器的秒语义；playback 跟进动作 snake_case，settings camelCase；dedup 旧别名实际仅 displayFold | 调整 0.5 秒可能用错方向/把折叠当删除原文 | 明确每域公式 `display=source-offset`，回执同时含 source/mapped；保留 alias、主目录推荐 update/analyze_alignment |
| retired 工具仍显示为普通工具 | danmaku.align 新请求 unavailable；align_apply/keep 只恢复旧决定 | Agent 按旧名字发新分析任务 | 目录标 lifecycle=legacyRecovery、replacement；不是删除旧持久任务 |
| effect 与“读”混用 | playback.levels/external(command=state)、media.sources.addresses(无 operations)、remote_admin.status 用 Effect.write；discover.recommendations(next=false) 也是 write；readable/refresh 会建临时代理/缓存仍标 read | 只读筛选遗漏可读工具，状态查询副作用不透明 | 独立 read Action 或 schema 说明 effect=domainRead/cacheWrite/runtimeControl，先保留现有兼容与审计 |
| 删除/覆盖与 write 标签不一致 | GUI roots.remove/cleanup/history.remove 标 write 并说明无需确认，但会删除持久历史；Mesh 文件 delete/overwrite 有 NeedsDecision，download.delete 走磁盘同意 | “不是删视频”仍可能丢观看事实；同名工具效果不可一眼判断 | **主控决定**：按真实数据影响公开 affectedData、preview；不在本研究中改 Classic 确认行为 |
| headless 的 readOnly 描述不等于全进程禁止写媒体根 | headless 下载后端拦 readOnlyRoots；MeshFiles 走绝对路径文件原语，没有复用该判断；mesh 文档明确按进程权限读写 | 仅看设备自描述 mediaReadOnly:true 可能误判所有 Action 都只读 | schema 标注 readOnly 的作用域（索引/下载目录），文件能力返操作权限；是否统一限制是宿主/主控决策，未实测写入 |
| 大结果没有同样的分页边界 | subtitle.tracks 省略 fileIds 会全取；files.list 返回完整递归清单；discover.search 全结果；已有 state.query 支持分页/filter/select | 大库超 Mesh 1 MiB 帧或 Agent 输出预算的风险（I，未测阈值） | 让源查询/文件枚举/字幕 facts 接同类 limit/cursor/select；批量也回每项索引，不能让 Agent 从截断文本猜遗漏 |

已经做得较好的契约应保留：download.read 返回路径、piece 完成、实际大小、playable/streamable、identificationPending、健康/磁盘 facts；绑定批次有 requestId、来源和 Classic 投影核验；danmaku.update 有 revision、绝对偏移和逐项错误；playback.capture 如实区分请求弹幕与实际包含；来源 browse 分开 sourceId/itemId/fileId、目录发现与身份判断；state.query 有闭合白名单、游标与来源观察时间。不要把这些列为缺失。

## SettingsStorage / SettingsKeys 逐键对照

`SettingsStorage` 是通用类型存取包装，自己不定义键表；不能从它的方法数推导设置覆盖。此次枚举 `lib/constants/settings_keys.dart` 全部 **80 个常量**及 `lib/` 非 Next 代码中全部 SettingsStorage 调用，追踪 literal、SettingsKeys、ThemeNotifier 常量。注册表核对按**实际 SettingEntry 的 storageKey/辅助工厂/兼容读取**，不是“某串在 Next 文件出现过”就算注册。

结果：58 个物理键有独立/分项注册，4 个是旧/兼容键（3 个由新设置兼容读写；`danmaku_kernel` 只由旧 API 读写，现代 renderEngine 是替代入口而非该键的兼容读取），另 18 个没有独立入口；SettingsStorage 另有 3 个未注册 literal。80 个键及每个引用位置逐行保存在 [settings_keys.tsv](../evidence/x51/settings_keys.tsv)，调用清单见 [settings_storage_calls.tsv](../evidence/x51/settings_storage_calls.tsv)。以下 **22 个未独立注册的 SettingsKeys 与 3 个 literal，全部逐项列出**。适合暴露指领域工具/设置，不是允许写内部数据文件；GUI-only 显示偏好仅登记，未作为 Next 界面缺口展开。

| 未独立注册键 | 现有代码/用途（C） | 是否适合暴露、原因与建议（P） | 用户决定的效果 |
|---|---|---|---|
| `clear_danmaku_cache_on_launch` | `lib/settings/pages/storage_settings_content.dart:251`；Classic 启动清缓存 | 是，`storage.clearDanmakuOnLaunch`；必须说明切换时 Classic 还会立即清一次，与 Next 池不同 | 删除缓存/影响离线观看；不能把持久唯一导入也清掉 |
| `danmaku_auto_match_on_play` | `lib/next/settings/application_settings.dart:288`；旧自动匹配兼容键 | 不新开入口，已有 `danmaku.autoLoadStrategy` + skipMatching；把迁移关系放 describe | 新策略有线上请求，无新删除/发布 |
| `media_server_connection_user_agent_v1` | `lib/services/media_server_transport.dart:38`；API、图片、播放同步统一 UA | 是，`network.mediaServerUserAgent`；复用 MediaServerTransport setter，空串恢复默认 | 无删除/付费/发布；网络识别字符串改变 |
| `auto_check_updates_on_about_page` | `lib/services/update_service.dart:15`；旧更新检查键，新设置读取后迁移/清除 | 不独立；已有 `general.autoCheckUpdates`，应标 legacyKey | 无新决定效果 |
| `show_remote_access_qr_code` | `lib/providers/remote_access_settings_provider.dart:18`；显示远程访问二维码 | 可有用户显示偏好 schema，但 QR/连接内容只显示给用户；不能返回含凭据的码/链接；网络监听权限另由宿主 | 显示连接信息可能被旁观者获取；不作为 Agent 自开网络入口 |
| `labs_show_remote_access_qr_code` | 同 provider:19；legacy fallback | 不独立，迁移到上项；不能开放两值互相覆盖 | 同上 |
| `labs_enable_agent_endpoint` | `lib/providers/labs_settings_provider.dart`、`lib/next/settings/denylist.dart:18` | 不开放自写，宿主授权入口；可读 enabled/reason 状态，不含连接秘密 | 打开 Agent 连接权限，由用户决定 |
| `torrent_recent_download_directories` | `lib/services/torrent_download_service.dart:137`；最近目录列表 | 不作为任意设置；已有 download.directories/forget_directories，新增任务自动 remember | 删除最近选择仅元数据；不是移动/删媒体 |
| `torrent_recent_download_directories_migrated` | 同 service:170；迁移完成标记 | 否，内部迁移事实；诊断可报告 migrationVersion/status | 任意改写会误触发迁移 |
| `media_library_selected_section` | `lib/media_library/adaptive_media_library_page.dart`（具体调用见 TSV）；当前 Classic 分类 | 可注册低优先级 Classic 显示偏好；任务若需切换用已有 ui.open，不能将它当能力任务数据 | 无删除/发布；界面焦点变化 |
| `media_library_section_order` | `lib/media_library/media_library_section_order_store.dart`；Classic 来源区排序 | 可按真实控制需求注册排序 schema，校验当前 section IDs；仅登记，不讨论 Next UI | 无删除/发布 |
| `downloader_verified_scanned_completed_task_keys` | `lib/next/downloads/download_library.dart`；完成文件经核对后的导入记录 | 否，回执/验证事实，应查任务与 download.read；需要重扫用 download.import | 任意 set 会伪造完成或丢重试事实 |
| `downloader_auto_scanned_completed_task_keys` | `lib/services/torrent_download_service.dart:579`；旧/Classic 自动扫描记录 | 否，同上；注册的 autoScanCompletedTasks 已是策略开关 | 任意重写会误报已扫描或重复扫描 |
| `danmaku_supersample` | `lib/providers/settings_provider.dart:171`、`:376`；旧 double 兼容键 | 不独立；`danmaku.supersample` 权威是 v2 字符串，读旧/双写受维护 | 无新决定效果 |
| `tvos_erika_danmaku_outline_default_migrated_v1` | `lib/utils/video_player_state/video_player_state_preferences.dart:1615`；tvOS 描边默认迁移 | 否；现有 danmaku.outlineWidth 才是控制项 | 任意改写破坏迁移语义 |
| `danmaku_kernel` | `lib/constants/settings_keys.dart:147` 注释称已废弃；`lib/utils/player_kernel_manager.dart:376`、`:385` 仍有旧 API 读写；现代工厂读 renderEngine | 不独立开放；现有 danmaku.renderEngine/pluginRenderer。旧键可能陈旧，应明确 legacy API 与现代权威值关系，不能称现代入口已兼容读取此键 | 无新决定效果；若清理旧 API 需守住 Classic 行为 |
| `spoiler_ai_use_custom_key` | `lib/utils/video_player_state/video_player_state_subtitles.dart:461`；代码无条件规范为 true | 否，目前不是有效用户选择，开放 false 会骗人；可在配置状态显示“userConfigured” | 若未来恢复切换，需披露目标服务和费用 |
| `spoiler_ai_api_key` | 同文件:475；CredentialStore/denylist 的秘密键 | 否，用户在自身设置窗口录入；仅公开 configured/缺失状态，绝不 get/set 原值 | 秘密与外部 AI 计费授权留给用户 |
| `show_canvas_danmaku_collision_boxes` | `lib/providers/developer_options_provider.dart:80`、`:142`；Canvas 调试碰撞框 | 可有 debug-only `diagnostics.canvasDanmakuCollisionBoxes` schema；实际使用价值低 | 无删除/发布；改变调试显示 |
| `show_canvas_danmaku_track_numbers` | 同 provider:85、`:151`；Canvas 轨道编号 | 可有 debug-only `diagnostics.canvasDanmakuTrackNumbers`，说明渲染器适用性 | 同上 |
| `show_gpu_danmaku_collision_boxes` | 同 provider:91、`:160`；GPU 调试碰撞框 | 可有 debug-only `diagnostics.gpuDanmakuCollisionBoxes` | 同上 |
| `show_gpu_danmaku_track_numbers` | 同 provider:96、`:169`；GPU 轨道编号 | 可有 debug-only `diagnostics.gpuDanmakuTrackNumbers` | 同上 |
| `anime_detail_display_mode`（literal） | `lib/main.dart:523` 用 SettingsStorage 读取；`lib/utils/theme_notifier.dart:79` setter 写回 | 是，低优先级 `appearance.animeDetailDisplayMode`；与 labs immersive 开关不是一个键 | 只影响 Classic 显示模式；本次不评价 UI |
| `debug_log_auto_scroll`（literal） | `lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:95`、`:483`，Cupertino 同键 | 可作为日志查看偏好；对 Agent 读日志无需此项，不提高优先级 | 只改变日志窗口滚动 |
| `debug_log_show_timestamp`（literal） | 同页面:92、`:466` | 可作为日志查看偏好；diagnostics.logs 已返回 timestamp，不是诊断事实缺口 | 只改变窗口显示 |

另两类符号参数 `ThemeNotifier.backgroundImageRenderModeKey/backgroundImageOverlayOpacityKey`（以及类内同名符号）已解析，分别注册 `appearance.backgroundRenderMode/backgroundOverlayOpacity`，**不是漏键**。Titan 的一个 JSON 物理键已经拆成 17 个分项 schema；同样不是“没有注册”。近期下载目录有领域工具、迁移标记没有写设置，是正确的区分。

上表适合新增 schema 的项统一复用 `settings.describe/get/set/reset`：输入为逻辑 `key` 与经 schema 校验的 `value`，输出应含实际值、是否已应用、适用宿主/渲染器、需重启与错误恢复方法（P）。布尔调试/显示偏好及已有 UA setter 的接入难度小；分类排序与显示模式需枚举/ID 校验，难度小到中；启动清缓存还需区分策略写入与立即删除，难度中。兼容键、迁移回执、秘密和宿主授权项不新增任意写入口，建议的只读状态也不得返回秘密值。

### 不在上述两张键表、但影响控制的持久设置/宿主配置

这些来自 SharedPreferences 或配置文件，补充说明，不能混算进 80 个 SettingsKeys。

| 设置或配置 | 现状（C） | 暴露建议（P） |
|---|---|---|
| `dandanplay_server_mode/dandanplay_server_url/bangumi_server_url` | `lib/utils/network_settings.dart`，Classic 可改；注册表无 | 官方模式可做 schema；自定义 origin 是凭据去向信任决定，用户操作；先读路由 facts（G09） |
| `nipaplay_auto_region/nipaplay_auto_region_at/nipaplay_failover_server/nipaplay_failover_until` | 同文件，路由缓存/故障转移 | 只读状态，不提供任意 set；不要让 Agent 伪造地域/限流状态 |
| `custom_storage_path` | `lib/utils/storage_service.dart:16` 有保存/清除函数；Classic 选路径调用部分被注释 | status/迁移预览；是否提供 relocate 需真实存储流程验证，不能只改偏好造成数据分裂 |
| `trusted_cert_rules_v1` | `lib/services/certificate_trust_service.dart:39`，有 per-host upsert/remove | 首先只读脱敏信任状态；信任写入由用户决定，不以已有全局 allow 开关代替逐站点授权 |
| `web_server_* / remote_control_*` | `lib/next/settings/denylist.dart` 明确禁止 | 状态/用户在场操作可讨论；不开放自授权写入口 |
| `mesh.json` 的 enabled/coordinator/issuer/loopbackOnly/broadcastDiscovery/fileProxyPort/agentDevice 等 | `lib/next/mesh/README.md`；manual addresses 已注册，其他为宿主配置 | 暴露配置是否生效、支持范围与重启要求，保持信任/监听权限由宿主控制；file proxy 状态已经有 view |
| `program.json.enabled` 与 headless `download.json`/native 初始化配置 | `lib/next/programs/runtime.dart`、`lib/next/headless/core.dart:183` | 只读 feature/setup facts；程序授权不是普通 settings；带宽/并发另建真实原生控制（G05） |

## 只能在 Classic 里完成、现有能力工具碰不到的部分

下面单列 GUI-only 的**功能结果**，不把“能 ui.open 打开页面”当成“能执行页面中的功能”。同样不把已开放的评分/评论、批量弹幕绑定、全屏、导入导出、插件市场误列进去。

| Classic 独有操作/事实 | 为什么现有工具不等价 | 代码 | 去向 |
|---|---|---|---|
| 自定义媒体信息、无平台身份文件编集号入库 | metadata.override 只能改既有实体；bind 的目录模式依赖可获取外部身份 | `lib/themes/nipaplay/widgets/custom_media_info_dialog.dart:975` | G02 |
| 章节读取/跳转、逐帧控制、按识别片头片尾跳过、当前列表完整事实 | seek/switch_episode 只实现部分动作，没有这些事实与精确语义 | `video_progress_bar.dart:749`、`playlist_menu.dart`、`lib/player_abstraction/abstract_player.dart:152` | G13 |
| 播放器内部字幕/弹幕正文的直接结构化读取 | Agent 可截图/读导出文件，但没有当前有效列表/cues | `lib/themes/nipaplay/widgets/danmaku_list_menu.dart`、`lib/utils/subtitle_parser.dart` | G07 |
| 清 Classic 全部弹幕缓存、清图片缓存、启动清弹幕开关 | Next cache_prune/cache_delete 的存储对象与唯一副本规则不同 | `lib/settings/pages/storage_settings_content.dart:283`、`:340` | G10 |
| 手动网络连通性检测、选择官方网关模式、修改 Bangumi/自定义兼容地址、媒体服务器连接 UA | 代理和播放器 UA 设置不能代替这些控制；自定义地址涉及信任 | `lib/settings/pages/network_settings_content.dart`、`lib/settings/widgets/media_server_connection_user_agent_setting.dart` | G09，信任保留用户决定 |
| LAN 扫描发现 Classic 共享服务器 | Mesh 发现不能产生 Classic 媒体来源候选 | `lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart` | G16 |
| 复制完整播放诊断、构建/依赖版本、显示资源数字、读持久日志、迁移/误迁移恢复 | app.instance/diagnostics.logs 只覆盖一部分；显示资源开关不返回资源数值 | `lib/themes/nipaplay/widgets/playback_info_menu.dart:158`、`lib/settings/pages/developer_options_settings_content.dart` | G14 |
| 日志上传分享、系统分享/剪贴板导出 | 本地 diagnostics.export/capture 只产出文件 | `lib/services/log_share_service.dart:48`、`system_share_service.dart:13` | G16，发布必须明确用户需求 |
| 立即检查更新/读新发布说明、打开发布页 | 自动检查开关与本机版本不足以执行此流程 | `lib/services/update_service.dart:37`、`lib/settings/pages/about_settings_content.dart` | G15 |
| 输入登录秘密、授予文件系统 bookmark/SAF、打开网络接收/端点、设置信任 | 故意留给用户/宿主，登录/授权 picker Action 能发起但不能替用户输入/批准 | `lib/next/accounts/login_dialog.dart`、`lib/next/media_sources/login_dialog.dart`、`lib/next/settings/denylist.dart` | 保留边界；不是应该自动化的缺口 |

debug 显示键、日志查看偏好和 Classic 分类顺序属于缺少 schema 的低影响控制，已经逐键列出；本节不据此提出 Next 新页面。原生文件关联、拖拽/快捷键/手势如果最终都调已有 playback/open/settings，是同一能力的输入方式，未另算成工具缺口。

## 证据强度、复核与未验证事项

- **代码确认**：GUI/无界面 capability 组装及过滤；全部静态 Action ID 和 Mesh 放行；SettingsKeys 的 80 个键及 SettingsStorage 调用；上述缺少的 schema/执行分支；关键 Classic 操作背后的服务/状态字段。证据以路径/行号、静态 TSV 与源码基线组成，不复制用户数据或秘密。
- **推断**：P0/P1/P2 对真实任务的影响、长回复跨 Mesh 帧失败风险、卸载旧导入之后的再次出现、设备 readOnly 文案引起误操作、异步命令返回过早的实际严重程度。未把这些写成已复现故障。
- **建议**：全部新能力名、输入输出、原子/逐项选择、事件设计、暴露与用户决定方案、难度均是研究建议；没有改注册表、权限、Classic 行为或持久数据。
- **未验证**：当前真实 `nipa list`、启动/挂载后的动态插件 schema、各平台原生内核、实际目录授权/登录/连通性、数据量阈值、外部播放器 IPC、Mesh 授权票据与实际传输。没有执行任何运行时实验。未来主控应选真实任务验证，不能拿这份静态报告宣称功能已通过真机验收。

报告自行决定：用“工具注册/实际后端/远程放行”三个层次表达覆盖；对同名 headless 工具列语义差异；把旧键、回执键、秘密键和低影响显示偏好逐项说明；难度/优先级与新契约明确标 P/I。需要主控决定：优先选择哪条真实任务；无界面后端顺序；逐族远程写策略；元数据删除与磁盘删除的用户决定语义；自定义网络 origin 的信任入口。

最后只做文档检查：报告/证据的源路径存在性、Action 家族展开与组装对照、键计数、diff 写入范围和敏感内容格式检查。没有提交、push、pub get、构建、启动应用或 flutter test。
