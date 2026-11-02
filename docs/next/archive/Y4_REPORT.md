# Y4：Next 顶栏与窗口外观、LAB 标签、书架悬停预览

2026-10-12，worktree `y4-chrome`，分支 `next/y4-chrome`。没有 commit、push，没有改依赖。按协调要求合并了 `next/capability-layer`：先快进到 1559a623（实验实例默认安静），实现完成后由接手的同伴再快进到 800987e8（带进安静实例的附属应用设置、`showBehind`、把前台还给原应用，以及 X28）。改动都在工作区，未提交。实验只用自己复制的 `y4-dev` 配置，结束时已按 PID 退出实例并删除 `y4-dev`。没有启动正式应用，没有碰 ui-demo 实例、别的同伴的实例、登录钥匙串或真实数据目录。

前半部分（第 1–2 节和第 3 节中“合并后复核”之前的内容）是原实现者在合并 800987e8 之前写的；“合并后复核”一节是接手后用合并后的构建重新核对的结果。

## 1. 完成了什么

### 顶栏（`lib/next/ui/shell/top_bar.dart`、`NextMetrics`）

- 顶栏高 52pt（`NextMetrics.topBar`）。导航、任务环、搜索、头像都在这 52pt 的中线（y = 26）上；macOS 上红绿灯也在这条线上（见下面的原生侧）。
- 导航“首页 片库 动态”和内容列左对齐（x = 96，和主视觉里 Nipa 的那句话、Logo、按钮同一条竖线）。红绿灯右缘在 79，留出 17pt。规则是 `max(96, 红绿灯右缘 + 16)`，以后系统的红绿灯再变宽，导航会自动让开。
- 文字行高固定为 20pt，整个顶栏高度都是点击区域。当前项的绯红小点在文字下方居中，和文字盒底部固定相距 3pt（离字形底部约 6.8pt），不再依赖外层盒子的高度。
- 右侧：任务环（32 高）、搜索（32）、头像（28，原来 30），间距 12，右边距 28（`NextMetrics.chromeEdge`）。头像连同外圈完整显示在 12–40pt 之间，离窗口上沿 12pt。两个弹出层的位置改为根据这些常量计算（`NextTopBar.tasksRight` / `avatarRight`），出现在顶栏下方 4pt。
- **全屏**：红绿灯消失，导航用 320ms 平滑移到顶栏的外边距（x = 28，和右侧边距对称），不留下空白；内容列仍在 96。退出全屏后移回 96。

### 原生侧（`macos/Runner/MainFlutterWindow.swift` 末尾的 `NextWindowChrome`）

- 通道 `nipaplay/next_chrome` 只有一个方法和一个回调：Dart 调 `set(bool)`，表示 Next 是否正显示在屏幕上；原生返回、并在全屏变化时回调 `layout`，内容是 `{leading: 红绿灯右缘, fullScreen}`（全屏时 leading 为 0）。
- Next 显示时，给主窗口挂一个**没有任何项目的统一样式工具栏**（`toolbarStyle = .unified`，`titlebarSeparatorStyle = .none`）。AppKit 因此把标题栏区域定为 52pt，并按 Safari 那类窗口的规矩自己摆红绿灯：本机（macOS 26.7）实测为 x = 19 / 42 / 65、14×14，中心 y = 26。
- 进入全屏前摘下工具栏，退出全屏后再装回（原因见“实验”中的第一次全屏）。全屏期间窗口和 Classic 一样，没有固定在上方的空工具栏条带。
- Next 不在屏幕上时（关闭“使用 Next 界面”，或者正在用 Classic 的播放页播放），摘掉工具栏，并恢复进入前保存的 `toolbarStyle` 和 `titlebarSeparatorStyle`。偏好关闭时这个通道根本不会被调用，Classic 的窗口和原来一模一样。
- Dart 侧是 `lib/next/ui/shell/window_chrome.dart`：`NextWindowChrome.layout` 供顶栏读取；`NextWindowChrome.showing` 供 LAB 标签读取；`NextWindowChromeScope` 放在 `NextUiGate` 里，`active = !playing`，在帧结束后同步状态。

