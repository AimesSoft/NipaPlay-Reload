**结论：不能全部做到。** Next 已覆盖五类远程来源的基本配置、登录发起、目录发现和播放，但 Classic 的远程访问服务、旧版遥控协议、弹弹play远程库、共享客户端管理及多地址管理仍有明确缺口。

审计分支为 `next/capability-layer`。本次仅静态阅读代码，没有修改文件、构建或运行应用。“已覆盖”允许组合多个能力，但不把本地缓存查询等同于远端刷新，也不把索引发现等同于刮削或对端管理。密码由用户输入不计为缺口；无法发起登录则计为缺口。

## 与本块相关的现有能力

| 类别 | 能力及实际边界 |
|---|---|
| 远程来源 | `media.sources.list/add/update/remove/check/login/libraries/select/browse/query/sync`。来源类型仅有 `jellyfin`、`emby`、`smb`、`webdav`、`nipaplay`，见 [Action 定义](~/Desktop/NipaPlay-Reload/lib/next/media_sources/capability.dart:101)。 |
| 登录、同步任务 | `task.list/get/wait/cancel`。登录可通过用户窗口完成；Jellyfin 还支持 Quick Connect，见 [登录实现](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:711)。 |
| 远程播放 | `playback.open/state/set_paused/seek/switch_episode`；`playback.stream_options/select_stream/tracks/select_track/load_subtitle/remove_subtitle`。流选择主要作用于当前已加载的 Jellyfin/Emby 视频。 |
| 状态视图 | `state.query` 可查询 `media.entities`、`media.bindings`、`library.works/seasons/episodes/files`、`library.classic_series/classic_episodes`、`mesh.devices`。这些不是完整的远程服务状态视图，见 [视图定义](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:323)。 |
| 设置 | `settings.describe/get/set/reset/history`；相关键包括 `network.httpProxy`、`player.customUserAgent`、`general.defaultHomeTab`、下文列出的 WebDAV 快捷设置，以及 `mesh.addressCandidates`。 |
| WebDAV 快捷设置重置 | `webdav_quick.reset`，直接调用 Classic Provider 的 `resetSettings()`，见 [实现](~/Desktop/NipaPlay-Reload/lib/next/settings/operations.dart:340)。 |
| 远程设备调用 | `mesh.devices/invoke/invoke_destructive`。它采用另一套发现和信任体系；允许调用的前缀只有 `task.`、`download.`、`media.library.`、`playback.`，见 [白名单](~/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:17)。 |
| 界面定位 | `ui.open` 可打开顶层页面、普通作品详情或播放目标；没有远程来源、媒体库子页、文件夹、季或共享详情上下文参数，见 [输入定义](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:22)。 |
| 远程文件手动匹配 | `media.metadata.search/get/get_batch/search_batch`、`media.identity.bind_batch/unbind_batch` 等可用于已索引远程文件。这里只核对远程入口与投影，不展开整个匹配模块。 |

## 1. 缺失：按用户影响排序

### 1.1 无法操作 Classic 的远程访问服务及授权

这些操作决定其他设备能否连接、读取共享库和遥控本机，影响最大。

| Classic 界面中的操作 | Classic 方法与位置 | Next 对照 |
|---|---|---|
| 启动或停止局域网 Web 服务 | 远程访问设置 `_toggleWebServer`：[185](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:185) → `WebServerService.startServer/stopServer`：[344](~/Desktop/NipaPlay-Reload/lib/services/web_server_service.dart:344)、[436](~/Desktop/NipaPlay-Reload/lib/services/web_server_service.dart:436) | 无对应 Action。 |
| 设置服务自动启动 | `_toggleAutoStart`：[217](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:217) → `setAutoStart` | 无对应能力；设置被拒绝。 |
| 开启或关闭 IPv6 | [开关处理](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:231) → `setIpv6Enabled` | 无对应能力；设置被拒绝。 |
| 修改监听端口并重启服务 | [端口对话框保存](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:400) → `setPort` | 无对应能力；设置被拒绝。 |
| 开启或关闭“被遥控端” | [开关处理](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:264) → `RemoteControlSettings.setReceiverEnabled`；开启时还会启动 Web 服务 | 无对应能力；设置被拒绝。 |
| 查看可信设备列表 | [_loadTrustedDevices](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:66) → `getTrustedDevices` | 无 Action 或视图；`mesh.devices` 是另一套设备集合。 |
| 撤销某设备的信任 | [_removeTrustedDevice](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:91) → [实际撤销](~/Desktop/NipaPlay-Reload/lib/services/remote_control_access_guard_service.dart:221) | 无对应能力。 |
| 对新遥控请求选择“允许”“拒绝”“信任此设备” | [授权对话框](~/Desktop/NipaPlay-Reload/lib/services/remote_control_access_guard_service.dart:233)，选项分别在 [262](~/Desktop/NipaPlay-Reload/lib/services/remote_control_access_guard_service.dart:262)、[277](~/Desktop/NipaPlay-Reload/lib/services/remote_control_access_guard_service.dart:277)、[282](~/Desktop/NipaPlay-Reload/lib/services/remote_control_access_guard_service.dart:282) | 无待授权请求视图或决策 Action。这不是输入秘密的例外。 |
| 查看访问地址、获取公网地址、复制地址 | [_loadAccessUrls](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:148)、[公网地址请求](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:157)、[_copyUrl](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:289) | 无 Classic 访问地址视图或对应操作。 |
| 显示连接二维码、复制二维码内容、设置是否显示二维码 | [二维码对话框](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:457)、[复制](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:504)、[显示设置](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_access_receiver_settings_section.dart:556) | 无对应 Action 或注册设置。 |

