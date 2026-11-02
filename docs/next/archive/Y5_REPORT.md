# Y5：发现页、首页补充、标记看过、侧栏加强与会话规则

2026-10-12，worktree `y5-discover`，分支 `next/y5-discover`。没有 commit、push，没有改依赖。按协调者通知，中途把 `next/capability-layer` 快进合并到 e79eb36f（X33）：合并前先把工作区备份为 `/tmp/nipa-next/y5/before-merge.patch` 和 `before-merge-new.tgz`，然后执行 `git merge --ff-only`。这次是快进，没有产生提交，也没有冲突。我的改动都在工作区，新文件未跟踪。

实验只用自己复制的 `y5-dev` 配置，同一时间只开一个实例。结束时已按进程号退出全部实例和附加进程，并删除了 `y5-dev`。没有启动正式应用，没有按应用名查找或激活窗口，也没有碰 `ui-demo` 实例。`macos/Podfile.lock` 被构建改动过，已恢复。

## 1. 完成了什么

### 发现页（顶栏改为“首页 · 发现 · 片库 · 动态”）

- **新番日历**：标题旁有星期标签，顺序是“周一 … 周日”，当天显示为“今天”并默认选中。下面一行是 2:3 横向海报；切换星期时整行淡入淡出。你在追的作品，海报下多一行“在追”。某天没有新番时，只显示“这天没有新番。”。
- **排行榜**：标题旁是来源标签（“弹弹play”“Bangumi”），竖线后面是该来源的榜单（“本周热播 / 本周飙升 / 本季新番”）。只有一个榜单时，直接显示榜单名。排名用描边的大号数字，半压在海报后面：前三名颜色稍亮，其余更淡。
- **点海报进入 Y2 的详情页**，海报会放大成为详情页背景，用的是同一套共享元素过渡。已入库的作品打开的就是原来的详情页。
- **未入库的作品**：
  - 背景是虚化的海报，右侧立一张清晰的海报；窗口放不下时就不显示这张海报。
  - 按钮是“让 Nipa 准备”和“问 Nipa”；没有剧集，也没有“⋯”。
  - “让 Nipa 准备”会打开侧栏，带上这部作品，并替用户在当前会话里说出“帮我准备《X》”。
  - 打开页面时会再取一次简介和集数。
- **未登录弹弹play时**，页面只显示“登录弹弹play 之后，这里会有新番和排行榜。”和一个“登录弹弹play”按钮。按钮调用 `accounts.login`，登录卡片会出现在侧栏里。
- **数据**：只读适配在 `lib/next/ui/data/discover.dart`（`NextDiscoverData`，与 `NextUiData` 分开）。真实实现 `CoreDiscover` 以 `origin: gui` 经 harness 调用：
  - `accounts.status`；
  - `discover.calendar`；
  - `discover.trending_batch`（allHot/week、allRising/week、newAnimeHot/currentSeason，各 20 条）；
  - 打开未入库作品的页面时，调用 `media.metadata.get`，取弹弹play 的作品资料。

  这些都是 Agent 也在用的 Action。离开发现页超过 15 分钟后回来会重新读取。

### 首页

- **今天更新**：后端（X32）已经把 `airing` 书架放在继续观看之后，界面按 16:9 卡片显示，标题下是“第 32 集 · 今天 23:00”这类说明。还没下载的集不显示播放按钮。
  - 输入栏的建议改为优先说“《X》更新了”，素材取自今天更新。
  - Nipa 没摆主视觉时，兜底顺序改为：最近准备好 → 今天更新 → 带“新”标的 → 继续观看。
- **主视觉弹幕**（`home/hero_danmaku.dart`）：
  - 位置和视觉稿 `.danmaku` 一致：主视觉宽度 60% 以右、顶栏下方、高 120 的天空区域，左右边缘渐隐。
  - 样式：15pt 半粗，白色，不透明度 0.34–0.42，带阴影。
  - 最多三条轨道，每条同时只有一句；各轨道轮流使用不同的句子，不会同时出现重复的一句。
  - 速度比视觉稿慢：穿过一次需要 25–34 秒。
  - 弹幕随主视觉一起滚走；悬停预览时换成被预览作品的弹幕。
  - 首页在对话（状态 B）、减少动态效果、没有弹幕这三种情况下都不显示。

