# Y1：Next 界面外壳与首页

2026-10-12，worktree `ui-shell`，分支 `next/ui-shell`。没有 commit、push，没有改依赖。按协调要求快进合并了 `next/capability-layer`（fed3c9cc，后端 `NextCore.uiData`）。构建只在本 worktree；实验只用自己启动的 `ui-dev` 实验配置，结束时已按 PID 退出并删除 `ui-dev`。没有启动正式应用，没有碰 lab10 实例、登录钥匙串或真实数据目录。

## 1. 做了什么

全部新代码在 `lib/next/ui/`（约 6.8k 行，含开发用假数据）：

```
theme/tokens.dart        颜色、字体（作品标题 Songti SC、正文 PingFang SC、数字 SF 等宽）、动效曲线、减少动态效果判断
widgets/                 设计基础组件
  grain.dart             颗粒叠层（一次生成噪声贴图，overlay 7%，一个物理像素一个噪点）
  glass.dart             玻璃面板（模糊 + 饱和度）；Tinted 是不模糊的半透明面
  buttons.dart           播放/幽灵/圆形按钮、图标按钮、发送、建议胶囊、⌘K 提示、卡片上的圆形播放键
  nipa_avatar.dart       Nipa 头像：运行时从 assets/images/main_image.png 裁脸（不新增资源）；空闲/思考/执行/等你回答/有新消息，悬停一句话
  progress.dart          进度环、细进度条（运行时有流光）、脉冲点、三个点、步骤标记
  artwork.dart           按显示尺寸解码的本地图片（cacheWidth 以 128px 分档），无图时用 tint 渐变
  cards.dart             16:9 卡片（WideCard）、海报卡片（PosterCard）：悬停 1.03 + 圆形播放键
  shelf.dart             横向书架；words.dart 文案（元信息行、Nipa 的句子、数字混排）
cards/card_views.dart    Agent 卡片的渲染：候选、作品、剧集、准备进度、任务；逐张上浮淡入（12px，60ms 间隔）。侧面板下一阶段可直接复用
conversation/            chat_port.dart（ChatPort 接口 + 接 NextRuntime.chat 的 ChatHostPort）、conversation.dart（B/C 的状态）
shell/                   next_ui_preference.dart（偏好）、next_ui_gate.dart（Classic/Next 切换）、next_shell.dart、top_bar.dart（顶栏、任务环面板、头像菜单）、shell_controller.dart
home/                    home_page.dart、hero_backdrop.dart、hero_copy.dart（含 C 的“正在准备”行）、ask_bar.dart、stage.dart（B）
pages/                   library_page.dart、activity_page.dart、detail_slot.dart（详情页占位路由）
data/                    ui_actions.dart（界面发出的动作）、services.dart（取服务）、core_connect.dart（真实接入点）
dev/                     fake_world.dart（假数据 + 脚本化对话）、dev_services.dart（环境开关）、debug_extension.dart（ext.nipaplay.nextui）
```

要点：

