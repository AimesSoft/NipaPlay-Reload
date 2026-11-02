**结论：没有完全覆盖。** 常规添加、暂停恢复、做种、播放和下载设置已有能力；但完成任务删除后重新下载、打开文件夹、取消进行中的预览仍有缺口，本地种子的同名文件夹行为也与 Classic 不一致。删除能力还绕过了 Classic 的确认流程。

审计分支为 `next/capability-layer`。仅读取源码，未修改文件、未构建或运行应用、未执行测试。下列结论区分“完成同一业务操作”和“改变 Classic 当前界面”；读取数据不等于修改界面。

**相关能力清单**

| 类型 | 已注册内容 | 代码依据 |
|---|---|---|
| 下载 Action | `download.add`、`download.set_paused`、`download.pause`、`download.resume`、`download.read`、`download.import`、`download.remove`、`download.delete` | [download_capability.dart:75](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_capability.dart:75) |
| 预览、目录 Action | `download.preview`、`download.directories`、`download.forget_directories` | [download_metadata_capability.dart:9](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_metadata_capability.dart:9) |
| 下载播放 Action | `download.play`，参数为 `jobId`、`fileIndex` | [download_playback_capability.dart:27](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_playback_capability.dart:27) |
| 公共辅助 Action | `task.list/get/wait/cancel`；`state.describe/query`；`settings.describe/get/set/reset/history`；`ui.open`；`playback.authorize_directory` | [tasks/actions.dart:3](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/tasks/actions.dart:3)、[state/query.dart:553](~/Desktop/NipaPlay-Reload/lib/next/state/query.dart:553)、[settings/capability.dart:64](~/Desktop/NipaPlay-Reload/lib/next/settings/capability.dart:64)、[ui_open.dart:21](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:21)、[playback_controls_capability.dart:177](~/Desktop/NipaPlay-Reload/lib/next/capabilities/playback_controls_capability.dart:177) |
| 状态视图 | `downloads`：持久化任务与历史回执，关联 `task_events`；辅助视图有 `tasks`、`task_receipts`、`history.entries`、`settings.changes` | [views.dart:481](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:481)、[views.dart:533](~/Desktop/NipaPlay-Reload/lib/next/state/views.dart:533) |
| 下载设置注册表 | `download.enabled`、`download.createFolderForTask`、`download.autoScanCompletedTasks`、`download.directory` | [download_settings.dart:49](~/Desktop/NipaPlay-Reload/lib/next/settings/download_settings.dart:49) |

上述下载能力确实进入注册链：[next_core.dart:160](~/Desktop/NipaPlay-Reload/lib/next/next_core.dart:160)；`download.play` 在 GUI runtime 注册：[next_runtime.dart:209](~/Desktop/NipaPlay-Reload/lib/next/next_runtime.dart:209)。

实际执行链为 Classic 页面／Action → `DownloadRuntime` 或 `DownloadService` → `BuiltinDownloadBackend` → `TorrentDownloadService` → Rust `torrent_*`／librqbit。当前应用配置的是内置后端：[service_provider.dart:39](~/Desktop/NipaPlay-Reload/lib/providers/service_provider.dart:39)。

**1. 缺失——按用户影响排序**

1. **完成任务移除或删除文件后，重新添加同一内容。**

   Classic 用户可以再次通过“添加链接”或“选择种子”进入原生添加流程：[torrent_download_page.dart:218](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:218)、[torrent_download_page.dart:288](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:288)。原生添加发生在历史任务收养之前：[download_runtime.dart:138](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_runtime.dart:138)。

   Agent 的 `download.add` 则先按后端和 infoHash 去重，**遇到历史 `succeeded` 任务直接返回，没有先确认下载会话是否仍存在**：[download_service.dart:40](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_service.dart:40)。`remove/delete` 对已结束任务不会改变这个成功状态：[download_service.dart:208](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_service.dart:208)。

   因此，“成功下载 → 删除任务和文件 → 再次下载同一内容”会返回旧成功任务，不重新下载。没有找到强制重加或重新创建该下载任务的 Action。

