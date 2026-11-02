# Y8：Next 的设置页

2026-10-13，worktree `y8-settings`，分支 `next/y8-settings`，基于 54ad5a4d（含 X52/Y8 契约 `host_settings.dart`、X49 记忆）。没有 commit、push；没有改 `lib/next/ui_data/`、后端、依赖和 Classic。只用自己的 `y8-dev` 配置（ui-demo 的副本），同一时间只开一个实例，按进程号操作，不激活窗口、不点像素、不动鼠标，只截自己的窗口。没有启动正式应用，没有碰 ui-demo、x45-controller 等其他实例、登录钥匙串和真实数据。

## 1. 完成了什么

| 文件 | 行数 | 内容 |
|---|---|---|
| `lib/next/ui/settings/settings_page.dart`（新） | 526 | `/settings` 页面：左侧分节栏和搜索，右侧内容；跳到某一项并点亮；调试入口 |
| `lib/next/ui/settings/settings_layout.dart`（新） | 485 | 分节、分组、折叠规则（只做编排，不造设置项）；取值的显示名（注册表补齐前的过渡） |
| `lib/next/ui/settings/registry_rows.dart`（新） | 406 | `SettingsModel`（读、写、失败回退）；按 schema 生成的行 `RegistryRow`；Nipa 标记与理由 |
| `lib/next/ui/settings/controls.dart`（新） | 1107 | 卡片、行、开关、选项（分段 / 菜单）、滑块、输入框、路径、颜色、词条、快捷键录制、折叠按钮 |
| `lib/next/ui/settings/section_accounts.dart`（新） | 773 | 账号（弹弹play、Bangumi、同步）；媒体来源（列表、展开编辑、登录、检查、选库、移除、添加） |
| `lib/next/ui/settings/section_host.dart`（新） | 712 | 设备（组网、本机名、设备卡、远程程序、高级）；Nipa（模型、测试连接、记得的事、她改过的设置） |
| `lib/next/ui/settings/section_misc.dart`（新） | 253 | 存储（缓存、截图）、快捷键、关于、经典界面 |
| `lib/next/ui/data/settings_data.dart`（新） | 456 | 界面侧适配层接口 `NextSettingsData` 和数据模型；`UiSetting.fromRow` 由 schema 定控件 |
| `lib/next/ui/data/core_settings.dart`（新） | 359 | 真实实现 `CoreSettingsData`（harness 动作，`origin: gui`；记忆走 `NextCore.memory`）；临时的 `UnavailableHostSettings` |
| `lib/next/ui/dev/fake_settings.dart`（新） | 1085 | 假数据世界：注册表真实契约（只读）+ 内存中的值；账号、来源、记忆、缓存、宿主设置都可切换 |
| `lib/next/ui/shell/shell_controller.dart` | +42 | `openSettings({section, key})`、`settingsTarget` |
| `lib/next/ui/shell/next_shell.dart` | +21 | `/settings` 路由、⌘, / Ctrl+,、给 macOS 菜单用的 `NextShell.openSettings()` |
| `lib/next/ui/shell/top_bar.dart` | +6 −1 | 头像菜单加“设置 ⌘,” |
| `lib/next/ui/data/services.dart`、`dev/dev_services.dart` | +32 −3 | 服务里接上 `settings` |
| `lib/next/ui/data/login_requests.dart` | +12 −1 | `expect(platform)`：设置页里点的登录直接开窗口，不变成对话里的卡片 |
| `lib/next/ui/dev/debug_extension.dart` | +38 | 调试操作 `settings` |
| `test/next/ui_settings_test.dart`（新） | 293 | 9 个测试，见第 5 节 |

## 2. 结构和设计决定

### 入口

