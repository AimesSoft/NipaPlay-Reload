**不能完全覆盖。** Next 已覆盖大多数弹幕显示设置、轨道开关、检索和基本加载，但仍有明确缺失，以及“能力已注册、实际效果不等价”的情况。

本报告针对 `next/capability-layer` 做静态代码审计；全程只读，没有修改文件、构建或运行应用。以下把“能完成业务操作”作为覆盖标准：例如，批量配对可以通过显式映射完成，不要求 Agent 模拟拖拽。

## 相关能力清单

**弹幕 Action**，注册于 [capability.dart:214](~/Desktop/NipaPlay-Reload/lib/next/danmaku/capability.dart:214)：

| 用途 | 能力 id |
|---|---|
| 导入、来源发现、检索、剧集、解析 | `danmaku.import`、`danmaku.sources`、`danmaku.search`、`danmaku.episodes`、`danmaku.resolve` |
| 获取、挂载、查询轨道 | `danmaku.fetch`、`danmaku.attach`、`danmaku.tracks` |
| 修改轨道 | `danmaku.update`、`danmaku.set_enabled`、`danmaku.set_dedup`、`danmaku.offset` |
| 解除绑定、删缓存、导出 | `danmaku.detach`、`danmaku.cache_delete`、`danmaku.export` |
| 分析固定偏移 | `danmaku.analyze_alignment` |
| 旧任务兼容 | `danmaku.align`、`danmaku.align_apply`、`danmaku.align_keep`；不能发起新的旧式对齐任务，[注册说明:418](~/Desktop/NipaPlay-Reload/lib/next/danmaku/capability.dart:418) |

当前注册来源为 Dandanplay 和 local：[runtime.dart:74](~/Desktop/NipaPlay-Reload/lib/next/danmaku/runtime.dart:74)。

**`state.query` 视图**：

| 视图 | 实际内容 |
|---|---|
| `danmaku.bindings` | 持久绑定、偏移、开关、缓存关联及挂载状态；[views.dart:587](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:587) |
| `danmaku.datasets` | 缓存分块范围、覆盖状态、条数；明确不返回正文或 sender；[views.dart:630](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:630) |
| `danmaku.tracks` | 当前 Classic、本地和 Next 轨道的名称、来源、条数、开关、偏移等；[views.dart:643](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:643) |

**设置能力**为 `settings.describe/get/set/reset/history`，注册于 [settings/capability.dart:64](~/Desktop/NipaPlay-Reload/lib/next/settings/capability.dart:64)。与弹幕相关的键包括：

- 显示与过滤：`danmaku.visible`、`showDensityChart`、`randomColor`、`stacking`、`merge`、`blockTop`、`blockBottom`、`blockScroll`、`blockWords`、`timelineEnabled`。
- 样式：`danmaku.opacity`、`fontSize`、`speedMultiplier`、`displayArea`、`trackGap`、`outlineWidth`、`outlineStyle`、`shadowStyle`、`fontFamily`、`fontFilePath`。
- 匹配与时间：`danmaku.convertToSimplified`、`autoMatchFirstSearchResultOnHashFail`、`skipMatching`、`autoLoadStrategy`、`manualOffset`、`rememberOffset`。
- 渲染：`danmaku.supersample`、`renderEngine`、`nextPlusPlusEnabled`、`pluginRenderer`。
- 防剧透：`danmaku.spoilerPreventionEnabled`、`spoilerAiApiUrl`、`spoilerAiModel`、`spoilerAiApiFormat`、`spoilerAiTemperature`、`spoilerAiDebugPrintResponse`。
- Titan：`danmaku.titan.opacity`、`fontSize`、`bold`、`fontBorder`、`fontFamily`、`speedPlus`、`density`、`duration`、`limit`、`trackGap`、`preventShade`、`offsetTop`、`offsetBottom`、`maxLength`、`isRecyclingDom`、`isRecyclingModel`、`forbidShrinkState`。

上述列表中省略前缀的键，均沿用所在组的 `danmaku.` 或 `danmaku.titan.` 前缀。注册实现见 [application_settings.dart:916](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:916)、[1062](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1062)、[1740](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1740)。

另有直接支持本块的能力：

- 登录：`accounts.status`、`accounts.login`。
- 匹配：`media.metadata.search/get`、`media.hash.match`、`media.identity.bind_batch`。
- 定位：`playback.seek`、`playback.external(command=seek)`。
- 弹幕插件：`plugins.list/set_enabled/invoke`；动态设置 `plugins.enabled.<pluginId>`、`plugins.settings.<pluginId>.<entryId>`。
- 相关设置：`shortcuts.toggle_danmaku`、`shortcuts.send_danmaku`、`player.topSendDanmakuButtonVisible`、`player.screenshotIncludeDanmaku`、`player.externalDanmakuOverlay`、`player.externalAutoSwitchToDanmakuConsole`。