2. **在桌面文件管理器打开任务文件夹。**

   入口为任务卡片／列表“打开文件夹”、电视操作按钮，以及手机任务菜单的“查看文件夹”；Classic 方法为 `_openTaskFolder`。桌面实际调用 `FolderOpener.open`：[torrent_download_page.dart:363](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:363)。

   Agent 可以用 `download.read` 获得路径，但没有打开文件管理器的能力。`ui.open.path` 进入的是播放流程：[ui_open.dart:109](~/Desktop/NipaPlay-Reload/lib/next/capabilities/ui_open.dart:109)。

   手机入口只显示路径，这部分信息已覆盖；桌面打开文件夹的效果缺失。

3. **取消正在解析的磁力预览。**

   Classic 在添加对话框关闭、取消，或修改磁力文本时，取消当前 `TorrentPreviewRequest`：[torrent_download_page.dart:1200](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1200)、[torrent_download_page.dart:1316](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1316)。取消最终进入原生 `torrentCancelPreview`：[torrent_download_service.dart:669](~/Desktop/NipaPlay-Reload/lib/services/torrent_download_service.dart:669)。

   `download.preview` 不返回请求句柄或 `jobId`，只在调用结束的 `finally` 中释放预览：[download_metadata_capability.dart:104](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_metadata_capability.dart:104)。没有预览取消 Action；`task.cancel` 只能取消任务引擎中的任务，不能取消这次独立预览调用。

4. **切换下载页卡片／列表显示。**

   Classic 工具栏、电视工具栏和手机页面菜单均能切换；实际方法为 `_toggleViewMode`：[torrent_download_page.dart:375](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:375)。手机菜单入口见 [cupertino_torrent_download_controls.dart:45](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_torrent_download_controls.dart:45)。

   `_viewMode` 是页面局部状态，没有对应 Action、状态视图字段或设置注册项。

**2. 部分覆盖**

1. **本地 `.torrent` 添加：已知路径可添加，但文件选择入口和同名文件夹行为不等价。**

   Classic“选择种子”先打开 `.torrent` 文件选择器，再选择下载目录：[torrent_download_page.dart:260](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:260)。Agent 有 `download.add.source`，但没有发起该种子文件选择器的 Action。

   更直接的行为差异是文件夹命名：Classic 将原始种子路径传给 Rust，Rust 用种子文件名去后缀作为文件夹名：[torrent_download_service.dart:357](~/Desktop/NipaPlay-Reload/lib/services/torrent_download_service.dart:357)、[torrent.rs:258](~/Desktop/NipaPlay-Reload/rust/src/api/torrent.rs:258)。

   Next 先将本地种子缓存为 `<infoHash>.torrent`：[download_source.dart:105](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_source.dart:105)，随后把缓存路径传给同一添加方法：[builtin_download_backend.dart:46](~/Desktop/NipaPlay-Reload/lib/next/downloads/builtin_download_backend.dart:46)。所以开启 `createFolderForTask` 时：

   - Classic：`作品合集.torrent` → `作品合集/`
   - Agent：同一文件 → `<infoHash>/`

   `download.add` 没有独立的文件夹名称参数。Agent 可自行拼出目标目录并关闭自动创建，但默认“创建同名文件夹”行为没有保持一致。

2. **预览、重新预览、预览后确认添加：不能复用同一次预览。**

   `download.preview` 已覆盖名称、建议文件夹名、总大小和逐文件信息；再次调用可重新预览。

   Classic 确认添加时会消费刚才的 `preview.requestId`：[torrent_download_page.dart:218](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:218)。Next 预览结束即释放句柄，`download.add` 也没有 `previewId` 参数：[download_metadata_capability.dart:126](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_metadata_capability.dart:126)、[download_capability.dart:141](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_capability.dart:141)。

   所以 Agent“看过预览后添加”会重新解析，不能复用 Classic 已完成的那次预览。

