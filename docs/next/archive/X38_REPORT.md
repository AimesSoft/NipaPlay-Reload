# X38：Codex 原生子代理成为后台帮手

2026-10-12；worktree `x38-native-helpers`，分支 `next/x38-native-helpers`。未 commit、未 push。

## 1. 完成了什么

- 用无凭据回环 Responses 服务驱动 **真实 Codex CLI 0.144.1 app-server**，取得 spawn/send/wait/close/resume、子回合生命周期、interrupt 和 thread/list 的真实协议。模型输出是实验夹具，app-server 与事件不是模拟。
- `Helpers` 接纳原生 `spawnAgent` 的 receiver threads，复用 X37 的任务引擎、回执和 X25/X31 的持久后续。宿主不再为原生子代理另开一个执行回合。
- 原生任务出现在 `tasks()`：`kind=helper`、child `threadId`、`parentThreadId`、短标题、实际 `startedAt`、最新活动、最后回答、取消状态。增加可选 `source`，值为 `codexNative` 或 `host`，既有字段含义不变。内部持久任务类型仍是 `agent.helper`。
- `task.cancel` 对原生任务调用子回合的 `turn/interrupt`，确认实际 interrupted 后写取消回执。接纳时标记 `sideEffectCommitted=true`，不能把已在跑的 queued 任务直接报成取消成功。
- 成功结果保存完整最后回答，不套用宿主帮手原有的摘要长度截断。父忙时结果排队，空闲后回到原父会话；不切换用户当前会话。
- 父 `wait` 实际取得这个子回合的成功回答后，持久取消尚未派发的后续并保存 `consumedBy`。超时/运行中状态不是取走。派发前重新核对父历史，补偿事件与回执落盘时序。
- 同一个原生 child 接收新输入产生新回合时，为该回合建新任务与回执，不覆盖上一轮结果。启动时显式列出子线程，恢复接纳，不重新派活。
- 未修改 `lib/next/ui/`，未改依赖、Classic 行为或 X35 媒体实现。`UiTask.source` 是给主控界面消费的可选增量。

核心代码：`lib/next/chat/native_helpers.dart`；契约说明：`lib/next/chat/README.md`、`lib/next/ui_data/README.md`。

## 2. 决策

### 两套能力：保留宿主派发，改公开名称

公开 Action 从 `agent.helper` / `agent.helper.report` 改为 **`agent.dispatch` / `agent.dispatch.report`**，不保留同义 delegation alias。

原生工具依附一个正在执行的模型回合；脚本、hooks 或外部调用在没有父模型回合时仍需要启动独立回合。`dispatch/` 实验证明这种能力确实可用，因此不能删除宿主执行器。改名把它描述为宿主派发，而非第二套原生子代理工具。宿主派发仍有 X37 的两个并发名额；原生并发由 Codex 控制。

内部 `agent.helper` job type 不改名，不迁移或重写历史任务。已有 harness 不会被新种子覆盖；维护其脚本时须把旧 Action 名改为 `agent.dispatch`，历史任务查询依然使用 `type=agent.helper`。

首次真实 DeepSeek 实验自然选择了旧宿主 Action，这也是改公开名称的实际依据。改名后父回合自然使用原生 spawn，但子代理仍选择了宿主 dispatch：**改名并不能保证模型不再次转派**。没有添加选择规则、禁止转派或“什么时候应该派”的提示。

### 标题、进度与来源

标题取 prompt 的首短句，限制 48 个 UTF-16 字符；不把 Codex 昵称当成任务说明。`currentActivity` 取最新助手短句（160 字符）；命令完成阶段用“帮手正在查询和整理”。最终完整回答保存在回执，UI 的 `summary` 沿用 X37 投影。

原生任务、后续和 retained turn process 来源是 `codex_native:<child>`。但 Codex 的子 shell 继承父 `NIPAPLAY_CHAT` 环境；个别 `nipa` CLI 调用仍记录父 CLI origin。未通过猜测命令来改写来源。因此 **原生子代理的卡片/CLI invocation 独立归属不在本次承诺内**；宿主派发的既有独立归属不变。

### 回执与恢复

verified 只表示 Codex 回合确实完成，不证明模型结论正确；原生回执另有 `resultVerification=unverified`。失败和中断如实交回状态，不用假结果代替。wait 去重目前针对 `agentsStates[child].status=completed` 且有回答的成功结果；没有把失败状态消息假设为同一份回答。

`closeAgent` 不是“父通过 wait 取走结果”的证据，即使它返回之前 completed 状态及 message，也不据此消费后续。取消某一轮任务不能停止 child 后来另一个回合。

## 3. 协议调研：真实输出

脚本：`scripts/next/x38_protocol.py`。原始 wire：[`evidence/x38/protocol.jsonl`](evidence/x38/protocol.jsonl)；模型工具 schema：[`model-tools.json`](evidence/x38/model-tools.json)；模型输出：[`model-outputs.json`](evidence/x38/model-outputs.json)；派生观察：[`protocol-summary.json`](evidence/x38/protocol-summary.json)。本节只描述该版本实测，不推广为所有 Codex 版本的保证。

