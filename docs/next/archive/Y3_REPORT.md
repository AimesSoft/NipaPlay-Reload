# Y3：对话侧面板

2026-10-12，worktree `y3-panel`，分支 `next/y3-panel`。没有 commit、push，也没有改依赖。前半段由一位同伴完成，他因网络问题中断，我接手完成剩余部分。合并了两次 `next/capability-layer`，第二次合并到 d232b5a8，包含 Y2 详情页、Y4 顶栏和 X31 主会话。合并结果在暂存区，我的改动都没有暂存，新文件未跟踪。实验只用了自己的 `y3-dev` 实验配置，同一时间只开一个实例。结束时已按进程号退出实例和假模型服务，并删除了 `y3-dev`。没有启动正式应用，没有碰 `ui-demo`，也没有改 `~/.codex`。

规范依据：`docs/next/design/INTERACTION.md` 的「对话侧面板」节；「打开与工作过程（2026-10-12 补充）」只在主仓库未跟踪的 `docs/next/proposals/visual/INTERACTION.md` 里有，本分支的规范还没有这一节（见第 5 节）。

## 1. 完成了什么

**侧面板（同伴完成，我做了验证和修补）**

- 从右侧滑入，背景模糊变暗，Esc 或点外面关闭。消息有三种：你的话是靠右气泡，Nipa 的话不加气泡，卡片穿插其间并实时更新。
- 好像没有回应：3 分钟没有任何事件时出现“好像没有回应”，下面有“再等等”和“重新发”。“重新发”会先中断再重发，不会自动中断。
- 需要回答：问题卡片，选项是按钮，也可以直接打字回答。
- 需要登录：显示“需要登录 X”的卡片（`LoginRequests`），按钮打开 NipaPlay 自己的登录窗口。Next 界面不在屏幕上时（例如 Classic 正在播放），仍按原来的方式直接弹窗。
- 其他：会话下拉、`openPanel({UiWork? about})`、⌘K（首页聚焦输入栏，其他页面打开侧栏）。

**一步打开**

- 顶栏、首页主视觉、输入栏、动态页、首页就地对话里的 Nipa 头像，点一下都直接打开侧栏。
- 原来头像弹出的菜单（问 Nipa / 回到经典界面）改为右键或长按打开。
- 首页就地对话的“展开”进入侧栏里的同一个会话。

**工作过程（`TurnActivity` + `ActivityLine`）**

- 回合进行中，最新消息下面有一行状态：动态小头像、当前在做什么、走动的计时，例如“在添加下载 · 0:10”。
  - `nipa` 的常用能力翻译成动词，不认识的命令显示命令本身，`ui.present` 不算一步。
  - Nipa 提问等待回答时，这一行显示“在等你回答”（这一点是我补的）。
- 点开这一行，按顺序列出：思考摘要，每条命令及其状态（✓ 或“退出 N”），每条命令的输出可单独展开。
- 回合结束后这一行收成“想了 15 秒 · 5 步”，放在回复上方，点开可回看。首页舞台上同样显示这一行，但不能展开。
- 切走再切回会话、或从 Codex 历史重新载入时，本次运行中见过的回合（最多 60 个）仍保留步骤。这是我加的。原因是 Codex 历史只存消息，见第 3 节真实宿主部分。

**会话模型：主会话（我做的）**

- 新增 `SessionChoice`，记录当前会话，默认是主会话。主会话由 X31 的宿主持久化。
- 首页输入栏、⌘K、点头像、侧栏、详情页“问 Nipa”都进入当前会话。
- “新的对话”只在用户点击时才开。
- 会话列表：最上面是“主对话”，下面是“新的对话”入口，再往下是其他会话（按时间排）。
- 不在主会话时，侧栏标题显示该会话的第一句话。
- 用户选了哪个会话，会通过 `switchThread` 告知宿主，所以 Agent 那边的 `chat.session.list` 里 isCurrent 一致。
- 同一会话里的后续唤醒（例如主会话里的 `agent.wake`）在首页按后台工作处理（状态 C），不会冒充成你刚说的那句话的回复。
- 详情页“⋯ → 下载全部”：先打开侧栏，带上这部作品，等当前会话载入后，再替用户说出“把《X》剩下的集都下载下来”。不再说到首页的对话上。“问 Nipa”本来就调用 `openPanel(about: work)`。

**假模型（`NIPAPLAY_NEXT_UI_FAKE_CHAT=1`，我重写了脚本）**

