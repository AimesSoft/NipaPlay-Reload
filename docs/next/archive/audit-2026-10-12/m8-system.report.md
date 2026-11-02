**结论：不是全部覆盖。** 常规设置项覆盖较完整，但多端增量同步、窗口与托盘控制、手动更新、Linux 存储修复、设置及对话框的界面入口仍有明确缺口；备份、背景导入、插件登录入口等存在部分覆盖。还发现能力绕过 Classic 确认或输入检查的路径。

审计分支为 `next/capability-layer`。以下是只读代码审计结果，未修改文件、构建或运行应用。“已覆盖”指能够完成相同业务操作；打开界面、操作当前窗口或对话框也作为独立操作核对。密码等秘密的代填不计为缺失，但发起用户输入流程仍需覆盖。

**先列出本块相关能力**

| 类别 | 已注册能力或设置 |
|---|---|
| 通用设置 | `settings.describe`、`settings.get`、`settings.set`、`settings.reset`、`settings.history`；支持批量、版本检查和变更来源。[定义](~/Desktop/NipaPlay-Reload/lib/next/settings/capability.dart:68) |
| 设置注册项 | `general.*`、`appearance.*`、`language.mode`、`diagnostics.*`、两个实验室开关、`shortcuts.*`、动态插件设置，以及外观页涉及的 `player.*`、`danmaku.showDensityChart`。[Classic 注册表](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:94) |
| Harness 路径 | `settings.get/set/reset`，键 `next.harnessPath`；此项在 settings 目录之外注册。[定义](~/Desktop/NipaPlay-Reload/lib/next/harness_location.dart:27) |
| 备份 | `backup.export`、`backup.preview`、`backup.restore`、`backup.history_export`、`backup.history_restore`。[定义](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:37) |
| 插件 | `plugins.list`、`plugins.market`、`plugins.install`、`plugins.set_enabled`、`plugins.delete`、`plugins.invoke`。[定义](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:146) |
| 诊断 | `diagnostics.logs`、`diagnostics.export`、`diagnostics.clear`、`diagnostics.directory`。[定义](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:273) |
| 重置 | `appearance.reset_home_sections`、`shortcuts.reset`；实验室下的快捷设置还有 `webdav_quick.reset`。[定义](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:340) |
| 打开与界面观察 | `ui.open`、`ui.capture`、`app.instance`；文件打开还有 `playback.open`，目录授权有 `playback.authorize_directory`。[打开定义](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:21) |
| state.query | 本块直接相关的是 `settings.changes`、`activity`；没有发现窗口列表、更新结果、系统资源、同步状态、构建信息或依赖版本的专用视图。[设置变更视图](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:542)、[活动视图](~/Desktop/NipaPlay-Reload/lib/next/state/activity.dart:56) |

上述能力确实进入运行时 Harness，不只是未使用的定义：[核心注册](~/Desktop/NipaPlay-Reload/lib/next/next_core.dart:120)、[运行时注册](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:209)。

**1. 缺失，按用户影响排序**