这是明确的接口限制：远程访问服务和遥控接收端相关键及前缀被 [设置 denylist](~/Desktop/NipaPlay-Reload/lib/next/settings/denylist.dart:22) 屏蔽。

### 1.2 无法完成 Classic 旧版遥控器的连接与管理流程

入口为 Cupertino 设置中的遥控器页面，实际通信由 `RemoteControlClientService` 完成。

| 操作 | Classic 位置 | 缺口 |
|---|---|---|
| 扫描局域网并自动匹配遥控目标 | [_scanDevices](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:56) → [发现服务](~/Desktop/NipaPlay-Reload/lib/services/remote_control_client_service.dart:42) | 没有对应 Classic 协议的扫描 Action。 |
| 扫描二维码、探测候选地址并保存目标 | [二维码连接](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:94) | 无对应能力。 |
| 清除已匹配的遥控目标 | [_clearMatchedTarget](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:193) | 无对应能力或设置。 |
| 刷新目标状态、发起控制授权请求 | [状态刷新](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:172)、[请求访问](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:353) → [fetchPlayerState](~/Desktop/NipaPlay-Reload/lib/services/remote_control_client_service.dart:141) | 无该协议的状态查询和授权发起 Action。 |
| 向目标发送弹幕 | [_sendDanmaku](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:416) → `sendCommand('send_danmaku')` | Mesh 白名单不包含弹幕能力。 |
| 在遥控面板读取并修改目标播放器参数 | [参数菜单](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:437)、[参数提交](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:747) → `sendCommand('set_parameter')` | 本机设置注册不能代替修改目标设备；Mesh 不允许 `settings.*`。 |

基本播放控制的条件性覆盖见“部分覆盖”。不能用 Mesh 的存在认定上述旧协议已经覆盖。

### 1.3 弹弹play远程媒体库整条来源流程缺失

`media.sources.add` 的来源枚举没有弹弹play远程服务器。`accounts.login` 是账户登录，不能替代远程媒体库连接。

| 操作 | Classic 位置及实际服务 |
|---|---|
| 配置远程地址并发起连接，包括交给用户输入 API Token | [连接对话框](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:880) → [DandanplayRemoteService.connect](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_remote_service.dart:95) |
| 修改连接后重新连接 | [重新连接提交](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:944) |
| 刷新远程库 | [_refreshDandanplay](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:962) → [refreshLibrary](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_remote_service.dart:143) |
| 断开远程库 | [断开确认](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:982) → [disconnect](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_remote_service.dart:124) |
| 浏览、搜索及清空搜索 | [搜索处理](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dandanplay_remote_library_view.dart:431)、[过滤实现](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dandanplay_remote_library_view.dart:523) |
| 打开远程作品详情并取得远程剧集播放上下文 | [_openAnimeDetail](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/dandanplay_remote_library_view.dart:864) |

**边界：**已有历史或已知流地址可能由 `playback.open` 播放；这里缺失的是来源配置、登录发起、发现和详情流程，不能据此声称“任何弹弹play远程视频都无法播放”。

### 1.4 无法管理 NipaPlay 共享客户端的媒体库

现有 `nipaplay` 来源能浏览共享内容，但不能完成下面的对端管理操作。

