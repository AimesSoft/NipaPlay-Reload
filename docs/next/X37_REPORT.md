# X37：并行帮手、后台任务与结果后续

2026-10-12，Asia/Taipei。worktree `~/Desktop/nipaplay-next-wt/x37-helpers`，分支 `next/x37-helpers`。未 commit、push、pub get 或改依赖；未改用户 Codex 配置。构建全部在本 worktree，Flutter 3.44.6、--no-pub、指定 Erika 缓存；Debug 包签名及 entitlements 检查通过。没有启动安装版、使用应用名寻找进程、激活窗口、像素点击或触碰 ui-demo／主控实例。

## 1. 完成了什么

- 真实 Codex 0.144.1 stdio 协议证实同一 app-server 进程可并发运行不同线程的回合，事件带 threadId；steer、interrupt 按目标线程隔离。
- 新能力 `agent.helper {title,instruction,threadId?}`：立即返回 jobId、parentThreadId 和 helperLimit=2。帮手在相同 harness 的独立 Codex 线程里工作，不改变主会话／当前会话指针。说明中的目标、背景和交付物由调用者提供，宿主不分解任务或决定什么时候派帮手。
- 帮手复用持久任务引擎，进入 task.list/get/cancel 和 activity。有标题、状态、实际开始时间、当前短句、线程号、最终摘要。`agent.helper.report {currentActivity,jobId?}` 供正在运行的帮手更新短句。
- 每个帮手自动登记一个 X25/X31 的任务终态后续，成功、失败和取消都返回发起会话，忙时等候。来源为 `harness_cli:helper:<jobId>`；X33 保存同样来源的回合工作过程。
- 宿主按线程维护 liveness、秘密 delta 尾部和思考合并。`threadDisplay` 包含全部线程的显示事件；thread-local host/reasoning、host/liveness 有 params.threadId。原 `display` 保留前台线程的 host 更新，其他原生协议事件继续带 threadId，以兼容现有界面。原 `busy/liveness` 仍指当前前台会话，新增 busyFor/livenessFor/threadLiveness。
- 帮手 `ui.present` 原卡片在帮手自己的实际回合。结果后续派发时，卡片引用也幂等复制到发起会话的实际后续回合；状态仍实时解析。没有改 `lib/next/ui/`。
- 种子增加一条帮手事实，列出独立线程、共同 harness、取消、结果返回和并发上限，没有加入派发时机或分工策略。

能力与宿主细节见 [chat/README](../../lib/next/chat/README.md)，界面契约见 [ui_data/README](../../lib/next/ui_data/README.md)。NextCore 的改动仅为注册执行器、服务和能力；state/views 的改动仅为公开任务与后续中的帮手事实，不涉及 X35 的作品／图片或 X36 的工具文件。

## 2. 决策与契约

**一个 app-server，两个帮手名额，主会话不占名额。** 协议已支持并发，无需每个帮手另开进程。thread/start 的 config 覆盖该线程的 `shell_environment_policy.set.NIPAPLAY_CHAT=helper-<jobId>`，CLI 请求仍走同一端点，后端将来源分成 helper 与 chat。实际来源从协议回合与 CLI 头部记录，不解析命令猜来源。

**复用现有容量等待状态。** 额外任务按 createdAt 等待，底层为 waiting_retry、每两秒检查一次名额；UiTask 映射 queued。没有模型重试或自动决定业务下一步。主会话关闭窗口不影响帮手；关闭 Next／进程会终止模型宿主，重启读取原线程的实际回合状态。被中断的回合如实失败并返回，不另开回合重做外部操作。发出 turn/start 前持久记录 dispatch 意图；丢失应答时根据带 jobId 的用户项核对历史，找不到不重放。

**完成回合与完成业务分开记录。** 任务引擎要求 succeeded 有 verified 回执。帮手只验证其实际 Codex turn/completed；回执中的 resultVerification=unverified 明确表示最终回复没有证明业务目标完成。摘要上限 8192 字符，保留 threadId、turnId、turnStatus，秘密在落盘和对外发布前脱敏。文件与业务效果仍以对应领域回执为准。帮手共享同一个仓库、设置和业务事实，独立线程不提供文件编辑隔离或冲突锁。

`UiTask` 字段说明（新增字段均有兼容默认值）：