| 优先级 | Classic 中的操作、入口及实际方法 | 对照结果 |
|---|---|---|
| 高 | 开发者选项 → Linux“紧急恢复个人文件”：确认后调用 `LinuxStorageMigration.emergencyRestorePersonalFiles`。[调用点](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:774) | 无恢复 Action、设置或视图；误迁移文件无法通过能力恢复。 |
| 高 | 开发者选项 → Linux“手动触发存储迁移”：确认后 `resetMigrationStatus` → `performMigration`。[调用点](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:627) | 无对应能力。 |
| 高 | 备份恢复 → WebDAV 多端同步设置：服务器地址、用户名、远端目录、同步间隔、数据类别、记录变更时同步；保存调用 `AutoSyncSettings.saveWebDavConfiguration`，随后重新调度。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:134) | 无设置注册项或 Action；这些非秘密参数也无法正常配置。 |
| 高 | 同步设置对话框 →“测试连接”：`AutoSyncService.testConnection`。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:791) | 无对应能力。 |
| 高 | 备份恢复 → 开启多端同步：`AutoSyncService.enable`；未配置时先打开配置对话框。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:106) | 无开启及发起用户配置流程的能力。 |
| 高 | 备份恢复 → 关闭多端同步：`AutoSyncService.disable`。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:119) | 无对应能力。 |
| 高 | 备份恢复 →“立即同步”：`AutoSyncService.manualSync`。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:177) | `.npb/.nph` 备份 Action 不能替代增量同步；没有立即同步能力。 |
| 高 | 备份恢复 → 查看上次同步时间、错误及当前配置：`AutoSyncSettings` 的读取方法。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:73) | 无对应状态视图。 |
| 高 | 主窗口关闭按钮、Cmd+W → 退出对话框：取消并返回、最小化到托盘、退出、记住选择；由 `DesktopExitHandler` 执行。[入口](~/Desktop/NipaPlay-Reload/lib/main.dart:1096)、[决策与执行](~/Desktop/NipaPlay-Reload/lib/services/desktop_exit_handler.dart:135) | 只能设置未来的关闭行为，不能发起关闭、选择当前退出对话框或退出应用。`playback.close` 仅关闭播放。 |
| 高 | 托盘单击／右键“显示播放器”：`_showMainWindow`；“退出播放器”：`_exitApp`。[调用点](~/Desktop/NipaPlay-Reload/lib/services/desktop_exit_handler.dart:519) | 无显示、聚焦、托盘菜单或退出 Action。 |
| 中高 | 主窗口标题栏：最小化、最大化／还原、拖动；标题栏双击也切换最大化。[按钮入口](~/Desktop/NipaPlay-Reload/lib/main.dart:2078)、[方法](~/Desktop/NipaPlay-Reload/lib/main.dart:1769)、[拖动入口](~/Desktop/NipaPlay-Reload/lib/main.dart:2039) | 启动窗口设置不控制当前窗口；无对应 Action。 |
| 中高 | 独立播放器：移出／移回主窗口、定位窗口；对应 `detachPlayer`、`returnPlayerToMain`、`focusDetachedPlayer`。[W 快捷键](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:900)、[定位／移回按钮](~/Desktop/NipaPlay-Reload/lib/widgets/desktop_player_page_slot.dart:25) | 无对应 Action；没有窗口列表视图。 |
| 中高 | 画中画：从主窗口拆离并进入、进入／退出已有独立窗口的画中画。[P 快捷键调用](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:881) | `general.pictureInPicturePosition` 只改停靠位置，不能切换画中画。 |
| 中高 | 独立窗口全屏；主／独立窗口适配视频尺寸。[全屏服务](~/Desktop/NipaPlay-Reload/lib/services/desktop_player_window_service.dart:129)、[R 快捷键](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:869) | 无当前窗口全屏、尺寸适配 Action。 |
| 中高 | 关于 →“检查更新”：`UpdateService.checkForUpdates`；查看最新版本、发布日期、更新说明、错误，再打开发布页及说明中的链接。[调用点](~/Desktop/NipaPlay-Reload/lib/settings/pages/about_settings_content.dart:476)、[结果与发布页](~/Desktop/NipaPlay-Reload/lib/settings/pages/about_settings_content.dart:515) | 只有自动检查开关和当前版本；缺手动检查、结果查询及发布页打开能力。 |
| 中 | 实验室 → 开启／关闭 NipaPlay Next；开启前显示风险确认，再调用 `setEnableAgentEndpoint`。[调用点](~/Desktop/NipaPlay-Reload/lib/settings/pages/labs_settings_content.dart:135) | 明确被设置 denylist 禁止；无正常启停或发起确认流程的 Action。[禁止项](~/Desktop/NipaPlay-Reload/lib/next/settings/denylist.dart:15) |
| 中 | Windows 配套安装／卸载文件关联；安装脚本注册扩展名与“打开方式”，卸载脚本删除注册项。[安装](~/Desktop/NipaPlay-Reload/windows/install_file_association.bat:35)、[卸载](~/Desktop/NipaPlay-Reload/windows/uninstall_file_association.bat:25) | 无文件关联注册、移除或状态查询能力。此项是仓库配套系统工具，不是应用内设置按钮。 |
| 中 | 日志查看器 → 上传日志、生成分享二维码、复制分享链接：`LogShareService.uploadLogs`。[调用点](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:638)、[上传服务](~/Desktop/NipaPlay-Reload/lib/services/log_share_service.dart:48) | `diagnostics.export` 只写本地文件，不能生成线上分享链接或二维码。 |
| 中 | 日志查看器 → 复制全部日志、复制单条日志到系统剪贴板。[全部](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:347)、[单条](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:392) | 可以读取文本，但没有写剪贴板的 Action。 |
| 中 | 打开设置窗口：统一设置按钮、Cmd+,；打开关于子页：macOS“关于”。[统一入口](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_app_page_actions.dart:88)、[菜单入口](~/Desktop/NipaPlay-Reload/lib/main.dart:1064) | `ui.open.page` 只接受 `primaryOrder`，其中没有 `settings`，也无 `initialSubpageId` 参数。[允许页面](~/Desktop/NipaPlay-Reload/lib/app/app_page_ids.dart:14) |
| 中 | 设置等虚拟窗口：移动、关闭；当前对话框的确认、取消、返回、关闭。[移动与关闭](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/nipaplay_window.dart:147) | 无窗口／对话框操作能力。`ui.capture` 只能观察，不能点击或提交。 |
| 中低 | 开发者选项 → 查看／刷新依赖版本，点击依赖打开仓库；`DependencyVersionsLoader.load`、`launchUrl`。[方法](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/dependency_versions_window.dart:21) | 无数据查询或打开该窗口的能力；当前应用版本不能替代依赖版本。 |
| 中低 | 开发者选项 → 构建信息：`loadBuildInfoSections`。[调用点](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:451) | `app.instance` 只有运行实例与应用版本等信息，不含该页的完整构建信息，也不能打开对话框。 |
| 中低 | Linux → 检查迁移状态、显示数据／缓存目录及 XDG 环境信息。[迁移状态](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:583)、[目录信息](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:719) | 无相应视图；`diagnostics.directory` 只查询日志目录。 |
| 低 | 插件市场 → 查看插件 README、返回市场。[方法](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/plugin_market_dialog.dart:259) | `plugins.market` 返回市场元数据，没有 README 内容或打开 README 的能力。 |
| 低 | 关于／帮助菜单 → 打开开源社区、仓库、QQ群、官网、爱发电；电视端显示这些链接的二维码；显示赞赏码。[链接入口](~/Desktop/NipaPlay-Reload/lib/settings/pages/about_settings_content.dart:58)、[二维码方法](~/Desktop/NipaPlay-Reload/lib/settings/pages/about_settings_content.dart:581)、[菜单](~/Desktop/NipaPlay-Reload/lib/main.dart:1086) | 无打开普通网页或发起这些二维码窗口的能力。 |
| 低 | 实验室 →“打开 Harness 仓库”：`FolderOpener.open`。[调用点](~/Desktop/NipaPlay-Reload/lib/settings/pages/labs_settings_content.dart:152) | 路径可读写，但不能在系统文件管理器中打开。 |
| 低 | 日志查看器 → 显示时间戳、自动滚动、滚动到末尾。[方法及保存键](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:453)、[滚动方法](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:313) | 两个持久显示设置未注册，也没有操作当前日志界面的 Action。 |
| 低 | 开发者选项 → 打开 UI 预览；预览内切换 Tab、示例开关、三种下拉值、重置示例。[打开](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:436)、[示例控件](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/nipaplay_ui_preview_window.dart:84)、[重置](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/nipaplay_ui_preview_window.dart:267) | 无对应能力。示例中另有空回调按钮，代码上没有业务副作用。 |
| 低 | macOS 系统菜单 → 隐藏本应用、隐藏其他应用、显示全部应用、排列窗口到前面。[菜单定义](~/Desktop/NipaPlay-Reload/lib/platform_menu/macos_platform_menu.dart:120) | 无对应 Action；操作由系统提供。 |