### LAB 标签

- `lib/main.dart` 全局覆盖层里的标签改为监听 `NextWindowChrome.showing`：Next 显示时，换成左下角的小标签 `NextLabBadge`（10pt 灰字加一个橙色小点，半透明深色底，不可点击，大约 80×16）；其余时候还是原来右上角的橙色标签，代码、样式和位置都没有变。只在实验配置（`LabProfile.active`）下出现。

### 首页

- **主视觉的上边距**：Nipa 那句话的最小上边距由 `topBar + 20` 改为 `topBar + 40`（92pt）。这只在窗口较矮、主视觉放不下时起作用；在 1100×760 下，那句话顶部离导航文字约 60pt。窗口较高时主视觉贴底排列，这个值不起作用。片库和动态页本来就是 `topBar + 40`，顶栏变矮后随之上移 12pt，和顶栏的距离不变。
- **书架悬停预览**（协调追加的需求，`home_page.dart`、`hero_backdrop.dart`）：
  - 卡片停稳 600ms 后，整块主视觉换成该作品：背景、Logo 或宋体标题、元信息、简介，以及“播放 第 N 集”（取 `work.next`）和“详情”。交叉淡入淡出 400ms。Nipa 的那句话和“正在准备”那一行随原来的文字一起淡出。
  - 鼠标离开书架 300ms 后，整块回到原来的作品，那句话也一起回来。在卡片之间移动只会重新开始计时：快速划过不切换；从一个预览移到另一张卡片，会停在当前预览上，直到新卡片停稳，中间不会闪回原作品。
  - 减少动态效果时不做预览；对话（B）开始时清掉预览；悬停的正是当前主视觉作品时，不算预览。
  - 原来的文字只是淡出，**仍然占着布局**，预览文字底部对齐叠在上面。这样无论两部作品的文字高度差多少，输入栏和书架都不会移动，鼠标下的卡片也不会被挤走。窗口很矮时，如果不这样做，书架移动会让悬停离开卡片，然后又回来，反复抖动。
  - 背景交叉淡入的时长成为 `HeroBackdrop.fade` 参数：A（预览）用 400ms，B（对话舞台）保持原来的 600ms。

### 调试扩展（只在 Debug + 实验配置下注册，`ext.nipaplay.nextui`）

新增三个操作：`window`（`size=WxH` / `maximize=` / `fullscreen=`，不激活窗口）、`chrome`（顶栏各项的矩形和红绿灯右缘）、`interface next=true|false`（切换“使用 Next 界面”；切到 Classic 后，这几个操作仍然可用）。

### 测试

`test/next/ui_gate_test.dart` 增加了一项守护：偏好关闭或 Next 关闭时，`nipaplay/next_chrome` 一次也不会被调用，`showing` 保持 false，也就是 Classic 的窗口不会被改动。合并 800987e8 之后，按 TEAM.md 排队先跑了相关的 `test/next/ui_gate_test.dart`（2 项通过），再跑完整的 `flutter test --no-pub test/next`：412 项通过，4 项跳过，没有失败（合并前是 407 项通过、4 项跳过，多出的 5 项来自 X28）。`flutter analyze --no-pub lib/next` 有 20 条 info，全部是 `curly_braces_in_flow_control_structures` 一类的风格提示，位于合并进来的 `lib/next/capabilities/` 和已有的 `lib/next/ui_data/service.dart:648`，本次改动的文件里没有任何问题，也没有 warning 或 error。

## 2. 决策

