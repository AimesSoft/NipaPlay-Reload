# Y7：按来源和类别组织的片库

2026-10-13，worktree `y6-mesh-library`，分支 `next/y6-mesh-library`，基于约定提交 f1d2d03d（X48/Y7）。没有 commit、push，没有改 `lib/next/ui_data/`、后端、Classic 和依赖。只用自己的 `y7-dev` 配置（假数据），同一时间只开一个实例，按进程号操作；没有启动正式应用，没有碰 ui-demo、x45-controller 实例、登录钥匙串和真实数据。

本任务分两段完成：前一位实现者因上下文过大、上游超时中断，我接手后核对现状、补完收尾、整窗验证并写报告。

## 1. 完成了什么

| 文件 | 行数 | 内容 |
|---|---|---|
| `lib/next/ui/pages/library_page.dart` | +485 −60 | 片库页：来源标题下拉、原始/整理过、书架/卡片、单类别直接显示网格、⋯ 调整面板、调试入口 |
| `lib/next/ui/library/fan_cover.dart`（新） | 446 | 扇形封面 `FanCover`、类别卡 `CategoryCard`、文件夹 `FolderTile`、`CategoryName`、悬停 |
| `lib/next/ui/library/category_grid.dart`（新） | 204 | 按需加载的 `CategoryItems`（每片 60）和网格 `CategoryGrid` |
| `lib/next/ui/library/category_page.dart`（新） | 278 | 类别全页：排序、文件夹进入下一层、返回、停靠小标题 |
| `lib/next/ui/library/category_editor.dart`（新） | 135 | 调整面板：拖动重排、移除、让 Nipa 整理 |
| `lib/next/ui/library/library_controls.dart`（新） | 123 | 来源标题 `SourceTitle`、`MenuPill`、`anchoredMenu` |
| `lib/next/ui/dev/fake_library.dart`（新） | 374 | 假数据：本地（上千部，含整理版本）、Jellyfin（多层文件夹）、SMB、WebDAV、离线的 Emby |
| `lib/next/ui/data/core_connect.dart` | +60 | 真实一侧最小实现 `CoreLocalLibrary`：只有“本地”一个来源、一个“全部”类别 |
| `lib/next/ui/data/services.dart`、`dev/dev_services.dart` | +16 | 服务里接上 `library` / `libraryActions` |
| `lib/next/ui/dev/debug_extension.dart` | +136 | 调试操作 `lib`、`cat`、计时滚动；`hover`/`tap` 认得类别卡和文件夹 |
| `lib/next/ui/widgets/icons.dart`、`segmented.dart`（新） | +39 −1、59 | `rows`/`grid`/`grip` 图标，分段切换 |
| `test/next/ui_library_test.dart`（新） | 177 | 4 个组件测试，见第 4 节 |

（`widgets/devices.dart`、`detail/episodes.dart`、`fake_world.dart` 的设备部分是 Y6 留在工作区的，没有动。）

### 本段接手后做的

- 核对书架标题箭头（标题、数量、› 一起是按钮，悬停时 › 右移并变亮）和卡片悬停展开，两者都已在代码里，整窗确认生效。
- **扇形位置**：卡片里扇形从 `Alignment(0.36, -0.78)` 下移到 `(0.36, -0.6)`。原来前卡顶边离卡片上缘只有十几像素，悬停上浮后几乎贴边。
- **类别全页的停靠小标题**：滚过大标题后，返回按钮压在海报上看不清（顶栏遮罩只有 96px 渐变）。现在滚动超过 56px 时，顶部淡入一层遮罩，返回按钮旁边显示小号“番剧 1211”，与详情页的做法一致。
- **类别全页标题行**：`Flexible` 标题和 `Spacer` 平分剩余空间，排序按钮停在中间；改成 `Expanded` 包住标题与数量，排序按钮贴右。
- 假数据补一个 WebDAV 来源“网盘”（单类别 40 部），覆盖“只有一个类别时直接显示网格”的非本地情况。
- 调试操作 `lib` 增加 `move=<类别>,<位置>` 和 `remove=<类别>`，走与调整面板相同的 `NextLibraryActions`。
- 新增组件测试（第 4 节）。

## 2. 设计决定