**2. 部分覆盖**

| 操作 | 已有能力 | 具体缺少什么 |
|---|---|---|
| 导出完整备份 | `backup.export` | 类别与文件内容流程复用 Classic，但没有传入当前 `appVersion`，服务默认写空字符串；Classic 会读取并写入版本。也没有 iOS 系统保存／分享面板流程。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:296)、[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:45) |
| 备份恢复预览 | `backup.preview` | 返回版本、类别和主要数量，但遗漏 Classic 用于显示的 `hasDandanplayRemote`、`hasNipaplayShare`。[Classic 显示](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:1605)、[Action 输出](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:65) |
| 单独恢复剧集匹配 | `backup.restore` | 数据恢复可执行，但 Action 仅在 `watchHistoryResult != null` 时刷新内存历史；Classic 恢复后会刷新历史。单选 `episodeMatches` 时缺这一步。[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:99)、[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:414)、[数据库修改](~/Desktop/NipaPlay-Reload/lib/services/full_backup_service.dart:1075) |
| 导出观看进度 | `backup.history_export` | 能写 `.nph`；缺 iOS 系统导出／分享流程。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:495) |
| 自定义背景图片 | `settings.set`：`appearance.customBackgroundPath`、`appearance.backgroundImageMode` | 能引用授权路径并显示背景；没有 Classic 的图库选择、图片处理、复制到应用 backgrounds 目录及清理旧副本流程。引用外部路径也不具备应用内副本的稳定性。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:844)、[注册项](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:286) |
| Android 背景权限流程 | 同上 | 缺发起媒体权限请求及“去系统设置”操作；这些不是代填秘密。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:766) |
| 菜单“上传视频”／Cmd+U | `playback.open`、`ui.open(path)` | 已知文件路径可以打开；缺发起 `FilePickerService.pickVideoFile` 的能力。现有 `playback.authorize_directory` 只打开目录选择器。[Classic](~/Desktop/NipaPlay-Reload/lib/main.dart:2235) |
| 启动参数 `--load-js` | `plugins.install`＋`plugins.set_enabled` | 新插件或较高版本可导入并启用；不能等价执行同版本脚本重载。Classic `loadStartupScript` 明确使用 `allowSameVersionUpdate: true`，安装 Action 未传此选项。[Classic 服务](~/Desktop/NipaPlay-Reload/lib/plugins/plugin_service.dart:1430)、[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:199) |
| 系统资源监控 | `settings.set`：`diagnostics.showSystemResources`，另可 `ui.capture` | 开关覆盖；没有 CPU、内存、FPS、GPU、热状态等结构化查询。主窗口实际显示时可尝试截图观察，不能当作完整遥测接口。[Classic 指标](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/system_resource_display.dart:80) |
| 日志关键词搜索 | `diagnostics.logs` | 支持 tag、level、分页；缺关键词参数。Agent 可以逐页取出后自行过滤，但能力不能直接执行 Classic 的 message 关键词搜索。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:120)、[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:273) |
| 打开日志目录 | `diagnostics.directory` | 只返回路径，没有调用 `FileLogService.openLogDirectory`。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:329) |
| 外部控制台切换为独立窗口 | `settings.set`：`player.externalConsoleWindowMode` | 保存模式覆盖，但 Classic 开关还会立即 `showControlsWindow`／`closeAll`；注册项只调用设置 provider。缺当前会话立即开关窗口的副作用及独立弹幕列表窗口控制。[Classic](~/Desktop/NipaPlay-Reload/lib/settings/pages/external_player_settings_content.dart:199)、[注册项](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:906) |
| 插件非秘密设置与登录入口 | `settings.set` 动态插件键、`plugins.invoke` | 非秘密开关／文本和已暴露 action 均可调用；秘密文本项被过滤。如果插件只提供秘密文本输入、没有登录 action，就缺打开用户输入表单的能力。具体插件是否提供登录 action **待确认**，不能由通用注册代码保证。[过滤及注册](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:773) |
| 虚拟窗口双击切换显示区域 | `settings.set`：`appearance.windowDisplayMode` | 模式结果覆盖；Classic 双击还会把当前窗口偏移归零，设置 Action 不操作当前窗口的 `_offset`。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/nipaplay_window.dart:153) |