### 详情页“⋯”菜单加回“标记看过”

菜单项按情况出现：

- “下载全部”（原有）；
- “第 N 集看过了”：当前集，必须有文件、且还没看完；
- “这一季都看过了”：本季有文件、还没看完的集；
- “这一季标成没看过”：本季有文件的集都已看过时，用来撤回。

以上都经 `NextUiActions.markWatched` 调用 `history.mark_watched_batch`（`origin: gui`），和 Agent 走同一条路。后端拒绝时（比如没有观看记录），按钮下方会出现一句“这几集还没法标记。”，3 秒后消失。

### 侧栏加强

- **上下文标签**：从作品打开侧栏时，顶部显示一枚小卡片：小海报加“关于《X》 ×”。
  - 标签在的时候，每句话都附带这部作品发给 Agent；点 × 去掉。不带作品打开侧栏时也会清掉。
  - 原来放在对话末尾的作品卡去掉了。改为在你说的话上方用一行小字记录“关于《X》”，但当前标签就是这部作品时不重复写。
  - 从历史载入时，也能从消息里读出这一行。
- **接下来可以说的话**（`conversation/next_sayings.dart`）：Nipa 回复的下方给出 2–3 个短句，点一下就等于说出这句话。规则写在界面侧，只读取最后一条回复和这一轮的卡片：
  - 有东西在准备：“还要多久”“先看点别的”；
  - 多部候选：“就《A》”（片名太长时说“就第一部”）、“换一批”；
  - 单部作品：能播放时是“就这部”“换一部”，不能播放时是“就这部”“先下第一集”“换一部”；
  - 单集：“就看这集”“换一部”；
  - 多集：“先看《A》”，再加“都下下来”（有没下载的集时）或“还有别的吗”；
  - 回复以问号结尾、又没有卡片：“好”“不用了”。

  Nipa 在工作、正在提问、出了问题、或刚说“好像没有回应”时，不显示建议。首页对话结束后，输入栏旁也用同一套规则给建议。
- **这次对话在后台做的事**：输入框上方一条细栏，例如“● 《胆大党》 下载 15% · 然后补上弹幕  还有 1 件 ⌃”，下面有一条 2px 的进度。
  - 点开后逐项列出：小海报、片名、一句状态和进度。
  - 数据来自本会话卡片的实时状态：还有步骤没完成的准备卡（运行中的步骤加百分比、等着的下一步）、仍在排队 / 进行 / 暂停的任务卡。最新的排在前面。
- **往对话里拖东西**：截图、视频、种子都可以拖进侧栏或首页输入栏。
  - 拖到上方时，该区域亮起绯红描边，并显示“松开，交给 Nipa”。
  - 松开后文件留在输入框上方：图片显示缩略图，其他文件显示图标和文件名，可以用 × 去掉。提示文字变成“想让 Nipa 做什么？”。
  - 发出后，气泡上方显示图片和文件名，首页舞台上的“你”那一行也会带文件名。
  - 交给 Nipa 的方式：宿主目前只收文字，所以在消息后附一段“[NipaPlay 附件] 用户拖进来的文件：- 路径（图片/视频/种子/字幕/文件）”。界面显示时会去掉这一段，读历史时再把文件解析回来。
  - Classic 原来在整个窗口都接受拖入并播放视频。现在，当 Next 在屏幕上、且拖入点落在这两个区域时，Classic 不播放，也不显示“拖放至页面内播放视频”的提示；其他位置和其他时候都和原来一样。

### 会话规则

- **首页输入栏永远进主会话**：`SessionChoice.mainTarget()`。即使侧栏正停在别的会话，首页说的话也进主会话。
- **侧栏里切到别的会话或开新对话只影响侧栏**；关闭侧栏时回到主会话，并通知宿主。
- **“想了 N 秒”扣掉等你回答的时间**：`TurnActivity.beginWait/endWait`。
  - 侧栏和首页都会在 Nipa 提问时停表、回答后继续。
  - 等待期间状态行显示“在等你回答”，不显示时钟。

### 回看工作过程（X33）

