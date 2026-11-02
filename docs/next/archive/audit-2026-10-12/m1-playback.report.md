**结论：不能。** 当前 Next 已覆盖基础播放、服务器流选择和多数播放设置，但仍有明确缺失，以及参数范围、来源、即时生效方式不一致的问题。密码等秘密不计入缺口；相关登录可以由 Agent 发起。

本报告基于 `next/capability-layer` 分支的静态代码审计。未修改文件，未构建或运行应用。只追踪播放界面及其直接调用的服务，没有扩展审查媒体库、下载、账号等块的其他操作。

## 播放相关能力清单

以下是实际注册的能力，不把“底层有方法”当作 Agent 可调用入口。

| 类别 | 能力 |
|---|---|
| 基础播放 | `playback.open`、`playback.state`、`playback.set_paused`、`playback.seek`、`playback.switch_episode` |
| 轨道与流 | `playback.tracks`、`playback.select_track`、`playback.load_subtitle`、`playback.remove_subtitle`、`playback.stream_options`、`playback.select_stream` |
| 外部播放 | `playback.external`，命令限 `state/pause/resume/seek/close`；`playback.external_state` |
| 捕获与退出 | `playback.capture`，类型为截图/GIF；`playback.close`；`playback.authorize_directory` |
| 弹幕 | `danmaku.import`、`sources`、`search`、`episodes`、`resolve`、`fetch`、`attach`、`tracks`、`set_enabled`、`set_dedup`、`offset`、`detach`、`analyze_alignment`、`update`、`cache_delete`、`export` |
| 弹幕兼容入口 | `danmaku.align`、`danmaku.align_apply`、`danmaku.align_keep`；描述明确限制为旧任务恢复，不能作为新流程覆盖依据 |
| 设置 | `settings.describe/get/set/reset/history`；播放相关注册键包括 `player.*`、`playback.rate`、`seek.*`、`subtitle.*`、`danmaku.*`、`shortcuts.*` |
| 快捷键 | `shortcuts.reset` |
| 播放入口辅助 | `ui.open`、`ui.capture`、`media.files.list`、`media.library.series`、`media.sources.browse/query`、`history.continue_watching`、`download.play` |
| 登录与播放完成评论 | `accounts.login/status`、`media.sources.login`；`accounts.collections.get/update` |

注册及实现依据：

- [基础播放能力](~/Desktop/NipaPlay-Reload/lib/next/capabilities/playback_capability.dart:20)。
- [播放控制能力](~/Desktop/NipaPlay-Reload/lib/next/capabilities/playback_controls_capability.dart:18)及[实际 Classic 服务桥接](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_playback_controls.dart:24)。
- [运行时注册](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:103)、[控制能力注册](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:215)。
- [播放设置注册表](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:422)、[快捷键注册表](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:576)、[快捷键恢复能力](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:350)。

`state.query` 与播放有关的视图包括：

- `library.classic_series`、`library.classic_episodes`、`library.files`及媒体实体/绑定视图；
- `history.entries`、`history.continue_watching`；
- `danmaku.bindings`、`danmaku.datasets`、`danmaku.tracks`；
- `settings.changes`。

**没有当前播放的完整诊断视图、字幕台词视图或弹幕逐条内容视图。** `danmaku.datasets` 明确只返回缓存块摘要，排除评论文本和发送者数据；`danmaku.tracks` 返回轨道摘要。[代码依据](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:630)

下面的“已覆盖”允许组合多个能力实现操作，但不会把修改长期设置、删除记录或重新打开视频，直接视为对应临时操作的完整替代。

## 1. 缺失：按用户影响排序

### 1. 普通音量控制与读取

Classic 可以通过播放快捷键 `↑/↓` 调整音量，移动端可以在音量手势区上下拖动。实际服务会修改播放器音量或系统音量。

- 界面：[音量手势区](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/volume_gesture_area.dart:22)。
- Classic 方法：[updateVolumeOnDrag](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_playback_controls.dart:1427)、同文件 `increaseVolume:1470`、`decreaseVolume:1503`。
- 快捷键入口：[video_player_ui.dart:261](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/video_player_ui.dart:261)。

Next 没有普通音量的读写能力或注册键。`player.volumeBoost` 修改的是增强倍率，不能替代普通音量、降低音量或静音。

### 2. 当前播放窗口的即时控制

缺少以下独立操作：

- 进入/退出全屏，包括桌面双击、Enter、按钮和 Esc；
- 将播放器移入独立窗口、移回主窗口；
- 定位已经打开的独立播放器窗口；
- 进入/退出画中画；
- 独立窗口置顶/取消置顶；
- 按视频尺寸调整主窗口或独立窗口；
- 拖动独立播放器窗口；
- 单独打开/关闭外部弹幕控制台窗口、弹幕列表窗口，而不终止外部播放。

Classic 依据：

- [双击全屏](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/video_player_ui.dart:675)、[窗口模式按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/modern_video_controls.dart:513)。
- [画中画按钮](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:1182)、[窗口置顶按钮](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:1204)。
- [窗口尺寸适配](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:182) → `resizeWindowToVideoSize` / `resizeDetachedWindowToVideo`。
- [独立窗口服务](~/Desktop/NipaPlay-Reload/lib/services/desktop_player_window_service.dart:52)。
- [播放器窗口拖动](~/Desktop/NipaPlay-Reload/lib/pages/desktop_player_window.dart:110)、[控制台窗口拖动](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_window.dart:99)。
- [控制台窗口模式切换的即时副作用](~/Desktop/NipaPlay-Reload/lib/settings/pages/external_player_settings_content.dart:199)。

