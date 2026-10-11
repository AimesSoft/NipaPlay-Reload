# Y2 报告：作品详情页

2026-10-12，worktree `y2-detail`，分支 `next/y2-detail`。前一位同伴因网络中断，本报告由接手者补完检查后写成。实现大部分出自前一位同伴；接手后改了三处（见「决策」第 9–11 条）。

没有 commit、push，没有改依赖，没有运行 pub get。按要求快进合并了 `next/capability-layer`（44720e5d → 6acd7f9a，带进实验实例的安静模式）。之后 `next/capability-layer` 又前进到 71b3429f（新增 airing 书架和 hero 弹幕的数据契约，只改了 `lib/next/ui_data/`），这次没有合并，和本分支的改动没有文件重叠。

构建只在本 worktree 进行。实验只用自己启动的 `y2-dev` 实验配置，全程只开一个实例；每次启动后 `lsappinfo front` 都还是 Terminal。结束时按进程号退出实例，并删除了 `y2-dev`。没有启动正式应用，没有碰其他实例（`ui-demo`、y3-panel、x31-sessions 的实例都在运行，没有动）。

## 1. 完成了什么

INTERACTION.md「详情」一节的全部内容，以及全局里的「共享元素过渡」：

- **进入与返回**：点击作品图片（首页主视觉、继续观看等书架卡片、对话舞台的卡片、片库海报）后，图片放大铺满，成为详情页背景；作品信息随后淡入。返回时文字先离开，背景缩回原来的图片。没有可飞的图片时，或系统开启了减少动态效果时，改用外壳统一的页面过渡（淡入，同时从 0.98 放大到 1，320ms）。
- **左侧信息**：原名（小字）、片名 Logo（没有 Logo 就用宋体大标题）、一行元信息（各家评分 · 年份 · 集数 · 制作公司）、两行简介（点“更多”展开）、三个按钮：“继续 第 N 集”（没看过显示“播放”）、“问 Nipa”、“⋯”。
- **“⋯”**：只有“下载全部”一项，只在作品有缺集时出现（有的集还不能播放，或已知集数少于总集数）。点击后替用户对 Nipa 说“把《片名》剩下的集都下载下来”，同时打开侧面板并带上这部作品。“标记看过”和“移除”按决定不显示。
- **剧集**：季标题（多季时带 ▾，展开季列表；第 0 季显示为“特别篇”，没有季信息时显示为“剧集”），下面是横排剧集卡片，每张有 16:9 截图、大号集号、标题、时长和弹幕热度线。看过的集显示满进度条，当前集加白色描边。悬停时卡片放大到 1.03 并出现播放按钮，点击直接播放。横排打开时定位到当前集。
- **滚动**：背景以 0.3 倍速视差移动；滚过 56px 后，大标题缩小、收进顶栏中间，由顶栏的小号宋体标题接替。
- **返回方式**：左上角的返回箭头、鼠标侧键、Esc。

## 2. 决策

