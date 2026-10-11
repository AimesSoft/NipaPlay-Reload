# Classic 对 Next 覆盖审计：汇总

分支 `next/capability-layer`，静态审计（8 块合并去重），抽查为只读 grep。影响判断：常做或缺了整条流程断掉为高，偶尔用的偏好和高级选项为低。

## 总体结论

- 设置类（外观、播放、字幕、弹幕样式、快捷键、下载设置、WebDAV 快捷设置、插件）基本由 `settings.*` 注册表覆盖，覆盖率高。
- 播放主线（打开、暂停、seek、切集、音轨、字幕装载、服务器流选择）、远程来源（Jellyfin/Emby/SMB/WebDAV/NipaPlay 共享的增删改查、登录发起、浏览）、识别绑定、账号收藏评分、Bangumi 同步、下载增删播放、备份、日志均有能力。
- 缺口集中在六处：
  1. Classic 本地扫描目录的生命周期，以及观看历史的删除。
  2. 当前播放窗口和应用窗口的即时控制（全屏、画中画、独立窗口、退出、托盘），加上音量、发送弹幕、外部播放器会话。
  3. WebDAV 多端增量同步（Classic 完整一套，Next 为零）。
  4. 弹弹play 远程媒体库、NipaPlay 共享端的对端管理、Jellyfin/Emby 多地址。
  5. 首页发现（标签搜索、排行榜、日历、推荐换组、整体刷新）。
  6. 各类“打开界面、对话框、系统文件管理器”的 UI 操作。
- 不能把 `ui.open` 当成通用入口：它只有 page、entityId、path 三种目标，且 page 仅限 `primaryOrder`（没有 settings）。
- 有意为之的边界：远程访问服务和被遥控端相关键被 `lib/next/settings/denylist.dart` 禁止，Next 开关也被禁止。这是防止 Agent 自行提权，列入缺失表时标“有意禁止”。

## 一、缺失（按影响从高到低）

“抽查”列：属实表示已回到代码核实 Classic 有该操作且 Next 无对应能力；其余为审计员结论，未逐项抽查。