`player.autoFullscreenEnabled`、画中画位置设置和外部控制台窗口模式设置，均不等于上述即时窗口操作。`playback.external.close` 会关闭播放会话，也不等于仅关闭控制台窗口。

### 3. 外部播放器会话中的弹幕控制

外部控制台可以：

- 修改本次会话的弹幕透明度、字号、描边、堆叠；
- 增减、输入、重置弹幕偏移；
- 添加/移除关键词、正则、用户 ID 屏蔽规则；
- 把会话样式写回用户设置；
- 将用户设置重新应用到当前会话；
- 查看会话弹幕列表、屏蔽状态及跟随播放。

Classic 依据：

- [会话样式滑块与开关](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:390)。
- [样式写回](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:153)、[重新应用](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:188)。
- [会话偏移输入](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:652)。
- [屏蔽规则添加](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:794)、同文件移除入口 `951`、列表跟随入口 `1058`。
- 实际服务：[external_player_console_service.dart:288](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:288)、同文件 `addBlockedItem:353`、`removeBlockedItem:378`。

Next 的外部播放能力只处理播放遥测、暂停、继续、定位和关闭。`danmaku.*` 的播放器桥接对象是内部 `VideoPlayerState`，[代码](~/Desktop/NipaPlay-Reload/lib/next/danmaku/player_port.dart:10)，不能据此认定覆盖外部控制台的独立会话状态。

### 4. 发送弹幕

Classic 的顶部按钮、右键菜单和 `C` 快捷键可打开发送对话框；用户可以输入内容，选择滚动/顶部/底部模式、预设或十六进制颜色，并发送到服务器，随后加入本地轨道。

- [播放入口](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1840)。
- [发送及参数](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/send_danmaku_dialog.dart:84) → `DanmakuMatchingService.sendDanmaku`。
- 实际服务：`lib/services/danmaku_matching_service.dart:115`。

没有发送能力。`danmaku.import` 是导入已取得的数据，不会向服务器发布弹幕。登录能力已经存在，但登录后仍缺发送操作。

### 5. 单条外挂字幕的独立调整

Classic 可以长按/拖动字幕，为每个外挂字幕分别调整：

- 时间延迟；
- 垂直位置；
- 水平边距；
- 字幕背景开关。

- [字幕拖动](~/Desktop/NipaPlay-Reload/lib/widgets/external_subtitle_overlay.dart:285)。
- [单条字幕设置面板](~/Desktop/NipaPlay-Reload/lib/widgets/external_subtitle_overlay.dart:561)。
- [背景开关](~/Desktop/NipaPlay-Reload/lib/widgets/external_subtitle_overlay.dart:515)。
- 实际方法：[setPathSubtitleDelaySeconds](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:225)、同文件 `setPathSubtitlePosition:238`、`setPathSubtitleMarginX:247`。

Next 只有全局字幕设置，没有以字幕路径为目标的对应参数和状态查询。全局 `subtitle.position`、`subtitle.marginX`、`subtitle.srtDelaySeconds` 不能分别控制多条外挂字幕。

### 6. 字幕台词列表与逐条弹幕列表

Classic 可查看字幕台词、定位当前句、点击某句跳转；也可查看逐条弹幕、显示被过滤的弹幕、点击弹幕跳转。

- [字幕列表加载](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/subtitle_list_menu.dart:129)、同文件 `_seekToTime:558`。
- [弹幕列表加载](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_list_menu.dart:116)、同文件 `_seekToTime:342`、显示过滤项开关 `414`。

`playback.seek` 覆盖“已知时间后跳转”，但没有入口取得上述列表的台词/文本、逐条时间和过滤状态。弹幕导出只覆盖部分持久绑定数据，见部分覆盖第 7 项。

### 7. 逐帧前进与后退

Classic 顶部按钮及 `E/Q` 快捷键调用逐帧方法；方法会先暂停，再调用播放器内核的 `stepForward/stepBackward`。

- [顶部按钮](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:1083)。
- [实际逐帧方法](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_playback_controls.dart:1643)。

Next 没有逐帧能力。毫秒 seek 没有调用这些内核方法，不能认定等价。

### 8. 字幕字体库管理

缺少字幕字体文件导入、目录导入、字体库枚举和清空字体缓存。

- [文件导入](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/subtitle_settings_menu.dart:117)、[目录导入](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/subtitle_settings_menu.dart:147)、[清空缓存按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/subtitle_settings_menu.dart:877)。
- 实际方法：`video_player_state_preferences.dart` 中 `listSubtitleFonts:2228`、`clearSubtitleFontCache:2251`、`importSubtitleFontFile:2372`、`importSubtitleFontDirectory:2399`。

`subtitle.fontName/fontDir` 能选择名称或设置目录，但不会执行上述复制、导入、枚举、删除缓存操作。

### 9. 手动重新检测字幕

字幕轨道菜单的“重新检测”会调用 `redetectAndLoadSubtitle`，重新执行本地/远程自动发现流程。

