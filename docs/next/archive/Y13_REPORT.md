# Y13：把 X60 的能力接到 Next 界面

2026-10-15～16，worktree `y13-wire-x60`，分支 `next/y13-wire-x60`。没有 commit、push。只改了 `lib/next/ui/` 和界面测试，没有改 `ui_data/`、能力层、Classic 和依赖；宿主设置只接了秘密设置和远程访问，没有碰 Nipa 一节的模型界面（X61 在改）。所有调用都经 harness，使用 `Invocation(origin: 'gui')`，沿用 `GuiCalls` 和各适配层。

做法：五位实现者按区域并行（记录/收藏/任务、下载/来源搜索、设置、单部作品管理、片库批量），各自只改自己的文件；随后四位核对者依次在唯一的 `y13-dev` 实例上截图、修视觉问题；最后主控在真实模式下截了只读状态，并跑了完整测试。

## 1. 对照 X60 第 3 节接线表

| 接线点 | 接上了什么 | 截图 |
|---|---|---|
| NextCollections.works | 读完所有 `nextCursor`，空页也继续读；`media.bindings` 同样按游标翻页。只认作品层、已确认的绑定，同一部合并作品只出一次。去掉了“unavailable 当空列表”的吞异常。真实环境下拉里出现五种状态，“在看”显示了真实返回映射到的片库作品。两个账号都没登录时，状态页只有“登录 Bangumi”“登录 弹弹play”两枚按钮，登录后自动重读 | a04、a05、r01、r02 |
| 动态观看记录 | 每行左侧是剧照（没有就用海报，再没有是色块）小卡，带进度条，看完是对勾；按日期分组保留。点行进入作品（`workId`），悬停出现“继续 / 删除”；没有作品的条目点行就是继续。没有本机位置、但片库里有这一集的，用 `libraryEpisodeId` 从片库播放。删除用 `entryIds`，没有位置的条目也能删；翻页沿用游标，删掉了“删除后从头重读”的做法。删除两条再翻页：entries=108、distinct=108、more=false | a01–a03、r07 |
| 后台面板 | 用 `UiTask.type` 判断下载，删掉了 `NextDownloads.which` 和为判断类型另调 `task.list` 的逻辑。`task.list` 只在“动态 › 下载”列表里取时间和状态 | a06、a07 |
| 同步 | 用 `sync.status.hasPassword`：已保存时显示“已登录”，按钮为“重新登录”；未保存时显示琥珀色“需要登录”。删掉了只在本页记着的 `_relogin`。改地址或用户名后清掉测试结果并重读，清凭据由能力层完成 | c01、c02、r05 |
| 来源搜索 | 作品行用海报，剧集和文件行用 16:9 图。`poster` 为空的行在出现时懒调用 `media.sources.artwork`，每个条目只请求一次，失败保持占位、不提示。只对 Jellyfin/Emby 调用，因为契约写明 SMB/WebDAV 没有服务器海报。`workTitle` 在文件和剧集行的副行显示；作品行只在和原名不同时显示 | b05 |
| 宿主设置 | 远程访问放在“设备”：主卡片是运行开关，有问题时显示粉点和原因；有信任设备时出现“信任的设备”，移除要点两次；随 NipaPlay 启动、端口、IPv6、接受遥控放在“高级”。两个 key 都只写，只显示“已设置”，回车替换，“清除”要点两次（传空串，另一个传 null）。TMDB key 在“账号”底部；防剧透 key 在“弹幕与字幕 › 更多 › 防剧透”，标题是“防剧透 AI API key”。搜索“tmdb”“防剧透”“key”能搜到并直接修改。宿主抛 `UnsupportedError` 时这些都不显示。真实环境接的是 `runtime.hostSettings`，假数据世界的宿主设置实现了 `NextHostDeviceSettings` | c03–c10、c17、r03、r04 |
| 多作品管理 | 片库多选：卡片右键菜单有“选择 / 全选”，⌘/Ctrl 点击逐个选，Shift 连选；选中的卡片是粉色描边加勾；底部玻璃操作条有数量、全选、刷新资料、匹配、解除匹配和 ×，Esc 退出。**批量刷新**：先列出将刷新的作品，确认后执行 `refresh_batch`，再逐部用 `task.get` 显示勾或失败短语。**批量匹配**：每部作品按名字搜候选，默认取第一个，可以换候选、换名重搜、跳过，也能切换提供方。文件按集号对到候选剧集，预览每部一行，薄荷色勾表示对上几集，粉色叉表示没对上几集。确认后带 `expectedPlan` 执行，冲突时只重新预览还没执行的部分。**批量解除**同样先预览 | e01–e11 |
| 标题恢复 | 剧集标题被改过时，旁边有“恢复”，调 `override_batch(... value:null, mode:"clear")` | d04 |
| 远端管理 | `media.management.targets` 拿到拥有者的原始 ID：本机直接调用，别的设备经 `mesh.invoke` 执行。设备名取自 `state.query mesh.devices`。离线显示“旧笔记本不在线”这类短语。单部管理和批量用的是同一份拥有者解析（新文件 `data/work_owners.dart`） | d08、d09、e03、e11 |
| 文件定位 | 改走 `media.files.reveal {paths}`，逐项看 requested/error，失败显示“没能打开”。按钮名随设备系统变化（在 Finder 中显示 / 在资源管理器中显示 / 打开所在文件夹）。删掉了直接执行 `open -R` 的做法 | d05、d10 |
| 下载删除 | “只移除任务”调 `download.remove`；“连同文件删除”交给 `withDecisions`，执行能力层给的选项。得到的 disk_deletion 任务不会被当成下载打开。确认里写“删除 N 个文件”，下面列出文件夹或文件名（超过 4 项时显示前 3 项加“…”） | b03、b04、a08 |
| 插件/记忆 | 插件行展开后，每个动作是一个按钮，插件关闭时不可点；执行走 `withDecisions`，结果显示标题和文字，失败时名字旁有红点。“Nipa 记得的事”跟随 `core.uiData.changes` 重读，连续变化合并成一次 | c11–c14 |