| # | 功能块 | 用户的操作 | Classic 位置 | 影响 | 建议的能力形状 | 抽查 |
|---|---|---|---|---|---|---|
| 1 | 弹幕 | 发送弹幕（正文、滚动/顶部/底部、颜色），本地回显 | `send_danmaku_dialog.dart:84` → `DanmakuMatchingService.sendDanmaku` | 高 | `danmaku.send {text, mode, color}`，需已登录，写操作 | 属实 |
| 2 | 账号与同步 | WebDAV 多端增量同步：启停、配置地址/目录/间隔/类别、测试连接、立即同步、查看状态 | `backup_restore_page.dart:106/134/177/791`、`AutoSyncService` | 高 | `sync.status/configure/enable/test/run` 加 `sync.status` 视图；密码由用户窗口输入 | 属实 |
| 3 | 媒体库 | 添加本地扫描目录；移除目录并清理关联历史；清理不存在目录 | `library_management_tab.dart:522/717/722`、`ScanService.startDirectoryScan/removeScannedFolder/cleanupMissingScannedFolders` | 高 | `media.library.roots.add/remove/cleanup`，添加时发起目录选择器；移除为 destructive | 属实 |
| 4 | 媒体库 | 删除单条观看历史；按番剧批量删除观看记录 | `watch_history_page.dart:740`、`anime_detail_page.dart:3603` | 高 | `history.remove {paths / animeId}`，destructive | 属实 |
| 5 | 播放 | 调整、读取普通音量；移动端亮度 | `volume_gesture_area.dart`、`video_player_state_playback_controls.dart:1427/1470/1503`（`volumeBoost` 不是音量） | 高 | `playback.set_volume` 并在 `playback.state` 返回音量；亮度同理，移动端 | 属实 |
| 6 | 播放与系统 | 全屏、画中画、独立窗口移出/移回/定位、窗口置顶、适配视频尺寸；主窗口最小化/最大化、关闭对话框与托盘（显示/退出） | `hotkey_service.dart:754/869/881/900`、`desktop_player_window_service.dart`、`desktop_exit_handler.dart:135/519`、`main.dart:1769` | 高 | `window.control {action: fullscreen/pip/detach/focus/resize/minimize/maximize/show/quit}` 加窗口状态视图；quit 为 destructive | 属实（Next 仅在登录对话框里用 `windowManager`） |
| 7 | 远程媒体 | 弹弹play 远程媒体库：配置地址、发起 Token 输入、连接/刷新/断开、浏览搜索、详情与剧集 | `remote_media_library_settings_content.dart:880/962/982`、`dandanplay_remote_library_view.dart` | 高 | `media.sources.add` 增加 `dandanplay_remote` 类型，login 由用户完成 | 属实（Next 无 `DandanplayRemote` 引用） |
| 8 | 首页与发现 | 标签检索、评分/年份高级搜索、排行榜（种类/周期）、完整榜单、新番时间表、随机推荐换组、首页整体刷新、季度回顾排序 | `tag_search_controller.dart:35/130/211`、`dashboard_home_page_trending.dart`、`dashboard_home_page_data_loading.dart:70` | 高 | `discover.search {tags, minRate, maxRate, year}`、`discover.trending {kind, range}`、`discover.calendar`、`discover.refresh` 和对应视图 | 属实（Next 无这些服务引用） |
| 9 | 下载 | 任务成功后删除，再添加同一内容（重新下载） | `torrent_download_page.dart:218/288` | 高 | `download.add` 增加 `force/reAdd`，或在 `download.remove/delete` 时同步清除历史去重记录 | 属实（`download_service.dart:44-47` 命中历史 succeeded 任务即返回，不重加） |
| 10 | 播放（外部播放器） | 外部控制台：本次会话弹幕样式/偏移/屏蔽规则（关键词、正则、发送者 ID）、会话样式与用户设置互相写回、会话弹幕列表 | `external_player_console_page.dart:153/188/390/652/794/951/1058`、`external_player_console_service.dart:288/353/378` | 高 | `playback.external.danmaku {style, offset, block}` 和会话弹幕视图 | 属实（`playback.external` 命令仅 state/pause/resume/seek/close） |
| 11 | 媒体库与远程 | NipaPlay 共享端对端管理：对端扫描目录增删/重扫/智能刷新/清理，对端 WebDAV/SMB 连接增删测试浏览刮削 | `shared_remote_library_view.dart:255-302/1699-1854`、`local_media_management_api.dart` | 中高 | `media.sources.remote_admin.*`，写操作，删除类 destructive | 审计员两块一致，未抽查 |
| 12 | 播放 | 逐条弹幕列表（含被过滤项）、字幕台词列表，点击跳转；播放信息完整诊断 | `danmaku_list_menu.dart:116/342/414`、`subtitle_list_menu.dart:129`、`playback_info_menu.dart` | 中高 | `state.query` 视图 `playback.danmaku_items` / `playback.subtitle_cues` / `playback.diagnostics` | 未抽查 |
| 13 | 播放 | 单条外挂字幕的延迟、垂直位置、边距、背景；字幕“重新检测” | `external_subtitle_overlay.dart:285/515/561`、`subtitle_tracks_menu.dart:796` | 中 | `playback.subtitle_style {trackId, ...}`、`playback.redetect_subtitle` | 未抽查 |
| 14 | 播放 | 逐帧前进/后退（E/Q）；长按临时加速开始/结束 | `play_video_page.dart:1083`、`video_player_state_playback_controls.dart:1643` | 中 | `playback.step_frame {direction}` | 未抽查 |
| 15 | 账号 | 弹弹play 内置 Bangumi 绑定 OAuth、管理页、刷新绑定状态；账号收藏/评分列表枚举；注册、注销账号；Bangumi 测试连接、清除同步缓存 | `account_controller.dart:176/269/504/536/551/581/594`、`user_activity_controller.dart:54` | 中 | `accounts.bind_bangumi`、`accounts.collections.list`、`accounts.register/delete`（用户窗口输入秘密）、`accounts.bangumi.test/clear_cache` | 未抽查 |
| 16 | 系统 | 手动检查更新并查看版本、日期、说明，打开发布页 | `about_settings_content.dart:476/515` | 中 | `app.update.check` 加结果视图 | 属实（Next 只有自动检查开关） |
| 17 | 远程访问（有意禁止） | 启停 Web 服务、自启、IPv6、端口、被遥控端、可信设备增删、遥控授权决策、访问地址与二维码 | `remote_access_receiver_settings_section.dart:66-556`、`remote_control_access_guard_service.dart:221/233` | 中 | 默认不开放；若开放，只给读（地址、设备列表）和用户窗口决策，不给开关 | 属实（`denylist.dart:22-37`，设计上禁止） |
| 18 | 远程媒体 | Jellyfin/Emby 同一服务器多地址：增删、切换、优先级；设备 ID 查看修改 | `network_media_server_dialog.dart:490/524/551/581`、`remote_media_library_settings_content.dart:1362` | 中 | `media.sources.update` 增加 `addresses[]`，或 `media.sources.address.*` | 未抽查 |
| 19 | 远程媒体 | 局域网扫描/扫码发现共享客户端；未保存配置直接测试连接 | `shared_remote_lan_scan_dialog.dart:149`、`webdav_connection_dialog.dart:322` | 中 | `media.sources.discover`、`media.sources.check` 允许传临时配置 | 未抽查 |
| 20 | 媒体库 | 自定义媒体信息创建（负数 animeId）；背景图修改；扫描失败文件查看/变化扫描/哈希缓存清理；海报墙刷新 | `custom_media_info_dialog.dart:975`、`anime_detail_page.dart:3060`、`library_management_tab.dart:1486/1833/2521` | 中 | `media.library.custom_info.create`、`media.library.scan_status` 视图、`media.library.maintain {clear_hash_cache, refresh}` | 未抽查 |
| 21 | 媒体库 | 详情社区评论、标签检索 | `bangumi_comments_widget.dart:87` | 中 | `media.metadata.comments` | 未抽查 |
| 22 | 系统 | 清空弹幕缓存、启动时清缓存 | `storage_settings_content.dart:66/263` | 中低 | `danmaku.cache_clear` 加设置 `storage.clearDanmakuCacheOnLaunch` | 未抽查 |
| 23 | 下载 | 在文件管理器打开任务文件夹；取消进行中的磁力预览；列表/卡片视图切换 | `torrent_download_page.dart:363/375/1200` | 中低 | `download.reveal`、`download.preview` 返回可取消句柄 | 属实（一并核对 Next 无 `FolderOpener` 用法的审计员结论，未单独 grep） |
| 24 | 系统 | 日志上传分享（链接、二维码）、复制到剪贴板；日志关键词搜索；日志界面两个显示设置；打开日志目录 | `debug_log_viewer_page.dart:347/392/638` | 中低 | `diagnostics.share`、`diagnostics.logs` 增加 `query` 参数 | 未抽查 |
| 25 | 系统 | Linux 存储迁移与紧急恢复个人文件；检查迁移状态；依赖版本、构建信息 | `developer_options_settings_content.dart:451/583/627/774`、`dependency_versions_window.dart:21` | 中低（审计员标高，但仅 Linux 且为故障恢复，按本表标准降为中低） | `system.storage_migration.{status,run,restore}`，restore 为 destructive | 未抽查 |
| 26 | 播放 | 字幕字体库管理（单文件/目录导入、枚举、清缓存）；弹幕字体目录导入；AirPlay、分享、复制 GIF/诊断、截图后“打开”；控制栏显隐、播放界面锁定 | `subtitle_settings_menu.dart:117/147/877`、`play_video_page.dart:270/304/440` | 低 | `playback.font_library.*`；其余多为界面动作，不建议做成能力 | 未抽查 |
| 27 | 系统 | 打开设置窗口及子页（`ui.open` 不支持）；虚拟窗口/对话框的确认、取消、关闭、移动；文件选择器入口（选视频/相册）；Windows 文件关联；插件 README；关于页链接与二维码；打开 Harness 仓库；UI 预览窗口；macOS 系统菜单 | `main.dart:1064/2235`、`nipaplay_window.dart:147`、`windows/install_file_association.bat` | 低 | `ui.open` 扩展 `page: settings` 加 `subpage`；其余视情况 | 未抽查 |
| 28 | 首页 | 轮播翻页、栏目横向滚动；搜索草稿、窗口关闭拖动 | `dashboard_home_page_actions.dart:464` | 低 | 不建议做成能力，`ui.capture` 即可 | 未抽查 |
| 29 | 设置 | 海报墙/库管理的界面状态（库分区选择与顺序、布局、六种排序、只看未观看）；Android 存储路径重置、权限申请 | `adaptive_media_library_controls.dart:912`、`library_management_tab.dart:192/1541/1582` | 低 | 注册为 `appearance.*` / `library.view.*` 设置键 | 未抽查 |

