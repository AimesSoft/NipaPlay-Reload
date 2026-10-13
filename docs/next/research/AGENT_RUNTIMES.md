# Nipa 的 agent 工具与模型：三种运行环境的调研和设计

调研日期：**2026-10-13**。仓库：`next/x59-runtimes`，基线提交 `2ae4a0af0c2e4e7aa710d010c18ff7443f1693c5`。本报告只做调研与设计；没有修改产品代码，没有构建、启动 NipaPlay、执行模型对话、读取 CPA 或 `~/.claude`、`~/.codex` 的凭据。写入限于本报告和 [x59 证据目录](../evidence/x59/)。

证据标记：**[仓库]** 为本提交代码或已有实验报告；**[官方]** 为提供方的一手文档；**[源码]** 为锁定版本的公开源码或类型；**[设计]** 为建议；**[待实测]** 为尚未用真实请求验证的判断。外部资料均于 2026-10-13 读取，文档日期不能替代端到端实验。证据 manifest 保存 URL、抓取日期和摘要，见文末。

任务书指定的 `HARNESS_TOOLS_CONTEXT.md`、`HARNESS_MEMORY.md` 在本 worktree 及已检索的相邻 worktree 中未找到。本报告用实际能力层、记忆代码、种子和 X49/X50/X52 补充，不能声称已读这两份文件。[基线记录](../evidence/x59/workspace-baseline.json)列出了这个缺口。

## 1. 核心决定与结论

**[用户决定／设计] 支持 Codex、Claude Code、DeepSeek Harness 三种 agent 工具；默认推荐模型为 DeepSeek V4.1 Flash 和 GLM 5.3 Flash。工具与模型是独立设置。** 工具负责 agent loop、工具执行、会话管理和压缩；模型负责推断。不能把“选择 Claude Code”解释成“必须使用 Anthropic 模型”，也不能把“DeepSeek 模型”绑定到 DeepSeek Harness。

用户推荐这两个模型的理由是前沿模型可能拒绝 BT 下载任务。**这属于待验证的行为假设**，本次没有对比拒绝率，也没有证据保证某个模型一定接受某类任务。后续应把真实 harness 任务的完成率、拒绝及理由、能力调用错误一起记录，不能从协议兼容或宣传榜单推出任务行为。

重要更新：**[官方] DeepSeek 已原生提供 Responses API，并发布 Codex 接入指南；智谱也提供独立的 Responses 兼容入口。** X52“当时官方 DeepSeek Chat Completions 不能直接接 Codex”的实验仍然有效，但不能外推为当前 DeepSeek 服务没有 Responses。推荐模型不再天然要求 NipaPlay 内置 Chat Completions → Responses 转换层。DeepSeek 的 Codex 组合有官方专门指南；智谱的 GLM Flash → Codex 组合目前只有协议与模型文档证据，完整工具调用兼容性须验收。

**[设计] 先抽出运行接口，再逐个适配。** Codex 第一实现保持现有行为；Claude 适配用官方 Agent SDK sidecar；DeepSeek Harness 使用完整 SDK profile 加受控的 Session Controller/core 控制桥。不要让三者伪装成同一种 Codex JSON-RPC，也不要重写三个工具已有的 agent loop。

## 2. NipaPlay 与 Codex 绑在哪里

以下位置均为本次基线；链接指向文件，行号写在标签中。读取的 [chat README](../../../lib/next/chat/README.md) 有局部陈旧描述：Windows 原生启动和 collab 过程保存已经在代码中实现，须以代码为准。

| 耦合点 | 实际依赖和迁移影响 | 代码位置 |
|---|---|---|
| 后台进程与握手 | 具体类 `ChatHost` 启动 `codex app-server`；POSIX 继承登录 shell 环境，Windows 找原生 exe。换行 JSON-RPC、请求 ID、`initialize`/`initialized`，`experimentalApi`、`config/read`、`model/list` 都是 Codex 协议 | [chat_host.dart:24、123、215、315](../../../lib/next/chat/chat_host.dart) |
| 项目运行语义 | 每次传 `cwd`、`sandbox: danger-full-access`、`approvalPolicy: never`。不同工具权限模式不等价，不能透传字符串 | [chat_host.dart:649](../../../lib/next/chat/chat_host.dart) |
| 创建与发送 | `thread/start`、`thread/resume`、`turn/start`；busy 时不能启动新 turn。结果及通知以 `threadId`/`turnId` 关联 | [chat_host.dart:655、685](../../../lib/next/chat/chat_host.dart) |
| 引导 | `turn/steer` 带 `expectedTurnId`，目标是正在运行的 turn；不等于将消息排到下一回合 | [chat_host.dart:821](../../../lib/next/chat/chat_host.dart) |
| 中断与问题 | `turn/interrupt` 指定 thread/turn。只回答 `item/tool/requestUserInput` 的问题；其他服务端请求返回 `-32601`，现有 host 并不是完整审批客户端 | [chat_host.dart:883、888](../../../lib/next/chat/chat_host.dart) |
| 会话列表和主会话 | `thread/list` 的 `data`/`nextCursor`、`preview`、更新时间；本地主/当前会话映射。空线程用 `thread/name/set` 落盘，避免为登记线程发付费“你好” | [chat_host.dart:720–806](../../../lib/next/chat/chat_host.dart)、[session_store.dart:14](../../../lib/next/chat/session_store.dart) |
| 冷恢复与历史 | `thread/read includeTurns`；`thread/resume`；实验性 rollout `path`。`chat-rollouts.json` 记原路径，切换独立模型 home 后恢复同一线程。不能假定其他工具 ID 与磁盘路径相通 | [chat_host.dart:610、634、828](../../../lib/next/chat/chat_host.dart) |
| 条目白名单 | `userMessage`、`agentMessage`、`reasoning`、`commandExecution`、`fileChange`、`mcpToolCall`、`collabAgentToolCall`、`plan`、`webSearch`；未知类型忽略。UI 认识的部分类型如 `dynamicToolCall` 不在 host 白名单 | [chat_host.dart:523](../../../lib/next/chat/chat_host.dart) |
| 推理显示 | 接受 `item/reasoning/summaryTextDelta` **及 `textDelta`**，100ms 合并为 `host/reasoning`。已有过程持久化只存 summary，但实时显示可能收到原始 reasoning；不能把现状概括为始终只显示摘要 | [chat_host.dart:552、556](../../../lib/next/chat/chat_host.dart)、[turn_process_store.dart:85](../../../lib/next/chat/turn_process_store.dart) |
| 压缩 | 显式 `thread/compact/start`，并读 Codex 状态/通知；X49 已观察到 compact 后记忆 hook 在下一回合生效。自动压缩由 Codex 自己管理 | [chat_host.dart:847](../../../lib/next/chat/chat_host.dart)、[X49](../X49_REPORT.md) |
| hook 与信任 | 内联 TOML `projects` 表设 harness trusted；`hooks/list` 找 harness `.codex` 项目 hook 的 enabled/currentHash，写每线程 `hooks.state[...].trusted_hash`。项目信任与 hook 哈希信任是两道门，不能用一个布尔字段代替 | [chat_host.dart:177、184](../../../lib/next/chat/chat_host.dart)、[X50](../X50_REPORT.md) |
| SessionStart 记忆 | 种子 `.codex/hooks.json` matcher 为 startup/resume/clear/compact；Python 接 `session_id`，调用 `nipa memory.context`，输出 `hookSpecificOutput.additionalContext`。同 server 对已加载线程 resume 不重跑 hook；进程真正重启后 resume 才重跑，这是 X49 实测 | [hooks.json](../../../assets/next/harness/.codex/hooks.json)、[session_start.py](../../../assets/next/harness/hooks/session_start.py)、[X49](../X49_REPORT.md) |
| `CODEX_HOME` 与模型 | X52 两种 source 为“Codex 自身配置”及“NipaPlay 管理”。后者建立独立 codex-home、`wire_api=responses`、`env_key`、`requires_openai_auth=false`、ephemeral auth、禁用 shell snapshot，shell环境排除模型key；模型切换要所有线程与帮手 idle，重启 transport 并恢复 | [host_settings_service.dart:161、199、238](../../../lib/next/settings/host_settings_service.dart)、[model_launch.dart](../../../lib/next/chat/model_launch.dart)、[chat_host.dart:338](../../../lib/next/chat/chat_host.dart)、[X52](../X52_REPORT.md) |
| 回合过程保存 | Codex 历史不保证保留本次 UI 所需过程，所以旁存 reasoning summary、command、collab；按类型顺序补回原 history。60 turns/4MiB、最多128条过程，输出有截断；完成态才有较完整输出，突然退出可能不知 exitCode | [turn_process_store.dart:8、42、85、196](../../../lib/next/chat/turn_process_store.dart) |
| 活跃状态 | liveness 直接识别 Codex method、turn/status；transport 活着不等于模型请求或后台子任务活着 | [liveness.dart:20](../../../lib/next/chat/liveness.dart) |
| 主控帮手 | `Helpers` 直接调用 `ChatHost` 建/续帮手线程，最多2个并发；有持久任务回执和 followup，恢复时不重放不确定执行 | [helpers.dart:14](../../../lib/next/chat/helpers.dart) |
| 原生子代理 | `NativeHelpers` 解析 collab 的工具、receiver threads，source 为 codexNative；把 spawn/sendInput/wait/adopt 接到任务系统，避免同一次 child start 重复登记 | [native_helpers.dart:19、72、118](../../../lib/next/chat/native_helpers.dart) |
| 近期记忆 | `recentMemoryFacts(ChatHost ...)` 查最多30个线程，按更新时间读原生 turns/items，过滤帮手，取最近6条消息及未完成工作。原生 history 字段渗入记忆服务 | [recent.dart:8](../../../lib/next/memory/recent.dart) |
| 生命周期装配 | `next_runtime.dart` 实例化具体 ChatHost，能力、记忆、帮手依赖它；只改 ChatPort 无法消除下层耦合 | [next_runtime.dart:508](../../../lib/next/next_runtime.dart) |

### 2.1 UI 消费的具体字段

**[仓库]** [chat_port.dart:58](../../../lib/next/ui/conversation/chat_port.dart) 的 `ChatHostPort` 返回原生 RPC 形状。[chat_turn.dart:288、444](../../../lib/next/ui/conversation/chat_turn.dart) 和 [nipa_chat.dart:133、667、799](../../../lib/next/ui/conversation/nipa_chat.dart) 直接消费：

| UI 需求 | 当前 Codex 字段/事件 | 中立化时的要求 |
|---|---|---|
| 路由和终态 | threadId/turnId/itemId；`turn/started`、`turn/completed`，status、error | 稳定的 Nipa session/turn/item ID；原生 ID 单独保留；failed/interrupted/incomplete 分开 |
| 用户与回复 | userMessage.content 文本；agentMessage.text 和 textDelta | 按语义标记人类、hook、工具结果、帮手报告；不能把 Claude 的 user/tool_result 当作用户发言 |
| 推理 | reasoning.summary，fallback content；host/reasoning.key/delta | summary 与 rawThinking 的可见性分开；不支持摘要时允许为空，不生成假摘要 |
| 命令 | command（字符串或数组）、aggregatedOutput、exitCode、status | 允许未知 exitCode、分离 stdout/stderr；heartbeat 不充当输出 |
| 工具与子代理 | tool/name、prompt、receiverThreadIds、collab 工具种类 | 用 delegation ID、parent、native child ref；子任务不必有可独立恢复的 thread |
| 历史时间/分页 | startedAt 秒、durationMs、updatedAt、preview、nextCursor | 统一 UTC 时间与 opaque cursor，列表必须标 runtime；原生时间单位在 adapter 处理 |
| 语义卡片与帮手接管 | thread/turn 关联、最后 ReplyPart 作为最终回复的启发式；隐藏 `ui.present` 的命令解析 | 卡片归属使用统一 ID；finalAnswer 显式标记；接管由 capability 决定 |
| 提问 | requestId、questions/options、answers | 中立 InteractionRequest，区分提问与权限审批，进程重启使旧请求失效 |