| 操作 | Classic 界面与实际 Provider 方法 |
|---|---|
| 刷新对端库管理信息，读取扫描文件夹、对端连接及扫描状态 | [刷新库管理按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:255) → [refreshManagement](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:967)、[refreshScanStatus](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1075) |
| 添加对端扫描文件夹，并选择添加后扫描 | [添加文件夹对话框](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1854) → [addRemoteFolder](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1807) |
| 对单个对端文件夹重新扫描 | [文件夹扫描按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1702) → `addRemoteFolder(scan: true, skipPreviouslyMatchedUnwatched: false)` |
| 移除对端扫描文件夹 | [移除按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1717) → [removeRemoteFolder](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1893) |
| 智能刷新，并跳过此前已匹配的未观看内容 | [智能刷新按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:302) → [rescanRemoteAll](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1967) |
| 清理不存在的对端文件夹 | [清理按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:271) → [cleanupMissingRemoteFolders](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:2022) |
| 在对端新增、编辑或删除 WebDAV 连接 | [新增入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:407)、[编辑入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6441)、[删除入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6498) → [addWebDAVConnection](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:2054)、`removeWebDAVConnection` |
| 测试对端 WebDAV 连接 | [测试入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6534) → [testWebDAVConnection](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1382) |
| 浏览对端 WebDAV 目录 | [目录加载入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:5770) → [listRemoteWebDAVDirectory](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1246) |
| 刮削对端 WebDAV 文件夹 | [刮削入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:5936) → [scanRemoteWebDAVFolder](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1454) |
| 在对端新增、编辑或删除 SMB 连接 | [连接对话框入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:452)、[删除入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6350) → [addSMBConnection](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:2116)、`removeSMBConnection` |
| 测试、刷新对端 SMB 连接 | [刷新入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6384) → [testSMBConnection](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1650) |
| 浏览对端 SMB 目录 | [目录加载入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6126) → [listRemoteSMBDirectory](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1525) |
| 刮削对端 SMB 文件夹 | [刮削入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6172) → [scanRemoteSMBFolder](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:1707) |

这些操作最终调用对端管理 API，见 [路由与处理](~/Desktop/NipaPlay-Reload/lib/services/local_media_management_api.dart:45)。Next 的 [同步实现](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:989) 只遍历并登记文件，没有上述对端写入；在本机添加 SMB/WebDAV 来源也不会配置对端连接。

### 1.5 Jellyfin/Emby 多地址管理缺失

| 操作 | Classic 位置 |
|---|---|
| 为同一服务器添加备用地址 | [对话框回调](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:490) → [addServerAddress](~/Desktop/NipaPlay-Reload/lib/services/media_server_service_base.dart:950) |
| 删除某个备用地址及取消删除 | [删除回调](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:524) → [removeServerAddress](~/Desktop/NipaPlay-Reload/lib/services/media_server_service_base.dart:996) |
| 切换已有地址 | [切换回调](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:551) → [switchToAddress](~/Desktop/NipaPlay-Reload/lib/services/media_server_service_base.dart:1016) |
| 设置单个地址的优先级 | [优先级回调](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:581) → [updateServerPriority](~/Desktop/NipaPlay-Reload/lib/services/media_server_service_base.dart:1061) |

`media.sources.update` 只修改当前地址配置，没有 `addressId`、备用地址集合或优先级参数；新增另一个来源也不能替代同一 Profile 的地址管理。

### 1.6 网络 API 地址与诊断缺失

| 操作 | Classic 位置及实际调用 |
|---|---|
| 选择弹弹play API 的自动、香港、国内或自定义模式 | [_changeServer](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:252) → [setDandanplayServerMode](~/Desktop/NipaPlay-Reload/lib/utils/network_settings.dart:102) |
| 保存或清除自定义弹弹play API 地址 | [地址对话框](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:277) → [setDandanplayServer](~/Desktop/NipaPlay-Reload/lib/utils/network_settings.dart:188)、`clearCustomServer` |
| 恢复弹弹play API 默认模式 | [重置操作](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:421) → `resetToDefaultServer` |
| 保存自定义 Bangumi API 地址 | [地址对话框](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:340) → [setBangumiServer](~/Desktop/NipaPlay-Reload/lib/utils/network_settings.dart:222) |
| 恢复 Bangumi API 默认地址 | [重置操作](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:454) → `resetBangumiServer` |
| 刷新网络诊断、自动路由判定及连接状态 | [诊断操作](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:221) → [NipaPlayServerRouter.refresh](~/Desktop/NipaPlay-Reload/lib/services/nipaplay_server_router.dart:131)、`Connectivity.checkConnectivity` |

没有对应注册键或 Action。`diagnostics.*` 的日志功能不能执行这里的网络诊断。

