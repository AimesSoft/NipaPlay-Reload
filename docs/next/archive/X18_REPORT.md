# X18：剩余 Classic 设置与操作

日期：2026-10-11。工作目录：`~/Desktop/nipaplay-next-wt/settings-rest`，分支：`next/settings-rest`。没有 commit、push、改依赖或运行 pub get。

## 1. 完成了什么

新增 **75 个静态设置**、按已安装插件动态生成的启用/非秘密 UI 设置，以及 **18 个动作**。接入现有 `NextCore`、`NextRuntime`、`SettingsRegistry` 和 `settings.describe/get/set/reset/history`，动作均支持 `operations` 批量。设置来源仍写入原 SQLite `settings_changes`，包含谁、时间、原因、调用 ID、前后值和 revision。

主要新增文件：

- `lib/next/settings/classic_settings.dart`：Classic 页面设置、schema、存储键与 Provider setter 映射。
- `lib/next/settings/operations.dart`：备份、插件、日志和恢复默认操作。
- `test/next/settings_rest_experiment_test.dart`：隔离数据实验和真实 Classic widget 观察。

### 按当前代码逐页清点

清点以当前页面及其事件回调为准，没有把缺口清单的数量直接当作存储键数量。

| Classic 页面 / 当前可操作内容 | Agent 对应项与持久化 |
|---|---|
| `lib/settings/pages/appearance_settings_content.dart`：主题、主题色 | `appearance.themeMode`、`accentColor`；原 ThemeNotifier / AppearanceSettingsProvider |
| 外观：底部进度条、颜色、弹幕密度曲线、顶部发送弹幕/跳过/适配/逐帧按钮 | 复用原注册的 `player.minimalProgressBarEnabled/Color`、`danmaku.showDensityChart` 与 `player.top*Button(s)Visible`，不新增重复键 |
| 外观：卡片简介、媒体库 NEW、低清海报晕染、目录名称显示 | `appearance.showAnimeCardSummary`、`showMediaLibraryNewBadge`、`diffuseLowResolutionPosters`、`folderNameDisplayMode` |
| 外观：首页新番回顾、轮播大图、上下小卡片 | `appearance.showQuarterlyAnimeReview`、`showHomeHeroBanner`、`showHomeHeroSideCardTop/Bottom` |
| 外观：六个首页分区的排序、启停、恢复默认 | `appearance.homeSectionsOrder`、`homeSectionsDisabled`；`appearance.reset_home_sections`，复用 HomeSectionsSettingsProvider |
| 外观：UI 缩放、支持设备上的自动缩放、窗口显示区域 | `appearance.uiScale`、`automaticUiScale`、`windowDisplayMode`；保留数值/模式跨键来源 |
| 外观：背景模式、自定义文件、毛玻璃、渲染模式、颜色叠加 | `appearance.backgroundImageMode`、`customBackgroundPath`、`blurPower`、`backgroundRenderMode`、`backgroundOverlayOpacity`；复用 ThemeNotifier / SettingsProvider |
| `language_settings_content.dart`：自动、简体、繁体、English | `language.mode`；原 `app_language_mode` 与 AppLanguageProvider |
| `general_settings_content.dart`：关闭行为、启动状态/位置/尺寸及尺寸重置、画中画位置、默认页 | `general.desktopExitBehavior`、`startupWindowState/Position/Width/Height`、`pictureInPicturePosition`、`defaultHomeTab`；两尺寸可批量 `settings.reset`，原 desktop preferences / WebDAV provider |
| `about_settings_content.dart`：后台自动检查更新 | `general.autoCheckUpdates`；UpdateService，兼容旧偏好键 |
| `network_settings_content.dart`：统一 HTTP 代理 | `network.httpProxy` → `player_http_proxy`，原 PlayerFactory/AppHttpProxy；**空字符串使用系统代理**，桌面可见，下次打开媒体生效 |
| `plugin_settings_content.dart` 与市场弹窗：本地导入、市场、更新、GitHub 加速、启停、删除、插件 UI 开关/文本/动作 | `plugins.githubProxyUrl`，动态 `plugins.enabled.<id>`、`plugins.settings.<id>.<entry>` 与六个 `plugins.*` 动作；原 PluginService 与存储方式 |
| `lib/themes/nipaplay/pages/settings/backup_restore_page.dart`：五分类全量备份、预览、恢复；旧观看进度备份/恢复 | 五个 `backup.*` 动作；原 FullBackupService `.npb`、BackupService `.nph` |
| `lib/pages/shortcuts_settings_page.dart`：19 个动作的快捷键录制、恢复默认 | 19 个 `shortcuts.<action>`、`shortcuts.reset`；原 HotkeyService parser、更新与 `keyboard_shortcuts` JSON |
| `developer_options_settings_content.dart`：系统资源、终端收集、文件日志、终端查看/导出/清空、日志目录 | 三个 `diagnostics.*` 设置和四个 `diagnostics.*` 动作；原 DebugLogService / FileLogService；防剧透 AI 响应打印复用原 `danmaku.spoilerAiDebugPrintResponse` |
| 开发者选项：全局允许自签名证书 | `network.allowInvalidCertificates` → `trusted_cert_global_allow_v1`，原 DeveloperOptionsProvider / CertificateTrustService；逐页复查时补齐 |
| `labs_settings_content.dart`：新版番剧详情、显示 Erika 内核 | `labs.enableImmersiveAnimeDetail`、`enableErikaPlayerKernel`，原 LabsSettingsProvider |
| 实验室：WebDAV 快捷子页 | 下表逐项映射 |