误报：本轮抽查的 10 项高影响缺失（#1–#10）全部核实属实，无误报（见第七节）。

## 二、部分覆盖

| 功能块 | 已有能力 | 缺的是什么 |
|---|---|---|
| 手动重匹配已有 Classic 匹配 | `media.metadata.*`、`media.identity.bind_batch`、`danmaku.attach` | 遇到不同的完整 Classic 匹配时返回 conflict，无法纠正错配；播放中重匹配不更新当前标题、剧集身份、`_episodeId/_animeId`、历史（`player_port.dart:160` 只装轨道）；批量匹配不迁移旧路径进度 |
| 清除匹配 | `media.identity.unbind_batch` | 只撤销 Next 显式绑定，不能清除独立 Classic 扫描匹配；整部番剧清理不等价 |
| 本地目录扫描并识别 | `media.library.scan` | 只索引，不走 Classic 识别流程，无智能变化检测和 `skipPreviouslyMatchedUnwatched`；SAF/Harmony URI 被排除 |
| WebDAV/SMB 自动刮削 | `media.sources.browse/sync`、`bind_batch` | `media.hash.match` 仅限本机文件，无远程字节匹配；`sync` 不能从任意目录开始；不迁移进度 |
| 文件列表 | `media.files.list` | 只返回递归视频，无目录行和非视频；缺 `.3gp/.m2ts` |
| 路径型设置 | `settings.set` + `path:true` | 限媒体目录内；外部播放器程序、截图目录、字体不能选到目录外；无选择器入口 |
| 选文件/相册播放 | `playback.open`、`playback.authorize_directory` | 无视频/相册选择器入口，无一次性 UA 参数，无插件分集 ID 参数 |
| 弹幕导出 | `danmaku.export` | 仅 JSON、单绑定、需 committed cache、授权目录内新文件；缺 XML、多轨合并、未绑定轨道、覆盖已有文件 |
| 弹幕轨道删除 | `danmaku.detach` | 要 bindingId；不能删未绑定本地轨道；已绑定本地轨道只剥离绑定，保留轨道 |
| 本地弹幕导入 | `danmaku.import` | 同身份重导替换同一池，不能保留多个独立轨道；无显示名 |
| 偏移与步长范围 | `danmaku.manualOffset`、`danmaku.update`、`seek.stepSeconds` | Next 限 ±30s、±2h、1/24–600s，Classic 不限或按视频动态；Classic 超出范围的合法值设不了（另见反方向第 12 条） |
| 临时状态 | `settings.set(playback.rate / seek.speedBoostRate / player.playbackEndAction)` | 无 `startSpeedBoost/stop`；自动下一话倒计时只能通过改长期设置取消，无倒计时查询 |
| 章节与片头片尾 | `playback.seek`、开关 | 无章节目录、识别区间、当前区间查询，无“跳过当前片段” |
| 外挂字幕 | `playback.load_subtitle/remove_subtitle` | 远程字幕仅已知 HTTP(S) URL，无 WebDAV/SMB/共享发现与凭据复用，无多选；`remove_subtitle` 删除登记，无“取消挂载但保留” |
| 截图与 GIF | `playback.capture` | 缺保存相册、分享、预览；未指定 `outputPath` 时固定 PNG，不沿用 `screenshotFormat` |
| 外部播放控制台窗口模式 | `player.externalConsoleWindowMode` | 设置只存值，缺立即显示/关闭窗口的副作用 |
| 服务器流 | `playback.stream_options/select_stream` | 要求已有视频；Classic 可在设置里独立配默认转码/画质，播放前为任意 Emby 剧集选版本/音轨/字幕；无 `followDefault` |
| 来源配置与状态 | `media.sources.list/check` | `list` 缺 SMB domain、地址集合、共享端 `isActive/lastConnected/error`；`check` 失败不写失败状态；`check` 只接收已保存 sourceId |
| 来源搜索与排序 | `browse/query` | 无服务器端搜索（Jellyfin/Emby 库内与跨库、WebDAV 文件搜索）；无排序参数和排序偏好写入；服务器“已看”状态（`UserData/Played`）不在元数据白名单 |
| 共享端内容 | `media.sources.libraries/browse` | 缺简介、封面、媒体身份、对端进度、时长；`query` 不支持 `nipaplay`；续播上下文不等价 |
| 详情 | `media.metadata.get`、`media.sources.query` | 丢标签、评分、`ImageTags` 等；Bangumi provider 转换不保留全部字段 |
| `ui.open` | `ui.open` | 无远程来源、媒体库子页、季、共享详情、自定义（负数 ID）上下文；Jellyfin/Emby 卡片不能打开 `MediaServerDetailPage`；点击卡片不写 NEW 基线和最近打开 |
| 元数据搜索 | `media.metadata.search` | 弹弹play 走 `/search/anime`，忽略 `year/kind`；Classic 走 `/search/adv`，返回集合是否等价待确认 |
| 首页读取 | `history.continue_watching`、`ui.capture` | 不能触发 Jellyfin/Emby Resume 拉取和 `WatchHistoryProvider.refresh()`；`ui.capture` 只见可见部分 |
| 季度回顾 | `accounts.collections.*` | 无回顾名单、排序、按卡片发起编辑 |
| 收藏评分提交编排 | `accounts.collections.update`、`accounts.episodes.update` | 不调用详情页提交编排，不刷新已打开详情；Classic 不提交 0 分，不算缺 |
| 下载预览与添加 | `download.preview`、`download.add` | 预览不可复用，`add` 无 `previewId`；本地 `.torrent` 缓存成 `<infoHash>.torrent`，开启 `createFolderForTask` 时文件夹名变成 infoHash，Classic 为种子文件名；无选种子入口；只“记住目录”会改默认目录 |
| 下载搜索排序 | `task.list`、`download.read`、`state.query` | 只能处理返回数据，不能改 Classic 搜索框/排序；入库摘要无只读接口，`download.import` 有写副作用 |
| Bangumi 同步 | `accounts.bangumi.sync` | 无进度回调（当前作品、当前/总数）；`state.query` 回执缺同步计数 |
| 备份 | `backup.export/preview/restore/history_*` | 不传 appVersion；预览缺 `hasDandanplayRemote/hasNipaplayShare`；单选 `episodeMatches` 恢复后不刷新内存历史；无 iOS 导出/分享；拒绝覆盖已有文件 |
| 背景图 | `appearance.customBackgroundPath` | 无图库选择、复制到 backgrounds 目录、清理旧副本；Android 权限流程缺 |
| 其他系统 | `diagnostics.*`、`plugins.install` | 日志目录只返回路径；`--load-js` 同版本重载不等价；系统资源无结构化数据；虚拟窗口双击不重置偏移；插件秘密文本项无登录入口（依赖插件是否暴露 action） |
| Mesh 遥控 | `mesh.invoke` | 仅在 Mesh 配好且对端提供能力时可用，生产 issuer 为空返回 `issuer_not_configured`；不能操作 Classic 遥控目标，白名单不含弹幕和设置 |

