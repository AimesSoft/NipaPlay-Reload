# NipaPlay Next 能力覆盖调研（CAPABILITY_COVERAGE）

> 状态：只读调研 · 2026-10-10
> 依据：`docs/next/DESIGN.md`（M1 基线）、当前工作区源码。
> 说明：主仓库此刻处于合并中，`lib/next/next_runtime.dart` 与 `lib/next/tasks/sqlite_job_store.dart` 含冲突标记；本文按两侧意图合并理解，不引用具体冲突行。
> 证据格式：仓库相对路径 `file:line`。凡属推断均显式标注“推测”。

---

## 0. 方法与边界

- 只读：未修改任何文件，未运行应用。
- “入口”指用户当前能通过 UI 触发的操作（点击、切换、输入、菜单项），不含纯渲染。
- 现有 Harness Action 的 id 直接从 `ActionSpec` 常量读取；`media.*` / `danmaku.*` 由 `_specs` 列表与 `for` 循环展开计算。
- 设置项的“当前存储键”来自 `lib/constants/settings_keys.dart` 或各文件内私有常量；两者都已核实。

---

## 1. 用户可操作入口盘点（按领域分组）

### 1.1 主页面与子页面

| 入口 | 位置 |
|---|---|
| 底部主导航页面（首页 / 播放 / WebDAV / 媒体库 / 下载 / 账号 / 外部播放器控制台 / 设置） | `lib/app/app_page_ids.dart:4-20`（`AppPageIds.primaryOrder`），构建于 `lib/app/unified_app_pages.dart:60-155` |
| 页面级动作：切换主题、打开设置 | `lib/app/unified_app_actions.dart:22-29`，`lib/app/app_page_ids.dart:40-45` |
| 首页（继续观看、排行榜、新番、媒体库推荐） | `lib/pages/dashboard_home_page.dart:1101-1152`；刷新动作 `lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart:701` |
| 新番时间表页（搜索、刷新） | `lib/pages/new_series_page.dart:367-392` |
| 番剧详情页（开始/继续观看、收藏、评分、短评、清理本地记录、修改背景图、剧集正逆序、标签浏览） | `lib/pages/anime_detail_page.dart:2776-2820`（观看按钮）、`:3140-3180`（更多菜单：收藏/评分/标签/正逆序/清理记录）、`:3721-3753`（评分对话框） |
| 媒体服务器详情页（播放、重试、季选择） | `lib/pages/media_server_detail_page.dart:1007`、`:1171`、`:1251-1277` |
| WebDAV 浏览器（切换服务器、上一级、添加服务器、搜索、播放） | `lib/pages/webdav_browser_page.dart:676-710`、`:1594`、`:1929` |
| 账号页（登录/注册/退出/注销、保存/删除令牌、增量同步、全量同步、测试连接、清除同步缓存、Bangumi 授权与同步管理） | `lib/pages/account/account_page_view_model.dart:60-95`、`:184-249` |
| 播放页 / 独立播放窗口 / 外部播放器控制台 | `lib/pages/play_video_page.dart`、`lib/pages/desktop_player_window.dart`、`lib/pages/external_player_console_page.dart` |

### 1.2 对话框与 Sheet（代表性清单）

| 对话框 / Sheet | 位置 |
|---|---|
| 媒体库操作 Sheet（添加媒体 / 远程访问） | `lib/media_library/adaptive_media_library_page.dart:388-452` |
| 媒体库顺序 / 排序 | `lib/media_library/adaptive_media_library_controls.dart:732-744` |
| 添加媒体来源选择（本地 / NipaPlay / Jellyfin / 弹弹play / Emby / WebDAV / SMB） | `lib/media_library/media_source_option.dart:40-83`，流程 `lib/media_library/adaptive_add_media_flow.dart:154-165` |
| 导入本地视频 | `lib/media_library/pick_local_media_directory.dart:37` |
| 网络媒体服务器连接（地址 / 用户名 / 密码 / 名称 / 断开 / 保存） | `lib/themes/nipaplay/widgets/network_media_server_dialog.dart:194-215`、`:1305-1315` |
| SMB / WebDAV 连接对话框 | `lib/themes/cupertino/widgets/cupertino_smb_connection_dialog.dart:8`、`lib/themes/cupertino/widgets/cupertino_webdav_connection_dialog.dart:18` |
| 共享客户端（扫码连接、添加、编辑、删除、刷新） | `lib/settings/pages/remote_media_library_settings_content.dart:563-651`、`:1199-1267` |
| 局域网扫描 / 共享主机选择 | `lib/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart:251-263`、`lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart:45` |
| 插件市场（安装 / 更新 / 删除 / 查看文档） | `lib/themes/nipaplay/widgets/plugin_market_dialog.dart:306`、`:737-783` |
| 插件导入 / 删除 / 动作选择 | `lib/settings/pages/plugin_settings_content.dart:79`、`:216`、`:201` |
| 远程访问端口设置 | `lib/settings/pages/remote_access_receiver_settings_section.dart:330-364` |
| 受信任设备移除 | `lib/settings/pages/remote_access_receiver_settings_section.dart:1004-1037` |
| 下载：添加磁链 / 选择种子 / 删除确认 | `lib/downloads/adaptive_torrent_download_dialogs.dart`、`lib/downloads/unified_torrent_page_model.dart:112-121` |
| 弹幕：发送弹幕、批量匹配、手动匹配、自定义媒体信息 | `lib/themes/nipaplay/widgets/send_danmaku_dialog.dart`、`lib/themes/nipaplay/widgets/batch_danmaku_dialog.dart:69`、`lib/themes/nipaplay/widgets/manual_danmaku_dialog.dart`、`lib/themes/nipaplay/widgets/custom_media_info_dialog.dart:49` |
| 弹幕屏蔽词、防剧透 AI 设置 | `lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_settings_pane.dart:68-80`、`lib/settings/pages/danmaku_settings_content.dart:344`、`:594-621` |
| Bangumi 收藏 / 短评 / 评分 | `lib/themes/nipaplay/widgets/bangumi_collection_dialog.dart:49`、`lib/themes/nipaplay/widgets/bangumi_comment_dialog.dart`、`lib/themes/nipaplay/widgets/rating_dialog.dart:30` |
| 观看记录删除 | `lib/themes/nipaplay/pages/settings/watch_history_page.dart:745-781` |
| 备份/恢复（全量备份、全量恢复、立即同步、备份/恢复观看进度） | `lib/themes/nipaplay/pages/settings/backup_restore_page.dart:585-643` |
| Linux 存储迁移 / 紧急恢复个人文件 | `lib/settings/pages/developer_options_settings_content.dart:595-848` |

### 1.3 播放器菜单（`lib/player_menu`，`PlayerMenuDefinitionBuilder`）

菜单项定义（pane id、标题、可见性谓词）全部在 `lib/player_menu/player_menu_definition_builder.dart:15-110`：