备份与日志导出 Action 还统一拒绝覆盖已有文件：[检查](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:408)。Classic 日志保存则直接写入选择的路径；因此“覆盖指定现有日志文件”也未完全覆盖。[Classic 写入](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:376)

**3. 已覆盖：一行一个操作**

下表设置项均通过 `settings.get/set` 读写，也可通过 `settings.describe/reset` 查询契约或恢复默认。文件位置是 Classic 调用点；注册表绑定同一个 provider／服务方法。

| 操作 | Classic 方法与位置 | 能力 id／设置键 |
|---|---|---|
| 关闭窗口默认行为：询问、最小化、退出 | `DesktopExitPreferences.save`，[通用:97](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:97) | `settings.set`：`general.desktopExitBehavior` |
| 启动窗口化／最大化 | `saveState`，[通用:127](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:127) | `settings.set`：`general.startupWindowState` |
| 启动窗口五种位置 | `savePosition`，[通用:165](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:165) | `settings.set`：`general.startupWindowPosition` |
| 启动窗口预设／自定义宽高 | `_saveStartupWindowSize` → `saveSize`，[通用:567](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:567) | `settings.set`：`general.startupWindowWidth`、`general.startupWindowHeight` |
| 恢复默认启动窗口尺寸 | `resetSize`，[通用:576](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:576) | `settings.reset`：上述宽、高两键 |
| 画中画四角停靠位置，包括更新当前放置 | `savePosition`＋`updatePictureInPicturePlacement`，[通用:250](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:250) | `settings.set`：`general.pictureInPicturePosition` |
| 默认展示页面 | `_saveDefaultPagePreference`，[通用:502](~/Desktop/NipaPlay-Reload/lib/settings/pages/general_settings_content.dart:502) | `settings.set`：`general.defaultHomeTab` |
| 自动检查更新开关 | `UpdateService.setAutoCheckEnabled`，[服务:30](~/Desktop/NipaPlay-Reload/lib/services/update_service.dart:30) | `settings.set`：`general.autoCheckUpdates` |
| 明亮／深色／跟随系统 | `ThemeNotifier.themeMode`，[外观:116](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:116) | `settings.set`：`appearance.themeMode` |
| 统一页面上的主题切换按钮 | `_toggleTheme`，[按钮:71](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_app_page_actions.dart:71) | `settings.set`：`appearance.themeMode`，选择 light／dark |
| 主题色 | `setAccentColorPreset`，[外观:140](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:140) | `settings.set`：`appearance.accentColor` |
| 底部进度条开关 | `setMinimalProgressBarEnabled`，[外观:158](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:158) | `settings.set`：`player.minimalProgressBarEnabled` |
| 弹幕密度曲线开关 | `setShowDanmakuDensityChart`，[外观:171](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:171) | `settings.set`：`danmaku.showDensityChart` |
| 底部进度条颜色 | `setMinimalProgressBarColor`，[外观:190](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:190) | `settings.set`：`player.minimalProgressBarColor` |
| 顶部发送弹幕按钮显示 | `setPlayerTopSendDanmakuButtonVisible`，[外观:209](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:209) | `settings.set`：`player.topSendDanmakuButtonVisible` |
| 顶部跳过按钮显示 | `setPlayerTopSkipButtonVisible`，[外观:228](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:228) | `settings.set`：`player.topSkipButtonVisible` |
| 顶部窗口适配按钮显示 | `setPlayerTopResizeButtonVisible`，[外观:247](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:247) | `settings.set`：`player.topResizeButtonVisible` |
| 顶部逐帧按钮显示 | `setPlayerTopFrameStepButtonsVisible`，[外观:266](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:266) | `settings.set`：`player.topFrameStepButtonsVisible` |
| 番剧卡片简介显示 | `setShowAnimeCardSummary`，[外观:290](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:290) | `settings.set`：`appearance.showAnimeCardSummary` |
| 媒体库 NEW 标识 | `setShowMediaLibraryNewBadge`，[外观:308](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:308) | `settings.set`：`appearance.showMediaLibraryNewBadge` |
| 低清海报晕染 | `setDiffuseLowResolutionPosters`，[外观:326](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:326) | `settings.set`：`appearance.diffuseLowResolutionPosters` |
| 目录名省略／多行 | `setFolderNameDisplayMode`，[外观:362](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:362) | `settings.set`：`appearance.folderNameDisplayMode` |
| 首页新番回顾显示 | `setShowQuarterlyAnimeReview`，[外观:386](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:386) | `settings.set`：`appearance.showQuarterlyAnimeReview` |
| 首页推荐轮播大图显示 | `setShowHomeHeroBanner`，[外观:404](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:404) | `settings.set`：`appearance.showHomeHeroBanner` |
| 首页上方推荐小卡片显示 | `setShowHomeHeroSideCardTop`，[外观:423](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:423) | `settings.set`：`appearance.showHomeHeroSideCardTop` |
| 首页下方推荐小卡片显示 | `setShowHomeHeroSideCardBottom`，[外观:442](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:442) | `settings.set`：`appearance.showHomeHeroSideCardBottom` |
| 拖动首页分区排序 | `reorderSections`，[外观:462](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:462) | `settings.set`：`appearance.homeSectionsOrder` |
| 启用／隐藏首页分区 | `setSectionEnabled`，[外观:464](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:464) | `settings.set`：`appearance.homeSectionsDisabled` |
| 恢复默认首页分区 | `restoreDefaults`，[外观:475](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:475) | `appearance.reset_home_sections` |
| 自动适配界面大小 | `setAutomaticUiScale`，[外观:498](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:498) | `settings.set`：`appearance.automaticUiScale` |
| 手动界面缩放 | `setUiScale`，[外观:515](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:515) | `settings.set`：`appearance.uiScale` |
| 虚拟窗口窗口化／铺满屏幕 | `setWindowDisplayMode`，[外观:559](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:559) | `settings.set`：`appearance.windowDisplayMode` |
| 背景：两种看板娘、关闭、自定义模式 | `backgroundImageMode`，[外观:585](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:585) | `settings.set`：`appearance.backgroundImageMode` |
| 背景毛玻璃档位 | `setBlurPower`，[外观:650](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:650) | `settings.set`：`appearance.blurPower` |
| 背景不透明度／柔光渲染 | `backgroundImageRenderMode`，[外观:684](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:684) | `settings.set`：`appearance.backgroundRenderMode` |
| 背景颜色叠加强度 | `backgroundImageOverlayOpacity`，[外观:708](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:708) | `settings.set`：`appearance.backgroundOverlayOpacity` |
| 自动／简体／繁体／英文 | `AppLanguageProvider.setMode`，[语言:57](~/Desktop/NipaPlay-Reload/lib/settings/pages/language_settings_content.dart:57) | `settings.set`：`language.mode` |
| 允许自签名证书 | `setAllowInvalidCertsGlobal`，[开发者:64](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:64) | `settings.set`：`network.allowInvalidCertificates` |
| 显示系统资源监控开关 | `setShowSystemResources`，[开发者:103](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:103) | `settings.set`：`diagnostics.showSystemResources` |
| 调试日志收集启停 | provider＋`startCollecting/stopCollecting`，[开发者:121](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:121) | `settings.set`：`diagnostics.collectLogs` |
| 日志文件写入启停 | provider＋`FileLogService.start/stop`，[开发者:307](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:307) | `settings.set`：`diagnostics.fileLog` |
| 防剧透 AI 响应调试输出 | `setSpoilerAiDebugPrintResponse`，[开发者:208](~/Desktop/NipaPlay-Reload/lib/settings/pages/developer_options_settings_content.dart:208) | `settings.set`：`danmaku.spoilerAiDebugPrintResponse` |
| 新版番剧详情页开关 | `setEnableImmersiveAnimeDetail`，[实验室:48](~/Desktop/NipaPlay-Reload/lib/settings/pages/labs_settings_content.dart:48) | `settings.set`：`labs.enableImmersiveAnimeDetail` |
| 显示 Erika 内核开关 | `setEnableErikaPlayerKernel`，[实验室:68](~/Desktop/NipaPlay-Reload/lib/settings/pages/labs_settings_content.dart:68) | `settings.set`：`labs.enableErikaPlayerKernel` |
| 修改 Harness 仓库路径 | `NextRuntime.setHarnessPath`，[实验室:195](~/Desktop/NipaPlay-Reload/lib/settings/pages/labs_settings_content.dart:195) | `settings.set`：`next.harnessPath` |
| 查看应用当前版本 | `PackageInfo.fromPlatform`，[关于:442](~/Desktop/NipaPlay-Reload/lib/settings/pages/about_settings_content.dart:442) | `app.instance` |
| 列出已安装插件、版本、启用／载入状态及错误 | `PluginService.plugins`，[插件页:67](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:67) | `plugins.list` |
| 检查插件更新／刷新市场 | `fetchRemotePlugins`，[插件页:220](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:220) | `plugins.market(refresh:true)` |
| 市场按名称、作者、说明、标签筛选 | `_onSearchChanged`，[市场:194](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/plugin_market_dialog.dart:194) | `plugins.market` 返回这些字段，可由 Agent 筛选 |
| 导入本地插件 | `importPluginScript`，[插件页:327](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:327) | `plugins.install(path)` |
| 市场安装／更新插件 | `importPluginFromContent`，[市场:306](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/plugin_market_dialog.dart:306) | `plugins.install(remoteId, updateForId)` |
| 启用／停用插件 | `setPluginEnabled`，[插件页:239](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:239) | `plugins.set_enabled`；或 `settings.set`：`plugins.enabled.<编码id>` |
| 删除非内置插件 | `deletePlugin`，[插件页:256](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:256) | `plugins.delete`；确认差异见第4节 |
| 修改插件非秘密开关 | `setSwitchSettingValue`，[插件页:656](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:656) | `settings.set`：`plugins.settings.<编码插件id>.<编码项id>` |
| 修改插件非秘密文本 | `setTextSettingValue`，[插件页:681](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:681) | `settings.set`：同上动态键 |
| 选择并执行插件 action、读取其结果 | `invokePluginUiAction`，[插件页:893](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:893) | `plugins.invoke(id, actionId)` |
| 保存／清除 GitHub 代理 | `setGithubProxyUrl`，[插件页:468](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:468) | `settings.set`：`plugins.githubProxyUrl`；检查差异见第4节 |
| 恢复 `.npb` 所选类别的数据 | `FullBackupService.importBackup`，[备份页:409](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:409) | `backup.restore(categories)`；匹配单选刷新差异见第2节 |
| 恢复 `.nph` 观看进度 | `BackupService.importWatchHistory`，[备份页:563](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:563) | `backup.history_restore` |
| 按日志级别／标签读取日志 | `_getFilteredLogs`，[日志页:120](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:120) | `diagnostics.logs(level, tag)` |
| 查看日志统计 | `getLogStatistics`，[日志页:397](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:397) | `diagnostics.logs` 的 `statistics` |
| 导出日志到新文件 | `exportLogs`＋文件写入，[日志页:355](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:355) | `diagnostics.export(path)` |
| 清空内存日志 | `DebugLogService.clearLogs`，[日志页:323](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:323) | `diagnostics.clear`；确认差异见第4节 |
| 拖放文件后打开播放 | `_handleDroppedFile` → `PlaybackService.play`，[主界面:1266](~/Desktop/NipaPlay-Reload/lib/main.dart:1266) | `playback.open(path)`、`ui.open(path)` |
| 启动参数／`NIPAPLAY_AUTOPLAY_FILE` 指定文件播放 | `LaunchFileHandler.handle`，[方法](~/Desktop/NipaPlay-Reload/lib/utils/launch_file_handler.dart:8) | `playback.open(path)` |
| 文件关联收到文件后播放 | 文件监听 → `LaunchFileHandler.handle`，[入口](~/Desktop/NipaPlay-Reload/lib/main.dart:1497) | `playback.open(path)`；不包含关联注册和移除 |
| macOS 导航菜单／Cmd+数字切换可见主页面 | `_navigateToPage`，[菜单绑定](~/Desktop/NipaPlay-Reload/lib/main.dart:1053) | `ui.open(page)`，限当前可见主页面 |

