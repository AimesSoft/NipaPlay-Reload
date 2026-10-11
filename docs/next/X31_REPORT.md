# X31：主会话、定时脚本和统一唤醒

2026-10-12，worktree `x31-sessions`，分支 `next/x31-sessions`。未 commit、push、解析依赖或修改用户 Codex 配置。没有启动正式应用、操作登录钥匙串、激活窗口或触碰 `ui-demo`。实验使用本 worktree 的 Debug 可执行文件、临时 NIPAPLAY_PROFILE、独立 CODEX_HOME、公共 CA 副本、NO_PROXY 和 `deepseek-v4.1-flash`。

## 1. 完成了什么

- 按 harness 绝对路径持久保存主会话和当前会话标识，启动恢复主会话；对话历史与上下文压缩继续由 Codex 管理。数据库 v11 → v12 只追加 `harness_sessions` 和 `harness_discoveries`，不改旧数据。
- `ChatHost` 提供 `getMainSession`、`newConversation`、`listSessions`（isMain/isCurrent、分页）和 `switchSession`。`ChatPort` 对应提供 mainThread/newThread/listThreads/switchThread；首页输入、⌘K、头像所用的 Conversation 默认取得主会话。没有新增会话选择器的视觉设计。
- 对应 Actions 为 `chat.session.main/new/list/switch`。X25 的无会话号终端后续默认返回活动 harness 的主会话；嵌入对话中的后续仍保存登记所在的线程，包括明确新开的对话。
- `hooks/schedules.json` 支持正整数 everySeconds 或本机日历时间 dailyAt（HH:mm）。运行时读取声明，修改自动生效；停机、关闭 Next、切换 harness 后不补跑错过的时点。同一项仍在运行时跳过新一次。
- 定时程序复用 `harness.hook` 任务：退出码、耗时、超时、脱敏输出末尾保存在回执中；任务及回执进入 activity，关联 jobId，可用 task.get 取得输出。上次运行时间来自持久任务事件，不是查询时间。
- `agent.wake` 接受 instruction/facts 和可选 threadId，默认主会话；复用 X25 的持久一次性派发、忙时排队、回执丢失时查历史的逻辑，不 interrupt。`activity.report` 接受 title/source/facts，记录真实调用来源和 invocationId，不自动唤醒；没有追番专用结构。
- 种子 AGENTS.md 与 hooks/README 补上上述事实和巡查建议，去掉“开始会话先做什么”等步骤。脚本的来源、频率和判断策略仍由 Agent 写在自己的 harness。

接口说明见 [chat/README](../../lib/next/chat/README.md) 和 [hooks/README](../../assets/next/harness/hooks/README.md)。

## 2. 决策

1. **复用 X25 队列。** 即时脚本唤醒是 ready 状态的后续，facts 是触发事实；任务/事件后续仍从 waiting 变 ready。两者共用派发、取消、重启恢复及真实线程/回合记录，没有另一套会话执行器。
2. **持久会话标识，启动选主会话。** 当前选择也保存为事实，但重启默认恢复 main；明确选别的会话不改变 main。主会话缺失或 Codex 拒绝恢复时保留原标识并报告错误，不替换成新线程。宿主忙时会话选择返回忙状态或错误，后台唤醒排队。
3. **先让空 Codex 线程落盘，再保存标识。** Codex 0.144.1 的 thread/start 不立即写空 rollout；thread/name/set 会写盘。因此新线程设置普通会话名称后才保存 ID，不发送虚构用户消息、不启动模型回合。恢复的空线程也保留空历史缓存，避免首次消息前 includeTurns 的协议限制。
4. **定时脚本上限 15 分钟。** 给网络巡查和文件准备留出比事件 hook 的 60 秒更宽的运行窗口，仍有有限回执。间隔从声明被读取时算起；每次到期从当前时间计算下次。延迟超过调度容差的旧时点直接跳过，不排成补跑队列。这里只执行时间声明，不判断检查内容或何时值得唤醒。
5. **配置留在 harness。** 不做宿主替 Agent 设频率的 Action；Agent 可直接维护 schedules.json。无效声明不执行程序，同一份无效内容只报告一次 activity 发现。进程世代标识跨重启不同，旧排队 hook 也不会误执行。
6. **来源与秘密分开。** 发现和唤醒事实保留公共来源 URL 的身份，移除 URL 用户信息、查询和 fragment；秘密字段及已知凭据脱敏。脚本回执继续使用 X23/X25 的输出脱敏。source 是调用者给出的证据来源，origin 是宿主记录的实际调用方。

## 3. 实验与真实输出

实验驱动为 [x31_experiment.py](../../scripts/next/x31_experiment.py)，只走 Debug lab VM 扩展和真实 harness 端点。失败部分修正后只补测该部分；没有重复完整行为观察或整套控制实验。

### DeepSeek 自主巡查观察