| Pane | 定义行 | 主题实现（Nipaplay / Cupertino） |
|---|---|---|
| 字幕设置 `subtitleSettings` | `:15` | `lib/themes/nipaplay/widgets/subtitle_settings_menu.dart`、`lib/themes/cupertino/widgets/player_menu/cupertino_subtitle_settings_pane.dart` |
| 字幕轨道 `subtitleTracks` | `:25` | `.../cupertino_subtitle_tracks_pane.dart` |
| 字幕列表 `subtitleList` | `:33` | `.../cupertino_subtitle_list_pane.dart` |
| 音频轨道 `audioTracks` | `:41` | `.../cupertino_audio_tracks_pane.dart` |
| 弹幕设置 `danmakuSettings` | `:49` | `lib/themes/nipaplay/widgets/danmaku_settings_menu.dart`、`.../cupertino_danmaku_settings_pane.dart` |
| 弹幕轨道 `danmakuTracks` | `:56` | `.../cupertino_danmaku_tracks_pane.dart` |
| 弹幕列表 `danmakuList` | `:63` | `.../cupertino_danmaku_list_pane.dart` |
| 弹幕偏移 `danmakuOffset` | `:70` | `.../cupertino_danmaku_offset_pane.dart` |
| 播放设置（快进步长 / 长按倍速 / 跳过） `seekStep` | `:77` | `.../cupertino_seek_step_pane.dart` |
| 倍速设置 `playbackRate` | `:84` | `.../cupertino_playback_rate_pane.dart` |
| 清晰度（Jellyfin/Emby 串流） `jellyfinQuality` | `:91` | `.../cupertino_jellyfin_quality_pane.dart` |
| 播放信息 `playbackInfo` | `:99` | `.../cupertino_playback_info_pane.dart` |
| 播放列表 `playlist` | `:106` | `.../cupertino_playlist_pane.dart` |

pane 控制器（已逻辑解耦的 3 个）：倍速 `lib/player_menu/player_menu_pane_controllers.dart:64`、播放设置 `:189`、字幕设置 `:215`；工厂注册 `:239-245`。

一级快捷操作（倍速、音量增强）：`lib/player_menu/player_quick_controls.dart:77-81`。

各 pane 实际调用的领域操作（已核实）：

- 字幕设置：`setSubtitleScale/Delay/Position/AlignX/AlignY/MarginX/MarginY/Opacity/BorderSize/ShadowOffset/Bold/Italic/Color/BorderColor/ShadowColor/FontName/FontDir/OverrideMode`、`importSubtitleFontFile/Directory`、`resetSubtitleSettings`、`clearSubtitleFontCache`（`lib/themes/cupertino/widgets/player_menu/cupertino_subtitle_settings_pane.dart:102-707`）。
- 字幕轨道：`setExternalSubtitle`、`forceSetExternalSubtitle`、`addExternalSubtitleToStack`（`.../cupertino_subtitle_tracks_pane.dart:294,469`；`:114`）。
- 音频轨道：`setJellyfinServerAudioSelection` + `reloadCurrentJellyfinStream`、`setEmbyServerAudioSelection` + `reloadCurrentEmbyStream`（`.../cupertino_audio_tracks_pane.dart:243-285`）。
- 清晰度：`stream.quality / transcodeEnabled / subtitleIndex / burnInSubtitle`，`_selectMediaSource`、`_applySelection`（`.../cupertino_jellyfin_quality_pane.dart:118-224`）。
- 弹幕设置：`setDanmakuVisible/RandomColor/Opacity/FontSize/OutlineStyle/ShadowStyle/SpeedMultiplier/DisplayArea/Stacking/Merge/BlockTop/BlockBottom/BlockScroll`、`setDanmakuDfmPlusTrackGap`、`setNext2DanmakuOutlineWidth`、`toggleTimelineDanmaku`、`setTitanDanmakuSettings`、`addDanmakuBlockWord/removeDanmakuBlockWord`、`importDanmakuFontFile/resetDanmakuFont`、`loadDanmaku`（手动匹配）、`collectDanmakuForExport/buildDanmakuXmlExport/buildDanmakuJsonExport`（`.../cupertino_danmaku_settings_pane.dart:68-881`）。
- 弹幕轨道：`loadDanmakuFromLocal`、逐轨 `toggleDanmakuTrack`（`.../cupertino_danmaku_tracks_pane.dart:54`；桥 `danmaku.track.enabled::<id>`）。
- 弹幕偏移：`setManualDanmakuOffset`（`.../cupertino_danmaku_offset_pane.dart:56`）。
- 弹幕列表 / 字幕列表：`seekTo`（`.../cupertino_danmaku_list_pane.dart:225`、`.../cupertino_subtitle_list_pane.dart:391`）。
- 播放列表：加载本地/WebDAV/SMB/Jellyfin/Emby 剧集并 `_playEpisode`（`.../cupertino_playlist_pane.dart:209-602`）。
- 播放信息：只读 `getDetailedMediaInfo()`（`lib/services/player_remote_control_bridge.dart:832-840`）。

### 1.4 设置页的每个设置项

设置页入口共 17 个（`lib/settings/unified_settings_entries.dart:280-508`，`UnifiedSettingEntryIds` `:31-48`）。设置页内 `AdaptiveSettingsTile` 构造点统计（含备份/恢复、遥控器页、快捷键页）：

| 页面 | 构造点数 | 文件 |
|---|---|---|
| 外观 | 23 | `lib/settings/pages/appearance_settings_content.dart` |
| 语言 | 1 | `lib/settings/pages/language_settings_content.dart:22` |
| 通用 | 7 | `lib/settings/pages/general_settings_content.dart` |
| 存储 | 10 | `lib/settings/pages/storage_settings_content.dart` |
| 网络 | 8 | `lib/settings/pages/network_settings_content.dart` |
| 备份与恢复 | 9 | `lib/themes/nipaplay/pages/settings/backup_restore_page.dart` |
| 播放器 | 25 | `lib/settings/pages/player_settings_content.dart` |
| 弹幕 | 35 | `lib/settings/pages/danmaku_settings_content.dart` |
| 外部播放器 | 7 | `lib/settings/pages/external_player_settings_content.dart` |
| 快捷键 | 2 | `lib/pages/shortcuts_settings_page.dart` |
| 远程访问与遥控 | 0（自绘行） | `lib/settings/pages/remote_access_receiver_settings_section.dart:585-760` |
| 远程媒体库 | 17 | `lib/settings/pages/remote_media_library_settings_content.dart` |
| 下载器 | 3 | `lib/settings/pages/downloader_settings_content.dart:37-84` |
| 开发者选项 | 14 | `lib/settings/pages/developer_options_settings_content.dart` |
| 实验室 | 5 | `lib/settings/pages/labs_settings_content.dart:29-160` |
| 插件 | 8 | `lib/settings/pages/plugin_settings_content.dart` |
| 关于 | 6 | `lib/settings/pages/about_settings_content.dart` |
| 媒体服务器连接 UA | 1 | `lib/settings/widgets/media_server_connection_user_agent_setting.dart:106` |
| 遥控器（Cupertino 子页） | 8 | `lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:212-303` |