现有过程日志不是第二份模型对话：Nipa 应继续只保存展示与回执所需的有界投影，原生 transcript 由工具管理。改造时应以稳定 item ID/seq 补历史，替换按类型位置匹配，避免并行工具或子代理重排后错配。

## 3. Claude Code 2.1.289：可驱动性与限制

**证据**：本机只运行了 `claude --version`/`--help`，[help](../evidence/x59/claude-help.txt)和 [version](../evidence/x59/claude-version.txt)已存。公开 npm **Agent SDK 0.3.289** 类型与本机 CLI 版本配套，[来源/完整性记录](../evidence/x59/claude-sdk-types-0.3.289/source.json)；另存最新 0.3.296 只作旁证，不把其新增行为归到 2.1.289。当前官方 SDK 文档可能比本机新，接入必须按握手 capability 和配套类型决定。

### 3.1 会话、回合、引导与中断

**[官方／源码]** CLI headless 路线为下面的启动形状；本次未执行这条命令：

```text
claude -p --input-format stream-json --output-format stream-json
  --verbose --include-partial-messages --replay-user-messages
```

stdin 保持打开，用换行 JSON 的 SDK user message 发送多条输入，stdout 为事件，stderr 为诊断。一次 `-p "文本"` 子进程虽能恢复，但不适合每条消息重启和持续引导。建议用 Node/Python 官方 Agent SDK sidecar：`query(prompt: AsyncIterable<SDKUserMessage>, options)` 管进程和控制协议，Dart 只维护自己的小协议；避免手写私有 `control_request` 的所有细节。[C1][C2]

| 能力 | 2.1.289 可用方式与语义 |
|---|---|
| 新会话 | `--session-id` UUID，系统 init 返回 session_id；本地可预留空会话，但首条输入前未必有可列出的磁盘 transcript，不发付费占位回合 |
| 恢复 | `--resume <id>`、SDK resume；`--continue` 是 cwd 最近会话，不能作为精确恢复；fork 使用独立 ID，原始历史不作跨工具通用 transcript |
| 列表/读历史 | SDK `listSessions({dir,...})`、`getSessionMessages(...)`，查询已有 session 数据；本次只查类型/文档，未读用户会话目录 |
| 发回合 | 异步输入流及 user message uuid；result 标记回合结束。异步背景工作可能再产生结果，不能首个 result 后杀进程 |
| 引导 | `priority: next`（默认）：当前工具调用完成后同回合读，若回合已结束则下一回合；`later` 总是排到下一回合。`now` 且 origin=human 在 CLI≥2.1.286 可将 shell、subagent、MCP 等转后台后同回合读；不适合后台化时中断后下一回合读。≥2.1.287 又覆盖 WebFetch/WebSearch。**支持引导，但不保证 Codex expectedTurnId 的原子语义** |
| 中断 | SDK `interrupt()`；握手有 interrupt_receipt_v1 才可依赖回执。`still_queued` 表示中断后仍可能执行的消息；有 interrupt_cancel_queued_v1 时控制请求可要求取消排队消息，sidecar 必须验证 SDK 暴露范围及处理回执 |
| 进程信号 | SIGINT 可中断；SIGTERM 退出143、终止 Bash 树并留下未完成 turn，不等价于正常中断。先中断/确认，再关进程；异常恢复不得自动继续有副作用的命令 |

这里的“引导”要在界面显示实际接受结果：`sameTurn`、`nextTurn` 或 `pending`。UUID 去重、queued/consumed/cancelled 状态由 Nipa 记录，不能把写入 stdin 成功显示成模型已读。[C2][C3]

### 3.2 可见条目

**[官方／源码]** 流有 system/init、assistant、user、result、stream_event，以及 tool_progress、task_started/progress/updated/notification、hook_started/progress/response、compact_boundary、status/retry 等。assistant 的 Messages 内容块有 text、thinking、tool_use；user 可能是 tool_result；raw stream_event 提供局部文本/工具参数增量。[C2]

命令可从 Bash tool_use 输入得到，stdout/stderr 等可从对应结构化 `tool_use_result` 得到。**tool_progress 是进度/心跳，不能保证逐行 stdout，也不能保证每个 Bash 都有 exitCode。** Hook 的 exit_code 不等于 Bash 的 exitCode；未知值保留 null。文档和类型给出的 Bash 输出还包含 interrupted、backgroundTaskId 等，要按具体工具 schema 解析。

thinking 是模型思考文本；task_progress.summary 是子任务进展摘要，二者均不自动等于 Codex reasoning summary。中立流默认只展示提供方明确的摘要、工作说明和进度，不把原始 thinking 存入过程日志。

原生子代理由 parent_tool_use_id、agent/task/run ID、Agent 工具结果及 task 通知关联；可开 `forwardSubagentText`。这些 ID **不天然是可独立恢复、引导、接管的顶层 session**。先实现观察和任务回执；需要可接管帮手时使用 Nipa 建立的独立会话。[C2][C6]

### 3.3 权限、说明、hook 与压缩

**[官方／源码]** CLI help 的权限选项为 acceptEdits、auto、bypassPermissions、manual、dontAsk、plan；配套 SDK 使用 default 对应通常交互模式，字符串不完全相同。dontAsk 会拒绝需要询问而尚未授权的调用；bypassPermissions 与 Nipa 当前完整访问实验授权更接近。auto 的可用性和行为受版本、提供方及策略约束，不能默认为第三方模型可用。`canUseTool`/AskUserQuestion 接到中立审批/提问接口；已自动批准的调用不一定进入 canUseTool。[C4]

**当前已支持 AGENTS.md，旧知识需要更新。** CLI≥2.1.277 在项目路径没有 CLAUDE.md/CLAUDE.local.md 时读取 AGENTS.md；2.1.281 修复部分第三方提供方场景。本机2.1.289满足版本条件，但上级 CLAUDE 文件或设置仍会改变发现。可靠兼容方案是项目根 `CLAUDE.md` 只写 `@AGENTS.md` 引用，不复制整份内容。[C5]

项目 `.claude/settings.json` 配置 SessionStart，source 有 startup/resume/clear/compact/fork；该 hook 用 additionalContext 注入记忆。PreCompact 可作压缩前处理；**PostCompact 主要是观察/落盘，不用来注入上下文；压缩后注入使用 SessionStart 的 compact。** 自动压缩由工具管理，并有 compact_boundary；项目根 CLAUDE.md 会重新注入，瞬时对话提示与长工具输出不能据此保证保留。[C5][C7]

Headless `-p` **跳过 workspace trust 对话并可直接执行项目 hooks/MCP**，没有 Codex 的每 hook trusted_hash 门。adapter 应只在 Nipa 已授权的 harness 启动，不能照抄 Codex trust 状态；显示实际加载的设置来源。SDK 显式配置 project 来源以加载项目说明/hook，用户来源按产品策略保留。不要盲目加 `--bare` 或 safe mode：它们会关闭本方案需要的说明、hook、技能和后台行为。[C1][C2]

### 3.4 模型、凭据及本机启动障碍

**[官方]** Claude 模型可用 API key，CLI 可使用 Claude 订阅登录，以及 Bedrock、Vertex/Google 平台、Foundry 等官方渠道；第三方 gateway 使用 **Anthropic Messages 兼容协议**，不能把 Chat Completions 或 Responses URL 当作它的模型入口。[C8][C9]

**[官方约束]** SDK overview 明确写第三方产品未经既有批准不得提供 claude.ai 登录/额度，建议 API-key 接入；所以不能把“技术上继承用户订阅会话”当作已可上线的 Nipa 登录方案。第三方 DeepSeek/GLM key 路线独立于 Claude 订阅。SDK 的公开菜单品牌指导建议用“Claude Agent”；技术说明可注明底层 Claude Code，实际 UI 文案需按最终集成方式核对。这里记录来源约束，研究阶段不发起额外确认流程。[C10]

**[本机只读事实]** 当前 PATH 的 `claude` 是 wrapper：清除 ANTHROPIC_BASE_URL、AUTH_TOKEN、API_KEY、MODEL 及模型别名等环境变量，然后调用本机2.1.289原生程序和固定 loopback proxy。adapter 若只给 `claude` 注入第三方环境变量，配置会被静默清除。必须允许选择可执行文件并做无额度启动诊断；可明确使用原生安装路径，或要求用户配置保留 provider 环境的 wrapper。本次未改 wrapper，也未记录其认证信息。API key 只经受控子进程环境注入，禁止打印整份环境或在 CLI 参数带 key。

## 4. DeepSeek Harness：完整 agent 工具，但现有 SDK 还不足

**[源码]** 官方 MIT developer preview，快照 `d743267388641bc76f17c45ce8b4c231aed1d32c`（2026-10-09），版本 **0.2.1-alpha.2**。只克隆到 `/tmp/nipa-x59-deepseek-harness` 并读源码，没有安装或启动。永久链接、复制文件哈希见 [source manifest](../evidence/x59/deepseek-source-manifest.json)。以下“支持”区分 stdio SDK、较完整 Session Controller 与内部 core，不能混为公开 SDK 能力。[D0]

### 4.1 生命周期及控制接口

`dsh --profile sdk` 是 full base + JSON-RPC 的后台 profile，stdout 为协议。不要选 sdk-minimal：它省掉说明发现、运行上下文、压缩、子代理等 Nipa 必需模块，且是完整访问模式。SDK profile 不生成模型会话标题，避免隐性标题调用成本。[D1]

| 操作 | 现有 stdio SDK | 更完整的 Session Controller/core 与适配决定 |
|---|---|---|
| 握手/选模型 | initialize(cwd, provider, model, reasoningEffort, maxTokens)；serverInfo version 当前0.0.1 | 版本字段不是完整 capability 协商，Nipa 控制桥需补 capabilities 与 schemaVersion |
| 创建/发送 | `session/prompt`，未知 ID **create**，返回 messageId 入队回执；调用 agent.followup | create + prompt；返回 receipt 与 turn/start/end 分开 |
| 已加载继续 | 同进程相同 ID 可以继续 | 明确 session open 状态 |
| 冷恢复/列表/历史 | **没有专用 resume/list/read 请求**；不能由“复用 ID”的教程推断跨进程恢复 | core `ctx.agents.resume`；controller list/page/fork，桥显式 resume 并检查持久 session |
| 引导 | prompt 是 followup，**不是 steer** | controller prompt(mode=queue/steer)；core agent.steer 是 next-step 语义，报告实际 consumption |
| 中断 | **没有 per-session cancel**，shutdown/kill 影响整进程 | controller cancel 或 core cancel；controller 当前 keepInbox=true，停止还要显式处理排队输入，避免停后再跑 |
| 历史/流 | session.event 只发已提交的 durable event，session.status 是 idle/running；subagent.started/finished | controller follow 有 snapshot、durable seq、可选 transient assistant frames；选此路线才有完整实时文本 |
| 工作目录 | working-directory/get/set；未知 ID 也可能创建 | 不在 UI 把读 cwd 当纯无副作用诊断 |

六种 stdio request 的完整列表为 initialize、session/prompt、session/wait、session/working-directory/get、session/working-directory/set、shutdown。SDK server 没有订阅 agent/assistant-stream；assistant/message 可含结算后的带时间 stream，但这不等于 token 即时推送。[D1][D2]