1. **用空的统一工具栏，而不是自己挪标准按钮。** Electron 的 `trafficLightPosition` 和 Tauri 的做法，是改 `NSTitlebarContainerView` 的高度，再逐个设置按钮的 origin。但 AppKit 在缩放、换屏、改标题、切换 key 状态、进出全屏时都会重新排标题栏，所以这种做法必须在每次重排后再改一遍，进出全屏时还会跳动。统一工具栏是 AppKit 自己的布局：红绿灯的内边距、间距和垂直居中，都与 Safari 这类窗口一致（macOS 26 上是 19pt 内边距、23pt 间距），缩放和换屏都不需要我们处理，代码只有挂上和摘下两个动作。担心的是工具栏会不会吞掉顶栏的点击。实验中用 `NSThemeFrame.hitTest` 检查：导航、搜索、头像和顶栏空白处命中的都是 Flutter 内容的 `DropTarget` 视图，只有红绿灯本身命中 `_NSThemeCloseWidget` 等系统按钮，所以 Flutter 照常收到点击。拖动窗口和双击缩放仍由 Flutter 顶栏处理，与原来相同。
2. **导航与内容列对齐（96），不按“红绿灯 + 固定间距”排。** 按后者是 101，会和下面的内容错开 5pt，看起来像没对齐。17pt 的间距和 Safari、Chrome 第一个控件与红绿灯之间的距离相当。
3. **全屏时导航移到 28（与右边距对称）**，而不是继续和内容列对齐。用户明确说不要留下红绿灯那块空白。如果更希望全屏时也和内容列对齐，只需改 `_left` 一行，见“问题”。
4. **全屏时摘掉工具栏。** 默认情况下，全屏窗口的工具栏会固定显示在顶部，会成为一条盖住顶栏、又吃掉点击的条带。让它随菜单栏自动隐藏需要窗口 delegate，而 delegate 被 `window_manager` 占用，所以这里直接摘掉，全屏时的行为和 Classic 一致。
5. **LAB 标签的开关跟着“Next 是否在屏幕上”，而不是跟着偏好。** 开着 Next 播放视频时显示的是 Classic 播放页，窗口外观和 LAB 标签也都回到 Classic 的样子，与当时看到的界面一致。
6. **能力覆盖**：窗口外观、LAB 标签和悬停预览都只是展示，没有新增用户可做的操作，所以没有对应的 Action 或设置 schema。

## 3. 实验

环境：本 worktree 的 Debug 构建，`NIPAPLAY_PROFILE=y4-dev`（ui-demo 的副本），并设置 `NIPAPLAY_NEXT_UI_FAKE=/tmp/nipa-next/visual/tmdb NIPAPLAY_NEXT_UI_FAKE_CHAT=1`。实例是安静的：不激活、不抢焦点，没有像素点击，也没有移动鼠标。状态全部用调试扩展切换，截图用 `screencapture -x -o -l<窗口号>` 只截自己的窗口。迭代阶段用 `flutter attach` 加 SIGUSR1 热重载同一个实例，最后用最终构建重新完整验证一遍。

测量：截图是 2x。用 `/tmp/nipa-next/y4/tools/img`（CoreGraphics 写的小工具）找出亮于阈值的像素行，换算成 pt；同时用调试扩展的 `chrome` 操作读出 Flutter 侧各项的矩形。

| 场景 | 红绿灯（像素实测） | “首页”字形（像素实测） | 搜索 / 头像（布局） |
|---|---|---|---|
| 普通窗口 1512×870 | y 19.0–33.0，中心 **26.00**；x 19–79 | y 19.5–32.5，中心 **26.00**；x 从 97 起 | 10–42 / 12–40，中心 26 |
| 窄窗口 1100×760 | 中心 **26.00** | 中心 **26.00** | 中心 26 |
| 全屏 1512×949 | 不在窗口内（leading = 0） | 中心 26，x 从 28 起 | 中心 26 |
| 退出全屏后 1100×760 | 中心 **26.00**，x 19–79 | 中心 26.00，x 从 97 起 | 中心 26 |