合计 **216** 个 `AdaptiveSettingsTile` 构造点（脚本按正则统计，仅作量级参考）。

各页主要设置项（已核实标题与回调位置）：

- **外观**：主题模式 `:89`、主题色 `:122`、底部进度条 `:147`、弹幕密度曲线 `:160`、进度条/曲线颜色 `:174`、左上角发弹幕/跳过/窗口适配/逐帧按钮 `:193-274`、番剧卡片简介 `:292`、媒体库 NEW 标识 `:310`、低清海报晕染 `:388`、目录名称显示模式 `:333`、首页分区排序与启用 `:407-460`、恢复默认 `:470`、自动界面缩放 `:485`、界面缩放 `:500`、虚拟窗口显示区域 `:518`、背景图像 `:569`、背景毛玻璃 `:594`、背景图像渲染 `:655`、背景颜色叠加 `:689`。
- **通用**：关闭窗口行为 `:81`、播放器启动窗口状态 `:100`、启动窗口位置 `:138`、启动窗口尺寸 `:173`、画中画位置 `:229`、默认展示页面 `:266`、自动检查更新 `:285`。
- **播放器**：播放器内核 `:368`、Erika 超分 `:432`、Erika Android 输出 `:457`、硬件解码 `:493`、Android 音频后端 `:516`、实验性 HDR 原生视频输出 `:545`、后台自动暂停 `:563`、播放结束操作 `:597`、自动连播倒计时 `:644`、快进快退步长 `:681`、长按倍速倍率 `:714`、跳过时间 `:735`、跳过片头提示 `:757`、时间轴截图预览 `:774`、MKV 章节标记 `:847`、播放预缓存大小 `:873`、播放预缓存时长 `:897`、立即隐藏播放器 UI `:921`、右侧悬浮设置菜单 `:942`、自动全屏 `:965`、双倍分辨率播放 `:995`、Anime4K `:1042`、CRT `:1090`。
- **弹幕**：渲染引擎 `:809`、Next++ `:834`、超采样 `:870`、Titan 一组（不透明度/字号/加粗/描边类型/字体/滚动速度/轨道间距/密度/基准时长/同屏上限/防挡字幕/顶部偏移/底部偏移/最大长度/DOM 回收/模型回收/禁止缩小）`:894-1243`、描边宽度 `:1253`、记住弹幕偏移 `:1271`、手动弹幕偏移 `:1295`、简繁转换 `:1319`、随机染色 `:1358`、时间轴告知 `:1371`、轨道间距 `:1385`、弹幕堆叠 `:1403`、防剧透模式 `:1427`、防剧透 AI 设置 `:1450`、跳过弹幕匹配 `:1467`、自动加载策略 `:1509`、哈希失败自动匹配 `:1534`。
- **存储**：启动时清空弹幕缓存 `:55`、立即清空弹幕缓存 `:65`、截图保存位置 `:91`、截图默认保存目标 `:118`、截图格式 `:153`、截图质量 `:174`、截图含弹幕 `:194`、截图含字幕 `:208`、截图裁剪黑边 `:222`。
- **网络**：网络诊断 `:90`、自定义 Bangumi API `:103`、弹弹play 服务器选择 `:121`、自定义弹弹play API `:130`、自定义 UA `:148`、恢复默认 UA `:160`、HTTP 代理 `:179`。
- **外部播放器**：启用 `:79`、类型 `:98`、选择路径 `:131`、弹幕外挂 `:147`、自动切控制台 `:175`、缩小窗口 `:216`、独立窗口控制台 `:236`。
- **下载器**：启用 `:37`、为任务建文件夹 `:50`、自动扫描完成任务 `:68`。
- **实验室**：新版番剧卡片页 `:29`、显示 Erika 内核 `:43`、WebDAV 快捷设置入口 `:59`、Agent 接口开关 `:120`、打开工作区文件夹 `:143`。
- **开发者选项**：允许自签名证书 `:47`、显示系统资源监控 `:87`、调试日志收集 `:105`、文件日志 `:136`、打开日志目录 `:145`、终端输出 `:152`、依赖版本 `:159`、Canvas/GPU 碰撞箱与轨道编号 `:167-288`、Linux 存储迁移 `:595`、紧急恢复 `:779`。
- **远程访问与遥控**（自绘行）：启用远程访问服务 `:600`、启用被遥控端 `:607`、软件打开自动开启 `:614`、启用 IPv6 `:621`、显示二维码 `:628`、远程访问端口 `:635`、受信任设备移除 `:1004`。
- **远程媒体库**：Jellyfin/Emby 连接与断开 `:113-258`、弹弹play 远程连接 `:290-326`、共享客户端列表/扫码/添加/刷新/编辑/删除 `:534-651`、设备 ID `:664`。
- **WebDAV 快捷设置**：显示 WebDAV Tab `:83`、默认主页 `:91`、默认服务器 `:141`、默认目录 `:149`、文件排序 `:163`、显示路径导航 `:180`、自动进入 Season 文件夹 `:195`、Season 匹配模式 `:204`、bgmid 快速匹配 `:226`、tmdbId 快速匹配 `:249`、匹配自动剧集偏移 `:272`、文件搜索 `:286`、搜索范围 `:295`、层级限制 `:313`、搜索文件夹/视频 `:326-336`、搜索超时 `:346`、请求间隔 `:363`、最大结果数 `:376`、重置 `:395`。
- **关于**：社区/仓库/QQ 群/官网/爱发电/赞赏码 `:58-119`、手动检查更新 `:325`。
- **快捷键**：见 1.5。
- **遥控器（Cupertino）**：控制其他设备 `:238`、扫描/二维码 `:280`、打开遥控器 `:295`、清除匹配设备 `:302`。

### 1.5 快捷键

- 默认键位表（19 项）：`lib/utils/hotkey_service.dart:168-186`，说明文案与图标 `lib/pages/shortcuts_settings_page.dart:29-93`。
- 注册与处理：`lib/utils/hotkey_service.dart:224-289`（注册）、`:750-900`（`_handlePlayPause` / `_handleFullscreen` / `_handleRewind` / `_handleForward` / `_handleToggleDanmaku` / `_changePlaybackRate` / `_handleVolumeUp|Down` / `_handlePrevious|NextEpisode` / `_handleSendDanmaku` / `_handleSkip` / `_handleStepForward|Backward` / `_handleResizeToVideo` / `_handleTogglePictureInPicture` / `_handleToggleDetachedPlayer`）。
- 初始化：`lib/services/hotkey_service_initializer.dart:15-28`。
- 存储键：`keyboard_shortcuts`（`lib/utils/hotkey_service.dart:29`）。
- 默认集合：`play_pause, fullscreen, rewind, forward, toggle_danmaku, volume_up, volume_down, speed_up, speed_down, speed_reset, previous_episode, next_episode, send_danmaku, skip, step_forward, step_backward, resize_to_video, toggle_picture_in_picture, toggle_detached_player`（`lib/utils/hotkey_service.dart:168-186`）。
- 平台限制：仅 windows/linux/macOS 注册（`lib/utils/hotkey_service.dart:33-44`）。

