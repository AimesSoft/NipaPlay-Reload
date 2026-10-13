# Y9：Next 的搜索

2026-10-13，worktree `y9-search`，分支 `next/y9-search`。没有 commit、push，没有改依赖、后端或 Classic。改动只在 `lib/next/ui/` 和新测试 `test/next/ui_search_test.dart`。

实验只用自己复制的 `y9-dev` 配置，同一时间只开一个实例，默认安静（不激活窗口、不点像素、不动鼠标）。截图前后都用 `lsappinfo front` 确认前台没变，只截了自己的窗口。没有启动正式应用，没有按应用名查找或激活窗口，没有碰 `ui-demo` 和其他实验实例。

`macos/Flutter/GeneratedPluginRegistrant.swift` 在我开始前就已经被改过（多了 audioplayers、gamepad、webview 三个插件，是 worktree 解析依赖时生成的），我没有动它。

## 1. 完成了什么

- **顶栏的搜索按钮**：现在打开搜索面板，不再打开对话。顶栏只改了这一个 `onTap`。
- **快捷键 ⌘F**（其他平台是 Ctrl+F）。⌘K 仍然是对话。
- **搜索面板**：
  - 放在顶栏下方居中，是一块玻璃面板，背后的页面会压暗。在任何页面上都能打开，关闭后回到原来的页面。
  - 顶部是输入框，下面按组显示结果：**片库 · 在线 · 来源**。最后一行固定是“让 Nipa 找「词」”。
- **边输入边出结果**：
  - 防抖 200 ms；输入法还在组字时不发起搜索。
  - 三组分别请求、分别显示，不用等最慢的那一组。
  - 每次搜索都有一个代次编号，旧请求返回的结果直接丢掉。
  - 某一组出错时，组名下只显示一行“暂时搜不了”，其他组照常显示。
- **键盘操作**：
  - ↑↓ 选择，回车打开，Esc 关闭；点击面板外面也会关闭。
  - 鼠标在某一行上移动时会选中这一行。用键盘选中的行如果在可视区外，列表会自动滚过去。
- **打开结果**：
  - 作品：打开作品页。在线作品会进入 Y5 的未入库作品页（有“让 Nipa 准备”）。
  - 剧集：按主控的决定，回车直接播放，经 `NextUiActions.play`（和作品页的播放按钮走同一条路）。
  - “让 Nipa 找”：把“帮我找「词」”填进对话输入框，然后打开对话（首页展开对话，其他页面打开侧栏）。不会替用户发出去。
- **最近搜索**：
  - 输入框为空时显示“最近”和“清除”。
  - 打开过某个结果（包括交给 Nipa）的搜索词会被记下，最多 10 条。
  - 选中一条最近搜索会立即重新搜索。
  - 按主控的决定，最近搜索跨重启保存在本机：用 Next 界面已有的偏好存储 `SettingsStorage`（参考 `next_ui_preference.dart`），键是 `next_ui_recent_searches`，按实验配置隔离。点“清除”时连存储里的这条记录一起删掉（`prefs.remove`，同样经 `SettingsAccess.persist`）。这个键没有在设置注册表里登记，所以搜索词不会进设置的 journal。
- **假数据世界**：`dev/fake_search.dart` 能演示三组都有结果、剧集结果、空结果和某一组出错。调试扩展新增了 `search` 操作，用来打开搜索、输入文字、按键、让某一组出错和清除最近搜索。

## 2. 设计决定

1. **选 ⌘F，不用 `/`。**
   - ⌘F 是 Mac 上通用的“查找”。
   - 焦点在任何输入框里时 ⌘F 都能用，而 Next 的首页常常停在输入栏上。`/` 是可以打出来的字符，在输入框里会直接被输入，只能在没有输入焦点时生效，行为不一致。
   - 我查过，Classic 的 macOS 菜单和 `lib/` 里都没有占用 ⌘F。
