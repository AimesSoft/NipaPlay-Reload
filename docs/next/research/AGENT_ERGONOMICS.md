# NipaPlay Next：Agent 工具体验评审与改造方案

> 评审日期：2026-10-11  
> 评审方式：只读检查；未修改文件，未运行会写入缓存、数据库或构建产物的测试。  
> 评价标准：Agent 能否理解工具、获得足够数据，并用少量调用自由组合出用户需要的结果。  
> 证据范围：仓库设计、ActionSpec、输入输出 schema、运行实现、覆盖率基线及 MCP transport。文中新增工具、契约与限制均为建议，不代表已经实现。

## 1. 结论与评审边界

建议保留 Harness、Effect、任务执行基础设施、设置注册表和凭据保险库，集中改造四个方面：

1. 将重复的状态读取收敛到有文档、支持筛选和关联的只读查询入口。
2. 将弹幕对齐、轨道替换等判断改为数据和显式操作，解除任务中的固定选择节点。
3. 将来源定义改为“一组 Action 加数据输出契约”，允许来源自行提供适合平台的能力。
4. 将完整能力目录与模型当前加载的工具集合分开管理，保留每个实际操作的 schema、Effect 和审批边界。

这些建议对应 `docs/next/DESIGN.md:48` 的 §2.3、`docs/next/ARCHITECTURE_REVIEW.md:5` 的判断标准，以及 `docs/next/TEAM.md:40` 的工具体验要求。

### 1.1 工具数量的证据范围

读取时，`test/next/capability_coverage_baseline.json:2` 包含 **58 个 Action**，分布如下：

| 领域 | 基线 Action 数 |
|---|---:|
| media | 20 |
| danmaku | 16 |
| download | 5 |
| playback | 5 |
| settings | 5 |
| task | 4 |
| credentials | 1 |
| history | 1 |
| ui | 1 |

同一基线包含 **126 个设置项**。设置项通过五个 `settings.*` Action 暴露，没有为每个设置生成独立工具。这是现有设计中最值得推广的形态。

**58 是覆盖率基线数量，不是本次测得的实时 MCP 工具数量。** 媒体组在评审期间持续修改工作区，后续读取已看到目录列表、批量哈希匹配、批量查询和批量绑定契约。本文不判断这组半成品实现是否已经完成装配、迁移或测试；表中的旧识别工具以基线记录为证据，目标以用户指定的原语方向为准。媒体文件行号为相应读取时的位置。

### 1.2 现有工具并非都需要合并

“更少、更强”应减少选择负担和重复调用，而不是把全部能力塞进一个接受任意 JSON 的 `execute`。

- 播放、跳转、绑定、解绑、导出等有独立语义的操作值得保留。
- 同一对象的多个绝对属性修改，适合合并为批量更新。
- 同一状态的多个读取入口，适合收敛为查询视图。
- `read`、`write`、`destructive` 操作需要保持可辨认的执行边界。
- 基础设施内部的分段获取、续传、重试、事务和验证，可以自动执行；选择媒体身份、来源、轨道或偏移，应由调用者明确表达。

## 2. 工具清单与使用体验

### 2.1 好的原语、重复 getter 与流程工具

**好的原语。** `playback.seek` 同时支持绝对位置和相对位移，返回结果状态；`playback.set_paused` 设置绝对状态；下载删除与保留文件的移除有独立 Effect；设置修改返回版本和来源。这些工具能直接表达用户意图。

证据：`lib/next/capabilities/playback_capability.dart:197`、`:233`；`lib/next/capabilities/download_capability.dart:53`；`lib/next/settings/capability.dart:84`。

**重复或过窄的读取入口。** Classic 媒体库提供 `search/series`，Next 提供 `works/work`；历史只提供“继续观看”；任务读取只有单个快照和按类型、状态过滤的列表。Agent 要回答跨领域问题时，需要自行逐个读取、关联。

证据：`lib/next/capabilities/library_capability.dart:29`、`:81`；`lib/next/media/media_capability.dart:284`；`lib/next/capabilities/history_capability.dart:25`；`packages/nipa_harness/lib/src/tasks/actions.dart:52`。

**流程工具。** 弹幕 `align` 创建候选并进入任务选择状态，`align_apply/align_keep` 只能执行任务已有选项。旧识别工具也围绕 start、补证据、重新判断、绑定、跳过、延期形成协议；这组按既定重构目标退役。

证据：`lib/next/danmaku/capability.dart:282`；`lib/next/danmaku/executors.dart:398`；`test/next/capability_coverage_baseline.json:26`。

**需要说明书的工具。** `danmaku.attach` 的结果取决于已有播放器轨道、来源、refresh 和缓存情况；一个工具同时承载绑定、复用、获取和替换。`danmaku.search` 返回的对象也不一定能直接获取：说明专门要求 B 站先 resolve，集目录说明要求补足未知时长。

证据：`lib/next/danmaku/capability.dart:179`、`:200`、`:242`；`lib/next/danmaku/service.dart:175`。

### 2.2 以 settings.* 推广“少量操作覆盖大量对象”

现有设置工具具有三个优点：

- `describe` 返回设置契约和当前值，可按 domain、keyword 查找。
- `set` 根据注册项 schema 校验值，并复用 Classic setter。
- 修改记录来源、理由和 revision，支持并发检查，并返回生效方式。

证据：`lib/next/settings/capability.dart:63`；`lib/next/settings/registry.dart:57`、`:142`、`:156`、`:219`。

建议保留五个工具名称，扩展批量能力：

| 工具 | 建议输入与输出 |
|---|---|
| `settings.describe` | 增加 keys、分页和字段投影；返回匹配项的类型、范围、默认值、当前值、revision、apply、可用性 |
| `settings.get` | 支持 keys 数组，一次读取多个值 |
| `settings.set` | 支持 changes 数组，每项携带 key、value、expectedRevision、reason；返回逐项结果及生效状态 |
| `settings.reset` | 支持 keys 数组及逐项版本检查 |
| `settings.history` | 支持多个 key、时间范围、分页与字段投影 |

批量修改不应自动承诺全部原子成功。现有实现会调用实际 setter，再记录修改；不能仅靠数据库事务保证所有外部 setter 回滚。批量契约应明确逐项成功、失败与未执行项。证据：`lib/next/settings/registry.dart:174`。

还应补齐动态值的机器可读契约：当前 `settings.set` 的 `value` 通过 `additionalProperties` 接纳，具体类型由注册项验证；Action 输入 schema 本身没有声明该属性类型。建议发现结果返回所选设置的值 schema，错误返回准确 JSON Pointer，避免 Agent 猜类型。证据：`lib/next/settings/capability.dart:97`。

推广到其他领域时，借鉴的是“对象目录、明确属性、批量操作、来源和回执”，不必复制设置工具的五个名称。

### 2.3 当前工具 → 目标工具

下表逐项覆盖 58 个基线工具，并补充评审期间看到的六个媒体原语契约。目标名称是方案建议；旧名称可作为兼容别名保留，模型目录只展示主要入口。