### 1.6 媒体库管理操作

`UnifiedLibraryManagementAction`（`lib/media_library/unified_library_management_model.dart:21-31`）在 `lib/themes/nipaplay/widgets/library_management_tab.dart` 组装：

- 本地库：浏览文件、重新扫描、移除文件夹（`:2566-2590`）。
- WebDAV：浏览文件、编辑连接、测试连接、删除连接（`:2612-2637`）。
- SMB：浏览文件、编辑连接、刷新连接、删除连接（`:2664-2691`）。
- 挂载目录：打开文件夹、自定义媒体信息、批量匹配弹幕、扫描/刮削文件夹（`:2847-2878`）。
- 挂载文件：自定义媒体信息、手动匹配弹幕（`:2883-2895`）。
- 库级：刷新、添加（`:2751`、`:3401-3430`、`:3625`、`:3794`）。
- 共享媒体库：刷新、编辑、删除、添加地址（`lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1694-1779`）。
- 多地址服务器：添加地址、删除（`lib/themes/nipaplay/widgets/multi_address_manager_widget.dart:308`、`:120`）。
- 库分区顺序：`lib/media_library/media_library_section_order_store.dart:57-72`（键 `media_library_section_order`）。

### 1.7 账号与服务器连接操作

- 账号：登录、注册、退出登录、注销账号（`lib/pages/account/account_page_view_model.dart:60-95`）；Bangumi 授权、管理同步设置、刷新状态（`:184-205`）；保存令牌、删除令牌（`:216-226`）；增量同步、全量同步、测试连接、清除同步缓存（`:230-250`）。
- Jellyfin/Emby：`connectToServer(url, username, password)`、`disconnectFromServer()`（`lib/providers/jellyfin_provider.dart:302,346`、`lib/providers/emby_provider.dart:269,313`）。
- WebDAV：`addConnection` / `removeConnection`（`lib/services/webdav_service.dart:265,300`）。
- SMB：`addConnection` / `removeConnection`（`lib/services/smb_service.dart:235,270`）。
- 共享客户端：`setActiveHost` / `refreshLibrary` / 编辑 / 删除（`lib/providers/shared_remote_library_provider.dart:175-177`）。
- 弹弹play 远程：连接 / 断开（`lib/settings/pages/remote_media_library_settings_content.dart:290-326`）。

### 1.8 插件管理操作

- 导入插件脚本（文件选择）：`lib/settings/pages/plugin_settings_content.dart:327-362`。
- 插件市场（浏览、安装、更新、删除、查看文档）：`lib/themes/nipaplay/widgets/plugin_market_dialog.dart:306,737-783`。
- 启用/禁用单个插件：`lib/settings/pages/plugin_settings_content.dart:166-190`。
- 插件动作选择：`:193-207`、`:590-973`。
- 删除插件：`:216-294`。
- GitHub 代理设置：`:94`。
- 检查插件更新：`:100`、`:216-236`。
- 插件设置存储键：`plugin_enabled_ids`、`plugin_downloader_override`、`plugin_text_setting_<key>`、`plugin_switch_setting_<key>`（`lib/plugins/plugin_service.dart:38-41,180,194`）。

### 1.9 Classic 下载页操作

`UnifiedTorrentPageViewModel`（`lib/downloads/unified_torrent_page_model.dart:66-110`）与 `UnifiedTorrentTaskAction`（`:11`）：

- 页级：刷新、切换视图（卡片/列表）、添加磁链、选择种子文件（`lib/pages/torrent_download_page.dart:690-709`、`:883-908`）。
- 任务级：播放、暂停/继续、查看文件夹、移除任务（保留文件）、删除任务和文件（`lib/pages/torrent_download_page.dart:555-576`，视图 `:2004-2028`）。
- 搜索、排序（`:741`、`:1972-1980`、`:2432-2446`）。
- 底层服务：`pause/resume/forget/delete`（`lib/services/torrent_download_service.dart:384-399`）。

---

## 2. 覆盖率矩阵

### 2.1 已有 Harness Action（M1 + 合并中的领域）

**M1 九项**（`lib/next/capabilities/`，注册于 `lib/next/next_runtime.dart:47-70`）：

| id | effect | 定义 |
|---|---|---|
| `media.library.search` | read | `library_capability.dart:30` |
| `media.library.series` | read | `library_capability.dart:82` |
| `history.continue_watching` | read | `history_capability.dart:26` |
| `playback.open` | write | `playback_capability.dart:61` |
| `playback.state` | read | `playback_capability.dart:167` |
| `playback.set_paused` | write | `playback_capability.dart:198` |
| `playback.seek` | write | `playback_capability.dart:234` |
| `playback.switch_episode` | write | `playback_capability.dart:275` |
| `ui.navigate` | write | `navigation_capability.dart:19`（`page` 枚举 = `AppPageIds.primaryOrder`，`media_models.dart:545`） |

**Task Engine 四项**（`packages/nipa_harness/lib/src/tasks/actions.dart:3-90`）：`task.list` / `task.get` / `task.wait`（read）、`task.cancel`（write）。

**下载五项**（`lib/next/capabilities/download_capability.dart:18-33,51`）：`download.add / pause / resume / remove`（write）、`download.delete`（destructive）。

**媒体（MA）17 项**（`lib/next/media/media_capability.dart:347-540`）：`media.metadata.search`、`media.metadata.get`、`media.identity.get`、`media.library.works`、`media.library.work`、`media.library.import_history`、`media.library.scan`、`media.identification.start`、`media.identification.get`、`media.identification.add_evidence`、`media.identity.bind`、`media.identity.unbind`、`media.metadata.override`、`media.metadata.refresh`，以及 `for op in [reconsider, skip, defer]` 展开的 `media.identification.reconsider/skip/defer`（共 17）。

**弹幕（MB）16 项**（`lib/next/danmaku/capability.dart:165-320`）：`danmaku.sources / search / episodes / resolve / fetch / attach / tracks / offset / detach / align / cache_delete / export`，以及 `for field in [enabled, deduplicate]` 展开的 `danmaku.set_enabled`、`danmaku.set_dedup`，和 `for operation in [apply, keep]` 展开的 `danmaku.align_apply`、`danmaku.align_keep`（共 16）。