2. **用面板，不单独做一个搜索页。** 搜索是从当前位置临时出去一下：在作品页、片库、侧栏打开的时候都能直接叫出来，Esc 一下就回到原处。
3. **组的顺序固定为片库 → 在线 → 来源。**
   - 每一组到达后单独显示。
   - 新词是旧词的延伸（“迷”→“迷宫饭”）时，旧结果以半透明保留，直到新结果到达，这样不会闪烁。
   - 新词和旧词无关时，旧结果直接清掉，避免误导。
4. **回车的规则**：
   - 结果已经是当前词的结果时，回车打开选中的那一行。
   - 结果还属于旧词时（防抖还没结束，或片库还没返回），先立即搜索，等片库返回后打开片库的第一项。
   - 片库没有结果时，回车不做任何事，不会意外跳到“让 Nipa 找”。
   - 连按回车只算一次。
5. **片库组里作品在前、剧集在后。** 剧集用 16:9 的剧照，能播放时行尾有播放标记。剧集按回车一律直接播放，不能播放时也不改为打开作品页，这是主控的决定。
6. **在线组不重复显示片库里已有的同名作品。** 这只是同一屏内的展示去重，见第 4 节第 3 条。
7. **“让 Nipa 找”固定在面板底部**，不随列表滚动，结果再多也看得到、能用键盘选到。
8. **“让 Nipa 找”和“问 Nipa”的关系**：⌘K 或任何打开对话的动作都会先收起搜索；按 Esc 时也先关搜索。
9. **文案**：
   - 组名：“片库”“在线”“来源”。
   - 输入框提示：“搜索”。
   - 空结果：“没有找到”。只有在所有组都已经返回、都为空、且没有组出错时才显示；有组出错时不显示，因为这时不能说什么都没有。
   - 出错：“暂时搜不了”。
   - 最近搜索：“最近”“清除”。
   - 不出现说明文字和 ID。来源组的行显示用户给来源起的名字（“客厅 Jellyfin”），作品在其他设备上时沿用 `DeviceMark`。
10. **视觉**：
    - 玻璃面板（blur 34），四角半径 22。
    - 选中行是由左向右渐淡的绯红色。
    - 搜索进行中，输入框下沿有一道绯红色的光扫过。
    - 开启“减少动态效果”时，面板不位移、不缩放，扫光改成一条静止的淡红线。

## 3. 能力怎么调用

真实实现是 `data/search.dart` 里的 `CoreSearch`，经 `runtime.harness` 以 `Invocation(origin: 'gui')` 调用，写法和 `core_connect.dart`、`CoreDiscover` 一样。

| 组 | 调用 | 说明 |
|---|---|---|
| 片库 | `state.query {view: "library.merged", filter: {title: {contains: 词}}, limit: 12}` | `library.merged` 是本机加组网设备合并后的那份片库，返回的 ID 能被 `work()` 和 `ui.open` 接受 |
| 在线 | `media.metadata.search {provider: "dandanplay", query: 词}` | 生成 `Found.id('dandanplay', animeId)`，Y5 的 `CoreDiscover.details` 能读这种 ID |
| 来源 | 不调用 | 没有只读的搜索能力，见第 4 节；真实模式下不显示这一组 |

逐个核对三个指定 Action 的结果：

- **`media.library.search`**
  - 输入 `{query?, limit?}`，输出 `{series: [{animeId, title, originalTitle, imageUrl, episodeCount, fileCount, lastWatchedAt}], total}`。
  - 只覆盖 Classic 观看记录里已识别的系列（本地、WebDAV、SMB），不包括组网设备。
  - 返回的是弹弹play 的 animeId，合并片库的 `work()` 不接受，打不开 Next 的作品页。所以没有用它。
- **`media.metadata.search`**
  - 输入 `{provider, query, kind?, year?}`，输出 `{results: [record]}`，其中 record 有 `ref.externalId`、`title`、`imageUrl`、`year` 等字段。按预期使用了。
- **`media.sources.query`**
  - 输入 `{sourceId, itemIds}`，只能按 ID 取条目详情，不能搜索。
  - 能搜索的只有 `media.sources.browse` 的 `searchTerm`，但它是 Effect.write。