**来源**
- 页面标题就是来源下拉：“本地 ⌄”在左上角，点开列出全部来源。标题旁不再另放控件。
- 菜单里来源名本身没说明类型时，右侧淡色标出 SMB / WebDAV / Jellyfin / Emby；“客厅 Jellyfin”这类名字里已有的就不重复。离线的来源半透明，仍可选。

**页面形式**
- 一个来源只有一个类别时：直接是网格，来源名旁边是数量，右侧是排序和 ⋯；不出现书架/卡片切换，也不显示“全部”这个类别名。
- 多个类别时右上角是书架/卡片切换，只用图标（≡ / ▦），文字留给读屏。
- “原始 / 整理过”只在 `hasArrangement` 为真时出现，放在形式切换左边，样式与它相同、不加强调。
- 换形式或换原始/整理过时，内容淡入 360ms；换来源直接换页。

**书架**
- 每行：类别名（19pt）+ 数量 + ›，整体可点进类别全页；下面一排横向滚动的预览（取 `preview`，假数据给 20 个）。文件夹在行里用同样的扇形，做成海报形状。

**类别卡片**（用户选定）
- 模糊背景（封面图缩到 96px 宽再模糊）+ 左下深色渐变；三张海报扇形叠放在右上；类别名 23pt 粗体放左下，数量跟在后面。
- 两张海报时两张相靠，一张时前面一张、后面一个空封套，没有海报时三个本色封套（录像、下载这类无法识别的文件）。
- 悬停：420ms 内扇形张开（两侧从 11° 到 16° 并外移），前卡上浮 3.5%、放大 2.5%，整张卡放大 2%，背景模糊稍亮。减弱动态时不动。
- 卡片最小宽度约 420，宽高比 0.62，列数随窗口变化。

**类别全页**
- 压在片库上的一页（壳的导航器），Esc、鼠标侧键、左上 ‹ 都能返回；作品详情从这里打开会压在它上面。
- 网格每片 60 个，滚到哪片才要哪片；还没到的格子是很淡的海报形占位。数据变化时已加载的片标记为过期，显示中的再取一次，不清空，不闪。
- 排序菜单在右上（类别带 `sorts` 时）；换排序从头重新加载。
- 文件夹（`UiFolderItem`）点开是同样的一页，可以一层层进、一层层退。

**调整**
- ⋯ 打开面板：每个类别一行，左边拖动把手、右边 ×；只剩一个类别时不能移除也不能拖。底部“让 Nipa 整理”打开对话并替用户说出“帮我整理一下片库里的「本地」”，沿用详情页“下载全部”的做法。
- 拖动、移除在面板里立即生效，页面随 `changes` 重读后一致。

**文案**：页面上只有来源名、类别名、作品名、数量、排序名和“原始 / 整理过”“让 Nipa 整理”。没有说明文字，没有 ID，空页只写“这里还空着。”

## 3. 截图（`docs/next/evidence/y7/`，窗口 1200×820，只截本实例窗口）

| 文件 | 内容 |
|---|---|
| `01-sources-menu.jpg` | 来源下拉展开：本地、客厅 Jellyfin、家里的 NAS（SMB）、网盘（WebDAV）、书房 Emby（离线，半透明） |
| `02-local-default.jpg` | 本地默认：只有“全部”，直接是网格，标题旁 1213，作品下有设备名 |
| `03-local-arranged-shelves.jpg` | 本地切到整理过，书架形式：番剧 1211 ›、电影 1 ›、工作站上没看完的 2 › |
| `04-local-arranged-cards.jpg` | 同上，卡片形式（三张、一张加封套、两张） |
| `05-card-hover.jpg` | 悬停“番剧”卡：扇形张开、前卡上浮、整卡微放大 |
| `06-category-top.jpg` | 番剧全页顶部，排序“最近添加” |
| `07-category-end.jpg` | 滚到 1211 部的底部（末行 1 部），顶部停靠小标题“‹ 番剧 1211” |
| `08-category-sorted.jpg` | 同一页按“名称”排序 |
| `09-jellyfin-original.jpg` | Jellyfin 原始结构（默认卡片）：动画 1103、电影 26，有“原始 / 整理过” |
| `10-jellyfin-folder-years.jpg` | 动画 → 按年份：四个年份文件夹 |
| `11-jellyfin-back.jpg` | 从“按年份”返回到“动画”：先是三个文件夹，再是作品 |
| `12-edit-panel.jpg` | ⋯ 调整面板 |
| `13-edit-moved.jpg` | 把“工作站上没看完的”移到最前，面板和页面一致 |
| `14-edit-removed.jpg` | 移除“电影”后 |
| `15-smb-shelves.jpg` | SMB 书架：行首是“旧番”文件夹 |
| `16-webdav-single.jpg` | WebDAV 单类别：直接是网格 |

