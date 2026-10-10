# 媒体能力原语实现报告

## 1. 完成了什么

在 `next/capability-layer` 完成重构，未 commit、未 push。
删除 Next 的 filename_parser、识别候选/补证/重新判断/Decision 状态机及 Release 级联，
移除所有通过文件名推断集号的 Next 逻辑。扫描只枚举、探测、计算头哈希和建立文件索引。
Classic 扫描与弹弹play匹配代码、AGENTS.md 均未修改。

新增完整文件列表、批量哈希、批量元数据查询与搜索、批量绑定与解绑。
保留现有媒体库读取、字段覆盖、元数据刷新和 Classic 可靠投影。
v5 升级测试逐表核对已有身份、绑定、证据、快照、FileEpisode 和 outbox 原样保留；
旧未完成的识别任务带明确失败回执退出，历史终态任务保持原样。

48 集调用次数通过 Harness InvocationObserver 断言：

- 任意文件名、弹弹play哈希无匹配：1 次完整列表 + 2 次元数据调用 + 1 次批量绑定。
- 48 集哈希均匹配：1 次批量哈希 + 1 次批量绑定。

同时覆盖文件不存在、内容修订变化、季/集成员关系、身份冲突、整批回滚、
一文件多集/一集多文件、显式跨来源映射、绑定来源、防止自报 boundBy、
跨重启幂等、元数据覆盖优先级和 Classic 投影失败重试。

### 新工具

| 名称 | Effect | 一句话语义 |
|---|---|---|
| `media.files.list` | read | 返回目录或作品的完整文件列表及大小、时长、头哈希、当前绑定。 |
| `media.hash.match` | read | 返回多个文件的弹弹play hashOnly 候选或逐项错误。 |
| `media.metadata.search_batch` | read | 一次搜索多个元数据来源或查询词。 |
| `media.metadata.get_batch` | read | 一次查询多个作品、季或集的详情，重复引用只获取一次。 |
| `media.identity.bind_batch` | write | 原子保存显式文件、集、季、作品绑定以及宿主来源、理由和证据。 |
| `media.identity.unbind_batch` | write | 原子撤销多个实体的全部或指定绑定并追加撤销审计。 |

保留工具和输入输出事实见 `lib/next/media/README.md` 与 Action schema。
MCP 工具名称将 Action id 中的点替换为下划线。

### 旧 Action 与取代能力

| 旧 Action | 取代它的原语 |
|---|---|
| `media.identification.start` | `media.files.list`、`media.hash.match`、`media.metadata.search_batch/get_batch` 提供原始信息；`media.identity.bind_batch` 保存显式选择。 |
| `media.identification.get` | `media.files.list`、`media.identity.get` 读取文件信息和真实绑定状态。 |
| `media.identification.add_evidence` | `media.metadata.get_batch/search_batch` 提供外部信息；`media.identity.bind_batch` 的 reason/evidence 保存判断依据。 |
| `media.identification.reconsider` | `media.metadata.get_batch/search_batch`、`media.hash.match` 提供新信号；判断由 Agent 完成。 |
| `media.identification.apply_release` | `media.identity.bind_batch` 显式提交作品、季和全部文件映射，无文件名级联。 |
| `media.identity.bind` | `media.identity.bind_batch`，不再依赖 candidateId 或 Decision revision。 |
| `media.identity.unbind` | `media.identity.unbind_batch`，支持文件、集、季、作品和指定绑定。 |
| `media.identification.skip` | `media.files.list`、`media.identity.get` 暴露未绑定事实；Agent 自行决定不绑定，无需流程状态。 |
| `media.identification.defer` | `media.files.list`、`media.identity.get` 暴露未绑定事实；Agent 自行决定暂缓，无需流程状态。 |
| `media.library.scan`（保留 id） | 仅提供索引基础设施；原识别功能由列表、哈希、元数据和批量绑定原语覆盖。 |

覆盖基线同步替换 9 个流程 Action 为 6 个原语；其他 Action 和 126 个设置保持覆盖，
运行时为 55 个 Action。没有通过修改测试门槛降低覆盖要求。

## 2. 决策

- 批量绑定同步执行，整批校验和事务提交，失败指向 `/entries/<index>`；
  不创建新的“识别任务”。扫描、刷新和投影保留 Task Engine 基础设施。
- 外部成员关系由来源目录校验，同一批的作品/季详情只获取一次。
  文件名保持原始数据；哈希未命中不搜索兜底，命中不自动接受。
- 身份是来源无关的本地实体；跨来源归并通过显式 workId/releaseId/localEpisodeIds。
  仅建立明确选择的集及其父实体，不导入或绑定未选择的整个季目录。
- File/FileLocation、绑定、快照、证据、FileEpisode、outbox 和幂等回执同事务保存。
  requestId 按 Action/origin 隔离，重复请求复用结果，输入变化返回 conflict。
- GUI 的 boundBy 为 user，其他外部调用为 agent；模型不能提供 boundBy。
  撤销保留原始绑定来源，另存撤销者、理由和证据。
- 文件列表、哈希和元数据批量查询均为 read，不创建索引、缓存、绑定或任务；
  未索引文件可由 path 直接绑定。保留既有 identity.get 的基础设施按需登记语义。
- 时长使用已有 fvp/MDK 的 prepare 获取，不播放；不可读取或超时为 null。
  未新增依赖或改变构建配置，时长端口可注入，离线测试不加载 native 播放器。
- 弹弹play上游匹配仍逐文件请求；48 集工具调用只有一次批量哈希，
  其内部为 48 次 hashOnly 请求，绑定时整季目录仅请求一次。

## 3. 验收命令与真实输出

使用 `~/development/flutter-3.44.6/bin/`，没有运行 pub get；测试未访问线上服务。

| 目录 | 命令 | 输出摘要 | 退出码 |
|---|---|---|---|
| `packages/nipa_harness` | `~/development/flutter-3.44.6/bin/dart test` | `00:00 +86: All tests passed!` | 0 |
| 仓库根目录 | `~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next test/next` | `No issues found! (ran in 3.8s)` | 0 |
| 仓库根目录 | `~/development/flutter-3.44.6/bin/flutter test --no-pub test/next` | `Capability coverage: 55 actions, 126 settings.`；`00:08 +268: All tests passed!` | 0 |
| 仓库根目录 | `git diff --check` | 无输出 | 0 |

完整 Next 测试日志保存在本机 `/tmp/nipa-media-primitives-flutter-test.log`。
新增/改写的测试只使用构造 fixture、MockClient 与注入的时长端口。

## 4. 问题

没有需要主控决定的事项。线上来源响应与 native MDK 时长的真机行为不属于这些离线
验收的证明范围；主控可继续真机验收并按既定原则重写 AGENTS.md。
