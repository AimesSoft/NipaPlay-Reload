# NipaPlay 局域网 API 安全调研与 Mesh 传输层草案

> 调研日期：2026-10-10  
> 范围：当前工作区的 HTTP 服务、路由、调用方、发现与授权实现，以及 `docs/next/DESIGN.md`。  
> 方法：只读源码分析；未修改文件，未运行服务器或实施利用测试。  
> 证据格式：仓库相对路径 `file:line`。依赖库证据另外标明本机缓存路径。  
> 本文将**代码事实**、**基于代码的攻击路径推导**、**设计建议**分开陈述。攻击路径尚未经过运行时复现。

## 1. 设计结论

1. **现有服务是整组宿主能力的无统一鉴权入口。** `/api` 不仅提供共享播放，还提供宿主账号操作、历史写入、媒体库管理、网络配置和通用 HTTP 代理。只有遥控命令检查 `RemoteControlAccessGuardService`；遥控状态即使未授权仍返回状态数据。证据：`lib/services/web_api_service.dart:38`、`lib/services/web_api_service.dart:83`、`lib/services/remote_control_api_service.dart:30`、`lib/services/remote_control_api_service.dart:35`、`lib/services/remote_control_api_service.dart:101`。

2. **服务可能在用户没有打开“Web 自动启动”时启动。** 接收端默认开启，后台初始化在接收端开启时启动整个 Web server，而不是仅启动遥控子接口；IPv4 默认监听所有地址，启用 IPv6 时尝试双栈监听。证据：`lib/services/remote_control_settings.dart:15`、`lib/providers/service_provider.dart:51`、`lib/services/web_server_service.dart:407`、`lib/services/web_server_service.dart:422`。

3. **不能直接改成仅同源、仅回环、禁止所有私网代理或关闭管理接口。** Web UI 可以独立部署并连接指定宿主；共享库 provider 同时被 Web 和原生实例使用；Web 播放其他共享实例时会走宿主代理。证据：`lib/services/web_remote_access_service.dart:46`、`lib/services/web_remote_access_service.dart:66`、`lib/themes/nipaplay/widgets/web_remote_access_gate.dart:124`、`lib/providers/shared_remote_library_provider.dart:683`、`lib/providers/shared_remote_library_provider.dart:743`。

4. **两个“任意文件读取”描述需要区分。** `image_proxy` 本地分支有图片扩展名限制；`folders → manage/stream` 有媒体扩展名限制。但另有更直接的链：`history/progress` 可以创建带任意本地路径和 `animeId` 的历史，共享服务将其加入映射，`share/.../stream` 不检查扩展名或共享根。证据：`lib/services/web_api_service.dart:210`、`lib/services/local_media_management_api.dart:760`、`lib/services/web_api_service.dart:853`、`lib/services/local_media_share_service.dart:161`、`lib/services/local_media_share_service.dart:409`。

5. **宿主弹弹play token 注入并非对任意直接目标无条件发生，但存在可推导的外层 URL 泄露路径。** HTTP 客户端递归展开任何以 `/api/web_proxy` 或 `/api/image_proxy` 结尾的 URL，再依据内层目标决定注入 token，实际发送的却仍是外层请求。攻击者可构造自己的同名路径，令内层指向弹弹play站点。证据：`lib/services/dandanplay_http_client.dart:30`、`lib/services/dandanplay_http_client.dart:59`、`lib/services/dandanplay_http_client.dart:72`、`lib/services/dandanplay_http_client.dart:91`。

6. **A 档只能消除实现缺陷和减少泄露，无法在零调用方变更下完成局域网授权。** 当前合法调用与恶意调用在请求层没有可靠身份区别。B 档应建立设备密钥、配对、加密会话和资源授权，再把 Web 与 Mesh 作为同一 Harness 的 transport。设计依据：`docs/next/DESIGN.md:18`、`docs/next/DESIGN.md:25`、`docs/next/DESIGN.md:26`、`docs/next/DESIGN.md:27`；现状依据：`lib/services/remote_control_access_guard_service.dart:267`。

## 2. 路由清单

### 2.1 清单约定与有效方法

全部路径包含 `/api` 前缀，挂载位置为 `lib/services/web_server_service.dart:373`。子模块挂载位置为 `lib/services/web_api_service.dart:83`。

表中：

- **读**：没有直接修改领域状态；可能加载缓存、访问网络或读取磁盘。
- **写**：修改配置、历史、账号或播放状态。
- **条件写**：取决于参数或代理上游行为。
- **低 / 中 / 高 / 极高**：本调研建议的敏感等级，不是现有代码中的权限等级。
- 调用方编号见第 3 节；“未发现”指在本仓库生产代码中未发现调用，不代表外部用户从未使用。

**所有通过 `router.get` 注册的路由都还有隐式 HEAD。** 当前使用 `shelf_router 1.1.4`，其 `add('GET', ...)` 先注册 HEAD，再注册 GET；HEAD 调用同一 handler 后去掉响应体。路由按注册顺序返回首次匹配结果。因此，下表将这些方法写作 `GET / HEAD*`。

依赖证据：

- 版本：`pubspec.lock:1495`。
- 自动 HEAD：`~/.pub-cache/hosted/pub.dev/shelf_router-1.1.4/lib/src/router.dart:135`。
- 顺序匹配：同文件 `:175`。

**显式 HEAD 被遮蔽：** share 流、manage 流和 `web_proxy` 的显式 HEAD 都在 GET 后注册，因此实际先进入 GET 对应的隐式 HEAD handler。下表同时列出声明位置；这会影响性能和修复方式。证据：`lib/services/local_media_share_api.dart:14`、`lib/services/local_media_management_api.dart:65`、`lib/services/web_api_service.dart:47`。

### 2.2 顶层 API

以下 handler 均位于 `lib/services/web_api_service.dart`；注册证据为该文件 `:38`—`:82`。

| 方法 | 完整路径 | Handler 与位置 | 状态影响 | 敏感度 | 调用方 |
|---|---|---|---|---|---|
| GET / HEAD* | `/api/info` | `handleInfoRequest`，`lib/services/web_api_service.dart:92` | 读 | 低：主机名、系统、功能与接收端开关 | C1 |
| GET / HEAD* | `/api/bangumi/calendar` | `handleBangumiCalendarRequest`，`:116` | 读 | 低 | C2 |
| GET / HEAD* | `/api/bangumi/detail/<id>` | `handleBangumiDetailRequest`，`:131` | 读 | 低 | C3 |
| GET / HEAD* | `/api/bangumi/login_status` | `handleBangumiLoginStatusRequest`，`:148` | 读 | 中：账号信息 | C4 |
| GET / HEAD* | `/api/danmaku/video_info` | `handleVideoInfoRequest`，`:630` | 读、宿主探测文件 | 高：路径与文件信息 | C5 |
| POST | `/api/danmaku/match` | `handleDanmakuMatchRequest`，`:650` | 读、请求上游匹配 | 中 | C5 |
| GET / HEAD* | `/api/danmaku/load` | `handleDanmakuLoadRequest`，`:695` | 读 | 中：使用宿主账号服务 | C5 |
| GET / HEAD* | `/api/image_proxy` | `handleImageProxyRequest`，`:166` | 读、网络请求或本地文件读取 | 高 | C6 |
| GET / HEAD* | `/api/search/config` | `handleSearchConfigRequest`，`:248` | 读 | 低 | C7 |
| POST | `/api/search/by-tags` | `handleSearchByTagsRequest`，`:273` | 读 | 低 | C7 |
| POST | `/api/search/advanced` | `handleAdvancedSearchRequest`，`:304` | 读 | 低 | C7 |
| GET / HEAD* | `/api/dandanplay/login_status` | `handleLoginStatusRequest`，`:336` | 读 | 中：宿主账号与绑定信息 | C8 |
| POST | `/api/dandanplay/login` | `handleLoginRequest`，`:358` | 写：宿主登录状态 | 高 | C8 |
| POST | `/api/dandanplay/logout` | `handleLogoutRequest`，`:380` | 写：清除宿主登录 | 高 | C8 |
| POST | `/api/dandanplay/refresh_login` | `handleRefreshLoginRequest`，`:411` | 写：刷新账号、绑定状态 | 高 | C8 |
| GET / HEAD* | `/api/dandanplay/bangumi/oauth_login` | `handleBangumiOAuthLoginRequest`，`:393` | 获取宿主账号授权入口；上游副作用未确认 | 高 | C8 |
| GET / HEAD* | `/api/dandanplay/webtoken` | `handleWebTokenRequest`，`:446` | 签发业务 WebToken | 极高 | C8 |
| GET / HEAD* | `/api/dandanplay/play_history` | `handlePlayHistoryRequest`，`:467` | 读 | 高：账号历史 | C8 |
| GET / HEAD* | `/api/dandanplay/favorites` | `handleFavoritesRequest`，`:498` | 读 | 高：账号收藏 | C8 |
| POST | `/api/dandanplay/send_danmaku` | `handleSendDanmakuRequest`，`:516` | 写：宿主账号发弹幕 | 高 | C8 |
| POST | `/api/dandanplay/add_play_history` | `handleAddPlayHistoryRequest`，`:552` | 写：上游历史，可添加收藏 | 高 | C8 |
| POST | `/api/dandanplay/add_favorite` | `handleAddFavoriteRequest`，`:581` | 写：上游收藏 | 高 | C8 |
| DELETE | `/api/dandanplay/remove_favorite/<animeId>` | `handleRemoveFavoriteRequest`，`:611` | 写：删除上游收藏 | 高 | C8 |
| GET / HEAD* | `/api/media/libraries` | `handleGetLibrariesRequest`，`:896` | 读 | 中：宿主库列表 | **未发现** |
| GET / HEAD* | `/api/media/local/items` | `handleGetLocalMediaItemsRequest`，`:958` | 读 | 高：媒体、观看信息 | C9 |
| GET / HEAD* | `/api/media/local/item/<animeId>` | `handleGetLocalMediaItemDetailRequest`，`:1085` | 读 | 高：历史与文件路径 | **未发现** |
| GET / HEAD* | `/api/history` | `handleGetHistoryRequest`，`:718` | 读 | 高：完整路径、历史、缩略图 | C10 |
| POST | `/api/history/progress` | `handleUpdateHistoryProgressRequest`，`:751` | 写：可创建新历史 | 极高：与共享流组合可读文件 | C10 |

