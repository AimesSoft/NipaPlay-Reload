# Y12：下载、来源、后台任务、观看记录和收藏

2026-10-13～14，worktree `y12-downloads-sources`，分支 `next/y12-downloads-sources`，基于 2ae4a0af。没有 commit、push；只改了 `lib/next/ui/` 和界面测试，没有改能力层、`ui_data/`、Classic 和依赖。实例只用自己的 `y12-dev`（ui-demo 的副本），按进程号操作，不激活窗口、不点像素、不动鼠标，只截自己的窗口。没有启动正式应用，没有碰别的实例、钥匙串和真实数据。

界面分四块并行做完：数据层、下载、后台面板、动态页、首次使用、弹层和调试接线由主实现者完成；观看记录页、收藏与片库、设置页接线分别交给三个子代理，各自只改自己的文件，最后统一接线、构建和截图。

## 1. 完成了什么

| 需求 | 做到的 |
|---|---|
| 下载管理 | 后台面板和“动态 › 下载”里的下载都能点开**下载详情**：进度、↓↑ 速率、连接数（已连 / 见过）、剩余时间、剩余空间、保存位置、出错原因；逐文件的勾选、进度、完成标记、播放（已完成或可边下边播）；“只要视频 / 全部”；暂停、继续；删除时让人二选一：只移除任务，或连同文件删除。**新建下载**：粘贴磁力链接、种子地址，或拖入 / 选择种子文件。磁力链接会先预览，可以在下载前选文件。目录可选默认、最近用过的或其他文件夹。下载器关闭时显示“下载已关闭”，并给出“打开”去设置。**限速**：两个方向各有预设和自定 KB/s；读回值以下载器为准。引擎不支持时显示“这个下载器不能限速”；下载器没在运行时也照实显示 |
| 后台任务 | 面板里每一项都能点：下载打开详情；等待确认的任务弹出它自己的问题，选择后执行对应选项。面板底部是“全部暂停 / 全部继续”和“动态 ›”。“动态 › 进行中”有全部暂停、全部继续、全部停止（停止要确认）。不能控制的会显示“N 个不能暂停”。折叠的“容量”里是扫描、识别、帮手三种工作：同时运行几个（圆点表示，正在跑的是薄荷色）、排队数和 ± 调整，下面是下载限速的入口 |
| 来源与文件夹 | 片库来源下拉多了“添加来源”，会深链到设置的“媒体来源”，并打开添加表单（复用 Y8 的编辑器和登录流程）。选 NipaPlay 种类时出现“附近”，列出局域网里的共享，可以一键加入。新增“本机文件夹”卡片：添加（加完自动扫描）、移除（要点两次，因为会清掉这个文件夹的观看记录）、单个扫描、全部扫描；扫描进度在后台面板里看 |
| 观看记录 | “动态 › 观看记录”：按今天、昨天、本周按星期几、更早按日期分组；每行有进度环（看完是对勾）、作品名、集名、时间。悬停时出现继续和删除；点整行也是继续。滚动时自动翻页。“清空”要确认。同一集有多个版本时，弹出让人选。空状态和出错状态都有 |
| 收藏和追番 | 详情页“问 Nipa”后面多了一枚按钮（与 ⋯ 菜单分开）。没标记时是空心书签，标记后显示“看过 ★10”。点开是玻璃小面板：五个状态、五颗星（每颗半分，对应 1–10 分），以及弹弹play、Bangumi 两个账号的同步点。选中立即写入，失败会退回原值，失败的账号点变红；没登录的账号显示“登录”。片库来源下拉里可以按五个状态看（这一项需要后端补能力，见第 4 节） |
| 设置页接线 | **存储**：可用 / 总量空间条、NipaPlay 和下载的占用；缓存分图片、弹幕、缩略图三类，每类有可回收大小和“保留 x MB”，可以分别清理。**关于**：立即检查更新，结果是有新版本（带“前往”）、已是最新或没能检查。**新分节“插件”**：已装插件的开关、版本、载入错误、更新、删除；“更多”里是市场和从文件安装。**新分节“同步”**：WebDAV 地址、用户名、同步内容、记录变化时同步、测试、登录、启用、立即同步、上次时间、错误 |
| 首次使用 | 没有模型时，Next 其他部分照常可用。只在 Nipa 所在的地方提示：顶栏头像右下角一个琥珀色小点，悬停显示“还没有模型”；头像菜单第一项是“设置 Nipa”；首页输入栏旁边、对话输入框上方各有一枚“设置 Nipa”，点了直达设置的 Nipa 一节。不弹窗，不挡路。真实模式下（ui-demo 副本没有可用模型）也确实出现了 |

## 2. 设计决定

### 界面怎么调用能力