- [按钮及调用](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart:796)。
- 实际桥接：`video_player_state_subtitles.dart:287`。

Next 只能装载已知路径或 URL，没有重新检测入口。

### 10. 移动端亮度调整

- [亮度手势区](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/brightness_gesture_area.dart:22)。
- [实际亮度修改](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_initialization.dart:227) → `ScreenBrightness.setScreenBrightness`。

没有亮度 Action、注册键或状态字段。

### 11. AirPlay、分享、剪贴板及外部查看器操作

以下操作没有对应能力：

- 发起 AirPlay 设备选择：[play_video_page.dart:440](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:440)。
- 分享当前视频文件或播放地址：[play_video_page.dart:304](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:304) → `SystemShareService.share`。
- 把 GIF 文件本体或地址复制到剪贴板：[media_capture_dialog.dart:320](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/media_capture_dialog.dart:320)。
- 复制完整播放诊断：[playback_info_menu.dart:158](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/playback_info_menu.dart:158)。
- 截图成功后的“打开”，交给外部查看器：[video_player_ui.dart:1010](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/video_player_ui.dart:1010)、同文件 `_openScreenshot:1022`。

生成文件的 `playback.capture` 不会完成分享、复制或打开操作。

### 12. 播放界面的临时 UI 控制

缺少显式显示/隐藏控制栏、锁定/解锁播放界面，以及打开/关闭播放菜单、右键菜单和具体设置面板的入口。

- [移动端单击显隐控制栏](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/video_player_ui.dart:660)。
- [锁定/解锁](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:270)。
- [设置菜单](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/modern_video_controls.dart:297)、同文件播放列表菜单 `377`、右键入口 `video_player_ui.dart:1199`。

`ui.open` 只能打开声明的页面、实体或播放路径，不能操作这些子面板；`ui.capture` 只能捕获已呈现的界面。

低影响界面操作中，空播放页点击看板娘触发动画也没有能力入口：[video_upload_ui.dart:95](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/video_upload_ui.dart:95)。

## 2. 部分覆盖