- **外壳**：顶栏导航“首页 / 片库 / 动态”带绯红小点；右侧任务环（有任务才出现，点开是任务卡片面板，可暂停/继续/取消）、搜索（目前等同 ⌘K）、头像（点开菜单：“问 Nipa”“回到经典界面”）。⌘K 聚焦首页输入栏（其他页面先回首页；侧面板留了 `openPanel` 槽位）。Esc 逐层关闭：面板 → 弹出层 → 推入页 → 就地对话 → 输入栏焦点。分区切换淡入并从 0.98 放大，320ms；访问过的分区保持挂载，滚动位置不丢。详情走嵌套 Navigator 的 `/work` 路由，首页留在下面。
- **首页 A**：主视觉 20 秒 1.00→1.05 来回推近；A 与 B 的取景按 concept（`center 30%` 的 660px 主视觉与 `center 35%` 的整屏）用变换切换，不重新布局图片。Nipa 的一句话、Logo（无 Logo 用宋体，长标题降到 52/44px）、元信息、两行简介、“播放 第 N 集”（只有可播放时出现）和“详情”。输入栏常驻主视觉下方，右侧建议按宽度显示 2–3 个，点一下等于说出口。书架：继续观看（16:9 + 进度条）、Nipa 的书架（海报 + 理由）、最近添加；悬停 600ms 后主视觉交叉淡入该作品背景，离开淡回。Nipa 没摆主视觉时依次取最近添加、有更新、继续观看第一部。
- **首页 B**：发送后作品信息淡出、对话舞台淡入，输入栏随内容平滑下移。你的话小号灰字；回复大号白字逐字出现；思考时头像旁三个点；卡片逐张出现；悬停或选中作品卡片时背景 600ms 跟随（默认第一张）。在 B 里继续说话沿用同一会话；从 A 说出的新意图开新会话。Esc 或 10 分钟静置回到 A，Nipa 的一句话换成这次结论；若对话落在一部作品上（单张作品/剧集卡），主视觉换成它，“播放 第 N 集”对应那一集。等你回答时出现问题和选项按钮，也可以直接打字回答。3 分钟没有任何事件时显示“好像没有回应”和“再等等 / 重新发”，不自动中断。
- **首页 C**：有后台任务时头像保持空闲，任务环显示总进度，Nipa 的一句话下多一行“正在准备”（封面、名字、细进度条、剩余时间），点开显示步骤。后续唤醒（宿主上出现不是首页发起的回合）时头像外圈转起来，句子换成正在做的事（取准备卡片里运行中的步骤，比如“在补弹幕”），做完换成结果；不在首页时头像右上角出现小红点，结果在首页显示 3 秒后自动清除。
- **减少动态效果**（跟随系统，或调试扩展强制）：关闭推近、视差、背景跟随、悬停放大、卡片上浮、选中上移、流光、头像转动，只保留淡入淡出。
- **性能**：模糊只用在输入栏、任务环和两个弹出面板上；卡片和建议胶囊不模糊。持续动画只改变换和透明度，推近的背景单独一层 RepaintBoundary；书架只在首页数据变化时重建，不随回复逐字重建。图片按显示尺寸解码，不放大。

### 数据与动作

- **真实接入点**：`data/core_connect.dart` 的 `coreUiData(core)`，现在返回 `NextCore.uiData`（等 `core.ready` 之后再读，外壳可能比 Core 先出现）。后端换实现只改这一处。
- **动作**（`NextUiData` 只读，所以另起 `NextUiActions`）：暂停/继续/取消调用 `core.engine`（taskId 即 jobId）；播放走 Agent 用的同一个 `ui.open {entityId: episodeId}`，来源 `gui`，多个位置时取第一个。
- **对话**：`ChatHostPort` 包装 `NextRuntime.chat`，用 `prepareFollowup / startFollowup`，和后续任务在宿主里串行，不会把话发到别的线程上；宿主忙时排队等。
- **假实现**只在 Debug 且实验配置激活、并设置 `NIPAPLAY_NEXT_UI_FAKE=<目录>` 时才用（`kDebugMode` 为常量，发布构建里这条分支和扩展都会被裁掉）。它读 `/tmp/nipa-next/visual/tmdb/meta.json`，同时实现 `NextUiData` 和 `NextUiActions`；`NIPAPLAY_NEXT_UI_FAKE_CHAT=1` 时用脚本化对话（发出与宿主相同格式的 display 消息，界面只有一条代码路径），否则仍接真实宿主。
- **调试扩展** `ext.nipaplay.nextui`：只在 Debug + 实验配置注册，不是 harness Action，Agent 用不到。支持 status、home A/B/C、fill/send、hover 第 N 张卡片或头像（在 Flutter 内注入合成鼠标，不动系统光标）、section、open/play、escape、popover、panel、reduce。

## 2. 改了哪些 Classic 文件