- 新增 `data/gui_calls.dart` 的 `GuiCalls`：所有新界面都经 harness、以 `Invocation(origin: 'gui')` 调用 Action，和 Nipa 用的是同一批。
  - Completed：返回结果。
  - Failed：抛出原来的 `Failure`。
  - NeedsDecision：抛出 `DecisionNeeded`。界面用 `withDecisions` 把问题和选项原样摆出来，执行所选项（选项本身又要决定时，继续问）。
- 各领域的适配层都只做 JSON 到界面模型的转换，不做业务判断：
  - `downloads.dart`：`task.list type=download` 加 `download.*`；
  - `background.dart`：`task.control`、`task.resources`、`task.get`，容量用 `settings.set tasks.*Concurrency`；
  - `history.dart`：`state.query history.entries`、`history.remove`、`playback.open`；
  - `collections.dart`：`accounts.status`、`state.query media.bindings`、`accounts.collections.*`；
  - `upkeep.dart`：`storage.status`、`cache.plan/prune`、`app.update.*`、`plugins.*`、`sync.*`、`media.library.roots.*`、`scan_classic`、`media.sources.discover`。
- `NextUiServices` 只多了一个 `calls` 字段和几个由它派生的适配层（`services.dart` 改动集中在一处）。
- 设置页原来的 `storage()`、`clearCache()`、`checkUpdate()`（Y8 的占位）已删除，改用同一套适配层，避免出现两套。
- 后台面板原来直接调 `core.engine.pause/resume/cancel`，现在改走能力：
  - 下载用 `download.set_paused`，这样下载本身也会暂停；
  - 其他任务用 `task.control`；
  - “取消”一律走 `task.control`，下载的数据保留。

### 假数据世界

- `dev/fake_calls.dart`（`fake_world.dart` 的 part）是一套**独立的 Harness**，按真实 Action 的 JSON 形状实现了上面所有动作，并和 FakeWorld 的任务共用同一份状态。界面适配层在假数据和真实环境里走的是同一段解析代码。
- 预置了以下状态：
  - 下载：下载中、已暂停、完成、磁盘满了（出错）四种；
  - 观看记录 110 条：一条没有位置（不能播放，也不能单删），一条播放时要选版本；
  - 收藏：八部作品各有状态和评分；
  - 插件：载入出错、内置不可删、有更新；
  - 同步：已配置。
- 调试开关 `nx fake fail=<动作,…>` 让指定动作失败，`limits=on|stopped|unsupported` 切换限速状态，`ask=delete` 放一个等待确认的删除任务。出错和需要确认的状态都能演示。

### 视觉与交互

- **弹层**（`widgets/sheet.dart`）：外壳最上层只挂一个 `NextSheetLayer`。打开时窗口变暗并模糊，中间是一块玻璃面板；Esc 或点空白处关闭。用在下载详情、新建下载、限速、二选一确认和能力问题上。确认的写法沿用系统的习惯：选项排成竖列，危险的用粉色。
- **动态页**改成三个大字标签：进行中、下载、观看记录。三者都是“发生了什么”，放在一起不必新开顶栏入口。“进行中”的标签右上角带数字。
- **复杂的东西藏得深**：容量折叠在“容量”后面；限速放在下载页右上角和容量下面；文件选择只在下载详情里出现；插件市场和同步的远端文件夹、间隔放在“更多”里。
- **文案**都是名词或短句，例如“只移除任务 / 连同文件删除”“下载已关闭”“认不出这个链接”“下载器没在运行”“这个下载器不能限速”“设置 Nipa”。不出现 ID、路径之外的技术来源和说明句。下载出错时只说结论，如“磁盘满了”“没有写入权限”“找不到来源”“没能下载”。
- **收藏的状态**以 Bangumi 为准，因为它有完整的五种。弹弹play 只有关注、看完、弃坑三种，所以想看和搁置写到弹弹play 时会变成“关注”，界面不另作解释。按状态浏览时，如果 Bangumi 已登录，就只用 Bangumi 的列表，否则“想看”和“搁置”会混进“在看”。

## 3. 截图清单（`docs/next/evidence/y12/`，窗口 1280×820，只截本实例窗口）

假数据世界：