表中 `:行号` 沿用本表声明的完整文件路径。

### 2.3 通用代理

注册证据：`lib/services/web_api_service.dart:47`。

| 方法 | 路径 | Handler 与位置 | 状态影响 | 敏感度 | 调用方 |
|---|---|---|---|---|---|
| GET | `/api/web_proxy` | `WebUiProxyApi.handle`，`lib/services/web_ui_proxy_api.dart:22` | 取决于上游；可读内部服务 | 极高 | C11 |
| POST | 同上 | 同上 | 条件写 | 极高 | C11 |
| PUT | 同上 | 同上 | 条件写 | 极高 | C11：Bangumi |
| PATCH | 同上 | 同上 | 条件写 | 极高 | C11：Bangumi |
| DELETE | 同上 | 同上 | 条件写 | 极高 | 通用客户端有分发分支，未发现实际业务调用 |
| HEAD | 同上 | 声明 `handle`；有效路由为 GET 自动产生的 HEAD | 条件影响、网络请求 | 极高 | C11：图片探测 |
| OPTIONS | 同上 | `handleOptions`，`lib/services/web_ui_proxy_api.dart:65` | 无 | 低 | 浏览器预检；有 Origin 时由外层 CORS 提前响应 |

DELETE 分发证据：`lib/services/bangumi_api_service.dart:369`。OPTIONS 提前响应证据见第 4.4 节。

### 2.4 本地媒体共享 API

挂载 `/api/media/local/share/`。全部注册证据：`lib/services/local_media_share_api.dart:10`。

| 方法 | 完整路径 | Handler 与位置 | 状态影响 | 敏感度 | 调用方 |
|---|---|---|---|---|---|
| GET / HEAD* | `/api/media/local/share/animes` | `_handleListAnimes`，`lib/services/local_media_share_api.dart:32` | 读 | 高：共享库 | C12 |
| GET / HEAD* | `/api/media/local/share/animes/<animeId>`，仅数字 | `_handleAnimeDetail`，`:44` | 读 | 高：剧集、原始路径、shareId | C12 |
| GET / HEAD* | `/api/media/local/share/history` | `_handleWatchHistory`，`:65` | 读 | 高 | **未发现** |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/stream` | `_handleEpisodeStream`，`:86`；显式 HEAD `_handleEpisodeStreamHead`，`:104` | 读磁盘 | 极高：无统一身份检查 | C12、C13 |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/subtitles` | `_handleEpisodeSubtitles`，`:126` | 读 | 高 | C13 |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/subtitle` | `_handleEpisodeSubtitleStream`，`:150`；显式 HEAD `:154` | 读磁盘 | 高 | C13；未发现专用 HEAD 调用 |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/audio` | `_handleEpisodeExternalAudio`，`:192` | 读 | 高 | C13 |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/audio_file` | `_handleEpisodeAudioFileStream`，`:216`；显式 HEAD `:220` | 读磁盘 | 高 | C13；未发现专用 HEAD 调用 |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/fonts` | `_handleEpisodeFonts`，`:257` | 读 | 高 | C13 |
| GET / HEAD* | `/api/media/local/share/episodes/<shareId>/font` | `_handleEpisodeFontStream`，`:281`；显式 HEAD `:285` | 读磁盘 | 高 | C13；未发现专用 HEAD 调用 |
| POST | `/api/media/local/share/episodes/<shareId>/progress` | `_handleUpdateEpisodeProgress`，`:322` | 写历史 | 高 | C14 |
| POST | `/api/media/local/share/episodes/<shareId>/thumbnail` | `_handleUpdateEpisodeThumbnail`，`:392` | 写磁盘、更新历史 | 高 | C14 |

表中 `:行号` 沿用 `lib/services/local_media_share_api.dart`。HEAD 遮蔽规则见第 2.1 节。

### 2.5 本地媒体管理 API

挂载 `/api/media/local/manage/`。全部注册证据：`lib/services/local_media_management_api.dart:45`。

| 方法 | 完整路径 | Handler 与位置 | 状态影响 | 敏感度 | 调用方 |
|---|---|---|---|---|---|
| GET / HEAD* | `/api/media/local/manage/folders` | `_handleListFolders`，`lib/services/local_media_management_api.dart:106` | 读 | 极高：包含 WebDAV/SMB 密码 | C15 |
| POST | `/api/media/local/manage/folders` | `_handleAddFolder`，`:605` | 写共享根，可启动扫描 | 极高 | C15 |
| DELETE | `/api/media/local/manage/folders` | `_handleRemoveFolder`，`:657` | 写配置、移除根 | 高 | C15 |
| POST | `/api/media/local/manage/webdav` | `_handleAddWebDAV`，`:127` | 测试、保存连接 | 高 | C15 |
| DELETE | `/api/media/local/manage/webdav` | `_handleRemoveWebDAV`，`:144` | 删除连接 | 高 | C15 |
| GET / HEAD* | `/api/media/local/manage/webdav/list` | `_handleListWebDAV`，`:157` | 用宿主凭据列目录 | 高 | C15 |
| POST | `/api/media/local/manage/webdav/test` | `_handleTestWebDAV`，`:198` | 网络请求；已有连接可更新状态 | 高 | C15 |
| POST | `/api/media/local/manage/webdav/scan` | `_handleScanWebDAV`，`:237` | 刮削、写历史 | 高 | C15 |
| POST | `/api/media/local/manage/smb` | `_handleAddSMB`，`:301` | 测试、保存或更新连接 | 高 | C15 |
| DELETE | `/api/media/local/manage/smb` | `_handleRemoveSMB`，`:327` | 删除连接 | 高 | C15 |
| GET / HEAD* | `/api/media/local/manage/smb/list` | `_handleListSMB`，`:340` | 用宿主凭据列目录 | 高 | C15 |
| POST | `/api/media/local/manage/smb/test` | `_handleTestSMB`，`:381` | 更新连接状态 | 高 | C15 |
| POST | `/api/media/local/manage/smb/scan` | `_handleScanSMB`，`:404` | 刮削、写历史 | 高 | C15 |
| GET / HEAD* | `/api/media/local/manage/browse` | `_handleBrowse`，`:682` | 读目录 | 高 | C15 |
| GET / HEAD* | `/api/media/local/manage/stream` | `_handleStream`，`:738`；显式 HEAD `:742` | 读磁盘 | 高 | C15、C13 |
| GET / HEAD* | `/api/media/local/manage/subtitles` | `_handleSubtitles`，`:831` | 读目录 | 高 | C13 |
| GET / HEAD* | `/api/media/local/manage/subtitle` | `_handleSubtitleStream`，`:935`；显式 HEAD `:939` | 读磁盘 | 高 | C13；未发现专用 HEAD 调用 |
| GET / HEAD* | `/api/media/local/manage/scan/status` | `_handleScanStatus`，`:992` | 读 | 中：路径、扫描状态 | C15 |
| POST | `/api/media/local/manage/scan/rescan` | `_handleRescanAll`，`:1009` | 启动扫描、后续写历史 | 高 | C15 |

表中 `:行号` 沿用 `lib/services/local_media_management_api.dart`。

### 2.6 网络配置、遥控与远程输入

| 方法 | 完整路径 | Handler 与位置 | 状态影响 | 敏感度 | 调用方 |
|---|---|---|---|---|---|
| GET / HEAD* | `/api/settings/network/jellyfin` | `_handleGetJellyfinSettings`，`lib/services/network_media_settings_api.dart:27` | 读；不返回密码/token | 中 | C16 |
| POST | 同上 | `_handleUpdateJellyfinSettings`，同文件 `:49` | 连接服务器、改库选择 | 高 | C16 |
| GET / HEAD* | `/api/settings/network/emby` | `_handleGetEmbySettings`，同文件 `:81` | 读；不返回密码/token | 中 | C16 |
| POST | 同上 | `_handleUpdateEmbySettings`，同文件 `:95` | 连接服务器、改库选择 | 高 | C16 |
| GET / HEAD* | `/api/settings/network/dandanplay` | `_handleGetDandanplaySettings`，同文件 `:126` | 读；不返回 token | 中 | C16 |
| POST | 同上 | `_handleUpdateDandanplaySettings`，同文件 `:139` | 连接弹弹play远程库或断开 | 高 | C16 |
| GET / HEAD* | `/api/remote/control/state` | `_handleState`，`lib/services/remote_control_api_service.dart:21` | 读；`requestAccess=1` 可触发审批 | 高 | C17 |
| POST | `/api/remote/control/command` | `_handleCommand`，同文件 `:57` | 写播放、参数；检查 guard | 高 | C17 |
| GET / HEAD* | `/api/remote/input/<key>` | `_handleGet`，`lib/services/remote_text_input_service.dart:478` | 读会话元数据或 HTML | 高：key 是临时能力凭据 | C18 |
| POST | `/api/remote/input/<key>` | `_handlePost`，同文件 `:489` | 一次性提交输入 | 高 | C18 |

注册证据：`lib/services/network_media_settings_api.dart:12`、`lib/services/remote_control_api_service.dart:10`、`lib/services/remote_text_input_service.dart:467`。