## 1. 缺失

按对用户的影响排序。

### 1.1 发送弹幕整条操作链缺失

Classic 用户可通过顶部发送按钮或默认快捷键 **C** 打开发送窗，输入正文，选择滚动／顶部／底部模式、预设颜色或六位 HEX 自定义颜色，发送后立即在本地回显。

调用链：

- 顶部按钮：[play_video_page.dart:1054](~/Desktop/NipaPlay-Reload/lib/pages/play_video_page.dart:1054)；快捷键：[hotkey_service.dart:832](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:832)。
- `showSendDanmakuDialog`：[video_player_state_danmaku.dart:1840](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1840)。
- 模式、颜色和 `_sendDanmaku`：[send_danmaku_dialog.dart:52](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/send_danmaku_dialog.dart:52)。
- 实际发送：`DanmakuMatchingService.sendDanmaku` → `DandanplayService.sendDanmaku`，[matching_service:115](~/Desktop/NipaPlay-Reload/lib/services/danmaku_matching_service.dart:115)、[dandanplay_service_io.dart:2556](~/Desktop/NipaPlay-Reload/lib/services/dandanplay_service_io.dart:2556)。

Next 没有对应发送 Action，也没有发起专用发送窗的能力。`accounts.login`、发送按钮显隐设置和快捷键改绑都不能替代发送。

### 1.2 当前逐条弹幕列表及过滤状态缺失

Classic 用户能：

- 浏览当前弹幕的时间、正文、类型和颜色。
- 切换是否显示被过滤的弹幕。
- 查看随播放定位的列表和当前高亮。
- 在外部控制台额外查看 sender、blocked／active 状态，暂停列表跟随或恢复跟随。

Classic 入口及实际读取：

- `_loadDanmakus` 读取当前列表或 `getFilteredDanmakuList`：[danmaku_list_menu.dart:116](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_list_menu.dart:116)。
- “显示被过滤的弹幕”开关：[danmaku_list_menu.dart:414](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_list_menu.dart:414)。
- Cupertino 列表：[cupertino_danmaku_list_pane.dart:224](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_list_pane.dart:224)。
- 外部列表跟随、sender 等：[external_player_console_page.dart:1058](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:1058)、[1191](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:1191)。
- 外部 blocked／active 计算：[external_player_console_service.dart:461](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:461)。

Next 的三个弹幕视图仅提供绑定、轨道和缓存摘要。`danmaku.export(raw)` 能导出部分 Next 缓存正文，但不能完整替代**当前多轨合并列表、过滤后列表及逐条状态**。

### 1.3 删除未绑定的 Classic 本地弹幕轨道缺失

Classic 的轨道菜单在 `source == local` 时提供删除按钮：

- 按钮直接调用 `removeDanmakuTrack`：[danmaku_tracks_menu.dart:277](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_tracks_menu.dart:277)。
- 实际删除轨道并重新合并：[video_player_state_danmaku.dart:1445](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1445)。

Next 的 `danmaku.detach` 必须提供 `bindingId` 和版本；`danmaku.update(trackId)` 支持开关、偏移、折叠，但不支持删除。因此，未绑定本地轨道不能通过现有能力删除。

已绑定本地轨道也有不等价行为，见部分覆盖。

### 1.4 立即清空 Classic 弹幕缓存缺失

Classic 在“设置 → 存储”提供“立即清空弹幕缓存”：

- 入口：[storage_settings_content.dart:66](~/Desktop/NipaPlay-Reload/lib/settings/pages/storage_settings_content.dart:66)。
- `_clearDanmakuCache` → `DanmakuCacheManager.clearAllCache`：[storage_settings_content.dart:283](~/Desktop/NipaPlay-Reload/lib/settings/pages/storage_settings_content.dart:283)。
- 实际清理内存和文件缓存：[danmaku_cache_manager.dart:374](~/Desktop/NipaPlay-Reload/lib/services/danmaku_cache_manager.dart:374)。

`danmaku.cache_delete` 删除的是指定 Next 缓存对象的 SQLite 分块：[store.dart:386](~/Desktop/NipaPlay-Reload/lib/next/danmaku/store.dart:386)。它不会清空上述 Classic 缓存，不能视为覆盖。

### 1.5 启动时清空 Classic 弹幕缓存设置缺失