静态设置数量：外观 20、语言 1、通用 8、网络 2、插件代理 1、快捷键 19、诊断 3、实验室 2、WebDAV 专属 19，共 75。WebDAV 的默认主页共用通用域的一项，不重复注册。

快捷键动作：`play_pause`、`fullscreen`、`rewind`、`forward`、`toggle_danmaku`、`volume_up/down`、`speed_up/down/reset`、`previous_episode`、`next_episode`、`send_danmaku`、`skip`、`step_forward/backward`、`resize_to_video`、`toggle_picture_in_picture`、`toggle_detached_player`。

当前页面没有可编辑的控件毛玻璃（代码固定关闭）、页面动画（固定开启）、布局切换（锁定），以及旧 `animeCardAction/recentWatchingStyle` 编辑入口，未据 Provider 的旧字段凭空增加入口。备份页的 Classic 多端增量同步是缺口清单单列的待排批次；开发者页依赖/构建信息、UI 预览和 Linux 数据迁移工具不属于本次诊断日志入口。Next 端点与执行权限延续现有设置 denylist 和控制流程。

### WebDAV 子页的 22 项操作

来源：`lib/settings/pages/webdav_quick_settings_content.dart`。有 23 个可操作控件实例；Season 预设和自定义输入编辑同一字段，合并后为 22 项操作（包括重置）。实际只有 **20 个持久键**：两个搜索目标开关合并成一个数组，另有重置动作。

| # | GUI 操作 | 注册项（省略 `webdavQuick.` 前缀） |
|---|---|---|
| 1 | 显示 WebDAV Tab | `showTab` |
| 2 | 默认主页 | 共用 `general.defaultHomeTab` |
| 3 | 默认服务器 | `defaultServerName` |
| 4 | 默认目录 | `defaultDirectory` |
| 5 | 文件排序 | `sortPreset` |
| 6 | 路径导航 | `showPathBreadcrumb` |
| 7 | 自动进入 Season 文件夹 | `autoEnterSeasonFolder` |
| 8 | Season 预设 / 自定义匹配模式 | `seasonFolderPattern` |
| 9 | bgmid 快速匹配 | `bgmIdQuickMatch` |
| 10 | bgmid 匹配规则 | `bgmIdMatchPattern` |
| 11 | tmdbId 快速匹配 | `tmdbIdQuickMatch` |
| 12 | tmdbId 匹配规则 | `tmdbIdMatchPattern` |
| 13 | 匹配弹幕自动剧集偏移 | `episodeOffsetEnabled` |
| 14 | 文件搜索 | `enableSearch` |
| 15 | 搜索范围 | `searchScope` |
| 16 | 层级限制 | `searchDepthLimit` |
| 17 | 搜索文件夹 | `searchTargets` 数组中的 `folder` |
| 18 | 搜索视频文件 | `searchTargets` 数组中的 `video` |
| 19 | 搜索超时 | `searchTimeout`：0/10/30/60 秒 |
| 20 | 请求间隔 | `searchRequestInterval`：0–1000 ms |
| 21 | 最大结果数 | `searchMaxResults`：50–2000 |
| 22 | 重置全部设置 | `webdav_quick.reset` |

### 新动作与 effect

