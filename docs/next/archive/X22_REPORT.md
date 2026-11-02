# X22：activity 与 ui.open

2026-10-11，`next/activity`，工作目录 `~/Desktop/nipaplay-next-wt/activity`。

已读取本 worktree 的 TEAM.md、RESEARCH.md。此 worktree 缺少任务指定的提案文件，因此只读主仓库同路径提案的第一、二节；主仓库没有构建或修改。

## 1. 完成了什么

新增公共视图 `activity`，接入现有 `state.describe` / `state.query`。默认按事件时间倒序，同时间按稳定事件 ID 排序。Agent、未来动态页和“本轮改了什么”可以直接使用同一份行数据，显示标题、时间、操作者、设备、关联对象和事实，不需要补查数据库或任务日志。

覆盖来源如下：

| 变化 | 事实来源 | 提供的事实 |
|---|---|---|
| 任务创建、状态、进度、回执 | `job_events`，任务输入，`task_origins` | 任务 ID、状态/阶段/修订、验证等级、公开回执、发起来源 |
| hook 创建、执行、回执 | 同一任务历史 | 事件、对象路径、退出码、耗时；hook 修改设置关联其任务 |
| 弹幕交入、绑定、替换、撤销 | `danmaku_binding_events` | 来源视频、绑定 ID、条数、缓存 ID、交入来源；不返回弹幕正文 |
| 身份绑定、撤销 | `media_evidence` 与关联身份 | 对象、站点身份、关系、绑定 ID、理由；撤销后证据保留 |
| 身份冲突 | journal 的 conflict；投影冲突转换记录 | 被拒绝的身份尝试与当前事实分开；不把失败说成绑定成功 |
| 元数据快照、字段修改 | `media_snapshots`、`media_metadata_edits` | 公开元数据、来源、抓取和收到时间、修改模式 |
| 设置修改 | `settings_changes` | 键、显示标题、前后值、修订、理由、来源 |
| 来源增删、修改和登录状态；账号登录/退出 | Classic 成功保存后的公开差异；相关调用 journal | 名称、类型、公开地址/用户名、连接/登录前后状态 |
| 活动 harness 提交 | 当前 harness 的 `git log` | hash、标题、作者、作者时间、提交时间、仓库 |

所有行含 `id / at / type / title / actor / origin / deviceId / originDeviceId / invocationId / entityId / entityIds / jobId / subjectId / source / facts`。不适用或无法恢复的字段为 null；空的实体集合为 `[]`。事件 ID 带来源命名空间。`deviceId` 是事实归属设备，Mesh 调用另以 `originDeviceId` 表达发起设备。

支持时间、类型、实体、任务、调用来源等顶层字段过滤；`entityIds.contains` 是精确成员匹配。沿用 `state.query` 的 `limit / nextCursor / select / orderBy`。例如：

```sh
./nipa query activity '{"filter":{"at":{"gte":"2026-10-11T12:46:00Z"},"type":{"in":["identity.bound","identity.revoked","identity.conflict"]}},"limit":20}'
./nipa query activity '{"filter":{"entityIds":{"contains":"<file/work/episode ID>"}},"limit":20}'
./nipa query activity '{"filter":{"invocationId":{"eq":"<invocation ID>"}}}'
```

新增 `ui.open`，保留原有 `ui.navigate` 的契约。输入恰好一个 `page`、`entityId` 或 `path`：

- 页面：调用现有主页面导航，并观察实际选中的可见 Classic 页面。
- 文件/剧集：优先打开本机已有可用位置，复用 `PlaybackCapability` 和 Classic 播放服务；多个位置返回可执行的选择。
- 作品、发行版本或没有可播放位置的剧集：沿父实体找到作品，有唯一已接受的弹弹play作品身份时打开现有详情页。
- Classic 无对应界面：返回 `opened:false`、`actual:null` 和具体原因。成功则返回实际页面、作品详情 ID 或播放器/路径/播放状态。外部播放器单独标成 `external_player`。

修改 Classic 的部分仅在原有持久化成功后观察公开事实；不替换客户端、不修改界面或原有保存流程、不新增依赖。新功能都是能力接口，未添加新的动态页面。

## 2. 决策