用户原话只有：

```text
《星港来信》以后有更新就帮我准备好
```

虚构作品的唯一来源是本机 ThreadingHTTPServer 的模拟 RSS，最初没有 item，只能发布测试文本附件，不是真实视频或种子。来源是实验 AGENTS.md 的环境事实，未给脚本、频率或唤醒方式的提示；没有访问真实种子站。

首次配置有时序错误：我在宿主创建主会话之后才追加来源事实，而 Codex 创建线程时已经读取 AGENTS.md。实验 rollout 中没有这段事实。6 分钟窗口内该轮没有结束，驱动按自己的期限关闭实例；保留了 [原始轨迹](evidence/x31/chat.jsonl.gz.gz.gz) 和 [退出记录](evidence/x31/experiment.log)。这是实验配置失败，不能用于判断 Agent 是否会利用一个已知 RSS 来源。

修正为启动前准备来源事实，再给同一句话，rollout 中直接确认存在该事实。Agent 自行阅读 hooks/README、查询能力，并读取到模拟 RSS 的 HTTP 200 与空 channel。它反复试图找到 fixture 服务实现和 item 结构，读取 worktree 和临时 profile 的公开文件，出现把 Action ID 误当 state view 查询的 invalid_input；没有把这些失败隐藏。

随后真实对话输出：

```text
RSS fixture 的服务脚本不在工作区，我会把解析写成防御式。现在明确一下这次要交付的东西：
- 定时巡查 RSS（hooks/schedules.json + hooks/starport_check）
- 发现新集时自动取回附件、记录状态、并唤醒我来完成准备
- 幂等：同一集不会重复下载或重复叫醒
先写脚本。
```

它写了 `hooks/starport_check`，解析 RSS/Atom，以条目标识保存 seen，尝试取回附件，出现新条目后调用 agent.wake，把条目、下载结果和说明交回主会话。脚本在调用唤醒前保存 seen；失败时也可能返回 0。这是被观察 Agent 写的策略，后端没有替它修正或编排。

它写入并通过真实命令读回了：

```json
[
  {
    "id": "starport-feed",
    "program": "hooks/starport_check",
    "everySeconds": 900
  }
]
```

900 秒与 README 的格式示例相同，不能据此断言它依据来源特性选择了频率。它遇到 heredoc 限制后改用 Python 写文件，之后说“现在写定时声明，并用本地 fixture 做一次端到端自测（不唤醒）”。第二个 6 分钟窗口结束时仍在这轮中，驱动关闭了实例；没有观察到自行结束、定时到期、真实更新后的唤醒或完成附件准备。模拟发布源尚未进入“这轮结束后发布更新”的阶段。这里的结论仅为：**它自行写出了脚本和声明，并在脚本里选择新条目取回附件后唤醒；实际自动巡查链路没有在本次观察窗口跑完。**

[完整轨迹](evidence/x31/prepared-source/chat.jsonl.gz)、[包含脚本写入及声明读回的工具证据](evidence/x31/prepared-source/authored-tools.json)、[窗口结束与清理](evidence/x31/prepared-source.log)。没有提供第二条方法提示来让观察“通过”。

### 空主会话重启

最初真实失败：

```text
no rollout found for thread id 01a12ca6-2925-7513-b676-147f227695e3
```

独立协议诊断没有模型回合。未命名线程 rolloutBeforeName=false、rolloutAfterName=false，重启 resume 失败；命名线程从 false → true，重启 resumeError=null 且 resumedId 相同：[真实对照](evidence/x31/empty-rollout-probe.json)，[诊断脚本](../../scripts/next/x31_protocol_probe.py)。修复后的真实应用在没有发送第一句话的情况下：

```json
{"before":"01a12ca9-88df-7282-9a9d-3e826345a40e","after":"01a12ca9-88df-7282-9a9d-3e826345a40e"}
```

[修复后完整记录](evidence/x31/empty-session.log)。

### 新对话后续、定时唤醒、忙时排队

独立基础设施控制使用另一临时真实实例，模型相同。用户明确要求 Agent 在新对话通过 followup.register 登记真实空目录扫描的后续；这不是上面的自主行为观察。实际结果：

```json
{
  "mainThread":"01a12caa-2f63-76e3-b6ad-de519a5889c2",
  "newThread":"01a12caa-39d7-7cf3-a0d7-dbde4efb7bd9",
  "followupThread":"01a12caa-39d7-7cf3-a0d7-dbde4efb7bd9",
  "turnId":"01a12caa-7470-7c80-8712-8a2eee5d471b",
  "state":"completed"
}
```

之后用实验编写的定时控制脚本报告发现并唤醒：这里的 3 秒属于驱动的控制输入，不是 Agent 的频率决策。此时新对话有一个真实执行 Python sleep 的回合。真实等待记录：

