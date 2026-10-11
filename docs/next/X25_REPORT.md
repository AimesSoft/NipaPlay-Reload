# X25：持久化 Agent 后续与自动唤醒

2026-10-11，worktree `~/Desktop/nipaplay-next-wt/followups`，分支 `next/followups`。已读 TEAM、RESEARCH、X23、X22。实现仓库没有 commit、push、依赖变更或 pub get；只在本 worktree 构建。没有启动安装的 NipaPlay、访问登录钥匙串或正常应用数据，也没有操作 lab10。

## 1. 完成了什么

- 新增 `followup.register / followup.list / followup.cancel`，经现有 Harness、CLI、MCP 和 Mesh 能力入口可用。
- 登记任务终态条件 `when: {jobId}`，成功、失败、取消都可唤醒，并附公开任务事实与回执；也支持现有 hook 事件 `download.completed / library.file_added / playback.started`，可限制 `objectId`。事件没有对应 hook 程序也会被后续观察。
- 内嵌调用通过 `harness_cli:chat:<NIPAPLAY_CHAT>` 找到自己的线程，保存稳定 thread ID。无会话号的终端调用可传 `threadId`，不传则在登记时的活动 harness 中新建线程。
- SQLite v10 追加后续快照、事务性事件与 hook 事件记录，不重写已有任务、绑定、回执或设置。NextCore 在没有聊天宿主时仍观察任务；启动、任务变化和宿主空闲后重新检查。
- 后续触发后排队，宿主使用原线程 resume + turn/start，输入包含登记说明、来源与触发事实。与界面的选线程、开启回合串行，忙回合不 interrupt、不 steer。
- 提供 `followups` 公共状态视图：标题、等待条件、说明、来源、目标线程、实际回合、触发事实、状态和原因，供以后小人旁的提示直接查询。
- `activity` 包含登记、触发、待执行原因、派发、实际开启的回合和回合结果。执行记录保存实际 session 来源，facts 保留登记者来源。同时修正 activity 将 X23 无 invocationId 的回合边界日志强转为调用记录的问题。
- 种子 AGENTS.md 只追加一条事实：“耗时操作是 NipaPlay 的后台任务：Agent 可以登记后续，让自己在任务结束时被唤醒。”

接口实现与语义见 [followups/README.md](../../lib/next/followups/README.md)。例如：

```sh
./nipa call followup.register '{"when":{"jobId":"<jobId>"},"title":"下载完成后处理弹幕","instruction":"检查下载回执，再判断弹幕是否够用；不足时处理下一来源，然后告诉用户。"}'
./nipa query followups '{"filter":{"state":{"in":["waiting","ready"]}}}'
./nipa call followup.list '{}'
./nipa call followup.cancel '{"id":"<followupId>"}'
```

代码没有弹幕阈值、下载后入库流程或站点选择规则。这些都由被唤醒的 Agent 决定。

## 2. 决策

1. **终端默认新线程。** 没有 NIPAPLAY_CHAT 时不猜测最近一个 Codex 会话；保存当前 harness，等宿主可用时在那里新建线程。显式 threadId 也保留。切换 harness 后，旧后续保留并注明原 harness 未激活，不迁移到另一仓库。
2. **宿主整体空闲后再执行。** 当前 X23 是一个宿主、一个所选线程，因此任何进行中的回合都阻止后续切换线程；这比只等待目标线程更严格，避免未来聊天界面正在工作时被后台选择操作切走。目标线程历史也检查 inProgress。
3. **触发与执行分开。** waiting 等条件；ready 等宿主或空闲；dispatching 已开始派发；started 已取得 turn ID；completed 表示那一轮完成。宿主启动失败保留 ready 和具体错误。明确 RPC 拒绝或失败回合保留 execution_failed。回合 completed 不证明 Agent 的每项媒体操作成功，仍以领域回执为准。
4. **一次性派发处理跨进程确认丢失。** SQLite 和 Codex 无法做同一个事务。发送前持久化 dispatching，输入带唯一 followup marker；确认丢失时从 Codex 原线程历史找该 marker，采用已有回合，不重复 turn/start。不能核实已有回合时保存执行失败及原因，不盲目重放。正常已完成、取消、失败记录均不因重启再次派发。本次未向真实 CPA 注入“请求已接受但响应丢失”的窗口；该恢复路径的实现不冒充已做过故障注入实验。
5. **条件语义。** jobId 可登记已经进入终态的任务。hook 条件等待登记后的下一次应用事件，不是历史事件重放；download.completed 还可从持久成功任务恢复。playback.started 是应用实际播放事件，library.file_added 是原有入库事件，不扩展成离线文件系统监视器。
6. **持久事实与对话历史各归其主。** 只保存后续说明、触发事实、状态、来源及 thread/turn ID，不创建第二份聊天历史。实验协议日志仅在临时 profile 中生成，导出脱敏证据后删除 profile。