1. **共享元素过渡用登记表实现，没有用 Hero**：作品图片用 `ArtOrigin` 登记自己（`widgets/art_origin.dart`）。打开作品时，按以下顺序找起飞的图片：指针下的那张；没有的话，取屏幕上这部作品最大的那张。卡片上的图片在飞行期间从原处隐藏，保证同一张图不会同时出现两次。主视觉这类上面压着文字的背景留在原处，飞行层在它上面淡入，这样文字是淡出而不是突然消失。返回时，如果原页面已经重建，就找同一部作品中离原位置最近的图片。飞行层沿用卡片已经解码好的宽度，避免中途重新解码。
2. **时长与节奏**：进入 560ms，返回 460ms，曲线都是 fastOutSlowIn。进入时，内容在 35%–100% 区间淡入；返回时，内容在前 25% 的时间里淡出。框的位置与大小、圆角、取景和原图上的遮罩都在两端之间插值；从海报飞入时，海报交叉淡入为背景图。
3. **标题收进顶栏**用一个自定义 RenderObject（`detail/docking_title.dart`），画在内容层之上；内容里只留出标题的位置。减少动态效果时只做淡出。
4. **详情页的元信息**显示所有评分（TMDB 和豆瓣并列）和制作公司，不显示类型，和视觉稿一致。首页依旧显示类型。
5. **“问 Nipa”调用 `shell.openPanel(about: work)`**。本分支的 `openPanel` 仍是 Y1 留下的占位：回到首页，聚焦输入栏，`about` 不起作用。Y3（`y3-panel`）实现了同样的签名 `openPanel({UiWork? about})`，合并后就会变成真正的侧面板。
6. **“下载全部”替用户说一句话**，而不是直接调用下载：选版本、补弹幕都是 Agent 的判断，界面只负责把意图说出口。
7. **抽出共用组件**：`WorkTitle`（主视觉和详情页共用 Logo 或宋体标题）、`MenuPanel`/`MenuItem`（头像菜单和“⋯”共用）。主视觉的遮罩改为数据（`ShadeLayers`），以便飞行时和详情页的遮罩插值；`NoArtGlow` 改为公开。占位用的 `pages/detail_slot.dart` 已删除。
8. **只做了 GUI，没有新增 Action**：详情页是作品与剧集数据的一个视图，这些数据 Agent 本来就读得到；页面上的动作也都已经有 Agent 的对应能力：播放对应 `ui.open {entityId: 剧集}`，下载全部对应一句话。见「问题」第 2 条。
9. **（接手后）“⋯”只留“下载全部”**：前一位同伴给 `NextUiActions` 加了 `canMarkWatched` 和 `markWatched`。真实后端的实现返回 false，假数据里却会显示“标记看过”。按“先不显示”的决定，并遵守“不预先建造抽象”的约定，我把接口、真实后端的桩、假数据实现和菜单项都删掉了。`ui_actions.dart` 和 `core_connect.dart` 现在与 HEAD 相同。
10. **（接手后）原名随标题一起淡出**：真实后端实验中，窗口高 600 时滚到底，原名正好落在顶栏的“首页 / 片库 / 动态”这一行，片库下面的绯红小点压在原名中间。现在大标题收进顶栏时，原名同步淡出。
11. **（接手后）演示数据的观看进度与“继续观看”一致**：之前从“继续观看”的《药屋少女的呢喃》（第 31 集，剩 9 分钟）进入，详情页显示“播放”，当前集是第 1 集。现在 `FakeWorld._continued` 把 `_continueAt` 的位置带进剧集进度（之前的集都算看过）。进入后显示“继续 第 31 集”，剧集横排定位到第 30、31 集。这一改动只影响假数据。

## 3. 实验

环境：本 worktree 的 Debug 构建，`NIPAPLAY_PROFILE=y2-dev`。状态用 `ext.nipaplay.nextui` 切换（`tap`/`detail`/`window`/`dilate`/`escape`），截图用 `screencapture -x -o -l<窗口号>`。屏幕可用高度限制了窗口，“1440×900”实际是 1440×868。过渡中间帧的截法：先用 `dilate factor=20` 把动画放慢 20 倍，再按时间间隔截图。

### 演示数据（`NIPAPLAY_NEXT_UI_FAKE=/tmp/nipa-next/visual/tmdb`，`NIPAPLAY_NEXT_UI_FAKE_CHAT=1`）