测试 `the real searches ask the harness as the interface, read only` 的做法：

- 用真实的 `StateCapability`（注册一个和 `registerMergedLibrary` 声明相同的 `library.merged` 视图，行数据由真实的 `workJson` 生成），加上真实的 `DandanplayMetadataProvider`（只把网络传输换成假的），组成 Harness。
- 用观察者断言：两次调用都是 `origin: gui`、`Effect.read`，并且解码结果正确。

这个测试发现，`state.query` 只返回视图里声明过的字段，所以片库行拿不到年份和原名。现在的处理是：集数取自 `episodes` 的条数，和片库编解码器的做法一致；不显示年份。

真实 NextCore 没有在应用里跑过，界面实验都在假数据世界里做。原因是真实模式会连接对话宿主和弹弹play 的网络服务，而这次的约束是不碰真实服务和凭据。

## 4. 能力层的缺口

1. **片库没有合适的搜索 Action。**
   - `media.library.search` 只覆盖 Classic 的观看记录，返回 animeId。
   - 现在借用的 `state.query library.merged` 有几个问题：
     - 只公开 `id/workId/title/devices/episodes/next/artwork` 这几个字段，搜不到原名和别名，也拿不到年份；
     - `filter` 只能对 `title` 做 `contains`，不支持 OR；
     - `episodes` 是对象数组，无法按剧集标题搜索，所以真实模式下片库组没有剧集结果；
     - 每次读取都会加载全部作品和每部作品的全部剧集，库大时每次输入都要扫一遍全库。
   - 建议提供一个只读的“合并片库搜索”：按标题、原名、别名、剧集标题匹配，返回合并 ID、作品摘要（标题、年份、集数、海报、所在设备）和命中的剧集，支持 `limit`。
2. **来源没有只读搜索。**
   - `media.sources.browse` 带 `searchTerm` 时是 Effect.write：会把结果登记进统一文件索引，并写 journal。不适合每输入一次就调用一次。
   - 对 SMB 和 WebDAV，它只在一个目录里按名字过滤。
   - 建议提供 `media.sources.search {query, sourceIds?, limit}`：只读；Jellyfin/Emby 用服务器端搜索，SMB/WebDAV 查已同步的索引；每条结果说明怎么打开（已绑定作品时给合并 workId，否则给 sourceId 和 itemId 用于播放）。
3. **在线结果不知道自己是否已入库。**
   - `media.metadata.search` 不标注“这个外部身份已在片库”，界面只能按标题完全相同来去重，所以译名不同的同一作品会重复出现。
   - 建议在结果里带上已接受身份对应的合并 workId。
   - 在线搜索目前只查弹弹play，因为 `CoreDiscover.details` 只会读弹弹play。要加 Bangumi、TMDB，需要先让未入库作品页支持其他提供方。
4. **最近搜索**：已按主控的决定存进本机偏好，这里不再是缺口。

## 5. 主控的决定（已落实）

1. **来源组**：不用 `browse`，等后端补只读搜索；在那之前真实环境里不显示来源组。现在就是这样。
2. **最近搜索**：跨重启保存在本机，用 `SettingsStorage`，最多 10 条，清除时同时删掉存储里的记录。已实现，见第 1 节和第 8 节。
3. **片库组**：用 `state.query library.merged`，已认可。第 4 节第 1 条的性能问题仍然要后端来解决。
4. **在线组**：按同名去重，先这样。
5. **回车**：剧集直接播放（经 `NextUiActions.play`），作品打开作品页。已实现。

还没确认的只有 ⌘F 这个快捷键。

## 6. 改了哪些文件