## 三、反方向风险（已逐项回到代码核实）

| # | 风险 | 说明与证据 | 核实 |
|---|---|---|---|
| 1 | 开启时间轴截图预览绕过性能确认 | Classic 开启前弹“开启警告”（`player_settings_content.dart:779-800`）；Next 直接调用 `setTimelinePreviewEnabled`（`application_settings.dart:548-558`） | 核实属实 |
| 2 | 可在未选外部播放器程序时启用外部播放 | Classic 路径为空会先检测 mpv 或弹选择器，取消则关回（`external_player_settings_content.dart:255-270`）；Next 直接 `setUseExternalPlayer`（`application_settings.dart:867`） | 核实属实 |
| 3 | destructive 能力的“确认”由调用方自填 | `media.sources.remove` 靠 `confirm:true`（`media_sources/capability.dart:303-312`）；`download.delete`、`backup.restore`、`backup.history_restore`、`plugins.delete`、`diagnostics.clear` 均无 confirm 参数；HTTP 端点靠 `execute:true`（`agent_endpoint.dart:297`），MCP 路径无该关卡。Classic 都要用户点击对话框 | 核实属实。注意：`Effect.destructive` 只是记录属性；按“Labs 同意一次后 Agent 即用户代理”的设计，这可能是有意的，建议产品确认 |
| 4 | `media.identity.unbind_batch` 无确认就恢复 Classic 字段 | Classic 单文件移除、整番清理有确认；Next 为 `Effect.write` 无 confirm（`media_capability.dart:496-499`）。仅限 Next 投影过的匹配 | 核实属实 |
| 5 | 恢复备份可写入被设置禁止的键 | `backup.restore` 经 `FullBackupService` 原样写 SharedPreferences，不过 `SettingsRegistry` / denylist；`labs_enable_agent_endpoint`、`web_server_*` 等键可被写入（影响持久值与下次启动）。Classic 本身也这样写，Next 额外丢了确认 | 核实属实（denylist 键存在于 `denylist.dart:15-32`，restore 路径未见过滤） |
| 6 | SMB/WebDAV 配置未验证连接就覆盖保存 | Classic 先测试再保存；Next `media.sources.add/update` 调 `configureConnection`，失败无回滚（`media_sources/service.dart:223/245`） | 审计员静态结论，本次未抽查 |
| 7 | Mesh 授权独立于 Classic 被遥控端开关 | Mesh 路径直接构造 `McpRpc` 调 Harness（`mesh/runtime.dart:620`），`lib/next/mesh` 无 `receiverEnabled`/可信设备引用；关闭 Classic 被遥控端不阻断 Mesh。生产 issuer 为空时不可触发 | 核实属实（代码层），实际触发取决于 Mesh 配置 |
| 8 | `danmaku.import` 可用空文件替换既有弹幕池 | Next 传 `allowEmpty:true`（`danmaku/import.dart:16`），Classic 默认拒绝空池 | 核实属实 |
| 9 | `danmaku.detach` 可删除新挂载的 Dandanplay 轨道 | Classic 菜单只对 local 来源显示删除，且 `removeDanmakuTrack` 保护 dandanplay；Next detach 无来源限制，对 `origin=binding` 的新轨道会真删（`player_port.dart:174`）。`Effect.write` | 核实属实（已看 spec 为 `Effect.write`；来源限制缺失按审计员调用链） |
| 10 | Next 挂载弹幕不触发 `danmakuLoaded` 插件事件 | 依赖该事件改写弹幕池的插件被绕过，静态屏蔽词仍生效 | 审计员静态结论 |
| 11 | 快捷键冲突确认被跳过 | Classic 检测冲突后“替换/取消”（`shortcuts_settings_page.dart:366`）；Next 直接 `updateShortcut`（`classic_settings.dart:576-590`） | 核实属实（Next 无冲突检查） |
| 12 | 参数范围大于 Classic GUI | 弹幕字号 0–100 对 12–60；Titan 上限 5000 对 1000；Titan 偏移 ±1000 对 ±100；进度条颜色任意 ARGB 对 5 个预设；背景模糊任意值对离散档；GitHub 代理接受 Classic 拒绝的值（Classic 要求 HTTP(S)、末尾 `/`、连通测试，注册项只是 `StringSchema`，`classic_settings.dart:524`） | 核实属实（GitHub 代理项） |
| 13 | Bangumi 单集可写 0/1/3 | Next `accounts.episodes.update` 允许 `state 0–3`（`accounts/capability.dart:98-100`）；Classic 进度界面只发“看过”，批量服务跳过 type=0 | 核实属实 |
| 14 | 评分/收藏提交限制不同 | Classic 评分对话框选 0 时禁用“确定”；Next 允许只传 status 或 comment | 审计员静态结论（收藏/回顾两处引用一致） |
| 15 | 首页设置无平台可见性条件 | Classic 手机隐藏小卡片设置，电视隐藏分区拖动；Next 注册项默认全部可改 | 审计员静态结论，低影响 |
| 16 | `bind_batch` 允许一个文件多个 episodeRefs | Classic 批量匹配要求一对一；Next 更宽，且 Classic 投影只处理单个精确关系，接受成功不等于 Classic 已接受 | 审计员静态结论 |
| 17 | `download.add` 跳过“预览后确认” | Classic 须预览完成才能点添加；Next 内部预览但不向用户展示 | 审计员静态结论 |