当前已注册 Action 总数（意图合并后的组合根）：9 + 4 + 5 + 17 + 16 = **51**。
注：`lib/next/next_runtime.dart:47-70` 注册 M1 九项 + Task + Media + Danmaku；`lib/next/next_core.dart:70` 注册 Task + downloads + media。两处都出现 `TaskCapability`，合并意图应为“NextCore 持有唯一引擎与能力，NextRuntime 构建 Harness”，本文按此理解。

### 2.2 覆盖率矩阵

**图例**：`已有` = 已注册 Harness Action；`Action` = 建议成为领域 Action（给 id/effect）；`设置` = 建议进入设置注册表（给 key/类型/默认/现存储键）；`ui` = 纯展示导航即可；`关闭` = 刻意不开放（A=输入秘密 / B=Agent 自我扩权）。

#### A. 播放器菜单

| 入口 | 状态 | 建议 |
|---|---|---|
| 播放/暂停 | 已有 | `playback.set_paused`（`playback_capability.dart:198`） |
| 快进/快退/跳转 | 已有 | `playback.seek`（`:234`） |
| 下一集/上一集 | 已有 | `playback.switch_episode`（`:275`） |
| 倍速设置 pane（`playbackRate`） | Action | `playback.set_rate`（write）；范围 `0.01–5.0`（`video_player_state.dart:822`） |
| 长按倍速倍率 / 快进步长 / 跳过时间（`seekStep` pane） | 设置 | `playback.speed_boost_rate`（number 1.25–5.0，默认 2.0）、`playback.seek_step_seconds`（number，默认 10）、`playback.skip_seconds`（int 10–600，默认 90）；现键 `speed_boost_rate` / `seek_step_seconds` / `skip_seconds`（`video_player_state.dart:831,835,840`） |
| 音量 / 音量增强 | Action + 设置 | `playback.set_volume`、`playback.set_volume_boost`（write）；`player_volume_boost`（number 1.0–2.0，默认 1.0，`video_player_state.dart:908`） |
| 弹幕开关 | 已有（部分） | 桥 `danmaku.visible`（`player_remote_control_bridge.dart:571`）；建议提升为 `playback.set_danmaku_visible` |
| 弹幕设置 pane（样式类） | 设置 | 见 2.3 弹幕组 |
| 弹幕轨道 pane（逐轨开关） | Action | `danmaku.set_track_enabled`（write），桥已有 `danmaku.track.enabled::<id>` |
| 弹幕偏移 pane | Action | `playback.set_danmaku_offset`（write）；桥 `danmaku.manualOffset`（范围 −30..30） |
| 弹幕列表 / 字幕列表 pane（点击跳转） | ui | 显示 + `playback.seek` |
| 字幕设置 pane | 设置 | 见 2.3 字幕组 |
| 字幕轨道 pane（选轨、外挂字幕） | Action | `playback.set_subtitle_track`、`playback.set_external_subtitle`、`playback.add_external_subtitle`（write） |
| 音频轨道 pane | Action | `playback.set_audio_track`（write）；串流时触发 `reloadCurrent*Stream`（副作用） |
| 清晰度 pane（Jellyfin/Emby） | Action | `stream.set_quality / set_transcode / set_subtitle_track / set_burn_in`（write）；桥已有 `stream.*` 4 项 |
| 播放列表 pane | 已有 | `media.library.series` + `playback.open` |
| 播放信息 pane | ui | 只读展示；`playback.state` 已覆盖关键字段 |
| 发送弹幕 | Action | `danmaku.send`（write，外发到弹弹play）；桥 `send_danmaku`（`player_remote_control_bridge.dart:122`） |
| 播放器内快捷（全屏、画中画、独立窗口、窗口适配） | Action | `ui.set_fullscreen`、`ui.set_picture_in_picture`、`ui.toggle_detached_player`、`ui.resize_to_video`（write，桌面端） |

#### B. 设置页

| 领域 | 入口示例 | 状态 | 建议 |
|---|---|---|---|
| 外观-主题/缩放/背景 | `appearance_settings_content.dart:89-689` | 设置 | `appearance.*`（见 3.1） |
| 通用-窗口行为 | `general_settings_content.dart:81-266` | 设置 | `general.*`；窗口尺寸类为设备级 |
| 播放器-内核/解码/渲染 | `player_settings_content.dart:368-1090` | 设置 | `player.*`；内核切换需重启/重载 |
| 弹幕-渲染/样式/匹配 | `danmaku_settings_content.dart:809-1534` | 设置 | `danmaku.*`（见 4.4） |
| 字幕-字体/样式 | 播放器 pane + 存储页 | 设置 | `subtitle.*`（见 4.4） |
| 存储-截图/缓存 | `storage_settings_content.dart:55-222` | 设置 | `storage.*`；清缓存为 destructive Action |
| 网络-服务器/UA/代理 | `network_settings_content.dart:90-179` | 设置 | `network.*`；自定义服务器 URL 属设置，UA/代理为设备级 |
| 外部播放器 | `external_player_settings_content.dart:79-236` | 设置 | `external_player.*`；路径属设备级 |
| 下载器 | `downloader_settings_content.dart:37-84` | 设置 | `download.*`；已有 `download.add/pause/resume/remove/delete` |
| 开发者选项 | `developer_options_settings_content.dart:47-288` | 设置（部分关闭） | 自签名证书 = 关闭(B)；资源监控/日志 = 设置 |
| 实验室 | `labs_settings_content.dart:29-160` | 设置（部分关闭） | 新版番剧卡片/Erika 内核 = 设置；Agent 接口开关 = 关闭(B) |
| 插件 | `plugin_settings_content.dart` | Action + 设置 | 启用/禁用/导入/删除 = Action；GitHub 代理 = 设置 |
| 关于 | `about_settings_content.dart:58-119` | ui | 链接打开；检查更新为 Action |
| 快捷键 | `shortcuts_settings_page.dart:29-93` | 设置 | `shortcuts.*`（见 3.4） |

#### C. 媒体库 / 账号 / 服务器 / 插件 / 下载