| 字段 | 含义 |
|---|---|
| taskId | 持久任务号，用于 task.get/cancel；不显示给观众 |
| title | 观众短标题；帮手直接使用调用者的 title，普通任务保留原投影 |
| state | queued/running/paused/finished/failed；容量等待是 queued；原兼容语义仍把取消归入 failed |
| kind | 新增 UiTaskKind.background（默认）／helper |
| startedAt | 新增 UTC 开始时间；帮手进入线程时记录，尚未开始或没有该事实时 null |
| currentActivity | 新增正在做什么的一句短话；可由帮手 report 更新，未报告时是宿主状态，普通任务可为 null |
| summary | 新增结束回执摘要；尚未结束或没有摘要时 null，不作为业务成功证明 |
| threadId | 新增帮手线程号，供界面打开对话；尚未建立或普通任务为 null |
| parentThreadId | 新增结果返回的发起线程号；普通任务为 null |
| cancelled | 新增确实取消的事实，默认 false，用于区分取消与错误 |
| artwork | 原关联作品图片，无关联或缓存时 null |
| progress | 原 0–1 可核实进度，未知 null；帮手始终 null，包括完成之后 |
| remaining | 原可靠剩余时长，否则 null |

## 3. 实验与真实输出

### 协议并发

[x37_protocol.py](../../scripts/next/x37_protocol.py) 使用无凭据回环 Responses provider 暂停两个请求，观察的仍是真实 Codex 进程及 JSON-RPC，不宣称调用了真实模型。[全部收发](evidence/x37/protocol.jsonl)、[摘要](evidence/x37/protocol-summary.json)。app-server PID=68572，同一进程在 provider 释放前已发出两次请求，相差约 0.5ms。两次 turn/start 原返回：

```json
{"id":4,"result":{"turn":{"id":"01a12ed7-1a25-7823-8e09-e1dca9f4bdab","items":[],"itemsView":"notLoaded","status":"inProgress","error":null,"startedAt":null,"completedAt":null,"durationMs":null}}}
{"id":5,"result":{"turn":{"id":"01a12ed7-1a25-7823-8e09-e1e464a4f72c","items":[],"itemsView":"notLoaded","status":"inProgress","error":null,"startedAt":null,"completedAt":null,"durationMs":null}}}
```

A 的 threadId=`01a12ed7-1a16-7181-b178-7f588f967ede`，B=`01a12ed7-1a21-7ba3-a75a-5dec473500e0`。先 steer A，再 interrupt A，A 收到自己的 turn/completed/status=interrupted。随后 B 的 steer 仍返回自己的 turnId：

```json
{"id":7,"result":{}}
{"method":"turn/completed","params":{"threadId":"01a12ed7-1a16-7181-b178-7f588f967ede","turn":{"id":"01a12ed7-1a25-7823-8e09-e1dca9f4bdab","items":[],"itemsView":"notLoaded","status":"interrupted","error":null,"startedAt":1791787211,"completedAt":1791787211,"durationMs":104}}}
{"id":8,"result":{"turnId":"01a12ed7-1a25-7823-8e09-e1e464a4f72c"}}
{"error":{"code":-32600,"message":"expected active turn id `01a12ed7-1a25-7823-8e09-e1dca9f4bdab` but found `01a12ed7-1a25-7823-8e09-e1e464a4f72c`"},"id":9}
```

最后单独 interrupt B，B 才收到自己的 interrupted。探针退出并删除自身临时 CODEX_HOME；没有改 ~/.codex。

### 容量、取消、忙时后续与卡片（无凭据模型控制）

[控制时间线](evidence/x37/controls/timeline.json)、[真实协议事件](evidence/x37/controls/chat.jsonl.gz)。模型为回环 fixture，命令、任务、app-server 和端点是真实执行；这部分不作为 DeepSeek 自主行为证据。

| 时间（UTC+8） | 实际观察 |
|---|---|
| 14:55:47 | 受理四个帮手 |
| 14:55:50 | 两个 running、有独立 threadId；另外两个 waiting_retry、尚无线程 |
| 14:55:50 | 主线程成功启动自己的回合；取消第三个排队任务 |
| 14:55:54 | 第一个帮手 succeeded，主线程仍 inProgress，后续 ready/“Chat host has an active turn; waiting until idle.”；随后取消第二个运行中的帮手 |
| 14:56:16 | 最终状态 succeeded/cancelled/cancelled/succeeded，第四个取得释放的名额；四个后续都 completed，目标同一发起线程 |