| Classic 操作与位置 | 已有能力 | 缺少的部分 |
|---|---|---|
| 选择外部播放器程序；`external_player_settings_content.dart:320` | `settings.set`，`player.externalPath/externalType` | 路径被限制在已配置媒体目录内。Classic 文件选择器可选择其他目录的程序，例如系统安装位置；Next 没有对应程序选择器或自动检测入口。 |
| 设置截图目录、导入弹幕字体；`video_player_state_preferences.dart:3079`、`danmaku_settings_menu.dart:329` | `settings.set`，`player.screenshotDirectory`、`danmaku.fontFilePath` | 同样受到媒体目录边界限制。Classic 可通过选择器选择媒体目录外的目录/字体。弹幕字体单文件导入及恢复默认已有真实 setter，但目录枚举、字体库枚举没有对应能力。 |
| 选文件/从相册选视频；`video_upload_ui.dart:229/462` | `playback.open` | 已知且可访问的文件可播放；没有视频/相册选择器入口。不能取得尚未授予访问权限的相册视频或创建与 Classic 文件选择相同的授权书签。 |
| 授予目录权限；`file_picker_service.dart:656` | `playback.authorize_directory` | 只能发起选择器，由用户选择目录；不能由 Agent 完成路径选择。该操作也不会把目录加入 Next 的媒体目录范围。 |
| URL 对话框中的“一次性 UA”；`video_upload_ui.dart:148` → `PlayerFactory.setOneTimeUA:271` | `playback.open`、`settings.set(player.customUserAgent)` | 缺一次性 UA 参数。长期 UA 设置与“下一次播放用后清除”语义不同。 |
| 插件链接中的分集选择；`plugin_playback_service.dart:27` | `playback.open` | 可以发起解析；多项时仍会进入 Classic 对话框，或使用已有 preferredId。Action 没有插件分集 ID 参数，也没有把插件选项转为可执行 Decision 返回给 Agent。 |
| 导出当前弹幕为 XML/JSON；`danmaku_settings_menu.dart:205` | `danmaku.export` | 只导出一个有缓存的持久绑定，且只支持 JSON、授权媒体目录、新文件。Classic 能保存当前播放器收集的弹幕，包括未绑定轨道，并提供 XML。Next 不支持当前多轨集合导出。 |
| 远程字幕发现、多选挂载；`subtitle_tracks_menu.dart:283/400` | `playback.load_subtitle`、`playback.select_stream` | 服务器字幕选择已覆盖；其他远程字幕只能传已知普通 HTTP(S) URL，桥接构造候选时 `authorizationHeader:null`。缺 Classic 的 WebDAV/SMB/共享目录候选发现、凭据复用和多选候选参数。 |
| 临时关闭外挂字幕，但保留列表；`subtitle_tracks_menu.dart:849` | `playback.load_subtitle/remove_subtitle` | `remove_subtitle` 会移除持久列表记录；`load_subtitle(activate:false)` 不会关闭已经活跃的字幕。缺“取消挂载但保留登记”的操作。 |
| 删除任意弹幕轨道；`danmaku_tracks_menu.dart:281` → `removeDanmakuTrack` | `danmaku.detach` | `detach` 以绑定 ID 为目标，不能删除没有绑定的 Classic/本地会话轨道。`danmaku.update(enabled:false)` 只关闭显示，仍保留轨道。 |
| 自定义全局弹幕偏移；`danmaku_offset_menu.dart:54` | `settings.set(danmaku.manualOffset)` | Classic 自定义输入不限制在 ±30 秒，setter 也没有此范围钳制；Next schema 限制为 `-30～30`。 |
| 设置快进快退步长；`seek_step_menu.dart:94`、`video_player_state.dart:1577` | `settings.set(seek.stepSeconds)` | Classic 下限是当前视频一帧，上限是当前视频时长；Next 固定为 `1/24～600` 秒。例如 60fps 的一帧及超过 600 秒的合法步长不能设置。 |
| 长按临时加速；`video_player_ui.dart:691`、`hotkey_service.dart:999` | `settings.set(playback.rate/seek.speedBoostRate)` | 可修改倍速，但未暴露 `startSpeedBoost/stopSpeedBoost`，无法设置/查询临时加速状态及其自动恢复语义。 |
| 自动下一话倒计时中的“取消”；`auto_next_episode_service.dart:169` | `settings.set(player.playbackEndAction)` | 改成非自动下一话会取消倒计时，但同时修改长期结束行为。没有本次倒计时取消入口，也没有倒计时剩余秒数/目标查询。 |
| 点击章节跳转；`video_progress_bar.dart:755` | `playback.seek`、`settings.set(player.chapterMarkersEnabled)` | 已知章节时间后能 seek；缺当前章节目录、标题、时间点及当前章节查询，不能直接按章节索引操作。 |
| 跳过识别的片头/片尾；`play_video_page.dart:1343` → `skipCurrentSegment:77` | `playback.seek`、`settings.set(player.introSkipEnabled)` | 没有识别区间、当前区间和结束点查询，也没有按当前识别区间跳过的入口。 |
| 读取完整播放信息；`playback_info_menu.dart:42/125` | `playback.state/tracks/stream_options` | 可读基本状态和轨道/服务器流摘要；缺实时编解码器、输出、缓存、网络及 Erika 运行诊断等完整信息。媒体文件探测不等于当前播放器诊断。 |
| 截图/GIF 对话框的完整流程；`media_capture_dialog.dart:264/390/440` | `playback.capture`、截图设置 | 文件生成和 GIF 区间/FPS/尺寸/质量已覆盖；缺保存到相册、系统导出/分享、预览流程。截图未指定 `outputPath` 时桥接固定选 PNG，没有沿用 Classic 的 `screenshotFormat`。 |
| 切换外部控制台窗口模式；`external_player_settings_content.dart:199` | `settings.set(player.externalConsoleWindowMode)` | 注册表只调用设置 setter；Classic 同时立即 `showControlsWindow/closeAll`。当前会话中的窗口变化缺失。 |
| 浏览本地播放列表；`playlist_menu.dart:140` | `media.files.list`、`playback.open` | 可列举媒体目录中的视频并打开；不能列举媒体目录范围外、Classic 已能访问的播放目录。Classic 列表还包含 `.3gp/.m2ts`，Next 目录枚举扩展名集合缺这两项。 |
| 打开当前视频的番剧详情；`video_player_ui.dart:1030` | `ui.open` | Next 详情打开最终要求唯一已接受的弹弹play作品身份。Classic 可传 `playbackDetailContext`，包括没有该身份的服务器播放上下文。 |
| 播放完成后的评分/评论；`auto_next_episode_service.dart:226` | `accounts.collections.get/update` | 评分、评论及收藏状态修改已有能力，但 Classic 的“清除评分”提交 `0`；Next `rating` 限 `1～10`。 |
| 播放中手动重新匹配弹幕；`danmaku_settings_menu.dart:1199` | `danmaku.search/episodes/attach`；媒体身份能力 | 搜索并挂载弹幕已有路径。**当前标题、剧集身份、历史及播放状态能否完整复现 Classic 的原地更新，待确认**：Classic 明确同时更新历史、调用 `setAnimeTitle/setEpisodeTitle/loadDanmaku`；Next 挂载桥接没有这组调用。 |

路径范围限制的共同依据：

- 设置写入中的 `path:true` 会调用授权检查：[application_settings.dart:408](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:408)。
- 授权检查只接受配置媒体目录及其子路径：[media_service.dart:73](~/Desktop/NipaPlay-Reload/lib/next/media/media_service.dart:73)。
- 配置来源是 `scanService.scannedFolders`：[service_provider.dart:53](~/Desktop/NipaPlay-Reload/lib/providers/service_provider.dart:53)。
- `player.externalPath` 确实标记为 `path:true`：[application_settings.dart:942](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:942)。

## 3. 已覆盖：一行一个操作

为避免重复长路径，以下代码位置采用文件缩写：

- **P**：`lib/utils/video_player_state/video_player_state_preferences.dart`
- **C**：`lib/utils/video_player_state/video_player_state_playback_controls.dart`
- **ST**：`lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart`
- **SS**：`lib/themes/nipaplay/widgets/subtitle_settings_menu.dart`
- **DS**：`lib/themes/nipaplay/widgets/danmaku_settings_menu.dart`
- **PS**：`lib/settings/pages/player_settings_content.dart`
- **ES**：`lib/settings/pages/external_player_settings_content.dart`

