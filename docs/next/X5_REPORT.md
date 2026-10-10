# X5：一个媒体库

日期：2026-10-11。worktree：`library`，分支：`next/one-library`。

## 1. 完成了什么

Classic 的有效弹弹play匹配现在进入既有 Work → Release → Episode、File、FileLocation、FileEpisode 和 binding 模型。启动补齐旧匹配；Classic 历史 Provider 的通知触发同步（250 ms 合并通知）；显式身份绑定/解绑和投影前后也读取 Classic。`media.library.import_history` 保留原 Action 名称，成为可重入的同步入口。

Agent 的单集、exact 弹弹play文件绑定继续通过既有 `media_projection_outbox` 写入 Classic。Classic 无匹配时填写匹配；已有相同 ID 时确认现有记录；已有不同匹配时保留双方事实并报告冲突。TMDB、Bangumi 等身份，以及 Classic 无法表示的多集绑定，留在 Next。没有加入新的匹配客户端、依赖或另一套投影队列。

Agent 可用 `media.identity.get` 的 `bindings.source`、`classicObservations`、`conflicts` 读取来源、历次观察和冲突。共享作品仍由 `media.library.works`、`library.works`、`media.entities` 等既有入口读取；没有修改 `state.query` 或 `nipa`。媒体模块 README 同步更新契约。

真实应用未退出、未重启。真实数据库仅通过 Python SQLite 的 `mode=ro` 查看，没有对真实数据执行迁移、匹配或绑定。没有 commit、push 或 pub get。

## 2. 决策

### 在已有两条链路上接起来

原 `IdentityStore.importLegacy` 只登记文件、位置和 `media_legacy_history`，特意不产生身份；所以 Classic 的作品没有进入 Next。反向链路则已完整存在：显式绑定事务写 outbox，`ClassicProjection` 投递，`media.project` 任务在启动恢复。

只读检查真实库得到：

```text
watch_history.db user_version=2, history rows=215
next.db user_version=7
media_entities=331
media_locations=267
media_bindings=2474
media_legacy_history=215
media_projection_outbox=12, all state=delivered
Next works: 长安十二时辰 (TMDB 90768), 炒翻天 (dandanplay 19768)
```

12 条投影都是《炒翻天》197680001–197680012 集。它们已经投递，缺口在 Classic → Next 的身份物化，而非反向队列尚未执行。

### 什么算 Classic 匹配

复用 `mediaLibraryItemMatchesSource` 和 `UnifiedMediaLibrarySource` 的现有筛选语义，同时要求正的作品/剧集 ID、非空作品名及非 null 剧集标题。清除匹配后保留的 ID 不重新变成绑定。Jellyfin、Emby、弹弹play远端流、共享远端媒体自己的身份不冒充本地弹弹play匹配；它们仍保留文件和旧证据。

实际历史中同一个数值 ID 有多种完全不同的标题，不能把历史中所有非空 `anime_id` 都解释成弹弹play作品。这一筛选使真实库得到 9 部 / 53 集 / 55 个文件，吻合实验 1；两个文件是同集的不同文件记录。

只按同一弹弹play外部引用复用作品、目录和集，不按标题或文件名合并不同身份。Classic 只有 anime 目录，没有季的概念，因此沿用现有弹弹play provider 的模型：Work 与 Release 引用同一个 anime 对象。缺少集号时保留 null，不从标题或 ID 算集号。重复的历史绑定若指向同一实体，按 DISTINCT 实体读取；若外部对象已有多个不同实体所有者，则返回 conflict，不选择一个。

### 冲突和来源规则

| 情况 | 记录与结果 |
|---|---|
| Classic 有有效匹配 | 在原模型中增加 `source=classic_match` 的 accepted 绑定，`boundBy=null`；这只确认 Classic 存在这个匹配，不推断最初是用户还是自动扫描所为。 |
| Classic 改成另一集或清除/删除 | 追加观察、更新当前指针，撤销该观察产生的旧 Classic 文件绑定，清理不再由 accepted 文件身份支持的关联；旧绑定、观察、作品与集实体仍保留。Agent/user 原绑定不动。 |
| Agent 弹弹play匹配与 Classic 相同 | 保存显式来源；Classic 原行及标题保持原值。解除 Agent 绑定不会清除独立 Classic 匹配。 |
| Classic A、Agent 弹弹play B | 两条来源绑定和两个集关联都保留。outbox 标为 `conflict`；Action 返回 `conflict`，消息明确身份已提交，Classic 未被替换。 |
| Classic A、Agent TMDB/Bangumi B | 保留双方关联；若没有显式共用同一个本地 Episode，`identity.get.conflicts` 报 `different_episode`。不据此推断两种来源指的是同一集。 |
| Agent 明确跨来源是同一集 | 使用原有 `workId` / `releaseId` / `localEpisodeIds` 表达映射；共用本地 Episode 时不报告该映射冲突。 |
| Classic 回读与本文件最新 pending/delivered 投影一致 | 保存 `next_projection_readback` 观察，不额外生成一个独立 Classic 文件绑定，避免 Agent 解除自己的匹配后被同步重新恢复。已有独立 Classic 观察不会因为相同指纹而改归来源。 |

