# Y11：作品的管理

2026-10-14，worktree `~/Desktop/nipaplay-next-wt/y11-work-manage`。

界面实现者完成代码和截图后中断，本次接手核对工作区并补写报告。核对范围包括 `git status` 中全部界面改动、新增管理接口及适配器、管理面板、开发假数据和测试，以及 `docs/next/evidence/y11/` 的截图文件名。本次不修改实现代码，不 commit。

## 1. 实现与入口

- `lib/next/ui/data/work_manage.dart`：定义作品、剧集、文件、弹幕和字幕管理接口，以及确认、撤回和冲突的数据模型。
- `lib/next/ui/data/core_manage.dart`：真实运行时适配器。通过 harness 调用 Action，统一使用 `Invocation(origin: 'gui')`；读取本地身份和版本，不从文件名猜测作品身份。
- `lib/next/ui/detail/manage_sheet.dart`：共用浮层、分区、操作反馈和删除确认卡。
- `lib/next/ui/detail/manage_work.dart`：匹配、资料、图片、剧集管理。
- `lib/next/ui/detail/manage_episode.dart`：弹幕、字幕、文件管理。
- `detail_page.dart`、`episodes.dart`：详情页 ⋯ 增加“匹配作品…”“编辑资料…”“剧集与文件…”；剧集卡悬停 ⋯ 或右键打开“弹幕…”“字幕…”“文件…”，文件页可再进入作品的剧集管理。
- `services.dart` 接入真实适配器；`dev_services.dart`、`fake_world.dart`、新增 `dev/fake_manage.dart` 接入内存假数据；`debug_extension.dart` 增加 `manage` 调试入口和失败、冲突注入。
- `test/next/ui_manage_test.dart`：新增 5 个适配器测试和 2 个组件测试。

以下“已做到”指界面及调用路径已存在；截图是开发假数据场景，不能单独证明真实服务、网络来源和磁盘操作均已端到端验证。

## 2. 按任务五块逐项对照

### 认对作品

| 要求 | 状态 | 实现和边界 |
|---|---|---|
| 手动匹配 | 已做到 | 弹弹play、TMDB、Bangumi 搜索；查看候选剧集；逐文件选择目标集后提交。已有文件身份先解除，再绑定新身份。 |
| 解除匹配 | 已做到 | 显示当前匹配，点击“解除匹配”后再次确认，解除作品已有的接受绑定。 |
| 改集号 | 已做到，有限制 | 本地作品可直接编辑集号并批量保存；已匹配作品通过选择来源剧集重新绑定文件。未匹配但尚非本地目录的作品不能直接编辑集号，需先匹配或建本地作品。 |
| 无身份作品建目录 | 已做到 | “作为本地作品”创建 work → release → episode 目录，一文件一集；可添加文件、编辑集号和标题、移除剧集或作品，并撤回目录移除。 |

### 资料和图片

| 要求 | 状态 | 实现和边界 |
|---|---|---|
| 编辑资料 | 已做到 | 标题、原名、简介；一次保存修改的字段。其他资料字段未提供编辑控件。 |
| 编辑图片 | 已做到 | 背景、海报、Logo 可选择本地图片更换。 |
| 批量 | 部分做到 | 多字段资料保存、多集标题保存、本地多集集号和标题保存走批量 Action。没有多作品批量编辑或多张图片批量替换入口。 |
| 清除覆盖 | 部分做到 | 作品资料各字段及三类图片提供“恢复”，调用 clear 语义回到来源事实；没有剧集标题覆盖的“恢复”按钮。将剧集标题留空提交 null，不等同于显式 clear。 |
| 刷新 | 已做到，有限制 | 已匹配作品显示“刷新资料”，刷新已有来源引用。无匹配作品不显示该按钮；图片分区没有单独刷新入口。 |

### 弹幕

| 要求 | 状态 | 实现和边界 |
|---|---|---|
| 轨道列表 | 已做到 | 显示来源、名称、条数及加载状态；读取剧集和文件两侧轨道并去重。 |
| 开关 | 已做到 | 每轨道单独开关，通过 `danmaku.update` 更新。 |
| 偏移 | 已做到 | 展开轨道后调整提前、延后和归零；更新保留绑定版本信息。 |
| 搜索添加 | 已做到 | 枚举支持搜索的来源，搜索后添加；添加过程显示“正在添加”。 |
| 导入 | 已做到 | 选择 XML / JSON 弹幕文件导入。 |
| 屏蔽词链到设置 | 已做到 | 关闭面板并打开弹幕设置，定位 `danmaku.blockWords`。 |