“已覆盖”限下表所写操作；同一功能的其他选项仍按前两节判定。

### 播放与来源

| 操作及 Classic 入口/方法 | 能力 ID |
|---|---|
| 播放已知、可访问的本地文件；`video_upload_ui.dart:229` → `initializePlayer` | `playback.open` |
| 将拖入的第一个文件交给播放服务；`main.dart:1114/1266` → `PlaybackService.play:72` | `playback.open` |
| 播放普通 HTTP(S) 媒体链接；`video_upload_ui.dart:166` | `playback.open` |
| 播放 Jellyfin 条目；`playlist_menu.dart:674` → 播放服务/初始化 | `playback.open` |
| 播放 Emby 条目；`playlist_menu.dart:674` → 播放服务/初始化 | `playback.open` |
| 打开播放页面；播放导航入口 | `ui.open` |
| 从保存进度继续播放；`PlaybackService._playInternally:110` | `playback.open` |
| 从指定时间开始播放；Classic 初始化后定位 | `playback.open(startPositionMs)` |
| 为同一剧集选择不同文件；`EpisodeFileSelectionService` 的选择流程 | `playback.open`，返回可执行文件 Decision |
| 播放/暂停；按钮、单击、空格、媒体键、右键；`C:514`及播放方法 | `playback.set_paused` |
| 进度条点击/拖动、水平拖动定位；`video_progress_bar.dart:764`、`video_player_ui.dart:798` → `seekTo` | `playback.seek(positionMs)` |
| 按已知步长快进；`C:922` | `playback.seek(offsetMs)`＋`settings.get(seek.stepSeconds)` |
| 按已知步长快退；对应 `seekBackwardByStep` | `playback.seek(offsetMs)`＋`settings.get(seek.stepSeconds)` |
| 顶部/右键/`S` 跳过配置秒数；`P:1432` | `playback.seek(offsetMs)`＋`settings.get(seek.skipSeconds)` |
| 上一话；`video_player_state_navigation.dart:26` | `playback.switch_episode(previous)` |
| 下一话；`video_player_state_navigation.dart:305` | `playback.switch_episode(next)` |
| 播放列表中打开已知条目；`playlist_menu.dart:674` | `playback.open` |
| 浏览服务器/远程来源条目后播放；`playlist_menu.dart:315/453/503/555/610` | `media.sources.browse/query`＋`playback.open` |
| 查看基本播放状态、时间、时长、倍速、前后集可用性 | `playback.state` |
| 停止并保存内部播放进度；右键停止 `video_player_ui.dart:1110` → `resetPlayer` | `playback.close` |
| 关闭播放错误后的播放器；`video_player_ui.dart:525` → `resetPlayer` | `playback.close` |
| 交给已配置的外部播放器播放；`PlaybackService.tryPlayExternally:27` | `playback.open` |
| 读取外部播放的实际遥测；控制台进度显示 | `playback.external_state` |
| 外部播放暂停；`external_player_console_page.dart:356` | `playback.external(pause)` / `playback.set_paused` |
| 外部播放继续；同上 | `playback.external(resume)` / `playback.set_paused` |
| 外部播放按时间或进度定位；`external_player_console_page.dart:1438/1489` | `playback.external(seek)` / `playback.seek` |
| 关闭外部播放器及会话；`external_player_console_page.dart:364` | `playback.external(close)` / `playback.close` |

### 音轨、字幕轨道与服务器流

| 操作及 Classic 入口/方法 | 能力 ID |
|---|---|
| 查看已暴露的内嵌/外挂/服务器轨道摘要；音轨、字幕轨道菜单 | `playback.tracks` |
| 选择内嵌音轨；`audio_tracks_menu.dart:349` → `selectEmbeddedAudioTrack` | `playback.select_track(kind:audio, origin:embedded)` |
| 选择服务器音轨；`audio_tracks_menu.dart:94` | `playback.select_track(kind:audio, origin:server)` |
| 选择内嵌字幕；`ST:515` → `selectEmbeddedSubtitleTrack` | `playback.select_track(kind:subtitle, origin:embedded)` |
| 关闭内嵌字幕；`ST:569` | `playback.select_track(index:-1)` |
| 装载已知本地外挂字幕；`ST:189` | `playback.load_subtitle` |
| 叠加装载多条已知外挂字幕；`ST:863` → `addExternalSubtitleToStack` | 多次 `playback.load_subtitle` |
| 装载普通 HTTP(S) 字幕 URL | `playback.load_subtitle` |
| 从登记列表删除外挂字幕；`ST:614` | `playback.remove_subtitle` |
| 查看服务器版本和清晰度选项；`jellyfin_quality_menu.dart:49` | `playback.stream_options` |
| 切换服务器媒体版本；`jellyfin_quality_menu.dart:157` | `playback.select_stream(mediaSourceId)` |
| 切换服务器清晰度；`jellyfin_quality_menu.dart:148/194` | `playback.select_stream(quality)` |
| 切换转码状态 | `playback.select_stream(transcode)` |
| 选择/关闭服务器字幕 | `playback.select_stream(subtitleIndex)` |
| 设置服务器字幕烧录 | `playback.select_stream(burnIn)` |

### 字幕设置

以下操作均通过 `settings.set/get/reset` 操作相应键。