**[设计]** 首选提供一个版本固定、范围小的 Cordis 控制桥，复用 Session Controller/core 的 list/create/resume/prompt-steer/cancel/page/follow，向 Dart 提供中立控制协议。或者连接现有 `/api/<namespace>/<method>` 与 Gateway `/api/remote.mux`，限定 loopback 和认证。桥不处理模型协议、不重新执行工具、不另建 agent loop。若先接纯 SDK，必须显式降级显示“仅进程内继续、无原生引导/单会话中断、结算后文本”；这不是最终验收完成。[D3]

### 4.2 事件、命令、帮手、权限与保存

持久 session 日志包含 turn/start/end、step/start/end、user/message（带 source）、assistant/message（text/reasoning/tool calls）、tool/call、tool/result、inbox spliced、compaction/start/summary/end，以及子代理 lineage。命令来自 Bash call 的 JSON 参数，tool result 的 message/meta 可给输出与结束信息。job registry 的 job.follow 可观察后台命令；纯 SDK 不自动得到实时 stdout。[D4]

reasoning 为原始思考块，未保证摘要。adapter 只保留工具必要的原生 transcript，由 Nipa 的过程日志默认略去 raw thinking；UI 显示“工作中/工具执行”即可。支持子代理创建、结束和父子身份；完整接管要经 core/controller 检查权限与会话是否已加载，不把通知等价为控制权。

权限将 sandbox 和 approval 分开，预设有 workspace-write + ask、danger-full-access + never。现有 stdio 协议没有 server→client approval request；需要控制桥或使用用户已授予 Next 的完整访问语义，不能发送假审批。[D5]

原生 session journal 是恢复事实来源，Nipa 的事件 seq/ID 是展示与业务回执来源。恢复不能把持久消息重新当作新工具执行；中断后的 inbox、后台 jobs、子代理必须分别核查。

### 4.3 说明、hook、记忆与压缩

agent-instructions 默认发现 AGENTS.md 和 CLAUDE.md，支持本地覆盖及重复内容处理、文件预算；DSH_HOME 可有用户说明。共享 harness 的 CLAUDE.md 若是 `@AGENTS.md` shim，DeepSeek Harness 不应被假定有相同 `@` 展开语义；配置 `instructionFileCandidates: [AGENTS.md]`，从源文件加载一次。[D6]

实验性 hooks-codex/hooks-claude-code 插件能读取部分现有 hook 配置及 SessionStart.additionalContext，**不是完全兼容**：未提供本任务所需的完整 compact 生命周期映射，不能直接宣布 X49 记忆机制复用成功。锁定源码的两种 bridge 都在 agent/created handler 中 `await run`；hooks-codex README 仍有 detached/可能错过首请求的旧段落，与更新后的源码/设计段落冲突。以源码为较强证据，但仍须实测事件派发是否真正等待到首请求。[D7]

compaction-basic 默认按窗口0.8阈值、约0.16保留比例执行，压缩摘要使用模型调用；模型容量、output cap/headroom 必须配对，未知模型不应任凭默认262144窗口。手动 compactRegion 还受 open turn 前置条件限制，不能直接包装为随时可用的 Codex compact。记忆方案用原生 compaction 事件和下一 step 前的 revision 注入，做到常驻事实不会只依赖被压缩的会话文本。[D8]

### 4.4 支持的模型和接口

**[源码]** `llm-deepseek` 的官方 direct route 实际使用 **Anthropic-compatible Messages**，base `https://api.deepseek.com/anthropic`，请求 `/v1/messages`；当前默认 catalog 有 deepseek-flash、deepseek-v4-pro、1M容量信息。工具名称“DeepSeek”不意味着它只能用 DeepSeek 模型。[D9]

`llm-pi-ai` 可声明 `openai-completions`、`openai-responses`、`anthropic-messages` 三种协议；catalog 或手工 routes 可接 GPT、Claude、GLM、Kimi、兼容 gateway/自部署服务。配置 `api`、`baseURL`、`apiKeyEnv`、models（id/contextWindow/输出预算/reasoningEfforts）及必要 compat；缺省 catalog 不证明新模型已登记。GLM 使用显式 route，不能只改 model ID。[D10]

**[源码／设计]** full base 默认挂 `session-log-deepseek`，向官方 API 上传最多8MiB的 session-log 附加字段，不进入模型 tokens。Nipa profile 应明确 `enabled:false`，不让换运行工具隐性增加整段操作日志上送。这是当前模块行为，不是猜想。用 Nipa vault 的环境引用而非 YAML key 值，禁止把运行环境保存成含 key 的 `.credentials.yaml`。[D11]

## 5. 工具 × 模型兼容矩阵

**资料日期均为2026-10-13。** “直连”是模型传输协议，不意味着会话控制与全部能力已经验收。状态：**可接**＝官方有直接接入路线或源码支持相应 protocol；**条件可接**＝接口存在但关键模型/工具一致性待实测；**需网关**＝此工具没有该模型的原生接口。推荐模型以官方端点为基准；CPA 是另一提供方，其支持格式不能由 DeepSeek 官方文档推断。**CPA Responses + deepseek-v4.1-flash 已有 X52 真实成功记录**，本次直接复用，不重新探测；这份记录不证明 CPA 也提供 Messages/Chat。

| agent 工具 | DeepSeek V4.1 Flash（推荐） | GLM 5.3 Flash（推荐） | OpenAI GPT／Codex 模型族 | Anthropic Claude Sonnet／Opus／Haiku 模型族 |
|---|---|---|---|---|
| **Codex** | **可接，原生 Responses**。官方 base `https://api.deepseek.com/`，model **deepseek-flash**，wire_api=responses，env_key，官方 model catalog；指南要求 Codex≥0.144.0。支持 function/custom apply_patch/并行调用；1M、输出上限384K。**无 reasoning summary/encrypted_content、无 previous_response_id；raw thinking 不能当 summary**。缓存自动，见 M1–M4 | **条件可接，智谱原生 Responses**。base `https://open.bigmodel.cn/api/v1`，model glm-5.3-flash，wire_api=responses，env_key + 容量/能力 catalog。协议文档以 glm-5.3 举例，未明确单列 Flash+Codex 全链路；须验 custom/apply_patch、reasoning replay、tool_choice/并行。模型1M/128K、不可关 thinking；API 无 cancel，summary 未声明，缓存自动。不能宣称已实测，见 M5–M8 | **可接，Responses 原生**。默认 OpenAI/Codex provider 或自管 Responses route；原生登录/API key模式按模型账号。工具、推理摘要、上下文和缓存依 exact model catalog，不硬编码为一个模型族值，见 O1 | **需 Responses 网关**。Claude 原生 Messages 不等于 Responses；Codex 无原生 Messages provider。配置网关 base/env_key/model catalog，需转换 tool calls、reasoning 与 SSE。Claude窗口/缓存以 exact model 和网关保真度为准，见 C9、O1 |
| **Claude Code** | **可接，官方 Anthropic Messages 兼容端点**。base `https://api.deepseek.com/anthropic`；AUTH_TOKEN=DeepSeek key；MODEL=deepseek-flash[1m]；主/快捷/子代理别名均钉 Flash。支持 tools/thinking；budget_tokens、cache_control 等被忽略；1M/384K仍需运行工具预算配置。不得把 Opus 默认别名留下导致映射到V4 Pro，见 M1、M3、M4 | **可接，智谱 Anthropic Messages 兼容端点**。国内 base `https://open.bigmodel.cn/api/anthropic`；MODEL=glm-5.3-flash[1m]，其余别名同模型，AUTH_TOKEN 或受控 API-key方式；区分 API余额与 Coding Plan key。1M/128K、thinking不能关闭，不能承诺 Claude原生摘要/缓存字段完整复刻；工具与子代理需验。国际 Z.AI另设区域/key/base，见 M5、M7–M9 | **需 Messages 网关**。OpenAI Responses/Chat不是Claude原生wire；网关转换+固定所有模型别名，不能使用 Claude订阅结算 GPT。工具schema、thinking/cache语义由网关适配，见 C9 | **可接，原生 Messages**（及官方云提供方）。API-key为Nipa建议路径；订阅登录集成有SDK官方约束。上下文、thinking摘要形状、prompt cache按exact模型/账户；SDK子代理可见性是runtime能力，见 C8–C10 |
| **DeepSeek Harness** | **可接，llm-deepseek 原生 Messages route**。provider/model=direct-route/deepseek-flash，apiKeyEnv指向同一DeepSeek key，1M/output/reasoning由catalog确认，禁 session-log附加上传。也可 pi-ai Responses/Chat显式route。原始reasoning无摘要保证；自动压缩另耗额度，见 D9–D11、M1–M4 | **可接协议，适配需验，pi-ai Chat Completions优先**。base `https://open.bigmodel.cn/api/paas/v4`，api=openai-completions，model=glm-5.3-flash，apiKeyEnv、1M/128K、thinking compatibility；备选anthropic-messages到智谱兼容入口。工具流/思考保留与compaction预算必须实测；不依赖旧catalog。缓存从usage观察，见 D10、M5–M8 | **可接，pi-ai Responses或Chat**，按exact模型选择其支持格式、base、key或catalog登录。provider可能限制模型授权；确认函数调用、图像、reasoningEfforts、窗口；原生子代理由DSH loop提供，见 D10 | **可接，pi-ai anthropic-messages**，官方Anthropic API-key或支持的提供方catalog。context/output/thinking/cache配置按exact model，不能借Claude CLI订阅凭据推断可用，见 D10、C8 |

其他常见模型（如 Kimi、Qwen 和自部署开放权重）在本报告只做协议归类，**不声明具体新型号已验证**：只有 Chat Completions 的服务可直接走 DSH pi-ai，接 Codex 要 Responses endpoint/gateway，接 Claude 要 Messages endpoint/gateway；已有原生兼容端点则按对应列的能力验收。运行工具选择独立于模型，但实际设置选项应按协议和 capability 过滤，不能承诺任意笛卡尔积都可用。

### 5.1 两个推荐模型的官方细节及配置

**DeepSeek V4.1 Flash**：[官方定价/功能表 M1]明确 API ID 为 **`deepseek-flash`**，旧 `deepseek-v4-flash`/vision-exp 名称被当前版本接替。用户 CPA 的 **`deepseek-v4.1-flash` 是 CPA 标识**，不能原样假定在官方端点有效，也不能在没有 CPA 元数据/实测时假定窗口、图像或输出上限相同。

官方1M窗口、最大输出384K是服务上限，**不是每次运行应申请的输出量**。Responses 是 stateless：客户端发送完整历史；previous_response_id、conversation、store、background、include、truncation、context_management 不支持。reasoning.effort支持，summary被接受但不生成；reasoning输入仅明文content，summary/encrypted_content不支持；parallel_tool_calls被忽略且总是可并行。function支持，custom主要支持apply_patch及call_id配对；内置工具不能一概当OpenAI原生工具。developer当user，文件输入不支持；图像允许的位置有限。以response.completed/incomplete/failed等终结，不发送[DONE]。[M2][M3]

Messages 兼容支持工具调用和结果、thinking，但 budget_tokens、cache_control、禁并行等不是完整等价；document/redacted_thinking不支持，beta能力不能普遍照搬。Codex/Claude都必须保留模型运行所需的thinking replay在原生history，UI日志另作裁剪；不能为了不显示raw thinking而删掉运行必需上下文。上下文缓存为自动、尽力而为的精确前缀缓存，从prompt_cache_hit/miss等usage观察；不是Claude cache_control就地生效。[M3][M4]

**[设计] Codex受控配置形状**（仅示意，未创建运行配置；所有key均由vault注入）：