运行中取消只给第二个帮手发 turn/interrupt；第三个取消任务没有线程、没有 turn/start。主线程的 liveness 在帮手完成时保持 inProgress、eventCount=6；两个帮手的状态和计数分别更新，没有被助手的结束覆盖。

ui_presentations 的真实查询有三条 helper 原卡片和三条主会话结果卡片，后者的 turn_id 对应各自实际 followup turn。已取消且未启动的任务没有制造卡片。三份 chat.turn.process 都 found=true，origin 为各自 `harness_cli:helper:<jobId>`，命令事实含独立 helper 环境以及 ./nipa 的调用。该控制的主线程 sleep 命令末尾有实验脚本引号错误，sleep 仍执行、之后退出非零；并行和后续等待观察来自实际回合状态，不把这个命令宣称成功。脚本已修正，未为这处末尾输出重跑整套控制。

### 当前短句与重启对账（只补测受影响部分）

[重启时间线](evidence/x37/recovery/timeline.json)、[事件](evidence/x37/recovery/chat.jsonl)。15:00:26 实际 task.list 返回 currentActivity=`正在整理弹幕`、phase=working，保留线程和开始时间。随后按本实例 PID=50383 关闭，重启同一临时 profile。

15:00:29 同一个 jobId、threadId、turnId 返回 failed，回执 turnStatus=interrupted、summary=`帮手这一轮未能完成`。帮手历史只有原来的一轮，没有重放命令；原自动后续仅一条、completed，主会话标识保持 `01a12ee9-9161-7462-be71-5726896c5ba6`。

### 真实 DeepSeek 弹幕与并行问答

真实实例 PID=35307，CODEX_HOME 在临时 profile，用户配置只读复制、模型改为 deepseek-v4.1-flash，复制公共 CA 并设置 CODEX_CA_CERTIFICATE/SSL_CERT_FILE 和 provider/localhost 的 NO_PROXY。没有在生产改变模型或代理。根目录只读使用 `/Volumes/Media/躲在超市后门抽烟的两人`，实际有九个 MP4；没有写、改名、删除、整部复制、寻找 SMB 账号或重新挂载。

[真实时间线](evidence/x37/real/timeline.json)、[原始脱敏事件](evidence/x37/real/chat.jsonl.gz)、[中途工作过程](evidence/x37/real/helper-process-in-progress.json)。主线程 `01a12ee2-6e65-7920-83a5-0a5a17167434`，帮手线程 `01a12ee5-beef-7352-b5b8-23bad06567df`，jobId=`job-79dc3119c1fa5e06ec227938800e3abd`。

| 时间（UTC+8） | 实际观察 |
|---|---|
| 14:52:34 | 用户原话“把《躲在超市后门抽烟的两人》的弹幕都补上” |
| 14:54:15 | 原轮仍在目录／能力查询，未派帮手；同轮 steer：“把这件事交给帮手继续做。我想继续聊别的。” |
| 14:56:13 | 帮手开始独立回合，主轮稍后结束 |
| 14:56:28 | 帮手 running 时主会话启动“BT 下载里的做种是什么意思？用两句话告诉我。” |
| 14:56:36 | 主会话回答完毕，帮手仍 running，未被主轮结束影响 |

主会话实际回复：

```text
已经交给帮手了（后台跑着，完成或卡住会把结果带回这条对话）。
```

另一问题的实际回复：

```text
做种就是把已经下载完的文件继续留在下载器里挂着，把自己手里的数据上传给其他还在下载的人。BT 本来就是靠所有人互相上传才跑得起来的，你下载时用了别人的带宽，下完继续做种就是把这个接力还回去——做种的人越多，大家下得越快，代价只是占一点上传带宽和硬盘空间。
```

这证明了并行问答；原话没有自行触发派发，后来明确要求交给帮手。因此不声称原话就足以触发自主分工。宿主没有加派发策略。后续还有一次只用于约束边界的 steer 和一次停止扩大候选搜索、要求交回实际导入数的 steer，两者均原样保留在 [constraint-steer](evidence/x37/real/constraint-steer.jsonl) 与 [completion-steer](evidence/x37/real/completion-steer.jsonl)。