| 文件 | 内容 |
|---|---|
| 00-panel | 后台面板：下载中、已暂停、帮手；底部“全部暂停”“动态 ›” |
| 01-download-paused | 从面板点开的已暂停下载：逐文件进度、完成标记、播放 |
| 02-download-running | 下载中：↓↑ 速率、连接 21/64、剩余时间、可边下边播 |
| 03-download-video-only | “只要视频” |
| 04-delete-confirm | 删除二选一 |
| 05-new-magnet / 06-new-folders | 新建下载：磁力预览选文件；保存位置选择 |
| 07-new-bad-link / 08-new-downloader-off | 出错：认不出链接；下载已关闭 + 打开 |
| 09-added-opens-sheet | 添加后直接打开它的详情 |
| 10-limits / 11-limits-unsupported / 12-limits-stopped | 限速；引擎不支持；下载器没在运行 |
| 13-activity-now | 动态 › 进行中，容量展开 |
| 14-activity-paused-refused / 15-stop-all-confirm | 全部暂停后；全部停止的确认 |
| 16-activity-waiting-task / 17-task-decision / 18-after-decision | 等待确认的任务 → 它的问题 → 执行后 |
| 19-activity-downloads | 动态 › 下载：完成、出错（磁盘满了） |
| 20-history / 21-history-hover | 观看记录；悬停操作 |
| 22-history-resume-choice | 继续播放时选版本（NeedsDecision） |
| 23-history-clear-confirm / 24-history-empty | 清空确认；空状态 |
| 25-detail-collection / 26-collection-panel / 27-collection-set | 详情页收藏按钮；面板；改为看过 10 分 |
| 28-collection-failed | 写入失败：退回原值，两个账号点变红 |
| 29-library-sources-menu / 30-library-doing | 片库下拉：添加来源、五种状态；“在看” |
| 31-settings-add-source / 32-sources-nearby / 33-folders-scan | 深链打开添加；附近的 NipaPlay 共享；本机文件夹扫描 |
| 34-storage / 35-storage-cleared | 存储：空间条、三类缓存；清理图片后 |
| 36-about-update / 37-about-update-failed | 有新版本 1.9.4；没能检查 |
| 38-plugins / 39-plugins-market | 插件；市场 |
| 40-sync / 41-sync-test | 同步；测试连接 |
| 42-first-use-home / 43-first-use-menu / 44-first-use-panel / 45-first-use-to-settings | 没有模型：首页“设置 Nipa”和头像琥珀点；头像菜单；对话输入框上方；点后到 Nipa 一节 |

真实模式（同一实例配置，不带假数据）：

| 文件 | 观察到的真实读数 |
|---|---|
| 50-real-activity-now | `task.resources`：扫描 1、识别 4、帮手 2 |
| 51-real-downloads / 52-real-history | 这个配置里没有下载和观看记录，空状态正确 |
| 53-real-limits | `download.limits.get`：supported、会话未初始化 → “下载器没在运行” |
| 54-real-storage | `storage.status` + `cache.plan`：可用 555 GB / 926 GB，NipaPlay 3.8 MB，图片缓存 2.8 MB，弹幕与缩略图为空 |
| 55-real-about-update | `app.update.check` 实际访问 GitHub：1.11.10 已是最新 |
| 56-real-plugins | `plugins.list`：两个内置弹幕插件 |
| 57-real-sync / 58-real-sources | `sync.status` 未配置；`media.library.roots.list` |
| 59-real-first-use-home | 宿主设置报告模型不可用，头像出现琥珀点，输入栏旁出现“设置 Nipa” |

真实模式下没有做写入类操作（下载、清理、登录、同步、收藏、删除记录），只做了读和更新检查。

## 4. 缺的能力（交给后端）

1. **按状态列出收藏**：没有 `accounts.collections.list`。现在只有按 workId 逐个读的 `collections.get`：Bangumi 每部一个请求，弹弹play 每部要拉两次（经我们的网关）。所以片库“按状态看”不能用拼装的方式实现。
   - 建议的契约：`accounts.collections.list {provider, statuses:[…]}` → `{items:[{workId, status, rating}], nextCursor}`。
   - 界面（`NextCollections.works`）和假数据都已按这个契约做好。能力不存在时，下拉里不出现状态项，所以真实环境现在只多了“添加来源”。
2. **取消收藏**：Classic 的 Bangumi 客户端不能删除收藏，所以界面没有“取消标记”。
3. **种子文件 / 种子地址的预览**：`download.preview` 只接受磁力链接，所以 .torrent 只能先加入，再到详情里选文件。
4. **观看记录**：
   - `history.entries` 没有 workId 和图片，只能做成文字列表。
   - locator 为空的条目（这台设备无权访问的路径）既不能单独删除，也不能播放。建议 `history.remove` 接受 `entryIds`。
   - `state.query` 的游标按偏移量计算，删除后翻页会错位。界面的处理是删除后从头重读到当前条数。
5. **任务类型**：`UiTask` 不带任务类型，界面要另调 `task.list type=download` 才知道哪些是下载。
6. **`ui_data`（不在本任务范围内）**：
   - `_taskVerb` 没有 `media.scan_classic`，扫描任务的标题会显示成“准备作品”。
   - 真实模式日志里，`UiDataService._task` 在任务关联的作品实体不存在时，会抛出未处理的 `Failure`（`IdentityStore.entity`）。