### 1.7 其他明确缺失

- **共享客户端的局域网扫描、二维码连接。**入口为 [选择共享客户端菜单](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart:250) 和 [远程媒体设置二维码连接](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1033)。手动已知地址可添加，但发现、扫码和候选地址探测没有对应能力。
- **查看、刷新、修改媒体服务器设备 ID，恢复生成的 ID。**Classic：[读取信息](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1510)、[修改提交](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1362)、[恢复](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1387)；实际写入 [MediaServerDeviceIdService](~/Desktop/NipaPlay-Reload/lib/services/media_server_device_id_service.dart:58)。没有对应设置、视图或 Action。
- **远程输入会话的读取与普通文本提交。**Classic：[加载与提交入口](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_remote_text_input_sheet.dart:60) → [fetchMetadata](~/Desktop/NipaPlay-Reload/lib/services/remote_text_input_service.dart:405)、[submitValues](~/Desktop/NipaPlay-Reload/lib/services/remote_text_input_service.dart:436)。这里仅计非秘密字段；没有会话能力。
- **Web 界面连接或切换远程 API 后端。**Classic：[WebRemoteAccessGate._connect](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/web_remote_access_gate.dart:124) → 探测地址、[WebRemoteAccessService.setBaseUrl](~/Desktop/NipaPlay-Reload/lib/services/web_remote_access_service.dart:34)。`media.sources.add(type: nipaplay)` 添加共享客户端，不会设置这个 Web 界面的 API 后端。

## 2. 部分覆盖