| 入口 | 状态 | 建议 |
|---|---|---|
| 本地文件夹添加/移除/扫描 | 部分已有 | 已有 `media.library.scan`（`media_capability.dart:399`）；补充 `library.add_root` / `library.remove_root`（write/destructive） |
| WebDAV/SMB 连接增删改测 | Action | `library.connection.add/remove/edit/test`（write/destructive） |
| 共享客户端增删改刷新 | Action | `library.shared_host.add/remove/edit/refresh` |
| 媒体库分区顺序 | 设置 | `library.section_order`（string[]，键 `media_library_section_order`） |
| 媒体库来源选择 | ui | 打开添加媒体流程；真正写入由上面的 Action 承担 |
| 弹幕批量/手动匹配 | Action | `danmaku.match`（write） |
| 自定义媒体信息 | Action | `media.metadata.override` 已存在（`media_capability.dart:514`） |
| 账号登录/注册/注销 | 关闭(A) | 需要输入密码，属输入秘密 |
| 保存/删除令牌、Bangumi 授权 | 关闭(A) | 令牌与凭据操作 |
| 增量/全量同步、测试连接、清缓存 | Action（同步） + 关闭(A)（凭据） | 同步可开为 `sync.run`（write）；凭据配置不开放 |
| Jellyfin/Emby 连接（含密码） | 关闭(A)（密码） | 可开放“连接已保存的服务器”`library.server.connect`（write），但不接收密码输入 |
| 远程访问服务开关、端口、IPv6、二维码 | 关闭(B) | 开放局域网远程访问，属 Agent 自我扩权 |
| 受信任设备移除 | 关闭(B) | 设备信任边界 |
| 插件启用/禁用/导入/删除/更新 | Action | `plugin.enable/disable/import/remove/update`（write/destructive）；导入涉及外部脚本，建议 destructive 或需确认 |
| 插件 GitHub 代理 | 设置 | `plugin.github_proxy`（string） |
| 下载任务：刷新/视图/搜索/排序 | ui | 展示与本地过滤 |
| 下载任务：添加磁链/种子 | 已有 | `download.add` |
| 下载任务：暂停/继续/移除/删除 | 已有 | `download.pause/resume/remove/delete` |
| 下载任务：播放完成文件 | 已有 | `playback.open` |
| 下载任务：查看文件夹 | ui | 桌面端打开目录 |

### 2.3 数量统计

按矩阵口径统计（不含“ui”这类纯展示项；同一入口的 Action 与设置分别计数）：

| 状态 | 数量 | 说明 |
|---|---|---|
| 已有 Harness Action | **51** | M1 9 + Task 4 + Download 5 + Media 17 + Danmaku 16 |
| 应成为领域 Action（建议新增） | **约 40** | 播放器（倍速/音量/轨道/偏移/发送弹幕/窗口）、媒体库连接增删改、共享客户端、弹幕匹配、插件管理、同步等 |
| 应进入设置注册表 | **约 130** | 216 个设置构造点中，去重同类项后约 120–140 项 |
| ui.* 即可 | **约 25** | 页面导航、菜单展示、播放信息、列表跳转、打开目录/链接 |
| 刻意不开放 | **约 20** | 秘密输入(A) 约 12；自我扩权(B) 约 8 |

> 说明：Action 与设置两类存在重叠（如弹幕样式既是 pane 操作也是设置项），上表按“入口的一次可操作”计数，非互斥分类。统计为本文按已核实入口的估算，精确值需在 4.5 的 CI 机制落地后以机器统计为准。

---

## 3. 设置注册表的现状基础

### 3.1 SettingsKeys 与分散的私有键

- **集中表**：`lib/constants/settings_keys.dart`，共 **80** 个常量（`static const String`），全部为字面量字符串。示例：`appLanguageMode`（`:4`）、`danmakuOpacity`（`:111`）、`danmakuSupersampleV2`（`:104`）、`labsEnableAgentEndpoint`（`:67`）、`downloaderEnabled`（`:85`）、`githubProxyUrl`（`:97`）。
- **分散私有键**：`lib/constants/settings_keys.dart` 之外，仍有 **约 206** 个私有键常量（脚本按 `*Key = '...'` 统计，排除 `settings_keys.dart`）。集中度最高的文件：
  - `lib/utils/video_player_state.dart`：**57** 个（`_chapterMarkersEnabledKey` `:429` … `_autoFullscreenEnabledKey` `:928`）。
  - `lib/providers/webdav_quick_access_provider.dart`：**19** 个（`:110-134`）。
  - `lib/utils/auto_sync_settings.dart`：**11** 个（`:13-25`）。
  - `lib/providers/appearance_settings_provider.dart`：**10** 个（`:34-48`）。
  - `lib/utils/network_settings.dart`：**7** 个（`:13-19`）。
- **裸字面量直写**：仍有约 **100** 处直接以字符串字面量调用 `prefs.getX/setX`（未走常量），例如 `lib/providers/settings_provider.dart:17`（`'blurPower'`）、`lib/utils/theme_notifier.dart:59`（`'backgroundImageMode'`）、`lib/services/remote_control_settings.dart:9-13`、`lib/services/web_server_service.dart:14-17`。
- **结论**：键空间存在三套来源（集中表、私有常量、裸字面量），且无统一类型/范围/默认值声明。设置注册表需要同时覆盖这三类。

### 3.2 PlayerRemoteControlBridge 已有参数描述能覆盖多少设置

`lib/services/player_remote_control_bridge.dart` 已实现一套“参数描述 + 设值”机制，是设置注册表最接近的现成基础：

- **参数描述**：`_buildParameters`（`:213-855`）按 pane 生成参数列表，共 **51** 个参数键，类型 `bool/double/enum/select/string/string_list/json/readonly`，并带 `min/max/step/options/nullable`（辅助函数 `addBool/addDouble/addEnum/addSelect/addString/addReadOnly` `:229-311`）。
- **可写判定**：`_setParameter`（`:859-1100`）的 `switch` 覆盖 **56** 个 case（含 8 个命令型 case）。
- **可写但无描述的键（8 个）**：`danmaku.blockWords`、`player.pauseOnBackground`、`player.desktopHoverSettingsMenuEnabled`、`player.instantHidePlayerUiEnabled`、`player.useHardwareDecoder`、`seek.skipSeconds`、`seek.speedBoostRate`、`seek.stepSeconds`。这些是“有写入通道但无参数描述”的缺口。
- **有描述但只读的键（11 个）**：`subtitle.fontDir / externalPath / currentLine / currentPositionMs`、`danmaku.fontFilePath / fontFamily / autoOffset / totalCount`、`playbackInfo.detailed`、`playlist.currentVideoPath / animeTitle`。

覆盖范围（按 pane 分布，脚本统计）：字幕设置 18、弹幕设置 17、串流清晰度 4、字幕轨道 2、字幕列表 2、播放列表 2、弹幕偏移 2、弹幕列表 1、音频轨道 1、倍速 1、播放信息 1。

**能覆盖多少设置**（推断）：桥的参数键与播放器/弹幕/字幕的运行时设置高度重合，可覆盖弹幕样式、字幕样式、串播清晰度的大部分运行时项；但它只覆盖“播放中可调”的子集，**不含**设置页里的内核、解码、外观、网络、下载器、实验室、插件等。因此桥是设置注册表在“播放器/弹幕/字幕”三个域的直接素材，而非全量来源。

### 3.3 有副作用或需要重启的设置

已核实的重启/重载类：