- **点头像仍然只是打开对话**，没有改。
- 头像**右键或长按**弹出的菜单里加了“设置 ⌘,”，排在“问 Nipa”和“回到经典界面”之间（`00-entry-avatar-menu.jpg`）。
- **⌘,**（以及 Ctrl+,）在外壳里打开设置；设置已经开着时不重复推入。
- 没有在顶栏加 ⋯：顶栏右侧已有后台任务、搜索（Y9 在改）和头像，再加一个常驻按钮会打破“藏得深”。头像菜单加快捷键已经能随时到达。
- 设置是推到外壳导航上的整页，和详情页同级：Esc 返回，点顶栏任一分区离开，对话侧栏照常可以打开。打开设置时会收起侧栏，这一点和打开详情页一致。

### 页面

- 左边是安静的分节栏，最上面是搜索；右边是内容，最宽 760。视觉沿用 Next 的语言：墨黑底、左上角一层很淡的粉色光、分组卡片、粉色开关和滑块、`Segmented` / `MenuPill` / `MenuPanel`。
- 分节栏用间距分成五组，不加组名：
  1. 账号、媒体来源
  2. 播放、弹幕与字幕、下载、网络、存储
  3. 设备、Nipa
  4. 通用、快捷键、关于
  5. 经典界面
- 调整说明：
  - **截图**归到“存储”，和 Classic 一样，因为它关心的是文件存到哪里。
  - **只影响 Classic 的设置**归到“经典界面”一节，放在“回到经典界面”按钮下面并折叠。这些设置包括 `appearance.*`、`general.defaultHomeTab`、`webdavQuick.*`。这样 Next 自己的各节里不会混进不起作用的设置。
  - 弹幕过滤插件的开关（`plugins.*`）放在“弹幕与字幕 › 过滤”。
  - 加了**搜索**：可以搜注册表里的每一项（含折叠的），也可以搜到分节（如“Jellyfin”“API key”“缓存”）。结果里的控件可以直接改。
- **复杂的东西藏起来**：每节先显示常用的几项，其余分组放在“更多”后面。从搜索或从 Nipa 的列表跳到一项被折叠的设置时，会自动展开，滚动到这一项，并把它点亮一会儿（`09f-jump-from-nipa.jpg`）。

### 通用设置由注册表生成

- 读：`settings.describe`；写：`settings.set` / `settings.reset`。都以 `Invocation(origin: 'gui')` 经 harness 调用，和 Nipa 走同一个动作。
- 控件按 schema 决定：
  - `boolean` → 开关；
  - `enum` → 选项。选项少时并排，多时用菜单。颜色值的 enum 用色块。
  - 有范围的数值 → 滑块（0–1 显示成百分比）；无界或跨度很大的数值 → 数字框；
  - `string` → 文字框；`x-secret` → 密文框；
  - 路径 → 显示最后一级名称，加“选择”和清除。选择用系统的选择器。
  - `#RRGGBBAA` 格式的字符串 → 色块加十六进制输入；
  - 字符串数组 → 词条；
  - 快捷键 → 录制按钮：点一下，按下新的组合。
- 不显示的项：`storage.kind == runtime` 的项，它们是播放器的即时状态；没有控件可用的 `object`；以及 `labs_use_next_interface`，它由“回到经典界面”按钮代表。
- **新增设置**：编排表里没有提到的键会落到“通用 › 其他”。所以注册表一加新项，界面和 Nipa 会同时看到。
- 改动先在界面上显示出来。NipaPlay 拒绝时，界面恢复为它最后确认的值，并在这一行下面显示几个字（“这个值不行”“没能保存”），4 秒后消失。按回车和离开输入框不会重复提交。对 `apply == restart_app` 的项，改完后提示“重新打开 NipaPlay 后生效”。
- **Nipa 改过的设置**：名字后面有一个 16px 的 Nipa 小头像。点开后显示“Nipa · 2 小时前”和她写的理由，旁边有“改回”按钮，会用注册表记录的上一个值。用户改过之后，标记就消失。Nipa 一节底部列出“Nipa 改过的设置”，点一项会跳到它所在的位置。
- 对话里 Nipa 的一轮结束时（她的状态回到空闲），页面会重新读一次注册表。这样她刚改的设置会马上带上标记。注册表目前没有变化通知，所以先这样处理。