| Classic 操作 | 已有能力 | 具体缺少什么 |
|---|---|---|
| 在服务器设置对话框中设置默认转码开关、默认画质 | `playback.select_stream` | 能写同一套默认值，但必须先加载 Jellyfin/Emby 视频，并会重载当前流。Classic 可在未播放时直接设置：[转码开关](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:1194)、[默认画质](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:1240)。Next 的限制见 [_itemId](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_playback_controls.dart:35)、[selectStream](~/Desktop/NipaPlay-Reload/lib/next/capabilities/classic_playback_controls.dart:281)。 |
| 播放前为任意 Emby 剧集选择版本、音轨、字幕并保存偏好 | `media.sources.query`、`playback.stream_options/select_stream` | 可读媒体版本事实；修改只面向当前流，没有目标剧集参数。Classic 可对尚未播放的剧集操作：[入口](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:488) → [偏好保存](~/Desktop/NipaPlay-Reload/lib/services/emby_media_selection_controller.dart:172)。 |
| Emby 音轨或字幕选择“跟随默认” | `playback.select_stream` | 有显式音轨、字幕索引和禁用字幕，没有 `followDefault` 语义；省略字段表示保留当前选择。Classic 选项见 [音轨](~/Desktop/NipaPlay-Reload/lib/widgets/emby_media_source_selector.dart:417)、[字幕](~/Desktop/NipaPlay-Reload/lib/widgets/emby_media_source_selector.dart:449)。 |
| 在 SMB/WebDAV 连接对话框中测试尚未保存的候选配置 | `media.sources.check/login` | `check` 只接收已保存的 `sourceId`，不能直接测试临时配置；需要先保存。Classic WebDAV 的测试与保存分离：[测试](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/webdav_connection_dialog.dart:322)、[保存](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/webdav_connection_dialog.dart:392)。 |
| 测试失败后更新连接状态 | `media.sources.check`、`media.sources.list` | `check` 成功才更新 `isConnected=true`；异常路径不更新失败状态，列表可能保留此前成功状态，见 [实现](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:457)。Classic [WebDAV 状态更新](~/Desktop/NipaPlay-Reload/lib/services/webdav_service.dart:729) 会写入成功或失败。 |
| 查看来源完整配置、共享客户端当前选中状态、最近连接时间和错误 | `media.sources.list` | 只返回有限配置及连接状态；SMB `domain`、Jellyfin/Emby 地址集合、共享客户端 `isActive/lastConnected/error` 等未返回。对照 [Next 列表](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:110) 与 [Classic 共享选择模型](~/Desktop/NipaPlay-Reload/lib/remote/shared_remote_host_selection_model.dart:9)。 |
| Jellyfin/Emby 搜索当前库或跨所选库搜索 | `media.sources.browse/sync`、`state.query` | 可枚举后自行过滤，也可查询已索引内容；没有直接调用服务器搜索的关键词、搜索范围、限制参数。Classic：[库内搜索](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:1795)、[跨库搜索](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:1855)。`media.library.search` 查询本机 Classic 库，不能替代。 |
| WebDAV 文件搜索、限制深度/目标/超时、查看进度、中止搜索、打开结果目录 | `webdavQuick.search*` 设置、`media.sources.browse/sync` | 搜索偏好可改，也能逐目录枚举；没有执行 Classic 搜索流程的 Action。`browse` 没有搜索参数，`sync` 也没有该搜索的停止条件和回调。Classic：[搜索执行](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:1949)、[打开结果目录](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:2042)，实际 [searchFiles](~/Desktop/NipaPlay-Reload/lib/services/webdav_service.dart:1881)。 |
| Jellyfin/Emby 修改当前库或全局排序并保存 | `state.query` 可对已记录字段排序 | 没有写入 Classic 排序偏好的能力，也没有 `browse` 排序参数。Classic [排序应用](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:2394) 会保存后重新加载。 |
| Jellyfin/Emby “只看未观看”，读取服务器观看进度 | 本机历史及 `state.query` | 服务器 `UserData/Played/PlaybackPosition` 未进入 Next 元数据白名单，见 [白名单](~/Desktop/NipaPlay-Reload/lib/next/media_sources/metadata.dart:9)。Classic 过滤使用服务器 `isPlayed`：[过滤](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:238)。`library.files.progress` 是本机历史，不能代替服务器状态。 |
| 共享库搜索、排序、“只看未观看”、管理列表/图标切换 | `media.sources.browse`；本机历史可查询 | 能获取标题并自行过滤；不能改变 Classic 当前搜索、排序、未看开关或管理视图。Classic 的共享“未看”基于本机历史；排序还使用共享摘要字段。入口见 [工具栏](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:225)。 |
| 查看共享作品和剧集完整信息，并按对端进度续播 | `media.sources.libraries/browse`、`playback.open` | 返回名称、条目及播放地址，但遗漏简介、封面、媒体身份、对端进度、时长、缺失文件、观看时间、哈希等；`query` 明确不支持 `nipaplay`。对照 [Next 返回值](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:515) 与 [Classic 历史构造](~/Desktop/NipaPlay-Reload/lib/providers/shared_remote_library_provider.dart:835)。已知 URL 的基本播放已覆盖，新条目的身份与续播上下文没有等价传递。 |
| 查看 Jellyfin/Emby 详情中的全部展示信息 | `media.sources.query/browse` | 基本描述、人员、类型、年份等有覆盖，但 `ImageTags`、服务器观看数据等被过滤；“complete metadata”的描述超过实际白名单。Classic [详情加载](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:287)，Next [字段过滤](~/Desktop/NipaPlay-Reload/lib/next/media_sources/metadata.dart:61)。 |
| 刮削本机配置的 SMB/WebDAV 文件夹 | `media.sources.sync`、元数据查询、`media.identity.bind_batch` | 文件发现和人工确认绑定可组合完成；不能认定已覆盖 Classic 自动刮削。Classic 还构造远程探测 URL 并执行刮削：[WebDAV](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:5936)、[SMB](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6172)。`media.hash.match` 仅支持 native 文件。 |
| 对任意目录发起递归发现 | `media.sources.browse/sync` | Jellyfin/Emby `browse` 支持递归；SMB/WebDAV 递归须 `sync`，而 `sync` 从已选择的 `libraries` 开始，不能直接传任意深层目录或根路径。手工逐层枚举仍可做到。限制见 [browse](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:639)、[select](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:433)。 |
| 设置 WebDAV 快速识别规则后直接播放，自动执行 bgm/tmdb 识别及剧集偏移 | 相关设置、`playback.open`、显式绑定能力 | 设置已覆盖；`playback.open` 没有调用该页的规则处理。Classic 在 [_playFile](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:240) 中匹配后构造历史，再调用播放服务：[历史构造](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:375)。Agent 可显式匹配和绑定，但不能把“改设置后播放”认定为同一流程。 |
| 打开具体远程作品详情、指定季、共享详情、媒体库子页、指定目录；返回和路径导航 | `ui.open`、来源浏览能力 | 数据层浏览可以组合；`ui.open` 只有顶层页面及普通作品详情，没有上述远程上下文参数。Classic：[季切换](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:1821)、[共享详情](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1893)、[WebDAV 返回](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:216)。 |
| 遥控另一台设备的暂停、跳转、上下集等基本播放行为 | `mesh.invoke` 调用对端 `playback.*` | 仅在 Mesh 已配置、同账号信任成立且对端提供能力时可用，不能操作任意 Classic 遥控目标。代码中的生产 issuer 为空，常规 release 会返回 `issuer_not_configured`，见 [启动条件](~/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:86)。Classic 快捷按钮见 [547](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart:547)。 |
| 远程文件“移除扫描结果” | `media.identity.unbind_batch` | 只撤销 Next 显式绑定，并按投影日志恢复；不等于清除独立 Classic 扫描匹配。Classic [操作](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4731) 与 Next [语义](~/Desktop/NipaPlay-Reload/lib/next/media/media_capability.dart:496) 不同。 |