三者偏差都小于 0.5pt。小点在“首页”下方，水平居中（文字中心 115.2，小点中心 115.4），y 为 39.3–42.7。

- **点击是否被工具栏吞掉**（只在实验构建里加过一个原生探针，之后已删除）：顶栏上的五个元素和空白处 (300, 26)、(700, 45)、(26, 48) 都命中 `DropTarget`；三个红绿灯分别命中 `_NSThemeCloseWidget`、`_NSThemeWidget`、`_NSThemeZoomWidget`。挂上工具栏后，`contentLayoutRect` 从 52 开始，标题栏容器高 52。
- **Classic 对照**：先关闭偏好重新启动一次，作为 Classic 基准：红绿灯 x 9–23、中心 y 16（标题栏 32pt），LAB 标签在右上角。然后在 Next 实例里用 `interface next=false` 切回 Classic：原生读到的按钮框是 (9, 9, 14, 14)，标题栏容器 32，与基准一致；截图中的位置和标签也一致。来回切换多次，窗口尺寸都保持 1100×760 或 1512×870 不变。（两次启动时窗口高度分别是 872 和 870，是启动时屏幕可用区域不同造成的：在 Classic 下设 872 同样会被限制到 870，与这次改动无关。）
- **全屏，第一次**：进入全屏正常，导航移到 28，没有条带。但退出后红绿灯停在标准位置（y = 16）。当时是在进入前把工具栏设为隐藏、退出前设回显示，AppKit 在退出后恢复了它保存的“隐藏”状态。**改为进入前摘下、退出后装回**，重新构建后又做了第二次全屏：退出后红绿灯中心回到 26.00，leading 为 79，窗口恢复到 1100×760。因为第一次发现了问题，全屏一共做了两次，不是一次。
- **悬停预览**：预览后整块主视觉换成【我推的孩子】（“播放 第 14 集”），Nipa 的那句话和“正在准备”那一行隐去，输入栏和书架没有移动。离开后 150ms 仍是预览，1.15s 后回到芙莉莲，那句话和“正在准备”也回来了。以 250ms 的间隔连续划过 6 张卡片时，主视觉始终是芙莉莲；停在迷宫饭上之后才切到迷宫饭。从迷宫饭移到孤独摇滚：350ms 时仍是迷宫饭，没有闪回，随后换成孤独摇滚。打开“减少动态效果”时，悬停只有卡片自身的播放键，主视觉不变。
- **弹出层**：任务面板的右缘比任务环右缘多出 13pt，Nipa 菜单比头像多出 8pt，都出现在顶栏下方 4pt，与原来的比例相同。

意外和需要说明的事：

- 在一次 Classic 启动之后、以及第一次全屏之后，`lsappinfo front` 显示前台应用是“NipaPlay”，但无法区分是哪一个实例（ui-demo、y3-dev 也开着）。全屏会切换桌面空间，这在预期之中。第二次全屏结束后，前台是 Terminal。
- `preview-1100-dungeon.png` 中的红绿灯处于悬停状态（带符号），这是系统根据当时真实鼠标的位置绘制的，不是我们移动了鼠标。
- 迭代时做过一次热重启（SIGUSR2），它会重新执行启动时的窗口代码；之后都只用热重载。
- 失误：清理自己后台的 `tail -f /dev/null` 时，用了按命令行匹配的 `pkill -f`，而不是按 PID。没有证据表明它匹配到了别人的进程，但这不符合“只按 PID 操作”的约定，以后不会再这样做。
- 构建环境：这个 worktree 原本缺 `.dart_tool/package_graph.json` 和 SPM 派生包 `macos/Flutter/ephemeral/Packages`。我从 ui-shell 复制了这两项，并把 `volume_controller` 的链接改到本 worktree，没有重新解析依赖。两项都在 gitignore 里。

### 合并后复核（接手后，合并到 800987e8）