```json
{"state":"ready","threadId":null,"turnId":null,"reason":"Chat host has an active turn; waiting until idle.","origin":"hook:job-d15a5cc276cf3f7711ff9af1847d9a0d"}
```

原轮完成后，才在 main 开新轮：

```json
{"threadId":"01a12caa-2f63-76e3-b6ad-de519a5889c2","turnId":"01a12caa-d5d3-7bd2-9005-8d08970ca4bd","state":"completed"}
```

脚本真实回执摘录：

```json
{"exitCode":0,"elapsedMs":5905,"timedOut":false,"verification":"verified","stdoutTail":"…timer finished; cookie=[redacted]\n","stderrTail":""}
```

第一回执还包含 activity.report 返回的 discovery:1/source=x31-control/version=2 和 agent.wake 的受理记录；另一次运行只输出已通知后的末尾，不重复唤醒。listSessions 返回两个线程，并准确标记 isMain/isCurrent。[完整输出](evidence/x31/controls.log)、[回合原始轨迹](evidence/x31/controls/chat.jsonl)。

这份驱动有两处配置/时序失败：首次未把空目录登记为临时媒体扫描根，真实端点拒绝“Path is outside the configured media folders”；只修正实验配置，没有放松授权。其次重启驱动用 mainThreadId 已加载作为就绪条件，读取到了 resume 尚未完成的 threadId=null，所以最后断言失败。这不影响上面已完成的路由观察；改为等待实际 threadId/model 就绪后，仅补测下面的终端与重启部分，没有重跑新对话和定时控制。

### 终端默认主会话、重启不重复派发、发现 activity

无 NIPAPLAY_CHAT 的真实端点登记任务后续，实际 origin=harness_cli：

```json
{"threadId":"01a12cab-f5b2-7ce3-973f-8d1c60198eb2","turnId":"01a12cac-0145-7c60-b984-cc6d275a42ec","state":"completed","origin":"harness_cli"}
```

关闭并从同一临时 profile 再启动：

```json
{"before":"01a12cab-f5b2-7ce3-973f-8d1c60198eb2","after":"01a12cab-f5b2-7ce3-973f-8d1c60198eb2"}
```

原后续仍 completed，turnId 保持 `01a12cac-0145-7c60-b984-cc6d275a42ec`，没有重复执行。activity 中能读到“版本已出现”、source=x31-terminal-fixture、version=3 和已脱敏 cookie，保留真实调用 origin/invocationId；不包含额外唤醒。[完整输出](evidence/x31/terminal.log)、[真实 activity](evidence/x31/terminal/activity.json)。

### 检查、构建和清理

Flutter 固定为 3.44.6，全都 --no-pub；测试经 TEAM.md 指定 lockf 队列。最初缺派生 package_graph/macOS Swift Package 输入，只读复制同 lock 的 followups worktree 派生输入并重定位到本 worktree，没有解析依赖；所有构建都在这里。CocoaPods 对 Erika 锁文件的自动改写已经恢复。

- 最终包含空线程落盘修复的 macOS Debug 构建成功：[build-materialize.log](evidence/x31/build-materialize.log)。原有 native 警告保留。
- 改动模块、对话适配器和约束测试 analyze 无问题：[analyze-final.log](evidence/x31/analyze-final.log)。
- 会话标识跨选择/重开保留、harness 间隔离、事实脱敏/来源、队列中旧 hook 不重放、非法定时配置不执行，以及原有回执/取消约束通过：[constraints.log](evidence/x31/constraints.log)。首次 native 构建并行期间一项 3 秒 hook 约束超时；构建结束后该项通过。随后新 facts 测试发现 cookie 脱敏不足，修复后相关两文件共 12 项通过，失败日志仍保留。
- 全量 test/next 加桌面退出测试只运行一次：421 通过、4 跳过、3 失败；三个失败都只是旧测试断言数据库版本仍为 11，实际为 12：[完整日志](evidence/x31/full-next.log)。改正三个旧版本断言后，只补测 next_core/danmaku_flow/media_identity 三文件，51 项全部通过：[补测日志](evidence/x31/migration-assertions.log)。去重后的有效结果为 424 通过、4 跳过。没有为了旧版本断言再跑全量。
- `git diff --check` 通过。所有 11 次实验 App 启动均按各自 PID 退出，临时 profile 已删除：[cleanup.json](evidence/x31/cleanup.json)。复制的 auth/config/CA、临时数据库、模拟源与 Agent 生成文件随各自 profile 删除；实现 worktree 没有提交。

## 4. 还缺什么与问题

实现与接口已交付。自主观察没有跑到 Agent 的定时脚本处理真实新增 item 并完成准备，因此不能把基础设施控制实验等同于这个自主闭环已经成立。每天定时的日历/DST 跨越和 Windows 宿主未做真实平台实验；Windows 继续保留 X23 的明确宿主不可用事实。

需要主控决定的问题：**没有**。