| 文件 | 改动 |
|---|---|
| `data/search.dart`（新） | `NextSearchData` 接口、`UiLibraryHits`、`UiSourceHit`，以及真实实现 `CoreSearch` |
| `search/search_controller.dart`（新） | `NextSearch`：防抖、代次、分组状态、行列表、选择、回车规则、最近搜索（启动时读回，记下和清除时写回） |
| `search/recent_searches.dart`（新） | `RecentSearchStore` 接口，以及 `PreferenceRecentSearches`（`SettingsStorage`，键 `next_ui_recent_searches`，清除时删除这个键） |
| `search/search_overlay.dart`（新） | `SearchLayer`：面板、各类行、键盘处理、焦点的取得和归还、动效 |
| `dev/fake_search.dart`（新） | `FakeSearch`：三组各有延迟，可以按需出错 |
| `shell/shell_controller.dart` | `search`（接上本机的最近搜索存储）、`openSearch`、`closeSearch`、`openSearchEntry`（剧集经 `play` 播放）；Esc 先关搜索；⌘K 和打开对话时收起搜索 |
| `shell/next_shell.dart` | 快捷键表抽成 `nextShellShortcuts`（加了 ⌘F 和 Ctrl+F）；最上层叠加 `SearchLayer` |
| `shell/top_bar.dart` | 搜索按钮改为 `shell.openSearch`（只改了这一行） |
| `data/services.dart` | 新增 `NextUiServices.search` |
| `dev/fake_world.dart`、`dev/dev_services.dart` | 接入 `FakeSearch` |
| `dev/debug_extension.dart` | 新增 `search` 操作；状态里加上搜索词；`press area=search` |
| `test/next/ui_search_test.dart`（新） | 9 个测试，见第 8 节 |

## 7. 截图清单（`docs/next/evidence/y9/`）

| 文件 | 内容 |
|---|---|
| `01-three-groups.jpg` | 首页上搜“少女”：片库、在线、来源三组都有结果，“让 Nipa 找”固定在底部 |
| `02-keyboard-online.jpg` | 用键盘选到在线组的作品 |
| `03-online-opens-found-page.jpg` | 回车后进入 Y5 的未入库作品页 |
| `04-episodes-over-detail.jpg` | 在作品页上搜“魔法”：片库组里的剧集结果，带播放标记 |
| `05-nothing-found.jpg` | 空结果：一行“没有找到”，下面是“让 Nipa 找” |
| `06-online-failed.jpg` | 在线组出错：显示“暂时搜不了”，其他两组照常 |
| `07-answering.jpg` | 片库已经返回、来源还在搜：旧结果半透明，输入框下沿有扫光 |
| `08-recent.jpg` | 输入框为空时的最近搜索和“清除” |
| `09-nipa-row.jpg` | 在片库页上搜一个没有结果的词 |
| `10-nipa-filled.jpg` | 选“让 Nipa 找”后：侧栏打开，输入框里是“帮我找「灌篮高手」”，没有发出 |
| `11-small-window.jpg` | 960×640 小窗口下的面板 |
| `12-keyboard-follows.jpg` | 用键盘一直往下选，列表跟着滚动 |
| `13-episode-played.jpg` | 搜“魔法”，选中“第 3 集 · 杀人魔法”后回车：面板收起，回到首页。假数据世界的播放只记一行日志：`[NextUi dev] play 葬送的芙莉莲 3` |

## 8. 验证

- `flutter analyze --no-pub lib/next/ui test/next/ui_search_test.dart`：没有问题。
- `test/next/ui_search_test.dart` 的 9 个测试全部通过：
  - 防抖与丢弃旧结果；
  - 一组出错不影响其他组，来源组只在能搜时出现；
  - 在线组的同名去重和空结果；
  - 真实能力经 harness 调用，`origin: gui`、只读；
  - 最近搜索：最新的在前、最多 10 条、下次启动能读回、清除后存储记录消失；
  - 最近搜索存在本机偏好里：写入 `next_ui_recent_searches`，新的控制器能读回，清除后这个键被删除；
  - 键盘操作、出错提示和空结果提示；
  - 最近搜索的显示与清除；
  - ⌘F 打开搜索；“让 Nipa 找”只填入、不发出；剧集经 `NextUiActions.play` 播放（不能播放的剧集也一样）；Esc 先关搜索。