快捷键配置作为系统设置核对：19 个动作都由同一个 `HotkeyService.updateShortcut` 修改，[Classic 调用](~/Desktop/NipaPlay-Reload/lib/pages/shortcuts_settings_page.dart:128)、[逐键注册](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:576)。

| 操作 | 能力 id／设置键 |
|---|---|
| 修改播放／暂停键 | `settings.set`：`shortcuts.play_pause` |
| 修改全屏键 | `settings.set`：`shortcuts.fullscreen` |
| 修改后退键 | `settings.set`：`shortcuts.rewind` |
| 修改前进键 | `settings.set`：`shortcuts.forward` |
| 修改弹幕开关键 | `settings.set`：`shortcuts.toggle_danmaku` |
| 修改音量增加键 | `settings.set`：`shortcuts.volume_up` |
| 修改音量降低键 | `settings.set`：`shortcuts.volume_down` |
| 修改加速键 | `settings.set`：`shortcuts.speed_up` |
| 修改减速键 | `settings.set`：`shortcuts.speed_down` |
| 修改速度重置键 | `settings.set`：`shortcuts.speed_reset` |
| 修改上一话键 | `settings.set`：`shortcuts.previous_episode` |
| 修改下一话键 | `settings.set`：`shortcuts.next_episode` |
| 修改发送弹幕键 | `settings.set`：`shortcuts.send_danmaku` |
| 修改跳过键 | `settings.set`：`shortcuts.skip` |
| 修改逐帧前进键 | `settings.set`：`shortcuts.step_forward` |
| 修改逐帧后退键 | `settings.set`：`shortcuts.step_backward` |
| 修改窗口适配键 | `settings.set`：`shortcuts.resize_to_video` |
| 修改画中画键 | `settings.set`：`shortcuts.toggle_picture_in_picture` |
| 修改独立窗口键 | `settings.set`：`shortcuts.toggle_detached_player` |
| 恢复全部快捷键默认值 | `shortcuts.reset`；[Classic 方法](~/Desktop/NipaPlay-Reload/lib/pages/shortcuts_settings_page.dart:135) |