- 按用户说的话分类，每类都有自己的思考、`nipa` 命令及输出（包含一次失败后放宽条件重试）、回复和卡片：
  - 问更新：单部或全部，剧集卡；
  - 要推荐：分轻松、周末一口气、安静、刺激、泛泛五种，候选卡；
  - 准备一部：没说哪部时先提问；同一部已经在下载时报告进度；新开的下载会出现在任务环里，准备卡跟着进度更新；
  - 接着看、问值不值得、在作品页上问、选版本；
  - 寒暄、道谢、自我介绍；
  - 听不懂时，三种追问轮换使用；
  - “慢慢来”用来模拟没有回应。
- 主会话预置了带步骤的历史，另有两个旁支会话。后续唤醒进入主会话。

**调试扩展 `ext.nipaplay.nextui`**

- 与 Y2 共用 `tap` 操作，我加了 `button=secondary`（右键）。
- `status` 里加了 `session` 一项（main/current/onMain/fresh）。
- 用于实验的操作：`panel`、`panelsay`、`activity`、`sessions`、`choose`、`stall`、`quiet`、`login`。

## 2. 改了哪些已有文件

以合并结果 d232b5a8 为基准，`git diff --stat` 列出的已有文件：

| 文件 | 改动 |
|---|---|
| `lib/next/ui/conversation/chat_port.dart` | 接 X31 的四个会话方法，加 `readThread`（经过 `redactHarnessJson`） |
| `lib/next/ui/conversation/conversation.dart` | 首页进入当前会话；用 `_expecting` 和回合号区分本回合与同会话的后续唤醒；增加 `round` 状态行；`followRound`、`dropQuestion` 与侧栏协同 |
| `lib/next/ui/shell/shell_controller.dart` | `SessionChoice`、`PanelChat`；`openPanel`、`openPanelOn`、`sayAbout`；⌘K；Esc 先关会话菜单；登录卡出现时自动打开侧栏 |
| `lib/next/ui/shell/top_bar.dart` | 头像左键打开侧栏，右键或长按弹菜单（保留 Y4 的尺寸） |
| `lib/next/ui/shell/next_shell.dart` | 挂上 `ChatPanelLayer`；告诉 `LoginRequests` 外壳是否在屏幕上 |
| `lib/next/ui/home/stage.dart` | “展开”；状态行；`StreamingReply` 可指定字号 |
| `lib/next/ui/home/home_page.dart`、`hero_copy.dart`、`ask_bar.dart`、`pages/activity_page.dart` | 各处头像点击打开侧栏 |
| `lib/next/ui/detail/detail_page.dart` | “下载全部”改用 `shell.sayAbout` |
| `lib/next/ui/cards/card_views.dart` | 连续的剧集卡横排；候选海报尺寸可调；`WorkRowCard` 对齐 |
| `lib/next/ui/widgets/nipa_avatar.dart` | `onTap`、`onMenu` |
| `lib/next/ui/widgets/icons.dart` | 新增 `plus` 图标 |
| `lib/next/ui/widgets/words.dart` | `Words.duration`（与 Y2 的 `season` 并存） |
| `lib/next/ui/widgets/progress.dart` | 宽度不定时进度条铺满 |
| `lib/next/ui/theme/tokens.dart` | `NextText.mono` |
| `lib/next/ui/data/services.dart`、`core_connect.dart` | `LoginRequests` 接到核心的登录窗口 |
| `lib/next/ui/dev/fake_world.dart` | 假会话脚本、主会话、准备任务（见上文） |
| `lib/next/ui/dev/debug_extension.dart` | 见上文 |

另外：

- `macos/Podfile.lock` 在接手前就有改动（erika 0.1.3 → 0.2.1），不是这次任务改的，我没有动它。
- 新文件：
  - `lib/next/ui/panel/chat_panel.dart`
  - `lib/next/ui/conversation/{panel_chat,session_choice,turn_activity}.dart`
  - `lib/next/ui/data/login_requests.dart`
  - `lib/next/ui/widgets/activity_line.dart`
  - `test/next/ui_login_requests_test.dart`
  - 本报告和 `docs/next/evidence/y3/`

没有改动 Classic 文件，也没有改动后端（`lib/next/chat` 等）。

## 3. 决策