### 各节

- **账号**：弹弹play 和 Bangumi 两张并排的卡片，显示服务、用户名、在线点，以及登录或退出按钮。退出要点第二次才生效，按钮会变成“确定退出”。Bangumi 已登录时显示“观看记录”同步：上次时间、部数、“同步”、“全部重新同步”。能力：`accounts.status / login / logout / bangumi.sync / bangumi.sync_status`。
  - 在设置页点登录，会通过 `LoginRequests.expect` 直接打开 NipaPlay 自己的登录窗口，不在对话里变成卡片；Nipa 发起的登录仍然走卡片。
- **媒体来源**：每个来源一行，显示种类标记、名称、“种类 · 地址”和连接状态点。点开后可以改名称、地址或主机端口、用户名，再保存。下面还有：
  - “显示”：可开关的服务器库标签（`libraries` / `select`）；
  - 登录：Jellyfin Quick Connect 会显示大号代码和“在服务器上批准”，其他来源打开密码窗口；
  - 检查；
  - 移除：要点两次。
  - 另有“添加”：先选种类，SMB 填主机和端口，其他来源填地址。

  能力：`media.sources.list / add / update / remove / login / check / libraries / select`。
- **设备**：用 `NextHostSettings`。
  - 组网开关，显示“1 / 2 台在线”和本机名；
  - 每台设备一张卡片：本机有薄荷色边，离线的变暗，副标题写角色和“可运行程序”；
  - “允许别的设备在这里运行程序”；
  - “高级”里放：协调地址、端口、只在这台电脑上、在局域网里让别的设备发现、文件转换端口、其他地址。
  - 不能组网时，只显示原因，开关不可用。
- **Nipa**：
  - 模型来源可以选“这台电脑的 Codex”或“在这里设置”。选后者时显示提供方、地址、模型、API key。已保存的 key 只显示“已保存”，不会读回。
  - 改动后出现“保存”。“测试连接”的结果显示为点和文字，例如“可以用 · 420 ms”或“缺少 API key”。
  - 头部副标题显示“正在用 …”，有问题时显示问题。
  - “Nipa 记得的事”：偏好、话题笔记（取笔记自己的标题）、目录。点开是原文，可以改了保存，也可以“忘掉”（要点两次）。修改带 revision，被别处改过时会提示“刚被改过，再试一次”。
- **存储**：缓存列表（大小 + 清理）+ 截图设置。真实一侧没有缓存动作，所以只显示截图设置，见第 4 节。
- **快捷键**：界面自己的键只读显示（⌘K、⌘,、Esc）。播放器快捷键来自注册表 `shortcuts.*`，可以录制；改过之后出现“恢复默认”，走 `settings.reset`。
- **关于**：Nipa 头像、NipaPlay、版本号（`app.instance`），以及“自动检查更新”（注册表）。“检查更新”只在数据层说能检查时出现。
- **经典界面**：“回到经典界面”按钮用 `NextUiPreference`（外壳的 `onLeave`），下面折叠着只影响 Classic 的设置。

### 文案

全部是名词或者短句：“退出”“确定退出”“在服务器上批准”“正在用 deepseek-v4.1-flash”“可以用 · 420 ms”“还没有记下什么”“没有找到”。不出现 ID、键名、来源文件或解释性说明；注册表的 `description` 是写给开发者和 Nipa 的，所以不显示。

## 3. 数据接口