## 3. 实验与真实输出

### 环境与证据

两次下载均在本 worktree 的 Debug 实例，通过 X23 的 VM 实验入口向真实内嵌 app-server 发送用户消息。服务端头部确认 `model=deepseek-v4.1-flash`、`provider=cpa`。每个 profile 独立 CODEX_HOME；config/auth 保留权限复制，skills 只读链接；公共 `/etc/ssl/cert.pem` 副本由 CODEX_CA_CERTIFICATE、SSL_CERT_FILE 引用。NO_PROXY 包含 CPA、127.0.0.1、localhost；实验 HTTP 请求直接绕过代理。没有用实验 Agent 承担实现工作。

种子来自 X19 的开放授权 Sintel 预告片（Blender Foundation，CC BY 3.0），4,372,373 字节，SHA-256：

```text
b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254
```

[experiment.py](evidence/x25/experiment.py) 复用 X19 的真实本机 tracker/BT TCP peer，每块延迟 0.8 秒。在线传输实际 267 个 block 请求，servedBytes=4,372,373，持续约 215 秒。用户只提出任务，没有告诉 Agent 用哪一个工具：

```text
帮我下载这个种子 http://127.0.0.1:55122/sintel.torrent ，下完以后加进媒体库，然后告诉我；下载时不用一直等着。
```

完整输出均保留，没有以 Agent 总结代替命令/任务事实：

| 实验 | 对话及命令输出 | 状态采样 | 完整 activity 原始输出 |
|---|---|---|---|
| 在线 | [transcript](evidence/x25/online-transcript.json)、[协议流](evidence/x25/online-chat.jsonl.gz)、[操作](evidence/x25/online-operations.json) | [samples](evidence/x25/online-samples.json.gz) | [75 行完整 JSON](evidence/x25/online-activity.json)、[完整贴出版本](evidence/x25/online-ACTIVITY.md) |
| 停机完成后重启 | [transcript](evidence/x25/restart-transcript.json.gz)、[协议流](evidence/x25/restart-chat.jsonl.gz)、[操作](evidence/x25/restart-operations.json) | [samples](evidence/x25/restart-samples.json.gz) | [44 行完整 JSON](evidence/x25/restart-activity.json)、[完整贴出版本](evidence/x25/restart-ACTIVITY.md) |
| 边界补充 | [操作](evidence/x25/controls.json)、[协议流](evidence/x25/controls-chat.jsonl) | 操作中含各次实际状态 | [34 行完整 JSON](evidence/x25/controls-activity.json)、[完整贴出版本](evidence/x25/controls-ACTIVITY.md) |

三份 activity 的 nextCursor 都是 null，warnings 都是 []，没有省略后续记录或领域记录。以下时间均为 UTC。

### 在线：登记、结束、同线程自动续接

Agent 自行发现 followup.register，真实登记结果摘录：