本实验最终导入发生在 **15:08（UTC+8）**，协议内是 07:08Z。[导入汇总](evidence/x37/real/import-summary.json) 从真实 completed 命令输出提取：

| 集 | 导入返回条数 |
|---|---:|
| 1 | 228 |
| 2 | 125 |
| 3 | 134 |
| 4 | 109 |
| 5 | 111 |
| 6 | 172 |
| 7 | 116 |
| 8 | 181 |
| 9 | 233 |
| 合计 | 1409 |

来源为公开 Bilibili 视频 `BV1HBpw6vEZH` 的 p1–p9，每集 `comment.bilibili.com/<cid>.xml`；它用自己在临时 harness 写的脚本取得 XML，再调用已有 danmaku.import，没有新增后端平台客户端。第一集相对路径导入失败，绝对路径成功；其余八集批量命令退出码为 0，各自有成功 count。最后一次 danmaku.tracks 返回九集都有 enabled=true、platform=bilibili、对应 p1–p9 的轨道；该输出的 count 为 None，不能用它再次验证条数。条数依据是各次导入返回。

15:08:36 驱动达到派发之后的 12 分钟观察期限，此时帮手正完成轨道核对，未收到其最终回复。驱动关闭并删除临时 profile，所以原长任务没有观察到回主会话。没有把九条导入回执等同于帮手回合已经 completed，也没有重跑原话、搜索或导入。临时实验产物已随 profile 删除，不是用户片库的一次持久修改。

只补结果交付：另一真实 DeepSeek 实例 PID=88336 让帮手只读上述保留记录，计算每集和总条数，不做业务操作。[交付部分时间线](evidence/x37/real-delivery/timeline.json)、[真实事件](evidence/x37/real-delivery/chat.jsonl.gz)。15:13:14 帮手 succeeded，输出每集条数与合计 1409，并明确 count=None 不能复核导入条数；主原轮仍忙，结束后自动 followup 的 turn/start 已返回 inProgress，threadId 是发起主会话。驱动紧接着尝试发送另一问题，与这个自动后续竞争，Debug turn 返回“Use steer for an active turn”；驱动因把它当异常而退出，没有捕获该后续的最终回答。这个错误来自实验驱动未给忙时新消息排队，不是帮手阻塞主会话。驱动已改为让这类新消息等待活动后续结束；未重做已成功的核对。

最后仅补“把已经核对的真实结果整理成观众短句，再完成自动后续”的子任务，不再核对记录或修改业务状态。[结果返回时间线](evidence/x37/real-return/timeline.json)、[真实协议](evidence/x37/real-return/chat.jsonl.gz)。实例 PID=90798，模型实际返回 deepseek-v4.1-flash/cpa。15:15:40 提出这个独立的结果整理子任务；15:17:31 自动后续已 completed，返回线程为发起主会话 `01a12ef7-8efb-71d0-aeda-31d97a9f23d7`，回合为 `01a12ef9-0589-7d13-94f9-69e0632203ab`。帮手的线程为 `01a12ef8-aa82-7172-9103-8d38fc7f58c0`，task 与 X33 process 都为 completed，实际来源 `harness_cli:helper:job-d409002464b5077fea4b297574b84b94`。

主会话真实收到后续并回复：

```text
帮手已结束，整理好的两句话是：

九集弹幕一共整理好 1409 条。其中第1集 228 条，第2集 125 条，第3集 134 条，第4集 109 条，第5集 111 条，第6集 172 条，第7集 116 条，第8集 181 条，第9集 233 条。

数字与 completed-result.json 中已核对的结果一致，未做任何业务状态改动。
```

这里的模型输入明确给出上一真实帮手已核对的结果，证明的是实际自动后续交付和主会话回应；不把这轮声称为重新完成了九集弹幕，不把三个观察拼成同一连续线程的成功闭环。

### 意外、约束偏离与检查