- 加上 `ui_gate_test`，11 个全部通过。补完第 5 节的两项后，又排队、去掉代理跑了一次全量 `flutter test --no-pub test/next`：519 个通过，7 个跳过，没有失败。
- 构建、重新签名后启动 `y9-dev`（使用假数据和假对话），用 `ext.nipaplay.nextui` 驱动并截图。
- 在应用里核对了最近搜索的保存：
  - 搜过“魔法”“迷宫饭”后，`y9-dev` 的偏好里出现 `next_ui_recent_searches = ['迷宫饭', '魔法']`（只读了这一个键）；
  - 退出实例再启动，打开搜索后最近列表仍是这两条；
  - 点“清除”后，偏好里已经没有这个键。

## 9. 收尾

- 按进程号退出了实例和 `flutter attach` 的附加进程（补做两项时重新启动过一次实例，也已按进程号退出）。
- 删除了 `y9-dev`。
- 用 `git checkout macos/Podfile.lock` 恢复了 `macos/Podfile.lock`。

## Y10 接线

2026-10-13，worktree `y10-search-wire`，分支 `next/y10-search-wire`。按 X56 报告第 4 节，把搜索面板接到新的只读搜索上。没有 commit、push，没有改后端、依赖或 Classic。代码只改了 `lib/next/ui/` 和 `test/next/ui_search_test.dart`。所有调用仍经 `runtime.harness`，使用 `Invocation(origin: 'gui')`。

### 1. 片库组

- 改为调用 `media.library.search_merged {query, limit: 12, episodeLimit: 4}`。
- `works` 解码为 `UiWork`，`episodes` 解码为 `(UiWork, UiEpisode)`，直接填入 `UiLibraryHits`。
- 年份、原名、集数、海报、设备、可播放状态都直接用合并目录给出的值，不再根据 episodes 数组估算集数。
- 真实环境里片库组现在也有剧集结果（按剧集标题匹配）。

### 2. 在线组

- `media.metadata.search` 结果里的 `workId` 不为 null 时，`UiWork.workId` 直接用它，作品页按片库作品读取。为 null 时仍用 `Found.id`。
- 去重改为按 workId：片库组已经显示的作品，不在在线组重复显示。原来按同名去重的做法已去掉，所以同名但不是同一部的作品会照常显示。
- 已入库、但不在片库结果里的候选（例如译名不同）会保留，行内带一个“✓ 已入库”标记，打开的是片库作品页，不是未入库作品页。
- 两个在线候选指向片库里同一部作品时，只显示一次。

### 3. 来源组

- **读取来源列表**：打开面板时读一次 `media.sources.list`，只保留 Jellyfin、Emby、SMB、WebDAV。每次打开面板都会重新读；读取失败时，下一次搜索会再读。
- **逐个来源搜索**：每个来源单独调用 `media.sources.search {query, sourceIds: [id], limit: 3}`。哪个先返回就先显示哪个，行的顺序仍按来源列表的顺序，每个来源最多 3 行。
- **出错**：
  - 来源返回 error 或 `total` 为 null 时，视为这个来源失败。失败且没有结果的来源，在“来源”下单独显示一行“书房 Emby  暂时搜不了”，其他来源照常显示。
  - 只要有来源失败，就不显示“没有找到”。
  - 来源列表本身读取失败时，整组显示“暂时搜不了”。
- **连接状态**：
  - `connectionState = failed` 但带有缓存结果的共享：结果照常显示，但调暗为 50%，不显示播放标记。
  - `unverified` 表示状态未知，不调暗。后端对这类文件给出 `playable = false`，所以不显示播放标记，但点击后仍会尝试播放。