Classic 用户可开启／关闭该设置；开启时还会立即清空一次：

`_updateClearOnLaunch`：[storage_settings_content.dart:263](~/Desktop/NipaPlay-Reload/lib/settings/pages/storage_settings_content.dart:263)。

对应 `SettingsKeys.clearDanmakuCacheOnLaunch` 未进入 Next 设置注册表，也没有等价 Action。

### 1.6 外部播放器会话的弹幕样式、调轴和同步缺失

Classic 外部控制台允许用户独立修改当前会话：

- 不透明度、字号、描边宽度、堆叠：[external_player_console_page.dart:397](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:397)、[416](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:416)、[431](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:431)、[447](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:447)。
- 提前、延后、重置、自定义偏移：`setDanmakuOffset` 等，[external_player_console_service.dart:288](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:288)；自定义输入入口：[console_page:652](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:652)。
- 将会话样式写回用户设置：`_writeBackUserDanmakuStyle`，[console_page:153](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:153)。
- 将用户设置重新应用于会话：`_reapplyUserDanmakuStyle`，[console_page:188](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:188)。

这些操作修改外部会话样式并调用 `queueDanmakuRefresh`。Next 的 `danmaku.*` 设置修改的是 `VideoPlayerState`；`playback.external` 只支持 state／pause／resume／seek／close：[能力定义:101](~/Desktop/NipaPlay-Reload/lib/next/capabilities/playback_controls_capability.dart:101)。没有对应会话样式 Action 或视图。

### 1.7 外部播放器会话的屏蔽规则管理缺失

Classic 外部控制台可选择关键词、正则或发送者 ID，添加规则、查看规则并删除：

- 类型选择和添加：[external_player_console_page.dart:805](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:805)。
- 删除入口：[console_page:951](~/Desktop/NipaPlay-Reload/lib/pages/external_player_console_page.dart:951)。
- 实际服务：`addBlockedItem/removeBlockedItem`，[external_player_console_service.dart:353](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:353)、[378](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:378)。
- 发送者 ID 匹配：[service:476](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:476)。

Next 没有管理该会话 `_blockedItems` 的入口。全局 `danmaku.blockWords` 不能替代会话规则，也不能表达这里的发送者 ID 屏蔽。

## 2. 部分覆盖

### 2.1 手动匹配、重新匹配和批量匹配

**已有能力：** `media.metadata.search/get`、`media.identity.bind_batch`、`danmaku.search/episodes/attach`。新文件映射、显式选择剧集、按指定顺序配对可完成；Classic 批量窗的选择、排序、拖拽配对可用映射 entries 表达。

**缺口：**

- **覆盖已有 Classic 匹配不等价。** Classic 手动重匹配会覆盖历史映射：[danmaku_history_sync.dart:53](~/Desktop/NipaPlay-Reload/lib/utils/danmaku_history_sync.dart:53)。Next 投影遇到完整且不同的 Classic 匹配会直接报 conflict：[classic_projection.dart:182](~/Desktop/NipaPlay-Reload/lib/next/media/classic_projection.dart:182)。
- **当前播放信息没有同步完成。** Classic 手动匹配更新标题并调用 `loadDanmaku`：[danmaku_settings_menu.dart:1199](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:1199)；后者更新 `_episodeId/_animeId`：[video_player_state_danmaku.dart:334](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:334)。Next 挂载路径只安装弹幕轨道：[player_port.dart:160](~/Desktop/NipaPlay-Reload/lib/next/danmaku/player_port.dart:160)。因此，标题及 Classic 发送弹幕所用目标不能据此认为已同步。
- **批量匹配中的旧路径历史迁移不等价。** Classic 会保留相关旧历史进度、更新新路径并删除迁移后的旧历史：[library_management_tab.dart:4365](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/library_management_tab.dart:4365)。Next 投影修改匹配字段，没有这条进度迁移流程。

Classic 批量选择／排序／含子目录／一对一确认入口见 [batch_danmaku_dialog.dart:352](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/batch_danmaku_dialog.dart:352)。

### 2.2 导出当前弹幕

**已有能力：** `danmaku.export(bindingId, path, view=raw|mapped)`。

**缺口：** XML、多启用轨道合并导出、未绑定 Classic／本地轨道导出，以及 Classic 文件选择器允许的保存目的地和覆盖已有文件。

Classic 菜单选择 JSON/XML 后，调用 `collectDanmakuForExport` 汇集启用轨道、应用各轨偏移并排序：

[danmaku_settings_menu.dart:205](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:205) → [video_player_state_danmaku.dart:840](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:840)。