1. **当前会话由界面记住，主会话的身份以宿主为准。**
   - 主会话 ID 从 `listThreads().mainThreadId` 读取。这条路径没有副作用，宿主忙时也能读。
   - 只有宿主还没有主会话时，才调用 `mainThread()` 创建，因为它会让 Codex 恢复主线程，忙时返回 null。
   - 不跟随宿主的 currentThreadId。后续唤醒在别的线程开始时，宿主的当前会话会跟着变，界面不应因此跳走。
   - 用户选会话时调用 `switchThread` 告知宿主。宿主忙时它返回 null，下一次在该会话开始回合时宿主会自己切过去。
2. **选中的会话会一直保持。** 用户在侧栏选了旁支会话或开了新对话后，首页输入栏、⌘K 也进入它，直到用户选回“主对话”。这是按“当前选中的会话 = 主会话（默认）”的字面理解实现的，是否改成在某个时机自动回到主会话，见第 5 节。
3. **区分首页本回合和同一会话里的后续唤醒。**
   - 首页只把两类事件算作本回合：自己刚发起、还没拿到回合号时的事件，以及回合号匹配的事件。其余回合都按后台工作处理。
   - 发起前先等宿主空闲，避免把正在跑的后续唤醒错认成回复。
4. **“问 Nipa”带的作品是“下一句话的上下文”。**
   - 发出之前，作品卡显示在对话末尾。
   - 发出时，作品卡变成该句上方的一条记录，并随这句话一起发给 Agent。
   - 每次打开侧栏都会重新设置这个上下文；不带作品打开就清掉。
5. **“下载全部”先载入会话，再说话。** 如果在侧栏载入历史的同时说话，载入会清掉刚发出的这句，所以 `sayAbout` 等 `show` 完成后再调用 `say`。
6. **用内存缓存保留步骤。**
   - Codex 历史里没有命令和思考，所以把本次运行中见过的回合缓存在内存里，最多 60 个。
   - 重启后，旧回合只剩“想了 N 秒”，不显示步数，也不能展开。真正的修复需要后端提供数据，见第 4 节。
7. **连续剧集卡横排。** 首页回复里有三张剧集卡时，竖排会把输入栏挤出画面，所以改为横排，放不下时换行。
8. **主会话在列表里叫“主对话”。** 它的第一句话已经不能代表整个会话；离开主会话时，标题显示该会话的第一句话。

## 4. 实验

截图都只截了实验实例的窗口。原图在 `/tmp/nipa-next/y3/shots2/`，挑出的 JPEG 在 `docs/next/evidence/y3/`。视觉稿对照的是 `/tmp/nipa-next/visual/v-chat.png`：布局、卡片、输入框一致。我们多了标题旁的下拉箭头（会话列表），以及气泡和回复之间的“想了 · 步”一行（补充规范要求的）。

### 假数据 + 假模型

`NIPAPLAY_NEXT_UI_FAKE=/tmp/nipa-next/visual/tmdb NIPAPLAY_NEXT_UI_FAKE_CHAT=1`

**一步打开**

- 合成左键点击顶栏头像：`panelOpen=true popover=none`，直接打开主会话（`fake-01-avatar-one-step.jpg`）。
- 首页主视觉、输入栏、动态页的头像，以及资料库页按 ⌘K，都直接打开主会话。
- 右键点击头像：`panelOpen=False popover=nipa`，弹出“问 Nipa / 回到经典界面”（`fake-02-avatar-rightclick-menu.jpg`）。
- X31 合并后复测，结果相同。

**工作过程三种状态**（在侧栏说“帮我准备一下《迷宫饭》”）

| 时间点 | 观察到的 | 截图 |
|---|---|---|
| 约 10 秒，进行中 | 动态小头像 + “在添加下载 · 0:10 ›” | `fake-03-process-live.jpg` |
| 进行中，展开 | 两条思考摘要；metadata.search ✓；第一次 download.preview “退出 1”，输出已展开；放宽条件的思考；第二次 preview ✓；download.add 正在运行（红点） | `fake-04-process-live-open.jpg` |
| 结束后 | “想了 15 秒 · 5 步 ›”在回复上方，下面是作品卡和正在准备卡，任务环多了一个任务 | `fake-05-process-done.jpg` |
| 结束后，展开 | 完整步骤可以回看 | `fake-06-process-done-open.jpg` |

**主会话**

- 首页说“最近有什么更新”：`homeThread = fake-thread-main`，侧栏同一会话也出现这一轮（`fake-09-home-updates.jpg`）。
  - 第一次三张剧集卡竖排，把输入栏挤出了画面，因此改为横排。
  - 第一次修改没有生效：`EpisodeCardView` 自带的 Align 在 Wrap 里撑满了一整行，加上固定宽度后才正常。