## 3. 调用方清单

### 3.1 Web 静态入口与宿主选择

`web/` 没有独立手写 API 客户端。`web/index.html:36` 加载 Flutter 的 `flutter_bootstrap.js`；API 调用来自 Dart 编译后的应用。服务端实际查找 `assets/web`，而当前该目录只有 `.gitkeep`，所以不能把未存在的构建产物视为已审计代码。证据：`web/index.html:36`、`lib/services/web_server_service.dart:18`、`lib/services/web_server_service.dart:49`、`lib/services/web_server_service.dart:125`。

宿主选择支持：

- 页面查询参数 `api`、`apiBase`、`baseUrl`；
- 已保存的远端地址；
- 当前页面 Origin；
- 在 gate 中手动输入任意 HTTP/HTTPS 地址。

证据：`lib/services/web_remote_access_service.dart:46`、`:66`、`:107`；`lib/themes/nipaplay/widgets/web_remote_access_gate.dart:124`。

这意味着“浏览器 Web UI”至少包含同源宿主部署与独立部署两种拓扑。

### 3.2 路由到调用点的对应关系

以下行号均指实际构造 URL、发送请求或消费服务端生成 URL 的位置。

| 编号 | 路由与调用方 | 全部已定位调用点 |
|---|---|---|
| C1 | `/info`：Web 探测、弹弹play Web stub 探测、遥控发现、共享库扫描、二维码探测 | `lib/services/web_remote_access_service.dart:118`；`lib/services/dandanplay_service_stub.dart:119`；`lib/services/remote_control_client_service.dart:313`；`lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart:352`；`lib/services/remote_access_qr_service.dart:174` |
| C2 | `/bangumi/calendar`：Web 新番页、首页 | `lib/pages/new_series_page.dart:116`；`lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:105` |
| C3 | `/bangumi/detail/<id>`：Web 详情、季度回顾、弹弹play stub | `lib/pages/anime_detail_page.dart:684`；`lib/themes/nipaplay/widgets/large_screen_anime_detail_page.dart:245`；`lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart:160`；`lib/services/dandanplay_service_stub.dart:1608` |
| C4 | `/bangumi/login_status` | `lib/services/bangumi_api_service.dart:128` |
| C5 | `/danmaku/video_info`、`match`、`load`：弹弹play Web stub | 分别为 `lib/services/dandanplay_service_stub.dart:1201`、`:554`、`:1266` |
| C6 | `/image_proxy`：通用图片助手、共享库封面、弹弹play stub | `lib/services/web_remote_access_service.dart:194`；`lib/providers/shared_remote_library_provider.dart:475`；`lib/services/dandanplay_service_stub.dart:1331`；具体消费者见第 3.3 节 |
| C7 | 搜索配置、标签搜索、高级搜索：`SearchService` 的 Web 分支 | `lib/services/search_service.dart:26`、`:105`、`:189` |
| C8 | 弹弹play账号接口：`dandanplay_service_stub.dart` | login_status `:211`；login `:633`；logout `:303`；refresh_login `:837`；bangumi/oauth_login `:744`；webtoken `:2656`；play_history `:1345`；favorites `:1739`；send_danmaku `:2046`；add_play_history `:1454`；add_favorite `:1836`；remove_favorite `:1920` |
| C9 | `/media/local/items`：Web 媒体集合 | `lib/media_library/adaptive_media_collection_view.dart:746` |
| C10 | `/history`：Web 历史加载；`/history/progress`：Web 播放同步 | GET：`lib/services/web_remote_access_service.dart:203`，上层消费者 `lib/providers/watch_history_provider.dart:106`；POST：`lib/services/web_remote_history_sync_service.dart:64`，且 `:28` 明确限制 `kIsWeb` |
| C11 | `/web_proxy`：Web 上游请求、图片探测、跨共享实例播放 | URL 统一生成于 `lib/services/web_remote_access_service.dart:157`；全部具体入口见第 3.4 节 |
| C12 | share/animes、share/animes/id、share/stream：共享库 provider，Web 和原生均使用 | 列表 `lib/providers/shared_remote_library_provider.dart:323`；详情 `:492`；消费服务端 `streamPath` 并生成播放 URL `:743`；服务端生成流路径 `lib/services/local_media_share_service.dart:54` |
| C13 | share 字幕、音轨、字体；manage 字幕；媒体流探测 | 路径派生 `lib/services/remote_subtitle_service.dart:879`；manage/subtitles `:915`，GET `:941`；manage/subtitle `:997`；share/subtitles GET `:1064`；share/subtitle URL `:1112`，下载 GET `:1922`；share/audio GET `:1172`，audio_file URL `:1231`、GET `:1403`；share/fonts GET `:1290`，font URL `:1349`、GET `:1464`；通用媒体 HEAD/GET `lib/utils/remote_media_fetcher.dart:91`、`:114` |
| C14 | share/progress、share/thumbnail：原生共享播放同步 | `lib/services/shared_remote_playback_sync_service.dart:31`、`:69`、`:149`；动作 URL 从播放 URL 派生 `:184`。该文件读取本地缩略图文件 `:120`，应与 Web 专用 C10 区分 |
| C15 | 全部 manage 管理接口：共享库 provider，Web 和原生均使用 | folders GET `lib/providers/shared_remote_library_provider.dart:903`、POST `:1755`、DELETE `:1837`；browse `:1074`；stream URL `:1709`；scan/status `:1012`；scan/rescan `:1906`；webdav POST `:1986`、DELETE `:2016`、list `:1210`、test 两种参数形式 `:1320`、`:1329`、scan `:1394`；smb POST `:2048`、DELETE `:2078`、list `:1488`、test `:1586`、scan `:1646` |
| C16 | settings/network：各 provider 的 Web 配置同步 | Jellyfin GET `lib/providers/jellyfin_provider.dart:193`，POST 连接 `:315`、选库 `:362`；Emby GET `lib/providers/emby_provider.dart:160`，POST `:282`、`:329`；弹弹play远程库 GET `lib/providers/dandanplay_remote_provider.dart:66`，POST 连接 `:101`、断开 `:142` |
| C17 | remote/control：`RemoteControlClientService` | state GET `lib/services/remote_control_client_service.dart:149`、`:157`；command POST `:191`。附带客户端声明头 `:269` |
| C18 | remote/input：扫码后的 NipaPlay 输入客户端、服务端生成的浏览器表单 | 生成 URL `lib/services/remote_text_input_service.dart:343`；客户端解析 `:380`、元数据 GET `:408`、提交 POST `:441`；HTML 表单 POST `:635` |

`DandanplayService` 使用条件导出，浏览器走 stub，原生走 IO 实现。不能把 IO 文件中的 `/api/v2/...` 上游请求计作宿主 `/api` 的直接调用。证据：`lib/services/dandanplay_service.dart:1`。

### 3.3 图片代理的全部助手调用点

除 C6 的 URL 生成位置，生产代码中的图片助手调用点为：

- `lib/models/shared_remote_library.dart:104`。
- `lib/providers/watch_history_provider.dart:116`。
- `lib/controllers/user_activity_controller.dart:229`。
- `lib/themes/nipaplay/widgets/anime_card.dart:95`。
- `lib/themes/nipaplay/widgets/tag_search_widget.dart:1434`。
- `lib/themes/cupertino/widgets/cupertino_tag_search_view.dart:408`。
- `lib/themes/nipaplay/widgets/bangumi_comments_widget.dart:263`。
- `lib/themes/nipaplay/widgets/large_screen_anime_detail_page.dart:147`。
- `lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:665`。
- `lib/pages/anime_detail_page.dart:1370`、`:2591`、`:2618`。

`imageProxyUrl` 明确把本地路径和普通网络图片都送入代理，跳过 `data:`、`blob:`。共享库 provider 对非网络封面也生成远端图片代理 URL。因此立即禁止所有本地图片会破坏缩略图和封面显示。证据：`lib/services/web_remote_access_service.dart:179`、`lib/providers/shared_remote_library_provider.dart:464`。

### 3.4 通用代理的全部助手调用点

`WebRemoteAccessService.proxyUri` 仅在 `kIsWeb` 下改写 HTTP/HTTPS URL；原生返回原 URL。证据：`lib/services/web_remote_access_service.dart:157`。

| 业务 | 调用点及方法 |
|---|---|
| Bangumi 账号、收藏与公开信息 | `lib/services/bangumi_api_service.dart:193`、`:234`、`:329`、`:733`、`:778`、`:870`、`:923`。通用方法分发 `:353`；实际业务有 POST `:498`、`:541`、`:837`，PUT `:593`，PATCH `:646`；DELETE 只有分发分支 `:369` |
| Bangumi 来源页面请求 | `lib/services/bangumi_service.dart:187`，GET |
| 弹弹play Web 搜索与匹配相关上游 | `lib/services/dandanplay_service_stub.dart:2366`；`lib/services/danmaku_matching_service.dart:86`；对应 IO 文件也使用助手 `lib/services/dandanplay_service_io.dart:1379`、`:1677`，但原生不改写 |
| 热门番组 | `lib/services/trending_bangumi_service.dart:173`，GET |
| 标签搜索中的上游请求 | `lib/services/search_service.dart:296`，GET |
| 跳过片头所需数据 | `lib/services/intro_skip/skip_id_resolver.dart:277`，POST；`lib/services/intro_skip/aniskip_service.dart:143`，GET；`lib/utils/video_player_state/video_player_state_intro_skip.dart:417`，GET |
| AI 防剧透 | `lib/services/danmaku_spoiler_filter_service.dart:65`、`:125`，POST，支持配置的 API 地址与调用方提供的 API key |
| 翻译 | `lib/themes/nipaplay/widgets/translation_button.dart:53`，POST |
| 日志上传 | `lib/services/log_share_service.dart:64`，POST |
| 更新检查 | `lib/services/update_service.dart:47`，GET |
| 媒体服务器图片 | `lib/services/media_server_image_loader.dart:57`、`:62`，GET |
| 首页图片与媒体封面 | `lib/themes/nipaplay/widgets/dashboard_home_page_data_loading.dart:663`；`lib/themes/nipaplay/widgets/dashboard_home_page_image_helpers.dart:117`、`:543`，HEAD |
| Jellyfin / Emby 字幕请求 | `lib/services/jellyfin_service.dart:1705`；`lib/services/emby_service.dart:2034` |
| Web 播放其他共享实例 | `lib/providers/shared_remote_library_provider.dart:753`，消费共享媒体流 |