## 3. 已覆盖

以下每行对应一个操作；“基本播放”“已保存连接”等限定与上一节的缺口同时成立。

### 来源配置、浏览与播放

| 操作 | 能力 id | Classic 入口 |
|---|---|---|
| 新增 Jellyfin/Emby 来源，保存非秘密连接信息 | `media.sources.add` | [服务器连接对话框](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:733) |
| 修改 Jellyfin/Emby 当前地址及账户配置 | `media.sources.update` | [服务器连接对话框](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:621)；不含备用地址管理 |
| 发起 Jellyfin/Emby 登录，交由用户完成密码输入 | `media.sources.login` | [服务器连接入口](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:733)；Next [用户窗口接入](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:85) |
| 查看 Jellyfin/Emby 可选媒体库 | `media.sources.libraries` | [媒体库选择列表](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:927) |
| 保存 Jellyfin/Emby 媒体库选择，包括清空选择 | `media.sources.select` | [保存选择](~/Desktop/NipaPlay-Reload/lib/widgets/network_media_server_dialog.dart:621) |
| 查看 Jellyfin/Emby 媒体库条目及文件夹 | `media.sources.browse` | [_loadLibraryContent](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:2024) |
| 刷新或重试读取当前远程库、目录 | `media.sources.libraries/browse` | [_manualRefresh](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/network_media_library_view.dart:276) |
| 读取 Jellyfin/Emby 作品基本详情 | `media.sources.query` | [_loadMediaDetail](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:287) |
| 枚举作品的季 | `media.sources.browse` | [季加载](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:347) |
| 枚举所选季的剧集 | `media.sources.browse` | [_loadEpisodesForSeason](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:378) |
| Jellyfin/Emby 电影基本播放 | `playback.open` | [_playMediaItem](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:625) |
| Jellyfin/Emby 剧集基本播放 | `playback.open` | [_playEpisode](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:1863) |
| 断开当前 Jellyfin/Emby 来源 | `media.sources.remove` | [断开操作](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:842) |
| 新增 SMB 连接配置 | `media.sources.add` | [SMB 对话框提交](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/smb_connection_dialog.dart:310) |
| 修改 SMB 名称、主机、端口、域及用户名 | `media.sources.update` | [SMB 对话框提交](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/smb_connection_dialog.dart:310) |
| 发起 SMB 用户登录 | `media.sources.login` | [SMB 连接入口](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:452) |
| 测试已保存的 SMB 连接是否可访问 | `media.sources.check` | [_refreshSMBConnection](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6384) |
| 枚举 SMB 共享及目录、进入子目录 | `media.sources.libraries/browse` | [_loadSMBFolderChildren](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6126) |
| 播放 SMB 文件 | `playback.open` | [_playSMBFile](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6337) |
| 删除本机 SMB 连接 | `media.sources.remove` | [_removeSMBConnection](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:6350) |
| 新增 WebDAV 连接配置 | `media.sources.add` | [_showAddServerDialog](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:448) |
| 修改 WebDAV 名称、地址及用户名 | `media.sources.update` | [_editCupertinoWebDavServer](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_webdav_browser_controls.dart:598) |
| 发起 WebDAV 用户登录 | `media.sources.login` | [WebDAV 连接对话框](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/webdav_connection_dialog.dart:392) |
| 测试已保存的 WebDAV 连接是否可访问 | `media.sources.check` | [当前连接测试菜单](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_webdav_browser_controls.dart:583) |
| 枚举 WebDAV 目录、进入子目录 | `media.sources.browse` | [_loadDirectory](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:122)、[_navigateToDirectory](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:206) |
| 刷新 WebDAV 目录 | `media.sources.browse` | [刷新按钮](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:1273) |
| WebDAV 文件基本播放 | `playback.open` | [_playFile](~/Desktop/NipaPlay-Reload/lib/pages/webdav_browser_page.dart:240) |
| 删除本机 WebDAV 连接 | `media.sources.remove` | [_removeCupertinoWebDavServer](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_webdav_browser_controls.dart:616) |
| 按已知地址手动添加 NipaPlay 共享客户端 | `media.sources.add` | [_showAddSharedHostDialog](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1093) |
| 修改共享客户端名称或地址 | `media.sources.update` | [_showEditSharedHostDialog](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1122) |
| 切换共享客户端并访问其内容 | `media.sources.libraries/browse` 自动激活指定来源 | [客户端行选择](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:627)；Next [激活实现](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:367) |
| 刷新共享媒体列表 | `media.sources.libraries` | [刷新按钮](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:255) |
| 枚举共享作品及其剧集 | `media.sources.libraries/browse` | [_openEpisodeSheet](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1893) |
| 浏览共享客户端的本地文件目录 | `media.sources.browse(parentId: 路径)` | [_loadRemoteDirectory](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1368) |
| 共享文件或剧集的基本流播放 | `playback.open` | [_playRemoteFile](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/shared_remote_library_view.dart:1495)；身份与续播限制见上一节 |
| 删除共享客户端记录 | `media.sources.remove` | [_confirmRemoveSharedHost](~/Desktop/NipaPlay-Reload/lib/settings/pages/remote_media_library_settings_content.dart:1254) |
| 对已索引 SMB/WebDAV 文件保存人工匹配结果 | `media.identity.bind_batch` | [_showManualDanmakuMatchDialog](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4628) |
| 对已索引 SMB/WebDAV 文件批量保存明确匹配结果 | `media.identity.bind_batch` | [_showBatchDanmakuMatchDialog](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4310) |

