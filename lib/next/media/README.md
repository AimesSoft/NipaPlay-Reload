# 媒体能力原语

Next 的媒体识别判断属于 Agent。代码提供文件信息、外部元数据和显式绑定，
不解析文件名，不推断集号，不生成识别 Decision，也不把一个季的选择级联到目录文件。
Classic 的扫描、匹配和自动弹幕策略保持原实现。

## 工具契约

Action id 是 Harness 名称；MCP 名称把点替换为下划线。输入输出以
`media_capability.dart` 的 schema 为准。

| 名称 | Effect | 语义 |
|---|---|---|
| `media.files.list` | read | 一次返回目录递归视频列表或作品的全部索引文件位置，含大小、时长、头哈希和当前绑定。 |
| `media.hash.match` | read | 对多个文件查询弹弹play hashOnly 候选，返回逐项结果或错误。 |
| `media.metadata.search_batch` | read | 批量搜索 TMDB、Bangumi、弹弹play等已注册来源。 |
| `media.metadata.get_batch` | read | 批量查询作品、季或集的详情，同一调用中的相同引用只请求一次。 |
| `media.identity.bind_batch` | write | 原子保存显式指定的文件、集、季、作品绑定及理由、证据。 |
| `media.identity.unbind_batch` | write | 原子撤销多个实体的全部或指定绑定，保留来源审计。 |
| `media.metadata.search` | read | 保留单次来源搜索。 |
| `media.metadata.get` | read | 保留单个外部对象详情查询。 |
| `media.identity.get` | read | 读取身份、位置、来源审计和合成元数据，沿用按需 File/FileLocation 基础设施登记。 |
| `media.library.works` | read | 读取 Next 作品及季、集、文件结构，支持非弹弹play身份。 |
| `media.library.work` | read | 读取一部 Next 作品的结构与元数据。 |
| `media.library.import_history` | write | 将 Classic 历史导入旁路索引，不推断绑定者或确认身份。 |
| `media.library.scan` | write | 提交枚举、探测、哈希和文件索引任务，不请求元数据来源。 |
| `media.metadata.override` | write | GUI 与 Agent 均可编辑；宿主记录 actor/origin。mode=persistent 刷新保留，correction 被新快照替代，clear 清除编辑。省略 mode 保持持久覆盖兼容语义。 |
| `media.metadata.refresh` | write | 沿用元数据快照刷新任务，不改变身份。 |

目录列表、批量哈希和元数据查询不写数据库，不创建绑定、缓存或任务。
目录列表没有分页，未索引文件的 `fileId` 为 null；绑定可直接使用它的 `path`。
作品列表返回全部已关联文件位置及存储的探测值，远端或尚缺探测值的字段为 null。
大小单位是字节，时长单位是毫秒，`headMd5` 是文件前 16 MiB 的 MD5。
时长使用已有 fvp/MDK 读取，不启动播放；无法读取或超时则为 null。
文件名只作为原始数据和 hashOnly 请求字段传递，不产生身份信号。
弹弹play上游没有这里可用的多文件匹配接口，批量 Action 内部逐文件发 hashOnly；
一次 Action 的语义仍是返回所有输入文件的独立信号。

## 绑定与不变量

`bind_batch.entries` 的 `kind` 是 work/release/episode/file。
文件目标使用 `entityId` 或 `path`；其他层级可用 `entityId` 绑定既有本地实体，
省略时按外部对象建立对应实体。每条输入明确给出 `workRef` 和理由：
TV 的季身份使用 `releaseRef`，文件或集的身份使用 `episodeRefs`。
Movie 本身就是对应播放单元。Bangumi subject、弹弹play anime 是各自的集目录。

`workId`、`releaseId`、`localEpisodeIds` 显式指向跨来源共用的本地身份；
代码校验层级和父实体，不猜测不同来源的映射。只建立输入涉及的集及其父实体，
不会按目录或文件名扩展绑定，也不会接受未选择的整个集目录。
`episodeRefs` 可含多集，多个文件可指向同一集。可选时间段保留在 FileEpisode 中。

文件可访问性、内容修订、外部季属于作品、外部集属于季、已接受身份冲突和
FileEpisode 的关系/时间段由宿主校验。违反不变量返回稳定 Failure code、
带 `/entries/<index>` 的 violation 和具体原因；整批绑定写入回滚。
绑定、FileEpisode、快照、理由、证据、投影 outbox 和幂等回执在同一事务中保存。

绑定的 `boundBy` 由宿主从 Invocation.origin 写入，GUI 为 user，其余外部调用为 agent；
输入 schema 不接受调用者自报的 boundBy。解除绑定保留原绑定的来源字段，
追加撤销操作的 origin、invocationId、boundBy、理由和证据。
文件绑定证据同时保存实际内容 probe 和文件修订。

`requestId` 按 Action 与 origin 隔离，回执跨重启保存。同一请求重试返回原结果，
同一 requestId 的不同输入返回 conflict。已有冲突不会静默替换；解除绑定属于
可恢复的 write，不删除文件或观看进度。

仅明确单集的弹弹play绑定投影到 Classic。身份提交与 Classic 不在同一数据库事务；
outbox 只有回读确认后才完成。投影失败返回对应条目错误，并明确身份已经提交、
投影仍待完成；重试和启动恢复都使用同一持久 outbox。

## 存储与升级

数据库仍由 NextCore 提供唯一连接；MediaRuntime 仅提供 Capability 和基础设施执行器。
存储保持 Work → Release → Episode、File、FileLocation、FileEpisode 的身份模型，
以及独立 external objects / bindings / evidence / snapshots / overrides。

v5 迁移移除 media_candidates、media_identifications，以及 scan_items 中的子识别任务列，
新增 media_binding_operations 保存幂等请求指纹和结果。
既有 entities、locations、bindings、evidence、snapshots、overrides、FileEpisode、
legacy history、Classic projection outbox 均保留，不重算身份或修改 boundBy。
旧非终态 media.identify / media.apply_release 任务标记为明确失败并追加任务事件，
历史终态任务保持不变；升级不会恢复旧判断流程。
补充时长等 probe 信息不改变文件内容修订，也不撤销原绑定。

## 验证边界

测试使用离线构造的来源 fixture、MockClient 和注入的时长探测端口，不访问线上 API，
不含真实凭据。两项 48 集测试通过 InvocationObserver 断言 Harness 调用次数：
无哈希匹配目录为 1 次完整列表、2 次元数据调用、1 次批量绑定；哈希匹配目录为
1 次批量哈希、1 次批量绑定。调用次数是工具能力的测试事实，不规定 Agent 的调用顺序。
真实来源响应和 native MDK 时长在真机上验收。