另提供轨道移除，但只有具备 `bindingId` 的轨道显示移除操作，播放轨道等不能从这里解除。

### 字幕

| 要求 | 状态 | 实现和边界 |
|---|---|---|
| 列出 | 已做到 | 按视频文件列出内嵌、外挂和导入轨道，显示语言、标题、格式；不可用轨道禁用选择。 |
| 默认 | 已做到 | 选择轨道作为明确默认，也可明确“关闭”。 |
| 清除默认 | 已做到 | “自动”调用 `subtitle.reset_selection`，清除明确选择。 |
| 导入 | 已做到 | 文件选择支持 ASS、SSA、SRT、VTT、SUB、SUP、IDX。 |
| 改语言、标题 | 已做到，有限制 | 导入轨道可修改语言和标题；内嵌及普通外挂轨道不显示编辑菜单。 |
| 解除关联 | 已做到，有限制 | 导入轨道经再次确认解除关联，副本保留；内嵌及普通外挂轨道不提供此操作。 |
| 删除副本走确认 | 已做到 | 显示已解除关联的副本数量，先调用 Action 获取 `NeedsDecision`，用户确认后执行 Action 提供的调用。 |

### 文件

| 要求 | 状态 | 实现和边界 |
|---|---|---|
| Finder 显示 | 已做到，但未走 Action | macOS 直接执行 `open -R <path>`；其他平台直接返回。 |
| 信息 | 已做到 | 文件名、所在目录、大小、时长、修改日期；缺失值不显示。 |
| 删除走确认 | 已做到 | `media.mesh_files.delete` 先取得决策，界面列出文件名，确认后执行决策给出的调用；取消不删除，冲突显示“刚刚有了变化，再试一次”。 |

## 3. 使用的 Action

真实管理适配器的 Action 调用均经 harness，来源为 `gui`。文件选择器、跳转设置和 Finder 显示是本地界面或系统操作，其中 Finder 显示尚未满足统一 Action 调用要求。

| 用途 | Action |
|---|---|
| 读取作品事实、本地可读位置和文件信息 | `media.metadata.ui_facts`、`media.library.readable`、`media.files.list` |
| 读取身份、注册所选本地文件 | `media.identity.get` |
| 搜索作品、读取候选剧集 | `media.metadata.search`、`media.metadata.get` |
| 匹配、重绑集号、解除匹配 | `media.identity.bind_batch`、`media.identity.unbind_batch` |
| 创建、修改本地目录 | `media.entities.put_batch`；已有目录修改先 preview 再携带计划提交 |
| 移除本地作品或剧集、撤回 | `media.entities.remove_batch`（含 preview）、`media.entities.restore` |
| 资料及剧集标题覆盖、清除作品资料覆盖 | `media.metadata.override_batch`、`media.metadata.override`（`mode: clear`） |
| 图片替换、清除覆盖 | `media.artwork.set`、`media.artwork.clear` |
| 刷新来源资料 | `media.metadata.refresh_batch` |
| 弹幕读取、更新、搜索、添加、导入、解除 | `danmaku.tracks`、`danmaku.update`、`danmaku.sources`、`danmaku.search`、`danmaku.attach`、`danmaku.import`、`danmaku.detach` |
| 字幕读取、默认及重置、导入、编辑、解除 | `subtitle.tracks`、`subtitle.select`、`subtitle.reset_selection`、`subtitle.import`、`subtitle.update`、`subtitle.remove` |
| 字幕副本删除 | `subtitle.copy_delete`；确认后执行决策提供的调用及指纹参数 |
| 视频文件删除 | `media.mesh_files.delete`；当前测试契约确认调用为 `media.mesh_files.confirm` |

确认适配器使用 `decision.options.first.call` 的 Action ID 和原始输入，不自行拼装确认令牌。

## 4. 缺失能力和暂不可用情况