### 设置操作

下面的注册设置均可通过 `settings.get/set/reset` 操作；WebDAV 键的注册及实际 Provider 写入集中在 [classic_settings.dart](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:601)。

| 操作 | 能力 id / 注册键 | Classic 位置 |
|---|---|---|
| 设置播放器自定义 User-Agent | `settings.set` → `player.customUserAgent` | [保存](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:516) |
| 重置播放器 User-Agent | `settings.reset` → `player.customUserAgent` | [重置](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:529) |
| 设置或清空桌面 HTTP 代理 | `settings.set` → `network.httpProxy` | [代理对话框](~/Desktop/NipaPlay-Reload/lib/settings/pages/network_settings_content.dart:540) |
| 显示或隐藏 WebDAV Tab | `settings.set` → `webdavQuick.showTab` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:89) |
| 设置默认主页 | `settings.set` → `general.defaultHomeTab` | [选择](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:110) |
| 设置默认 WebDAV 服务器 | `settings.set` → `webdavQuick.defaultServerName` | [选择](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:147) |
| 设置默认目录 | `settings.set` → `webdavQuick.defaultDirectory` | [保存](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:159) |
| 设置文件排序预设 | `settings.set` → `webdavQuick.sortPreset` | [选择](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:178) |
| 显示或隐藏路径导航 | `settings.set` → `webdavQuick.showPathBreadcrumb` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:186) |
| 设置是否自动进入 Season 文件夹 | `settings.set` → `webdavQuick.autoEnterSeasonFolder` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:201) |
| 修改 Season 文件夹匹配模式 | `settings.set` → `webdavQuick.seasonFolderPattern` | [编辑](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:210) |
| 设置 bgm ID 快速匹配开关 | `settings.set` → `webdavQuick.bgmIdQuickMatch` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:232) |
| 修改 bgm ID 匹配规则 | `settings.set` → `webdavQuick.bgmIdMatchPattern` | [保存](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:245) |
| 设置 TMDB ID 快速匹配开关 | `settings.set` → `webdavQuick.tmdbIdQuickMatch` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:255) |
| 修改 TMDB ID 匹配规则 | `settings.set` → `webdavQuick.tmdbIdMatchPattern` | [保存](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:268) |
| 设置自动剧集偏移 | `settings.set` → `webdavQuick.episodeOffsetEnabled` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:278) |
| 开启或关闭文件搜索 | `settings.set` → `webdavQuick.enableSearch` | [开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:292) |
| 设置搜索范围 | `settings.set` → `webdavQuick.searchScope` | [选择](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:310) |
| 设置搜索层级限制 | `settings.set` → `webdavQuick.searchDepthLimit` | [滑块](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:323) |
| 设置搜索目标为文件夹、视频或两者 | `settings.set` → `webdavQuick.searchTargets` | [目标开关](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:333) |
| 设置搜索超时 | `settings.set` → `webdavQuick.searchTimeout` | [选择](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:361) |
| 设置搜索请求间隔 | `settings.set` → `webdavQuick.searchRequestInterval` | [滑块](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:373) |
| 设置搜索最大结果数 | `settings.set` → `webdavQuick.searchMaxResults` | [滑块](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:386) |
| 重置全部 WebDAV 快捷设置 | `webdav_quick.reset` | [重置按钮](~/Desktop/NipaPlay-Reload/lib/settings/pages/webdav_quick_settings_content.dart:401) |