| 当前工具 | 体验评价与问题 | 目标工具或形态 | 证据 file:line |
|---|---|---|---|
| `credentials.status` | 好的只读诊断原语；输出有限且排除秘密 | 保留；可增加按来源的登录可用性和稳定诊断码 | `lib/security/credential_capability.dart:15` |
| `playback.open` | 好的操作；多文件歧义合理；当前目标依赖历史记录及旧 ID | 保留，增加稳定 file/entity 引用；候选提供结构化数据 | `lib/next/capabilities/playback_capability.dart:60`、`:93` |
| `playback.state` | 聚合运行态快照，值得保留的 getter | 保留快捷入口；也可进入状态查询 | `lib/next/capabilities/playback_capability.dart:166` |
| `playback.set_paused` | 好的绝对状态原语 | 保留，不合并成含糊的 toggle | `lib/next/capabilities/playback_capability.dart:197` |
| `playback.seek` | 好的原语；绝对与相对位移明确 | 保留单位和边界语义 | `lib/next/capabilities/playback_capability.dart:233` |
| `playback.switch_episode` | 合理的领域操作；当前复用播放器切集能力 | 保留；如存在版本歧义，应返回候选数据 | `lib/next/capabilities/playback_capability.dart:274` |
| `ui.navigate` | 好的导航原语；返回的是已派发目标 | 保留；回执区分 requested 与实际呈现状态 | `lib/next/capabilities/navigation_capability.dart:18` |
| `history.continue_watching` | 有用但只覆盖一个历史视图 | `state.query(view=history.continue_watching)`；旧名作别名 | `lib/next/capabilities/history_capability.dart:25` |
| `media.library.search` | Classic 列表原语；与 Next 列表入口并存 | `state.query(view=library.works)`；保留 Classic 来源标记 | `lib/next/capabilities/library_capability.dart:29` |
| `media.library.series` | 单对象 getter；一次展开全部集和文件 | `state.query` 查询作品、集、文件并按需展开 | `lib/next/capabilities/library_capability.dart:81` |
| `media.library.works` | Next 列表原语；当前嵌套返回作品结构 | `state.query(view=library.works)`，投影、分页、筛选 | `lib/next/media/media_capability.dart:284` |
| `media.library.work` | 与 works 配对的一对一 getter | 同一查询入口按 workId 筛选 | `lib/next/media/media_capability.dart:295` |
| `media.identity.get` | 有用的身份快照；契约包含按路径注册缺失索引 | `state.query(view=media.identities)`；查询不隐式注册 | `lib/next/media/media_capability.dart:277` |
| `media.library.import_history` | 明确的索引导入原语 | 保留，返回导入数量、跳过项和来源 | `lib/next/media/media_capability.dart:301` |
| `media.library.scan` | 按重构目标应是索引基础设施 | 保留索引任务；枚举、探测、哈希，不判断身份 | `docs/next/DESIGN.md:50`；`lib/next/media/media_capability.dart:308` |
| `media.metadata.search` | 好的外部查询原语；单来源、单查询 | 以批量搜索为主入口；来源 Action 可提供平台特有查询 | `lib/next/media/media_capability.dart:255` |
| `media.metadata.get` | 合理的外部读取；与本地 getter 不同 | 以批量 refs 查询为主入口，保留独立来源语义 | `lib/next/media/media_capability.dart:270` |
| `media.metadata.override` | 操作能力存在，但仅允许 GUI，Agent 无法代用户编辑 | `media.metadata.edit`：批量字段修改；宿主记录真实 actor | `lib/next/media/media_capability.dart:390`、`:536` |
| `media.metadata.refresh` | 合理的快照刷新任务 | 保留，增加 refs 批量输入及逐项回执 | `lib/next/media/media_capability.dart:405` |
| `media.identity.bind` | 基线中的绑定依赖旧识别选择协议；按目标退役 | 显式批量绑定，不依赖候选任务 | `test/next/capability_coverage_baseline.json:33`；`docs/next/DESIGN.md:50` |
| `media.identity.unbind` | 解绑是原语；基线为单对象入口 | 批量解绑，保留来源和并发检查 | `test/next/capability_coverage_baseline.json:35` |
| `media.identification.start` | 旧识别流程入口；不评审重构中实现细节 | 目录列表、哈希匹配、元数据查询和批量绑定 | `test/next/capability_coverage_baseline.json:32` |
| `media.identification.get` | 旧识别专用 getter | 已有数据进入 `state.query`，执行进度由任务快照提供 | `test/next/capability_coverage_baseline.json:29` |
| `media.identification.add_evidence` | 旧流程中的补证据操作 | 证据随显式绑定提交；分析结果作为数据返回 | `test/next/capability_coverage_baseline.json:26` |
| `media.identification.reconsider` | 旧流程中的再次判断节点 | Agent 使用已有数据重新判断，无专用流程 Action | `test/next/capability_coverage_baseline.json:30` |
| `media.identification.apply_release` | 旧流程中的批量推断与级联入口 | Agent 提交明确的逐文件绑定数组 | `test/next/capability_coverage_baseline.json:27` |
| `media.identification.skip` | 旧流程中的终结选项 | 无需绑定时不执行绑定；持久备注另建数据操作 | `test/next/capability_coverage_baseline.json:31` |
| `media.identification.defer` | 旧流程中的延期选项 | 未解决事项作为数据或 Agent 待办，不挂住执行任务 | `test/next/capability_coverage_baseline.json:28` |
| `download.add` | 好的执行原语；内部元数据验证、去重合理 | 保留，支持 sources 批量输入，逐项返回任务 | `lib/next/capabilities/download_capability.dart:54` |
| `download.pause` | 合理的绝对操作；与 resume 同一属性 | `download.set_paused(paused=true)`，支持 jobIds | `lib/next/capabilities/download_capability.dart:58` |
| `download.resume` | 合理的绝对操作；与 pause 可合并 | `download.set_paused(paused=false)` | `lib/next/capabilities/download_capability.dart:59` |
| `download.remove` | 保留文件的移除原语，语义重要 | 保留独立工具，支持批量 | `lib/next/capabilities/download_capability.dart:61` |
| `download.delete` | 破坏性原语，独立 Effect 正确 | 保留独立工具，支持批量及明确文件回执 | `lib/next/capabilities/download_capability.dart:63` |
| `task.list` | 通用 getter；只有 state/type，未提供分页 | `state.query(view=tasks)`；旧名作别名 | `packages/nipa_harness/lib/src/tasks/actions.dart:52` |
| `task.get` | 通用 getter；可由按 ID 查询覆盖 | `state.query(view=tasks)`；保留快照兼容入口 | `packages/nipa_harness/lib/src/tasks/actions.dart:39` |
| `task.wait` | 好的长任务观察原语；当前只等一个任务 | 保留，支持多个任务及逐任务 cursor，返回完整变化快照 | `packages/nipa_harness/lib/src/tasks/actions.dart:42` |
| `task.cancel` | 好的执行控制原语；受理不等于已停止 | 保留，支持批量；不承担下载移除或删除文件 | `packages/nipa_harness/lib/src/tasks/actions.dart:47` |
| `settings.describe` | 好的发现入口；全量契约可能较大 | 保留，增加 keys、投影和分页 | `lib/next/settings/capability.dart:85` |
| `settings.get` | getter，但统一覆盖全部设置，有价值 | 保留并支持 keys 批量输入 | `lib/next/settings/capability.dart:87` |
| `settings.set` | 好的原语；目前逐个设置 | 保留并支持 changes 数组、逐项版本和回执 | `lib/next/settings/capability.dart:89` |
| `settings.reset` | 好的默认值恢复原语 | 保留并支持批量 | `lib/next/settings/capability.dart:91` |
| `settings.history` | 有用的审计查询；过滤能力有限 | 保留并增加时间、多个 key 和分页 | `lib/next/settings/capability.dart:93` |
| `danmaku.sources` | 来源目录有用；当前描述固化能力布尔字段 | `capabilities.discover(kind=danmaku)`，返回真实 Action 集合 | `lib/next/danmaku/capability.dart:165` |
| `danmaku.search` | 外部搜索原语；平台对象差异靠说明补偿 | 来源专属 Action，返回带类型的对象和可用数据 | `lib/next/danmaku/capability.dart:172` |
| `danmaku.episodes` | 外部目录读取原语；page 等形态统一过早 | 来源专属目录 Action，允许 page、cursor 或直接列表 | `lib/next/danmaku/capability.dart:180` |
| `danmaku.resolve` | 解析 locator 是原语；多分 P 要再调用同一工具选择 | 来源解析 Action 直接返回全部结构化候选 | `lib/next/danmaku/capability.dart:201`、`:408` |
| `danmaku.fetch` | 获取和缓存原语；内部还支持绑定后装载 | 保留期间限定为获取数据；最终可由来源获取 Action 输出标准数据集 | `lib/next/danmaku/capability.dart:209`；`lib/next/danmaku/executors.dart:193` |
| `danmaku.attach` | 绑定、复用、获取、替换混合，结果形态不一 | `danmaku.attach` 绑定已有数据集或轨道；获取独立，支持批量 | `lib/next/danmaku/capability.dart:215`；`lib/next/danmaku/service.dart:175` |
| `danmaku.tracks` | 有用快照；混合绑定与播放器轨道并做分组 | `state.query` 分别查询 bindings/tracks，再按需关联 | `lib/next/danmaku/capability.dart:243`；`lib/next/danmaku/service.dart:423` |
| `danmaku.set_enabled` | 单属性绝对更新原语 | `danmaku.update` 的 enabled 字段 | `lib/next/danmaku/capability.dart:250` |
| `danmaku.set_dedup` | 单属性更新；名字未说明是显示折叠 | `danmaku.update` 的 displayFold 属性 | `lib/next/danmaku/capability.dart:250` |
| `danmaku.offset` | 好的绝对偏移原语；单位和方向明确 | `danmaku.update` 的 offsetMs 字段；旧名作别名 | `lib/next/danmaku/capability.dart:260` |
| `danmaku.detach` | 好的可恢复解绑原语 | 保留并支持批量，缓存单独处理 | `lib/next/danmaku/capability.dart:275` |
| `danmaku.align` | 将简单分析包装为等待选择的任务 | `danmaku.analyze_alignment`，返回估计、残差和证据 | `lib/next/danmaku/capability.dart:282` |
| `danmaku.align_apply` | 只能执行任务预设选项，限制组合 | 退役；直接更新 offsetMs，可采用任意明确值 | `lib/next/danmaku/capability.dart:304` |
| `danmaku.align_keep` | 为“不修改”设置专用流程操作 | 退役；保留当前值无需调用 | `lib/next/danmaku/capability.dart:304` |
| `danmaku.cache_delete` | 好的破坏性原语；缓存与绑定影响需明确 | 保留，支持批量，回执列出受影响绑定和轨道 | `lib/next/danmaku/capability.dart:313` |
| `danmaku.export` | 好的原语；raw/mapped、目录授权、回读明确 | 保留，支持批量数据集或绑定引用 | `lib/next/danmaku/capability.dart:319` |
| `media.files.list`，重构新增 | 目标契合：目录数据加文件事实 | 保留目标；交付时明确分页、资源上限和哈希语义 | `lib/next/media/media_capability.dart:316` |
| `media.hash.match`，重构新增 | 目标契合：批量信号，不做后续身份判断 | 保留，空匹配与逐项错误分别表达 | `lib/next/media/media_capability.dart:329` |
| `media.identity.bind_batch`，重构新增 | 目标契合：显式批量绑定 | 作为主要绑定入口，单项用一元素数组表达 | `lib/next/media/media_capability.dart:341` |
| `media.identity.unbind_batch`，重构新增 | 目标契合：显式批量解绑 | 作为主要解绑入口 | `lib/next/media/media_capability.dart:359` |
| `media.metadata.get_batch`，重构新增 | 目标契合：批量外部对象读取 | 作为主要查询入口；单项 getter 作兼容别名 | `lib/next/media/media_capability.dart:371` |
| `media.metadata.search_batch`，重构新增 | 目标契合：批量来源搜索 | 作为主要搜索入口；单项搜索作兼容别名 | `lib/next/media/media_capability.dart:379` |