- 会话列表：主对话置顶，其次是“+ 新的对话”，再往下是旁支会话（`fake-07-sessions-main-pinned.jpg`）。
- 开新对话后说“长安十二时辰讲什么的”：`current=fake-thread-22 onMain=False`；标题变成这句话；列表中主对话仍在最上（`fake-08-sessions-new-conversation.jpg`）。
- 此时在首页说“谢谢”，进入 `fake-thread-22`，符合决策 2。
- 选回主对话后，假的后续唤醒进入主会话：首页 `mood=acting line=在补弹幕 staged=False`，侧栏主会话出现“在找弹幕”这一行；结束后首页显示“《葬送的芙莉莲》的弹幕补好了…”，并带未读红点。

**脚本是否各不相同**

依次说“在吗 / 推荐点刺激的 / 帮我准备一下（再选莉可丽丝）/ 嗯嗯 / 那个啥 / 今晚想安静一会儿”。每句的回复、步骤数和卡片都不同，两句听不懂的话得到的追问也不同。

**作品页提问与提问状态**

- `panel about=fake:lycoris` 后说“这部讲什么的”：作品卡位于这句话上方，回复介绍了这部作品（`fake-10-ask-from-work.jpg`）。
  - 第一次脚本没有认出作品，因为作品名只在上下文里、不在用户的话里。已修正。
- “帮我准备一下”触发提问时，状态行显示“在等你回答 · 0:06”（`fake-11-waiting-for-answer.jpg`）。
  - 修正前这一行显示“在想”。
  - 另一个现象：回答后回合总时长是“想了 1 分 12 秒”，其中包括等待用户回答的时间。

**详情页“下载全部”**（X31 合并后）

- 在莉可丽丝详情页打开“⋯”菜单，合成点击“下载全部”。
- 观察到：`panelOpen=True staged=False`，侧栏主会话里依次出现作品卡 → “把《莉可丽丝》剩下的集都下载下来” → 工作过程 → 回复和准备卡，首页舞台没有被占用（`fake-12-download-all.jpg`）。
- 意外：在没有缺集的迷宫饭页面，用调试命令强行打开菜单时，因为没有“⋯”锚点，菜单落在左上角，合成点击落进窗口拖动区，没有生效。这是调试命令的问题，正常界面里没有缺集时不会出现“⋯”。

### 真实对话宿主

只做了一次，在 X31 合并之前。环境：`/tmp/nipa-next/y3/mock_provider.py` 在 18765 端口提供无凭据的回环服务，y3-dev 自带的 codex-home 已经配置好。

- 当时主会话还是我写的临时实现：把最近的线程当作主会话，即 `01a12c81…`。首页说“最近片库里有什么更新”，随后点头像，侧栏显示同一会话。
- 进行中展开（`real-01-process-live-open.jpg`）：
  - “在想 · 0:03”；
  - 思考“想知道片库最近加了什么，先把作品列出来看看。”；
  - 真实执行的 `./nipa call media.library.works '{"limit": 20}'` ✓；
  - 下一条思考。
- 结束后：“想了 6 秒 · 1 步”，展开后能看到真实输出（`real-02-process-done-open.jpg`）。输出里是原始 JSON，含 `jellyfin://…`、`fileId` 这类内部标识，见第 5 节。
- 从 Codex 历史重新载入（切到新对话再切回主会话）：刚才那一轮只剩“想了 5 秒”，没有步数，也不能展开（`real-03-reloaded-from-codex.jpg`）。这说明 `thread/read` 只返回消息，与 v1 调研 T4 一致。
  - 我据此加了内存缓存（决策 6）。
  - 由于真实宿主实验只做一次，这个缓存是用一个临时单元测试验证的：存根端口的历史只有消息，在同会话和另一会话分别看过回合后再切换，两处都保留了 1 条命令步骤；不加缓存则为 0。测试跑完已删除。
- 会话列表：“主对话”置顶，下面是旧会话（`real-04-sessions.jpg`）。

### 检查

- `flutter analyze --no-pub lib/next`：`lib/next/ui` 没有问题。剩下 20 条 info 都在合并进来的后端文件里（`capabilities/*`、`ui_data/service.dart` 的花括号），不是这次改的。
- 迭代时只跑了单个测试文件。X31 合并后排队跑了一次完整的 `flutter test --no-pub test/next`：426 项通过，4 项跳过。

### 合并过程