滚动流畅度（调试版，番剧 1211 部，`nx cat scroll=… ms=…` 统计帧时间）：

| 滚动 | 帧数 | build 平均/最大 | raster 平均/最大 | 超过 16.7ms |
|---|---|---|---|---|
| 约 4000px/s（6100px，1.5s，接近用力甩动） | 91 | 5.2 / 10.6ms | 1.1 / 7.5ms | 0 |
| 顶到底 90000px，2.5s | 144 | 5.7 / 38.8ms | 1.2 / 43.3ms | 15 |
| 44000px，1.2s | 73 | 11.3 / 21.1ms | 1.0 / 1.4ms | 20 |

极端速度下每一片都会被经过的格子要一次（顶到底共 21 片），超时帧集中在新海报解码；正常速度没有掉帧。发布版会更快。运行日志和 attach 日志里没有溢出和异常。

## 4. 测试

- `test/next/ui_library_test.dart`（新，4 项）：3000 部的类别只加载看到的片（开头 1 片，跳到底后共不到 4 次请求，末片 49），换排序从当前位置重新要；调整面板移除后行消失、只剩一个类别时没有 ×；按把手拖动后 `onMove('a', 2)` 且行序随之改变；卡片悬停时扇形角度变大。
- 同时跑 `ui_library_test`、`ui_gate_test`、`ui_drop_zone_test`、`ui_login_requests_test`、`ui_data_constraints_test`：18 项全部通过。
- `flutter analyze --no-pub lib/next/ui test/next/ui_library_test.dart`：No issues found。
- 环境注意：`flutter test` 和 `flutter attach` 都要去掉 `HTTP_PROXY` 等代理变量，否则连不上本机 VM 服务。

## 5. 对接口的意见（`lib/next/ui_data/library.dart`，未改）

1. **文件夹没有排序**：`UiFolderItem` 不带 `sorts`，进入文件夹后的页面没有排序按钮，`items(sort:)` 也不知道哪些 id 可用。建议 `UiFolderItem` 带 `sorts`，或约定子文件夹沿用上级类别的排序。
2. **`moveCategory` 的 index 含义**：界面传的是“移走后列表里的目标位置”（Flutter `onReorderItem` 已校正过的值）。建议在注释里写明。
3. **离线来源的页面**：`UiLibrarySource.online` 只在菜单里体现。选中离线来源时 `page()` 应该返回什么（上次的内容？空？）没有约定；界面现在照原样显示返回的内容，页面上没有离线表现。
4. **原始结构里的移除**：`removeCategory` 在原始结构下是否允许（相当于隐藏服务器上的某个库），以及之后怎么恢复，没有约定。界面现在两种都允许移除，恢复只能找 Nipa。
5. **书架预览的数量**：`preview` 只说“前几个”，书架需要大约一屏多（假数据给 20）。建议写明一个数，或者书架改为自己用 `items(limit:)` 取。
6. **`changes` 粒度**：任何变化都会让当前来源整页重读、所有显示中的片重取。几千部时问题不大，以后可以按来源或类别细分。
7. **真实一侧**：`CoreLocalLibrary` 每取一片都读一次 `data.library()` 的全部作品，只是过渡；X48 的身体接上后替换。

## 6. 需要主控决定的问题

1. “让 Nipa 整理”现在是打开对话并**直接替用户说出**一句话（与“下载全部”一致）。是否改为只把这句话放进输入框、由用户自己发送？
2. 原始结构（Jellyfin/Emby 的库、SMB 的文件夹）里是否允许用户直接移除和重排，还是只允许在整理过的版本里调整？
3. 离线来源要不要在菜单里能选；选中后页面上要不要有表现（例如整页变淡）？
4. 书架行末是否需要一个“进入全部”的入口？现在只有标题上的 ›，横向滚到行尾没有出口。我倾向保持现状，避免多一块控件。
5. 真实一侧目前只有“本地 / 全部”，SMB、WebDAV、Jellyfin、Emby 来源等 X48 后端；要不要先接一个只读的 Jellyfin/Emby 原始结构？