没有发现“删除确认被能力绕过”之外的、与 Classic 明确禁止相冲突的新写入路径。

## 四、待确认

- 播放中手动重匹配后，当前标题、剧集身份、历史能否经现有能力完整复现（m1、m2）。
- `media.metadata.search` 与 Classic `/search/adv` 返回集合是否等价（m5）。
- 新番时间表 `NewSeriesPage` 当前是否仍有产品入口（`adaptive_app_page_content.dart` 只注册 `DashboardHomePage`），如无则日历缺口可降级（m5）。
- 首页继续播放未匹配条目：Classic 先走 `WatchHistoryAutoMatchHelper`，Next 直接播放，副作用是否等价（m5）。
- “清除评分”：Classic 对话框只把草稿设 0 且“确定”禁用，不是持久清零，因此 Next 评分下限 1 不算缺失（m1、m3、m5、m7 一致）。
- 降低“已看 N 集”不是已证实的远端撤销，不算缺（m7）。
- 弹幕密度曲线内容能否用截图读取（m2）；Bilibili/AcFun 来源在 Classic 只是占位，不算缺失（m2）。
- 第三方插件：运行时安装插件的私有 UI 和 action，是否有登录入口（m2、m8）。
- 大于 16 MiB 的本地种子：Next 拒绝，Classic 经 librqbit 是否接受未验证（m6）。
- `Effect.destructive` + `execute:true` / `confirm:true` 是否符合“Labs 一次同意后 Agent 为用户代理”的产品意图（反方向第 3 条）。
- Web 客户端：`NextCore` 仅在 `!kIsWeb` 创建，原生覆盖不能推广到 Web（m3）。
- 平台与运行时：各平台选择器、托盘、窗口、外部播放器 IPC、真实服务器响应均未运行验证（全部）。
- Emby 播放前偏好继承（系列级、轨道指纹）未追完（m3）；自定义媒体字段映射与 `media.metadata.override` 未逐字段核对（m4）；Android/iOS/macOS/Linux 文件关联原生链路未审（m8）。