```json
{
  "id": "followup-1791728233428934-9ab2d900",
  "state": "waiting",
  "title": "Sintel 下载完成后入库",
  "condition": {"jobId":"job-926a68237e3556ddfcbcad5d208c1676"},
  "threadId": "01a12b52-88f7-7172-a689-50e82b2e3243",
  "turnId": null,
  "origin": "harness_cli:chat:nipa-1791728190736996-4bf812f",
  "invocationId": "inv-1791728233427475-58"
}
```

登记说明是 Agent 自己写的条件判断：succeeded 时核对文件、download.import、必要时补索引/身份并汇报；failed/cancelled 时如实告知。

初始轮 `01a12b52-8ade-7692-9254-d9a0e974b799` 于 14:17:26.078 结束，共 53.858 秒。登记后它还执行了 `sleep 5; download.read` 来确认已开始，然后回复：

```text
下载已经在跑了，后续也登记好了。
……任务一到终态（成功或失败）就会唤醒我。
……你可以先去做别的，我这边不用一直守着。
```

从初始轮结束到下载终态的 99 个约两秒采样，跨度 195.366 秒，原回合全部为 completed。协议流期间没有任何 turn/started，也没有 task.wait；不是把下载等待藏在进行中的回合里。下载受理后、登记和初次汇报期间当然仍有初始轮在执行。

14:20:43，下载 succeeded、回执 verified 后，宿主自动在同一线程开启 `01a12b56-60cb-7c82-ad58-6bd7ee17fcab`。Agent 的第一条回复：

```text
下载已成功并验证。我来核对文件并导入媒体库。
```

新回合实际调用 download.read、download.import、media.library.scan、Bangumi 公开检索和 media.identity.bind_batch，再查询作品和文件验证。由于未登录弹弹play，Classic 扫描没有识别出可投影的历史；Agent 将文件登记进 Next 索引，绑定 Bangumi subject 49694 / episode 912364。最终回复摘录：

```text
下载完成并已入库。
……状态 succeeded、回执 verified
……作品：《辛特爾》（Sintel，2010）……身份来源：Bangumi
这是个 52 秒的片段，不是完整片。
```

实际 Next library.files 返回一个文件、一个 episode、一个 work，historyStatus=no_history。两个 Agent 都把这份预告片绑定到正片集且 relation=exact；在线 Agent 虽明确提示时长差异，这个身份关系仍是其判断，不能把本实验当作预告片/正片识别正确性的证明。

该轮 153.249 秒后 completed。在线完整后续 activity 生命周期：

| 时间 | type | 来源 | 事实 |
|---|---|---|---|
| 14:17:13.428928 | followup.registered | 原 chat session | waiting，原 thread，登记说明与任务 ID |
| 14:20:43.565720 | followup.triggered | application | ready，succeeded/verified 触发回执 |
| 14:20:43.583122 | followup.dispatching | application | 保存派发目标 |
| 14:20:43.596749 | followup.started | 原 chat session | turn `01a12b56-60cb-7c82-ad58-6bd7ee17fcab` |
| 14:23:16.856949 | followup.finished | application | completed，保留相同 thread/turn ID |

来源的完整字符串、全部 trigger/facts 和所有下载、扫描、身份、元数据记录见上面的 75 行原始 activity，不只包含这张生命周期表。

在线 Agent 还在可删除的实验 harness 中写入经验并自行提交 `07d4dd1`。这不是实现 worktree 的提交，但它确实发生了；实验 profile 删除后该 harness 也一并删除。后续重启回合追加了“不开发、不提交”的约束。zsh here-document 的临时路径被 lab 拒绝、未引用带空格路径的 cd 失败、错误 action 输入等原始失败均保留，没有放宽 sandbox 或修改种子步骤来让实验过关。

### 停机完成后重启

另一份独立 profile 的 Agent 也自行登记后续。初始轮 29.510 秒，于 14:17:53.575886 completed，之后下载仍在运行，没有保持回合等待。