实验室打开的 WebDAV 快捷设置子页只核对设置操作，不延伸到远程媒体浏览：

| 操作 | Classic 调用点 | 能力 id／设置键 |
|---|---|---|
| 显示 WebDAV Tab | [89](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:89) | `settings.set`：`webdavQuick.showTab` |
| 默认主页 | [110](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:110) | `settings.set`：`general.defaultHomeTab` |
| 默认服务器 | [147](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:147) | `settings.set`：`webdavQuick.defaultServerName` |
| 默认目录 | [159](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:159) | `settings.set`：`webdavQuick.defaultDirectory` |
| 文件排序 | [178](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:178) | `settings.set`：`webdavQuick.sortPreset` |
| 路径导航开关 | [186](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:186) | `settings.set`：`webdavQuick.showPathBreadcrumb` |
| 自动进入 Season 文件夹 | [201](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:201) | `settings.set`：`webdavQuick.autoEnterSeasonFolder` |
| Season 预设／自定义匹配模式 | [221](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:221) | `settings.set`：`webdavQuick.seasonFolderPattern` |
| bgmid 快速匹配开关 | [232](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:232) | `settings.set`：`webdavQuick.bgmIdQuickMatch` |
| bgmid 匹配规则 | [245](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:245) | `settings.set`：`webdavQuick.bgmIdMatchPattern` |
| tmdbId 快速匹配开关 | [255](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:255) | `settings.set`：`webdavQuick.tmdbIdQuickMatch` |
| tmdbId 匹配规则 | [268](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:268) | `settings.set`：`webdavQuick.tmdbIdMatchPattern` |
| 自动剧集偏移开关 | [278](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:278) | `settings.set`：`webdavQuick.episodeOffsetEnabled` |
| 文件搜索开关 | [292](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:292) | `settings.set`：`webdavQuick.enableSearch` |
| 搜索范围 | [310](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:310) | `settings.set`：`webdavQuick.searchScope` |
| 搜索深度 | [323](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:323) | `settings.set`：`webdavQuick.searchDepthLimit` |
| 搜索文件夹开关 | [333](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:333) | `settings.set`：`webdavQuick.searchTargets` 中的 `folder` |
| 搜索视频开关 | [343](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:343) | `settings.set`：`webdavQuick.searchTargets` 中的 `video` |
| 搜索超时 | [361](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:361) | `settings.set`：`webdavQuick.searchTimeout` |
| 请求间隔 | [373](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:373) | `settings.set`：`webdavQuick.searchRequestInterval` |
| 最大结果数 | [386](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:386) | `settings.set`：`webdavQuick.searchMaxResults` |
| 重置全部快捷设置 | `resetSettings`，[402](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:402) | `webdav_quick.reset` |