| 操作及 Classic 方法 | 设置键 |
|---|---|
| 调整字幕大小；`SS:425` → `P:1973` | `subtitle.scale` |
| 调整外挂 SRT 大小；`P:1986` | `subtitle.srtScale` |
| 调整全局字幕时间偏移；`SS:280` → `P:2005` | `subtitle.delaySeconds` |
| 调整全局 SRT 时间偏移；`SS:553` → `P:1996` | `subtitle.srtDelaySeconds` |
| 调整全局垂直位置；`SS:577` → `P:2036` | `subtitle.position` |
| 选择水平对齐；`SS:616` → `P:2057` | `subtitle.alignX` |
| 选择垂直对齐；`SS:622` → `P:2067` | `subtitle.alignY` |
| 调整全局横向边距；`SS:638` → `P:2077` | `subtitle.marginX` |
| 调整全局纵向边距；`SS:648` → `P:2093` | `subtitle.marginY` |
| 调整透明度；`SS:663` → `P:2107` | `subtitle.opacity` |
| 调整描边大小；`SS:678` → `P:2117` | `subtitle.borderSize` |
| 调整阴影偏移；`SS:688` → `P:2127` | `subtitle.shadowOffset` |
| 设置加粗；`SS:703` → `P:2137` | `subtitle.bold` |
| 设置斜体；`SS:709` → `P:2146` | `subtitle.italic` |
| 设置文字颜色，包括颜色输入；`SS:725` → `P:2179` | `subtitle.color` |
| 设置描边颜色；`SS:731` → `P:2188` | `subtitle.borderColor` |
| 设置阴影颜色；`SS:737` → `P:2197` | `subtitle.shadowColor` |
| 设置已有字幕字体名称/多名称；`SS:114/780` → `P:2206` | `subtitle.fontName` |
| 设置字幕样式接管方式；`P:2452` | `subtitle.overrideMode` |
| 设置外挂字幕颜色；`external_subtitle_overlay.dart:758` → `P:2158` | `subtitle.externalColor` |
| 设置已有外挂字幕字体名称；`external_subtitle_overlay.dart:736` → `P:2169` | `subtitle.externalFontName` |
| 恢复字幕样式默认值；`SS:351` → `P:2461` | `settings.reset`，对相应字幕键批量恢复 |
| 清除字体名称/目录设置；`SS:865` | `settings.set/reset(subtitle.fontName/fontDir)`；不包含删除字体缓存 |

### 内部播放器弹幕

| 操作及 Classic 入口/方法 | 能力 ID / 设置键 |
|---|---|
| 导入已知本地 XML/JSON 弹幕；`danmaku_tracks_menu.dart:30` → `loadDanmakuFromLocal` | `danmaku.import` |
| 搜索在线弹幕并选择剧集挂载；`DS:1199` | `danmaku.search/episodes/resolve/attach` |
| 查看当前轨道摘要；弹幕轨道菜单 | `danmaku.tracks` / `state.query(danmaku.tracks)` |
| 开关某条弹幕轨道；`danmaku_tracks_menu.dart:201` | `danmaku.update(enabled)`；绑定轨道亦可 `danmaku.set_enabled` |
| 调整普通轨道偏移；`danmaku_tracks_menu.dart:270` | `danmaku.update(offsetMs)` / `danmaku.offset` |
| 删除具有 Next 绑定的轨道 | `danmaku.detach` |
| 显示/隐藏全局弹幕；`P:364/381` | `settings.set(danmaku.visible)` |
| 调整透明度；`DS:566` → `P:339` | `settings.set(danmaku.opacity)` |
| 调整字号；`DS:679` → `P:1487` | `settings.set(danmaku.fontSize)` |
| 调整显示区域；`DS:1005` → `P:2730` | `settings.set(danmaku.displayArea)` |
| 调整速度倍率；`P:2778` | `settings.set(danmaku.speedMultiplier)` |
| 调整 DFM+ 轨道间距；`P:2797` | `settings.set(danmaku.trackGap)` |
| 设置描边样式；`DS:952` → `P:1783` | `settings.set(danmaku.outlineStyle)` |
| 设置阴影样式；`DS:984` → `P:1794` | `settings.set(danmaku.shadowStyle)` |
| 设置描边档位 | `settings.set(danmaku.outlineWidth)` |
| 开关堆叠；`P:445` | `settings.set(danmaku.stacking)` |
| 开关合并弹幕；`P:393` | `settings.set(danmaku.merge)` |
| 开关随机染色；`P:456` | `settings.set(danmaku.randomColor)` |
| 添加屏蔽词；`DS:141` → `video_player_state_subtitles.dart:580` | `settings.set(danmaku.blockWords)` |
| 删除屏蔽词；`DS:508` → `video_player_state_subtitles.dart:589` | `settings.set(danmaku.blockWords)` |
| 屏蔽顶部弹幕；`video_player_state_subtitles.dart:304` | `settings.set(danmaku.blockTop)` |
| 屏蔽底部弹幕；同文件 `321` | `settings.set(danmaku.blockBottom)` |
| 屏蔽滚动弹幕；同文件 `338` | `settings.set(danmaku.blockScroll)` |
| 显示/隐藏弹幕密度图；`P:324` | `settings.set(danmaku.showDensityChart)` |
| 开关时间轴告知弹幕；`video_player_state_danmaku.dart:1935` | `settings.set(danmaku.timelineEnabled)` |
| 切换视频时保留偏移；`P:2768` | `settings.set(danmaku.rememberOffset)` |
| 调整范围内的全局偏移/归零 | `settings.set/reset(danmaku.manualOffset)`，限 ±30 秒 |
| 导入授权范围内的单个弹幕字体；`P:1707` | `settings.set(danmaku.fontFilePath)` |
| 恢复系统弹幕字体；`DS:382` → `P:1734` | `settings.reset(danmaku.fontFilePath)` |
| 设置已有字体名称；`P:1693` | `settings.set(danmaku.fontFamily)` |
| 调整 Titan 透明度；`DS:563` | `settings.set(danmaku.titan.opacity)` |
| 调整 Titan 字号倍率；`DS:577` | `settings.set(danmaku.titan.fontSize)` |
| 选择 Titan 字体；`DS:594` | `settings.set(danmaku.titan.fontFamily)` |
| 开关 Titan 加粗；`DS:601` | `settings.set(danmaku.titan.bold)` |
| 选择 Titan 描边类型；`DS:621` | `settings.set(danmaku.titan.fontBorder)` |
| 调整 Titan 滚动速度；`DS:632` | `settings.set(danmaku.titan.speedPlus)` |
| 调整 Titan 密度；`DS:644` | `settings.set(danmaku.titan.density)` |
| 调整 Titan 基准时长；`DS:656` | `settings.set(danmaku.titan.duration)` |
| 开关 Titan 防挡字幕；`DS:664` | `settings.set(danmaku.titan.preventShade)` |