- **详情终态**：`/tmp/nipa-next/y2/final2/detail.png`。和视觉稿并排对照：`final2/compare-detail.png`（左为 `v-detail.png`，右为实机）。两边的布局、元信息（★ 8.8 · 豆瓣 9.2 · 2023 · 28 集 · Madhouse）、按钮、“第一季”、剧集卡片（01、02 满进度，03 部分进度且有白色描边）和热度线都对得上。差别有：这部作品有 Logo，所以用 Logo 代替宋体标题（规范允许）；背景是数据里的另一张图；左上多了返回箭头；从首页进入时，顶栏当前项是“首页”（视觉稿是从片库进入的）。
- **进入（从主视觉）**：`final2/enter-hero-seq.png`。主视觉背景从上部区域扩展到整页，首页内容淡出，详情内容淡入。
- **进入（从继续观看卡片）**：`final2/enter-shelf-seq.png`。卡片图片从左下角放大，铺满整页。
- **返回（到主视觉）**：`final2/back-hero-seq.png`；**返回（到卡片）**：`final2/back-shelf-seq.png`。详情的文字先淡出，背景缩回原来的位置，首页内容随后淡入。
- **继续观看的一致性**：修正前是 `final2/detail-kusuriya.png`（显示“播放”，当前集为第 1 集），修正后是 `final2/detail-continue.png`（“继续 第 31 集”，第 31 集有白色描边和部分进度）。
- **“⋯”菜单**：`final2/menu.png`，只有“下载全部”。点击后扩展返回 `panelOpen: true`，`said: "把《葬送的芙莉莲》剩下的集都下载下来"`，4 秒后 `reply: "好，选了简中内嵌的 1080p，已经在下了。……"`，`cards: 2`。画面见 `final2/download-all.png`：因为侧面板还是占位，详情页被关闭，对话出现在首页的对话舞台上，带作品卡片和“正在准备”卡片。

### 真实后端（不带假数据，`NIPAPLAY_PROFILE=y2-dev`）

- 首页（`real/home.png`）：实验配置里只有一部作品《莉可丽丝：友谊是时间的窃贼》，没有 TMDB 令牌，所以没有图片。
- 详情（`real/detail-hero.png`；与视觉稿对照见 `real/compare-detail-real.png`）：降级显示正常。背景是绯红微光；原名 “リコリス・リコイル Friends are thieves of time.”；宋体大标题；元信息只有“2025 · 6 集”（没有评分和制作公司）；简介两行；按钮是“播放”和“问 Nipa”，没有缺集，所以没有“⋯”；季标题是“剧集”（扩展返回 `seasons: [null]`），没有 ▾；剧集卡片是深色占位，显示大号集号和标题（“第1话 Take it easy”），没有时长和热度线（这一配置里没有时长和弹幕数据）；第 1 集有白色描边。
- 从卡片进入的中间帧（`real/enter-shelf-seq.png`）：没有图片时，飞行的是微光底色，过渡正常。
- 1440×600 下滚到底（`maxScroll: 91`，`docked: 1.0`）：大标题收进顶栏中间，正常。这一步发现原名压在顶栏的导航上（`real/detail-600-docked.png`），按决策第 10 条修正后见 `real/docked-before-after.png`（左为修正前，右为修正后）。
- 没有在真实后端点“下载全部”或“问 Nipa”发送消息，以免真的触发 Agent。

### 检查

- `flutter analyze --no-pub lib/next`：20 条 info，全部在 `lib/next/capabilities/` 和 `lib/next/ui_data/service.dart`，是已有代码；`lib/next/ui/` 没有任何提示。
- 迭代时跑了 `test/next/ui_gate_test.dart`：2 项通过。
- 最后跑了一次完整的 `flutter test --no-pub test/next`（排队，去掉代理）：410 项通过，4 项跳过。日志在 `/tmp/nipa-next/y2/test-next.log`。

## 4. 改动的已有文件