已合并 X33。它把每一轮的过程补进 `readThread` 的历史，Y3 留下的 `_loadHistory → TurnActivity.fromHistory` 接入点不需要改，我没有动。这一项没有在真实宿主上复测，见第 4 节。

### 顺带修复：卸载时的连锁泄漏

`StreamingReply`（Y1）的 ticker 是 `late final` 惰性创建的。一句回复如果从没播放过动画，ticker 会在 `dispose` 里才第一次被创建，这时会去查已停用的祖先，于是抛出异常。Flutter 卸载停用元素时一旦出错，同一帧里其余的停用元素就永远不会释放。

实验中观察到的后果：关闭侧栏后，侧栏的拖放区一直留在 desktop_drop 的监听列表里。之后每次拖放，插件都会在它身上报错，并就此中断，排在它后面的拖放区（首页输入栏）完全收不到事件。

修复方法：ticker 改为在 `initState` 里创建（`stage.dart`，3 行）。新加的 `hero_danmaku.dart` 也同样处理。

## 2. 改了哪些已有文件

| 文件 | 改动 |
|---|---|
| `lib/main.dart`（Classic） | 全局 `DropTarget`：进入或移动到 Next 的拖放区上时不显示 Classic 的拖放提示；落在 Next 的拖放区上时不播放。另有一行导入。Next 不在屏幕上时，`NextDropZones.claims` 恒为 false，行为不变。 |
| `shell/top_bar.dart`、`shell/next_shell.dart`、`shell/shell_controller.dart` | 加入“发现”分区；首页输入栏的附件；关闭侧栏时回到主会话 |
| `conversation/session_choice.dart`、`conversation.dart` | 首页固定进主会话；首页附件；提问时停表 |
| `conversation/panel_chat.dart` | 上下文标签持续生效；附件；接下来可说的话；后台事项；提问时停表；`ChatContext` 移到新文件 `chat_context.dart` 并重新导出 |
| `conversation/turn_activity.dart`、`widgets/activity_line.dart` | 扣除等待时间；等待期间不显示时钟 |
| `panel/chat_panel.dart` | 关于标签、附件栏、拖放亮起、建议、后台细栏、你说的话带文件 |
| `home/home_page.dart`、`home/ask_bar.dart`、`home/stage.dart` | 弹幕层、今天更新优先、输入栏拖放与附件、舞台上的建议；修复 `StreamingReply` 的 ticker |
| `detail/detail_page.dart`、`detail/detail_backdrop.dart` | 未入库作品（虚化海报背景、立着的海报、“让 Nipa 准备”）；“⋯”菜单的标记看过 |
| `data/ui_actions.dart`、`data/core_connect.dart`、`data/services.dart` | `markWatched`、`login`；`NextUiServices.discover` |
| `widgets/artwork.dart` | `artProvider`：`http(s)` 路径用网络图片，供发现页使用 |
| `widgets/shelf.dart`、`widgets/icons.dart` | 书架标题旁可放标签；新增文件、视频、种子图标 |
| `dev/fake_world.dart`、`dev/dev_services.dart`、`dev/debug_extension.dart` | 假数据（下文）；调试操作 `discover` / `press` / `drag` / `drop` / `scroll`，状态里加了附件、建议、后台事项 |

新文件：

- `pages/discover_page.dart`
- `data/discover.dart`
- `home/hero_danmaku.dart`
- `conversation/chat_context.dart`
- `conversation/next_sayings.dart`
- `widgets/drop_zone.dart`
- `widgets/attachments.dart`
- `test/next/ui_drop_zone_test.dart`
- 本报告和 `docs/next/evidence/y5/`

没有改后端（`lib/next/ui_data`、能力和宿主）。

**假数据**：

- 今天更新：药屋第 32 集今天 23:00、我推第 15 集今天 23:30、迷宫饭第 14 集今天。
- 弹幕：芙莉莲六句、孤独摇滚三句、紫罗兰两句；其余作品没有弹幕，用来验证“没有就不显示”。
- 发现页：七天的日历；四个榜，其中弹弹play 三个、Bangumi 一个。
- 标记看过：会真正改动假数据里的观看进度。
- 拖入文件的对话脚本：种子、截图、视频各一种回应。
- 发现页里未入库作品的海报：我用现有的 TMDB 令牌抓了 14 张，放在 `/tmp/nipa-next/visual/tmdb/discover/`，这是在共用素材目录里新增的子目录。`FakeWorld` 有这个目录就读取，没有就只用片库作品。