**4. 反方向的风险**

1. **删除、恢复、日志清空可以跳过 Classic 的用户确认。**

   | 操作 | Classic 要求 | 能力执行 |
   |---|---|---|
   | 删除插件 | 设置页及市场均先确认。[设置页](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:256)、[市场](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/plugin_market_dialog.dart:363) | `plugins.delete` 直接调用服务。[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:232) |
   | 完整备份恢复 | 预览、选择类别后，再确认。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:385) | `backup.restore` 直接执行恢复。[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:84) |
   | 观看进度恢复 | 先确认。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/backup_restore_page.dart:545) | `backup.history_restore` 直接执行。[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:133) |
   | 桌面日志清空 | “确认清空”对话框。[Classic](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart:323) | `diagnostics.clear` 直接清空。[Action](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:327) |

   JSON 接口虽然默认预览 destructive 操作，但调用方传 `execute=true` 即可执行：[接口](~/Desktop/NipaPlay-Reload/lib/next/agent_endpoint.dart:297)。Harness 校验后直接调用 `action.run`，没有用户确认关卡：[执行](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/harness.dart:110)。手机 Cupertino 日志页本来就直接清空，以上日志确认差异限定桌面页。

2. **备份恢复绕过设置注册表的禁用项和参数校验。**  
   `backup.restore` 把 preferences 交给 Classic 恢复服务，服务按键直接写 SharedPreferences，没有调用 `SettingsRegistry.set` 或 `isSettingDenied`。[写入](~/Desktop/NipaPlay-Reload/lib/services/full_backup_service.dart:725) Rust 恢复计划也只检查该类别是对象，没有逐键过滤：[解析](~/Desktop/NipaPlay-Reload/rust/src/api/incremental_sync.rs:300)。

   因而，备份中的 `labs_enable_agent_endpoint` 等键可以被写入，尽管普通设置能力禁止它；实验室开关页面本来要求风险确认。其影响是**持久值及后续启动**，不是保证即时改变 provider。[加载开关](~/Desktop/NipaPlay-Reload/lib/providers/labs_settings_provider.dart:42) Classic 自己的备份恢复同样采用原始写入；这里额外的问题是 Agent 恢复没有保留 Classic 的恢复确认，也没有守住 Next 注册表边界。