这里存在自定义 AI 地址、媒体服务器地址和其他实例地址。固定为几个公共域名的代理白名单不能覆盖当前调用契约。

### 3.5 二维码和 LAN 发现

**远程访问二维码目前只是地址载体。** 内容为 URL，或包含 `type`、`baseUrl`、候选地址和名称的 JSON；没有设备公钥、密码或配对凭据。扫码后调用 `/api/info` 判断返回的 `app` 和 `success`。证据：`lib/services/remote_access_qr_service.dart:70`、`:94`、`:167`。

**LAN 发现不是 HTTP 路由。** 使用 UDP `32123`，请求包含固定 `type` 和版本；回应包含主机名、系统、Web 端口。回应解析使用 datagram 的源地址，没有签名或挑战绑定。证据：`lib/services/nipaplay_lan_discovery.dart:6`、`:28`、`:35`、`:50`、`:92`。

发现后的 HTTP 验证点是 C1：

- 遥控客户端 UDP 发现后检查 `/api/info` 的接收端开关：`lib/services/remote_control_client_service.dart:295`、`:313`。
- 共享库扫描验证 `/api/info`：`lib/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart:352`。

**结论：自动发现和扫码连接都不能作为设备已可信的证据。** 返回特定 JSON 只能说明对方声称自己是 NipaPlay。

### 3.6 无调用方路由与客户端/服务端不一致

生产代码中未发现以下接口的调用：

- `/api/media/libraries`。
- `/api/media/local/item/<animeId>`。
- `/api/media/local/share/history`。
- `/api/web_proxy` 的实际 DELETE 业务调用；客户端保留通用 DELETE 分发能力。
- share 字幕、音轨、字体文件及 manage 字幕的专用 HEAD 请求；路由仍实际可达。

此外，Web stub 调用两个**未注册接口**：

| 客户端请求 | 调用证据 | 服务端结论 |
|---|---|---|
| POST `/api/dandanplay/register` | `lib/services/dandanplay_service_stub.dart:1040` | `lib/services/web_api_service.dart:60` 的账号路由没有 register |
| POST `/api/dandanplay/episodes/watch_status` | `lib/services/dandanplay_service_stub.dart:1130` | 同一路由表没有 episodes/watch_status |

不能为了“清理无人调用接口”直接删除上述服务器路由；本次只确认仓库内部调用关系，未确认旧版本和外部用户。

## 4. 现有信任机制

### 4.1 遥控审批的真实边界

`RemoteControlAccessGuardService` 的身份来源是客户端自报的 ID、名称、平台，加上解析得到的 IP。身份键优先为 `id:<clientId>`，没有 ID 时使用 `ip:<remoteIp>`。没有签名、challenge 或请求 token。证据：`lib/services/remote_control_access_guard_service.dart:62`、`:267`、`:275`。

批准记录和受信任记录的行为：

- 受信任设备命中即授权。
- 本进程已批准身份命中即授权。
- 已批准记录更新访问时间，但 `evaluate` 没有检查过期。
- 拒绝冷却为八秒。
- 批准/信任通过本机对话框完成。
- 信任列表持久化到 SharedPreferences。

证据：`lib/services/remote_control_access_guard_service.dart:66`、`:80`、`:90`、`:113`、`:137`、`:170`；`lib/services/remote_control_settings.dart:90`。

删除信任设备只删除 `_trustedDevices` 和持久化记录，没有删除 `_approvedClients`。因此已在当前进程获得批准的身份在移除信任后仍可能被授权。证据：`lib/services/remote_control_access_guard_service.dart:196`、`:90`。

覆盖范围：

- `/remote/control/command`：未授权返回 403。
- `/remote/control/state`：无论授权状态如何，仍构造并返回播放器状态；授权结果仅附在 payload 中。
- 接收端开关在 bridge 执行命令时检查。
- 媒体、账号、代理、网络设置没有复用该 guard。

证据：`lib/services/remote_control_api_service.dart:35`、`:101`；`lib/services/player_remote_control_bridge.dart:91`；全部路由见第 2 节。

`RemoteControlAuthManager` 是另一套名称/IP 列表实现，但本次未发现生产代码对该类的调用，不能把它算作 HTTP 防护。其按 IP 判断信任的实现位于 `lib/services/remote_control_auth_manager.dart:114`。

### 4.2 WebRemoteAccessGate 只是连接门

Web gate 调用 `/api/info` 探测成功后保存 base URL、刷新弹弹play宿主信息、挂载共享库，并显示应用。没有输入 NipaPlay 密码、配对码或交换会话 token。证据：`lib/themes/nipaplay/widgets/web_remote_access_gate.dart:92`、`:139`、`:150`、`:167`；`lib/services/web_remote_access_service.dart:115`。

绕过页面不会改变服务器行为：服务端没有依赖 gate 的鉴权中间件。证据：`lib/services/web_server_service.dart:399`。

### 4.3 密码、token 和 Basic Auth

| 名称 | 实际用途 | 是否保护当前 NipaPlay API |
|---|---|---|
| 遥控客户端 ID | SharedPreferences 保存的时间戳加随机数标识；作为请求头自报 | **否**，不是秘密或私钥证明。`lib/services/remote_control_settings.dart:63`、`lib/services/remote_control_client_service.dart:269` |
| 弹弹play账号 token | 宿主调用弹弹play上游、HTTP 客户端注入账号授权 | **否**，是上游凭据。`lib/services/dandanplay_http_client.dart:25`、`:61` |
| 弹弹play WebToken | 为 `business` 获取账号业务临时凭据，包括注销入口 | **否**。`lib/services/web_api_service.dart:446`、`lib/services/dandanplay_service_io.dart:2660`、`:2782` |
| Jellyfin/Emby 密码和 access token | 媒体服务器连接凭据 | **否**。配置写入调用连接方法：`lib/services/network_media_settings_api.dart:61`、`:107` |
| settings/network/dandanplay 的 token | 弹弹play远程媒体库连接凭据 | **否**，不是 NipaPlay Mesh 身份，也不是官方网关账号 token 配置入口。`lib/services/network_media_settings_api.dart:144`、`lib/services/dandanplay_remote_service.dart:24` |
| 远程输入 key | 18 个安全随机字节编码，默认十分钟寿命，一次提交 | **只保护该输入会话**。`lib/services/remote_text_input_service.dart:249`、`:353`、`:494` |
| URL userInfo 的 Basic Auth | 共享库 provider、共享同步与字幕客户端从 `user:password@host` 构造 Authorization | **服务器本身不验证**；可供外部反向代理验证。`lib/providers/shared_remote_library_provider.dart:658`、`lib/services/shared_remote_playback_sync_service.dart:240`、`lib/services/remote_subtitle_service.dart:912` |

宿主没有统一密码/Bearer/Basic 校验，服务器 pipeline 只有 CORS、请求日志和业务分发。证据：`lib/services/web_server_service.dart:399`。

反向代理若部署 Basic Auth，能保护经过它的请求；直接访问仍监听所有网卡的 1180 端口可绕过这层。后者是基于部署拓扑的攻击推导，前提是端口仍可达。源码不能证明用户已部署反向代理或防火墙。

`Documentation/remote-access.md:8` 建议设置强随机口令，但上述实现没有对应的全局密码机制；该文档建议不能作为现有认证能力的证据。

### 4.4 CORS 的实际行为

服务端使用没有参数的 `corsHeaders()`：`lib/services/web_server_service.dart:400`。锁定版本为 `0.1.5`：`pubspec.lock:1487`。

读取对应依赖源码后确认：

- 默认 Origin checker 允许全部来源。
- 默认 `Access-Control-Allow-Credentials: true`。
- 将请求 Origin 原样作为 Allow-Origin。
- 有 Origin 的 OPTIONS 请求直接返回 200，不进入路由。
- 默认允许 Authorization 和 Content-Type。
- 默认方法列表未列 HEAD。
- 响应自身 header 会覆盖中间件生成的同名 header。
- 默认回显分支没有设置 `Vary: Origin`。

证据：`~/.pub-cache/hosted/pub.dev/shelf_cors_headers-0.1.5/lib/src/shelf_cors_headers_base.dart:13`、`:23`、`:32`、`:45`、`:50`、`:77`、`:80`、`:86`。

因此“任意 Origin 回显并允许凭据”对普通 API 成立；但不能说所有响应都采用该值：

- `image_proxy` 成功响应显式设置 `Access-Control-Allow-Origin: *`，会覆盖回显。
- `web_proxy` 原样保留上游多数响应头，上游 CORS 也可能覆盖宿主 CORS。

证据：`lib/services/web_api_service.dart:194`、`:234`；`lib/services/web_ui_proxy_api.dart:55`。

## 5. 漏洞与利用条件

本节场景均为**代码可推导路径，未运行时复现**。严重度是设计优先级建议。

### 5.1 任意 Origin 的跨站访问：高

**前置条件：** 受害者浏览器能访问宿主，浏览器的混合内容、私网访问策略等没有阻止请求。