## 4. 反方向风险

### 4.1 删除确认可以由 Agent 自行声明

Classic 删除共享客户端、SMB、WebDAV 连接等入口要求用户在确认对话框中选择删除，例如 [WebDAV 删除对话框](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_webdav_browser_controls.dart:616)。

Next `media.sources.remove`：

- 有 `Effect.destructive`，并非没有保护。
- `confirm: true` 就执行删除，否则返回预览，见 [执行分支](~/Desktop/NipaPlay-Reload/lib/next/media_sources/capability.dart:303)。
- HTTP Agent Endpoint 另要求 `execute: true`，见 [端点检查](~/Desktop/NipaPlay-Reload/lib/next/agent_endpoint.dart:297)。
- 两个布尔值均由调用方提供；这条路径没有要求 Classic 用户确认对话框或用户确认凭据。

因此，**代码层面的确认由用户点击改为调用方声明，Agent 能绕过原 UI 确认步骤**。这不等于删除完全没有预览或破坏性标记。

### 4.2 SMB/WebDAV 配置可在连接验证失败前覆盖保存

Classic SMB `addConnection/updateConnection` 先测试，通过后才保存；失败时保留原配置，见 [新增](~/Desktop/NipaPlay-Reload/lib/services/smb_service.dart:272)、[更新](~/Desktop/NipaPlay-Reload/lib/services/smb_service.dart:312)。Classic WebDAV `upsertConnection` 也先验证，见 [实现](~/Desktop/NipaPlay-Reload/lib/services/webdav_service.dart:339)。

Next `media.sources.add/update` 使用无需连接验证的 `configureConnection`：

- SMB 调用位置：[223](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:223)。
- WebDAV 调用位置：[245](~/Desktop/NipaPlay-Reload/lib/next/media_sources/service.dart:245)。

分离配置与用户登录有明确用途，但当前更新路径确实允许**先覆盖此前可用配置，再登录或检查；失败后没有这里的自动回滚**。这是 Classic 保存流程原本不允许的状态变更。

### 4.3 Mesh 授权与 Classic“被遥控端”开关相互独立

Classic 遥控请求先经过 [RemoteControlAccessGuard](~/Desktop/NipaPlay-Reload/lib/services/remote_control_api_service.dart:103)，执行命令时还检查 [receiverEnabled](~/Desktop/NipaPlay-Reload/lib/services/player_remote_control_bridge.dart:92)。

Mesh 接收路径直接创建 MCP RPC 并调用 Harness，见 [620](~/Desktop/NipaPlay-Reload/lib/next/mesh/runtime.dart:620)，没有经过上述 Classic 开关或逐设备确认。

因此，**在 Mesh 已配置、可启动且同账号信任成立的条件下，关闭 Classic 被遥控端或撤销 Classic 可信设备，不能据此保证阻止 Mesh 的远程播放调用**。Mesh 有自己的认证和信任检查，不能称为未授权访问；同时生产 issuer 当前为空，不能宣称普通 release 已能触发此路径。

## 5. 没能审完及待确认部分

- **远程入口中的自定义媒体信息完整字段映射未审完。**已找到 WebDAV/SMB 文件夹入口：[WebDAV](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4496)、[SMB](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4582)。未逐字段核对 `CustomMediaInfoDialog` 与 `media.metadata.override`，因此不把整项判为已覆盖。
- **自动匹配的完整等价性待确认。**Classic 详情页有自动匹配及“中断匹配”按钮：[802](~/Desktop/NipaPlay-Reload/lib/pages/media_server_detail_page.dart:802)。Next 有任务取消和显式绑定，但没有证据表明 `task.cancel` 能取消这个 Classic 对话框启动的匹配流程。完整匹配策略属于相邻模块，本次没有展开。
- **未逐一穷举所有主题、平台和全局交互入口。**已核对指定起点及相关 Nipaplay/Cupertino 页面、菜单和对话框回调；没有完成全仓库快捷键、拖放、电视端及所有独立主题控件的逐入口审计，不能据此证明这些入口没有额外操作。
- **未验证运行时行为。**按只读要求没有构建、启动或联网测试；登录窗口、设备发现、真实服务器分页、流切换和平台差异的运行结果仍待验证。上述明确缺口均有静态接口或调用链依据。