**派生视图，不复制事件总账。** 读取现有领域历史、journal 和 git。单次查询内物化一次，避免每个内部扫描分块重新读取 git/journal。跨次分页仍是现有 live observation：并发新增会移动页边界，不承诺冻结快照。没有隐含超时或历史条数上限；调用者可以设置 `timeoutMs`。journal 缺失、harness 无 git 仓库或 git 读取失败会给 warnings。

**只补缺失的历史。** 数据库迁移由 v8 追加到 v9，不重写旧事实：

1. `body_changes` 保存 Classic 来源/账号成功保存后的公开 before/after，以及身份投影进入冲突的转换。旧配置只有当前值，没有增删历史，无法倒推出过去；初始化只建立基线，不制造“今天添加了所有旧来源”。Classic 先初始化、Next 后接入时保留公开内存基线，避免漏掉第一次后续修改。
2. `task_origins` 保留任务发起调用；`job_events` 增加 nullable origin/invocation_id，记录后续手动状态操作的来源，后台执行恢复发起上下文。没有旧来源证据时明确 unknown。
3. 弹幕交入事件补充条数、视频与缓存 ID；元数据快照补充 receivedAt/provenance。自动内容变化和 Classic 匹配替换造成的撤销补写到原有 identity evidence。
4. InvocationRecord 可保留脱敏的成功结果，解决“只知道调用 add，不知道返回哪个 source/job ID”的问题。现有 journal 默认仍只持久化 write/destructive 调用，不保存 activity 读查询的结果。

这些记录不保存密码、token、cookie、登录秘密或弹幕内容；公共差异在落盘前脱敏并剥离 URL 认证部分，activity 输出再次投影。设置只暴露当前可见且未被 denylist 禁止的 schema 值。

**谁发起、谁推进分开。** `actor=user` 配 `origin=gui`；经 nipa 的本地 Agent 为 agent/harness_cli；Mesh 保留 mesh:设备 ID；hook 子进程传递自己的任务来源。任务后台推进/回执为 system，`facts.initiatedBy` 保留原发起者。设置的 Invocation scope 与 Classic SettingsAccess scope 分开，避免改变 Classic 的 deferReload 语义。git 作者是提交声明的作者，不把它伪装成经过身份验证的 Agent。

**时间采用变化发生/收到时间。** 导入昨天抓取的快照今天收到，应放在今天的流里；事实保留两种时间。旧快照没有 receivedAt 时只能使用已有 fetched_at。git 只能到秒，不能证明同秒内与其他事件的精确先后。同一任务提交内的状态与回执同时间，不视为两次执行。实体关联可包含当前可解析的关系；回执中的产出文件只在已有该回执的修订出现。

**不把尝试当结果。** `invocation.result` 是来源/账号调用结果，和 committed 的 source/account 事件不同；可以显示调用结果，但不重复计数。身份冲突是失败尝试。当前 activity 聚焦身体变更，不收录所有窗口导航、普通未落盘失败或任意 harness 未提交文件编辑。账号提供商是固定服务，没有独立“新增/删除提供商”模型，账号的加入和移除表现为登录/退出；来源确有 added/removed。

**ui.open 依据 Classic 实际能力。** 不为仅 TMDB 身份的作品假造弹弹play ID；不把收到导航请求说成页面已可见。详情使用现有 `ThemedAnimeDetail`，播放使用同一 Classic 服务；路径输入复用现有本地授权检查和播放能力，实体位置来自本机媒体位置事实。

## 3. 实验

### 环境与实际操作

直接运行本 worktree 的 Debug 可执行文件，使用 `NIPAPLAY_PROFILE=x22activity`，回环请求绕开代理。数据、偏好、凭据和 harness 均在临时 LabProfile。没有启动安装的 `/Applications/NipaPlay.app`，没有读取用户钥匙串/真实数据，没有触碰 lab10。文件是实验生成的 12 秒蓝色视频和一条规范化弹幕。

先修改快进步长 10→12、添加一个 WebDAV 来源并扫描文件；随后登录一个本地协议 fixture 账号、绑定弹弹play作品和临时 TMDB 身份、交入元数据快照、尝试冲突身份、撤销 TMDB 身份、交入一条弹幕。所有能力操作经临时 harness 的 `nipa` 完成。

在临时 harness 写入真实 `hooks/library.file_added`，内容调用 nipa 把快进步长改为 13，然后在那里提交 `af88fb8408790e18a8282c327533827147729d53`，作者 X22 Agent。复制第二个视频并再扫描：真实 hook 进程运行、设置改变、任务与回执落盘。只在这个临时 harness 提交；本 worktree 未 commit/push。