### 播放、截图、外部播放器与快捷键设置

| 操作及 Classic 入口/方法 | 能力 ID / 设置键 |
|---|---|
| 选择预设或自定义常规倍速；`playback_rate_menu.dart:92/263` → `P:632` | `settings.set(playback.rate)` |
| 快捷键增加/降低/恢复常规倍速 | `settings.get/set/reset(playback.rate)` |
| 设置长按加速倍率；`PS:719` → `P:654` | `settings.set(seek.speedBoostRate)` |
| 设置顶部跳过秒数；`PS:745` → `P:784` | `settings.set(seek.skipSeconds)` |
| 设置音量增强；`player_quick_controls.dart` → `VideoPlayerState.setVolumeBoost` | `settings.set(player.volumeBoost)` |
| 设置视频画面适配模式；`modern_video_controls.dart:266` → `P:2971` | `settings.set(player.videoAspectMode)` |
| 设置快速开始播放；`PS:338` | `settings.set(player.fastPlaybackStartup)` |
| 选择播放器内核；`PS:409` → `_savePlayerKernelSettings:94` | `settings.set(player.kernel)` |
| 开关硬件解码；`PS:498` → `P:485` | `settings.set(player.useHardwareDecoder)` |
| 设置硬件解码模式；`P:2919` | `settings.set(player.hwdecMode)` |
| 设置软解输出颜色格式；`P:2982` | `settings.set(player.softDecodePixelFormat)` |
| 选择 Android 音频后端；`PS:535` | `settings.set(player.androidAudioOutput)` |
| 选择 Erika Android 输出模式；`PS:478` | `settings.set(player.erikaAndroidOutputMode)` |
| 开关 macOS 原生视频输出；`PS:552` | `settings.set(player.macosNativeVideoEnabled)` |
| 设置 Erika 超分；`PS:437` → `P:929` | `settings.set(player.erikaUpscalerMode)` |
| 开关双倍分辨率；`PS:1000` → `P:891` | `settings.set(player.doubleResolutionPlaybackEnabled)` |
| 选择 Anime4K 预设；`PS:1047` | `settings.set(player.anime4kProfile)` |
| 选择 CRT 预设；`PS:1095` → `P:1036` | `settings.set(player.crtProfile)` |
| 设置播放结束行为；`PS:602` → `P:79` | `settings.set(player.playbackEndAction)` |
| 设置自动下一话倒计时秒数；`PS:652` → `P:113` | `settings.set(player.autoNextCountdownSeconds)` |
| 开关后台暂停；`PS:568` → `P:142` | `settings.set(player.pauseOnBackground)` |
| 开关片头片尾识别；`PS:762` | `settings.set(player.introSkipEnabled)` |
| 开关章节标记；`PS:852` → `P:297` | `settings.set(player.chapterMarkersEnabled)` |
| 设置预缓存大小；`PS:882` → `P:595` | `settings.set(player.precacheBufferSizeMb)` |
| 设置预缓存时长；`PS:906` → `P:610` | `settings.set(player.precacheBufferDurationSeconds)` |
| 开关桌面悬停菜单；`PS:947` → `P:164` | `settings.set(player.desktopHoverSettingsMenuEnabled)` |
| 设置立即隐藏 UI；`PS:926` → `P:188` | `settings.set(player.instantHidePlayerUiEnabled)` |
| 开关播放菜单快捷控制；`PS:360` → `P:229` | `settings.set(player.showMenuQuickControls)` |
| 开关自动全屏；`PS:970` → `P:3133` | `settings.set(player.autoFullscreenEnabled)` |
| 开关时间轴预览设置；`PS:779` | `settings.set(player.timelinePreviewEnabled)`；确认绕过见下一节 |
| 生成截图文件；`play_video_page.dart:357` | `playback.capture(kind:screenshot)` |
| 设置截图质量；`P:2904` | `settings.set(player.screenshotQuality)` |
| 设置截图格式；`P:2896` | `settings.set(player.screenshotFormat)`；Action 默认格式差异见部分覆盖 |
| 设置截图目标偏好；`P:2883` | `settings.set(player.screenshotSaveTarget)`；实际相册保存入口缺失 |
| 设置截图包含弹幕；`P:2955` | `settings.set(player.screenshotIncludeDanmaku)` / `playback.capture(includeDanmaku)` |
| 设置截图包含字幕；`P:3019` | `settings.set(player.screenshotIncludeSubtitles)` / `playback.capture(includeSubtitles)` |
| 设置截图裁剪黑边；`P:2963` | `settings.set(player.screenshotCropLetterbox)` |
| 生成 GIF 文件并指定区间、FPS、尺寸、质量；`media_capture_dialog.dart:264` | `playback.capture(kind:gif)` |
| 开关使用外部播放器；`ES:246` | `settings.set(player.externalEnabled)`；配置前置检查差异见下一节 |
| 选择外部播放器类型；`ES:118` | `settings.set(player.externalType)` |
| 开关外部弹幕外挂；`ES:349` | `settings.set(player.externalDanmakuOverlay)` |
| 开关自动切换控制台；`ES:63` | `settings.set(player.externalAutoSwitchToDanmakuConsole)` |
| 设置外部播放时缩小主窗口；`ES:236` | `settings.set(player.externalShrinkWindow)` |
| 修改各播放快捷键；`shortcuts_settings_page.dart:128` → `HotkeyService.updateShortcut` | `settings.set(shortcuts.<action>)` |
| 恢复全部快捷键；`shortcuts_settings_page.dart:135` | `shortcuts.reset` |
| 发起弹弹play/Bangumi 登录，由用户输入秘密 | `accounts.login` |
| 发起播放来源登录，由用户输入秘密 | `media.sources.login` |
| 播放完成后读取既有评分、评论和收藏状态；`bangumi_comment_prompt_controller.dart:74` | `accounts.collections.get` |
| 播放完成后提交非零评分；同文件 `_submitComment:163` | `accounts.collections.update(rating:1～10)` |
| 播放完成后提交评论；同上 | `accounts.collections.update(comment)` |
| 播放完成后修改收藏状态；同上 | `accounts.collections.update(status)` |