工具位于 `multi_agent_v1` namespace。Responses function_call 要分别传 `name` 和 `namespace`，不是 dotted name。

| 模型工具 | 实测参数 | app-server item.tool | 实测 agentsStates |
|---|---|---|---|
| spawn_agent | message、agent_type；schema 另有 model 等可选项 | spawnAgent | pendingInit / message:null |
| send_input | target、message（schema 另有 interrupt） | sendInput | interrupted / message:null（前一轮已被 interrupt） |
| wait_agent | targets、timeout_ms | wait | completed / 完整结果 |
| close_agent | target | closeAgent | 返回关闭前 completed / 完整结果 |
| resume_agent | id | resumeAgent | pendingInit / message:null |

真实 `item/completed` 的 spawn item（原样摘取，未把 pendingInit 写成 running）：

```json
{"type":"collabAgentToolCall","id":"call_0","tool":"spawnAgent","status":"completed","senderThreadId":"01a12f1b-e239-7160-80f0-4c67177edf81","receiverThreadIds":["01a12f1b-e24f-7f63-97ae-d61b5a565c01"],"prompt":"CHILD:HOLD","model":"probe","reasoningEffort":"medium","agentsStates":{"01a12f1b-e24f-7f63-97ae-d61b5a565c01":{"status":"pendingInit","message":null}}}
```

同一 child 被 wait 取到的真实 item：

```json
{"type":"collabAgentToolCall","id":"call_5","tool":"wait","status":"completed","senderThreadId":"01a12f1b-e239-7160-80f0-4c67177edf81","receiverThreadIds":["01a12f1b-e24f-7f63-97ae-d61b5a565c01"],"prompt":null,"model":null,"reasoningEffort":null,"agentsStates":{"01a12f1b-e24f-7f63-97ae-d61b5a565c01":{"status":"completed","message":"已完成只读检查，17 条。"}}}
```

五种条目共享 `type/id/tool/status/senderThreadId/receiverThreadIds/prompt/model/reasoningEffort/agentsStates`；sendInput 有 prompt，wait/close/resume 的这些可选内容为 null。外层 params 还带父 `threadId`、父 `turnId`、`completedAtMs`。开始和完成条目分别在 `item/started` / `item/completed`；状态不能仅凭 tool call 已完成来推断。

### 生命周期、终止与线程发现

- spawn 返回 pendingInit，**child 的 turn/started 在后面才到**。空 rollout 尚未落盘时不能立即 read child history。
- 实验先等真实 child turn ID，再发送 `turn/interrupt {threadId,turnId}`。RPC 返回 `{}`，随后 child `turn/completed.status=interrupted`。
- 默认 `thread/list` 实测只列交互父线程。加 `sourceKinds:["subAgentThreadSpawn"]` 才列 child。
- child 有 `parentThreadId`、`agentNickname`、`agentRole`；source 为 `{"subAgent":{"thread_spawn":{"parent_thread_id":…, "depth":1,"agent_path":null,"agent_nickname":"Halley","agent_role":"default"}}}`。不能靠 preview 或名字判断关系。
- 最后一个 child 在父已结束后完成，观察两秒，没有收到父线程的新事件/回合。Codex 没有自动把结果送回空闲父会话；需要宿主后续机制。
- 原始派生统计误把主动 **sent thread/read** 算进父事件；本次核对后按 received 过滤修正 `parentEventsAfterChildRelease=[]`。原始 wire 保留，没有重跑同一协议实验。

## 4. 实验与意外

实验均运行本 worktree Debug 可执行文件，ad-hoc runtime 签名与 strict verify；没有启动安装版。配置从 demo 复制；SQLite 使用只读 backup，不复制 live WAL；独立 CODEX_HOME、公有 CA 副本、回环 NO_PROXY。模型实测为 `deepseek-v4.1-flash`。默认 quiet，没有激活窗口或像素点击；未写 SMB。

### 可控回环模型 + 真实应用

| 证据目录 | 实际观察 |
|---|---|
| [`controls/`](evidence/x38/controls/) | 父结束而 child running；父另一个回合 busy 时 child 完成，后续 ready 排队；父空闲后 completed；第二帮手 task.cancel 后 child interrupted、任务 cancelled。 |
| [`wait/`](evidence/x38/wait/) | spawn + wait 成功取结果；任务 succeeded，后续 cancelled 且保存 consumedBy；父只有一个回合，没有重复交回。 |
| [`timeout/`](evidence/x38/timeout/) | wait 超时没有消费；child 后来完成，结果照常回父。 |
| [`dispatch/`](evidence/x38/dispatch/) | 父没有活动回合，脚本 agent.dispatch 启动宿主任务，完成后通过后续交回。 |
| [`recovery/`](evidence/x38/recovery/) | 活动帮手期间 close host、按 PID 退出，再开同临时配置；同 job 恢复为 failed / interrupted，终态后续交回一次，未重派。关闭 app-server 不保证模型工作继续，恢复不是续跑承诺。 |
| [`reuse/`](evidence/x38/reuse/) | 同 child 两个独立 turn；两份 succeeded 回执分别为“已完成只读检查，17 条。”和“第二次只读检查，23 条。”；两份后续 completed，第一份未重写。 |