- `NextUiServices.settings`（`NextSettingsData`）是设置页唯一的数据入口，参照 `discover.dart` 的写法。
- 真实一侧是 `CoreSettingsData(core, runtime, logins, {host})`。宿主设置现在接的是 `UnavailableHostSettings`：模型、组网、远程程序都返回“暂不可用”，写入会失败。**主控合并 X52 时，只需要在 `services.dart` 里传 `host: <X52 的实现>`。**
- 假数据世界是 `FakeSettings`。它启动时用 `settings.describe` 只读地取一次真实注册表契约（187 项），值从默认值开始，写入只留在内存里；路径里的用户名一律换成 `hikari`。几项设置预置为 Nipa 改过：弹幕透明度、自动下一话倒计时、字幕大小、弹幕屏蔽词。拿不到核心时，改用内置的 49 项样本（单元测试就用这份）。
- 调试操作 `settings`：
  - `nx.py <log> settings [section=] [key=] [query=] [more=] [source=<id>|new|none] [memory=<path>|none] [check=true] [advanced=] [scroll=] [reload=true]`；
  - 只在假数据世界里可用：`model=key|nokey|codex|nocodex`、`mesh=online|offline|unavailable`、`account=<provider>:in|out`；
  - 关闭设置页：`settings open=false`。

## 4. 验证

- `flutter analyze --no-pub lib/next/ui test/next/ui_settings_test.dart`：没有问题。
- `flutter test --no-pub test/next`（排队、去掉代理）：519 个通过，7 个跳过，没有失败。日志在 `/tmp/nipa-next/y8/test-all.log`。之后改了一处花括号和导入顺序，又跑了一次 4 个界面测试文件，共 19 个，全部通过。
- 构建 `flutter build macos --debug --no-pub`（带 `ERIKA_PREBUILT_CACHE_DIR`）后重新签名，再以 `y8-dev` 启动。后续改动用 `flutter attach` 热重载。
- **真实模式**（不带 `NIPAPLAY_NEXT_UI_FAKE`）中实际做过下面这些，截图带 `15-real` 前缀：
  - 读到真实注册表 187 项。
  - 点“播放自动全屏”。随后 `settings.get` 显示 `changedBy: user, origin: gui`。
  - 用 CLI 以带理由的方式改同一项。页面重读后出现 Nipa 标记和这条理由；点“改回”后，记录为 `user/gui`，`previousValue` 正确。
  - 账号状态。测试用的弹弹play 显示已登录，Bangumi 未登录。没有点登录或退出。
  - 媒体来源列表和服务器库。测试用的 Jellyfin 和 Emby 在 127.0.0.1；点开后读到“番剧”“开放电影”。点“检查”后，状态点变成在线，`media.sources.list` 也显示为 `connected`。
  - Nipa 一节：宿主设置显示“暂不可用”。记忆列表为空，显示“还没有记下什么”。
  - 关于：版本是 1.11.10。
- 真实模式下**没有**做的：登录、退出、来源的添加、修改、删除、Quick Connect、记忆编辑、Bangumi 同步。为了不碰账号凭据，这些只在假数据世界里走过一遍。

## 5. 测试（`test/next/ui_settings_test.dart`）

1. schema 到控件：开关、选项（包括数值 enum 和命名颜色）、数值、文字、密文、颜色（`#RRGGBBAA` 和 ARGB enum）、词条、对象，以及可为空的类型。
2. 路径和文件夹的判断；WebDAV 服务器上的目录不当本地路径；即时状态项会被标出来。
3. 来源记录：能认出 Nipa 改的，拿到理由和上一个值。
4. 分节：截图归存储，GitHub 代理归网络，外观归经典界面，新的域落到通用。
5. 分组：明确列出的键排在前面，其余按前缀归入“更多”里的组；即时状态项和 `labs_use_next_interface` 不显示。
6. 取值的显示名，以及未知值原样显示。
7. 组件：点开关后立即生效，并以 `user` 身份保存；被拒绝的数值会恢复、显示“这个值不行”、4 秒后消失，只提交一次，输入框也回到原值。
8. 组件：点 Nipa 标记会显示理由；“改回”写入上一个值，标记随之消失。
9. `LoginRequests.expect`：设置页的登录直接开窗口，只生效一次。

## 6. 截图清单（`docs/next/evidence/y8/`）