Next 导出仅接受授权目录内的绝对 `.json` 新文件，且单绑定必须具有 committed cache：[export.dart:13](~/Desktop/NipaPlay-Reload/lib/next/danmaku/export.dart:13)。

### 2.3 全局自定义弹幕偏移

**已有能力：** `settings.set(key=danmaku.manualOffset)`；预设、重置及范围内自定义可完成。

**缺口：** Next 限制为 **−30～30 秒**：[application_settings.dart:1347](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1347)。Classic 偏移菜单允许输入自定义 double，setter 没有该范围限制：[danmaku_offset_menu.dart:54](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_offset_menu.dart:54)、[video_player_state.dart:1844](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state.dart:1844)。

全局偏移的方向是**正数延后、负数提前**。

### 2.4 单轨自定义偏移

**已有能力：** `danmaku.update`、`danmaku.offset`；范围内提前／延后／重置可完成。

**缺口：** Next 仅接受整数毫秒，范围为 **±7,200,000 ms，即 ±2 小时**：[capability.dart:179](~/Desktop/NipaPlay-Reload/lib/next/danmaku/capability.dart:179)。Classic 自定义输入支持有限 double 秒，没有这条范围限制：[danmaku_track_offset_button.dart:76](~/Desktop/NipaPlay-Reload/lib/widgets/danmaku_track_offset_button.dart:76)、[setter:1425](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1425)。

单轨偏移是**正数提前**，与全局方向不同。时间轴提示轨道禁止调轴，两边一致。

### 2.5 本地 XML/JSON 导入与重复独立轨道

**已有能力：** `danmaku.import` 复用 Classic 本地格式、编码解析，基本导入已覆盖。

**缺口：** Classic 每次导入可创建新的本地轨道：[danmaku_tracks_menu.dart:65](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_tracks_menu.dart:65)、[loadLocalDanmaku:541](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:541)。

Next 对相同 entity revision、platform、videoId 重导会替换同一池，而不是保留同来源元数据下的多个独立轨道：[store.dart:35](~/Desktop/NipaPlay-Reload/lib/next/danmaku/store.dart:35)。也没有轨道显示名参数。给每次导入编造不同来源 ID，不等价于保留原来源的重复导入。

### 2.6 已绑定本地轨道的删除／卸载

**已有能力：** `danmaku.detach`、`danmaku.cache_delete`。

**缺口：** 实际调用 `removeSourceDanmakuTrack` 时，`source == local` 或 `origin == auto_remote` 分支只移除绑定、缓存和回调元数据，**保留轨道及其弹幕**：

[player_port.dart:214](~/Desktop/NipaPlay-Reload/lib/next/danmaku/player_port.dart:214) → [video_player_state_danmaku.dart:1470](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1470)。

因此不能把 detach 的“remove track”描述，或 cache_delete 的“unload”描述，当作 Classic 本地删除已覆盖。

### 2.7 字体文件夹和字体库选择

**已有能力：** 已知路径的单文件导入、恢复默认字体，以及按已知文件路径逐项调用 `settings.set(key=danmaku.fontFilePath)`。

**缺口：** 没有字体文件夹枚举／导入入口，也没有现有字体库名称与真实文件路径的发现视图。

Classic 支持：

- 多选字体文件：[danmaku_settings_menu.dart:329](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:329)。
- 选择文件夹并遍历字体文件：[359](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:359)。
- 展示字体库、按名称选择；再次点击已应用字体恢复默认：[824](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:824)。

Next 的单文件设置调用实际导入服务：[application_settings.dart:206](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:206)，但要求已知且授权的路径。

### 2.8 防剧透 AI 配置流程

**已有能力：** 开关，以及 URL、模型、格式、温度等非秘密设置。

**缺口：** 没有直接发起“由用户填写 Key”的专用配置窗口能力，也没有对应 Classic `spoilerAiConfigReady` 的状态视图。

Classic 配置入口及配置状态：[danmaku_settings_content.dart:1450](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1450)；窗口方法：[326](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:326)。`ui.open` 只接受主页面、实体或路径，不能指定该对话框：[ui_open.dart:29](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:29)。

**不把 Agent 不能填写 API Key 判为缺失**；缺的是发起用户完成配置的流程。已配置用户的防剧透开关可以操作。

### 2.9 依赖加载事件的插件过滤

**已有能力：** 插件启停、非秘密设置、普通插件 UI Action；静态插件屏蔽词仍经过 Classic 过滤逻辑。

**缺口：** Classic 在线／本地加载会调用 `_notifyPluginDanmakuLoaded`，并接收插件替换后的数据：[加载路径:395](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:395)、[本地路径:620](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:620)、[事件方法:1951](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1951)。