1. **Finder 显示未通过 harness Action。** `CoreWorkManage.reveal` 直接调用系统进程，且仅 macOS 有实现；需要补统一的系统文件定位 Action 接口。当前调用也未检查 `open` 的退出状态。
2. **批量管理范围有限。** 界面只管理当前作品，批量覆盖多字段和多集标题/本地集号；缺多作品批量资料、图片批量替换和批量清除覆盖入口。
3. **剧集标题清除覆盖缺显式入口。** 作品字段有“恢复”，剧集标题只有保存，适配器没有剧集标题 clear 方法。
4. **完整文件位置列表未接到管理模型。** `media.files.list` 能返回作品全部索引位置，但适配器只用它补充信息；`work()`、`episode()` 从 `media.library.readable` 为每集构建一个本地可读文件。多版本、多位置文件不会全部列出；纯远端作品显示“在其他设备上”，不能在此跨设备修改、管理字幕或删除文件。
5. **集号编辑有身份边界。** 本地目录直接编辑，已匹配作品只能重绑到来源已有剧集；没有自由修改已匹配剧集集号或编辑季号的控件。本地目录接口虽传递 season，界面保存时沿用原值。
6. **轨道操作有来源边界。** 字幕语言、标题和解除关联只开放导入轨道；弹幕移除仅开放有绑定身份的轨道。界面没有扩大这些操作的能力。

在本次新增管理代码中没有发现字面标为“暂不可用”的固定占位按钮。实际失败提示为“暂时读不到”“暂时搜不了”“没能完成”，冲突提示为“刚刚有了变化，再试一次”；无本地文件提示“这台设备上没有文件”。这些提示应与永久缺失入口区分。

`FakeManage` 用内存模拟管理操作、等待、后台添加和失败，开发模式的 Finder 只打印日志，文件选择返回样例路径。截图中的删除、匹配和刷新结果不能当作真实磁盘或来源服务的成功证据。

## 5. 截图清单

目录：`docs/next/evidence/y11/`。本次核对了以下 28 个 JPG 的文件名，未重新运行截图流程，也未逐张复验画面；场景说明按文件名记录。

| 文件 | 场景 |
|---|---|
| `01-detail-menu.jpg` | 详情页菜单 |
| `02-match-search.jpg` | 匹配搜索 |
| `03-match-assign.jpg` | 文件分配到候选剧集 |
| `04-match-refused.jpg` | 匹配拒绝反馈 |
| `05-info-edited.jpg` | 资料编辑 |
| `06-art.jpg` | 图片管理 |
| `07-art-replaced.jpg` | 图片更换 |
| `08-episodes-matched.jpg` | 已匹配作品剧集管理 |
| `09-local-episodes.jpg` | 本地目录剧集管理 |
| `10-local-episode-removed.jpg` | 本地剧集移除 |
| `11-local-match.jpg` | 本地作品匹配 |
| `12-work-removed.jpg` | 作品移除 |
| `13-files-match.jpg` | 无身份文件匹配 |
| `14-made-local.jpg` | 创建本地作品 |
| `15-episode-menu.jpg` | 剧集卡菜单 |
| `16-danmaku.jpg` | 弹幕轨道 |
| `17-danmaku-search.jpg` | 弹幕搜索 |
| `18-danmaku-adding.jpg` | 弹幕添加中 |
| `19-danmaku-added.jpg` | 弹幕添加后 |
| `20-danmaku-search-failed.jpg` | 弹幕搜索失败 |
| `21-blockwords-settings.jpg` | 屏蔽词设置跳转 |
| `22-subtitles.jpg` | 字幕列表和选择 |
| `23-subtitle-edit.jpg` | 字幕语言和标题编辑 |
| `24-copies-confirm.jpg` | 字幕副本删除确认 |
| `25-files.jpg` | 文件信息和操作 |
| `26-file-delete-confirm.jpg` | 文件删除确认 |
| `27-file-delete-conflict.jpg` | 文件删除冲突 |
| `28-file-deleted.jpg` | 文件删除后 |

## 6. 测试情况

主控已运行并提供以下验证结果，本次补报告未重新执行 Flutter 分析或测试：

- `flutter analyze`：没有 error 和 warning。
- 完整 `test/next`：576 项以上通过；唯一失败为 `host_settings_test` 中真实启动 Codex 的测试，负载高时超时，单独重跑通过，与 Y11 无关。
- 新增 `ui_manage_test.dart` 的 7 项测试覆盖：文件先取得决策再确认且 origin 为 gui、文件变更冲突、字幕副本确认及指纹参数、从本地 ID 读取轨道及保留版本、资料批量保存与目录预览/撤回、删除取消不产生删除、界面冲突反馈。没有覆盖五块功能的全部真实服务端到端路径。

## 7. 收尾

本次仅新增此报告；删除实验配置目录 `~/Library/Application Support/NipaPlay/LabProfiles/y11-dev`，使用 `git checkout macos/Podfile.lock` 恢复依赖锁文件。保留原有 Y11 实现和截图，未修改代码，未 commit。