```toml
model = "deepseek-flash"
model_provider = "nipaplay-deepseek"
model_catalog_json = "<Nipa私有目录中的已验证catalog路径>"
cli_auth_credentials_store = "ephemeral"
[features]
shell_snapshot = false
[shell_environment_policy]
exclude = ["NIPAPLAY_MODEL_API_KEY"]
[model_providers.nipaplay-deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
env_key = "NIPAPLAY_MODEL_API_KEY"
requires_openai_auth = false
```

模型catalog从官方指南的版本约束和schema生成，声明Flash图像、1048576容量、effort、shell_command/apply_patch等能力；不能只把model名字塞入GPT catalog，也不要照抄指南内的大段GPT persona或启用raw reasoning显示。保持X52的env_key/vault策略，不采用文档中直接把bearer key写入TOML的示例。[M2]

**Claude + DeepSeek受控环境形状**：ANTHROPIC_BASE_URL设官方anthropic入口；ANTHROPIC_AUTH_TOKEN从vault读取；ANTHROPIC_MODEL与DEFAULT_OPUS/SONNET固定deepseek-flash[1m]，DEFAULT_HAIKU与CLAUDE_CODE_SUBAGENT_MODEL固定deepseek-flash。官方指南建议EFFORT_LEVEL=max、AUTO_COMPACT_WINDOW=786432，可作为可配置preset，先验成本/延迟后定默认。全部只作用于host启动的进程，禁止改用户全局shell和配置；本机wrapper问题见3.4。[M3]

**GLM 5.3 Flash**：[M5]明确ID `glm-5.3-flash`，1M上下文、128K最大输出、Function Calling、原生多模态，thinking.type只支持enabled；官方API建议effort=max、clear_thinking=false，Chat流建议stream=true/tool_stream=true。不能把“关思考加速”做成有效选项，也不能用开源权重model-card与API服务不同的建议互相覆盖。

国内智谱三个入口是不同地址：Chat `https://open.bigmodel.cn/api/paas/v4`；Messages `https://open.bigmodel.cn/api/anthropic`；Responses `https://open.bigmodel.cn/api/v1`。Responses默认store=false，有状态previous_response_id要store=true且有效7天；无cancel、无[DONE]，tool_choice只声明none/auto，schema包含function/namespace/custom/web_search及原始reasoning_text，**未声明Codex式summary/encrypted_content**。模型字段示例为glm-5.3，没有Flash专门允许清单；因此“Flash可以原生接Codex”是合理条件推断，不能标已证实完整兼容。[M6]

智谱Claude指南正文称默认映射Flash，但示例的别名可能指glm-5.3；Nipa应显式固定主、轻量和子代理模型到用户选定ID，核对init/usage实际model。GLM Coding Plan提供Flash但FlashX不是该套餐默认范围；API充值key和套餐/团队key不能假定互通，尤其不能把“有Messages套餐权限”推成“有Responses余额权限”。国际Z.AI的Messages为 `https://api.z.ai/api/anthropic`，本次没有找到可据以推荐国际Responses基址的一手资料；不从国内URL机械替换域名。[M7][M9]

GLM缓存为隐式自动机制，官方建议重复前缀至少500tokens，观察prompt_tokens_details.cached_tokens；不开缓存开关不代表每次命中。1M模型、完整工具schema、反复变化的记忆前缀会影响缓存与自动压缩，需要实际usage验收。[M8]

## 6. 是否需要内置接口转换层

**[判断] 推荐组合不应把通用转换层列为先决条件。** DeepSeek官方三种格式齐全；智谱有Chat/Messages/Responses，GLM→Codex先验原生端点。DeepSeek用户可选DSH，但继续选Codex也有原生路线，不能把“改用DSH”当作唯一解。

| 情况 | 判断 |
|---|---|
| Codex → DeepSeek官方Flash | 按官方Responses指南直连，无须Nipa转换层 |
| Codex → GLM Flash国内智谱 | 先做原生Responses一致性实验；失败字段若可用catalog/配置解决则不加转换。模型准入或custom工具缺失不能由UI宣称已解决 |
| Codex → CPA deepseek-v4.1-flash | **X52 已实测 Responses 路线及该 exact model 成功**，无需为确认格式再跑小请求，也不需为这一已证实路线内置转换层。沿用原证据；新 runtime 的工具能力、当前端点是否变化另验。不得读取凭据配置来重复确认 |
| Claude → DeepSeek/GLM官方Messages | 原生兼容端点，不需Nipa转换；功能差异由runtime/provider capability和参数preset处理 |
| DSH → 任一推荐模型的Chat/Messages | pi-ai或llm-deepseek已有协议adapter；Nipa控制桥是会话控制桥，不是模型协议转换层 |
| 用户坚持Codex+Chat-only，或Claude+只有Responses的服务 | 需要外部gateway或可选内置模型协议bridge；不能靠改base URL连通 |

**[设计] 若实验最终证明必须内置，限定为“本机模型传输bridge”。** 它在loopback暴露一类下游协议，把模型HTTP请求/响应转换到provider格式；工具实际执行、agent loop、会话存储仍由Codex/Claude/DSH管理。它不负责nipa能力调用、帮手编排或审批。

难点包括：function/custom/freeform apply_patch与JSON schema；并行tool_call ID、增量arguments、tool_result配对；SSE output_item/content/delta/done顺序与终态；原始reasoning replay和summary/encrypted字段的不同；图像/角色/文件映射；context/output预算、truncation和compaction；usage/cache计数、模型别名/实际model；429、quota、超时、断流与取消。Messages↔Responses↔Chat不存在所有字段的无损互换。bridge不能凭空提供推理摘要、子代理、服务器缓存、恢复或approval。

转换时上游断开应abort下游请求，但没有provider cancel不等于模型已经停止计费；中途有副作用的工具执行不能因HTTP失败自动重放。禁止记录认证头、整份prompt/环境作为默认debug，日志只留脱敏结构与有界片段。先做一个明确模型/工具组合的fixture与真实验收，证明必要后再泛化；不要为理论上的任意模型组合预建通用代理。

## 7. 中立 AgentRuntime 设计

以下是接口草案，**不是本次产品实现**。SessionRef将Nipa ID与native ID分离，RuntimeBinding将工具和模型分离。

```text
RuntimeBinding {
  runtimeKind: codex | claude | deepseekHarness,
  executable, runtimeVersion, harnessRoot, permissionPolicy,
  modelRoute: { provider, region, protocol, endpoint, modelId,
                credentialRef, catalogRevision, reasoning, budgets }
}

AgentRuntime {
  health(check: localOnly | paidModelProbe) -> HealthReport
  capabilities() -> RuntimeCapabilities
  createSession(meta) -> SessionRef              // 不发占位模型请求
  resumeSession(ref) -> SessionState
  listSessions(filter, cursor) -> Page<SessionInfo>
  history(ref, cursor) -> Page<NormalizedTurn>
  submit(ref, input, clientMessageId) -> MessageReceipt
  steer(ref, input, targetTurn, policy) -> SteeringReceipt
  interrupt(ref, targetTurn, cancelQueued) -> InterruptReceipt
  respond(interactionId, response) -> Receipt
  injectContext(ref, ContextRevision, boundary) -> ContextReceipt
  compact(ref, policy) -> Receipt               // capability可不支持
  delegate(ref, task) -> DelegationReceipt
  observeDelegation(id) / adoptDelegation(id)    // 分别声明能力
  events(ref, afterSeq) -> Stream<AgentEvent>
  closeSession(ref) / shutdown()
}
```

### 7.1 统一条目、状态和错误

`AgentEvent` envelope 包含 schemaVersion、runtimeKind、runtimeInstanceId、sessionId、turnId?、itemId?、seq、observedAt、nativeRef，以及kind/payload。Nipa seq只在一个session流中单调；native seq独立保存，不拿到达顺序当原生因果。正文与增量按itemId去重；UTF8/JSON分包处理后才归一化。

kind建议：sessionOpened/Recovered、inputQueued/Consumed/Cancelled、turnStarted/Settled、messageDelta/Completed、reasoningSummaryDelta、toolStarted/Updated/Completed、commandOutput、fileChanges、interactionRequested/Resolved、delegationStarted/Updated/Settled、contextInjected、compactionStarted/Settled、activityChanged、runtimeError。工具结果的“用户消息”外壳只作原生传输事实，不成为人类message。

命令payload为command、cwd?、stdout/stderr?、exitCode?、signal?、status、outputCompleteness；输出有界，截断显式。reasoningSummary仅接受provider标明的summary；rawThinking独立分类，默认不投影、不旁存。原生日志若运行工具必须保留思考，留在原生存储，不删改其恢复数据。帮手进度、计划、工具说明分别展示，避免把缺少摘要变成虚假“模型思考”。

turn状态有queued/running/awaitingInteraction/completed/failed/interrupted/incomplete；进程消失归incomplete，不能仅靠EOF推completed。session总活跃状态考虑foreground、queued、background tasks及子代理；native不报告完整后台集合时标unknown，不能假定空集合。steer返回acceptedAt、delivery=sameTurn/nextTurn/pending/rejected、nativeMessageId及appliedTurnId?；interrupt返回已中断目标、仍排队/已取消消息、仍在跑的后台任务及确定性。

错误分为binaryMissing/versionUnsupported、configuration/unsupportedProtocol、authentication、quota/rateLimited、providerUnavailable、contextLimit、permissionDenied、toolFailed、interrupted、transportLost、sessionNotFound/corrupt、unsupportedCapability。公开错误先脱敏，保留可操作原因及是否可重试；“key有效但账户没额度”与“协议不匹配”不能都叫连接失败。

### 7.2 capability 与所有权

不能只有supportsStreaming布尔值。应声明liveText、liveCommandOutput、reasoningSummary、history/coldResume/list、sameTurnSteer（含边界/条件）、interruptScope/queueCancel、manualCompact、contextInjectionBoundaries、nativeSubagentObservation/adoption、permissionCallbacks、images、tools、effectiveContextWindow、observedModel等，并附来源（declared/observed/verified）。模型route能力与runtime能力取交集。用户切模型不应自动获得原生子代理接管能力，换工具也不增加模型上下文。

**事实所有权**：runtime保管native transcript、compaction和工具执行；Nipa保管设备能力、授权、记忆文件/revision、任务回执、followup及会话路由。过程日志只保存脱敏的展示投影，按session/runtime稳定ID归档，不提供第二个模型对话事实源。

ContextRevision有revision/hash、来源preferences/index/settings/recent、字节预算、注入boundary、已确认native receipt。记忆改动在下一安全边界注入；压缩结束后下一请求前重注入常驻事实。hook与host直接注入需选一个owner并按revision去重，避免同一事实叠加三次。先查询实时能力与状态，记忆是提示，不覆盖nipa实时结果。

native helpers与Nipa独立helpers使用同一个DelegationRecord（origin、parent、ownerRuntime、childRef?、task/receipt/followup、可观察/可控制/可接管能力）。优先观察runtime已经创建的子代理，不重复启动。需要接管而原生child不可控时建立独立session并携带有界交接摘要；不能把Claude task_id塞到resume字段。

### 7.3 三个实现怎样接入

**Codex 第一实现**：把ChatHost transport、trust/hook、model defaults、rollout和native事件解释留在CodexRuntime；从next_runtime装配开始注入AgentRuntime。先让ChatPort接中立接口，临时为现有UI做有限旧事件投影，保证主会话、引导、中断、语义卡片和helpers无回归。逐步让ChatTurn直接消费typed events，移除原生method判断。liveness、recentMemoryFacts、ProcessStore、NativeHelpers改读中立数据。保留X49/X50/X52原来实验事实，用独立home/vault/catalog生成新provider preset，继续idle后切换和冷恢复。