第 1 节表里的其他条目：

- **种子预览**：本地 .torrent、`file://` 和 HTTP(S) 种子地址都会先 `download.preview`，可以勾选文件。换了输入就清掉旧预览。认不出时显示“认不出这个文件 / 链接”，“下载”按钮变灰。截图：b01、b02。
- **设置显示名**：注册表给字号用的是 `valueNames`，不是 `enumNames`。现在 `UiSetting` 两者都解析，字号 0 显示“设备默认”。删掉了 `settings_layout.dart` 里已被注册表覆盖的过渡值名表。截图：c16。
- **扫描标题、任务关联作品已不存在**：只改了后端，界面不用动。
- **Mesh 写入不再需要额外审批**：界面不受影响。

## 2. 决策

- **观看记录的点击**：点行进入作品，和首页“继续观看”一致；悬停时的按钮负责继续播放。
- **取消收藏没有做**。Bangumi 没有删除接口。两个账号都登录时，取消只能清掉弹弹play，而面板以 Bangumi 的状态为准，看起来就像去不掉。
- **下载删除的确认**：能力层问题文字里嵌着清单 JSON，适配层从中整理出“删除 N 个文件”和名字。选项原样执行。删除这一步用 `chooseSheet` 显示，没有用通用的 `decisionSheet`，因为后者不能在标题下再加一行。
- **按钮组件**（`settings/controls.dart` 的 `PillButton`）：
  - 禁用时整体淡到 0.4；
  - 宽度改为按文字取宽，作品管理、批量浮层、下载列表都看过，没有变丑；
  - 忙碌时的三个点改为深色，原来是白点画在白底上。
- **跳到折叠的设置**：跳过去后分组保持展开。原来高亮褪去后分组会自动收起，要找的那一项就不见了。
- **单部作品的匹配**：先按预览的计划执行解除，执行时再对绑定预览一次，用新的计划执行，因为绑定的计划要等解除完成才拿得到。
- **作品在几台设备上**：资料、剧集标题、匹配和清除覆盖会改到所有在线的拥有者设备；更换图片只改本机。只在别的设备上的作品，凡是要从本机选文件的操作都隐藏，因为契约不允许把本机路径发给另一台设备。
- **批量匹配要对到剧集**：只在作品层绑定，剧集和文件不会自动对上，依据是 `identity_store.dart:1291/1298` 和 `media_service.dart:672`。后端也没有“按作品自动对集”的 Action，`media.identify` 已在迁移中删除。所以照单部匹配的方式，用 `media.metadata.get` 读候选剧集，按集号（必要时按季）对应，对不上的集不绑定，并在预览里显示出来。逐集手动调整仍在单部作品管理里做。
- **文案**：去掉了批量预览底部的“文件和观看进度保留”（读起来像安慰话），统一为“条进度”。记录、收藏、来源、管理里都没有出现 ID。