## 3. 决策

1. **发现数据单独做一个只读适配，不扩展 `NextUiData`。** 发现条目不在片库里，没有本地 workId。我用 `found:<来源>:<外部 ID>` 作为界面内部的 ID，只用于路由，以及告诉 Agent“还不在片库里；弹弹play 作品 123”，从不显示给用户。
2. **未入库作品仍用 Y2 的详情页。** 区别只有：不读片库，读一次资料；按钮换成“让 Nipa 准备”。只有海报的作品用“虚化海报做背景，加一张立着的海报”，这是常见媒体库的做法；片库里没有横幅图的作品，背景也会因此用上虚化的海报。
3. **标记看过只给有文件的集。** 后端要求先有观看记录，没文件的集一定会被整批拒绝，所以不在菜单里出现。失败时用一句话说明，不重试。
4. **上下文标签在侧栏打开期间一直生效。** 标签就是“这段对话关于什么”的状态：每句话都附带作品，点 × 或关闭侧栏后结束。
5. **建议规则只看最后一轮的回复和卡片**，最多三条。宁可少给，也不给可能说错的话：多部候选时用片名或“第一部”，不用指代不清的“就这部”。
6. **后台细栏只从卡片推断。** 卡片的状态是实时的，而且一定属于这段对话。没有卡片的任务和后续不在这里出现，缺口见第 5 节。
7. **附件用文件路径写进消息。** 宿主的 `turn/start` 只发 text，我不改后端。路径写在固定标记之后，界面显示时去掉、读历史时解析回来。有一项测试守住这个往返。
8. **拖放和 Classic 的关系。** desktop_drop 会把同一个事件广播给所有 `DropTarget`，没有“被谁接住”的概念，所以只能让 Classic 判断落点是否在 Next 的区域上。区域只在可见、且 Next 在屏幕上时才算数：隐藏的分区和被 Classic 播放页盖住的 Next 都不算。侧栏打开时，首页输入栏不接收拖入。
9. **弹幕比视觉稿慢一些。** 实测视觉稿的速度约 41pt/s，用户要求“慢”，我改成 25–34 秒穿过一次，约 30pt/s，这是按数值计算的。
10. **能力覆盖**：
    - 发现数据、标记看过、登录，用的都是 Agent 已有的 Action；
    - “让 Nipa 准备”和建议都只是替用户说出一句话；
    - 拖放和后台细栏只是展示，用户和 Agent 之间没有新的操作需要对应，所以没有新增 Action。

## 4. 实验

### 环境

- 用本 worktree 的 Debug 构建。这个 worktree 原本缺 `.dart_tool/package_graph.json` 和 `macos/Flutter/ephemeral/Packages`，我从 `x32-uidata`（同一份 `pubspec.lock`）复制过来，都在 gitignore 里，没有重新解析依赖。
- 实例：`NIPAPLAY_PROFILE=y5-dev NIPAPLAY_NEXT_UI_FAKE=/tmp/nipa-next/visual/tmdb NIPAPLAY_NEXT_UI_FAKE_CHAT=1`，默认安静。
- 驱动和截图：所有状态都用 `ext.nipaplay.nextui` 切换。“点击”是调试扩展合成的指针事件，不移动系统鼠标。截图用 `screencapture -x -o -l<窗口号>`，窗口号用一个只读的小工具按进程号取得（`/tmp/nipa-next/y5/tools/winid`）。
- 拖放的模拟方法：经 `ui.channelBuffers` 向 `desktop_drop` 通道送入原生插件会发的 `entered` → `updated` → `performOperation_macos` 消息。这条路和从 Finder 真实拖入时界面收到的事件相同，Classic 的全局 `DropTarget` 也会一起收到。
- 实例 PID 依次为：
  - 78514：第一次，配合热重载；
  - 79952：重启。启动的是旧构建，见下文“意外”；
  - 81946：用新构建重启；
  - 82385：一次不用假数据的真实数据检查，见本节末尾。

### 观察