- **Android 音频后端**：需重启 APP 生效（`lib/settings/pages/player_settings_content.dart:133`、`:519`）。
- **播放器内核切换**：`PlayerFactory.saveKernelType` 触发内核变更广播与播放器重建（`lib/player_abstraction/player_factory.dart:480-500`）。
- **macOS/Windows 原生视频输出**：保存后向 `MediaKitPlayerAdapter` 推送并广播内核变更（`lib/player_abstraction/player_factory.dart:318-330`）。
- **Erika Android 输出模式**：保存后广播 Erika 内核变更（`lib/player_abstraction/player_factory.dart:355-370`）。
- **远程访问端口**：保存后服务重启（`lib/settings/pages/remote_access_receiver_settings_section.dart:411`）。
- **远程访问自动开启**：下次启动生效（`lib/settings/pages/remote_access_receiver_settings_section.dart:226`）。
- **自定义播放器 UA**：下次打开视频生效（`lib/player_abstraction/player_factory.dart:390-400`）。
- **HTTP 代理**：立即生效（`lib/settings/pages/network_settings_content.dart:566`）。
- **Agent 端点开关**：随 Labs 监听启停端点（`lib/next/next_runtime.dart:130-145`）。
- **时间轴截图预览**：开启有性能副作用并弹确认（`lib/settings/pages/player_settings_content.dart:774-806`）。
- **清空弹幕缓存 / 缓存删除**：破坏性（`lib/settings/pages/storage_settings_content.dart:65-76`）。
- **紧急恢复个人文件 / Linux 存储迁移**：破坏性（`lib/settings/pages/developer_options_settings_content.dart:595-848`）。

推测：凡经 `PlayerFactory` 内核变更广播或 `WebServerService` 重启的项，都应在注册表中标记 `requiresRestart` 或 `reloadScope: player|server`，否则 Agent 设值后无法解释“为什么没生效”。

### 3.4 设备级 vs 用户级

按语义与现有存储位置判断（推测部分已标注）：

**设备级（同账号多设备应各自独立）**：

- 播放器内核、解码、渲染（`player_kernel_type`、`use_hardware_decoder`、`soft_decode_pixel_format`、`hwdec_mode`、Anime4K/CRT profile）——依赖本机 GPU/系统。
- 外观中的窗口尺寸、启动窗口状态/位置/尺寸、画中画位置（`desktop_startup_window_*` `lib/services/desktop_startup_window_preferences.dart:28-31`）、界面缩放、虚拟窗口显示区域。
- 远程访问服务开关、端口、IPv6、自动开启（`web_server_auto_start`/`web_server_port`/`web_server_ipv6_enabled` `lib/services/web_server_service.dart:14-17`）、被遥控端开关（`remote_control_receiver_enabled` `lib/services/remote_control_settings.dart:9`）。
- 信任设备列表（`remote_control_trusted_devices`）、遥控客户端 ID、匹配地址。
- 外部播放器路径（`external_player_path`）、文件选择器最近目录（`last_video_dir` 等 `lib/services/file_picker_service.dart:33-36`）。
- 下载目录与最近目录（`torrent_download_directory`、`torrent_recent_download_directories`）。
- 截图保存目录/默认目标（`screenshot_save_directory`/`screenshot_save_target`）。
- 开发者选项（日志收集、自签名证书、资源监控）——本机行为。
- 实验室（Erika 内核显示、沉浸式详情页）——本机 UI 能力。

**用户级（同账号可跨设备同步）**：

- 语言、主题模式、主题色、界面密度类偏好（`app_language_mode`、主题相关键）。
- 弹幕样式与屏蔽词、字幕样式、防剧透 AI 配置（除 API Key 属秘密）、超采样。
- 观看历史与进度（已由 `watch_history` 与同步机制管理）。
- 媒体库连接（WebDAV/SMB/Jellyfin/Emby 服务器地址与账号）、共享客户端列表。
- 插件启用集合（`plugin_enabled_ids`）与插件设置。
- 下载器开关、自动扫描、为任务建文件夹（`downloader_enabled` 等）。
- WebDAV 快捷入口与搜索参数（`webdav_*`）。

**灰色地带**：弹幕偏移“记住偏移”（`remember_danmaku_offset`）与逐文件偏移既可能被视为用户偏好，也可能是设备/播放位置相关；需在注册表中显式声明 `scope`。

秘密类（Jellyfin/Emby 密码、WebDAV/SMB 密码、`incremental_sync_webdav_password`、`bangumi_access_token`、`dandanplay_token`、`spoiler_ai_api_key`）当前明文存于 SharedPreferences；`docs/next/research/VAULT_AND_MESH.md:34` 已记录其中一项。它们不应进入设置注册表的可读写面，只以引用形式暴露。

---

## 4. 建议的设置注册表契约草案

### 4.1 schema 字段

```jsonc
{
  "key": "danmaku.opacity",              // 稳定、点分、域前缀
  "title": "弹幕透明度",                  // 人类可读
  "description": "面向 Agent：语义、何时改、边界",
  "type": "number",                       // boolean|integer|number|string|enum|string_list|color
  "enumValues": null,                     // type=enum 时的取值
  "minimum": 0.0,
  "maximum": 1.0,
  "step": 0.01,
  "default": 1.0,
  "scope": "user",                        // user | device
  "apply": "immediate",                   // immediate | reload_player | reload_server | restart_app
  "effect": "write",                      // read|write|destructive（对齐 ActionSpec）
  "storage": {
    "kind": "shared_preferences",
    "key": "danmaku_opacity",             // 现存储键（可为 legacy 列表）
    "legacyKeys": [],
    "reader": "lib/utils/video_player_state/video_player_state_preferences.dart:334",
    "writer": "lib/utils/video_player_state/video_player_state_preferences.dart:347"
  },
  "provenance": {
    "changedAt": "2026-10-10T14:03:11Z",
    "changedBy": "user",                  // user | agent | mesh:<deviceId> | migration
    "origin": "gui",                      // gui | mcp | mesh:<deviceId> | task_engine
    "invocationId": "...",                // 与 Invocation 关联
    "reason": "用户要求降低弹幕干扰",
    "previousValue": 0.8,
    "revision": 12
  }
}
```

要点：

- `key` 与 `storage.key` 分离，兼容现存三套键空间（集中表 / 私有常量 / 裸字面量），迁移期不改物理键。
- `provenance` 直接复用 Harness 的 `Invocation`（`origin` + `id`），与 `JsonlJournal`（`docs/next/DESIGN.md` §4）同源，保证 GUI/Agent/任务三条路径可追溯。
- `scope` 支撑将来的 Mesh 与跨设备同步（`docs/next/DESIGN.md` §9.6）。
- `apply` 支撑 §3.3 的副作用/重启语义。

### 4.2 `settings.*` Action 的语义

建议三个通用 Action，均放在新 `SettingsCapability`：

| id | effect | 输入 | 输出 |
|---|---|---|---|
| `settings.describe` | read | `{domain?}` | 设置项 schema 列表（不含秘密项） |
| `settings.get` | read | `{key}` | `{key, value, provenance, revision, scope, apply}` |
| `settings.set` | write | `{key, value, expectedRevision?}` | `{key, value, provenance, revision, apply}` |