**ClaudeRuntime**：配套SDK sidecar托管headless进程、input AsyncIterable、interactions、interrupt和history读取；sidecar将原生信息映射成typed stream。主会话和独立helper可以各有持久query进程；按资源限制懒启动，close不必删除session。按native uuid/priority处理引导回执，无法sameTurn则明示下一回合；不要在UI预先“成功”。非token命令输出按completed结果展示；task进度用于liveness；原生子代理先只观察。SessionStart compact提供memory保证，手动compact只有在配套SDK/CLI有稳定入口且实验成功后公开，不能用任意slash字符串假设成功。

**DeepSeekHarnessRuntime**：锁定alpha快照与配套依赖，full SDK profile加控制桥/Session Controller。桥提供明确resume/list/page/steer/cancel/queue清理、transient assistant frames、native compaction listener；复用已有agent/services而不fork整个loop。按实际seq映射turn和工具事件。说明候选只AGENTS，禁session-log附加上传，所有provider key用apiKeyEnv。纯SDK最小demo只能作为前置实验，不能满足完成标准。升级DSH时做protocol能力回归，不按name/version0.0.1猜兼容。

## 8. 一份 harness 同时给三者使用

**[仓库／设计]** 现有 `nipa` CLI、HTTP Actions、任务回执、mesh、记忆文件及下载/播放hooks已主要与agent工具无关，应保留其语义。agent只从harness运行shell调用`nipa list`、`nipa call ...`等实时能力，不把能力描述复制到模型协议转换层。

| harness元素 | 共享方式 |
|---|---|
| AGENTS.md | 保留唯一的用户经验/能力说明源；Codex直接读，Claude root CLAUDE.md用@AGENTS.md引用，DSH instructions显式只读AGENTS。已有用户harness升级先检测，不覆盖其经验文件 |
| 生命周期配置 | Codex .codex/hooks.json及hash信任；Claude .claude/settings.json；DSH原生context/compaction插件或部分hook bridge。共享的是记忆语义，不要求三份JSON完全同构 |
| 记忆payload | 一个runtime无关的构造器输出preferences/index/settings/recent及revision；各adapter包装为native SessionStart.additionalContext或下一step context。沿用X49有界读取原则，不塞完整历史 |
| 身份映射 | hook传native session_id先经Nipa映射到统一session；请求来源NIPAPLAY_CHAT→X-NipaPlay-Chat链保持。子代理身份由adapter验证，避免把child命令归主线程 |
| nipa调用 | CLI路径和本机端点由host提供，PATH平台差异在launch处理；认证仍在仓库外，不把模型key作为nipa认证或写进AGENTS |
| 领域hooks | 下载完成、新文件、播放等是Nipa业务hooks，保持现有任务回执；SessionStart/compact是agent生命周期hooks，二者无需同一个runtime插件 |
| 用户外部设置 | runtime-specific用户说明、MCP、skills可按用户选定来源加载；不能无提示地把一工具的记忆目录当三者共享存储 |

种子变化在将来实现阶段以可审阅迁移补丁交付，不由本次调研改种子。X50的“种子创建后用户维护”原则仍然成立；已有harness选择新工具时只提出/应用用户授权的适配文件，不覆盖AGENTS和业务工具。

## 9. 设置页：“agent 工具”先选，“模型”再选

**[设计]** 面板顺序为：agent工具 → 模型（DeepSeek V4.1 Flash、GLM 5.3 Flash置顶推荐）→ 提供方/账户类型与API key → 当前生效状态。现有用户迁移保留Codex和既有模型；新设置推荐先沿用成熟Codex实现与DeepSeek Flash原生Responses，GLM作为第二推荐，DSH/Claude显示适配成熟度。不要因为推荐DSH模型就强制用户切工具。

普通用户选官方推荐组合后，只需输入**所选提供方的一把key**：Nipa自动填端点、wire protocol、API模型ID、catalog、主/快捷/子代理别名和预算。DeepSeek key可在其官方三个格式入口复用；GLM需选择国内智谱/国际Z.AI、API余额/Coding Plan账户，按该账号权限确定入口。**一把key不是跨公司通用key，也不保证所有套餐/协议都有权限**。高级项允许CPA、自定义端点/model/catalog；CPA的deepseek-v4.1-flash显示独立provider标签，不能冒充官方模型ID。

将X52 source拆成：runtimeKind（agent工具）；modelSource（runtime原有配置／Nipa管理）；ModelRoute（provider/region/account/protocol/base/model/catalog/credentialRef）；RuntimeBinding（exe/version/harness/权限）。`codex`不再同时代表工具与模型来源。vault按provider+规范化endpoint+账号类型作用域保存，UI仅显示hasKey，不能读回明文；避免同名provider换地址误用旧key。process环境注入时保留必要PATH和nipa来源，去掉无关provider凭据和覆盖变量；禁止snapshot/debug把key落盘。

**[仓库／设计]** 当前实验室的 `LabModelVault` 实际只在内存保存模型key，因为原实验室vault会写明文文件（[host_settings_service.dart:460](../../../lib/next/settings/host_settings_service.dart)）。因此“一次填key跨重启使用”还不是现状；实现阶段若要记住key，应接入合适的系统安全存储并验证三平台行为，否则明确说明退出后需重新填写。三种工具的shell/tool子进程还要分别验证key排除机制，不能因Codex已有shell_environment_policy就推断Claude/DSH也会隔离。

界面明确“已保存／等待当前工作结束／当前生效”，当前工具版本、model/provider取运行握手或可观察响应，不从输入值推断。模型切换在所有受影响sessions/helpers idle后应用；工具切换只作用于新绑定，未完成helpers/followups继续由原工具拥有。新工具有独立main/current和native历史，用户可以回看原会话。跨工具继续使用同一份harness记忆及有界交接摘要，**不是原生历史无损迁移**。

按钮分为“检查安装与配置”（无模型请求）及“真实连通性测试”（说明可能用额度，主控取得预算授权后执行）。X52 checkModel/probe会发送真实模型回合；不能拿它做本次无额度诊断。保存key不自动发探测。失败区分exe被wrapper改环境、协议/模型不匹配、鉴权/余额、工具支持缺失；不让用户填三个base URL，也不以通用“连接失败”掩盖真正原因。

## 10. 其他值得考虑的工具

| 候选 | 一手资料中的可驱动接口 | 支持判断 |
|---|---|---|
| Goose | `goose acp` stdio；`goose serve` 的`/acp`可HTTP/WebSocket；ACP有会话/消息/取消及能力协商，实际支持按Goose扩展参考核对 | 最值得排第四。先将AgentRuntime映射ACP做无额度fixture；不要用one-shot headless代替多回合控制。无需为前三者先实现ACP总线。[R1] |
| OpenClaw | Gateway WebSocket握手/认证/scopes，`sessions.list`、`chat.send`、`chat.history`、`chat.abort`及run事件；包含完整助手、渠道、调度栈 | 能驱动，但与Nipa的memory/任务/mesh职责重叠。用户已有Gateway时做外接runtime有价值，首批不内嵌整套栈。[R2] |
| OpenHands | 官方Software Agent SDK的agent-server，HTTP/WebSocket conversation/events，可local或container宿主 | 更适合后续远程帮手/mesh。沙箱进程到宿主nipa能力的连通与凭据需设计，初期成本高于前三者。[R3] |

## 11. 分阶段计划与真实实验验收

2026-10-14 根据主控转交的“开箱即用”决定调整阶段顺序：**阶段一先交付随 NipaPlay 提供的固定版本 Codex、DeepSeek V4.1 Flash 官方直连，以及 GLM 5.3 Flash 原生 Responses 验证**；Claude Code、DeepSeek Harness 后续作为切换选项。默认推荐路线不引入转换层，只有第6节所述确实无法直连的组合才考虑。分发和配置详见新增第14节。

下列均为**未来实验计划**，本次没有执行模型请求，也没有构建或启动产品。所有阶段先用公开类型/脱敏fixture验证，再用真实模型；fixture通过不作为真实支持的证明。指标按“工具+版本、provider+账户+protocol+exact model、harness revision”记录，包含token/缓存usage、耗时、actual model、hook/context revision、工具与消息回执，不保存key/认证URL/raw thinking。

| 阶段 | 工作与真实实验 | 验收条件 |
|---|---|---|
| P0：无额度准备与已有证据复用 | 锁定 Codex 原生产物、LICENSE/NOTICE、hash和schema；准备自管home、两份provider/catalog preset和脱敏fixture。**CPA Responses + deepseek-v4.1-flash 的连通、错误key检查、同条件来源切换直接复用 X52**，X49/X50同条件hook/信任事实也复用。模型传输以官方Responses为阶段一目标，不先做Messages/Chat矩阵 | 无需用户安装Node/npm/Codex；三平台产物版本/架构可识别；配置语法与模型catalog符合固定版本；旧config和凭据未复制；依赖、签名与许可清单完整。体积/许可证证据见第14节 |
| **P1：内置 Codex 与两个官方推荐模型** | 实现内置原生 Codex 的默认定位、保险库和配置生成；沿用现有app-server能力并抽取够用的runtime边界。使用 **DeepSeek官方key + deepseek-flash** 直连 `api.deepseek.com/responses`；使用 **国内智谱API key + glm-5.3-flash** 验 `open.bigmodel.cn/api/v1/responses`。不依赖用户PATH里的Codex，不以CPA替代官方验证。实验清单见11.2 | 干净macOS/Windows/Linux只选提供方、填一把key即可开始；DeepSeek功能实测通过；GLM模型准入、工具/补丁、reasoning replay、历史与中断全部达到相同验收条件后再标默认可用。任何失败保留精确限制，不以initialize成功或普通文本成功替代工具循环验收 |
| P1b：抽象完善与受影响回归 | 将event/history reader/process store/liveness/helpers统一；旧UI投影短期保留。用两个已获准官方route只补改造影响的引导、两帮手并行、过程保存、语义卡片和模型idle切换 | 主/当前会话一致，消息不重复，steer实际delivery正确；command/output/exitCode或unknown诚实；compact/重启后resident facts revision可见；原生与Nipa帮手不重复；保留P1与X49–X52已通过证据，不重新烧额度跑无变化项 |
| P2：ClaudeRuntime | 配套2.1.289 SDK sidecar、明确exe选择。优先DeepSeek Flash Messages，GLM Flash Messages同组对照；测默认next、now后台化、later、中断+queued cancellation、AskUserQuestion/权限、Bash/subagent task事件、cold resume/list、compact后SessionStart | 首个模型请求已有指定memory marker；compact后重注入一次；wrapper环境覆盖可诊断；请求receipt和turn归属正确；tool_result不变成人类消息；task_id不当顶层session；未知exitCode不伪造；任一摘要不可用仍可正常对话 |
| P3：DeepSeekHarnessRuntime | full SDK profile+controller/core桥，先锁定版本；DeepSeek Flash优先可用官方Messages或CPA/pi-ai route，GLM Flash用pi-ai Chat/Messages。测create/resume/list/page/live frames、steer/cancel及inbox清理、jobs、native helpers、compaction memory barrier | 不靠SDK复用ID伪造冷恢复；没有取消后悄悄执行的queued消息；live流与durable历史对齐；session log附加上传关闭；首请求/压缩后memory有revision；native权限与控制桥一致 |
| P4：产品选择与端到端能力 | 三工具×两推荐模型，先相同nipa list/状态/媒体查询，再用用户确认的真实BT内容源、受控下载目标、完成回执及库查询；有下载运行时发送改目标/停止，随后重启恢复。测试设置页一把key、工具切换、模型idle切换、旧历史回看、凭据撤销 | 六组合逐项记录可用/降级/失败及原因；授权后任务完成、重复执行为0、来源/回执可追踪；记录拒绝及理由，不能以绕过工具出错当作成功。转换层仅在原生端点确实阻塞且目标组合必须支持时立项 |