| 动作 | effect |
|---|---|
| `backup.export`、`backup.history_export` | write |
| `backup.preview` | read |
| `backup.restore`、`backup.history_restore` | destructive |
| `plugins.list`、`plugins.market` | read |
| `plugins.install`（含更新）、`plugins.delete`、`plugins.invoke` | destructive |
| `plugins.set_enabled` | write |
| `diagnostics.logs`、`diagnostics.directory` | read |
| `diagnostics.export` | write |
| `diagnostics.clear`、`webdav_quick.reset` | destructive |
| `appearance.reset_home_sections`、`shortcuts.reset` | write |

## 2. 决策

1. **以 Classic 的持久化和应用路径为唯一实现。** NextRuntime 绑定 GUI 使用的现有 Provider；读原偏好键，写原 setter，不引入另一套配置。来源接在原持久化边界，GUI 操作仍标 `user/gui`，Agent 标 `agent/mcp`。没有更改 GUI 控件、选项、通知顺序或存储格式。
2. ThemeNotifier 的旧 setter 不等待持久化，增加 `pendingSave` 供 Agent 等待，保留 GUI 原有通知时机。Provider 的初始化 Future 暴露为 ready，避免 Agent 写入被异步加载覆盖。
3. UI 缩放模式与值、默认主页新键与旧 index 是同一语义的关联存储；注册表增加 secondary keys，并按实际前后值记录。WebDAV 的旧 index 读取沿用该 Provider 的迁移映射。启动尺寸拆成宽高，可一次批量修改或恢复默认，不另存 GUI 的“尺寸预设”标签。
4. 插件注册项随安装/载入/UI entry 更新刷新，删除后从 schema 移除；异步读取注册表和持久化来源使用 entry 快照，防止刷新时改变迭代集合。ID 使用 URI 编码。登录秘密按 entry ID/标题、现有 denylist 排除 password、cookie、token、API key 等。公开文本仍走 Classic PluginService/CredentialStore 的原存储，来源只记已注册的公开项，没有改变秘密分类。
5. 插件市场实际索引用 `file`；原 RemotePluginInfo 仅读 `downloadUrl`。新增模型字段和 Agent 安装 helper，按 GUI 的 raw/blob URL 与 GitHub 代理路径下载，再调用原导入方法；GUI 原安装路径未替换。安装/更新执行 JS，插件动作副作用由脚本决定，因此标 destructive。启停沿用现有 write 规则并返回 enabled/loaded/error。
6. 路径复用现有已授权目录解析；导出拒绝已有文件、目录和断链，避免覆盖。备份恢复复用 Classic 合并规则，返回各分类结果及 `apply=restart_app`，观看历史另刷新原 Provider；没有声称所有 Provider 会立即热重载恢复值。
7. WebDAV 搜索目标用非空去重数组表达，保留 GUI 至少一个目标的约束；匹配规则校验有效正则和捕获组。数值范围、枚举沿用当前 GUI/Provider。`network.httpProxy` 描述明确空值使用系统代理，拒绝带登录认证的代理 URL，复用原校验。
8. 日志读取可按 tag/level 分页；导出原 `exportLogs` 文本，复用原脱敏。批量逐项返回 completed/failed，已完成项不因其他项失败回滚；每项可附 `reason`。
9. 发现的 Classic 插件备份分类缺陷没有静默修改，理由及待决定事项见第 4 节。

## 3. 实验

### 隔离方式与命令