## 3. 截图清单（`docs/next/evidence/y13/`，只截本实例窗口）

假数据世界的截图都在 10-15 23:57 之前拍完，早于 `/tmp/nipa-next/visual/tmdb` 被清理（目录修改时间是 10-16 00:00），所以都是完整的假数据场景，不用补拍。

| 文件 | 内容 |
|---|---|
| a01-history / a02-hover / a03-hover-unlisted | 带剧照/海报的观看记录；悬停“继续 / 删除”；未入库条目（无图，用文件名） |
| a04-status-wish / a05-status-signedout | 按状态看“想看”；两个账号都没登录 |
| a06-tasks-popover / a07-activity-now | 后台面板；进行中，展开容量 |
| a08-deletion-waiting | 请求删除后多出的删除任务（拍的时候任务标题还是旧的假数据标题，后来已改成真实的“等待你确认删除”） |
| b01-torrent-preview / b02-torrent-bad | 种子文件预览、选文件；认不出的种子 |
| b03-delete-ask / b04-delete-files | 删除二选一；能力层的文件清单确认 |
| b05-search-sources / b06-downloads-list | 来源搜索的海报、16:9 图、作品名；下载列表（顶部按钮已对齐） |
| c01-sync-saved / c02-sync-login | 同步已保存密码；需要登录 |
| c03-remote-trusted / c04-remote-problem / c05-remote-advanced / c06-remote-unsupported | 远程访问和信任设备；有问题；高级项；宿主不支持 |
| c07-spoiler-key-set / c08-search-spoiler / c09-tmdb-key / c10-search-tmdb / c17-keys-unset | 防剧透 key 已设置；搜“防剧透”（拍于改标题之前）；TMDB key；搜“tmdb”；两个都未设置 |
| c11-plugin-actions / c12-plugin-result / c13-plugin-failed / c14-plugin-confirm | 插件动作；结果；失败；确认 |
| c15-pill-disabled / c16-fontsize-default | 主按钮禁用态；字号“设备默认” |
| d01-unmatch-preview / d02-match-preview / d03-conflict-repreview | 解除、换匹配的影响卡片；冲突后重新预览 |
| d04-episode-title-restore | 剧集标题“恢复” |
| d05-all-locations / d06-locations-offline / d07-remote-delete-confirm | 按设备分组的全部位置；工作站离线；“从工作站删除？” |
| d08-remote-work / d09-offline-work / d10-reveal-failed | 工作站上的作品；离线设备上的作品；定位失败 |
| e01-grid-select / e02-menu / e10-shelves-select | 网格多选和操作条；右键菜单；书架多选 |
| e03-refresh-list / e04-refresh-result | 批量刷新列表（含离线行）；结果：2 部成功，3 部失败 |
| e05-match-candidates / e06-match-preview / e07-match-conflict / e09-match-done / e11-match-offline | 候选；对上/没对上；冲突后重新预览；完成；工作站离线时 |
| e08-unmatch-preview | 批量解除的预览（e06、e08 底部的“文件和观看进度保留”拍完后已经删掉） |
| r01-library-statuses / r02-library-doing | 真实模式：下拉出现五种状态；“在看”列出真实返回映射到的作品 |
| r03-devices-remote / r04-keys-search / r05-sync / r06-plugins / r07-history | 真实模式：远程访问（Classic 接收端的真实状态）；两个 key 未设置；同步；两个内置弹幕插件（没有动作，所以没有入口）；观看记录为空，没有报错 |

真实模式只做了读取，没有写 key、改远程访问、同步、收藏或删除。

## 4. 验证

- `flutter analyze --no-pub lib/next/ui` 加上各个界面测试文件：没有问题。`git diff --check` 通过。
- 各区域分别跑过受影响的测试：
  - ui_history 5、ui_collections 14、ui_downloads 10、ui_search 12；
  - ui_settings 和 ui_upkeep 共 19；
  - ui_manage 12；
  - ui_batch 6、ui_library 4。
  - 新增的 `ui_batch_test.dart` 守住这些约束：`origin: gui`、entries 的形状、`expectedPlan` 原样带回、冲突后重新预览、按设备分组。