这里的“主要入口”不要求立即重命名媒体组已经采用的 `*_batch`。先完成其既定交付，再统一模型可见目录和兼容策略。

### 2.4 元数据编辑的特殊问题

当前 `media.metadata.override` 在描述和执行中都要求 GUI origin。其目的是不让 Agent 冒充用户，但结果是用户让 Agent 修改标题时，工具也无法执行。

证据：`lib/next/media/media_capability.dart:390`、`:536`。这与 `docs/next/TEAM.md:35` 的能力覆盖目标存在冲突。

建议将“谁执行”和“修改是否具有持久覆盖语义”分开：

- 用户与 Agent 都能执行获授权的元数据编辑。
- actor、origin、invocationId 由宿主生成。
- Agent 执行的编辑记录为 Agent 修改。
- 持久覆盖、普通修正、清除覆盖使用明确的数据字段。
- 来源刷新按照已声明的覆盖规则处理，不根据调用者身份猜测用户意图。

## 3. 有文档说明的只读状态查询

### 3.1 适用性判断

**适合增加。** 媒体库、观看历史、任务、身份绑定、弹幕绑定和缓存摘要都有明确结构。统一查询能覆盖大量 getter，并让 Agent 直接询问“哪些未绑定文件已有下载回执”“哪些轨道已获取但未装载”。

现有任务公开快照已经排除了存储用 input 和 checkpoint，证明系统具备建立公开投影的基础。证据：`packages/nipa_harness/lib/src/tasks/model.dart:223`、`:250`。

查询工具应读取**版本化的公开领域视图**。直接把 `next.db` 的原始表结构作为 Agent API，会暴露存储细节，并绕过现有公开投影。

### 3.2 建议工具

新增两个 read Action：

- `state.describe`：发现视图、字段、类型、单位、ID 命名空间、关系、支持的过滤和聚合。
- `state.query`：对公开视图执行结构化查询，支持筛选、投影、排序、分页、有限关联和聚合。

建议首批视图：

| 视图 | 数据与语义 |
|---|---|
| `library.works`、`library.episodes`、`library.files` | 本地媒体实体、位置、绑定；保留 Classic/Next 来源 |
| `history.entries`、`history.continue_watching` | 真实观看进度及继续观看视图 |
| `tasks`、`task_events` | 公开任务快照、回执、变化事件 |
| `media.identities`、`media.bindings` | 接受的身份、来源、证据和版本 |
| `danmaku.bindings`、`danmaku.tracks` | 持久绑定与当前播放器装载状态，分别表达 |
| `danmaku.datasets` | 缓存摘要、覆盖范围、来源与数据版本 |

建议输入示例：