语义：

- `settings.set` 走注册表校验（类型/范围/枚举），非法值返回 `Failed(invalidInput, violations)`，与 `Harness.invokeJson` 的既有顺序一致（`docs/next/DESIGN.md` §4）。
- `expectedRevision` 为乐观并发控制：不匹配返回 `Failed(conflict)`，避免 Agent 覆盖用户刚改的值。
- `apply == restart_app` 或 `reload_player` 时，Action 返回 `apply` 字段说明生效时机；不自行重启进程。
- 秘密项与扩权项**不出现在 `describe` 输出**中；对它们的 `get/set` 一律返回 `Failed(notFound)` 或 `Failed(unavailable)`。
- `settings.set` 的 `effect` 恒为 `write`；真正破坏性的设置（清缓存、删除连接）应各自保留为独立 destructive Action，而不是走 `settings.set`。

### 4.3 与 Classic 设置页共存

- **单一事实来源**：Classic 页面继续渲染，但读写统一经注册表（先在 Next 侧实现适配层，再由页面调用）。注册表的 `storage.reader/writer` 指回现有方法，不复制逻辑。
- **不改物理键**：注册表 `key` 是新命名空间，`storage.key` 保留旧键；迁移期双写（写新键 + 旧键）与回退读取（新键缺失时读旧键），与 `danmakuSupersample` → `danmakuSupersampleV2`（`lib/constants/settings_keys.dart:99-104`）的既有做法一致。
- **UI 直连保留**：Classic 直接调用 `SettingsProvider`/`VideoPlayerState` 的 setter 的路径保留，但 setter 内部改为写注册表（带 provenance 记为 `user`）。
- **可见性对齐**：`describe` 返回的项应与当前页可见性一致（例如 `visible: (context, surface) => !globals.isTelevision`，`lib/settings/unified_settings_entries.dart:324`），避免 Agent 看到本机不存在的项。

### 4.4 迁移顺序：先播放器、弹幕、字幕

**理由（核实支撑）**：

1. 这三个域已有最完整的参数描述与写入通道：`PlayerRemoteControlBridge` 的 51 个参数键中，字幕设置 18、弹幕设置 17、倍速 1、串流 4，占绝大部分（`:213-855`）。迁移它们可最大程度复用现成描述，先把契约跑通。
2. 这三个域的风险最低：改动即生效、无网络、无凭据、可回退（多数有 `reset*`）。
3. 这三个域是 Agent 最可能被要求改的（“弹幕太吵”“字幕太小”“慢一点”），收益最快。
4. 副作用语义已经在这些域出现（内核切换、硬件解码、串流重载），可在小范围内先验证 `apply` 字段。

**建议阶段**：

- **P1 播放器**：`playback.rate`、`seek.*`、`player.pauseOnBackground/instantHidePlayerUi/desktopHoverSettingsMenuEnabled/useHardwareDecoder`（这 8 个“有写入无描述”的键优先补齐，见 §3.2）。副作用：内核/解码需 `reload_player`。
- **P2 弹幕**：`danmaku.*` 全部样式与屏蔽词；`danmaku.blockWords`（string_list）补描述。跳过 `spoiler_ai_api_key`（秘密）。
- **P3 字幕**：`subtitle.*` 全量；外挂字幕/字体目录类为路径引用，需作用域校验。
- **P4 之后**：外观、网络、下载器、插件、实验室；账号/服务器凭据类永不进入可读写面。

### 4.5 “覆盖率只升不降”机制（CI）

目标：把 §2 的矩阵变成可回归的机器统计，且**不依赖源码字符串断言**（避免 `grep 'title: ...'` 这类脆弱断言）。

建议做法：

1. **运行时枚举，而非源码扫描**：
   - 新增 `SettingsRegistry`（纯 Dart，放 `packages/nipa_harness` 或 `lib/next/settings`），启动时不依赖 Flutter，直接 `describe()` 返回全部 schema。
   - 测试用 `Harness([SettingsCapability(...)])` 构造并读取 `harness.catalog`（`packages/nipa_harness/lib/src/harness.dart`），得到 Action id 集合——这正是 `test/next/capabilities_contract_test.dart:34` 已在用的方式（`harness.catalog.map((s) => s.id)`）。
   - 覆盖率统计 = `settings.describe` 返回的键集合 + `harness.catalog` 的 Action id 集合。

2. **基线快照 + 只增校验**：
   - 在 `test/next/` 下维护 `capability_coverage_baseline.json`（Action id 列表 + 设置 key 列表，含 `effect` 与 `scope`）。
   - 契约测试：`当前集合 ⊇ 基线集合`；缺失即 fail，并打印缺失项。新增项自动通过（不阻断），但需显式更新基线。
   - 同时断言“新增项必须有 schema 且能通过 `settings.set` 的校验往返”，防止只登记不实现。

3. **行为断言而非文本断言**：
   - 每个设置项至少一条“读默认值 → set → get 回读 → 复原”的往返测试；用真实 setter 与真实存储抽象（可用内存版 `SharedPreferences` mock）。
   - 每个 Action 至少一条 `invokeCompleted`（`test/next/test_support.dart`）契约测试，断言输出 schema 合法（`Schema.validate`），与 `capabilities_contract_test.dart` 的做法一致。
   - 断言 `effect` 与 `readOnlyHint/destructiveHint` 的映射一致（`docs/next/DESIGN.md` §2.2），确保新增项不会把 destructive 错标为 write。

4. **CI 接入**：`pr-validation.yml` 已运行 `flutter test --no-pub --reporter expanded`（`.github/workflows/pr-validation.yml:52-54`），把上述契约测试放进 `test/next/` 即自动纳入；统计数字由测试输出（如 `--reporter json` 解析）生成，不需要额外脚本。

5. **防回退的边界**：对“刻意不开放”的项，维护一份显式 `denylist`（按 key 前缀或秘密字段），并断言它们**不在** `describe` 输出中——这比“源码里不出现某字符串”更稳，因为断言的是运行时契约。

---

## 5. 未决与推测汇总

- **推测**：`media.*`/`danmaku.*` 的 Action 总数（17/16）由 `_spec` 调用点与 `for` 循环展开计算得出；若合并后有新增循环，数量会变。
- **推测**：§2.3 的数量统计为人工估算，精确值需 §4.5 的运行时枚举落地后以机器统计为准。
- **未核实**：Web 平台（`kIsWeb`）下部分设置与 Action 是否可用；本文按桌面/移动/电视主路径描述。
- **未核实**：Mesh 与跨设备同步尚未实现，`scope` 字段是面向未来的契约，当前无运行时消费者。
- **已知冲突**：`lib/next/next_runtime.dart` 与 `lib/next/tasks/sqlite_job_store.dart` 含冲突标记；本文按两侧意图（NextCore 持有唯一引擎、NextRuntime 构建 Harness）理解，不代表最终合并结果。