- 第一次控制就绪条件仅看 threadId，早于 Followups.attach，因此 agent.helper 返回 host unavailable；没有开始模型任务。改为实际 model/mainThreadId 就绪。[失败与清理](evidence/x37/initial-controls-startup/experiment.log)。真实观察的初始 launch 快照也早于头部完成，但 turn 请求经串行控制等待会话创建后正常启动，没有重跑它。
- 第一轮控制脚本误读任务公开返回中的 checkpoint（该字段仅在存储中），等待条件没有满足；同时暴露 unverified receipt 不能 succeeded。更正为公开 threadId 和回合完成验证。[保留的失败](evidence/x37/initial-receipt-controls/experiment.log)。后来的四任务控制只在修复后执行一次。
- 第一次 UiTask 新约束同样发现回执验证要求；改正后该文件六项通过。控制发现 scalar 直接交给 publicHarnessFacts 会成为 null，已改为对象字段投影；仅补测当前短句与重启，没有再跑四任务控制。
- 真实模型执行过 `ls ~/.config/nipaplay/`，输出一个 endpoint.json 文件名。这是对真实连接目录的元数据枚举，偏离“不读真实数据目录”的约束。观察到的轨迹没有读取该文件内容；发现后立即向帮手追加明确限制，禁止真实目录、钥匙串、登录态和登录窗口。没有隐藏这项偏离，也不把实验称作完全零读取。实验 ./nipa 实际通过临时 profile 的 lab-profile.json 连到本实验端点。
- 同一真实线程观察期间两次 Dart VM 热更新，只修正回执验证、短句投影和线程显示兼容性；没有重跑原话、重建模型线程或改它的业务产物。[第一次](evidence/x37/real/hot-reload.json)、[第二次](evidence/x37/real/hot-reload-final.json)。
- 代码检查补上了按 harness 筛选容量等待队列，避免已停用 harness 的旧帮手阻塞新 harness；仍只运行当前 harness 的线程。相关约束文件补测通过：[harness-queue-constraints](evidence/x37/harness-queue-constraints.log)。未重复全量或真实搜索／导入。
- RPC 回复自身没有 threadId；宿主按发出请求时的目标线程关联其活性与 error，避免把一个线程的 RPC 错误记到另一个线程。最终相关 analyze 与构建均通过，没有因此重跑业务实验。
- 相关约束最终 14 项通过：[final-related](evidence/x37/final-related.log)；X33 原过程／Classic 路由两项通过：[process-tests](evidence/x37/process-tests.log)。全量 test/next 加 desktop_exit_handler **只跑一次：442 项通过、4 项跳过**：[full-next](evidence/x37/full-next.log.gz)。之后容量等待恢复 running 的小修正仅跑相关文件。
- 最终 analyze 无 error/warning，保留八项花括号风格 info：[analyze](evidence/x37/analyze-delivery.log)，其中宿主最后检查四项 info：[chat analyze](evidence/x37/analyze-chat-final.log)。最后构建成功：[build](evidence/x37/build-rpc-liveness.log)；codesign verify --deep --strict 通过，无 app-sandbox、保留 allow-jit：[entitlements](evidence/x37/entitlements.log)。CocoaPods 对 Erika Podfile.lock 的自动变化已恢复，GeneratedPluginRegistrant 的已有生成变化按任务约定保留。git diff --check 通过。
- 全部实验按各自 VM service 返回的 PID 关闭并复查；对应临时目录已删除。[清理汇总](evidence/x37/cleanup.json) 列出原始失败、控制、重启、长任务和两个结果交付实例。各驱动不保留 auth/config、端点文件、原始应用日志或私有 VM 地址；只保留宿主脱敏流和公开能力输出。已检查当前实验端点凭据不在证据中。后台原生插件警告没有在本任务修复。后端实验没有截图需求，因此未制造界面截图。

## 4. 还缺什么与问题

界面主控需要使用 UiTask.kind/threadId/parentThreadId/currentActivity/summary/cancelled 接上后台入口、帮手对话打开和取消；本 worktree 没有改进度环或界面。全部线程事件可用 threadDisplay，现有显示适配保持兼容。Windows 延续 X23 的明确宿主不可用事实；没有做 Windows 运行实验。没有做大规模多层帮手压力实验。

原九集长任务在观察期限前完成导入，但没有走到其自身结果后续；真实结果核对与返回通过仅补交付的独立子任务完成。原话没有自行触发派帮手；明确的用户补充指令后才派发。视频与整段弹幕的时轴匹配由观察 Agent 根据元数据和时间戳判断，本轮没有播放／画面对照验证。真实目录枚举偏离如上记录。

需要主控决定的问题：**没有**。