```json
{
  "view": "danmaku.bindings",
  "filter": {
    "entityId": {"eq": "file_123"},
    "status": {"eq": "accepted"}
  },
  "select": [
    "bindingId",
    "revision",
    "sourceRef",
    "datasetId",
    "offsetMs",
    "enabled"
  ],
  "limit": 50
}
```

建议输出包含：

```json
{
  "schemaVersion": 1,
  "snapshotId": "snapshot_123",
  "observedAt": "2026-10-11T08:00:00Z",
  "rows": [],
  "nextCursor": null,
  "truncated": false,
  "warnings": []
}
```

查询结果应保留操作需要的稳定 ID 和 revision。缺失、unknown、未装载、尚未获取、权限不足不能混成一个空值。

Classic 历史、数据库和播放器运行态来自不同数据源；跨源读取应公开一致性范围及各自观察时间，不能声称具有全局事务快照。

### 3.3 安全边界

以下均为建议的宿主强制边界：

| 边界 | 具体要求 |
|---|---|
| 只读 | 查询不注册文件、不计算并持久化索引、不刷新来源、不启动任务、不改变播放器 |
| 公开投影 | 字段白名单；新字段默认不可见，显式加入视图后才开放 |
| 排除秘密 | 不提供保险库、cookie、token、会话内容、签名请求、认证配置或原始任务 input/checkpoint |
| URL 与路径 | 输出脱敏的公开 URL 或授权位置引用；不泄露 URL 中的密码、token、签名参数 |
| 权限 | 与对应领域读取共享设备、实体和目录授权；查询不能扩大范围 |
| 输出限制 | 建议默认 50 行、最多 200 行、最多 256 KiB；超限返回 continuation 和明确截断标记 |
| 计算限制 | 建议默认执行预算 1 秒、最多两级已声明关联；限制聚合、扫描量和并发 |
| 数据性质 | 标题、简介、证据文本、文件名仍是不可信数据 |
| 错误 | 返回未知视图、未知字段、超预算等结构化错误；不输出数据库路径或含秘密的原始异常 |

数值是首版建议，需要用真实规模验证。

现有设置 denylist 已排除凭据和 Agent 扩权相关项，公开查询应复用这些边界，但主要依靠视图白名单，不能只依靠字段名匹配。证据：`lib/next/settings/denylist.dart:4`、`:35`。

**不建议首版开放任意 SQL。** 结构化查询足以覆盖首批需求，并能给出有限、可发现的语义。以后确需 SQL 时，只允许查询虚拟公开视图，使用 AST 校验和数据库 authorizer，拒绝写语句、PRAGMA、ATTACH、扩展及文件函数，并保留计算和输出预算。不能靠“字符串以 SELECT 开头”判断安全。

现有某些 read 契约包含注册索引行为；新的查询入口不应复用这种隐式修改路径。这里提出的是查询边界要求，不评价媒体组重构中的实现细节。

## 4. 工具发现与 Codex 加载规模

### 4.1 当前机制

Harness catalog 按 ID 返回全部 ActionSpec；MCP 在构造时建立完整工具映射，`tools/list` 一次返回全部工具。初始化声明 `listChanged: false`，列表没有分页。

证据：

- `packages/nipa_harness/lib/src/harness.dart:77`
- `packages/nipa_harness/lib/src/mcp/endpoint.dart:33`
- `packages/nipa_harness/lib/src/mcp/endpoint.dart:105`
- `packages/nipa_harness/lib/src/mcp/endpoint.dart:116`

每个工具还包含完整输出 envelope，重复声明 Decision 和 Failure 结构。证据：`packages/nipa_harness/lib/src/mcp/endpoint.dart:171`、`:186`。

来源增加时，这种全量目录会持续增长。**推测：**更大的目录会增加上下文占用和相近工具的误选机会；本次没有进行模型调用实验，不能把它写成已测性能下降。

### 4.2 建议发现机制

增加 `capabilities.discover`，支持自然语言 query、domain、sourceId、effect、actionIds、detailLevel 和分页。

摘要返回：

- Action ID、简短能力说明、Effect；
- 来源及实现版本；
- 输入输出数据契约名称；
- 当前可用性和缺失条件；
- 稳定契约版本。

详细结果返回完整 ActionSpec、字段单位、限制、错误语义和数据示例。

目录由实际注册的 Action 派生。不要再建立一份手写“意图 → 调用步骤”表。`settings.describe` 已展示了注册事实驱动发现的价值。

需要区分三个集合：

1. 宿主已注册的全部能力。
2. 当前会话获授权、可发现的能力。
3. 当前模型请求已经加载的工具定义。

发现工具不赋予权限，也不执行其发现的 Action。来源不可用时，仍可展示能力及 unavailable 原因。

### 4.3 发现结果不等于工具已加载

`capabilities.discover` 返回一个 ActionSpec，只能让 Agent 了解契约；它不会自动使该 Action 成为 Codex 可调用的工具。

建议分阶段处理：

- **近期 MCP：**先收敛主要入口，保留有限、稳定的全量工具集合；兼容别名不必重复展示。发现主要用于设置、来源、视图和契约说明。
- **具备验证条件后：**使用运行时支持的延迟加载，让发现结果进入实际可调用工具集合。
- **不支持延迟加载的客户端：**按来源或领域提供有限工具集合，明确声明可用入口；不假定客户端支持热更新。

只给 `tools/list` 加分页不能保证模型上下文变小，客户端仍可能取完全部页面。当前端点也没有实现工具列表变化通知，不能直接假设运行中修改 catalog 会被客户端感知。

### 4.4 Codex 一次加载多少工具

已核实的外部与仓库证据：

- 官方 API 部署文档建议使用 tool search 和 `defer_loading`，按意图组织 namespace，并建议每个 namespace 约少于 10 个函数。该建议属于 API 工具设计指导，**不是 Codex 总工具数上限**。
- 官方 App Server 文档确认 dynamicTools 是实验 API。
- 仓库对 Codex 0.144.1 的调研记录了 `deferLoading` 字段及 namespace 条件；没有给出 NipaPlay 全目录延迟加载的验收结果。

来源：