3. **任务搜索、清空搜索、四种排序：能处理返回数据，不能改变 Classic 列表。**

   Classic 搜索匹配任务名、路径、显示状态和扫描结果；排序支持最近添加、名称、进度、状态：[unified_torrent_page_model.dart:219](~/Desktop/NipaPlay-Reload/lib/downloads/unified_torrent_page_model.dart:219)。页面方法为 `_updateSearchQuery`、`_applySort`：[torrent_download_page.dart:240](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:240)。

   Agent 可通过 `task.list`、批量 `download.read` 获取数据后筛选排序；`state.query` 也有过滤与排序，但 `downloads` 视图是持久化任务投影，没有原生实时状态、速度等完整列表字段。

   缺的是：设置／清空 Classic 搜索框、改变当前排序，以及读取当前搜索词和排序选项。没有对应注册入口。

4. **查看当前入库摘要和扫描标记：历史证据可读，当前完整状态未提供只读接口。**

   Classic 显示“正在加入媒体库”、作品／剧集摘要、“已加入媒体库”或“未匹配到番剧信息”，依据当前扫描阶段、历史记录和 `autoScannedKeys`：[torrent_download_page.dart:446](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:446)、[torrent_download_page.dart:547](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:547)。

   Agent 有任务阶段、历史回执、`history.entries`；但 `download.read` 返回的实时 task 不做当前入库状态查询：[download_service.dart:142](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_service.dart:142)。也没有公开当前任务扫描标记或 Classic 摘要的专门字段。

   `download.import` 会返回新的识别结果，但会执行扫描并写扫描标记，不能作为纯读取的替代：[download_service.dart:147](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_service.dart:147)。

5. **最近目录管理：可读、可删除、可用于添加，但不能只“记住目录”。**

   Classic 添加对话框选择新目录后，立即写入最近目录；之后即使取消添加，该记录仍保留：[torrent_download_page.dart:1206](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1206)。

   Next 的 `download.directories` 和 `download.forget_directories` 已覆盖读取、删除；`download.add.downloadDirectory` 可使用指定目录。但没有只记住一个最近目录的 Action。通过 `settings.set(download.directory)` 记住目录会同时改变默认目录：[download_settings.dart:85](~/Desktop/NipaPlay-Reload/lib/next/settings/download_settings.dart:85)。

6. **对话框取消选项：业务上的放弃可表达，现有弹窗关闭未覆盖。**

   尚未提交时，Agent 可以不调用 `download.add/play/delete` 来放弃操作；但没有关闭当前 Classic 添加、播放文件选择、删除确认等弹窗的能力。

   Classic 取消入口分别见 [torrent_download_page.dart:1351](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1351)、[desktop_torrent_download_dialogs.dart:97](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/desktop_torrent_download_dialogs.dart:97)、[desktop_torrent_download_dialogs.dart:20](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/desktop_torrent_download_dialogs.dart:20)。进行中的预览取消另列为缺失。

**3. 已覆盖——一行一个操作**

以下只列已经覆盖的业务效果；相关限制见前两节。