- **合并**：工作区改动先备份为 `/tmp/nipa-next/y4/y4-before-merge2.patch`，`git stash` 后 `git merge --ff-only next/capability-layer`（44720e5d → 800987e8，快进，没有产生提交），再 `git stash pop`，没有冲突。`MainFlutterWindow.swift` 里安静模式的 `setActivationPolicy(.accessory)`、实例通道的 `showBehind` 和本次的 `NextWindowChrome` 注册都在；`lib/main.dart` 里 `skipTaskbar: LabProfile.quiet` 和本次的 LAB 标签改动也都在。`AppDelegate.swift`、`SandboxMigration.swift` 本次没有改，直接取合并后的版本。随后按要求重新构建 Debug 版，成功。
- **实例**：只启动了一个 `y4-dev` 实例（PID 19247，ui-demo 的副本，删掉了 `endpoint.json` 和 `single_instance/` 下的文件），全程用调试扩展驱动，`screencapture -x -o -l<窗口号>` 只截它的窗口。它是附属应用，从不成为 key 窗口，所以截图里的红绿灯是灰色的（未激活的样子），不是颜色被改了。结束时 `kill -TERM 19247`，确认退出后删除了 `y4-dev`。期间看到另一个 Debug 实例（PID 23341，工作目录是 `y2-detail`，属于别的同伴），没有碰。
- **中线对齐**（像素实测，2x 截图换算成 pt；导航和搜索取亮于阈值的像素，头像取偏红像素，红绿灯在灰色状态下取亮度 > 40 的像素，三个阈值 35–50 结果相同）：

| 场景 | 红绿灯 | “首页”字形 | 头像 | 搜索 / 头像（布局） |
|---|---|---|---|---|
| 默认 1512×868 | y 19.0–33.0，中心 **26.00**；x 19–33 / 42–56 / 65–79 | y 19.5–32.5，中心 **26.00**；x 从 97 起 | y 12.0–40.0，中心 **26.00**，完整 | 10–42 / 12–40 |
| 1100×760 | 中心 **26.00**，x 19–79 | 中心 **26.00** | 中心 **26.00**，完整 | 10–42 / 12–40 |
| Classic 往返后回到 Next | 中心 26.00，x 19–33 | 中心 26.00 | — | `leading` 79 |
| 最大化 1512×868 | 中心 26.00，x 19–33 | 中心 26.00 | — | `leading` 79 |

三者偏差为 0（在 0.5pt 的测量粒度内）。对照修改前（`zoom-before-left.png` / `-right.png`）：红绿灯在 32pt 标题栏里、导航比红绿灯低，LAB 标签压在任务环和头像上，头像上沿被裁掉；修改后这些都没有了，LAB 小标签在左下角。

- **悬停预览**（1100×760，调试扩展 `hover index=N area=shelf`，脚本 `/tmp/nipa-next/y4/preview_check.py`，截图本身约 0.15s）：
  - 停在第 2 张卡片 0.35–0.5s 时，主视觉仍是芙莉莲；约 1.3s 时整块换成【我推的孩子】（背景、Logo、元信息、简介、“播放 第 14 集”和“详情”），Nipa 的那句话和“正在准备”那一行都已淡出，输入栏和书架没有移动。
  - 停稳后约 0.75s（淡入进行到一半）的截图里，药屋少女和芙莉莲两份文字叠在一起，那句话和“正在准备”半透明，确实是交叉淡入。
  - 离开书架约 0.12s 时仍是预览；约 1.2s 后回到芙莉莲，那句话和“正在准备”回来。
  - 以约 0.26s 的间隔依次划过 3 张卡片：划过时主视觉始终是芙莉莲；停在最后一张（迷宫饭）上约 1.6s 后换成迷宫饭。
  - 从迷宫饭的预览移到第 2 张卡片：0.35s 时仍是迷宫饭，没有闪回芙莉莲；1.3s 时换成【我推的孩子】。
  - `reduce on=true` 后悬停第 3 张卡片 1.5s：主视觉不变，只有卡片自己的播放键。随后恢复 `reduce on=system`。