**场景：** 用户打开恶意网站，该网站对宿主 `/api/history`、`/api/dandanplay/webtoken` 发起读取，或预检后提交管理和账号操作。服务器回显来源并允许凭据，未鉴权 API 本身也不要求凭据。

**证据：** 第 4.4 节依赖源码；`lib/services/web_api_service.dart:446`、`:718`、`:751`。

**边界：** 没有运行浏览器验证，因此不能断言所有浏览器版本、HTTPS 页面到 HTTP 私网的组合都可利用。局域网原生客户端直接访问无需依赖 CORS。

### 5.2 `/web_proxy` SSRF：极高

**前置条件：** 服务可达，宿主可连接目标地址。

**场景：** 攻击者指定 `url=http://127.0.0.1:<port>/...`、其他局域网主机或宿主才能访问的 HTTP 服务，读取其响应，或用 POST/PUT/PATCH/DELETE 操作上游。

**代码事实：**

- `url` 或 `x-proxy-url` 控制目标。
- 只检查绝对 URI 和 HTTP/HTTPS scheme。
- 没有地址、端口、DNS、资源范围或调用者身份检查。
- 转发请求方法、请求体及大部分请求头。
- 返回上游状态、响应头和响应流。

证据：`lib/services/web_ui_proxy_api.dart:22`、`:29`、`:36`、`:39`、`:48`、`:55`、`:78`。

**边界：** 这是 HTTP SSRF，不能从现有 scheme 检查推导为任意 TCP 协议代理；也不能直接推导为读任意本地文件。

### 5.3 宿主弹弹play凭据代理与泄露：极高

#### 直接目标的实际策略

内置弹弹play域名、官方网关和明确选中的 custom 网关会获得宿主账号 Authorization；无关直接目标不会无条件获得该 token。证据：

- `lib/services/dandanplay_http_client.dart:61`、`:74`。
- `lib/utils/network_settings.dart:52`、`:69`、`:78`。

但未鉴权调用者仍能借代理使用宿主账号访问这些上游。是否能完成某项写操作，还取决于对应上游接口的签名、参数和业务检查；不能只凭 token 注入断言每个上游写接口都可调用。

#### 外层 URL 与内层目标不一致的泄露路径

**前置条件：** 宿主已持有账号 token；攻击者有一个可接收请求的 HTTP/HTTPS 服务器。

**场景结构：**

```text
宿主 /api/web_proxy
  url = https://攻击者站点/api/web_proxy
          ?url=https://api.dandanplay.net/某路径
```

`WebUiProxyApi` 创建指向攻击者站点的请求；`DandanplayHttpClient.targetUri` 仅根据路径递归展开到弹弹play站点；随后将宿主 Authorization 写入原请求，并仍向攻击者站点发送。

证据：`lib/services/web_ui_proxy_api.dart:36`；`lib/services/dandanplay_http_client.dart:30`、`:59`、`:72`、`:91`。

这条路径不需要攻击者控制弹弹play域名，也不需要修改宿主 custom 网关设置。`image_proxy` 网络分支使用同一个 HTTP 客户端，也具有相同的目标判定问题。证据：`lib/services/web_api_service.dart:187`。

### 5.4 `/image_proxy` 本地图片泄露与网络 SSRF：高

**前置条件：** 服务可达；已知或猜中宿主可读路径。

**场景：** 请求宿主媒体目录以外的 `.jpg`、`.png` 等文件，获取私人图片、截图。路径只做扩展名检查，没有共享根或资源登记检查。

证据：`lib/services/web_api_service.dart:178`、`:200`、`:210`、`:222`。

**正确边界：**

- 不能直接用该本地分支读取 `.txt`、`.sqlite`、私钥等非图片扩展名文件。
- 扩展名不是内容验证。若宿主上已有图片扩展名的符号链接指向敏感文件，代码会沿该路径读取；这是条件性推导，需要已有链接或额外写盘能力。
- 网络分支不检查图片类型，直接返回响应字节和上游 Content-Type，也可用于 HTTP SSRF。

网络证据：`lib/services/web_api_service.dart:185`。

### 5.5 未鉴权 folders 扩大共享范围：极高

**前置条件：** 服务可达；宿主进程对目标目录有操作系统读取权限。

**场景：** POST `/api/media/local/manage/folders` 提交 `{"path":"/","scan":false}`，或其他敏感目录，然后调用 browse、stream、subtitle。

证据：

- handler 接受任意非空路径：`lib/services/local_media_management_api.dart:616`。
- `scan=false` 调用 `addScannedFolder`：同文件 `:641`。
- service 只检查非空和重复，然后持久化：`lib/services/scan_service.dart:1006`。
- 路径允许范围直接取 `scannedFolders`：`lib/services/local_media_management_api.dart:1078`。

**正确边界：** manage/stream 仍检查媒体扩展名，因此此链本身不是“不受扩展名限制的任意文件读取”。browse 也过滤文件类型；subtitle 对名称和字幕扩展名有检查。证据：`lib/services/local_media_management_api.dart:706`、`:760`、`:1187`。

路径边界采用字符串规范化和 `isWithin`，没有真实路径校验。若共享树内存在逃逸符号链接，可能读取树外内容；需要已有链接。证据：同文件 `:1078`、`:766`。

### 5.6 历史写入到共享流的任意文件读取链：极高

**前置条件：** 服务可达；已知目标本地文件路径；宿主进程可读该文件。

**场景：**

1. POST `/api/history/progress`，指定目标 `filePath` 和一个非空数值 `animeId`。
2. handler 在没有已有历史时创建历史并保存。
3. 共享服务监听历史变化，把所有带 `animeId` 的记录加入 shareId 映射。
4. 获取该动画详情中的流路径，或按照规范化路径 SHA-1 计算 shareId。
5. GET 对应 share stream。

**证据链：**

- 接受路径和 animeId：`lib/services/web_api_service.dart:762`、`:794`。
- 新建并保存历史：同文件 `:853`、`:876`。
- 监听历史：`lib/services/local_media_share_service.dart:132`。
- 带 animeId 即入映射：同文件 `:156`、`:161`。
- shareId 为规范化路径 SHA-1：同文件 `:186`。
- stream 直接打开历史路径，无扩展名/共享根检查：同文件 `:409`。

**结论：** `shareId` 是资源索引，不是秘密能力 token。只加长或随机化 shareId 不能修复可由未授权用户建立资源映射的问题。

### 5.7 `/dandanplay/webtoken` 泄露业务凭据：极高

**前置条件：** 宿主已登录；上游接受指定 business。

**场景：** 无鉴权请求 `business=deleteAccount`，服务器用宿主 token 请求上游 WebToken 并原样返回。宿主代码随后将此 token 放入注销页面 URL。

证据：`lib/services/web_api_service.dart:446`；`lib/services/dandanplay_service_io.dart:2660`、`:2689`、`:2782`、`:2795`。

**边界：** 已确认泄露的是业务 WebToken，不能将其等同于长期账号 token；是否无需其他确认即可删除账号，需要核验上游行为。本仓库只证明它能打开注销流程入口。

普通 login_status 没有返回长期 token，登录成功返回值也没有长期 token。证据：`lib/services/web_api_service.dart:336`；`lib/services/dandanplay_service_io.dart:740`。

### 5.8 settings/network 未授权写入：高

**前置条件：** 服务可达；连接类操作若要求成功，需要目标服务器可达。

**场景：**

- 更改 Jellyfin/Emby 选库。
- 让宿主连接攻击者指定的媒体服务器，改变原有媒体配置。
- 断开弹弹play远程媒体库。
- 利用连接过程发起宿主侧网络访问。

证据：`lib/services/network_media_settings_api.dart:49`、`:69`、`:95`、`:114`、`:139`、`:148`。

**纠正：** `/settings/network/dandanplay` 修改的是 `DandanplayRemoteService` 的远程库地址/token，不是 `NetworkSettings` 的弹弹play官方网关/custom 网关选择。因此不能把这一写入直接接到“更换 token 注入网关”的利用链。证据：同文件 `:142`；`lib/utils/network_settings.dart:69`。

### 5.9 WebDAV/SMB 凭据泄露及宿主代理访问：极高

**前置条件：** 宿主已保存相关连接。

**场景：** GET manage/folders，获得连接 JSON 中的用户名、密码、地址；或无需知道密码，通过 list/test/scan 使用宿主已保存的连接。

证据：

- 返回 `toJson()`：`lib/services/local_media_management_api.dart:108`。
- WebDAV JSON 包含 password：`lib/services/webdav_service.dart:35`。
- SMB JSON 包含 password：`lib/services/smb_service.dart:54`。
- 用连接访问目录：`lib/services/local_media_management_api.dart:166`、`:172`、`:340`。
- 客户端确实解析这些连接，并在 Web 下登记远端 WebDAV 连接：`lib/providers/shared_remote_library_provider.dart:953`、`:965`、`:976`。

立即删除 password 字段不能被认定为零兼容影响；需要同步调整客户端的编辑、连接和播放路径。

### 5.10 X-Forwarded-For 和客户端 ID 冒充：高

**前置条件：** 目标身份已获批准或信任；攻击者知道对应 IP 或客户端 ID。

**场景：**

- 对没有 clientId 的身份，发送伪造 `X-Forwarded-For`，使身份键变为已批准的 `ip:...`。
- 发送已批准 ID 的 `X-NipaPlay-Remote-Client-Id`，直接命中 `id:...`，不需要伪造 IP。

证据：`lib/services/remote_control_access_guard_service.dart:275`、`:301`、`:80`、`:90`。

解析 IP 优先信任 XFF，甚至在存在真实 socket 连接信息时也如此；没有可信反向代理配置。`X-Real-IP` 也有后备分支。证据：同文件 `:302`、`:310`、`:329`。