Next 新获取／导入后的挂载走 `installSourceDanmakuTrack`，该方法不发这个事件，也不接收 pending 替换数据：[实现:680](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:680)。

因此，**依赖 `danmakuLoaded` 改写弹幕池的插件流程不等价**。这不代表全部插件过滤失效；静态插件词／正则过滤仍在 [video_player_state_subtitles.dart:658](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:658)。

### 2.10 从列表选中弹幕并跳转

**已有能力：** 已知时间可用 `playback.seek`；外部会话可用 `playback.external(command=seek)`。

**缺口：** 没有当前逐条弹幕查询，不能完整完成“找到某条正文 → 获取其时间 → 跳转”的操作。

Classic 内部列表 `_seekToTime`：[danmaku_list_menu.dart:342](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_list_menu.dart:342)；外部实际定位服务：[external_player_console_service.dart:279](~/Desktop/NipaPlay-Reload/lib/services/external_player_console_service.dart:279)。

## 3. 已覆盖

这里逐行列出已确认的操作或子操作；导入、匹配、导出、调轴的整体限制仍以第 2 节为准。表中的 Classic 链接指向调用入口或实际方法。

设置项的修改能力 id 均为 **`settings.set`**，读取使用 `settings.get/describe`。

| Classic 操作／界面 | 能力 id 或设置键 | Classic 代码 |
|---|---|---|
| 发起 Dandanplay 登录，由用户输入秘密 | `accounts.login(provider=dandanplay)`；状态用 `accounts.status` | [ensureAccess:15](~/Desktop/NipaPlay-Reload/lib/services/danmaku_matching_service.dart:15) |
| 手动匹配窗搜索动画 | `danmaku.search`／`media.metadata.search` | [搜索服务:44](~/Desktop/NipaPlay-Reload/lib/services/danmaku_matching_service.dart:44) |
| 获取剧集并选择指定集／第一集 | `danmaku.episodes`／`media.metadata.get`，再 `danmaku.attach` | [手动匹配入口:1199](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:1199) |
| 播放匹配中的文件哈希查询 | `media.hash.match` | [匹配服务:19](~/Desktop/NipaPlay-Reload/lib/services/danmaku_matching_service.dart:19) |
| 为新文件批量指定剧集配对 | `media.identity.bind_batch` | [批量确认:410](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/batch_danmaku_dialog.dart:410) |
| 加载已选择的线上弹幕 | `danmaku.attach`；单独获取用 `danmaku.fetch` | [loadDanmaku:303](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:303) |
| 从轨道菜单基本导入 XML/JSON | `danmaku.import` | [loadLocalDanmaku:541](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:541) |
| 查看轨道名称、来源、条数、开关、偏移 | `danmaku.tracks`／`state.query(view=danmaku.tracks)` | [轨道显示:243](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_tracks_menu.dart:243) |
| 启用／关闭单轨 | `danmaku.update`；已绑定也可 `danmaku.set_enabled` | [toggleDanmakuTrack:1434](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1434) |
| 范围内单轨提前／延后／重置 | `danmaku.update`／`danmaku.offset` | [setDanmakuTrackOffset:1425](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1425) |
| 播放器按钮或 D 键显示／隐藏弹幕 | `settings.set`：`danmaku.visible` | [快捷键处理:788](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:788) |
| 开关弹幕密度图 | `settings.set`：`danmaku.showDensityChart` | [setShowDanmakuDensityChart:324](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:324) |
| 调节普通弹幕不透明度 | `settings.set`：`danmaku.opacity` | [setDanmakuOpacity:339](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:339) |
| 调节普通弹幕字号 | `settings.set`：`danmaku.fontSize` | [setDanmakuFontSize:1487](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:1487) |
| 调节滚动速度倍率 | `settings.set`：`danmaku.speedMultiplier` | [setDanmakuSpeedMultiplier:2778](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:2778) |
| 导入已知路径的字体文件 | `settings.set`：`danmaku.fontFilePath` | [importDanmakuFontFile:1707](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:1707) |
| 恢复默认弹幕字体 | `settings.set`：`danmaku.fontFilePath=""`／`settings.reset` | [resetDanmakuFont:1734](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:1734) |
| 选择描边样式 | `settings.set`：`danmaku.outlineStyle` | [setDanmakuOutlineStyle:1783](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:1783) |
| 选择 0／1／2 描边档位 | `settings.set`：`danmaku.outlineWidth` | [设置页回调:1261](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1261) |
| 选择阴影样式／开启关闭阴影 | `settings.set`：`danmaku.shadowStyle` | [setDanmakuShadowStyle:1794](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:1794) |
| 选择轨道显示区域 | `settings.set`：`danmaku.displayArea` | [setDanmakuDisplayArea:2730](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:2730) |
| 调节 DFM+／Erika 轨道间距 | `settings.set`：`danmaku.trackGap` | [设置页回调:1393](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1393) |
| 开关相同弹幕合并 | `settings.set`：`danmaku.merge` | [setMergeDanmaku:393](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:393) |
| 开关弹幕堆叠 | `settings.set`：`danmaku.stacking` | [setDanmakuStacking:445](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:445) |
| 开关随机染色 | `settings.set`：`danmaku.randomColor` | [setDanmakuRandomColorEnabled:456](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:456) |
| 开关时间轴进度提示弹幕 | `settings.set`：`danmaku.timelineEnabled` | [toggleTimelineDanmaku:1935](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1935) |
| 屏蔽／恢复顶部弹幕 | `settings.set`：`danmaku.blockTop` | [setBlockTopDanmaku:304](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:304) |
| 屏蔽／恢复底部弹幕 | `settings.set`：`danmaku.blockBottom` | [setBlockBottomDanmaku:321](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:321) |
| 屏蔽／恢复滚动弹幕 | `settings.set`：`danmaku.blockScroll` | [setBlockScrollDanmaku:338](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:338) |
| 查看全局屏蔽词 | `settings.get`：`danmaku.blockWords` | [菜单列表:500](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:500) |
| 添加单个／逗号批量关键词／命名正则 | `settings.set`：`danmaku.blockWords` 完整数组 | [输入处理:111](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:111) |
| 删除全局屏蔽词 | `settings.set`：`danmaku.blockWords` 剩余数组 | [删除回调:508](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_settings_menu.dart:508) |
| 范围内全局预设／自定义偏移／重置 | `settings.set`：`danmaku.manualOffset` | [偏移菜单:54](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_offset_menu.dart:54) |
| 切换视频是否记住偏移 | `settings.set`：`danmaku.rememberOffset` | [setRememberDanmakuOffset:2768](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_preferences.dart:2768) |
| 开关弹幕转简体 | `settings.set`：`danmaku.convertToSimplified` | [设置页回调:1325](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1325) |
| 开关跳过自动弹幕匹配 | `settings.set`：`danmaku.skipMatching` | [设置页回调:1473](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1473) |
| 选择远程＋本地／仅远程／仅本地自动加载 | `settings.set`：`danmaku.autoLoadStrategy` | [设置页回调:1515](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1515) |
| 哈希失败时是否自动选择首个搜索结果 | `settings.set`：`danmaku.autoMatchFirstSearchResultOnHashFail` | [设置页回调:1541](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1541) |
| 切换平台支持的内置弹幕渲染引擎 | `settings.set`：`danmaku.renderEngine` | [_saveDanmakuRenderEngineSettings:95](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:95) |
| 开关 Next++ 优化 | `settings.set`：`danmaku.nextPlusPlusEnabled` | [_saveNextPlusPlusEngineSetting:119](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:119) |
| 选择已启用插件的弹幕渲染器 | `settings.set`：`danmaku.pluginRenderer` | [_savePluginDanmakuRendererSettings:108](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:108) |
| 选择关闭／1.5x／2x 超采样 | `settings.set`：`danmaku.supersample` | [设置页回调:875](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:875) |
| 已配置 AI 时开关防剧透 | `settings.set`：`danmaku.spoilerPreventionEnabled` | [setSpoilerPreventionEnabled:378](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:378) |
| 修改防剧透接口 URL | `settings.set`：`danmaku.spoilerAiApiUrl` | [setSpoilerAiApiUrl:549](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:549) |
| 修改防剧透模型 | `settings.set`：`danmaku.spoilerAiModel` | [setSpoilerAiModel:553](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:553) |
| 选择 OpenAI／Gemini 接口格式 | `settings.set`：`danmaku.spoilerAiApiFormat` | [setSpoilerAiApiFormat:565](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:565) |
| 修改防剧透温度 | `settings.set`：`danmaku.spoilerAiTemperature` | [setSpoilerAiTemperature:561](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_subtitles.dart:561) |
| 改绑弹幕显隐快捷键 | `settings.set`：`shortcuts.toggle_danmaku` | [updateShortcut:1039](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:1039) |
| 改绑发送弹幕快捷键 | `settings.set`：`shortcuts.send_danmaku`；不代表能发送 | [updateShortcut:1039](~/Desktop/NipaPlay-Reload/lib/utils/hotkey_service.dart:1039) |
| 显示／隐藏顶部发送弹幕按钮 | `settings.set`：`player.topSendDanmakuButtonVisible` | [外观设置回调:209](~/Desktop/NipaPlay-Reload/lib/settings/pages/appearance_settings_content.dart:209) |
| 设置截图是否包含弹幕 | `settings.set`：`player.screenshotIncludeDanmaku` | [存储设置回调:203](~/Desktop/NipaPlay-Reload/lib/settings/pages/storage_settings_content.dart:203) |
| 开关外部播放器弹幕外挂偏好 | `settings.set`：`player.externalDanmakuOverlay` | [_toggleDanmakuOverlay:350](~/Desktop/NipaPlay-Reload/lib/settings/pages/external_player_settings_content.dart:350) |
| 设置是否自动切换弹幕控制台 | `settings.set`：`player.externalAutoSwitchToDanmakuConsole` | [设置页回调:63](~/Desktop/NipaPlay-Reload/lib/settings/pages/external_player_settings_content.dart:63) |