| Classic 用户操作及位置 | 对应能力 |
|---|---|
| 进入下载 Tab／页面 | `ui.open`，`page:"torrent"`；[AppPageIds:8](~/Desktop/NipaPlay-Reload/lib/app/app_page_ids.dart:8) |
| 查看任务列表、发现下载任务；[页面初始化:131](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:131) | `task.list`，`type:"download"`；或 `state.query(view:"downloads")` |
| 刷新、读取任务最新原生状态；[刷新:175](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:175) | `download.read`，支持 `jobId/jobIds`；这是数据刷新，未提供强制重绘页面入口 |
| 查看名称、目录、进度、已下载／总大小、下载／上传速度、状态和错误；[任务卡片:1922](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1922) | `download.read` |
| 磁力对话框“预览”，查看名称、总大小、建议文件夹与文件路径／大小；[预览:1235](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1235) | `download.preview` |
| 提交一个新磁力下载；[添加:218](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:218) | `download.add` |
| 为新任务指定下载目录；[确认结果:1298](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1298) | `download.add.downloadDirectory` |
| 发起 Classic 目录选择／授权；[选择目录:1206](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1206) | `playback.authorize_directory`，复用同一 `FilePickerService.pickDirectory`；目录由用户在系统选择器中选定 |
| 查看最近目录，并选择已有目录供新任务使用；[最近目录:189](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:189)、[选择:1216](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1216) | `download.directories` ＋ `download.add.downloadDirectory` |
| 从最近目录列表删除一项；[删除最近目录:1227](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1227) | `download.forget_directories` |
| 磁力对话框切换“为任务创建独立文件夹”；[开关:1329](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1329) | `download.add.createFolderForTask` |
| 将本次目录、创建文件夹选项保存为以后默认值；[保存:210](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:210) | `settings.set`，键为 `download.directory`、`download.createFolderForTask`；单次 `download.add` 本身不保存这些默认值 |
| 暂停下载；[任务切换:333](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:333) | `download.set_paused(paused:true)`／`download.pause` |
| 恢复下载；同上 | `download.set_paused(paused:false)`／`download.resume` |
| 错误任务“重试”；[重试判断:103](~/Desktop/NipaPlay-Reload/lib/models/torrent_task.dart:103) | `download.resume`，服务对原生错误调用恢复；[实现:202](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_service.dart:202) |
| 暂停做种；[做种按钮标签:107](~/Desktop/NipaPlay-Reload/lib/models/torrent_task.dart:107) | `download.pause`／`download.set_paused` |
| 继续做种；同上 | `download.resume`／`download.set_paused` |
| 移除任务、保留文件；[移除:342](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:342) | `download.remove` |
| 删除任务及文件；[删除:350](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:350) | `download.delete`；执行效果覆盖，确认流程见第 4 节 |
| 查看可播放视频文件并选定其中一个；[文件选择:456](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:456) | `download.read.files` ＋ `download.play.fileIndex` |
| 播放未完成任务；[播放:480](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:480) | `download.play`，复用 Classic 流式播放 |
| 播放暂停中的未完成任务，并自动恢复下载；[自动恢复:472](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:472) | `download.play` |
| 播放已完成文件，包括尚未识别入库的文件；[播放源:258](~/Desktop/NipaPlay-Reload/lib/services/torrent_download_service.dart:258) | `download.play`，复用 Classic 磁盘／历史解析 |
| 设置页“启用下载器”；[设置:37](~/Desktop/NipaPlay-Reload/lib/settings/pages/downloader_settings_content.dart:37) | `settings.get/set`，`download.enabled` |
| 设置页“下载时创建同名文件夹”；[设置:50](~/Desktop/NipaPlay-Reload/lib/settings/pages/downloader_settings_content.dart:50) | `settings.get/set`，`download.createFolderForTask`；本地种子命名差异见第 2 节 |
| 设置页“完成后自动加入媒体库”；[设置:68](~/Desktop/NipaPlay-Reload/lib/settings/pages/downloader_settings_content.dart:68) | `settings.get/set`，`download.autoScanCompletedTasks` |

手机长按／“更多”菜单复用同一组播放、暂停恢复、查看文件夹、移除和删除回调：[cupertino_torrent_download_controls.dart:245](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_torrent_download_controls.dart:245)、[菜单分发:409](~/Desktop/NipaPlay-Reload/lib/themes/cupertino/widgets/cupertino_torrent_download_controls.dart:409)。电视卡片主操作及 Enter、数字键盘 Enter、Select 激活也复用这些回调：[torrent_download_page.dart:2360](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:2360)、[large_screen_focusable_action.dart:136](~/Desktop/NipaPlay-Reload/lib/themes/nipaplay/widgets/large_screen_focusable_action.dart:136)。