只修 XFF 能消除 IP 冒充路径，不能解决自报 ID 冒充。

### 5.11 DNS rebinding：高，浏览器条件待验证

**前置条件：** 用户打开攻击者控制的 HTTP 域名页面；攻击者能改变其 DNS 指向宿主地址；浏览器和网络策略允许连接目标端口。

**场景推导：** 攻击者先向自己的站点提供脚本，再使同一域名解析到局域网 NipaPlay。服务器没有 Host allowlist，API 不检查身份，即使未来仅检查 Origin 是否等于 Host，也可能把攻击者域名视为“同源”。

证据：HTTP 分发不检查 Host，`lib/services/web_server_service.dart:375`；监听全部地址 `:422`；API 路由无统一认证 `lib/services/web_api_service.dart:38`。

服务器还把 `requestedUri.origin` 用作首页重定向的 `api` 参数，不应把该请求值视为预先批准的服务地址。证据：`lib/services/web_server_service.dart:113`。

本次没有验证浏览器 DNS 缓存、私网访问拦截或端口扫描条件，所以记录为**代码支持的攻击面与条件性推导**。

### 5.12 Torrent 流接口：回环接口可经 SSRF 暴露

**代码事实：**

- Torrent 流服务不是 `/api` 子路由。
- Rust 绑定 `127.0.0.1` 的随机端口。
- URL 为 `/torrent/<id>/stream/<file_id>/<filename>`。
- 只允许 GET/HEAD，但没有凭据或 Host/Origin 校验。
- 路径解析使用数字 torrent/file ID，后面的 filename 不参与资源身份校验。
- 每个连接创建线程。

证据：`rust/src/api/torrent.rs:386`、`:478`、`:488`、`:512`、`:671`。

合法调用者为 `TorrentDownloadService` 的本机未完成文件播放：`lib/services/torrent_download_service.dart:247`、`:271`。

**场景：** Torrent 流服务已启动，攻击者通过 `/web_proxy` 或 `image_proxy` 网络分支访问该回环端口并读取任务文件。需要知道或探测随机端口和有效 ID。

**边界：** 没有证据表明 Torrent 原生流监听 0.0.0.0，也没有证据表明 1180 API 暴露新增/删除 Torrent 的 REST 接口。主要问题是回环信任被 SSRF 穿透；本机恶意进程则本来能连接回环服务。

### 5.13 其他需要纳入修复的行为

- **信任撤销不立即生效：** 第 4.1 节的 `_approvedClients` 残留。
- **敏感日志：** 获取 WebToken、注销 URL 的日志包含完整返回数据或 token。证据：`lib/services/dandanplay_service_io.dart:2694`、`:2698`、`:2784`、`:2788`、`:2799`。
- **请求日志泄露查询参数：** server 启用 `logRequests()`；代理 URL、远程输入 key 和业务参数可能出现在 URI 日志中。证据：`lib/services/web_server_service.dart:401`；静态回退也记录完整 URI，`:297`。
- **资源消耗：** web_proxy 完整缓冲请求体，image_proxy 完整读取文件/上游响应，缩略图解码并写盘。没有在这些入口看到统一体积限制。证据：`lib/services/web_ui_proxy_api.dart:40`、`lib/services/web_api_service.dart:222`、`lib/services/local_media_share_api.dart:422`。
- **缩略图覆盖：** 共享缩略图写入优先复用历史记录已有 thumbnailPath；该路径检查只排除空值和 HTTP URL。攻击者不能通过 thumbnail 请求直接指定路径，但可覆盖已登记的缩略图文件。证据：`lib/services/local_media_share_service.dart:996`、`:1005`、`:1025`、`:1049`。

## 6. A 档：可以立即上线的兼容修复

### 6.1 A 档的边界

A 档保持现有路由、字段、无会话旧客户端和独立部署 Web UI 的访问能力。不能声称在此前提下已经解决任意局域网调用者的问题。

尤其不能通过下列操作冒充“兼容修复”：

- 给全部旧路由直接加新密码或 token。
- 只允许同源 Origin。
- 禁止所有私网、回环或非官方目标。
- 禁止所有本地图片。
- 删除 WebDAV/SMB 密码字段而不迁移客户端。
- 要求所有 JSON 请求必须使用 `application/json`。

最后一项会影响现有 Web 配置写入：Jellyfin、Emby、弹弹play远程库的若干 POST 仅传入 JSON 字符串，没有显式 Content-Type。证据：`lib/providers/jellyfin_provider.dart:314`、`lib/providers/emby_provider.dart:281`、`lib/providers/dandanplay_remote_provider.dart:100`。

### 6.2 立即实施项

以下均为**建议行为，尚未实现**。

| 项目 | 修改位置与目标行为 | 兼容性依据与限度 |
|---|---|---|
| A1：修复 token 外层 URL 泄露 | 修改 `lib/services/dandanplay_http_client.dart:30`、`:59`。原生请求按**实际出站 request.url** 判断凭据接收方，不展开 URL 中的代理路径。Web 端如需识别内层服务，只允许识别当前配置宿主的精确 Origin 与已知代理路径；该识别只能决定“交给宿主代理”，不能给任意外层站点附宿主 token | 合法 Web 包装由 `WebRemoteAccessService.proxyUri` 生成；宿主代理处理时 request.url 已经是实际上游。直接官方网关和明确 custom 网关仍获得账号授权。证据：`lib/services/web_remote_access_service.dart:170`、`lib/services/web_ui_proxy_api.dart:36`。不删路径、不改响应契约 |
| A2：修复客户端 Origin 比较 | 修改 `lib/services/web_remote_access_service.dart:165`，把字符串 `startsWith(base)` 改成解析后比较 scheme、host、有效 port，并按配置 base path 判断。禁止把 `host` 的文本前缀当成同一站点 | 原有同宿主请求保持直连；真正跨实例请求仍包装代理。证据：同文件 `:157`；跨实例消费者 `lib/providers/shared_remote_library_provider.dart:750` |
| A3：让移除信任立即生效 | 修改 `lib/services/remote_control_access_guard_service.dart:196`：同时清除该 key 的 approved、denied；给 pending 审批增加取消/代次标记，避免已撤销后的旧弹窗结果重新授权 | 不影响正常 state/command 请求；改变的是“撤销”本应具有的行为。现有批准逻辑证据：同文件 `:137`、`:143` |
| A4：修复 HEAD 遮蔽 | 在 `lib/services/local_media_share_api.dart:14`、`lib/services/local_media_management_api.dart:65` 中先注册显式 HEAD，再注册 GET；确保 HEAD 使用现有 `headOnly: true` 路径。`web_proxy` 若保留共用 handle，也应明确方法注册和测试顺序 | RemoteMediaFetcher 的 HEAD 仍返回长度、类型、Range 信息；GET 播放不变。证据：`lib/utils/remote_media_fetcher.dart:91`、`lib/services/local_media_share_api.dart:116`。消除 HEAD 创建完整 GET 响应的额外工作 |
| A5：敏感日志与缓存 | 修改 `lib/services/web_server_service.dart:401`、`:297`，只记录路由模板、方法、状态、耗时，不记录代理目标查询、输入 key 或凭据；删除 IO/stub 账号流程中的 token、完整 WebToken 响应和注销 URL 日志。账号状态、WebToken、网络配置、输入会话响应统一 `Cache-Control: no-store`；输入页加 `Referrer-Policy: no-referrer` | 不改变正文、方法或认证形式；第 3 节调用者读取正文，不依赖敏感日志。WebToken 现有消费者仍能获得返回值 |
| A6：修正 CORS 响应一致性与缓存 | 在 `lib/services/web_server_service.dart:399` 统一管理下游 CORS，合并 `Vary: Origin`，保留现有来源兼容性；代理上游的 `Access-Control-*` 不作为宿主策略。去掉 image_proxy 内部 `*`，由统一层产生响应。显式支持实际 HEAD 和所需预检头 | 独立 Web UI、原生请求、Basic Authorization 和媒体 HEAD 均保留；不在本阶段突然限制 Origin 或移除凭据支持。证据：第 3 节及 `lib/services/web_api_service.dart:194`、`lib/services/web_ui_proxy_api.dart:55`。此项修复一致性，**不解决任意 Origin 授权** |
| A7：新增可选安全配置与兼容观测 | 在 server/provider 设置层新增手动配置的监听地址、公开 Host、可信代理和浏览器 Origin 规则；升级旧安装默认保留现有行为。新增不含秘密的请求来源统计、旧协议使用计数、协议能力字段 | 不默认拒绝旧调用；为 B 迁移提供证据。设置持久化入口 `lib/services/web_server_service.dart:301`、`:320`；能力探测入口 `lib/services/web_api_service.dart:92` |

A1 的凭据策略必须对 `image_proxy` 网络路径同时生效；不能只在 WebUiProxyApi 中拒绝某一种嵌套 URL。

### 6.3 需兼容验证后才能默认开启的项目

以下适合立刻开发，但不能仅凭本次阅读保证“任何现有用户配置均不受影响”：

1. **XFF 改为只信任指定代理。** 修改 `lib/services/remote_control_access_guard_service.dart:301`，默认依据真实 socket peer；仅当 peer 命中本地配置的代理时解析 XFF，并从可信链边界取客户端地址。C17 原生客户端不依赖 XFF，但旧代理后的 IP-only 授权可能改变，因此必须迁移旧 IP 授权或要求一次重新确认。

2. **代理请求头和响应头隔离。** 修改 `lib/services/web_ui_proxy_api.dart:78`、`:55`。目标是不给上游发送宿主 cookie、Mesh token、身份声明和代理认证信息，不允许上游 Set-Cookie 改写宿主会话。不能简单删除所有 Authorization：Bangumi、AI 和媒体上游已有合法授权头，见第 3.4 节。应先引入独立的宿主认证载体与明确的上游授权字段，再做彻底隔离。