- **Classic**：`interface next=false` 后，红绿灯回到 x 9–23、y 9–23（中心 16，32pt 标题栏），与合并前 Classic 首次启动的基准（`/tmp/nipa-next/y4/final/classic-fresh.png`）一致；LAB 标签回到右上角，仍是原来的橙色样式。切回 Next 后红绿灯又回到中心 26。
- **全屏：合并后没能触发。** `window fullscreen=true`（`window_manager.setFullScreen` → `toggleFullScreen(nil)`）之后，窗口仍是 1100×760，原生回报 `fullScreen: false`，截图也不是全屏（`fullscreen-attempt-noop.png`）；随后发 `fullscreen=false` 也没有任何变化，前台应用前后都是 Terminal，没有占用用户的屏幕。原因推断是合并进来的 cd02f863：安静实例现在是附属应用（`.accessory`），AppKit 不会自动给附属应用的窗口加 `.fullScreenPrimary`，`toggleFullScreen` 就成了空操作。合并前（实例还是普通应用）同一份 `NextWindowChrome` 代码已经验证过两次全屏，见上文；合并没有改这段代码。我没有用 `NIPAPLAY_LAB_QUIET=0` 重启去绕过，因为那会激活窗口。
- **意外**：`run.log` 里出现过一行 `Resize timed out`，出现在调试扩展改窗口尺寸的时候；之后尺寸和布局都正确，截图也正常。unmaximize 后窗口回到 1440×836，而不是最大化前的 1100×760，这是 `window_manager` 的还原行为，与本次改动无关。

## 4. 问题（需要主控决定）

1. **全屏时导航的位置**：现在是 28（与右边距对称，不留红绿灯的空白）。如果更希望和内容列一起停在 96，改 `NextTopBar._left` 一行即可。
2. **退出全屏的瞬间**：工具栏在退出动画结束后才装回，红绿灯会在那一刻从标准位置跳到居中位置（向下、向右各约 10pt，一次）。截图只验证了最终位置，没有逐帧观察过渡。如果要消除这一下跳动，需要接管窗口 delegate 的全屏呈现选项，而 delegate 现在归 `window_manager`。
3. **LAB 小标签**在左下角，右缘约在 92pt，离第一张卡片只有约 4pt。配置名很长时会压到卡片的左下角（它不可点击）。需要的话可以再缩短，或者只显示一个点。
4. **没有实测的部分**：显示器切换（本机只有一块屏幕，这部分由 AppKit 自己布局，与缩放的原理相同）；开着 Next 真实播放视频时切到 Classic 播放页（和 `interface next=false` 走同一条代码路径，没有用真实视频验证）。
5. **安静实例无法全屏**：合并 800987e8 后，安静的实验实例是附属应用，`toggleFullScreen` 不起作用，所以合并后的构建没有复测全屏（合并前已测两次）。这只影响实验实例，正式应用仍是普通应用。如果以后需要在安静实例里测全屏，可以考虑在安静模式下给主窗口的 `collectionBehavior` 加上 `.fullScreenPrimary`（属于 Classic 原生代码和实验基础设施，本次没有改），或者由用户在场时用 `NIPAPLAY_LAB_QUIET=0` 演示。另外值得确认：附属应用的绿色按钮是否也就此变成“缩放”而不是“全屏”，这会影响在实验实例里演示全屏相关的功能。

## 5. 改动的文件