登录的无秘密参数路径会创建用户窗口登录任务，实际等待 `requestLogin`：[accounts/service.dart:70](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:70)、[106](~/Desktop/NipaPlay-Reload/lib/next/accounts/service.dart:106)。这符合“用户完成登录、Agent 可以发起”的要求。

**Titan 设置逐项覆盖**，均使用 `settings.set`，注册表调用 `commitTitanDanmakuSettings`：[注册实现:1740](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1740)。

| Classic 操作 | 设置键 | Classic 设置页 |
|---|---|---|
| 不透明度 | `danmaku.titan.opacity` | [895](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:895) |
| 字号倍率 | `danmaku.titan.fontSize` | [930](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:930) |
| 粗体 | `danmaku.titan.bold` | [973](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:973) |
| 描边档位 | `danmaku.titan.fontBorder` | [988](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:988) |
| 字体族 | `danmaku.titan.fontFamily` | [1015](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1015) |
| 速度加成 | `danmaku.titan.speedPlus` | [1038](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1038) |
| 密度 | `danmaku.titan.density` | [1056](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1056) |
| 轨道间距 | `danmaku.titan.trackGap` | [1074](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1074) |
| 基准时长 | `danmaku.titan.duration` | [1092](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1092) |
| 同屏上限 | `danmaku.titan.limit` | [1110](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1110) |
| 防挡字幕 | `danmaku.titan.preventShade` | [1131](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1131) |
| 顶部像素偏移 | `danmaku.titan.offsetTop` | [1147](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1147) |
| 底部像素偏移 | `danmaku.titan.offsetBottom` | [1166](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1166) |
| 最大长度 | `danmaku.titan.maxLength` | [1185](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1185) |
| DOM 回收 | `danmaku.titan.isRecyclingDom` | [1206](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1206) |
| 模型回收 | `danmaku.titan.isRecyclingModel` | [1222](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1222) |
| 禁止收缩状态 | `danmaku.titan.forbidShrinkState` | [1238](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1238) |