本地 fixture 位于 `127.0.0.1:18922`，提供合成登录和目录响应，Next 仍使用 Classic 的 router/http client 与 `/dandanplay` 路径。第一次尝试真实目录时返回需要登录，改用隔离配置的 fixture，不借用真实用户登录。实验验证的是本机调用、持久化、来源传递与界面链路，不是线上网关认证的可用性。

### 只看 activity 的重建与对照

第一次只连续读取 activity：7 页，每页 7 条，共 48 条、48 个不同 ID，warnings=[]，耗时约 0.784 秒。没有为重建追加数据库、任务详情或其他 state 视图查询。完整重建先保存为 [ACTIVITY_RECONSTRUCTION.md](evidence/x22/ACTIVITY_RECONSTRUCTION.md)，之后才与实际操作输出逐项对照。原始响应在 [activity-pages.json](evidence/x22/activity-pages.json)。

由流重建的顺序（UTC）：

| 时间 | 发生的事 | 谁做的 |
|---|---|---|
| 12:46:05 | 步长 10→12；新增未连接 WebDAV；扫描一个文件成功且 verified | Agent/harness_cli 发起，系统给扫描回执 |
| 12:49:37 | x22-fixture 登录；登录任务 succeeded/verified | Agent 发起，Classic 保存账号，系统完成任务 |
| 12:50:21 | 收到弹弹play快照、绑定 7001；绑定临时 TMDB；收到昨天抓取的评分 8.1/10、52 人快照 | Agent/harness_cli |
| 同秒 | 第二个 TMDB 身份冲突被拒绝；撤销临时身份；交入一条弹幕 | Agent/harness_cli |
| 12:50:43 | harness 实验提交；再次扫描 | git 声明作者 X22 Agent；Agent 发起扫描 |
| 12:50:44 | 扫描产出两个文件；library.file_added hook 把步长 12→13；exitCode=0、600ms、verified | 系统扫描；hook 自己修改设置并完成 |
| 12:51:31 | 重新接受 TMDB 身份、撤销弹弹play身份 | Agent/harness_cli |

对照 [operations.json](evidence/x22/operations.json) 后，要求的变更没有遗漏，未把 conflict 说成成功、未把“弹幕已交入”说成“当时已经播放”。发现并修正了三处查询偏差：

1. `account:dandanplay` 被第一版分类成 account.changed。保留已存 before/after，从事实派生为 account.logged_in；后续观察写入也使用正确类型。
2. 扫描回执已有 fileIds，但顶层 entityIds 为空。现在按回执产出关联文件，hook 的对象路径从已有 locations 解析文件 ID。
3. hook 设置来源已经含任务 ID，但 jobId=null。现在从实际存在的 hook 任务派生 jobId。

补做账号退出、来源删除。删除第一次调用只有 confirm=true，CLI 返回 preview/executed=false；随后明确加 `--execute` 才发生 removed=true，流里没有虚构第一次已经删除。最终重读 8 页共 52 条、52 个不同 ID，warnings=[]，耗时约 0.927 秒：[activity-final-pages.json](evidence/x22/activity-final-pages.json)。

真实组合过滤返回：时间+类型得到账号退出、来源删除 2 行；按第二个文件得到扫描结果与 hook 8 行；按 hook 任务得到状态、回执和设置效果 7 行，均 warnings=[]：[activity-filters.json](evidence/x22/activity-filters.json)。

下面是实际 `state.query` 选择字段返回的两行，完整 envelope 见 [settings-activity-output.json](evidence/x22/settings-activity-output.json)：

```json
[
  {
    "at": "2026-10-11T12:50:44.781293Z",
    "type": "settings.changed",
    "actor": "hook",
    "origin": "hook:job-fddd817e49a6022d008f5bfd423f767f",
    "jobId": "job-fddd817e49a6022d008f5bfd423f767f",
    "facts": {"key":"seek.stepSeconds","revision":2,"reason":"X22 library.file_added hook","before":12.0,"after":13.0}
  },
  {
    "at": "2026-10-11T12:46:05.017819Z",
    "type": "settings.changed",
    "actor": "agent",
    "origin": "harness_cli",
    "jobId": null,
    "facts": {"key":"seek.stepSeconds","revision":1,"reason":"X22 real progress reconstruction","before":10.0,"after":12.0}
  }
]
```