## 五、已覆盖（每块一行，附能力 id 前缀）

| 块 | 覆盖内容 | 能力 id 前缀 |
|---|---|---|
| 播放 | 打开（本地、URL、Jellyfin/Emby、续播、指定起点、同集多文件决策）、暂停、seek、步长快进快退、跳过秒数、切集、轨道读取与选择、字幕装载与删除、服务器流选择、截图与 GIF、关闭、外部播放遥测与五种命令、目录授权 | `playback.*`（含 `playback.external*`、`playback.authorize_directory`） |
| 播放设置 | 倍速、快进步长、字幕样式 21 项、播放器内核与解码、超分、播放结束行为、预缓存、截图设置、外部播放器设置、19 个快捷键与重置 | `settings.*`（键 `player.* playback.rate seek.* subtitle.* shortcuts.*`）、`shortcuts.reset` |
| 弹幕 | 搜索、剧集、解析、获取、挂载、轨道查询与开关、偏移、去重、本地导入、基本导出、对齐分析与旧任务、缓存删除、显示/样式/屏蔽/Titan/防剧透/渲染设置 | `danmaku.*`、`settings.*`（键 `danmaku.* danmaku.titan.*`）、`state.query: danmaku.bindings/datasets/tracks` |
| 媒体库与识别 | 库查询、系列与剧集、历史读取、继续观看、哈希匹配、元数据搜索与获取与覆盖与刷新、批量绑定/解绑、扫描与导入历史、文件列表 | `media.library.*`、`media.files.*`、`media.hash.*`、`media.identity.*`、`media.metadata.*`、`history.*`、`state.query: library.* media.* history.*` |
| 远程媒体 | 五类来源的增改删、登录发起、检查、媒体库选择、浏览、查询、同步；WebDAV 快捷设置 | `media.sources.*`、`settings.*`（键 `webdavQuick.*`）、`webdav_quick.reset` |
| 网络设置 | User-Agent、HTTP 代理、允许自签名证书 | `settings.*`（键 `player.customUserAgent`、`network.*`） |
| 首页与发现 | 分区顺序/显隐/重置、轮播与卡片设置、季度回顾开关、打开首页、已知 Bangumi 条目评分短评、普通弹弹play详情 | `appearance.reset_home_sections`、`settings.*`（键 `appearance.*`）、`ui.open`、`ui.capture`、`accounts.collections.*` |
| 下载 | 添加、预览、暂停/恢复/重试/做种、移除、删除、读取、导入、播放、最近目录、下载设置、任务列表 | `download.*`、`task.*`、`settings.*`（键 `download.*`）、`state.query: downloads` |
| 账号与同步 | 状态、登录发起、登出、收藏评分评论、剧集观看状态、Bangumi 增量/全量同步与状态、备份导出预览恢复、观看进度导出恢复 | `accounts.*`、`backup.*`、`task.*` |
| 设置与系统 | 窗口启动状态与位置、关闭行为、画中画位置、默认页、自动更新检查、主题与外观全部、语言、开发者开关、实验室开关、Harness 路径、插件全生命周期、日志读取导出清空、拖放与启动参数打开文件、macOS 导航切换 | `settings.*`（键 `general.* appearance.* language.* diagnostics.* labs.* next.harnessPath`）、`plugins.*`、`diagnostics.*`、`app.instance`、`ui.open`、`playback.open` |