| 文件 | 内容 |
|---|---|
| `00-entry-avatar-menu.jpg` | 头像右键菜单：问 Nipa / 设置 ⌘, / 回到经典界面 |
| `01-accounts.jpg` | 账号卡片 + Bangumi 同步 |
| `02-sources.jpg` | 媒体来源列表（在线、未验证、连不上） |
| `02b-source-quick-connect.jpg` | 展开的 Jellyfin：字段、Quick Connect 代码、显示哪些库 |
| `02c-source-new.jpg` | 添加来源 |
| `03-playback.jpg` / `04-playback-more.jpg` | 播放；展开“更多”（画面、播放界面……） |
| `05-danmaku.jpg` / `05b-danmaku-words.jpg` | 弹幕与字幕；屏蔽词词条和 Nipa 的理由 |
| `06-nipa-mark.jpg` | 跳到“弹幕透明度”：点亮 + Nipa 理由 + 改回 |
| `07-downloads.jpg` / `07b-network.jpg` / `07c-storage.jpg` | 下载、网络、存储（缓存 + 截图） |
| `08-devices-online.jpg` / `08b-devices-advanced.jpg` | 组网在线：设备卡、远程程序；高级 |
| `08c-devices-offline.jpg` / `08d-devices-unavailable.jpg` | 未加入组网；这个版本不能组网 |
| `09a-nipa-key-tested.jpg` | 在这里设置（有 key），测试连接“可以用 · 420 ms” |
| `09b-nipa-no-key.jpg` | 没有 API key：“缺少 API key” |
| `09c-nipa-codex.jpg` | 这台电脑的 Codex |
| `09d-nipa-memory.jpg` | Nipa 记得的事：打开“偏好”原文 |
| `09e-nipa-changed-settings.jpg` | Nipa 改过的设置列表 |
| `09f-jump-from-nipa.jpg` | 从列表跳到“字幕大小” |
| `10-general.jpg` / `10b-general-more.jpg` | 通用；启动、诊断、实验 |
| `11-shortcuts.jpg` / `11b-shortcut-recording.jpg` | 快捷键；录制中“按下新的组合” |
| `12-about.jpg` | 关于：版本、检查更新（有新版本） |
| `13-classic.jpg` / `13b-classic-more.jpg` | 经典界面：按钮；它自己的设置 |
| `14-search.jpg` | 搜索“弹幕” |
| `15-real-*.jpg` | 真实模式：播放、点开关后、Nipa 标记、账号、来源、展开来源、检查后、Nipa（宿主不可用）、关于 |

## 7. 后端缺口

### 注册表

1. **取值没有显示名。** 例如 `player.playbackEndAction` 的 `autoNext`，或 `language.mode` 的 `simplified`。界面里有一张过渡用的显示名表（`SettingWords`，约 30 个键），不认识的值原样显示。建议注册表给每个 enum 加 `enumTitles`（或 `x-enumTitles`），之后删掉这张表。
2. **路径没有标记。** 现在从键名推断（结尾是 `path`、`directory` 或 `dir`），并手工排除了 `webdavQuick.defaultDirectory`（它是服务器上的目录）。建议加 `format: path | directory | file`；`ApplicationSettings.add` 里已经有 `path` 和 `directory` 参数，只是没有写进 describe。
3. **标题不是给人看的。** 播放器快捷键的标题是“快捷键 play_pause”，`next.harnessPath` 的标题是“Harness repository”。界面里暂时替换了。
4. **缺少的项**：
   - Classic 存储页的“启动时清除弹幕缓存”（`clear_danmaku_cache_on_launch`）不在注册表里。
   - `danmaku.fontSize = 0` 表示“使用默认”。这只写在 `description` 里，界面只能显示“0”。
5. **Nipa 的身份没有统一。** 注册表只把 `mcp` 记成 `changedBy: agent`。NipaPlay 里 Nipa 的对话和帮手调用来源是 `harness_cli:chat:*` 和 `harness_cli:helper:*`，原样写进了 `changedBy`。界面暂时把 `agent` 和 `harness_cli*` 都当作 Nipa。建议后端统一归一成 `agent`；也可以另给一个字段，说明是哪段对话。
6. **没有变化通知。** 现在每当 Nipa 的一轮结束，界面就重读一次注册表。有 `settings` 的变化流以后可以去掉这一步。
7. **多端同步没有控件。** `sync.enabled` 和 `sync.configuration` 被标成 runtime 或 object，界面没有显示。对应的是 `sync.*`（WebDAV 多端同步）这组动作，需要单独一节（可以放在设备里），还需要后端说明哪些可以作为设置。