不足：旧记录缺 provenance 无法补出操作者；本次没有两台真实 Mesh 设备或 GUI 手动修改的实验，Mesh/GUI 归属由数据约束检查覆盖；没有实测每一种 SMB/Jellyfin/Emby/共享来源登录。普通失败和 ui.open 调用没有进入身体变更流，因此不能仅从 activity 重建完整窗口操作；git 同秒排序也不能证明因果。

### ui.open 与窗口证据

有弹弹play身份的作品打开实际 Classic 详情，真实返回：

```json
{
  "status": "completed",
  "result": {
    "opened": true,
    "interface": "classic",
    "target": {"entityId":"work-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1"},
    "actual": {"kind":"work_detail","animeId":7001,"entityId":"work-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1"},
    "reason": null,
    "message": null
  }
}
```

[作品窗口截图](evidence/x22/ui-open-work.jpg) 能看见 X22 catalogue fixture 和第一集；截图只捕获该实验进程的主窗口 44049。

切回 home，再让同一作品只保留 TMDB 身份。真实返回：

```json
{
  "status": "completed",
  "result": {
    "opened": false,
    "interface": null,
    "target": {"entityId":"work-ff948ed78c87cee1521ed4890da5025b27c71c57b5e2def8941a4b91003b22f1"},
    "actual": null,
    "reason": "该work没有唯一已接受的弹弹play作品身份，Classic 作品详情仅支持弹弹play；Next 事实页尚未实现。",
    "message": "目前没有界面能显示它：该work没有唯一已接受的弹弹play作品身份，Classic 作品详情仅支持弹弹play；Next 事实页尚未实现。"
  }
}
```

[不支持的实体截图](evidence/x22/ui-open-unsupported.jpg) 仍是 home，没有详情弹窗。第一次截图遇到关闭动画，等稳定后重截。隐藏页面 external_player_console 同样返回 opened=false。文件实体和绝对路径均实际打开 internal 播放，hasVideo=true、durationMs=12000，实际 path 指向实验 x22.mp4；[播放窗口截图](evidence/x22/ui-open-file.jpg) 只捕获新进程的窗口 44143。使用 CoreGraphics 按 PID 找窗口，再 `screencapture -x -o -l <窗口ID>`，没有截整个屏幕。

### 检查、意外与清理

Flutter 固定为 `~/development/flutter-3.44.6`，build/analyze/test 均 `--no-pub`，构建只在本 worktree。初始生成元数据缺 package_graph 与原生 Swift Package 配置，首次运行失败；从相同 lock 的 sibling worktree 复制生成文件并重定位忽略的本地路径，没有 pub get、没有依赖修改。构建使用 `ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache`。CocoaPods 自动改动的 Podfile.lock 已恢复到原值。

最终检查：

- macOS Debug 构建成功：[build 日志](evidence/x22/x22-build-verified.log)。保留已有 CocoaPods/脚本构建警告。
- 受影响 Next 状态/能力/运行层 analyze：No issues found：[analyze 日志](evidence/x22/x22-analyze-verified.log)。首轮 5 个 info lint 已修复。
- 10 个回归文件 117 项通过，加 4 个数据/Classic 约束文件 29 项通过，共 146 项：[回归](evidence/x22/x22-regression-verified.log)、[约束](evidence/x22/x22-constraints-verified.log)。新增约束检查撤销证据保留、query 不写事实、Mesh 来源、账号转换、产出实体关联和公开差异不保存 URL 秘密。已有窗口/播放器平台通道不可用消息未使测试失败。
- nipa_harness journal/harness 21 项通过：[kernel 日志](evidence/x22/x22-harness-tests.log)。根配置不包含 test 包，最初调用缺包失败；最终使用临时 package_config 指向已安装缓存运行，没有改变项目依赖。
- `git diff --check` 通过。本 worktree 未 commit/push。

实验进程按 PID 退出：最终 App 90095、本地 fixture 76945；早先重启的 App 也按各自 PID 退出。仅删除 `LabProfiles/x22activity`，最终 profileExists=false，详见 [cleanup.json](evidence/x22/cleanup.json)。原始状态、操作输出和窗口截图已保存在本报告的 evidence 目录。

## 4. 问题

需要主控决定的事项：没有。