14:18:02 退出 App PID 40113，保存的下载进度为 309,141 / 4,372,373，后续仍为 waiting。真实输出：

```json
{"pid":40113,"returncode":-15}
{"appStopped":true,"transport":"independent BT TCP client to the same local seed peer","sha256After":"b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254"}
```

内置下载器随应用退出而停止，因此实验用独立 BT TCP 客户端继续从同一 peer 完成同一个临时输出文件，逐块校验、写盘并 fsync，没有手写任务终态或回执。rqbit 的 fastresume 位图仅记得自身进程已经收到的 pieces；为验证应用停机期间完成的外部文件，在应用停止时将这一个临时 5 字节位图备份为 `.bitv.x25-backup`，让启动重新哈希校验。[实际 fixture 记录](evidence/x25/restart-fixture-recheck.json)。此条件不是生产下载器行为修改，也不把位图缓存未复查的问题说成已经解决。

14:21:38 从同一 profile 启动 App PID 40768。NextCore 根据恢复的真实下载校验结果满足终态条件；启动时短暂 ready，宿主成功后 resume 原线程并开启新轮。没有再发用户请求来唤醒：

```json
{
  "initial":"01a12b53-54ac-7772-b930-e73c9980b0cc",
  "followupThreads":["01a12b53-54ac-7772-b930-e73c9980b0cc"],
  "followupTurns":["01a12b57-37b7-7272-af63-d8271a077bbb"]
}
```

原登记者 session 是 `nipa-1791728243400860-deb1f799`；执行 session 是重启后的 `nipa-1791728498257278-bfef221f`。activity 同时保留了这两项事实，thread ID 没变。

Agent 在自动新轮完成索引和 Bangumi 绑定，随后持续截图、查询并阅读 Classic 源码，试图解释为什么 Classic 库没有显示。14:28:30 我通过 steer 追加范围约束：

```text
不用为了让 Classic 界面显示而开发或修改程序，也不要提交。只告诉我这次实际完成了哪些事，哪些还没有完成。
```

这次 steering 是在已经自动唤醒并完成 Next 写入之后，为阻止实验转成开发；[完整输入及 RPC 结果](evidence/x25/restart-steer.json)。它不是触发后续的手工请求。因此“重启自动同线程唤醒”已直接观察到，而“这一轮自主结束并完整汇报”有此次人工约束。14:29:07 回合 completed，总计 448.658 秒。最终实际回复：

```text
已完成：下载……校验通过；文件已登记进 Next 媒体库索引；身份识别与绑定……
未完成：Classic 界面的「本地媒体库」里看不到它……Bangumi 绑定不会投影到那里。
按你的要求，我没有为此改程序，也没有提交任何代码。
```

重启前后 seed peer servedBytes 没有增加，重启采用的是离线完成后的本地校验。44 行完整 activity 包含 registered → triggered → 启动期 pending → dispatching → 新 session started → finished，以及 Agent 的扫描、身份和快照事实。

### 不可用、终端默认线程、取消、忙回合和一次性

[controls.py](evidence/x25/controls.py) 使用另一临时真实实例，仍是 CPA/deepseek-v4.1-flash。

故意不准备 lab CODEX_HOME/config.toml，使宿主真实启动失败；经终端来源登记一个已经成功的真实空目录扫描：

```json
{
  "state":"ready",
  "threadId":null,
  "turnId":null,
  "origin":"harness_cli",
  "reason":"Bad state: Prepare provider configuration inside the lab CODEX_HOME."
}
```

补齐实验配置再启动，原记录自动执行，在活动 harness 新建线程 `01a12b5d-96bc-7bb1-a84a-a4d017fd886a`，开启 `01a12b5d-98a2-7dd0-983c-9f1cec61cba2`，最终 completed；没有重新登记。另登记 playback.started 后取消两次，只有一条 followup.cancelled 事件，重启仍 cancelled。显式无效线程保存 execution_failed 和 Codex 原因，没有伪造 turn ID。