首次接纳在 pendingInit 读空 rollout 失败，保存于 [`initial-pending-init/`](evidence/x38/initial-pending-init/)，之后改为等 child 实际开始。复用回合首次实验在 pendingInit 就 sendInput，Codex 把两个输入合进同一个 turn，只有最后回答，等待“两个任务”的实验断言超时；保存于 [`initial-reuse-coalesced/`](evidence/x38/initial-reuse-coalesced/)。修正的是实验：第一回合实际完成后才发第二输入。不能把同回合两条 assistant message 伪称两个任务。

### 真实 DeepSeek：确认机制，不夸大任务完成

原话：“派个帮手去把这部每一集的弹幕情况查一遍（每集有没有、多少条），查完告诉我。你这边先别等它。” 当前作品事实是《莉可丽丝：友谊是时间的窃贼》六集。

1. **改名以前**，模型选择宿主 helper；[`initial-host-choice/initial-choice.json`](evidence/x38/initial-host-choice/initial-choice.json) 保存 succeeded 任务及完整六集表格。结论是实时 `danmaku.tracks` 六集均空、每集 0 条；它只能说明复制片库当前的轨道，不证明外部弹幕服务没有弹幕。这不是原生子代理的完成证据。
2. **改名以后**，[`deepseek/timeline.json`](evidence/x38/deepseek/timeline.json) 与 [`activity.jsonl`](evidence/x38/deepseek/activity.jsonl) 证明父实际原生 spawn：child `01a12f33-18b1-77f1-9691-46d588b6d420`，父 `01a12f2f-ef27-7420-891d-923e011bd067`，task source=codexNative。
3. 台北时间 **16:20:45** 父 completed，child 到 **16:22:21** 才 completed。16:21:29 采样同时显示父 completed、helper running、currentActivity=“帮手正在查询和整理”。主对话并未等 child；父自身首轮耗时约 211 秒，不等于响应很快。
4. 原生 child 最后回答是“已经派了一个独立帮手去做这件只读盘点……我这边不等待”。它实际又调用了宿主 dispatch。**这份真实回答没有丢**：终态后续在 16:22:21 开父回合，16:22:57 父回应指出“它没有自己做，而是又转手给了第二个帮手”，并确认下级宿主任务还在跑。
5. 另派一个原生帮手，16:23:11 发 `task.cancel`；约 0.57 秒后子回合 interrupted，任务 cancelled，回执带 afterCommit=true。[`deepseek/chat.jsonl.gz`](evidence/x38/deepseek/chat.jsonl.gz) 保存实际事件。
6. 上游中断后，核对已记录 PID 63646 确认退出，归档剩余日志并删除临时 profile。没有重复跑同一句真实实验。**没有观察到转派宿主任务的最终表格回到父，也没有记录真实取消后续的最终父回答**；不能把可控实验的成功表格或第一次宿主表格冒充这次结果。

本次真实实验确认原生帮手可见、活动更新、父不等、原生最后回答持久回父和 task.cancel 真正停止。模型是否自己完成原任务是另一事实；这次它没有完成，基础设施没有替它选择策略。这里是实验验收的剩余限制，而非“全部真实目标已满足”。

各实验目录 `cleanup.json` 记录自己 PID 与 profile 删除状态。没有截图：本次只验后端状态/协议，不宣称观察了尚由主控实现的后台面板。

## 5. 验证与交付边界

- 唯一一次完整测试：`flutter test --no-pub test/next test/desktop_exit_handler_test.dart test/lab_profile_test.dart`，按 TEAM 的 lockf 与无代理环境排队，**448 passed / 4 skipped**。日志：[`full-next-test.log.gz`](evidence/x38/full-next-test.log.gz)。没有第二次全量。
- 新增数据约束断言：adopted 外部副作用不可直接 queued-cancel；wait 消费幂等且重开持久，不改任务回执；UiTask 保留 helper 字段并投影 source。初次相关 run 的测试自身误等 entered 而非 recovered，修正后通过，完整测试包含修正。
- 最后相关 analyze 无 error/warning；既有 curly-braces infos 没有扩大范围修。日志：[`analyze.log.gz`](evidence/x38/analyze.log.gz)。worktree build 成功：[`build.log.gz`](evidence/x38/build.log.gz)。最后修饰性加括号不改逻辑。
- 构建自动改动 Podfile.lock 的 Erika 版本/checksum 已恢复；不改生成的 GeneratedPluginRegistrant.swift。最终 diff --check 通过，未 commit/push。
- 尚未验证：真实原生子代理直接产出六集完整表格并回父；失败 wait 的消息消费；原生 CLI/卡片独立来源归属；多层原生转派压力。已明确记录，不以单元测试替代真实观察。

## 6. 需要主控决定的问题

**没有。** 保留并改名宿主派发属于本任务明确授权的实现决策；本次缺少的真实最终表格是实验限制，不需要通过增加 Agent 选择规则来掩盖。主控可据上述边界验收，并接入可选 `UiTask.source` 展示来源。