`unbind_batch` 默认及指定 bindingIds 都只操作显式绑定。Classic 来源事实通过 Classic 现有匹配/清除操作改变。`conflicts` 包含来源差异及失败的投影 ID；Agent 修正来源事实后，可以重用原 requestId 重试该文件投影。启动恢复 pending，不自动重试 conflict 或决定胜者。双方事实在 Next 并存，Classic 继续使用自己的匹配。

投影先核对观察，实际写 Classic 时又在 Classic SQLite 事务中检查当前匹配，防止读取之后发生的重匹配被覆盖。现有行只更新四个匹配列，不用 REPLACE，不改观看进度、位置、时间、缩略图、media_key、扫描标记或行 ID。新行使用 Classic 标准的零进度、扫描匹配初始值。验证相同身份时接受 Classic 原标题，不要求其变成 provider 标题。

元数据展示保留既有持久编辑优先规则；来源服务快照优先于 Classic 标题快照，后者带 `source=classic_match` 和未知语言 `und`。各个原始 Classic 标题仍在观察里。此顺序只决定展示字段，不撤销或裁决身份事实。

### 可恢复、可重入的数据变化

v8 schema 只追加 `media_classic_observations` 和 `media_classic_current`，使用可重入的 CREATE TABLE IF NOT EXISTS。原表不修改、不清理、不重算；原 `media_legacy_history` payload 原样保留。首次观察也保存原旧证据，后续变化使用追加观察。

每个文件的实体、绑定、关联、观察和当前指针在同一 Next 事务里提交。匹配字段和 hash 构成指纹，观看进度不参与；相同指纹不重复写。整个导入不设“已经迁移”的一次性标记，启动重读 Classic 即可补齐未完成文件，也能同步之后的匹配变化。

Classic 与 Next 是两个数据库，继续使用现有持久 outbox 和回读恢复中间状态，不假装跨库事务。新观察监听在 Core 关闭数据库前停止并排空。读取 Classic 失败会报错，不把读失败解释成空库并撤销来源事实。

## 3. 实验

### 共享库与中断恢复

`test/next/one_library_experiment_test.dart` 使用真正的 `watch_history.db` schema、`WatchHistoryMetadataPort`、Next SQLite、MediaRuntime、Harness Action、TaskEngine 和 Classic 卡片筛选函数。只有元数据服务和视频时长来自离线夹具；文件是临时目录下的合成内容，没有真实路径、凭据或个人数据。

共享库夹具先通过 Action 建立 2 部 Next 作品，其中一部与随后 Classic 的作品同一弹弹play ID。Classic 夹具有 215 条历史：9 部 / 53 集 / 55 条有效文件，100 条远端服务记录和 60 条已清除匹配的记录；保留非零进度、media_key、缩略图、时间等字段。同步后原两个作品保留/复用，作品总数变成 10。

执行：

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/one_library_experiment_test.dart --reporter expanded
```

实际输出（提取实验输出行及完成行）：

```text
X5 initial: history=215; Classic matched files=55; Next works=2->10; Next episodes=53; Classic unchanged=true
X5 existing Next data: both original works reused/retained; bindings/operation receipts unchanged=true
X5 repeat: entities/bindings/snapshots/observations unchanged=true
X5 Agent Dandanplay: Classic episodeId=7101; Classic card visible=true; protected columns unchanged=true
X5 Agent TMDB: Next binding accepted=true; Classic rows unchanged=true
X5 conflict: {"code":"conflict","acceptedSources":["classic_match","explicit_binding"],"conflictTypes":["different_episode","classic_projection"],"ClassicUnchanged":true}
X5 live Classic rematch: currentAnime=8010; old observation retained=true; Agent binding retained=true; conflict visible=true
X5 Classic add/delete: added identity=true; removed active link=true; observations retained=2; foreign_key_check=[]
X5 interrupted: committed observations=17; locations=17; row18 fully rolled back=true
X5 restarted: observations=53; first17 preserved=true; Classic unchanged=true; foreign_key_check=[]
X5 restarted repeat: observations=53 (no duplicates)
X5 delivery interrupted: Classic episode=7101; outbox=pending; Agent binding durable=true
X5 delivery restarted: outbox=delivered; receipt.projectionVerified=true; Classic/bindings unchanged=true
00:02 +4: All tests passed!
```

导入中断用 SQLite trigger 在第 18 条观察插入时执行 RAISE(ABORT)：本条事务回滚，前 17 条保留。移除故障注入、关闭并重开运行时与数据库后，启动补齐到 53 条，前 17 条逐字段相同，再次同步不重复。这验证数据库事务失败后的运行时重启恢复，没有模拟操作系统断电。

另一个中断点是 Classic 已写入、验证未完成：注入回读失败，Action 返回 unavailable，outbox 留 pending；重开后 `media.project` 成功，回执 `projectionVerified=true`，Classic 行和原绑定逐字段相同。

第四项数据约束检查：Classic 原匹配与 Agent 选择同一集时没有冲突；绑定和解除 Agent 绑定后 Classic 原行仍完全相同，独立 Classic 绑定及文件关联保留。

### 意外和修正

1. 首轮老回归仍断言 schema=7；新增迁移后实际为 8。更新对应断言，并增加 v7 升级及 schema 重入检查。
2. 首轮共享库实验里，outbox 显示 delivered，但原 Classic 行仍保留旧 ID。macOS 把 `/var/...` 规范化为 `/private/var/...`，原实现只查规范化路径，给已有文件新建了另一个实体/匹配。现在 `readFile` 优先查调用者传入的已存路径，再查规范化路径；保留原行并填写匹配。修正后上述真实 SQLite 实验通过。
3. 中断恢复检查第一次用了 Map 的普通 contains 比较，日志实际包含原记录但比较失败。改成按 observation ID 取记录并逐字段比较，确认前 17 条确实没有被重写。

### 回归与数据保护

完整 Next 和观看历史回归：

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next test/watch_history_database_migration_test.dart \
  test/watch_history_model_test.dart test/watch_history_startup_test.dart \
  test/watch_history_legacy_startup_test.dart --reporter expanded
```