真实实验设置有界输出/回合数/并发和经主控批准的token/金额上限；压缩、标题、子代理和web search也可能产生模型调用。推荐effort=max先按提供方建议验证，再对比成本/延迟决定Nipa默认，不能把“Flash”理解成始终无思考开销。压缩测试可用缩小阈值/窗口在测试harness触发，**无需为覆盖1M窗口故意烧满上下文**。

### 11.1 需要主控向用户申请的额度/凭据

| 资源 | 已知情况 | 主控需要申请什么 |
|---|---|---|
| CPA deepseek-v4.1-flash | X52 已实测该模型经Responses成功；本次复用证据，未读凭据或重复发请求 | **只为未来新增实验申请额度/金额与调用范围**，不重跑已有连通性/错误key/同条件切换测试。若用户明确授权凭据位置，脚本内部读取，不用cat/print，不写入证据；输出仅脱敏能力/状态。现有可用key不等于已授权本次付费探测 |
| **阶段一：DeepSeek官方Flash** | 官方支持原生Responses；CPA结果不能证明官方endpoint结果 | **必须向用户申请DeepSeek官方API key和阶段一预算**，模型ID为deepseek-flash。只在受控脚本/保险库读取，不要求贴进对话；明确回合/金额上限，并覆盖工具循环及压缩调用 |
| **阶段一：GLM 5.3 Flash** | 本次没有可用key，Flash+Codex完整一致性未实测 | **必须向用户申请国内智谱开放平台API key及预算，确认具有Responses/Flash调用权限**。阶段一不以仅Coding Plan套餐key或国际Z.AI地址替代国内Responses；若用户只有套餐key，先核对其权限，不默认花API余额 |
| Claude/GPT原生对照 | 非本次推荐模型优先项，无用户额度授权 | 仅需比较或保证回归时申请相应API余额/既有授权；不自动使用Claude订阅，SDK产品登录约束另按C10处理 |
| BT真实任务 | 完成率/拒绝行为未实验 | 申请具体内容源、目标路径与下载任务授权；可先用用户认可的开放分发样本验证链路，再按真实工作流验收；不要从模型选择推断对具体下载的授权 |

本报告不替主控发送额度申请，也不运行这些实验。研究交付到此即可完成；实现阶段应逐项补实验记录，未验证的格子保留状态。

### 11.2 阶段一的范围和验收实验

本阶段的产品范围是“应用自带可运行的Codex，用户选DeepSeek或GLM并填一把官方key即可工作”。默认native executable和固定catalog随应用提供；首次使用不下载Codex、不打开终端安装npm、不要求ChatGPT登录。Claude/DSH只保留后续切换路径，转换层也不作为本阶段必需工作。

| 验收实验 | 输入条件与观察 | 通过条件／复用边界 |
|---|---|---|
| A1：干净系统和国内网络 | 未来在macOS ARM64/Intel、Windows x64、Linux x64的干净安装上禁止访问GitHub/npm，保留所选官方模型入口可达；系统不预装Codex、Node、Python，使用打包产物 | 不执行远程安装脚本，不需要全局PATH/WSL；nipa入口和记忆执行器也可用。离线可完成runtime安装/配置检查；模型回合需网络，不承诺离线推断。签名/公证与安装增量在这一未来打包实验实际测量 |
| A2：DeepSeek官方最小完整工具循环 | 获授权后用deepseek-flash：一次nipa list/状态查询、一次工具结果续答、两次并行无副作用工具、一次测试文件apply_patch及图像输入 | 请求确为官方Responses，actual model正确；call_id/result和SSE终态一致，补丁文件正确；没有provider配置回落或OpenAI登录。本实验是官方route新证据，不能由CPA普通对话替代 |
| A3：GLM原生Responses准入及工具一致性 | 获授权后用glm-5.3-flash跑A2同组，并单列custom/freeform patch、reasoning输入回放、model/output cap、tool_choice/并行字段及第二轮完整history | 模型获准调用、首轮及工具续答均成功；不能只用glm-5.3样例推Flash成功。失败先判断catalog/schema字段调整是否可解决；确实不可连通或工具格式不可表达才按第6节立项bridge，期间该preset保持“待验证” |
| A4：会话、引导、中断与恢复 | 两个官方route分别跑一轮长shell输出中途改目标/停止，再退出并恢复同thread；有排队消息、后台帮手时检查实际停止范围 | 当前工作状态/receipt准确，历史/主会话ID稳定，不重放有副作用工具；原生无cancel入口时说明下游计费停止不可由UI保证。X52同条件CPA来源切换不重复，新的official-route恢复必要项单列 |
| A5：记忆和压缩 | 使用测试harness里独特的preferences revision marker，首请求、真实进程恢复、受控compact后的下一请求前核对注入；不要烧满1M窗口 | 常驻事实来自当前磁盘，hook只按实际边界运行，旧偏好不被摘要复活；X49/X50已证明的Codex基线语义复用，只测新打包环境/route/adapter所影响部分 |
| A6：key生命周期和X52泄露回归 | 保存/重启/更换/撤销key；新建shell工具及native helper；检查用户配置、自管home、snapshot、journal、进程参数、公开错误和代理重定向。负向检查用fixture/已授权的最小新增请求 | 系统保险库持久化有效，key没有被写进TOML/catalog/种子/日志；shell不继承模型key，未生成携密钥snapshot；错误不会静默回落；没有认证请求被转发到重定向域名。已有CPA错误key请求不重跑 |

阶段一需要的两把实验key分别属于DeepSeek官方、国内智谱官方；实际用户只选其中一家，填写该家一把key。额度由主控申请，本次没有提前读取或使用这些key。

## 12. 一手资料与证据索引

所有URL最后读取日期：**2026-10-13**。官方页面是当前文档快照，不声称未来一直不变。正文的[C]/[D]/[M]/[R]/[O]指下表；源码永久链接均锁定上述DSH commit。