## 六、各块缺失比重

播放与弹幕的缺失多是当前播放的即时控制和列表读取；媒体库与远程的缺失多是管理类操作；账号与系统的缺失多是同步、更新和窗口控制；首页的缺失集中在“发现类”外部数据；下载只缺三项小操作。

## 七、抽查结果（高影响前 10 项与全部反方向风险）

高影响缺失 #1–#10：

| 项 | 核对方式 | 结论 |
|---|---|---|
| 1 发送弹幕 | `lib/next`、`packages/nipa_harness/lib` 无 `sendDanmaku`，仅有按钮显隐设置和快捷键；Classic `danmaku_matching_service.dart:115` 存在 | 核实属实 |
| 2 多端增量同步 | Next 无 `AutoSync` / `auto_sync` / `incremental_sync`；Classic `backup_restore_page.dart` 有 `_manualSync` | 核实属实 |
| 3 本地扫描目录 | Next 无 `startDirectoryScan` / `removeScannedFolder` / `cleanupMissing`；Classic `library_management_tab.dart:533/717/749` 存在 | 核实属实 |
| 4 删除观看历史 | Next 无 `removeHistory` 等；Classic `watch_history_provider.dart:443` 与 `watch_history_page.dart` 存在 | 核实属实 |
| 5 普通音量 | Next 中 `volume` 仅出现在 `player_volume_boost`；Classic `increaseVolume/decreaseVolume` 存在 | 核实属实 |
| 6 窗口控制 | Next 无 `toggleFullscreen`、画中画、`detachPlayer`、托盘、`DesktopExitHandler`；`windowManager` 只用于登录对话框前置；Classic `hotkey_service.dart:754` 存在 | 核实属实 |
| 7 弹弹play 远程库 | Next 无 `DandanplayRemote` 引用；`media.sources.add` 类型枚举无此类型；Classic 视图存在 | 核实属实 |
| 8 首页发现 | Next 无 `searchAnimeByTags` / `SearchService` / `TrendingBangumi` / `getCalendar` / `RandomRecommend`；Classic `tag_search_controller.dart:35` 存在 | 核实属实 |
| 9 下载重加 | `download_service.dart:44-47` 命中历史 succeeded 任务即直接返回；Classic 原生添加在收养历史任务之前 | 核实属实 |
| 10 外部会话弹幕控制 | `playback.external` 命令枚举仅 `state/pause/resume/seek/close`，Next 无外部会话服务的样式、偏移、屏蔽调用；Classic `external_player_console_page.dart` 存在 | 核实属实 |

反方向风险：第三节 #1、#2、#3、#4、#5、#7、#8、#9、#11、#12（GitHub 代理项）、#13 已逐项核实；#6、#10、#14–#17 为审计员静态结论，未抽查。

误报合计：0 项（高影响缺失抽查 10 项全部属实）。另有 3 处审计员已自行排除，不计入缺失：“清除评分”、“降低已看 N 集的撤销”、Bilibili/AcFun 来源占位。