3. **GitHub 代理可以保存 Classic 设置页拒绝的值。**  
   Classic 要求 HTTP(S)、末尾 `/`、有效 authority，并测试请求成功才保存。[格式检查](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:998)、[连通性检查](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:503) 注册项只是 `StringSchema`，直接调用只 trim 并保存的 setter。[注册项](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:524)、[setter](~/Desktop/NipaPlay-Reload/lib/providers/settings_provider.dart:358)

4. **快捷键冲突确认被跳过。**  
   Classic 检测重复快捷键后要求“替换／取消”。[Classic](~/Desktop/NipaPlay-Reload/lib/pages/shortcuts_settings_page.dart:366) 注册项只检查快捷键能否解析，然后直接 `updateShortcut`；该服务不检查冲突。[注册项](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:576)、[服务](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:1038)

5. **部分参数能超出 Classic 此入口提供的选项。**  
   外观页进度条颜色提供五个预设，而注册项接受全部 32 位 ARGB；背景模糊页提供离散档位，而注册项接受区间内任意数值。[Classic 颜色选项](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:43)、[颜色 schema](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:710)、[模糊 schema](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:316) 这是能力可达状态更宽，不能视为完全保持界面约束。

内置插件禁止删除、插件最低宿主版本检查仍保留，没有发现这两项被绕过。[删除限制](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:235)、[宿主版本检查](~/Desktop/NipaPlay-Reload/lib/plugins/plugin_service.dart:1470)

**5. 没能审完／待确认的部分**

- **运行时结果未验证。** 已覆盖项依据注册、调用链及服务实现判断；原生窗口、图库权限、托盘、平台文件选择器及恢复后的即时 UI 表现没有实测。
- **第三方插件内部登录流程待确认。** 通用层能调用插件已暴露的 action，但没有逐个审计所有插件脚本，不能保证每个秘密输入项都有可发起的登录 action。
- **macOS“服务”子菜单具体条目未展开。** 它由系统动态提供：[定义](~/Desktop/NipaPlay-Reload/lib/platform_menu/macos_platform_menu.dart:113)。仓库没有固定条目可逐项核对。
- **各平台文件关联的原生接收与安装行为未全面审完。** 已核对 Dart 收件到播放链、Windows 配套注册／卸载代码；Android、iOS、macOS、Linux 的全部打包及系统默认程序交互仍需专项核对。
- 播放器、媒体库、账户、下载和远程服务本身的完整操作未扩展审计；仅追踪本块涉及的打开文件、窗口及备份调用边界。