- **首页**（`home.jpg`、`home-airing.jpg`）：
  - 导航是“首页 发现 片库 动态”；
  - 输入栏的建议是“接着看《药屋少女的呢喃》 / 【我推的孩子】更新了 / 来点轻松的”；
  - 滚动后，“今天更新”在继续观看之后，三张卡片的说明是“第 32 集 · 今天 23:00”等。
- **弹幕**：间隔 4 秒截两次。“好治愈 / 音乐好好听 / 一起看”三句淡淡地从右向左移动了约 165pt（这是放慢之前的速度）。放慢后，`danmaku-on-crop.jpg` 是“画面好美 / 音乐好好听”两句。`reduce on=true` 时天空区域没有字（`danmaku-reduced-crop.jpg`）。
- **发现页**（`discover.jpg`）：
  - 默认选中“今天”（周一），六部作品，药屋、迷宫饭下面有“在追”；
  - 排行榜是“弹弹play · 本周热播”，有 1–6 的描边大数字。
  - 合成点击“周四”和“Bangumi”后，调试状态返回 `day: 4`、`calendar: [胆大党, 间谍过家家, 蓝色监狱, 咒术回战]`、`source: Bangumi`、`list: 高分`（`discover-thursday-bangumi.jpg`）。
- **未入库作品**：在日历上合成点击胆大党，进入详情（`detail-found.jpg`）：原名“ダンダダン”、宋体标题、“★ 8.5 · 2024 · 12 集”、两行简介、“让 Nipa 准备 / 问 Nipa”，右侧立着海报。调试状态是 `found: true`，没有剧集。
  - 第一版没有右侧海报，页面右半边大片空白，所以补上了。
- **让 Nipa 准备**：合成点击后，`panelOpen: True`、`about: 胆大党`，记录是 `you: 帮我准备《胆大党》 (about 胆大党)`。15 秒后变成“想了 15 秒 · 5 步”、作品卡、准备卡，建议是“还要多久 / 先看点别的”（`panel-prepare-done.jpg`）。
  - 第一次假脚本不认识发现页的片名，转而问“准备哪一部？”。这是假数据的问题，已让假数据也认得发现页的作品。
- **后台细栏**：收起时，第一条是最新的“《胆大党》下载 15% · 然后补上弹幕”，后面是“还有 1 件”；展开后两行，另一行是“葬送的芙莉莲 正在补上弹幕”（`panel-underway-open-crop.jpg`）。
  - 最初的顺序是旧的在前，“补上弹幕”前面也没有“正在”，读起来像一句指令，两处都改了。
- **关于标签的 ×**：合成点击后，`about: None`，提示文字从“问问《胆大党》”变回“继续说…”。
- **拖进侧栏**：
  - 拖到上方时 `claimed: True`，侧栏亮起“松开，交给 Nipa”，整窗没有 Classic 的“拖放至页面内播放视频”覆盖层（`panel-drag-over-small.jpg`）。
  - 松开后两个附件（截图缩略图和种子名）出现在输入框上方（`panel-attached-crop.jpg`）。
  - 日志：Classic 的全局目标打印了 `[DragDrop] onDragDone: 2 files`，但 `Handling dropped file` 出现 0 次，即没有播放。
  - 发送“这是哪一集？”后，气泡上方显示截图和种子名，回复是“种子里是《迷宫饭》第 14 集……要我加进下载吗？”，建议是“好 / 不用了”（`panel-files-reply-crop.jpg`）。
- **拖到首页输入栏**：亮起的效果见 `ask-drag-over-crop.jpg`，附件见 `ask-attached-crop.jpg`。合成点击“发送”后，`saidFiles` 是这张截图，舞台上显示“你 这是哪一集？ · 截屏 2026-10-12 21.03.17.jpg”，回复带第 3 集的剧集卡，输入栏旁是“就看这集 / 换一部”（`home-files-stage-small.jpg`）。
- **会话规则**：
  - 侧栏选中“长安十二时辰值得看吗”：`current: fake-thread-changan, onMain: False`；
  - 此时在首页说“最近有什么更新”：`homeThread: fake-thread-main`，侧栏仍是 `fake-thread-changan`；
  - Esc 关闭侧栏：`current: fake-thread-main, onMain: True`。