**内置弹幕过滤插件的管理入口覆盖：**

| Classic 操作 | 能力 id／设置键 | Classic 依据 |
|---|---|---|
| 查看内置过滤插件状态和配置入口 | `plugins.list` | [插件设置页:565](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:565) |
| 启停内置敏感词过滤插件 | `plugins.set_enabled(id=builtin.cn_sensitive_danmaku_filter)` | [插件启用注册:783](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:783) |
| 启停内置正则过滤插件 | `plugins.set_enabled(id=builtin.cn_danmaku_regex_filter)` | [插件启用注册:783](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:783) |
| 查看／修改每条内置正则规则开关 | `settings.get/set`：`plugins.settings.builtin.cn_danmaku_regex_filter.<ruleId>` | [Classic 开关回调:655](~/Desktop/NipaPlay-Reload/lib/settings/pages/plugin_settings_content.dart:655) |

最后一项的 `ruleId` 为 `repeat`、`rewatch`、`date`、`anyone`、`group`、`keyword`：[规则声明:17](~/Desktop/NipaPlay-Reload/assets/plugins/builtin/danmaku_regex_filter.js:17)。它们是 switch，走动态设置注册表 [classic_settings.dart:813](~/Desktop/NipaPlay-Reload/lib/next/settings/classic_settings.dart:813)，不是 `plugins.invoke` 的普通 Action。

## 4. 反方向的风险

### 4.1 Next 新挂载绕过 Classic 的加载事件过滤阶段