### 能力

1. **缓存**：没有列出或清理缓存的动作。真实一侧的“存储”只显示截图设置。建议加 `storage.caches`（大小）和 `storage.clear`（图片、弹幕等）；界面和假数据世界都已经准备好。
2. **检查更新**：没有动作。真实一侧不显示“检查更新”，只显示“自动检查更新”。建议加 `app.update.check`，返回最新版本号和下载地址。
3. **宿主设置还不全。** 下面这些被 denylist 挡住了，Nipa 不能改，这是对的；但设置页也没有接口可用，需要像 `NextHostSettings` 那样补宿主专用接口：
   - 远程访问（Web 服务：开关、自动启动、端口、IPv6）；
   - 遥控接收和受信任的设备；
   - 插件安装许可；
   - 防剧透 AI 的 API key（`danmaku.spoilerAiApiKey`），现在界面只能设置接口地址和模型，设不了 key；
   - TMDB 的 key。
4. **还没放进页面的能力**：插件管理（`plugins.list / market / install / set_enabled / delete`）、备份与恢复（`backup.*`）、诊断日志导出（`diagnostics.*`）。动作都有了，可以放在“通用”或“关于”的“更多”里，需要决定放在哪里。
5. **记忆**：用了 `NextCore.memory`，按任务要求没有走 harness 动作。没有变化通知，所以 Nipa 写新记忆后，要重新打开这一节才看得到。

## 8. 需要主控决定的问题

1. **macOS 菜单“偏好设置… ⌘,”**：`main.dart` 里两处 `onOpenSettings`（约 1077 行，以及 2037、2095 行的标题栏回调）会打开 Classic 的设置窗口。Next 显示时，如果菜单先收到 ⌘,，Classic 设置会盖在 Next 上。我在实例里不能按键，所以没能确认菜单和 Flutter 谁先收到按键。已经准备好 `NextShell.openSettings()`：Next 在屏幕上时打开 Next 的设置，并返回 true。建议在 `main.dart` 的这几处开头加一行 `if (NextShell.openSettings()) return;`。这改的是 Classic，不在我的范围内。
2. **用 CLI 改的设置也算“Nipa 改的”吗？** 现在 `harness_cli` 开头的都算，包括其他代理通过 CLI 做的改动（见缺口第 5 条）。
3. **只影响 Classic 的设置放在“经典界面”一节，是否合适？** 也可以完全不在 Next 里显示，只留按钮。
4. **取值显示名的过渡表**（`SettingWords`）能否先保留，等注册表补上再删？
5. **打开设置时收起对话侧栏**，这一点和详情页一致。也可以让侧栏留着，边看设置边问 Nipa。
6. **设置页里点登录直接开窗口**（`LoginRequests.expect`）。它靠平台名称匹配，名称是“弹弹play”“Bangumi”或来源名。如果希望由后端区分，可以给 `accounts.login` 和 `media.sources.login` 加一个“这是用户自己发起的”标志。
7. **多端同步、插件管理、备份与诊断**要不要进设置页，放在哪一节（见能力缺口第 4 条和注册表第 7 条）。

## 9. 收尾

- 已经按进程号退出实例和 attach 进程，删除了 `y8-dev`，并执行了 `git checkout macos/Podfile.lock`。
- `macos/Flutter/GeneratedPluginRegistrant.swift` 在接手时就有改动，没有动它。
- 临时脚本和工具在 `/tmp/nipa-next/y8/`。其中 `pass.sh` 是整轮截图，`launch-real.sh` 是真实模式启动，`call.py` 是端点调用，`tools/montage` 用来拼图。