- **各类结果的打开方式**：
  - Series、Movie：作为作品，ID 用 `workId`，没有时用 `sourceWorkId`，打开作品页。
  - Episode、Video：作为剧集，ID 用 `episodeId`，没有时用 `sourceEpisodeId`；所属作品用 `workId`，没有时用 `sourceWorkId`。集数取 `IndexNumber`。播放规则和片库剧集相同：能播放时经 `NextUiActions.play` 播放，不能播放时打开作品页。
  - File：
    - 绑定到一集：按剧集处理；
    - 只绑定到作品：打开作品页；
    - 未绑定：经新增的 `NextUiActions.playFromSource` 调用 `media.sources.play {sourceId, itemId}`。
  - 服务器上没有所属系列的 Episode 没有作品页，也走 `playFromSource`。
- **itemId 的用途**：只用来和 sourceId 一起调用 `media.sources.play`，以及作为行的内部 key。从不当作 workId 使用，界面上不显示任何 ID，行里只显示来源的名字。

### 4. 类型

| 位置 | 改动 |
|---|---|
| `data/search.dart` | `NextSearchData` 增加 `sources()` 和 `searchSource(source, query, {limit})`，去掉旧的 `sources(query)`；新增 `UiSearchSource`、`UiSourceAnswer`（`failed`）、`UiSourceHitKind`；`UiSourceHit` 改为能承载作品、剧集或文件，字段有 `source`、`itemId`、`kind`、`title`、`work?`、`episode?`、`playable`、`reachable`；`CoreSearch` 换成上面这些调用，解码不信任字段类型 |
| `data/ui_actions.dart`、`data/core_connect.dart` | `NextUiActions.playFromSource`，真实实现调用 `media.sources.play` |
| `search/search_controller.dart` | `SourceEntry`；`SearchGroup.unanswered`；`WorkEntry.inLibrary`（去掉了 `source` 字段）；在线组按 workId 去重；来源列表在打开面板时读取；逐个来源搜索 |
| `search/search_overlay.dart` | 来源行（作品用海报，剧集和文件用 16:9 小图，文件带视频标记）；已入库标记；单个来源出错的提示行；连不上的来源调暗 |
| `shell/shell_controller.dart` | `openSearchEntry` 按来源行的种类打开作品页、播放，或从来源播放 |
| `dev/fake_search.dart`、`dev/fake_world.dart`、`dev/debug_extension.dart` | 假数据世界见下一节；`fake_world` 实现 `playFromSource`（只记一行日志）；调试输出增加 `in library`、来源行和 `unanswered` |

### 5. 假数据世界

- **在线组**：也返回片库里的作品，带片库 workId。其中三部用别的译名：“间谍家家酒”“药师少女的独语”“电驭叛客：边缘行者”，搜这些名字时能看到已入库标记。
- **来源组**：
  - “客厅 Jellyfin”：系列和剧集；
  - “家里的 NAS”：文件，部分未绑定，可以播放；
  - “网盘”：状态未知，不显示播放标记；
  - “书房 Emby”：连不上，默认出错。
- **调试扩展**：`search fail=` 现在也接受来源 ID，例如 `fail=smb,emby` 表示共享连不上、只剩缓存结果。`fail=none` 表示什么都不出错，用来演示“没有找到”。

### 6. 验证

- `flutter analyze --no-pub lib/next/ui test/next/ui_search_test.dart`：没有问题。`git diff --check` 通过。
- `test/next/ui_search_test.dart` 的 11 个测试全部通过。新增或改写的内容：
  - **每个来源单独返回**：先返回的先显示；某个来源抛错或 `total` 为 null 时，只有它自己显示出错；旧查询的结果被丢弃；连不上的共享保留调暗的缓存结果；重新打开面板会重新读来源列表；列表读取失败时整组出错，下次搜索会重新读；没有来源时不显示来源组。
  - **在线组按 workId 去重**：同名但不是同一部的作品保留；已入库的作品保留并带标记；同一部作品只出现一次。
  - **真实调用**：片库组用真实的 `LibrarySearchIndex`，数据行由真实的 `workJson`/`episodeJson` 生成；在线组用真实的弹弹play 提供方，按 MediaService 的方式加上 `workId`；来源用按 X56 输出格式写的假 Action。逐项核对 `origin: gui`、`Effect.read`、解码结果，并确认 itemId 不会被当成 workId 或 episodeId。
  - **界面**：来源的作品、剧集、文件行，已入库标记，单个来源出错的提示行；没有出现 ID，也不显示“没有找到”。
  - **外壳**：来源剧集经 `play` 播放；未绑定的文件经 `playFromSource(smb-1, /下载/…)` 播放。