7. **同步**：`sync.status` 没有“已保存密码”这一项，所以改了地址或用户名后的“需要重新登录”只能在本页记着，离开就丢。
8. **插件和存储**：
   - 插件自带的界面动作（`plugins.invoke` / `describePlugin.actions`）没有入口；
   - 更新只能打开发布页，不能就地安装；
   - Classic 的“启动时清除弹幕缓存”不在注册表里。
9. `download.delete` 不返回 NeedsDecision，确认由界面自己做。若希望“删除前确认”成为能力层的不变量，需要后端改。

**多端同步和插件**：Classic 有，能力层也已有 `sync.*`、`plugins.*`，这次都已接入设置页。备份与恢复（`backup.*`）、诊断日志（`diagnostics.*`）也有动作，但不在本任务范围内，没有放进来。

## 5. 需要主控决定的问题

1. 是否接受第 4 节第 1 条 `accounts.collections.list` 的契约？
2. 设置页把注册表的 `plugins.*` 从“弹幕与字幕 › 过滤”移到了新的“插件”分节：`plugins.enabled.*` 由每个插件行的开关代替，`plugins.settings.*` 放在“插件 › 设置”。这样可以吗？
3. 弹弹play 把想看和搁置记成“关注”，界面不作解释。可以接受吗？
4. 观看记录点整行就继续播放（子代理加的，规格里没有）。要保留吗？
5. 下载在后台面板里的 × 现在是 `task.control cancel`：停止跟踪，但保留会话和数据。要不要改成“移除任务”，与详情页的删除一致？
6. 观看记录现在只在“动态”里。要不要在头像菜单或首页“继续观看”的标题上也加一个入口？
7. 本次改动的共享文件，供合并 Y11 时参考：
   - `services.dart`：一处加字段和适配层，一处给真实 `calls`；
   - `dev_services.dart`：+4 行；
   - `fake_world.dart`：一个 import、一个 part；
   - `shell_controller.dart`：Esc 先关弹层、`nipaSetup` 字段；
   - `next_shell.dart`：挂上弹层；
   - `top_bar.dart`：头像点与菜单项；
   - `background.dart`：面板；
   - `detail_page.dart`：一个 import，加上操作行里一行 `CollectionButton(work: work)`，没有动 ⋯ 菜单；
   - `debug_extension.dart`：新的调试操作。

## 6. 验证

- `flutter analyze --no-pub lib/next/ui` 和新测试文件：没有问题。
- 新增的界面测试：
  - `test/next/ui_downloads_test.dart`（8 个，含下载详情里选文件和“连同文件删除”的组件测试）；
  - `ui_history_test.dart`（5 个）；
  - `ui_collections_test.dart`（14 个）；
  - `ui_upkeep_test.dart`（与 `ui_settings_test.dart` 合计 16 个）。
- 完整 `flutter test --no-pub test/next`（排队、去掉代理）：614 个通过，7 个跳过，1 个失败。日志在 `/tmp/nipa-next/y12/test-all.log`。
- 构建用 `flutter build macos --debug --no-pub`（带 `ERIKA_PREBUILT_CACHE_DIR`），签名后以 `y12-dev` 启动；改动用 `flutter attach` 热重载。注意：attach 之前已经改过的文件要先 `touch`，否则不会被重载。
- 调试操作（`nx <op>`）：
  - `activity tab=now|downloads|history capacity= all=pause|resume|cancel open=<i>`
  - `downloads new= open=<i> limits=true`
  - `download jobId= files=all|video|none toggle=<i> pause= delete=ask`
  - `newdl source= folders= files=video add=true wait=`
  - `limits`
  - `history hover= resume= remove= clear=ask reload=`
  - `collection open= status= rating=`
  - `lib status=<name>|none`
  - `settings adding= folders=scan|nearby plugins=market sync=test|run clear=<kind> update=check`
  - `sheet close=true`
  - `fake fail= limits= ask=delete`
  - `press … area=sheet`

### 测试结果

完整运行中唯一的失败是 `ui_collections_test.dart` 的“按状态列出”。原因是截图时我改了口径（Bangumi 登录时只用 Bangumi 的列表），测试还按旧口径写。我已按新口径更新，并补上“Bangumi 未登录时用弹弹play”这一情形；随后重跑 `ui_collections_test.dart` 和 `ui_downloads_test.dart`，22 个全部通过。其余文件没有再改动。

## 7. 收尾

- 已按进程号退出实例和 attach 进程，删除了 `y12-dev`，并执行了 `git checkout macos/Podfile.lock`。
- 临时脚本在 `/tmp/nipa-next/y12/`：`launch.sh`、`attach.sh`（已去掉代理）、`reload.sh`、`save.sh`、`nx`。