| 文件 | 改动 |
|---|---|
| `macos/Runner/MainFlutterWindow.swift`（Classic 原生） | 末尾新增 `NextWindowChrome`；`MainFlutterWindow` 多了一个属性，`awakeFromNib` 多一行注册。偏好关闭时不会被调用 |
| `lib/main.dart`（Classic） | 一行导入；全局覆盖层的 LAB 标签外面包了 `ValueListenableBuilder`。Next 不在屏幕上时，原来的标签逐字不变 |
| `lib/next/ui/shell/top_bar.dart` | 顶栏布局、导航项、全屏调整、弹出层锚点 |
| `lib/next/ui/shell/next_ui_gate.dart` | Next 分支外面包一层 `NextWindowChromeScope(active: !playing)` |
| `lib/next/ui/theme/tokens.dart` | `topBar` 改为 52，去掉 `chromeRow`，新增 `chromeEdge` |
| `lib/next/ui/home/home_page.dart`、`hero_backdrop.dart` | 悬停预览、主视觉上边距、背景淡入时长参数 |
| `lib/next/ui/dev/debug_extension.dart` | `window` / `chrome` / `interface` 三个操作 |
| `test/next/ui_gate_test.dart` | 偏好关闭时不调用窗口通道 |
| 新增 `lib/next/ui/shell/window_chrome.dart` | 通道、布局与“是否显示”的通知、作用域、`NextLabBadge` |

`docs/next/design/INTERACTION.md` 的改动来自主控（悬停预览规范），`macos/Podfile.lock` 是构建自动改的，这两项都没有动。

## 6. 截图

在 `/tmp/nipa-next/y4/final/`；修改前是 `/tmp/nipa-next/y4-before.png`。

- 整窗：`next-1512.png`、`next-1100.png`、`next-fullscreen.png`、`next-1100-after-fullscreen.png`、`classic-fresh.png`（Classic 基准）、`classic-after-toggle.png`（Next 切回 Classic）
- 顶栏放大：`zoom-next-1512-left.png` / `-right.png`、`zoom-next-1100-left.png` / `-right.png`、`zoom-fullscreen-left.png`、`zoom-after-fullscreen-left.png`、`zoom-classic-fresh-left.png`、`zoom-classic-after-toggle-left.png`、`zoom-lab-badge.png`
- 悬停预览：`preview-1512-oshinoko.png`、`preview-1512-back.png`、`preview-sweep-no-change.png`、`preview-settled.png`、`preview-a2b-300ms.png`、`preview-1100-dungeon.png`、`preview-reduced-none.png`
- 弹出层：`popover-tasks-1100.png`、`popover-nipa-1100.png`

合并 800987e8 后的复核截图在 `/tmp/nipa-next/y4/merged/`：

- 整窗：`next-wide.png`（1512×868）、`next-1100.png`、`next-after-classic.png`（Classic 往返后）、`next-maximized.png`、`next-after-fullscreen.png`（全屏尝试之后）、`fullscreen-attempt-noop.png`（全屏没有生效的那一张）、`classic-after-toggle.png`
- 顶栏放大（4 倍）：`zoom-wide-left.png` / `-right.png`、`zoom-1100-left.png` / `-right.png`、`zoom-classic-left.png` / `-right.png`；修改前对照 `zoom-before-left.png` / `-right.png`（从 `y4-before.png` 裁出）
- 悬停预览 `preview/`：`p1-350ms-still-hero`、`p2-preview-settled`、`p10-crossfade-mid`、`p3-left-120ms-still-preview`、`p4-back`、`p5-sweep-no-change`、`p6-sweep-settled-on-last`、`p7-a2b-350ms`、`p8-a2b-settled`、`p9-reduced-no-preview`

复现脚本在 `/tmp/nipa-next/y4/`：`launch.sh`（启动 y4-dev）、`nextui.py <op> k=v`（调试扩展）、`shot.sh <png>`（按 PID 找窗口截图）、`reload.sh`（配合 `flutter attach --pid-file` 热重载）、`tools/img`（裁剪 / 测量；接手后加了 `red` 模式，用偏红像素测头像）、`preview_check.py <输出目录> <窗口号>`（按时间点驱动悬停预览并截图）。