## 4. 反方向的风险

### 1. 开启时间轴截图预览绕过 Classic 的确认

Classic 开启时明确展示“后台实时生成截图可能导致卡顿或性能下降”的确认对话框，只有 `confirm == true` 才写入设置。

- [Classic 确认及门禁](~/Desktop/NipaPlay-Reload/lib/settings/pages/player_settings_content.dart:779)。
- Next 注册表直接调用 `setTimelinePreviewEnabled`：[application_settings.dart:554](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:554)。

因此 Agent 的 `settings.set(player.timelinePreviewEnabled:true)` 会绕过该确认。此 Action 是 `Effect.write`；端点的破坏性预览机制只处理 `Effect.destructive`，[代码](~/Desktop/NipaPlay-Reload/lib/next/agent_endpoint.dart:297)，不会补上这个确认。

### 2. 可在未选择播放器程序时启用外部播放

Classic 启用外部播放时，如果路径为空，会先检测 mpv 或打开程序选择器；选择取消则保持关闭。

- [Classic 前置检查](~/Desktop/NipaPlay-Reload/lib/settings/pages/external_player_settings_content.dart:255)。
- Next 直接调用 `setUseExternalPlayer`：[application_settings.dart:868](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:868)。
- setter 本身没有路径检查：[settings_provider.dart:291](~/Desktop/NipaPlay-Reload/lib/providers/settings_provider.dart:291)。

因此 Next 能建立“外部播放已启用、程序路径为空”的状态，Classic 的正常启用流程不会产生这个结果。

其余已追踪的播放删除入口中，未确认到必须确认却被 Next 绕过的案例。不能仅凭 `Effect.write/destructive` 名称推断存在或不存在确认。

## 5. 没能审完／待确认的部分

- **手动弹幕重匹配的当前播放身份同步**：已确认搜索、挂载及持久身份能力存在；尚未确认它们能否完整复现 Classic 的原地标题、剧集身份、历史和播放状态更新，理由见部分覆盖最后一项。
- **任意第三方插件的私有播放选项**：审计了仓库中的通用插件 URL 解析和选择流程；未枚举运行时安装插件新增的 UI/能力。
- **平台及内核的真实执行效果**：本次按要求没有运行应用，未验证 macOS/iOS/Android 权限选择器、外部播放器 IPC、各内核截图/GIF、音轨切换的运行结果。“已覆盖”表示存在注册入口并追到了实际 Classic 方法，不表示完成了运行验证。
- **系统原生选择器内部操作**：只核对了 Dart 发起点、参数及后续服务调用，没有审查系统选择器本身的所有界面选项。

上述未确认项不影响结论：普通音量、即时窗口控制、发送弹幕、单条字幕调整、逐帧和外部控制台弹幕会话操作，已经提供了足够的代码依据，证明当前播放能力尚未全部覆盖 Classic。