忙回合实验：先让同一线程执行 20 秒 Python sleep，同时扫描新测试文件触发 library.file_added（没有 hook 程序）。14:29:04 后续真实输出：

```json
{"state":"ready","turnId":null,"reason":"Chat host has an active turn; waiting until idle."}
```

原轮 `01a12b5e-02f1-7041-af54-aae10e8b9e4d` 在 14:29:30 正常 completed 后，才开启后续轮 `01a12b5e-6cf8-72a2-bb46-a79a30e3f736`；没有 interrupt。再重启，两个已执行记录的 turn ID 与重启前完全相同，宿主没有选线程、没有新轮。完整 34 行 activity 在上述链接中。

补充实验也暴露并修复了一处实现错误：未收到首次输入的新 Codex 线程不能 includeTurns。真实错误：

```text
thread 01a12b58-30f0-7f32-86e9-3e52f54133c2 is not materialized yet;
includeTurns is unavailable before first user message
```

修正为宿主持有新建线程的空历史，首次 turn/start 后再查询服务端历史；明确 RPC 拒绝直接保存 execution_failed。失败记录在 [attempt2-failure](evidence/x25/controls-attempt2-failure.json)，修正前协议流在 [attempt2-chat](evidence/x25/controls-attempt2-chat.jsonl)。最初控制脚本还曾因 Python 条件表达式先引用未赋值局部变量而提前退出，修正后重跑；两次失败实验都经 finally 按自身 PID 退出并删除 profile，没有沿用失败结果作为最终验证。

### 检查与清理

Flutter 固定使用 `~/development/flutter-3.44.6`，所有 Flutter 命令带 --no-pub。初次缺 package_graph 和 macOS 派生 Swift Package，只读复制同 lock 的 sibling worktree 生成输入并重定位，没有解析依赖。构建使用 ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache；CocoaPods 对 Erika lock 的自动改写已恢复。

- 最终 macOS Debug 构建成功：[build.log](evidence/x25/build.log)。保留原有 native/脚本警告。
- 受影响代码与新约束测试 analyze：No issues found：[analyze.log](evidence/x25/analyze.log)。
- 新后续持久化/取消/失败与取消回执约束，加 v0–v9 迁移/旧数据保留，共 17 项通过：[constraints.log](evidence/x25/constraints.log)。
- 端点、hooks、桌面退出和 harness 回归通过；与旧迁移检查合跑共 23 项：[regression.log](evidence/x25/regression.log)。
- state.query 的来源、公开数据与只读约束 16 项通过：[state-regression.log](evidence/x25/state-regression.log)。初次因视图数 21→22 的旧断言失败，更新断言后重跑通过。
- 同一初次合跑中的 task engine / download runtime 17 项均通过：[完整首次日志](evidence/x25/constraints-first-attempt.log)；其中 state 断言失败没有影响这些已通过的约束。去重后的最终有效检查为 62 项。
- `git diff --check` 通过。最终 diff 没有 lock/依赖配置。

真实 App 都由各自 VM getVM.pid 与 subprocess PID 对照，按 PID 关闭；host close 等待 app-server 退出。在线、重启和控制实验共五个 profile（含失败尝试）均已删除，九次 App 启动对应 PID 均不存在：[cleanup.json](evidence/x25/cleanup.json)。复制的 auth/config/CA、下载文件、临时数据库与实验 harness 提交随 profile 删除；外部 fixture 的 `/tmp/nipa-next/x25` 也在导出证据后删除。只留下脱敏输出与本 worktree 构建产物。

Windows 沿用 X23 的明确宿主不可用错误，后续层保留 ready/原因；本次没有运行 Windows 实例，不声称已验证那里的对话可用性。这里验证的是任务/唤醒基础设施，不改变 Classic 对非弹弹play作品的显示能力。

## 4. 问题

需要主控决定的问题：没有。