3. **体积、并发和超时限制。** 修改 web_proxy body 缓冲、image_proxy 读取、thumbnail 解码、输入 body 流读取。限制应按路由设置，媒体流保持流式传输和 Range。当前客户端没有统一大小上限，不能凭代码断言某个硬编码上限不影响所有合法图片、截图、日志和 AI 请求。证据：`lib/services/web_ui_proxy_api.dart:40`、`lib/services/local_media_share_api.dart:422`、`lib/services/remote_text_input_service.dart:500`。

4. **真实路径与媒体类型边界。** manage 路径应检查 canonical root 与 canonical target，阻断符号链接逃逸；share stream 应拒绝由非媒体历史记录产生的资源。但已有符号链接媒体库、无扩展名资源和特殊格式需要回归验证，不能将新格式白名单直接称为零兼容变化。现有路径检查证据：`lib/services/local_media_management_api.dart:1078`；无类型共享流证据：`lib/services/local_media_share_service.dart:409`。

5. **本地图片改为资源登记。** 可先为宿主已返回的封面、历史缩略图建立资源索引并双轨支持；强制拒绝未登记本地路径应与 B 的身份授权一同启用。现有任意本地路径助手契约见 `lib/services/web_remote_access_service.dart:192`。

### 6.4 A 档验收清单

以下是后续实施必须新增或执行的验证，不是本次已通过的测试：

- 伪装为攻击者 `/api/web_proxy`、`/api/image_proxy` 的外层 URL 不获得宿主 token；真实官方与 custom 网关保持正常。
- 同源 Web、独立来源 Web、多个共享实例、含 userInfo 的反向代理地址分别回归。
- GET/HEAD/Range 播放、字幕、音轨、字体保持正常。
- 撤销信任后立即不能执行命令，未完成弹窗不能重新恢复授权。
- CORS 响应不能被上游头覆盖；缓存按 Origin 区分。
- 所有日志不含账号 token、WebToken、输入 key。
- 保持当前未鉴权调用方式的同时，准确报告仍未解决的风险。

现有 `test/web_ui_proxy_api_test.dart:8` 只验证 Accept-Encoding 转发回归，不覆盖以上安全属性。

## 7. B 档：设备身份、配对与授权协议

本节全部为**协议草案**。当前源码没有实现这些 endpoint、密钥或会话。

### 7.1 身份与信任存储

每个原生 NipaPlay 实例生成一对 Ed25519 长期身份密钥：

```text
device_id = base64url(SHA-256(Ed25519 public key))
```

建议规则：

- 私钥放操作系统安全存储；不得放入普通备份、日志或发现广播。
- 信任记录以公钥/device_id 为键，保存用户授予的权限、资源范围、信任时间和撤销代次。
- 名称、平台、IP、端口是可变展示/定位字段，不参与身份认证。
- 安装克隆、恢复、换机须明确“恢复原身份”或“生成新身份”，避免多个运行实例共享同一私钥。
- Ed25519 用于签名。需要密钥交换时使用独立临时 X25519 密钥或成熟 TLS 实现，不自行把 Ed25519 当作 ECDH 密钥使用。

设计动因是当前自报 ID 和 IP 不是持有秘密的证明：`lib/services/remote_control_access_guard_service.dart:267`；现有 ID 生成：`lib/services/remote_control_settings.dart:63`。

### 7.2 发现只提供线索

保留 UDP 发现兼容格式，扩展协议版本、device_id、公钥指纹、可用安全 endpoint、pairing 状态和 capability 摘要。

新客户端发现流程：

1. 接收候选地址。
2. 对已配对设备验证连接上的公钥证明。
3. 对未配对设备只展示“未验证设备”，不自动获取媒体凭据或执行命令。
4. 对响应加入扫描 nonce 与签名，降低旧响应重放；签名只能证明持有该公钥，不能自动赋予信任。

现有 discovery 没有 nonce/签名，二维码也只含地址，见 `lib/services/nipaplay_lan_discovery.dart:28`、`lib/services/remote_access_qr_service.dart:94`。

### 7.3 配对：二维码

建议由接收端本机 UI 显式开启两分钟配对窗口，生成：

```text
version
pairing_id
host_device_id
host_public_key / fingerprint
candidate_secure_endpoints
one_time_secret       # 至少 256 bit
expires_at
requested_profile
```

流程：

1. 扫码方读取 host 公钥指纹和一次性 secret。
2. 建立加密连接并验证 host 身份，不能只按二维码中的 IP 判定可信。
3. 双方提交 challenge，签名绑定协议版本、两端公钥、pairing_id、双方 nonce、连接握手摘要和请求权限。
4. 用一次性 secret 对配对 transcript 作密钥确认。
5. 接收端展示真实配对会话的双方名称、指纹摘要和权限；本机确认后才建立信任。
6. secret 原子消费，失败/超时作废；并发配对不能复用。
7. 二维码只提供配对能力，不直接携带长期会话 token。

旧二维码格式继续作为地址导入；扫描旧二维码后进入新配对流程，不把“成功访问 `/info`”升级为身份确认。

### 7.4 配对：PIN

建议使用双方显示/输入的短 PIN，但通过经过审查的 PAKE 协议完成认证密钥交换，再绑定 Ed25519 身份证明与权限 transcript。

必须满足：

- PIN 不直接作为长期 token。
- 不采用“发送 PIN hash + 普通 challenge”作为替代；低熵 PIN 不能承担可离线猜测的秘密。
- 本机显式开启短时窗口，设置全局和会话尝试上限。
- 配对会话和身份公钥必须参与密钥确认，防止未知密钥共享和身份替换。
- 失败记录不能只按客户端自报 ID 限流。
- 原生端与 Web 端共用相同的配对状态机和权限确认结果。

当前八秒拒绝冷却不是 PIN 防猜测机制：`lib/services/remote_control_access_guard_service.dart:113`。

### 7.5 安全连接与会话令牌

**签名身份不能代替传输加密。** 现有 HTTP 会明文传输账号密码、上游 API key、历史和媒体数据，监听代码没有 TLS。证据：`lib/services/web_server_service.dart:407`、`:422`；Web 配置密码发送 `lib/providers/jellyfin_provider.dart:314`。

建议原生对端采用 TLS 1.3，并将证书/握手公钥与已配对 Ed25519 身份绑定。客户端按配对身份验证，不能只接受任何自签证书。也可以采用成熟、经审查的加密通道协议，但不自行拼装加密握手。

会话建立草案：

```text
client -> host: device_id, client_nonce, requested_scopes
host   -> client: session_challenge, host_nonce, expiry, host_signature
client -> host: signature(
  protocol_domain,
  host_device_id,
  client_device_id,
  both_nonces,
  requested_scopes,
  secure_channel_binding
)
host -> client: short_lived_session_token, granted_scopes, expires_at
```

会话 token 建议为至少 256 bit 的不透明随机值，服务端只保存摘要及：

```text
subject
audience_host_device_id
scopes
resource_grants
expires_at
trust_epoch
channel/key binding
```

建议短会话约十五分钟；续期再次证明持有设备私钥。会话失窃后的风险窗口、播放器长连接续期策略应由产品确定。

授权规则：

- audience 限定接收宿主，不能转交另一设备使用。
- 信任撤销使全部会话、资源票据及 pending 配对失效。
- 设备改 IP 不影响信任。
- 浏览器 Origin、IP、User-Agent 和自报名称不能代替 token。
- token 不能由 web_proxy 转发给上游。

### 7.6 浏览器 Web UI 接入

浏览器是一个独立授权主体，不借用原生设备私钥。

建议两种方式：

| 部署 | 接入方式 |
|---|---|
| 宿主同源 Web UI | 新 Web gate 先探测协议，再进行 QR/PIN 或本机批准；通过 HTTPS 设置 HttpOnly、Secure、适当 SameSite 的会话 cookie；写请求增加 CSRF 校验 |
| 独立部署 Web UI | 宿主批准准确的浏览器 Origin；浏览器配对获得该主体的短会话。所有宿主请求统一通过认证客户端；媒体使用受限资源票据。跨来源 cookie 或 Bearer 的选择须明确支持的浏览器范围 |

浏览器可在安全上下文中生成客户端密钥，若保存长期密钥则作为一个可撤销的“浏览器设备”登记；不具备合适密钥能力时使用短期批准会话。Ed25519/WebCrypto 支持范围须做实际平台验证，不能从本仓库判断。

**首次连接的关键限制：** 从未验证的 HTTP 宿主加载 JavaScript，再让这段 JavaScript 自己验证宿主，不能抵抗主动网络攻击者替换页面。二维码指纹也不能让普通浏览器绕过 TLS 信任机制。

因此需要确定一种可信 bootstrap：

- 由受信任 HTTPS Origin 提供 Web UI，宿主也使用浏览器可验证的证书；
- 安装本地信任证书或采用可验证的域名证书；
- 通过已信任原生应用完成桥接。

不能把“自签 HTTPS + 页面内确认指纹”描述为已经解决浏览器首次连接安全。

现有 gate、直接 API 调用和图片 URL 必须一起迁移，不能只给 `WebRemoteAccessService.probe` 加一个 token。调用范围见第 3 节。

### 7.7 原生 NipaPlay 对端接入

统一提供认证 transport client，替换或包装：

- `RemoteControlClientService`。
- `SharedRemoteLibraryProvider` 的 GET/POST/DELETE 请求。
- `SharedRemotePlaybackSyncService`。
- `RemoteSubtitleService` 和 `RemoteMediaFetcher`。
- 播放器直接消费的媒体 URL。