- 完整 `flutter test --no-pub test/next`（排队、去掉代理）：647 个通过，7 个跳过，0 个失败。
- 实例日志里没有新的 overflow 或未处理异常。
- **意外**：
  1. 真实模式第一次启动用的是旧构建，核对阶段的修改只热重载到了假数据实例上。截图里看出来后，重新构建并重拍了 r01–r07。
  2. 截图脚本偶尔会截到实例冒出的一个 1000×1000 空白窗口，原因没查出来，重拍就好。正式截图都确认过是主窗口。
  3. 批量核对者重启实例后，几次看到前台是 NipaPlay。我们没有激活过窗口，不确定是不是启动引起的；之后检查前台都是别的应用。

## 5. 接不上的及原因

1. **Bangumi 取消收藏**：后端没有接口，见第 2 节。
2. **等待确认的任务显示成“已暂停”，还带继续按钮**：`ui_data` 把 waitingUser/needsDecision 映射成 paused，`UiTaskState` 没有“等你确认”这个状态。点这一行仍能正常弹出它的问题。这要改 `ui_data`，不在本任务范围。
3. **下载删除**：
   - 能力层的问题文字里嵌着 JSON，界面只能解析它；
   - 真实执行时还会弹出应用自己的同意窗口（Material AlertDialog，正文也带原始 JSON），风格和 Next 不一致。
   这两处都在后端。
4. **共享来源的作品**（`source-work:`）不能批量管理，显示“在共享来源里”；假数据里没有这种作品，演示不了。
5. **离线设备上的文件**：`files.list` 需要对方在线，所以列不出路径，只显示“X 不在线”。
6. **来源图片懒加载失败**：假数据的来源结果都带图，实例上演示不了，代码路径和测试都在。
7. **Esc、⌘ 点击、Shift 连选**：按安静规则不能用键盘鼠标，实例上没有实测，只用调试操作走了同样的选择逻辑。
8. **远程访问出问题时文字重复**：标题“远程访问”下面又写“远程访问服务未能启动”。这句来自后端 `classic_host_device_settings.dart`，建议改成“未能启动”。

## 6. 需要主控决定的问题

1. 只登录弹弹play、或作品只关联弹弹play时，要不要支持“再点一次已选状态就取消”？
2. 观看记录点行进作品、悬停按钮负责继续（Y12 第 4 问），这样可以吗？清空时还要不要同时带 animeIds（沿用原来按作品删除的语义）？
3. TMDB key 放在“账号”还是“网络”？
4. 下载删除要过三道（二选一、文件清单、应用同意窗口）。要不要请后端给一句人话加结构化清单，并把同意窗口改成 Next 的样式？
5. “等你确认”要不要成为单独的任务状态（需要改 `ui_data`）？
6. 作品在多台设备上时，文字和匹配写到所有在线的拥有者设备、图片只写本机，这个策略可以吗？
7. 匹配是“解除 + 绑定”两步。要严格按同一份预览执行，需要后端提供合并预览。
8. 远端文件的“在 Finder/资源管理器中显示”会在那台设备上打开窗口，而人并不在那台电脑前。这个按钮要保留吗？
9. 批量匹配在界面上按集号给出默认对应，再让人看预览确认。可以接受吗？还是希望后端提供按作品对集的原语？
10. 记忆随 `uiData.changes` 重读，下载进行中会频繁触发（已合并成同时只读一次）。要不要请后端加更窄的记忆变化通知？

## 7. 收尾

- 实例和 attach 进程已按进程号退出；`y13-dev` 已删除；`macos/Podfile.lock` 已用 `git checkout` 恢复。
- 临时脚本在 `/tmp/nipa-next/y13/`：`build.sh`、`launch.sh`、`launch-real.sh`、`attach.sh`、`reload.sh`、`save.sh`、`quit.sh`、`nx`。
- 完整测试：排队、去掉代理后跑了一次完整的 `flutter test --no-pub test/next`，**647 个通过，7 个跳过，0 个失败**，用时 1:54。`host_settings_test` 这次没有超时。日志在 `/tmp/nipa-next/y13/test-all.log`。