| 文件 | 改动 | 原因 |
|---|---|---|
| `lib/main.dart` | 2 行导入；`MultiProvider` 加 `NextUiPreference`（非 Web）；桌面/平板主页由 `MainPage(...)` 改为 `NextUiGate(classic: MainPage(...))` | 唯一的切换点。偏好关闭（或 Next 关闭）时 gate 只返回 Classic，外层的 ExcludeFocus/Offstage/TickerMode 都是无效状态；手机、电视、Web 不变 |
| `lib/settings/pages/labs_settings_content.dart` | 在 NipaPlay Next 已开启时多一个开关“使用 Next 界面” | 入口放在开启 Next 的同一处 |

偏好本身（`labs_use_next_interface`）放在 Next 自己的 `NextUiPreference` 里，没有改 `LabsSettingsProvider` 和 `SettingsKeys`。`macos/Podfile.lock` 是构建自动改的，未处理。

开启时 Classic 仍挂在下面（服务、热键、播放器照常），只是隐藏且不可聚焦；视频打开期间（loading/ready/playing/paused）gate 显示 Classic 的播放页，关闭后回到 Next。Classic 用 GlobalKey 保持同一个实例，切换不会重建 MainPage。`test/next/ui_gate_test.dart` 守住“偏好关或 Next 关时只有 Classic”。

## 3. 截图对照

实验环境：本 worktree Debug 构建，`NIPAPLAY_PROFILE=ui-dev`（lab10 的副本），调试扩展切状态，`screencapture -l<窗口号>` 只截自己的窗口。屏幕可用高度只有 874pt，“1440×900”实际是 1440×874（整体比 concept 高约 26px）；1280×800 是原尺寸。前期截图时把 Classic 的实验角标临时移到左下角，避免它挡住顶栏右侧，最终构建已改回。

截图在 `/tmp/nipa-next/y1/final/`：

- 对照图（左 concept，右实现）：`compare-home.png`、`compare-converse.png`
- 1440：`1440-A.png`、`1440-A-hover.png`（书架悬停 600ms 后背景跟随、卡片 1.03 + 播放键）、`1440-B-thinking.png`、`1440-B.png`、`1440-B-hover.png`、`1440-A-after.png`（回到 A 后句子换成结论）、`1440-C-wake.png`（“在补弹幕”，头像外圈转动，悬停显示句子）、`1440-C-done.png`、`1440-library.png`、`1440-activity.png`、`1440-detail-slot.png`、`1440-popover-nipa.png`、`1440-final-build.png`
- 1280：`1280-C.png`、`1280-popover-tasks.png`、`1280-B.png`、`1280-B-prep.png`（作品卡 + 准备进度卡）、`1280-reduced-hover.png`
- 其他实验：`/tmp/nipa-next/y1/real-B-done.png`（真实对话宿主）、`real-A.png`（真实后端数据）、`play-classic.png` / `after-close.png`（播放交接）、`B-question-c.png`（等你回答）

结论：首页 A 与 B 的版式、颜色、字体、渐变、颗粒、圆角和 concept 基本一致；B 帧连同“你 来点轻松的，今晚就看一会儿”和输入栏里的“那就孤独摇滚吧”几乎重合。差异：

1. 顶栏这一行对齐的是 macOS 原生红绿灯（约 17pt），concept 是 32px。
2. concept 主视觉上有淡淡飘过的弹幕；数据契约里没有可显示的弹幕句子，这次没做。
3. concept 首页同时有任务环 47%，但规范 C 里任务在跑时还要多出“正在准备”一行；两者不能同时成立，A 的对照帧去掉了任务。
4. 继续观看卡片按 concept 用 296×150（约 2:1），不是严格的 16:9；剧集卡是 16:9。

另外三项实验：

- **真实对话宿主**：在 ui-dev 的 `codex-home` 里配置无凭据的回环 provider（`/tmp/nipa-next/y1/mock_provider.py`），经 `NextRuntime.chat` 跑了两轮（同一线程），delta 逐段到达，回合结束后读卡片，画面与脚本化对话一致。
- **真实后端**：不设假数据时，`NextCore.uiData` 给出 lab 副本里的作品。没有 TMDB 令牌，图片全为 null，降级正常：宋体标题、tint 或绯红微光背景、深色占位卡片。播放过程中 `changes` 推来新入库作品，首页实时刷新。
- **播放交接**：Next 的播放按钮走到 `ui.open → playback.open → PlaybackService`，但这个作品来自没在运行的测试 Emby，以 error 结束，Next 保持可见。改用一个本地无声视频，通过 `playback.open` 打开后 gate 显示 Classic 播放页；`playback.close` 后回到 Next。