原生请求通过设备签名建立会话，随后使用宿主会话 token。反向代理 Basic Auth 可以继续作为外层访问机制，但与设备会话分开保存和发送。

当前这些客户端各自构造 Authorization 或直接 URL，证据：`lib/providers/shared_remote_library_provider.dart:563`、`lib/services/shared_remote_playback_sync_service.dart:62`、`lib/services/remote_subtitle_service.dart:912`、`lib/utils/remote_media_fetcher.dart:91`。

### 7.8 权限与资源边界

建议授权粒度如下：

| 权限 | 能力范围 |
|---|---|
| `library.read` | 列举授权媒体库和资源元数据 |
| `media.read` | 读取指定库的媒体、字幕、音轨、字体 |
| `history.read` | 读取授权历史范围 |
| `history.write` | 更新授权资源的观看进度 |
| `playback.control` | 操作宿主播放器 |
| `library.manage` | 添加/移除根、扫描、管理连接 |
| `settings.write` | 更改媒体服务器等配置 |
| `account.use` | 指定上游账号操作 |
| `account.sensitive` | WebToken、账号注销、解绑等操作；建议逐次本机确认 |
| `proxy.use` | 指定目的地或服务的代理访问 |

具体资源规则：

1. `history.write` 不允许通过任意路径获得 `media.read`。历史建立与共享资源发布必须是两个独立操作。
2. 新共享根需 `library.manage` 和本机明确许可；已有媒体库不能因普通进度同步扩大读取边界。
3. 本地图片、媒体、字幕统一使用资源 ID；路径仅在宿主内部解析。
4. WebDAV/SMB 凭据保留在宿主，浏览器使用连接 ID 和宿主资源接口。编辑支持“密码未改变”，避免必须回传原密码。
5. 代理目的地授权需覆盖精确 Origin、端口及必要 path；重新验证重定向目标、DNS 解析结果与实际连接地址。
6. 回环、链路本地、元数据地址、宿主内部服务默认拒绝；允许的本机媒体服务应显式登记。
7. Torrent 不开放整个回环端口，而由已授权的媒体 transport 访问指定任务/文件。

授权后代理仍需 SSRF 边界，不能把“已配对设备”解释为能访问宿主任意内部服务。

### 7.9 媒体与浏览器资源票据

播放器、图片标签和外部播放器不一定能携带通用认证头。建议为这些场景签发短期资源票据：

```text
resource_id
allowed_methods = GET, HEAD
audience
subject/session
expires_at
trust_epoch
```

票据只授权一个资源或明确的资源集合，不能授权任意路径、代理 URL 或配置写入。

设计要求：

- 支持 Range、HEAD 和并发读取。
- 长播放通过认证客户端续签，不能因固定短期票据在中途随机失效。
- 字幕、音轨、字体分别得到资源权限。
- URL 中票据不进入日志和 Referer，不能作为长期身份。
- 资源票据与 session token 使用不同类型和解析入口。

这与现有媒体探测和下载契约对应：`lib/utils/remote_media_fetcher.dart:91`、`lib/services/remote_subtitle_service.dart:1403`、`:1464`。

### 7.10 现有用户平滑迁移

建议按以下阶段推进：

1. **兼容修复阶段：** 上线 A；保留旧 API。`/info` 增加可选协议版本、配对方式、身份指纹和安全 endpoint，保留现有 `app`、`success`、features 字段。
2. **双协议阶段：** 新客户端优先安全连接；旧地址、旧二维码、旧 Basic 配置保留。旧遥控信任记录显示为“待升级”，不能静默转换为公钥信任。
3. **用户完成配对：** 迁移地址、显示名和偏好，重新核验设备身份；用户确认权限。已有 IP/clientId 批准只能辅助展示，不能免除证明。
4. **按设备观测兼容调用：** 显示旧客户端仍在使用哪些能力，提供升级入口。避免无提示地全局关闭导致播放或同步失败。
5. **安全模式成为默认：** 新安装只公开最小 discovery/info、配对入口和静态 UI；业务接口要求会话。旧安装保留明确标示的临时兼容模式，并由用户完成升级后关闭。
6. **最终收口：** 关闭匿名敏感 API；匿名 discovery 不泄露账号、路径或凭据。旧 REST 路由仍可作为安全 transport 的兼容 adapter，不必立即删除。

安全 endpoint 不应在认证失败时自动降级到无认证 HTTP。否则攻击者可以主动制造失败，恢复旧风险。

## 8. 成为 Mesh 的传输层基础

Next 设计明确 GUI、Agent、远端设备调用相同 Harness，未来 Mesh/Web 是 transport；`Invocation.origin` 预留 `mesh:<device>`。证据：`docs/next/DESIGN.md:8`、`:25`、`:26`、`:27`。

建议 Mesh transport 提供以下职责：

1. **发现与身份分离。** 地址可动态变化，身份是 device_id；发现结果不直接授予调用权限。
2. **能力交换经过认证。** 配对后交换该设备允许对当前主体看见的 ActionSpec、schema、版本与资源范围。广播摘要不能替代认证后的能力清单。
3. **远程调用认证后进入同一 Harness。** envelope 包含 invocation_id、目标设备、action_id、输入、deadline、请求幂等标识；transport 校验会话和权限后构造可信 `origin=mesh:<device_id>`，不能采用客户端任意提交的 origin。
4. **Effect 与权限分别执行。** `read/write/destructive` 是副作用契约，不是网络信任等级。当前设计中的 Agent 自动审批规则不能直接套给任意已配对设备。证据：`docs/next/DESIGN.md:38`。
5. **本机决定跨设备授权。** 设备 A 信任 B，不意味着自动信任 B 的其他邻居或 Agent。转发请求必须保留已验证发起主体、目标 audience 和明确委托，禁止隐式传递权限。
6. **统一返回 Outcome。** `Completed`、`NeedsDecision`、`Failed` 跨传输序列化；Decision 后续 ActionCall 重新检查身份、权限和资源范围。不能把网络端返回的 UI 选择当作新增授权。
7. **流与事件也受会话控制。** 媒体流、扫描状态和播放事件订阅绑定权限；撤销后终止或限制既有连接。
8. **日志关联但不泄密。** 记录主体、目标、Action ID、effect、结果和 invocation_id，隐藏 token、媒体真实路径与账号凭据。

建议保留 M1 的回环 MCP 边界，不把原 MCP listener 直接改成 0.0.0.0。Mesh 应是新的认证 transport，复用 Harness 内核。设计依据：`docs/next/DESIGN.md:27`、`:50`。

## 9. 风险与待决问题

| 问题 | 已核实依据 | 需要决定或验证 |
|---|---|---|
| 接收端默认开启会启动全部 API | `lib/services/remote_control_settings.dart:17`；`lib/providers/service_provider.dart:55` | 是否将遥控、共享、管理的服务能力分开启用；旧安装如何提示 |
| 严格零兼容变化与彻底授权不可同时完成 | 第 3 节存在合法匿名管理、任意代理与跨来源 Web 调用 | A 只能减风险；B 的用户配对与兼容模式退出必须成为正式产品阶段 |
| 独立 Web UI 与 HTTPS bootstrap | `lib/services/web_remote_access_service.dart:46`、`:66` | 可信证书、域名、独立 UI Origin、浏览器支持矩阵 |
| 反向代理部署未知 | 内置服务无认证、全地址监听：`lib/services/web_server_service.dart:399`、`:422` | 公开 Host、可信代理、后端防火墙及 Basic 与会话组合 |
| 凭据当前被客户端消费 | `lib/providers/shared_remote_library_provider.dart:953`、`:976` | WebDAV/SMB 改宿主代理资源后，编辑和播放是否全部可替换 |
| 本地媒体路径范围广 | share stream 使用历史路径：`lib/services/local_media_share_service.dart:414` | 单文件播放、历史资源、已扫描根、符号链接和特殊格式的统一授权模型 |
| 账号副作用上游规则未知 | `lib/services/dandanplay_service_io.dart:2660`、`:2795` | WebToken 生命周期、business 枚举、注销确认和 API 签名要求 |
| DNS rebinding 的运行条件 | 无 Host 检查：`lib/services/web_server_service.dart:375` | 支持浏览器的私网访问策略、DNS 行为与可复现测试 |
| 资源与限流阈值缺少契约 | body 全缓冲：`lib/services/web_ui_proxy_api.dart:40` | 图片、缩略图、日志、AI 请求和大媒体的不同限制 |
| Torrent 回环接口没有身份 | `rust/src/api/torrent.rs:512` | 是否增加本机能力 token、Host 检查、线程/连接上限；避免影响原生播放 |
| 私钥生命周期与备份 | 当前遥控身份只是 prefs ID：`lib/services/remote_control_settings.dart:63` | 各平台安全存储、恢复、克隆、轮换和丢失后的撤销 |
| Mesh 的权限委托 | Next 预留 mesh origin：`docs/next/DESIGN.md:26` | 仅直连还是允许 relay；是否支持委托，谁能批准 destructive 操作 |
| 当前 Web 构建产物缺失 | `assets/web/.gitkeep`；加载构建目录 `lib/services/web_server_service.dart:49` | 发布前审计实际打包的 Web 版本，防止服务端与前端版本错配 |
| 内部调用缺失不等于可删除 | 第 3.6 节路由与 stub 不一致 | 明确旧版本兼容窗口；修复 register/watch_status 应作为独立功能问题 |

**优先级建议：** 首先修复实际出站 URL 的 token 判定、撤销残留、敏感日志和 HEAD 路由；同时开始统一认证客户端与配对协议。任意文件读取链、凭据返回、匿名配置写入和通用 SSRF 必须在 B 中建立身份与资源边界，不能以 CORS 或“可信局域网”代替授权。