| 编号 | 一手来源 |
|---|---|
| O1 | OpenAI [Codex app-server](https://developers.openai.com/codex/app-server)、[配置参考](https://developers.openai.com/codex/config-reference)；使用openai-docs技能的Codex manual helper，快照见[codex-manual](../evidence/x59/codex-manual/codex-manual.md)。本仓库X49/X50/X52验证的Codex版本为0.144.1，未在本次重新发模型请求 |
| C1 | Anthropic [Headless](https://code.claude.com/docs/en/headless)、[CLI reference](https://code.claude.com/docs/en/cli-reference) |
| C2 | Anthropic [TypeScript Agent SDK](https://code.claude.com/docs/en/agent-sdk/typescript)、[Streaming input](https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode)；[0.3.289公开类型](../evidence/x59/claude-sdk-types-0.3.289/sdk.d.ts) |
| C3 | Anthropic [Sessions](https://code.claude.com/docs/en/agent-sdk/sessions)；SDK priority、interrupt receipt及停止语义同C1/C2 |
| C4 | Anthropic [SDK permissions](https://code.claude.com/docs/en/agent-sdk/permissions)、[permission modes](https://code.claude.com/docs/en/permission-modes) |
| C5 | Anthropic [Memory／CLAUDE.md／AGENTS.md](https://code.claude.com/docs/en/memory) |
| C6 | Anthropic [SDK subagents](https://code.claude.com/docs/en/agent-sdk/subagents) |
| C7 | Anthropic [Hooks reference](https://code.claude.com/docs/en/hooks)、[How Claude Code works](https://code.claude.com/docs/en/how-claude-code-works) |
| C8 | Anthropic [Authentication](https://code.claude.com/docs/en/authentication)、[Model config](https://code.claude.com/docs/en/model-config) |
| C9 | Anthropic [LLM gateway](https://code.claude.com/docs/en/llm-gateway)及[gateway protocol](https://code.claude.com/docs/en/llm-gateway-protocol)，已核对Messages/云提供方格式、SSE顺序与自定义模型窗口假设 |
| C10 | Anthropic [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)，订阅登录及公开菜单品牌原文见[快照](../evidence/x59/official/sdk-overview.md) |
| D0 | DeepSeek [官方仓库快照](https://github.com/deepseek-ai/deepseek-harness/tree/d743267388641bc76f17c45ce8b4c231aed1d32c)及[package.json](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/package.json) |
| D1 | [SDK profile](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/bundle/sdk-app/README.md)、[protocol types](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/sdk/protocol/src/types.ts) |
| D2 | [SDK server](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/sdk/server/src/server.ts)，尤其session创建、followup及事件订阅 |
| D3 | [Session Controller](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/api/session-controller/README.md)、[commands.ts](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/api/session-controller/src/commands.ts)（steer约364、cancel约523）、[core agent](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/core/agent/README.md) |
| D4 | [Session event types](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/core/session/src/types.ts)、[Bash tool](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/shell/tool-bash/src/index.ts) |
| D5 | [Permission presets](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/interaction/permission-presets/README.md) |
| D6 | [Agent instructions](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/context/agent-instructions/README.md) |
| D7 | [hooks-codex源码](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/experimental/hooks-codex/src/index.ts)、[README](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/experimental/hooks-codex/README.md)、[hooks-claude-code源码](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/experimental/hooks-claude-code/src/index.ts) |
| D8 | [Compaction](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/compaction/compaction-basic/README.md) |
| D9 | [DeepSeek provider](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/llm/llm-deepseek/README.md)、[model info](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/llm/llm-deepseek/src/model-info.ts) |
| D10 | [pi-ai multi-provider](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/llm/llm-pi-ai/README.md)、[provider guide](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/docs/user/guide/providers.md) |
| D11 | [Session-log upload](https://github.com/deepseek-ai/deepseek-harness/blob/d743267388641bc76f17c45ce8b4c231aed1d32c/packages/session/session-log-deepseek/README.md) |
| M1 | DeepSeek [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing/)（当前Flash API ID、版本、窗口、输出、三格式支持） |
| M2 | DeepSeek [Codex integration](https://api-docs.deepseek.com/quick_start/agent_integrations/codex/)、[Responses API guide](https://api-docs.deepseek.com/guides/responses_api/)、[create-response](https://api-docs.deepseek.com/api/create-response/) |
| M3 | DeepSeek [Claude Code integration](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/)、[Anthropic compatibility](https://api-docs.deepseek.com/guides/anthropic_api/) |
| M4 | DeepSeek [Context caching](https://api-docs.deepseek.com/guides/kv_cache/)、[Thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/) |
| M5 | 智谱 [GLM-5.3-Flash/FlashX](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash)、Z.AI [Flash guide](https://docs.z.ai/guides/vlm/glm-5.3-flash) |
| M6 | 智谱 [Responses介绍](https://docs.bigmodel.cn/cn/guide/develop/responses/introduction)、[创建Response schema](https://docs.bigmodel.cn/api-reference/response/%E5%88%9B%E5%BB%BA-response)、[OpenAPI](https://docs.bigmodel.cn/openapi/openapi-responses.json)；模型示例及能力限制已核对，Flash+Codex未实测 |
| M7 | 智谱 [Anthropic兼容](https://docs.bigmodel.cn/cn/guide/develop/claude/introduction)、[Claude Code与Coding Plan](https://docs.bigmodel.cn/cn/coding-plan/tool/claude) |
| M8 | 智谱 [上下文缓存](https://docs.bigmodel.cn/cn/guide/capabilities/cache) |
| M9 | Z.AI [Claude Code](https://docs.z.ai/devpack/tool/claude)；地区/套餐入口分别核对，不能假定与国内共用key |
| R1 | Goose [ACP client guide](https://block.github.io/goose/docs/gdk/acp/)；[源码发现索引](../evidence/x59/goose-source-index.json)，公开快照见[goose-acp](../evidence/x59/official/goose-acp.md) |
| R2 | OpenClaw [Gateway protocol](https://docs.openclaw.ai/gateway/protocol)、[Session control RPC](https://docs.openclaw.ai/gateway/protocol/rpc-session-control) |
| R3 | OpenHands [Agent server](https://docs.openhands.dev/sdk/guides/agent-server/overview)、[Server architecture](https://docs.openhands.dev/sdk/arch/agent-server)；具体抓取URL/重定向见[sources-other-runtimes](../evidence/x59/sources-other-runtimes.json) |

证据目录另含：workspace-baseline；Claude help/version及npm公开类型来源（匹配CLI的是0.3.289）；33份DSH公开文件与manifest；Codex manual；官方文档正文；sources/sources-sdk-corrected/sources-extra/sources-other-runtimes/sources-models记录。早期platform SDK URL重定向到overview，已用code.claude.com的正确SDK页面补查，判断以corrected manifest为准。抓取脚本只访问公开文档，不读取key、不调用模型；一次OpenClaw路径404已更正并成功保存。

**完成状态**：本次交付的是可审阅设计与证据。推荐组合的协议事实、现有代码耦合及适配缺口已定位；CPA Responses及deepseek-v4.1-flash连通/切换直接复用X52真实证据。六组合完整端到端能力、CPA的其他协议、新工具控制语义、GLM Flash Responses一致性、BT任务行为仍保留为未来实验证据项。

## 13. 主控追加决定与续接记录

2026-10-13 收到“继续完成 x59b”的指令后，核对了当前 worktree、git 状态、已有报告及证据索引。基线提交仍为 `2ae4a0af0c2e4e7aa710d010c18ff7443f1693c5`；X59 报告已完整写入，续接前证据目录共122份文件，最近记录为 artifact-checks.json。已有资料与检查结果直接复用，没有重新抓取文档、重跑CLI检查或发起模型实验。

**主控后来追加了两个用户决定，本报告据此扩展设计：**（1）“推荐模型”：Codex、Claude Code、DeepSeek Harness是三种agent工具，模型独立选择，默认推荐DeepSeek V4.1 Flash或GLM 5.3 Flash；（2）2026-10-14“开箱即用”：NipaPlay默认提供一个固定版本Codex，普通用户只选DeepSeek/智谱、填写该家一把API key即可使用推荐模型，Claude/DSH是可切换选项，只有确实无法直连的组合才考虑转换层。

第11节已按新决定把内置Codex和两个官方Responses路线放到阶段一，新增第14节记录分发、体积、许可、签名和预置配置；其余章节保留原调研内容。**x59本轮没有新模型实验**，已有X49/X50/X52真实实验及失败记录按原证据复用。真实模型验证仍由主控取得两家官方key/预算后执行，不把计划写成已完成实验。

### 13.1 已有实验复用与新增验证边界

**复核纠正了此前“CPA 是否支持 Responses 尚未知”的错误判断**：X52 的真实切换明确用了 Responses，managed/original 两回合实际模型均为 deepseek-v4.1-flash，provider 分别为 nipaplay/cpa，均 completed。以下已完成项直接复用，不消耗额度重复运行。

| 已有实验与来源 | 可以沿用的观察 | 仍需新增验证的变化条件 |
|---|---|---|
| [X49 hook、compact、resume](../X49_REPORT.md) | Codex0.144.1同server已加载thread的resume不重跑SessionStart；真实进程重启resume重跑；compact后下一回合重新注入当前记忆；旧偏好变化通知有实测 | Claude/DSH生命周期和注入边界不同，必须验证；新adapter改变Codex注入/恢复路径时才补受影响回归，不重新比较同条件缓存百分比 |
| [X50 信任与种子](../X50_REPORT.md) | 新CODEX_HOME需项目trust及project hook currentHash信任；种子可读且hook执行；原config保持不变 | Claude无同样hash门，DSH兼容插件有覆盖差异，需各自首次请求memory barrier实验；用户harness迁移不能由旧种子测试替代 |
| [X52 protocol.json](../evidence/x52/protocol.json) | Codex0.144.1的wire_api=chat无效，initialize成功不足以证明provider生效；responses配置有效 | 新Codex版本需按配置schema决定回归；DeepSeek/智谱新的原生Responses不能被旧Chat结论否定 |
| [X52 experiment.json](../evidence/x52/experiment.json) | CPA Responses+deepseek-v4.1-flash成功；正确/错误key检查；模型来源切换后实际model/provider、同thread/main、两轮历史及原config不变 | 不证明官方DeepSeek端点、GLM、CPA Messages/Chat、新runtime工具循环、推理摘要和完整上下文/缓存行为；后续只补这些缺口 |
| [X52 隔离与泄露修复](../X52_REPORT.md)及[delivery-scan.json](../evidence/x52/delivery-scan.json) | shell snapshot曾落下凭据，关闭后扫描无泄露；实验模型vault为内存，原已通过小请求没有重复执行 | Claude/DSH子进程和日志路径不同，必须验证各自凭据排除；不能把Codex隔离结果推广到三者 |

这次续接只读取脱敏实验材料，未读取原凭据、未重新启动实验程序。所复用 X52 证据的内容哈希与边界见 [reused-experiments.json](../evidence/x59/reused-experiments.json)。

## 14. 开箱即用

追加日期：**2026-10-14**。本节按用户新决定设计：**NipaPlay默认就提供Codex，普通用户只选择DeepSeek或智谱并填该家一把API key，Nipa即可使用推荐模型工作。** Claude Code、DeepSeek Harness是可切换选项；转换层只服务第6节判定确实不能直连的组合。本节为研究设计，没有实际打包、签名、公证、安装或使用官方key。

### 14.1 分发推荐：随应用打包固定的原生运行包

**[设计] 推荐默认随应用打包，按操作系统和CPU架构发包。** Nipa发布流程获取并验证上游固定版本的原生产物，完整打入应用；用户第一次使用不访问GitHub/npm、不执行远程安装脚本、不需要全局安装Codex/Node/npm或ChatGPT登录。直接以绝对路径运行native `codex app-server`，保留配套文件的相对布局；不要将npm的JS启动器当作内置Codex而额外要求用户安装Node。

**固定版本首验基线为0.144.1**：它是本机实装及X49–X52已有实验版本，也满足DeepSeek指南的≥0.144.0要求。该数字是本次适配/体积基线，不能把它等同“最新版本”。发布时锁定通过两个官方route、三平台签名与恢复实验的确切版本，记录tag、平台/架构、上游digest、catalog/schema revision及Nipa最终产物hash；应用更新一起升级，禁止首次运行自动抓latest。

| 方案 | 国内网络、版本与用户体验 | 本次判断 |
|---|---|---|
| 随应用打包 | 安装Nipa后runtime已齐备，首次对话仅依赖所选官方模型端点；安装包更大，但版本、签名、许可和恢复行为与应用一起验收 | **默认方案**。Nipa安装包本身也应有用户可达的正式下载渠道，不能把依赖GitHub的问题只转移到应用下载 |
| 首次使用下载 | 首次启动增加约115–138MiB的平台包下载；GitHub/npm可达性无法保证，断网/中断/代理/完整性失败都阻塞首次使用；macOS还须处理独立下载helper的签名与公证 | 可选精简版或高级安装方式，不能作为普通用户默认。若提供，必须从Nipa受控HTTPS镜像下载固定版本，有校验、恢复和完整离线包 |
| 用系统已有Codex | 用户自行维护PATH/版本；npm wrapper可能依赖Node，任意升级会改变协议/catalog/恢复 | 高级选项，仅用户明确选择后使用；默认不被PATH里别的Codex覆盖 |

本次未在国内网络实测，不能声称GitHub/npm必然被阻断或某个镜像已可用。设计上由Nipa发布端获取上游，提供可达的自有/CDN镜像和完整安装包；镜像能力需要发布基础设施实现，不编造现成域名。镜像只改变分发位置，不改变来源验证：固定上游版本/digest先核对，重新签名后另外记录Nipa产物hash，更新manifest由Nipa签署。运行中的runtime不热替换，先等所有主/帮手idle，保留旧版本以恢复失败时回滚。

### 14.2 三平台实际体积、许可证与签名

**[实测／官方发布元数据]** 2026-10-14测量固定 **Codex0.144.1**。本机macOS ARM64原生`codex`为 **260,405,808字节**；npm JS入口仅7,236字节，不能用于估计。其vendor目录还包含code-mode-host、rg、zsh和包元数据，共 **311,566,632字节**。Linux/macOS其他架构的binary大小读取官方tar header，Windows.exe大小来自官方release asset metadata；完整平台包解包总量来自官方npm的dist.unpackedSize，压缩量读取实际平台tarball字节数。没有安装或执行下载的二进制。[B1][B2]

| 平台/架构 | codex二进制：实际字节（MiB） | 完整原生平台npm包解包量：实际字节（MiB） | 平台包压缩传输量：实际字节（MiB） |
|---|---:|---:|---:|
| macOS ARM64 | 260,405,808（248.34） | 311,569,963（297.14） | 120,299,266（114.73） |
| macOS Intel x64 | 282,836,688（269.73） | 337,129,194（321.51） | 128,728,164（122.76） |
| Linux x64 musl | 298,520,624（284.69） | 351,529,018（335.24） | 131,162,436（125.09） |
| Windows x64 MSVC | 341,200,688（325.39） | 409,157,780（390.20） | 145,088,030（138.37） |

MiB=1,048,576字节。平台npm包包含vendor及少量README/package.json，**不含Node运行时**；内置时取完整native目录并补许可文件。上述给出了真实Codex载荷：安装占用约297/335/390MiB，压缩包约115/125/138MiB（macOS ARM64/Linux/Windows）。**它们不是最终DMG/MSIX/AppImage增量的实测值**；最终安装格式的压缩、重新签名和去重不同，必须在11.2 A1的未来打包实验分别量出“带/不带runtime”的最终文件差。本次不构建，因此不伪报精确安装包增量。Linux/Windows ARM64需另取该架构产物并测量，不能套x64数字。macOS推荐分架构安装包；若现有发布必须Universal，可装两份完整native目录，原生载荷约618.65MiB，另测压缩增量，不用lipo后假定原签名仍有效。

完整平台包比单个codex二进制大，是配套工具真实占用。先以官方完整native目录为交付单位，不为缩包盲删code-mode-host、rg、zsh或Windows辅助exe。未来若只部署较小的独立app-server产物，须另证实版本、依赖、命令/帮手功能与恢复等价，不能把其体积替代当前`codex app-server`方案。

**许可证义务 [官方]**：Codex固定tag的LICENSE为Apache-2.0，允许二进制再分发；第4节要求随分发交付许可证副本，保留适用归属/版权等通知，有修改的文件标明改动，随带可读NOTICE。此tag的NOTICE还列出源自Ratatui的MIT代码归属。Nipa包中应有离线可读`third_party/codex/LICENSE`、`NOTICE`和该版本配套依赖的许可证清单，在“开源许可”可查看；默认下载安装与镜像均附相同材料。[B3]

不能只带根Apache文本就忽略平台包内rg、zsh及其他依赖自己的license。发布流程核查该tag依赖和配套二进制的许可证，收集MIT/BSD等适用归属，GPL组件按其实际许可履行源代码或有效供源义务；不把Apache“可分发”解释为所有附件都只有Apache。该版本来源、原始hash、重新签名/修改记录及完整许可清单是发布验收项；本次没有完成全依赖许可审计，不宣称已有可发布的完整清单。独立进程边界也不代替许可证义务。API账户条款与代码许可分别处理。

**macOS [官方／本机观察／设计]**：本机ARM64二进制已有OpenAI Developer ID签名、hardened runtime标志及时间戳，[只读签名记录](../evidence/x59/distribution/local-mac-signature.txt)已保存；这不证明Nipa的新bundle已公证。放在应用标准嵌套可执行代码位置（例如`Contents/Helpers`中的完整runtime目录），确认每个Mach-O及配套helper的签名有效，必要时由发布CI以Nipa的Developer ID签署，并正确保留所需entitlements。按**内层helper→外层应用→分发容器**完成签名，启用hardened runtime与secure timestamp，提交notarytool公证并对适合的应用/分发容器staple；最终验证签名、Gatekeeper与干净系统的真实helper启动。不能靠`codesign --deep`一把签名或用户移除quarantine替代正确流程；公证后不再在.app内下载/改写runtime/config。首次下载方案的helper也要有独立可验证签名/公证票据，存用户Application Support，不改已签.app。[B4]

**Windows [官方／设计]**：使用原生MSVC exe和所有匹配架构的辅助exe，公共分发用受信任CA的Authenticode签名或可用地区/账号的Microsoft Artifact Signing，对Nipa主程序、内置PE/helper与安装器校验签名并加可信时间戳；MSIX外包也需按发布渠道签名。上游exe的签名状态必须实际检验，不能仅凭“来自OpenAI”假定已满足Nipa发布条件。Microsoft当前文档明确**EV证书不再保证免SmartScreen提示**，有效签名也可能需积累信誉；不能承诺首次分发绝不弹窗。微软商店MSIX与独立MSI/EXE的签署责任不同，按实际渠道验收。用户端不需要开发证书、npm或WSL。[B5]

### 14.3 两个官方模型的预置配置

**[设计]** 普通入口只有“DeepSeek / 智谱”和key输入。host默认使用应用内固定native路径；为用户profile创建Nipa私有`CODEX_HOME`，内部有原子写入的`config.toml`和`models.json`。不复制用户`~/.codex/config.toml`/auth文件，不运行提供方会改全局配置的一键脚本。用户选择信息只存provider/model/catalog revision/credentialRef；key进入Nipa生产保险库，启动子进程时短暂取出，经`NIPAPLAY_MODEL_API_KEY`环境传给Codex，禁止argv、TOML、catalog、harness和日志含key。

| 用户选择 | model | provider ID / name | base_url（Codex自动追加responses） | protocol与凭据 |
|---|---|---|---|---|
| DeepSeek V4.1 Flash | **deepseek-flash** | nipaplay-deepseek / DeepSeek | `https://api.deepseek.com/` | wire_api=responses；env_key=NIPAPLAY_MODEL_API_KEY；requires_openai_auth=false |
| GLM 5.3 Flash（国内智谱API） | **glm-5.3-flash** | nipaplay-zhipu / 智谱 | `https://open.bigmodel.cn/api/v1` | 同上；**不是**Chat的`/api/paas/v4`或Messages的`/api/anthropic` |

“base”不能已经含`/responses`，避免双拼接；host按白名单preset生成，普通用户不手填路径。国际Z.AI和Coding Plan仍是高级账户/route选项，不能由智谱普通API key的默认配置自动推断其Responses权限。一位用户选择一家只填一家key，阶段一测试两家需要两把分别授权的官方key。

以DeepSeek为例的生成配置形状如下；路径是host展开后的绝对路径，schema按固定0.144.1检验，key不在文件里。[B6]

```toml
model = "deepseek-flash"
model_provider = "nipaplay-deepseek"
model_catalog_json = "/absolute/nipaplay/profile/codex-home/models.json"
model_reasoning_effort = "high"
model_reasoning_summary = "none"
cli_auth_credentials_store = "ephemeral"

[features]
shell_snapshot = false

[shell_environment_policy]
exclude = ["NIPAPLAY_MODEL_API_KEY"]

[model_providers.nipaplay-deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
env_key = "NIPAPLAY_MODEL_API_KEY"
requires_openai_auth = false
supports_websockets = false
```

智谱仅将model/provider ID/name/base替换为表中值；同一套隔离规则保留。高档effort是候选初始值，提供方建议max的成本/延迟在阶段一对比后再定默认；GLM不提供无效的“关闭思考”选项。`supports_websockets=false`使阶段一使用已文档化SSE入口。harness cwd、danger-full-access/never和项目trust/hook hash继续由已有host控制面按用户Next授权传入，不能用上述provider文件取代X50双重信任机制。

**model catalog不是可省略的美化文件。** 固定版本的`ModelInfo`需要slug/display_name、supported_reasoning_levels、shell_type、visibility、supported_in_api、priority、base_instructions、supports_reasoning_summaries、support_verbosity、truncation_policy、supports_parallel_tool_calls、experimental_supported_tools等字段；生成完整`{"models":[...]}`，不是仅写model ID和窗口两项。加载发生在进程启动时；per-thread config改变catalog路径不会重新应用，模型变更要沿用X52的idle→重启transport→原rollout恢复路径。[B6]

| catalog差异 | DeepSeek preset | GLM preset |
|---|---|---|
| 精确slug与容量 | deepseek-flash；官方Codex指南给1048576 context_window/max_context_window及95% effective比例 | glm-5.3-flash；官方模型标1M，初验按不超过1,000,000的保守整数配置，确认服务确切容量后锁定；不偷用GPT或旧GLM catalog |
| 推理 | low/high/max候选；summary API不生成，因此supports_reasoning_summaries=false、default_reasoning_summary=none。原生history仍保留必要reasoning回放 | 按提供方支持的low/high/max及不可关thinking；summary/encrypted能力未宣称，先false/none；以真实reasoning round-trip验收 |
| 工具 | 官方指南的shell_command、freeform apply_patch、并行工具及图像；不复制其GPT身份persona或启用raw reasoning展示 | shell/函数/图像基于协议证据配置；custom/freeform apply_patch及并行一致性为准入实验，不预填“已验证”。0.144.1的apply_patch_tool_type枚举只有freeform，不能编造function字符串 |
| instructions和预算 | 使用Nipa中立基础指令，项目规则来自唯一AGENTS；初始保留官方truncation/有效窗口机制，实际请求预算另验，不把384K服务输出上限当每回合默认 | 同样使用Nipa基础指令和AGENTS，按128K服务输出上限留预算余量；unknown能力不冒充Claude/GPT。不得沿用X49失败实验的18K压缩阈值 |

DeepSeek指南提供可用catalog模板，但本次已见其中supports_reasoning_summaries=true与Responses兼容表“summary接受但不生成”存在差异，Nipa按后者处理显示能力并在真实请求验收；这不影响模型运行所需的原生reasoning保存。GLM preset先作为待验证candidate随开发构建提供；A3通过后才转为普通用户默认可用的推荐项。若custom工具不兼容，先试固定版本确实支持的工具配置和原生API参数调整；没有验证过的fallback不能宣称已解决，更不为理论差异先引入全协议转换层。

**保险库和工具入口是开箱即用的组成部分。** X52的LabModelVault只存内存，不能直接满足普通用户“填一次、重启继续用”；生产应使用已有系统保险库，macOS/Windows/Linux各验保存、取回和撤销，Linux无可用安全后端时明确不持久化，不静默落明文。现有种子`nipa`及SessionStart脚本依赖Python3，干净Windows/macOS不保证有解释器；阶段一必须提供随应用可运行的nipa入口与记忆执行器（host原生执行器/配套CLI，或经过许可与签名验证的解释器），不能把“另装Python”藏在只填key流程里。若选择额外打包解释器，其体积另计，不能包含在上表Codex数字中。

### 14.4 官方key是否仍会遇到X52的问题

| X52发现或限制 | DeepSeek/智谱官方key的影响 | 本方案如何衔接 |
|---|---|---|
| wire_api=chat无效，initialize成功会掩盖配置回落 | **与key来源无关，仍会发生**。两家现有原生Responses解除的是过去仅Chat地址的协议缺口，不会修复填错base/model | 两个固定Responses preset、schema校验、实际provider/model观察；不静默改用OpenAI |
| shell snapshot捕获环境key并落盘 | **官方key也有相同风险**，不是CPA特例 | 保留shell_snapshot=false、shell_environment_policy.exclude、ephemeral auth和全新自管home；新的打包版本必须做A6，所有native helper一起检查 |
| 实验室vault明文后端与内存替代 | **与DeepSeek/智谱无关**，Lab内存key退出即丢 | 用户默认生产系统保险库；实验环境继续用内存/明确安全后端，不复制含key配置 |
| 模型切换、主/帮手并发与rollout恢复 | 官方route不会自动消除状态一致性问题 | X52已有idle等待、experimentalApi/thread.resume.path、同thread恢复方案复用；catalog启动加载要求相同；只补受影响official-route实验 |
| CPA名字与提供方别名 | CPA的deepseek-v4.1-flash不等于DeepSeek官方ID；智谱套餐和API权限也不同 | 官方DeepSeek固定deepseek-flash，智谱固定glm-5.3-flash并明确API账户；key有效但模型/额度无权时分开显示 |
| checkModel的小请求成功不证明完整工具能力 | **两家官方key都仍适用这一限制**，尤其GLM Flash/custom/reasoning兼容未实测 | 不在保存key时自动消耗额度；无额度配置检查与获授权后的A2/A3真实循环分开；普通文本成功不足以发布 |

### 14.5 本节新增一手来源与证据

读取日期均为 **2026-10-14**，与第12节保留的2026-10-13资料分开记录。

| 编号 | 来源与可核实内容 |
|---|---|
| B1 | OpenAI [Codex0.144.1 release](https://github.com/openai/codex/releases/tag/rust-v0.144.1)，API asset size/digest和tar header；[分发测量manifest](../evidence/x59/codex-distribution.json)。release压缩digest是上游公布值，部分archive只读header，未宣称下载全量并校验其digest |
| B2 | OpenAI官方npm [包元数据](https://registry.npmjs.org/@openai/codex/0.144.1)，四个架构的具体version、tarball、integrity、unpackedSize见[distribution](../evidence/x59/distribution/)和B1；压缩byte count是本次公开下载只读计数，未安装到全局 |
| B3 | 固定tag [LICENSE](https://github.com/openai/codex/blob/rust-v0.144.1/LICENSE)、[NOTICE](https://github.com/openai/codex/blob/rust-v0.144.1/NOTICE)，本地[LICENSE](../evidence/x59/distribution/LICENSE)/[NOTICE](../evidence/x59/distribution/NOTICE)；配套依赖的完整许可审核是发布计划，未伪称已完成 |
| B4 | Apple [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[TN2206 Nested Code](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)，快照与hash见[signing-sources](../evidence/x59/distribution/signing-sources.json) |
| B5 | Microsoft [Code signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)、[SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)，同上；未将签名承诺为免所有系统提示 |
| B6 | Codex固定版本 [config.schema.json](https://github.com/openai/codex/blob/rust-v0.144.1/codex-rs/core/config.schema.json)、[ModelInfo类型](https://github.com/openai/codex/blob/rust-v0.144.1/codex-rs/protocol/src/openai_models.rs)；本地[配置schema](../evidence/x59/distribution/config.schema.json)和[model类型](../evidence/x59/distribution/openai-models.rs)。提供方base/模型/能力仍引用第12节M1/M2/M5/M6的一手快照 |

本轮只新增本节、更新第11和13节；第1–10及12节按原文保留。正式分发、签名、公证、两家官方key实验和最终安装包差分大小，均由未来阶段一实际验收。