实验只在本 worktree 运行 Flutter 3.44.6。使用真实临时 SQLite、mock SharedPreferences、MemoryVault、真实 Provider、JS runtime 和真实 Classic widget；应用存储 override 指向系统临时 `nipa-x18-*` 目录。回环市场服务器的 HttpClient `findProxy=(_) => 'DIRECT'`，命令同时移除代理环境变量。没有读写用户钥匙串或真实数据目录，没有构建或启动已安装应用，也没有启动窗口。成功实验 teardown 删除临时文件/数据库；此前失败遗留的三个同前缀实验目录也已清理。

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/settings_rest_experiment_test.dart --reporter expanded
```

最终原始输出保存在 `/tmp/nipa-x18-experiment.log`，以下为原样摘录：

```text
X18 read/change/read/provenance: {"appearance":20,"diagnostics":3,"general":8,"labs":2,"language":1,"network":2,"plugins":1,"shortcuts":19,"webdavQuick":19} total=75
X18 proxy: explicit=PROXY 127.0.0.1:7890; empty=SYSTEM
X18 Classic widgets: language=English; WebDAV maxResults=1000; showTab=true
X18 GUI provenance: {"key":"appearance.showHomeHeroBanner","previousValue":false,"value":true,"changedAt":"2026-10-11T10:54:15.429260Z","changedBy":"user","origin":"gui","reason":null,"invocationId":"inv-1791716055428682-227","revision":2}
X18 Agent provenance: {"key":"language.mode","previousValue":"auto","value":"english","changedAt":"2026-10-11T10:54:14.796080Z","changedBy":"agent","origin":"mcp","reason":"X18 language experiment","invocationId":"inv-1791716054795425-100","revision":1}
X18 plugin install/enable/settings: {"id":"x18.fixture","name":"X18 fixture","version":"1.0.0","builtin":false,"enabled":true,"loaded":true,"error":null,"description":"isolated experiment","actions":[{"id":"inspect","title":"Inspect","description":null}]} secretField=excluded
X18 plugin update/invoke: version=2.0.0; text setting preserved; action=roundtrip
X18 plugin disable/delete: loaded=false; dynamic settings removed
X18 market/install: file field resolved; Classic proxy requests=["/https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main/plugins.json","/https://github.com/AimesSoft/Nipaplay-plugins/blob/main/plugins/x18-market.js"]
X18 diagnostics export: text preserved; batch=[failed(conflict),completed]
恢复了 66 项偏好设置
恢复了 1 个本地媒体库路径
恢复了 1 个服务器配置
观看历史恢复完成: 恢复 1 条，跳过 0 条
剧集匹配恢复完成: 恢复 0 条，跳过 1 条
恢复了 1 个服务器账户
X18 .nph roundtrip: restoredCount=1; position=123000
X18 reset: WebDAV maxResults=500; shortcuts=19 defaults
00:01 +1: All tests passed!
```

75 项逐项经 Harness `settings.get → settings.set → settings.get`，校验实际值、Agent/MCP、reason、UTC 时间、invocationId 与 revision。另验证 GUI setter 的 user/gui 来源、自动缩放切换为手动时跨键前后值；插件启用、公开 switch/text 同样读回并检查 Agent 来源，password/cookie 不出现在注册表。

GUI 观察挂载的是现有 `LanguageSettingsContent` 和 `WebDAVQuickSettingsContent`，English 文本、显示 Tab 开关和最大结果数 slider 均读到 Agent 修改后的值；还直接检查同一外观、主题、语言、WebDAV Provider 和 HotkeyService 的实际状态。

### 备份往返的实际结果

测试在临时目录建立一条历史与剧集匹配、一条本地媒体库、公有服务器配置/账户，以及字符串、Unicode 列表和本次设置。导出 `.npb` 后改写语言/字符串/列表、清空本地库与历史，再按五分类恢复。恢复前后重新 `collectBackupData`，五个分类分别深比较完全相等，历史位置恢复为 123000 ms，语言恢复的来源是 `agent / X18 restore roundtrip`。账户 fixture 没有登录秘密。

```text
X18 backup preview: {"version":2,"timestamp":"2026-10-11T18:54:15.538196","appVersion":"","categories":["preferences","mediaLibraries","watchHistory","episodeMatches","accounts"],"watchHistoryCount":1,"episodeMatchCount":1,"serverProfileCount":1,"localLibraryCount":1,"webdavConnectionCount":0,"smbConnectionCount":0}
X18 backup roundtrip: {"success":true,"error":null,"restoredCount":67,"skippedCount":1,"apply":"restart_app","categories":{"preferences":{"success":true,"restoredCount":66,"skippedCount":0,"error":null,"localLibraryCount":0,"serverProfileCount":0,"serverAccountCount":0,"dandanplayRestored":false,"bangumiRestored":false},"mediaLibraries":{"success":true,"restoredCount":0,"skippedCount":0,"error":null,"localLibraryCount":1,"serverProfileCount":1,"serverAccountCount":0,"dandanplayRestored":false,"bangumiRestored":false},"watchHistory":{"success":true,"restoredCount":1,"skippedCount":0,"error":null,"localLibraryCount":0,"serverProfileCount":0,"serverAccountCount":0,"dandanplayRestored":false,"bangumiRestored":false},"episodeMatches":{"success":true,"restoredCount":0,"skippedCount":1,"error":null,"localLibraryCount":0,"serverProfileCount":0,"serverAccountCount":0,"dandanplayRestored":false,"bangumiRestored":false},"accounts":{"success":true,"restoredCount":0,"skippedCount":0,"error":null,"localLibraryCount":0,"serverProfileCount":0,"serverAccountCount":1,"dandanplayRestored":false,"bangumiRestored":false}}} all five categories=exact; position=123000; provenance=agent/X18 restore roundtrip
```

`episodeMatches skipped=1` 是观看历史恢复已包含同一匹配，深比较确认匹配仍在，没有丢失。Classic 的媒体库/账户计数采用独立字段，因此动作返回对应 count，不能只看总 restoredCount。`.nph` 单独将进度改为 0 后恢复，重新查库为 123000 ms。

这证明上述 fixture 往返，没有证明所有插件状态都能无损备份。单独的插件启用列表实验实际失败，详见下一节。

### 回归与静态检查

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/settings_registry_test.dart test/security/backup_credentials_test.dart \
  test/appearance_quarterly_review_setting_test.dart \
  test/unified_http_proxy_settings_widget_test.dart test/hotkey_service_policy_test.dart \
  test/desktop_startup_window_placement_test.dart test/desktop_exit_handler_test.dart \
  test/next/next_core_test.dart test/next/state_query_test.dart \
  test/plugins/plugin_runtime_resolution_test.dart --reporter expanded
```