第 2.9 节的调用链差异可以确定：Next 新挂载不发 `danmakuLoaded`，没有执行 Classic 加载路径中的事件驱动替换阶段。

实际受影响程度取决于启用的插件。**静态词／正则过滤仍执行，不能扩大为“所有屏蔽均被绕过”。**

### 4.2 Agent 能删除 Next 管理的新 Dandanplay 轨道，Classic 菜单没有该删除入口

Classic 菜单只对本地来源显示删除按钮：[danmaku_tracks_menu.dart:277](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_tracks_menu.dart:277)，传统 `removeDanmakuTrack` 也保护 `dandanplay`：[实现:1447](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1447)。

Next 的 `danmaku.detach` 没有来源限制；新 Next 在线轨道挂载为 `origin=binding`、`usesMediaTimeline=true`，会进入实际删除分支：

[player_port.dart:174](~/Desktop/NipaPlay-Reload/lib/next/danmaku/player_port.dart:174) → [removeSourceDanmakuTrack:1480](~/Desktop/NipaPlay-Reload/lib/utils/video_player_state/video_player_state_danmaku.dart:1480)。

范围限定为**新 Next 管理轨道**；复用的 Classic `auto_remote` 轨道只剥离绑定，不删除。

### 4.3 设置参数可超出 Classic GUI 的选择范围

| 参数 | Classic GUI | Next 注册表 |
|---|---|---|
| 普通字号 | 12～60；[设置页:954](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:954) | 0～100；[注册:1178](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1178) |
| Titan 同屏上限 | 最大 1000；[设置页:1110](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1110) | 最大 5000；[注册:1876](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1876) |
| Titan 顶／底偏移 | ±100；[设置页:1147](~/Desktop/NipaPlay-Reload/lib/settings/pages/danmaku_settings_content.dart:1147) | ±1000；[注册:1927](~/Desktop/NipaPlay-Reload/lib/next/settings/application_settings.dart:1927) |

这些是实际允许传入服务的值，并非仅描述文本不同。这里确认的是 GUI 操作范围差异，不据此推断必然产生渲染故障。

### 4.4 空文件导入可覆盖既有池，而 Classic 手动导入拒绝空池

Classic 手动导入使用默认 `allowEmpty=false`，空池报错：[local_danmaku_file.dart:28](~/Desktop/NipaPlay-Reload/lib/utils/local_danmaku_file.dart:28)、[114](~/Desktop/NipaPlay-Reload/lib/utils/local_danmaku_file.dart:114)。

Next 导入显式使用 `allowEmpty=true`，允许返回空 entries：[import.dart:15](~/Desktop/NipaPlay-Reload/lib/next/danmaku/import.dart:15)，同身份重导随后替换既有绑定池：[store.dart:113](~/Desktop/NipaPlay-Reload/lib/next/danmaku/store.dart:113)。

因此，Agent 可以通过普通 `danmaku.import` 把同身份池替换为空；该操作没有专门的空池确认阶段。

**本次没有发现有证据的“绕过 Classic 弹幕删除二次确认”。** 本地轨道删除与立即清缓存原本就是直接执行。Next `cache_delete` 的 destructive HTTP 入口还要求 `execute=true`，否则返回 preview：[agent_endpoint.dart:297](~/Desktop/NipaPlay-Reload/lib/next/agent_endpoint.dart:297)。

## 5. 没能审完／待确认的部分

- **平台运行效果未验证。** 没有运行应用，因此 GPU、DFM+、Next、Titan、Erika 的即时渲染、登录窗口实际展示、网络返回及外部 ASS 重载，只确认静态调用链，不宣称运行测试通过。
- **额外安装的第三方插件未逐个审计。** 通用启停、非秘密配置和普通 UI Action 入口存在，但其自定义脚本、WebView 交互及额外操作不能据此全部判为覆盖。依赖加载事件的插件是否正在使用、实际影响多大，待确认。
- **密度图内容的 Agent 可读性待确认。** 开关已覆盖；Classic 根据当前弹幕生成并平滑密度曲线：[danmaku_density_bar.dart:39](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/danmaku_density_bar.dart:39)。Next 没有返回这条曲线的视图。是否能通过现有截图能力取得等价图形，需要验证截图捕获范围，不能仅凭 `playback.screenshot` 存在就判为覆盖。
- **Bilibili／AcFun 在线来源不列为缺失。** 当前 Classic 对应菜单项只是占位展示，没有可执行加载回调：[cupertino_danmaku_tracks_pane.dart:139](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_tracks_pane.dart:139)。它们不是本次可确认的 Classic 用户操作。