检查：`flutter analyze --no-pub lib/next` 只剩后端文件 `lib/next/ui_data/service.dart:648` 的一条 info；`flutter test --no-pub test/next` 401 项通过、4 项跳过。这台机器设置了 `HTTP_PROXY`，flutter test 需要带 `NO_PROXY=127.0.0.1,localhost`，否则测试进程连不上工具。

## 4. 还没做到的

- 详情页、对话侧面板、共享元素过渡、详情视差：只留了路由、`openPanel` 和 Hero 的位置。`detail_slot.dart` 只是占位。⌘K 在其他页面目前是回首页并聚焦输入栏。
- 主视觉弹幕没做（缺数据）。
- 片库页暂时用首页数据里的作品（契约里没有片库列表）；动态页只有任务和 Nipa 最近一句话。
- “正在准备”点开的步骤来自最近一张准备卡片；`UiTask` 本身没有步骤，没有对应卡片时展开的是任务列表。
- Classic 的弹窗（例如播放失败的“播放错误”）会盖在 Next 上，样式不统一。
- 没有在 app 里实测：10 分钟静置回 A、3 分钟“好像没有回应”（代码按宿主的 liveness 判断）；实验室设置页里的新开关（设置侧栏用合成事件滚不到“实验室”，只验证了偏好读写和“回到经典界面”）；真实键盘输入中文（合成按键经输入法会变成乱码，改用扩展的 fill）。
- 实验构建日志里有 audioplayers / gamepad 的 MissingPluginException，与本次改动无关，没有处理。

## 5. 需要你决定的

1. **红绿灯位置**：继续让顶栏对齐原生红绿灯（约 17pt），还是改 Classic 原生窗口代码（`MainFlutterWindow.swift`）把红绿灯下移到 concept 的 30px？后者要动 Classic 原生代码。
2. **继续观看卡片比例**：保持 concept 的 296×150，还是改成严格 16:9（296×166）？
3. **弹幕与步骤的数据**：主视觉弹幕需要 `UiHero` 带几句弹幕；“正在准备”点开步骤需要任务能对应到步骤。两者都要改数据契约，要不要做？
4. **Classic 弹窗**：在 Next 打开时，是否由 Next 接管播放错误等提示？
5. **“使用 Next 界面”是否注册进设置注册表**，让 Agent 也能切换？目前没有注册。
6. **播放有多个位置时**直接取第一个（Classic 本来会让用户选）。可以接受吗？
7. **Nipa 的书架用海报卡片**（与 B 的候选一致），最近添加用 16:9 卡片。规范只规定了继续观看用 16:9，这样分可以吗？

## 6. 复现

```bash
# 构建（只在本 worktree）
ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
# 假数据 + 脚本化对话
NIPAPLAY_PROFILE=ui-dev NIPAPLAY_NEXT_UI_FAKE=/tmp/nipa-next/visual/tmdb NIPAPLAY_NEXT_UI_FAKE_CHAT=1 \
  build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
# 切状态（读运行日志里的 VM service 地址）
/tmp/nipa-next/y1/nextui.py home state=B text=来点轻松的
/tmp/nipa-next/y1/nextui.py hover index=1 area=shelf
/tmp/nipa-next/y1/shot.sh out.png 1440
```

其他开关：`NIPAPLAY_NEXT_UI_FAKE_TASKS=0` 关后台任务，`NIPAPLAY_NEXT_UI_FAKE_FOLLOWUP=<秒>` 让 Nipa 自己醒来，`NIPAPLAY_NEXT_UI_REDUCE_MOTION=1` 强制减少动态效果。这个 worktree 原本缺 `.dart_tool/package_graph.json` 和 SPM 派生包，构建前从 ui-data / chat-host worktree 复制了这两项（包路径改成本 worktree），没有重新解析依赖。