真实输出 `/tmp/nipa-x18-regression.log`：

```text
00:01 +47: All tests passed!
```

新增设置/实验/市场模型的 targeted analyze 无错误；加入证书服务后，该服务原有 `dart:typed_data` 导入产生一条 `unnecessary_import` info。全部 27 个修改 Dart 文件另以 `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 检查，exit 0，无 error，10 条原有 info 和 3 条原有 warning，结果记录 `/tmp/nipa-x18-analyze.log`。没有顺手清理 Classic 原有诊断。`git diff --check` 通过。

```text
Analyzing 27 items...
13 issues found. (ran in 3.9s)
analyzed Dart files: 27 exit: 0
```

### 意外与限制

- 初轮编译遇到 harness 的 ArraySchema 没有 minItems、动作 ID 只接受 snake_case，已按实际契约调整。
- widget 实验最初受 fake async、缺少页面 Provider、隐藏搜索开关影响，改用 `runAsync`、注入真实 Provider 并在验证 slider 前开启搜索。
- macOS 系统临时目录经符号链接映射，实验授权根改为 canonical 路径。Flutter test 默认拦截网络返回 HTTP 400，回环测试改为真实 HttpClient override 并 DIRECT，才观察到实际市场请求。
- Flutter test 不包含 Rust framework，Classic 备份 codec 输出 `Rust 增量同步编解码不可用，回退 Dart 实现` 并走原 Dart fallback。此次结果不证明 Rust 编解码、原生 `.app` 构建、完整运行时装配或真实桌面窗口行为；没有做这些实验。

## 4. 问题：需要主控决定

**一项：是否修正 Classic 非秘密插件偏好的凭据分类与备份恢复行为。**

`lib/security/credential_store.dart` 的 `isSecretKey` 当前把除 switch 前缀外的所有 `plugin_` 键都当作秘密，包含 `plugin_enabled_ids`（StringList）、`plugin_downloader_override`（bool），也包含公开插件文本。`exportPreference` 无论实际值类型都导出 credentialRef。启用列表/布尔项原本按普通偏好保存，没有相应 vault 值；FullBackupService 恢复时 hydrate 掉无法解析的引用，仍报告成功。

在本次临时目录实验中：启用内置正则插件 → 导出 preferences → 停用 → 恢复，实际输出：

```text
恢复了 46 项偏好设置
备份恢复完成
X18 existing Classic backup limitation: plugin_enabled_ids exported={"credentialRef":{"namespace":"preferences","key":"plugin_enabled_ids"}}; before=[builtin.cn_danmaku_regex_filter]; after=[]
```

因此不能交付“所有插件配置备份无损”的结论。Agent 入口已忠实复用现有备份格式与恢复实现；本次只在注册表放行确认为非秘密的启用列表，没有改 CredentialStore 分类。

建议主控授权后，将明确非秘密的插件结构偏好从秘密分类中排除，并决定公开文本的便携导出策略和旧备份兼容方式；登录秘密继续保留引用。这会改变 Classic 导出/恢复行为及数据语义。依据 [TEAM.md](TEAM.md)「以下情况必须停下来提问，不能自行决定：改变 Classic 模式的行为（它有真实用户）；可能丢失或改写持久数据」，本批次将该修复留给主控决定。