```text
01:19 +361: All tests passed!
```

包括 Mesh 真实本地 TLS 回归；其 HTTP 回环客户端设置 DIRECT。X5 本身不访问网络。完整回归之后，补充了 schema 重入、同集解绑保护、来源语言和唯一实体校验；最终对相关范围复验：

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/one_library_experiment_test.dart test/next/next_database_test.dart \
  test/next/media_identity_test.dart test/next/media_classic_projection_test.dart \
  test/next/next_core_test.dart --reporter expanded
```

```text
00:02 +40: All tests passed!
```

`next_database_test` 验证 v0–v7 升级，并逐表、逐行比较 v7 升级前后所有原表，包含任务/回执、历史绑定、证据、快照、位置、legacy evidence 和 delivered outbox；再次执行 v8 schema 迁移成功，foreign_key_check 为空。原有媒体批量绑定原子性、幂等回执、Classic 启动和 legacy JSON 迁移回归均通过。

最终静态检查：

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next/media lib/next/next_database.dart lib/next/next_core.dart \
  lib/providers/service_provider.dart test/next/one_library_experiment_test.dart \
  test/next/next_database_test.dart
```

```text
No issues found! (ran in 4.0s)
```

`git diff --check` 通过。未测试线上元数据响应、真实用户数据库的写入，或新版本 GUI 真机运行；Classic 可用性在实验中通过实际 SQLite 读回和其现有页面筛选语义验证。

### 用户真实数据的只读推算

通过 `sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)` 查看两个数据库，只查询表结构、计数、匹配元数据和外部 ID，不输出真实文件路径。读取时数据如下：

| 弹弹play anime ID | Classic 作品名 | 文件记录 | 不同集 | 合并后的来源 |
|---|---|---:|---:|---|
| 19768 | 炒翻天 | 12 | 12 | 复用现有 Next 作品与集；保留 Agent 绑定及 12 条 delivered 投影，追加 Classic 回读事实 |
| 19290 | 穹庐下的魔女 | 2 | 2 | Classic 匹配 |
| 18727 | 无职转生Ⅲ ～到了异世界就拿出真本事～ | 11 | 11 | Classic 匹配 |
| 19873 | 尼古喵喵 | 7 | 7 | Classic 匹配 |
| 19566 | BanG Dream! YUME∞MITA | 6 | 6 | Classic 匹配 |
| 17864 | 莉可丽丝 新作 | 8 | 6 | Classic 匹配 |
| 18459 | 拔作岛 | 3 | 3 | Classic 匹配 |
| 18795 | Silent Witch 沉默魔女的秘密 | 5 | 5 | Classic 匹配 |
| 17493 | 吊带袜天使 新作 | 1 | 1 | Classic 匹配 |
| TMDB TV 90768 | 长安十二时辰 | — | — | 保留现有 Next TMDB 身份，不写 Classic |

预计 **10 部作品**：新增 8 部，原有 2 部保留，《炒翻天》只计一次。Classic 的 55 条有效文件路径已全部存在于 Next 索引。64 个既有外部对象 ID 都符合当前稳定 ID 算法，无需修正 ID。

```text
external object canonical IDs: 64 noncanonical: 0
Classic works= 9 Next workRefs= [('tmdb', '90768'), ('dandanplay', '19768')] overlap= 1 predicted= 10
eligible Classic file paths already indexed= 55 / 55
```

真实库的 2474 条绑定（其中 2448 条旧 `agent_evidence`、26 条 `explicit_binding`）保持原样；既有同实体/同对象重复绑定也不清理。推算基于本次只读快照，用户之后增删或重匹配会改变实际同步结果。

## 4. 问题

需要主控决定的问题：**没有**。

本次交付是代码、夹具观察和只读推算。主控后续集成并在新版本真机验证页面及迁移；本次没有操作正在运行的真实应用或真实数据库。