| 文件 | 改动 |
|---|---|
| `lib/next/ui/shell/shell_controller.dart` | `openWork` 查找起飞的图片并推入 `/work` 路由；新增 `origins`；`openPanel` 增加 `about` 参数 |
| `lib/next/ui/shell/next_shell.dart` | `/work` 路由改为 `workRoute`；向 `origins` 报告指针按下的位置 |
| `lib/next/ui/shell/top_bar.dart` | 头像菜单改用共用的 `MenuPanel`/`MenuItem` |
| `lib/next/ui/widgets/cards.dart` | 卡片图片按作品登记为 `ArtOrigin`；新增角标位（集号） |
| `lib/next/ui/cards/card_views.dart` | 对话卡片的海报登记为 `ArtOrigin` |
| `lib/next/ui/home/hero_backdrop.dart` | 主视觉背景登记为 `ArtOrigin`；遮罩改为数据（`ShadeLayers`）；`NoArtGlow` 改为公开 |
| `lib/next/ui/home/hero_copy.dart` | 标题改用共用的 `WorkTitle` |
| `lib/next/ui/home/home_page.dart`、`lib/next/ui/pages/library_page.dart` | 传入作品标识，供登记使用 |
| `lib/next/ui/widgets/words.dart` | 新增 `Words.season`；`MetaLine` 可以不显示类型 |
| `lib/next/ui/dev/debug_extension.dart` | 新增 `tap`、`detail`、`window`、`dilate`；`hover` 支持 `episodes`/`library` |
| `lib/next/ui/dev/fake_world.dart` | 豆瓣评分、逐集进度、按季拆分、热度线、只有带截图的集可播放（用于演示“下载全部”）、继续观看的进度 |
| `lib/next/ui/pages/detail_slot.dart` | 删除（占位页） |
| `macos/Podfile.lock` | 构建自动改写（erika 0.1.3→0.2.1），没有处理 |

新增文件：`lib/next/ui/detail/`（`detail_page.dart`、`detail_backdrop.dart`、`docking_title.dart`、`episodes.dart`、`work_route.dart`），以及 `lib/next/ui/widgets/art_origin.dart`、`menu.dart`、`work_title.dart`。

## 5. 还没做到的地方

- **侧面板**：“问 Nipa”和“下载全部”现在都是回到首页、在首页对话，作品上下文没有传给 Agent（`about` 没有用上）。这要等 Y3。
- **与 Y3 合并时要改一处**：`detail_page.dart` 的 `_downloadAll` 现在用 `shell.conversation.say(...)`。Y3 的侧面板有自己的会话（`PanelChat.say`），合并后应改为在面板里说，否则这句话会落到面板后面首页的对话上。Y3 和本分支有 9 个文件重叠（`card_views`、`debug_extension`、`fake_world`、`hero_copy`、`home_page`、`next_shell`、`shell_controller`、`top_bar`、`words`），合并时需要手工处理。
- **“标记看过”和“移除”**：不显示。现在没有写本地观看进度的 Action。
- **演示数据里的一处不一致**：首页主视觉的《葬送的芙莉莲》显示“播放 第 1 集”，Nipa 的话是“第一集随时可以看”，但进入详情后是“继续 第 3 集”（为了对上视觉稿，假数据里第 1、2 集已看完）。这只影响演示。我没有改，以免改动 Y1 的首页叙事。
- **真实后端的截图、时长和热度线**取决于数据：这个实验配置里都没有，所以没能在真实数据上看到它们。热度线的数据来自 `heat.load`，需要有弹幕的作品才能验证。
- 详情页的滚动条沿用系统默认（窗口变矮时右侧出现），和首页、片库一致，没有单独处理。
- **没有实测**：真实指针的悬停和点击（按约定只用合成事件）、鼠标侧键返回、多季作品在真实后端的季切换。

## 6. 问题（需要主控决定）

1. **Y2 与 Y3 的合并顺序**：两边重叠的文件较多。建议先合并其中一个，另一个在它之上合并，再把 `_downloadAll` 改成用面板的会话说话。由谁来做？
2. **Agent 打开详情页**：现在 `ui.open {entityId: 作品}` 打开的是 Classic 的弹弹play作品详情（代码里写着“Next 事实页尚未实现”）。Next 界面开启时，是否应改为打开这个详情页？这要改能力层，不在 Y2 范围内。
3. **“标记看过”**：是否要给本地观看进度一个 Action（GUI 与 Agent 共用）？有了它，“⋯”里才能加回这一项。“移除”同理，还涉及删除文件需要用户确认的约束（ff2fb744）。