- 第一次 `git merge --no-commit next/capability-layer` 合到 800987e8，没有冲突。
- 后来协调者通知 Y2、Y4、X31 已经合入。当时上一次合并还没有结束，不能直接再合并，所以按以下步骤处理：
  1. 把全部改动备份到 `/tmp/nipa-next/y3/backup-044515/`，包括补丁和新文件；
  2. 把工作树还原到合并结果；
  3. 中止旧的合并；
  4. 重新 `merge --no-commit` 到 d232b5a8，没有冲突；
  5. 用 `git apply --3way` 打回我的补丁。
- 有 6 个文件冲突，都按“两边功能都保留”处理：
  - `conversation.dart`：用 `choice.target()` 代替 `port.mainThread()`；
  - `top_bar.dart`：用我的点击逻辑，尺寸沿用 Y4 的 `_avatar`；
  - `words.dart`：Y2 的 `season` 和我的 `duration` 并存；
  - `shell_controller.dart`：Y2 的 `origins` 和我的侧栏并存；
  - `debug_extension.dart`：用 Y2 的 `tap`/`_click`，加上右键参数，删掉我那份旧的 `window`；
  - `fake_world.dart`：用我的假会话，补上 X31 的 `switchThread` 和列表格式。
- `chat_port.dart` 虽然没有报冲突，但接口重复了，我手工去掉了自己的临时 `setMainThread`，以及按最近线程推断主会话的代码。
- 最后用 `git read-tree` 把暂存区恢复成纯合并结果。
- 我核对过：Y2、Y4、X31 在重叠文件里新增的行，除了被我有意替换的 X31 假会话方法，全部保留了。

## 5. 还没做到 / 需要决定的问题

**还没做到的**

1. **X31 接上后，没有在真实宿主上复测。** 唯一一次真实宿主实验是在 X31 合并前做的。接上后只用模仿 X31 列表格式的假端口、分析和完整测试验证过。建议再做一次真实宿主检查：首次启动没有主会话时由 `mainThread()` 创建；重启后恢复主会话；`switchThread` 后 `chat.session.list` 的 isCurrent 是否一致。
2. **后端接口缺一项：回合步骤的历史。** Codex 的 `thread/read` 只有消息，重启后历史回合无法回看步骤。需要后端按 threadId 和 turnId 提供这一回合的命令和结果。X31 的日志里已经有 `chat.turn_boundary` 和带 `harness_cli:chat:<sessionId>` 来源的调用记录，可以据此提供；界面已经在 `_loadHistory` 留好了接入点（`TurnActivity`）。思考摘要可能只能来自宿主自己保存的显示事件。这一项我没有改后端。
3. 首页舞台上的状态行不能展开，要展开需要点“展开”进侧栏。规范只要求侧栏可以展开。
4. 详情页的“问 Nipa”按钮没有合成点击入口。验证用的是同一个 `openPanel(about:)` 调用（调试命令 `panel about=`），不是点击那个按钮本身。

**需要你决定的**

1. **当前会话要不要自动回到主会话？** 现在用户选了旁支会话或开了新对话后，首页输入栏和 ⌘K 会一直进入它，直到用户在列表里选回“主对话”。可以考虑在关闭侧栏时、静置一段时间后，或从首页说话时，自动回到主会话。
2. **规范需要更新：**
   - 本分支 `INTERACTION.md` 第 48 行“在首页说出的每个新意图，都开一个新会话”与主会话模型矛盾；
   - 「打开与工作过程（2026-10-12 补充）」只在主仓库未跟踪的 `docs/next/proposals/visual/INTERACTION.md` 里，本分支的规范还没有这一节。
   
   我没有改规范。
3. **命令输出要不要整理？** 展开后的命令输出是脱敏后的原始 JSON，含内部 ID。它只在用户点开时才出现；是否保持原样，还是只显示摘要（例如“列出 20 部作品”），需要你决定。
4. **“想了 N 秒”是否扣掉等待时间？** 目前计时包含等待用户回答的时间，可以考虑扣除。
5. **主会话的名称。** 列表里叫“主对话”，侧栏标题仍是“Nipa”。如果想用别的叫法（例如不显示名字，只靠置顶），请告诉我。
6. **旁支会话里的后续唤醒。** 按 X31 的决定，嵌入对话中登记的后续会在登记所在的线程里唤醒，包括旁支对话。这种唤醒在首页按后台工作显示，但只有侧栏正好显示那个会话时才看得到过程。是否要求所有后续都进入主会话，需要后端决定。