- 排队、去掉代理变量后，完整跑了一次 `flutter test --no-pub test/next`：**555 个通过，7 个跳过，0 个失败**。`ui_gate_test`、`ui_library_test` 也单独跑过，全部通过。
- **在应用里验证**（`y10-dev`，假数据和假对话，实例保持安静）：
  - 截图前后都用 `lsappinfo front` 确认前台没有变，只截自己的窗口。
  - 回车打开“间谍家家酒”，进入的是片库的“间谍过家家”作品页（`found: false`）。
  - 在 NAS 的未绑定文件上回车，日志是 `[NextUi dev] play from smb /下载/[字幕组] 未知作品 - 01.mkv`。
  - `fail=none` 时搜“冷门老番”会显示“没有找到”；Emby 出错时不显示。
  - 日志里没有 overflow 或异常。
- 真实 NextCore 没有在应用里运行，原因同第 3 节：不碰真实服务和凭据。

截图在 `docs/next/evidence/y10/`：

| 文件 | 内容 |
|---|---|
| `01-source-files.jpg` | 搜“mkv”：NAS 的文件（可以播放）、网盘的文件（状态未知，没有播放标记），最后一行“书房 Emby  暂时搜不了” |
| `02-source-episodes.jpg` | 搜“魔法”：片库的剧集，以及 Jellyfin 里的同几集（“葬送的芙莉莲 · 客厅 Jellyfin”） |
| `03-online-in-library.jpg` | 搜“家家酒”：在线组的“间谍家家酒 2022 ✓ 已入库” |
| `04-in-library-opens-its-page.jpg` | 回车后打开的是片库的“间谍过家家”作品页 |
| `05-share-out-of-reach.jpg` | NAS 连不上：缓存的“录屏 2026-09-30.mp4”被调暗、没有播放标记，Emby 单独一行出错 |

### 7. 还有的缺口和我的取舍

1. **来源的行没有海报。** `media.sources.search` 按设计不返回图片地址，界面也没有按条目调用 X48 图片供应者的入口，所以现在显示的是占位底色。需要海报的话，要后端或数据层补一个只读、可以懒加载的图片来源。
2. **已绑定共享文件不知道作品名。** 搜索结果里只有 workId，所以这类行只显示文件名和来源名；点进作品页后，作品页会读到完整信息。
3. **来源组和片库组不去重。** 已经绑定到片库作品的系列，会同时出现在两组，两行打开的是同一个页面。来源组本来就表示“来源里有什么”，所以我保留了。如果主控希望去掉重复，只需要在 `shown(sources)` 里按 workId 过滤。
4. **状态未知的共享上的未绑定文件，点击时仍会尝试播放。** 失败时只记日志，和其他播放失败的处理一样。

### 8. 收尾

- **复制配置时发现的问题**：从 `ui-demo` 复制来的 `lab-profile.json` 里，`endpointFile` 仍然指向 `ui-demo/endpoint.json`。启动前我把它改成了 `y10-dev` 自己的路径。
- **热重载的注意事项**：热重载只会发送 `flutter attach` 之后改过的文件。在 attach 之前改的文件需要 `touch` 一下，否则不会生效。
- 按进程号退出了实例和 `flutter attach` 的附加进程，删除了 `y10-dev`，用 `git checkout` 恢复了 `macos/Podfile.lock`。
- 没有启动 `/Applications/NipaPlay.app`，没有激活窗口、点击或移动鼠标，没有截全屏，没有碰 `ui-demo` 和其他实例，也没有读写钥匙串或真实数据。
- `macos/Flutter/GeneratedPluginRegistrant.swift` 在开始前就已经被改过，没有动。