- **扣除等待时间**：新对话里说“帮我准备一下”，3 秒后 Nipa 提问，此时状态行只有“在等你回答”，没有时钟（`panel-asking-crop.jpg`）。等了约 13 秒才回答，回合在约 32 秒时结束，显示“想了 18 秒 · 6 步”（32 − 13 ≈ 19，计时粒度为 1 秒）。
- **标记看过**：芙莉莲的菜单是“下载全部 / 第 3 集看过了 / 这一季都看过了”（`detail-menu-crop.jpg`）。
  - 点“第 3 集看过了”：第 3 集的进度条变满，白框移到第 4 集，按钮变为“继续 第 4 集”（`detail-marked-crop.jpg`）。
  - 再点“这一季都看过了”，菜单变成“下载全部 / 这一季标成没看过”；撤回后变回“第 1 集看过了 / 这一季都看过了”。
  - 这些都走的是假数据的 `markWatched`，见第 5 节。
- **首页对话结束后的建议**：“最近有什么更新”得到三张剧集卡，建议最初只有“先看《药屋少女的呢喃》”一条（`home-stage-sayings.jpg`），之后补上了“还有别的吗”。

### 意外和失误

- **卸载时的连锁泄漏**：关闭过一次侧栏后，再拖到首页输入栏，`claimed: True` 但 `askFiles: []`。日志有 5 次“Cannot get renderObject of inactive element”，以及 `_StreamingReplyState.dispose` 里的“deactivated widget's ancestor”。我临时加了探针，看到侧栏的拖放区只有 deactivate、没有 dispose，由此找到了第 1 节所说的原因。修复后重新构建，再走一遍同样的流程：这两类报错都是 0 次，附件正常（`askFiles` 两项）。探针已删除。
- **用旧构建重启**：第二次启动（PID 79952）用的是热重载之前的构建产物。附加热重载时，是以当时的源码为基准，所以新改动并没有送进去。从日志里仍然出现旧报错发现了这一点，于是重新构建、重新启动。
- **真实数据检查**（PID 82385，不设 FAKE，只做这一次）：
  - 为了只看“未登录”这条路径，我先在自己的 `y5-dev` 副本里删掉了弹弹play 的 token 和用户名，`ui-demo` 没有动。
  - 结果 `accounts.status` 仍报告已登录，页面用 `CoreDiscover` 显示了真实的新番日历（`real-discover-calendar.jpg`，海报来自网络图片）。
  - 日志显示，排行榜请求在本地就被拒绝了：“请先登录弹弹play账号后再使用弹弹play服务”，Classic 首页启动时也打印同样的话。日志里看不到日历的请求，我推断日历来自 Classic 的缓存，这一点没有核实。
  - 排行榜四个请求全部失败，界面就不显示排行榜这一块。
  - 这次没有打开任何作品，也没有发起对话，随即按 PID 退出。由此可知，真实适配的 `accounts.status → discover.calendar → 映射 → 网络海报` 这条路是通的；未登录时的那句话没有在真实环境里看到。
- 截图里红绿灯是灰色的，原因和 Y4 一样：安静实例不是 key 窗口。

### 检查

- `flutter analyze --no-pub lib/next`：33 条 info，全部在后端文件里；`lib/next/ui` 没有任何问题，也没有 warning 或 error。`lib/main.dart` 的 info 都在我没有改动的行上。
- 迭代时排队跑了 `ui_drop_zone_test.dart` 和 `ui_gate_test.dart`，4 项通过。
- 最后排队跑了一次完整的 `flutter test --no-pub test/next`：435 项通过，4 项跳过。
- 新测试守两件事：
  - Next 不在屏幕上、或落点在 Next 的区域外时，拖放仍归 Classic，防止 Classic 退化；
  - 附件和“关于”在消息里写入后，能从历史里完整读回来。
- 最终构建 `flutter build macos --debug --no-pub` 成功。

## 5. 还没做到 / 需要你决定的问题

**还没做到**