所读下载界面没有发现另外的鼠标右键菜单、拖放添加、下载文件勾选、优先级或限速操作，未将它们列为 Next 缺口。

**4. 反方向的风险**

1. **`download.delete` 绕过 Classic 删除确认。**

   Classic `_deleteTask` 必须等待确认，只有 `confirm == true` 才调用删除：[torrent_download_page.dart:350](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:350)。桌面和手机均提供明确的取消／删除选项。

   Action 没有确认参数，直接进入 `downloads.remove(deleteData:true)`：[download_capability.dart:290](~/Desktop/NipaPlay-Reload/lib/next/capabilities/download_capability.dart:290)。

   两条传输路径的限制不同：

   - `/harness` JSON 调用：破坏性动作默认只预览，但调用方传 `execute:true` 即可执行；这不是用户点击确认的证明。[agent_endpoint.dart:297](~/Desktop/NipaPlay-Reload/lib/next/agent_endpoint.dart:297)
   - MCP 调用：`McpEndpoint` 构造 `McpRpc` 时没有配置动作授权回调，`tools/call` 可直接调用 Harness，没有上述 `execute` 限制。[endpoint.dart:28](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/mcp/endpoint.dart:28)、[rpc.dart:74](~/Desktop/NipaPlay-Reload/packages/nipa_harness/lib/src/mcp/rpc.dart:74)

   删除仍有文件路径边界检查和审计记录；它们没有补回用户确认。种子 harness 文档要求“删除数据等破坏性操作只在用户明确要求时执行”，但这是 Agent 行为指令：[AGENTS.md:64](~/Desktop/NipaPlay-Reload/assets/next/harness/AGENTS.md:64)，不是删除 Action 的强制确认门槛。

2. **`download.add` 可跳过 Classic“展示预览后确认添加”的步骤。**

   Classic 磁力添加按钮仅在预览完成后启用，并通过 `_confirm` 提交：[unified_torrent_page_model.dart:191](~/Desktop/NipaPlay-Reload/lib/downloads/unified_torrent_page_model.dart:191)、[torrent_download_page.dart:1298](~/Desktop/NipaPlay-Reload/lib/pages/torrent_download_page.dart:1298)。

   Agent 可直接调用 `download.add`。内置后端会内部完成元数据预览再添加，但不向用户展示预览或等待确认：[builtin_download_backend.dart:46](~/Desktop/NipaPlay-Reload/lib/next/downloads/builtin_download_backend.dart:46)、[torrent_download_service.dart:339](~/Desktop/NipaPlay-Reload/lib/services/torrent_download_service.dart:339)。

   因而元数据解析仍保留，Classic 的交互确认步骤没有保留。

**5. 没能审完的部分／待确认**

- **大种子文件兼容性待确认。** Next 明确拒绝超过 16 MiB 的本地种子：[download_source.dart:105](~/Desktop/NipaPlay-Reload/lib/next/downloads/download_source.dart:105)。Classic Dart／Rust 添加入口没有同样的显式限制，但本次没有核验 librqbit 对特定大种子文件的最终接受范围，不能据此断言所有超过 16 MiB 的有效种子 Classic 都能下载。
- **平台实际行为未实测。** 系统文件选择、macOS 目录书签、Android SAF、iOS 目录限制及真实网络预览只沿源码检查；依照只读要求，没有运行应用或测试。
- **RSS、资源搜索和下载登录未发现可对照入口。** 在指定起点及相关服务调用链中，未找到 Classic RSS 订阅、种子资源检索或下载器登录流程。`SearchService` 的搜索是番剧元数据搜索，没有进入上述种子添加链，因此未将“缺少 RSS／资源搜索 Action”算作本块覆盖缺失。
- 除上述待确认项，指定下载界面、桌面／手机／电视入口、下载设置，以及增删、控制、预览、播放和完成扫描调用链已完成静态对照。