- [官方 tool search 指导](https://developers.openai.com/api/docs/guides/deployment-checklist#use-tool_search)，2026-10-11 核对。
- [官方 App Server 文档](https://developers.openai.com/codex/app-server)，2026-10-11 核对。
- `docs/next/research/CODEX_APP_SERVER.md:373`、`:402`、`:424`。

本次没有核实 Codex 一次加载工具的固定最大数量，也没有测得 58 个工具不可用。因此建议以体验预算管理：

| 指标 | 首版建议，尚未实测 |
|---|---|
| 初始常驻工具 | 约 12–20 个，覆盖发现、查询、设置、播放、任务观察及常用执行 |
| 每次补充加载 | 一个明确领域或来源，通常 3–8 个 |
| 核心完整目录 | 收敛到约 30–40 个主要入口；来源工具按需发现 |
| 衡量方式 | 真实模型请求中的 schema token、首次正确选工具率、无效调用数、完成目标的调用数 |

初始工具集合应允许 Agent自行发现其他能力，不能由关键词分类器硬性裁剪到无法探索。加载策略是运行时机制，不是业务流程。

### 4.5 审批不能在通用调用器中丢失

当前 MCP 从 ActionSpec 的 Effect 生成 annotations；工作区对 destructive 工具生成独立 prompt 配置。证据：`packages/nipa_harness/lib/src/mcp/endpoint.dart:177`；`lib/next/agent_workspace.dart:24`。

如果用一个自动批准的 `capabilities.invoke` 包装全部 Action，内部删除可能失去现有工具级审批。建议优先保留实际工具定义。

如未来确需通用调用器，应按 read、write、destructive 分开，并由宿主检查目标 Action 的真实 Effect，拒绝跨等级调用。批量调用同样必须执行每项授权和审计。

## 5. NeedsDecision：逐项用法与改法

### 5.1 判断标准

合理的 `NeedsDecision` 表达“输入不足以确定唯一操作对象”。它可以提供可执行按钮，但不应强制调用者进入一段持久业务流程。

应满足：

- 结构化返回候选，而非仅把 JSON 塞进说明文字。
- 尚未执行目标操作时明确说明。
- 所有独立操作仍可直接调用。
- 选项调用通过正常输入校验、授权和并发检查。
- 用户意图已经明确时，不要求额外确认节点。

当前 DecisionOption 只有 label、detail、call，没有结构化候选字段。证据：`packages/nipa_harness/lib/src/outcome.dart:40`、`:53`。

### 5.2 现有用法清单

| 用法 | 已核实的现状 | 判断 | 建议 |
|---|---|---|---|
| `playback.open` 多文件选择 | 一个集对应多个候选文件时返回各路径调用，保留 startPositionMs | 合理的对象歧义 | 保留；增加候选路径、来源、进度、版本等结构化数据；路径调用可独立执行 |
| `danmaku.resolve` 多分 P | 多候选返回 Decision，候选 JSON 放进 detail；选项再次调用 resolve 并传 selectionVideoId | 歧义合理，但机器数据被包装成再次选择调用 | 主结果返回 candidates；如保留 GUI 按钮，将其作为展示附件，无需重新获取相同候选 |
| `danmaku.align` | 无论已有估计是否足够明确，分析后进入 needs_decision；只提供 apply/keep | 在驱动流程 | 分析完成即返回数据；偏移设置使用独立原语 |
| `danmaku.align_apply/keep` | 通过任务 revision 和精确 ActionCall 匹配恢复执行 | 在执行固定分支 | 退役；保留绑定 revision 检查，允许调用者设置其他偏移 |
| 旧识别 start/apply_release | 基线保留旧流程入口；架构复审已明确整体替换 | 按既定目标退役 | 枚举、哈希、元数据查询、显式批量绑定 |
| 旧识别 add_evidence/reconsider | 基线保留补证据、重新判断入口 | 按既定目标退役 | 候选和证据作为数据；Agent自行重新判断 |
| 旧识别 bind/skip/defer | 基线保留识别选项操作 | 按既定目标退役 | 直接绑定；不绑定无需完成一个识别流程 |
| `FileIndexingCapability` | 遍历 Decision 选项中的路径并注册文件位置 | 是 Decision 的消费适配，不是判断生产者 | 随媒体重构确认索引职责；查询和返回候选不应隐式写索引 |
| TaskEngine | 提供 needsDecision 状态、持久 Decision 和 resolveDecision | 通用机制没有判断领域含义，但具备流程门禁能力 | 新领域任务停止使用固定 Decision 门禁；存量协议先兼容 |
| MCP、Outcome、任务 schema | 序列化 Decision、公开选项；MCP 只把 Failed 标成 isError | 数据传输机制 | 保留兼容；不要让 instructions 将其解释为固定请示流程 |

证据：

- 播放：`lib/next/capabilities/playback_capability.dart:111`
- 分 P：`lib/next/danmaku/capability.dart:408`
- 对齐：`lib/next/danmaku/executors.dart:396`
- 对齐恢复：`lib/next/danmaku/service.dart:260`
- 旧识别：`test/next/capability_coverage_baseline.json:26`
- 索引适配：`lib/next/media/file_indexing.dart:40`
- 引擎：`packages/nipa_harness/lib/src/tasks/engine.dart:41`、`:283`
- 传输：`packages/nipa_harness/lib/src/mcp/endpoint.dart:130`
- 任务 schema：`packages/nipa_harness/lib/src/tasks/actions.dart:133`

媒体识别生产和消费代码在评审期间变化，因此上表按基线和既定目标列出，不据此判断半成品内部是否仍有实际 Decision 流水线。

### 5.3 建议的数据形态

候选首先是数据：

```json
{
  "candidates": [
    {
      "candidateId": "part_1",
      "videoRef": {
        "sourceId": "bilibili",
        "objectType": "cid",
        "externalId": "123"
      },
      "title": "第 1 P",
      "durationMs": 1440000
    }
  ]
}
```

GUI 可额外展示宿主生成的 ActionCall 按钮。按钮是便捷入口，不是唯一合法调用方式。

不变量冲突继续返回明确错误，例如版本变化、对象不存在、集不属于指定季；这些情况不应自动转成“重新判断”流程。

## 6. 弹幕：数据分析、获取、绑定和去重

### 6.1 对齐改为分析数据加偏移原语

现有对齐执行器计算：

- 每个锚点的 `sourceTimeMs - mediaTimeMs`；
- 排序后中间位置的估计偏移；
- 最大残差；
- 锚点时间跨度；
- 根据锚点数量、跨度和残差生成 confidence 标签。

随后存储候选并进入 apply/keep Decision。证据：`lib/next/danmaku/executors.dart:351`、`:398`。

建议 `danmaku.analyze_alignment` 为只读分析：

```json
{
  "bindingId": "binding_123",
  "observedRevision": 7,
  "estimateOffsetMs": 1200,
  "anchorOffsetsMs": [1180, 1200, 1220],
  "residualsMs": [20, 0, 20],
  "maxResidualMs": 20,
  "anchorSpanMs": 180000,
  "method": "median",
  "evidence": [],
  "limitations": []
}
```

不修改绑定、不建立等待选择的任务、不把估计当作语义正确的证明。当前锚点上限为 100，计算本身没有必要等待持久选择任务；证据：`lib/next/danmaku/capability.dart:460`。

调用者可以采用估计、修正数值或不修改。修改用 `danmaku.update`：

```json
{
  "changes": [
    {
      "bindingId": "binding_123",
      "expectedRevision": 7,
      "offsetMs": 900,
      "reason": "根据片头后锚点修正"
    }
  ]
}
```

保留现有方向：正值提前，显示时间减去 offsetMs。证据：`lib/next/danmaku/capability.dart:274`；`lib/next/danmaku/player_port.dart:160`。

### 6.2 attach/fetch 的内部流程

当前 `attach`：

1. 对当前媒体查找已有平台视频轨道。
2. 非弹弹play 的已有轨道直接返回 alreadyExists。
3. 弹弹play 已有轨道创建绑定并复用。
4. 其他情况创建绑定，再提交 fetch。
5. refresh 请求会获取并替换。

证据：`lib/next/danmaku/service.dart:175`。

fetch 执行器则承担分段获取、缓存、重试、覆盖验证，以及在存在 bindingId 时分配缓存并刷新播放器。证据：`lib/next/danmaku/executors.dart:127`、`:178`、`:193`、`:218`。

问题在于，Agent 调用“附加”时需要理解播放器当前是否有本地或 Classic 轨道，才知道是否会访问网络、是否创建绑定、是否返回任务。

建议分离：

| 操作 | 建议职责 |
|---|---|
| 来源获取 Action／过渡期 `danmaku.fetch` | 获取指定对象或范围，产生标准数据集和覆盖回执 |
| `danmaku.attach` | 将明确数据集或已有轨道关联到媒体，记录来源、证据和版本 |
| `danmaku.update` | 批量修改偏移、启用和显示折叠 |
| `danmaku.detach` | 撤销关联，缓存保留 |
| 来源重新获取 | 产生新数据集版本 |
| 显式替换关联 | 指定替换哪个绑定的数据集，检查 expectedRevision |

分段请求、缓存复用、重试和挂载已接受绑定属于基础设施，可以保留自动执行。选择本地池还是线上池、是否替换、采用哪个版本，应在输入中明确。

不要求 Agent 手动获取每一分钟或每个 protobuf 分片。来源 Action 可以完成一个明确获取请求的全部技术过程。

还应补齐数据访问能力：目前已有 tracks 和 export，但 Action 清单没有直接读取弹幕时间窗条目或统计摘要的入口。建议通过查询视图提供有限条目窗口、数量统计、来源构成和覆盖数据，让 Agent 能检查实际内容，而不必为了读取先导出文件。证据：`lib/next/danmaku/capability.dart:164` 的完整工具清单。

### 6.3 三种“去重”必须分别定义

| 层次 | 已核实现状 | 建议 |
|---|---|---|
| 缓存重复消除 | 优先 sourceEntryId，其次 platformId；缺少这些字段时使用 sender、时间、内容、模式和颜色；无 sender 时保留 | 保留原始条目；只有可靠身份相同时确定重复。sender 指纹作为可解释的候选或视图规则 |
| 轨道唯一性 | 一般按 platform/videoId；弹弹play 特殊地按平台合并；新注册轨道会移除重复轨道 | 明确唯一键和冲突数据；已有同一对象可幂等复用，不同对象不可仅因平台相同而被视为相同 |
| 显示跨轨折叠 | 可靠原始 ID 加 100 ms；未知聚合重叠允许至少 8 字符、相同内容/类型/颜色的近时折叠 | 定义为可配置显示策略，公开折叠理由、数量、成员；原始数据不改写 |

证据：

- 缓存：`lib/next/danmaku/store.dart:216`
- 轨道：`lib/utils/danmaku_track_registry.dart:8`
- 服务分组：`lib/next/danmaku/service.dart:60`、`:468`
- 显示折叠：`lib/utils/danmaku_source_merge.dart:13`、`:38`
- 折叠配置的消费：`lib/utils/video_player_state/video_player_state_danmaku.dart:720`

具体改法：

- `set_dedup` 更名或映射为 `displayFold`，说明其影响显示。
- 查询同时展示持久绑定和实际装载轨道，避免分组隐藏多个绑定的状态。
- 返回可靠的 canonical source identity；unknown 不猜。
- 同一平台、同一视频的一条有效轨道可以作为明确不变量，符合 `assets/next/AGENTS.md:16`。
- 对不同缓存版本、偏移或实体范围的冲突，返回相关数据，由调用者显式选择替换。
- 现有“已装载优先、本地优先”等恢复顺序应与来源选择分离，避免它静默决定用户最终使用哪份数据。

最后一项基于 `lib/next/danmaku/service.dart:346` 的优先排序与去重逻辑。对用户体验的具体影响需在改造验收中验证。

## 7. 来源契约：约束宿主消费的数据

### 7.1 当前接口及问题

| 来源 | 现状 | 问题 |
|---|---|---|
| 弹幕 | `DanmakuSource` 要求 search、listEpisodes、resolve、planFetch、fetchChunk、validate；descriptor 包含相关能力布尔值 | 不支持某种入口的来源仍须实现方法或报 unavailable；获取机制固定为计划与分片 |
| 元数据 | `MetadataProvider` 固定 search/get；HashMetadataProvider 扩展 matchHash | 新来源必须适配预设方法形状，平台特有查询不易直接表达 |
| 发布 | `ReleaseSource` 目前出现在设计文档；本次在 lib/packages 中未发现对应实现 | 应直接设计数据和注册方式，无须先建立固定 search/RSS/detail 接口 |

证据：`lib/next/danmaku/source.dart:176`、`:220`；`lib/next/danmaku/sources.dart:61`；`lib/next/media/metadata_provider.dart:83`；`docs/next/DESIGN.md:435`。

这些接口本身没有强制 Agent 按某个顺序调用，不能把“存在 search/get 方法”直接等同于状态机。问题是它们规定了所有来源必须具有的能力形状，并使宿主围绕统一形状组织执行。

### 7.2 通用原则

宿主要求标准数据，来源提供适合自己的 Action：

- 不规定必须有 search、resolve、fetch 三个阶段。
- 不要求无搜索能力的来源实现空 search。
- 不要求整包、本地、cursor 来源伪装成时间分片来源。
- 来源可直接接受公开 URL、精确 ID、查询或已有标准对象。
- 技术上的签名、分页和传输可以在一次 Action 内完成。
- 业务选择和跨来源组合由 Agent 决定。
- 宿主独立验证结构、权限、资源限制和数据一致性。

### 7.3 宿主要消费的数据格式

以下是建议契约，已有字段尽量沿用现有数据模型。

#### A. 弹幕数据集

现有 `DanmakuEntry` 已区分获取来源、平台、原始时间、模式、颜色及原始 ID，可作为标准条目的基础。证据：`lib/next/danmaku/source.dart:68`。

| 部分 | 建议字段与约束 |
|---|---|
| 数据集身份 | contractVersion、datasetId、contentDigest、sourceId、implementationVersion |
| 对象引用 | provider/sourceId、objectType、externalId、scope；可包含 canonicalRef |
| 采集事实 | fetchedAt、requestedRange、coveredRanges、coverageMeaning、complete、partial、failures |
| 条目 | sourceTimeMs、text、mode、colorRgb、fontSize、sourceEntryId |
| 原始来源 | originPlatform、originVideoId、originEntryId；未知为 null/unknown |
| 可选属性 | sender、sentAt；不用于推断身份真实性 |
| 完整性说明 | 当前池、相关聚合池或历史池；结构验证与平台完整性分开 |
| 分页或大数据 | entries 或宿主数据引用；分页记录属于数据，不要求特定获取方法 |

边界：

- 时间为原始来源毫秒，不预先应用播放器偏移。
- 不支持的原始 mode 可保留，渲染降级另行记录。
- 数据集不隐含媒体绑定或播放操作。
- `complete` 必须对应声明的覆盖范围，不能宣称抓完全部历史。
- 原始条目和显示折叠结果分开保存。

#### B. 元数据快照

现有 ExternalRef 和 MetadataRecord 已包括引用、标题、种类、编号、语言和 fetchedAt。证据：`lib/next/media/metadata_provider.dart:5`、`:23`。

建议标准快照包含：

- contractVersion、snapshotId、sourceId、implementationVersion、fetchedAt；
- 对象 ref、kind；
- fields：每项 value、language、来源和可选字段证据；
- relations：work、season/release、episode 等关系；
- numbering：编号字符串、order、season、episodeType；
- 目录覆盖范围及分页事实；
- 已验证的跨来源引用；未验证关联显式标记；
- 结构和来源验证等级。

采用可分页关系数据，避免要求一次递归返回全部目录。快照不接受媒体身份、不覆盖用户编辑、不自动绑定文件。

#### C. 发布候选

当前设计要求标题、下载入口、大小、做种数、属性和来源。证据：`docs/next/DESIGN.md:436`。

建议标准候选包含：

- contractVersion、candidateId、sourceRef、publicPageUrl、observedAt；
- 原始标题；
- artifacts：magnet、torrent URL 或宿主托管种子引用，附 infoHash 等已知事实；
- sizeBytes、seeders、leechers、publishedAt，未知为 null；
- 来源明确声明的分辨率、字幕、语言、编码等属性；
- 属性依据、是否为来源声明、是否经过验证；
- 登录可用性、错误和可访问性。

来源文本与 Agent 的理解分别记录。Next 核心不重新引入文件名猜测或自动发布选择。候选数据本身不创建下载、订阅或追番。

### 7.4 “一个来源 = 一组 Action”的注册方式

建议来源包 manifest：

```json
{
  "sourceId": "example",
  "implementationVersion": "1.0.0",
  "domains": ["danmaku"],
  "produces": ["nipa.danmaku.dataset@1"],
  "actions": [
    {
      "id": "source.example.lookup",
      "effect": "read",
      "inputContract": "example.lookup@1",
      "outputContract": "example.objects@1"
    },
    {
      "id": "source.example.collect",
      "effect": "write",
      "inputContract": "example.collect@1",
      "outputContract": "nipa.danmaku.dataset@1"
    }
  ]
}
```

名称和 Action 数量不固定。manifest 不包含流程顺序、下一步、默认分支或“何时请 Agent 选择”。

注册要求：

1. Action ID、输入输出 schema、Effect 和实现版本可验证。
2. 标准输出在宿主消费边界经过校验。
3. 大数据通过宿主生成的、带摘要和访问范围的数据引用传递。
4. 请求域名、profile、目录、会话和预算属于宿主授权；包内声明只是申请。
5. 来源不能读取凭据明文，不能自行增加权限或伪造 actor。
6. 安装版本可撤销；已有绑定保留数据版本和来源记录。
7. 发现目录由实际 Action 集合生成，无须另写能力布尔矩阵。

现有 ScopedDanmakuHost 已限制来源只能使用声明 profile；签名和会话请求留在宿主。这些边界应保留并推广。证据：`lib/next/danmaku/host.dart:19`、`:134`。

来源注册时的宿主授权和验证属于能力安装边界，不是 Agent 的媒体业务流程。Agent 生成能力后，也应经过同一注册路径。

## 8. MCP 说明与工具描述

### 8.1 现状

MCP package 接受 instructions 参数，并在 initialize 返回；实际 NipaPlay 文本由 AgentEndpoint 设置：

> Query before acting. When an outcome is needs_decision, execute the chosen option's call … otherwise ask the user.

证据：`packages/nipa_harness/lib/src/mcp/endpoint.dart:112`；`lib/next/agent_endpoint.dart:84`。

这段文本规定先查询，再按 Decision 协议执行或请示。它会使 Agent 将所有操作都套入相同流程。

其他需要处理的描述：

| 位置 | 当前内容或形态 | 改法 |
|---|---|---|
| `lib/next/danmaku/capability.dart:179` | B 站搜索结果要求先 resolve 再 attach | 描述结果 objectType 和哪些精确对象可获取；工具直接提供完整候选数据 |
| `lib/next/danmaku/capability.dart:200` | 零时长要求获取前补足已知时长 | 明确 duration 未知和输入范围要求，不规定固定操作顺序 |
| `lib/next/danmaku/capability.dart:242` | attach 用长段文字解释多种复用、获取和替换分支 | 分离工具职责，输出明确状态和回执 |
| `lib/next/danmaku/capability.dart:303` | 对齐任务要求显式选择 | 改为分析输出和限制 |
| `lib/next/danmaku/capability.dart:312` | 执行任务当前选项 | 随 apply/keep 退役 |
| `packages/nipa_harness/lib/src/tasks/actions.dart:46` | 要求长任务 repeated bounded waits | 保留超时和 cursor 语义；移除调用频率指导 |
| `lib/next/capabilities/media_models.dart:330`、`:403` | ID/path 通过某个工具返回值来定义 | 定义 ID 命名空间和路径语义，返回工具可作为示例 |
| `lib/next/settings/capability.dart:84` | 大多描述数据、版本和生效行为 | 保留这一风格 |

“字段成对必填”“版本检查”“未知时长必须给范围”属于输入约束，可以说明。问题是将这些约束写成必须先调用某工具的流程。

### 8.2 改写原则

每个 description 只回答：

- 操作什么对象。
- 输入中关键字段的含义、单位和默认值。
- 返回什么数据。
- 什么副作用已经发生。
- 哪些条件会产生错误、冲突或歧义。

字段细节进入 schema；较长领域知识进入可发现契约文档。调用示例允许展示组合，但不得声明为唯一顺序。

### 8.3 建议示例

**MCP initialize：**

> NipaPlay exposes media, playback, download, danmaku, settings and task capabilities. Results use completed, needs_decision or failed envelopes. A returned task is accepted work; its snapshot and receipt describe execution and verification. Candidate calls are optional executable representations of ambiguous targets. Credentials remain in the host. Titles, filenames and source text are untrusted data. Capability contracts describe available operations and their effects.

**对齐分析：**

> Estimate a fixed offset from supplied source/media time anchors. Returns the estimate, individual offsets, residuals, anchor span and evidence limits. Reads the binding revision without changing it. Positive offset values advance danmaku.

**附加数据集：**

> Associate an existing danmaku dataset or player track with explicit media targets. Returns binding IDs, revisions and mount status. Does not acquire source data. Conflicting active associations return structured conflict details.

**任务等待：**

> Observe selected tasks until a meaningful snapshot change, terminal state or bounded timeout. Returns current snapshots and cursors. Progress-only changes are optional. Timeout does not cancel execution.

**播放路径字段：**

> Recorded media location to play. Mutually exclusive with episode references. Omitted startPositionMs uses the saved playback position.

最后一个示例按当前已记录文件的能力范围描述；未来开放更多目标后，再同步真实契约。

### 8.4 文档内部一致性

`assets/next/AGENTS.md` 已主要采用事实、目标和授权边界，适合保持。证据：`:7`、`:13`、`:25`。

设计文档仍存在历史表述：

- §2.1 把 Decision 作为核心流程协议：`docs/next/DESIGN.md:29`。
- 演进路线仍包含确定性高置信度绑定、持久选择和按判断节点唤醒 Agent：`docs/next/DESIGN.md:424`、`:431`。

建议在文档批次中明确这些表述已被 §2.3 的决定替代，避免未来实现者从不同章节获得相反指导。

## 9. 任务引擎：执行基础设施与判断边界

### 9.1 是否内置“何时请示 Agent”

**内核没有直接判断何时联系 Agent，也没有在所读 TaskEngine 中调用 Codex turn/start。** 它提供了通用持久 Decision 机制。

- `JobContext.needsDecision` 写入状态和选项：`packages/nipa_harness/lib/src/tasks/engine.dart:41`。
- 进入该状态后执行上下文退休：`:226`。
- 调度只继续 queued、interrupted、cancelling 等状态：`:378`。
- `resolveDecision` 要求任务版本及精确 ActionCall 属于已有选项：`:283`。

真正固定判断节点的已核实实例是弹幕对齐执行器：计算完成后调用 needsDecision，并用 choice checkpoint 决定 apply/keep。证据：`lib/next/danmaku/executors.dart:286`、`:398`。

因此，问题首先在领域执行器如何使用内核，而不是任务的持久化、恢复、重试或取消机制。

### 9.2 建议的任务语义

- 执行任务只执行明确输入，完成后交付数据和验证回执。
- 分析任务成功表示“分析结果已生成并验证”，不表示用户目标已经解决。
- 未匹配、未知身份、多个候选可以是正常结果数据。
- 缺失登录、对象失效或不变量冲突返回结构化条件或错误。
- 需要另一个业务操作时，由 Agent 调用独立 Action，而不是恢复一个固定选择分支。
- 已提交副作用的取消和恢复仍需验证，保留现有机制。

下载执行器已有按设置自动导入、扫描及记录识别未完成的行为。证据：`lib/next/downloads/download_executor.dart:165`、`:203`；`lib/next/downloads/download_library.dart:40`。

应保留 Classic 既有行为和用户配置的自动索引；Next 下载完成事件可携带真实文件数据。不能由下载执行器预设 Agent 下一步必须识别、绑定或请示。

### 9.3 事件与 Agent 唤醒

当前任务已有公开事件和变化流，可作为观察基础。证据：`packages/nipa_harness/lib/src/tasks/model.dart:266`；`packages/nipa_harness/lib/src/tasks/engine.dart:125`、`:216`。

建议：

- 领域产生事实事件，例如数据集可用、下载完成、身份过期。
- 事件携带对象引用、版本、数据摘要和结果引用。
- Agent Runtime 根据用户正在追踪的目标和订阅决定是否开启或继续 turn。
- 合并、去重和预算控制留在运行时基础设施。
- 领域代码不产生“请选 A/B 后继续”的唤醒指令。

当前 revision 是逐任务 cursor。批量 `task.wait` 应接受逐任务 revision，或另建全局事件 cursor，不能把一个 afterRevision 用于多个任务。

### 9.4 存量兼容

不建议第一批直接删除 JobState.needsDecision：

1. 先停止新领域任务生产固定 Decision。
2. 对齐任务改成完成分析；身份流程由媒体组按原语目标替换。
3. 兼容读取已有 Decision 快照和 GUI 按钮。
4. 显式迁移或终结旧任务，保留回执和审计。
5. 生产者、恢复路径及存量数据处理完成后，再移除内核 API。

这样可以独立合并，避免任务恢复被破坏。

## 10. 分批实施计划

收益与风险为本次评审判断，尚未通过模型使用实验量化。

| 批次 | 范围 | 收益 / 风险 | 独立合并条件与验收 |
|---|---|---|---|
| 1 | MCP instructions、description、设计文档旧表述 | 高收益 / 低风险 | 不改变执行行为；说明只描述真实数据、效果和约束；覆盖率不变 |
| 2 | settings 批量读写、describe 投影；下载暂停/恢复合并及批量操作 | 高收益 / 中风险 | 旧调用兼容；逐项失败和 revision 正确；删除仍独立 destructive；不改变 Classic setter 行为 |
| 3 | 弹幕只读对齐分析、通用属性更新 | 高收益 / 中风险 | 新路径无需 Decision 任务；允许任意明确偏移；旧对齐任务可恢复；方向与单位一致 |
| 4 | state.describe/query 首版公开视图 | 高收益 / 中高风险 | 与旧读接口结果等价；秘密不可见；查询无业务写入；权限、分页、预算和截断可验证 |
| 5 | capabilities.discover、主要入口与兼容别名区分、工具加载实验 | 高收益 / 中风险 | 全能力仍可发现和调用；恢复线程可用；真实 Effect 审批保留；记录模型请求中的加载数量和 schema token |
| 6 | 弹幕获取与附加分离、显式数据版本替换、去重透明化 | 高收益 / 高风险 | 获取不修改绑定或播放器；附加不访问来源；本地/Classic 轨道有明确引用；重复和冲突数据可解释 |
| 7 | 来源数据契约、Action 包注册、内置来源适配 | 长期高收益 / 高风险 | 每个来源可单独迁移；整包、本地、分段、cursor 数据均能消费；会话和请求仍由宿主控制 |
| 8 | 任务 Decision 存量迁移、退休相关内核机制、事件驱动观察 | 中高收益 / 高风险 | 不再有固定判断生产者；重启、取消、重试及历史任务兼容；领域代码不决定 Agent 请示节点 |

媒体组重构作为并行既定交付，不纳入以上批次重新实现。与它的交接只包含：

- 已确定的目录列表、哈希、元数据查询和批量绑定契约。
- 后续统一目录中哪些入口作为主要工具、哪些保留兼容别名。
- 查询视图采用的稳定实体 ID、来源和版本。
- 存量识别任务及覆盖率基线的迁移责任。

第 4 批可以先新增查询而保留所有旧 getter；第 5 批再减少模型目录中的重复入口。第 6、7、8 批均不作为前面批次合并的前置条件。

### 10.1 覆盖率基线的迁移

当前测试逐项要求基线中的旧 Action ID 和 Effect 存在。证据：`test/next/capability_coverage_test.dart:73`。

工具合并后，不能通过删除基线行证明覆盖未下降。建议同时维护：

- 能力覆盖：用户可完成的操作和设置。
- 主要 Action 契约：新入口及 Effect。
- 兼容映射：旧 Action 到新入口。
- 行为场景：结果、边界和来源是否保留。

退役 getter 或流程节点时，验收其能力已由新工具覆盖。减少 Action 数量与保持能力覆盖可以同时成立。

### 10.2 Agent 使用体验验收

以下为建议场景，不是本次已运行测试：

| 场景 | 应观察到的结果 |
|---|---|
| 修改多个字幕和弹幕设置 | 少量发现与批量修改；返回各项值、revision、apply 和失败 |
| 查看任务及其产出文件 | 一次查询或有限关联获得公开回执，无逐个任务拼接 |
| 根据三个锚点校正弹幕 | 分析直接返回数据；可设置不同于估计的值；无需 apply/keep |
| 解析 B 站多分 P | 一次返回全部结构化候选，无再次选择调用才能取得同一数据 |
| 获取弹幕而暂不附加 | 只产生数据集，播放器与绑定不变 |
| 附加已有本地数据集 | 不发起线上获取，返回明确绑定和挂载状态 |
| 查看去重情况 | 区分缓存重复、轨道冲突和显示折叠，保留原始数据 |
| 添加只有 URL 获取能力的来源 | 无须实现无意义的 search/listEpisodes |
| 查询带 token 的来源数据 | 秘密字段及认证 URL 参数不可见 |
| 删除下载文件 | 即使工具按需加载或采用批量，仍经过真实 destructive 审批 |
| 查询大量历史和绑定 | 分页、预算及截断明确；查询不启动扫描或刷新 |
| 重启存在旧 Decision 的任务 | 存量处理可解释、可恢复，不丢失回执 |

验收同时记录完成率、错误选工具次数、无效调用、额外确认次数、模型上下文中的工具数量和 schema token。工具调用少只有在结果完整、授权正确且状态可验证时，才代表体验改善。