1. **Bangumi 排行榜没有数据来源。** X29 的 `discover.trending` 只有弹弹play 的三个榜。界面按来源分页签，真实数据目前只会出现“弹弹play”。假数据里的 Bangumi 只是为了看多来源时的样子。
2. **发现条目和片库作品对不上。** 缺一个只读查询：按已接受的弹弹play 身份，把 animeId 对应到 workId。因此在真实数据里，所有发现条目都按“未入库”处理，打开后是“让 Nipa 准备”；已经入库的作品，要靠 Nipa 自己发现。
3. **后台细栏只能从卡片推断。** 缺“这段对话发起的任务和后续”的数据，例如按 threadId 列出任务和后续。Agent 登记的后续，只有写进准备卡的步骤里才看得到。
4. **附件只能以路径交给 Nipa。** 宿主只发 text。如果要让模型直接看截图，需要宿主支持 Codex 的图片输入（`localImage`）。
5. **重启后的“想了 N 秒”仍含等待时间。** 本次运行中见过的回合会扣除等待；从历史读回的回合，X33 的过程记录里没有等待区间，所以无法扣除。
6. **X33 的步骤回看没有在真实宿主上看过。** 本次全程用假对话；X33 自己用离线回放和约束测试验证过。
7. **标记看过只在假数据上验证过。** 真实的 `history.mark_watched_batch` 由 X32 验证过，界面这边只是一层很薄的调用，但没有在真实片库上点过。没有观看记录的集，后端会拒绝。
8. **没有看到真实的“未登录”页面**，见实验第三条。
9. **desktop_drop 本身很脆弱。** 只要有一个停用的 `DropTarget` 没释放，它抛出的异常就会让后面所有目标都收不到事件。本次已经修掉了引起泄漏的那处，但插件的行为本身没有改。

**需要你决定**

1. **Classic 的 `main.dart` 改了三处小地方**（拖放让出），只在 Next 显示、且落点在 Next 区域时生效。这是否可以接受？
2. **Bangumi 排行榜和发现条目到片库的对应**，是否交给后端补上（见上面第 1、2 条）？
3. **INTERACTION.md 还需要更新**：顶栏仍写“首页 / 片库 / 动态”；另外，“详情”一节的“⋯”菜单里还有“移除（二次确认）”，这次没有做。我没有改规范。
4. **弹幕速度**：现在穿过一次 25–34 秒，比视觉稿慢。是否合适？
5. **关于标签的语义**：现在是标签在，每句话都带上这部作品，关闭侧栏后清掉。是否符合你的预期？
6. **首页对话结束后，输入栏旁也给出“接下来可以说的话”**，而任务只要求了侧栏。这样是否保留？

## 6. 截图

挑选后的 JPEG 在 `docs/next/evidence/y5/`，原图在 `/tmp/nipa-next/y5/shots/`。

| 画面 | 文件 |
|---|---|
| 首页、今天更新 | `home.jpg`、`home-airing.jpg` |
| 弹幕（正常 / 减少动态效果） | `danmaku-on-crop.jpg`、`danmaku-reduced-crop.jpg` |
| 发现页 | `discover.jpg`、`discover-thursday-bangumi.jpg`、`real-discover-calendar.jpg`（真实数据） |
| 未入库作品的详情 | `detail-found.jpg` |
| 标记看过 | `detail-menu-crop.jpg`、`detail-marked-crop.jpg` |
| 侧栏：关于标签、准备、建议、后台细栏 | `panel-prepare-done.jpg`、`panel-underway-open-crop.jpg` |
| 侧栏：拖放与附件 | `panel-drag-over-small.jpg`、`panel-attached-crop.jpg`、`panel-files-reply-crop.jpg` |
| 侧栏：等你回答（不计时） | `panel-asking-crop.jpg` |
| 首页：拖放、附件、对话后的建议 | `ask-drag-over-crop.jpg`、`ask-attached-crop.jpg`、`home-files-stage-small.jpg`、`home-stage-sayings.jpg` |

复现脚本都在 `/tmp/nipa-next/y5/`：

- `launch.sh`、`attach.sh`、`reload.sh`、`quit.sh`：启动、附加热重载、热重载、退出，全部按记录的 PID 操作；
- `nextui.py <op> k=v`：驱动调试扩展；
- `shot.sh`：截取实例窗口；
- `tools/winid`：按进程号取窗口号；
- `fetch_discover.py`：抓取发现页用的海报；
- `drop/`：拖放用的三个测试文件。
