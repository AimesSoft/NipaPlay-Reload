# Y15：Next 默认 agent 是否从 Codex 换成 pi / DeepSeek Harness

调研与实验日期：2026-10-20，Asia/Taipei。对象：**Codex 0.144.1、pi 1.3.0、DeepSeek Harness（DSH）0.2.1-rc.2**。后两者为实验开始及结束核对时的 npm `latest`；没有把旧名 `@mariozechner/pi-coding-agent` 的版本当成新版 pi。真实模型固定为用户 CPA provider 的 **DeepSeek V4.1 Flash**，API ID `deepseek-v4.1-flash`。

## 结论与建议

**暂不更换默认 agent。保留 Codex；把 pi 原生 RPC 作为下一优先级的可选运行器。现在没有实验依据把 pi 或 DSH 宣布为第四轮沉默问题的修复。**

1. **Codex 的编码包袱确实重，而且可以剥掉不少。** 在同一份 Nipa 种子下，带种子 SessionStart hook 和 live web search 的首请求约 **12,852 个估算 token**；pi 默认约 **4,331**，DSH 完整 SDK profile 约 **7,865**。Codex 基础指令本身 20,751 字符，含持续解决问题、编辑、补丁、测试、计划和代码交付指导。pi 也自称编码助手，DSH SDK 也有编码 persona；三者都不是开箱即用的看片人格。
2. **更轻与更及时回复是两件事。** 无提供方错误的下载中插话样本里，Codex 首次出声为 9.1–42.2 秒（3 次）、精简 Codex 为 25.1–33.8 秒（3 次）、pi 为 12.0–23.7 秒（仅 2 次）；DSH 整条文字提交为 40.7–67.2 秒（3 次，计时接口不同）。pi 的请求更小，工具和控制面也更适合嵌入；但它仍会先查状态或补做工具操作。精简 Codex 没有产生稳定的即时回复优势。不能据此断言“主要是 Codex”，也不能把剩余原因全归到模型：样本小，种子、假接口、模型和提供方都参与决定行为。
3. **pi 是值得适配的备选，DSH 不是本题的优先迁移目标。** pi 原生 `--mode rpc` 已有 steer、follow-up、取消、清队列、会话切换与压缩，不需要先绕过 ACP 社区转换器。它能显著降低固定上下文成本。DSH 的默认工具面更大；要有同回合 steer 和完整停止语义，仍要维护控制桥。其最小 profile 确实很小，但默认不加载 AGENTS.md，不能拿这个数字直接与完整 Nipa 比。
4. **最先应改的是宿主与 agent 的任务边界。** 下载受理与“用户现在就能看”必须分开；卡住时先回已有事实，把后续观察交给后台事件。用户问进度时，宿主可以直接展示 NipaPlay 已有的确定状态，必要时提供“先停下并汇报”的明确动作。仅把消息 steer 进去，三家都不会保证模型先输出一句话。

建议落地顺序：先在现有 Codex 上移除编码基础指令并选择性关闭不需要的工具，同时验收中途问进度的行为；再做 pi 原生 RPC 适配和同条件验收。**切换默认应以行为验收为门槛，而非以系统提示长度为门槛。** 本次不改任何 NipaPlay 产品代码。

## 1. 实验范围、夹具与证据

已有的接入生态、许可、分发比较直接复用 [ACP 调研](research/ACP.md) 和 [X59 运行时设计](research/AGENT_RUNTIMES.md)。这里只补固定版本请求、真实模型行为、pi 原生 RPC，以及 DSH 新版相对旧调研的变化。

所有安装、原始 HTTP 请求体、完整事件、第三方源码/提示、测试脚本均在 `~/.nipa-next/y15/`。仓库证据仅含原创摘要、计量、哈希和原创实验脚本的压缩包；**不包含第三方提示原文、源码、SDK 或真实端点/key**。假端点同时实现 `/v1/responses` 与 `/v1/chat/completions`，记录完整 JSON 请求，再返回固定中文回答。真模型实验使用同一个 loopback 转发器，脚本仅在内存中读取真实 provider 地址和 key，只转发给配置中的提供方；日志不记录 Authorization。

各次运行有独立的 HOME、CODEX_HOME、pi 配置目录、DSH_HOME、XDG 目录和工作目录。正式运行还用 macOS `sandbox-exec` 限制嵌套 agent/工具只能向实验根目录写文件、只能连接 loopback；模型外部访问由父转发器完成。没有启动 NipaPlay，没有连接真实片库或用户 harness。

### 1.1 同一份种子

实验期间工作区的 AGENTS.md 被外部更新过一次，本任务没有修改它。旧版首请求捕获另行保留；**报告表格使用补抓的新版本，正式行为组也全部使用这一版本**：

- 5,111 字符，SHA-256 `131a9e869dcd5f3b8dde550a0969ce019d95353cbf7de307f2c5f54c01705a36`。
- 已固定在实验根目录的 `seed/AGENTS.md`，后续不再随工作区变化。
- 新版明确要求忙时被插话先回复，并说明下载停滞会通过后续回来。这意味着本实验甚至比第四轮种子更强调及时回复；它不是第四轮的原样重放。

### 1.2 假 NipaPlay

假 `nipa` 同时接受 `nipa download add/status` 和种子的 `./nipa call download.add/download.status` 写法。片库为空，目录返回唯一来源：《孤独摇滚！》第 01 集、1080p、简体中文、450 MB，列表标称 12 seeds。创建前没有下载；创建后始终 0 peers、0 字节、速度 0，停滞分钟数从 3 随时间增加。种子是实验用的无效占位 magnet，不会发起真实 BT。

`status`、`describe`、搜索、卡片、任务等返回离线假数据。外部发现脚本也只返回同一来源。相同的 `memory/preferences.md` 告知 1080p、简中、第一集优先，并已授权选择唯一来源开始下载；`memory/MEMORY.md` 告知后台下载。它们通过假状态和读文件可见。行为组不单独给 Codex 启用记忆 hook，以免额外的生产上下文成为组间变量；种子 hook 另有首请求捕获。

用户输入固定为“我想看《孤独摇滚！》”，侦测真实 `download.add` 后 **2 秒**发送“怎么样了？”。忙时分别使用 Codex `turn/steer`、pi `steer`、DSH 原生 core 的 next-step steer。初始阶段最长观察 120 秒，插话后最长 120 秒。若 agent 已结束而未下单，记录“未下单”，后续问进度属于新回合，不能混入下载中的插话指标。

预跑发现过“查询来源误带了未创建下载的状态”的夹具问题，已修正；预跑不用于正式比较。部分真实请求遇到提供方 429，失败与补样都保留，不将它们算作 agent 沉默或成功回复。

## 2. 第一份实际请求：包袱在哪

估算使用 `tiktoken o200k_base`，**不是 DeepSeek 官方 tokenizer**。数字统计发送文本与 JSON 工具 schema，不含无法获知的提供方内部封装，不能当作账单。固定假回答中的 usage 是夹具值，不参与这些估算。实际真模型 usage 另列。

| 配置 | 基础 `instructions` 字符 | system/developer 合计字符 | 其余种子注入 | 工具 schema 估算 token | 首请求文本+工具估算 token |
|---|---:|---:|---|---:|---:|
| Codex 内核基线 | 20,751 | 24,172 | user，含种子与环境 | 4,286 | 12,615 |
| Codex：种子 hook + live web | 20,751 | 24,598 | user，含种子与环境 | 4,297 | **12,852** |
| Codex：只替换基础提示 | 66 | 3,512 | 仍有种子与环境 | 4,286 | 8,301 |
| Codex：基础提示 + 关子代理/goals | 66 | 3,542 | 仍有种子与环境 | 1,167 | 5,190 |
| pi 默认 | — | 8,140，**含种子** | 合并进 developer | 601 | **4,331** |
| pi：自定义提示 + 仅 bash | — | 5,469，**含种子** | 仍合并进 developer | 115 | 3,265 |
| DSH `sdk` | — | 2,567 | user，种子+运行上下文 | 4,159 | **7,865** |
| DSH `sdk-minimal` | — | 46 | **默认没有种子** | 351 | 400 |
| DSH minimal 补回说明发现 | — | 46 | user，重新有种子 | 351 | 3,493 |

路径、环境与模式提示也占字符，配置变体的 developer 字符数因此略有变化。Codex 内核基线关闭 web search、无 hook；“种子 hook + live web”另外使用现有种子配置、原来的 `session_start.py` 和假的 memory client，并按宿主相同的 hook hash 信任步骤启动。**记忆 marker 确实出现在首份模型请求中**，不是只验证 hook 进程运行过。

pi 和 DSH 的两种 API 路径都实测返回固定回答。pi Chat 首请求约 4,341 个估算 token，DSH Chat 约 7,918；不是只比较帮助文案。Codex 0.144.1 本次使用其原生 Responses 路径，没有把它伪装成 Chat 客户端。

### 2.1 Codex 0.144.1

实际 wire 为 `instructions` + `input` + `tools`。基础提示明确面向编码，包括 AGENTS 作用域、计划、编辑与补丁、测试/lint、代码风格、最终代码交付，以及“问题解决完再结束回合”的持续执行要求。它也要求事前告知与定期更新，所以不能把其中只有持续执行的一半视为模型唯一收到的要求。

本次内核基线声明 9 个顶层工具条目，展开 namespace 共 **13 个可调用函数**：`exec_command`、`write_stdin`、`update_plan`、`request_user_input`、`view_image`；`multi_agent_v1` 下的 `close_agent/resume_agent/send_input/spawn_agent/wait_agent`；`get_goal/create_goal/update_goal`。种子 live 配置再加 `web_search`。这个模型/配置组合没有声明 `apply_patch`；不能把其他 Codex 模型的工具清单套过来。

AGENTS.md 实际在 **user-role 上下文块**内注入，另有 developer 层的权限和运行指导。不要因为基础提示对 AGENTS 的描述使用了另一种措辞，就忽略实际 wire。用户 CPA catalog 的目标模型条目只有模型列表元数据，没有替代基础指令。

实测 `thread/start.baseInstructions` 和 `model_instructions_file` 都能把基础指令替换为本次自写的 66 字符提示；后者首请求同样约 8,301 个估算 token。**替换不会清空工具 schema、权限/协作模式 developer 消息、AGENTS 或环境。** `developerInstructions` 是叠加层，不是基础指令替换。

再关闭 `features.multi_agent`、`features.multi_agent_v2`、`features.goals` 后，本次只剩 `exec_command/write_stdin/update_plan/request_user_input/view_image`，约 5,190 个估算 token。没有实测到 pi 式任意内置工具 allowlist；动态工具是添加能力，不能据此推断能替换整个内置工具集合。若要只暴露一个 Nipa 工具，Codex 比 pi 更难做到彻底。

### 2.2 pi 1.3.0

默认提示仍有编码助手身份、文件读写与精确编辑规则、工具用法、pi 自身文档入口。它没有 Codex 那么长的编码执行与交付规范。默认工具为 **`read/bash/edit/write`**；本次使用干净 home，并关闭扩展、skills、MCP 和模板发现，避免加载用户额外资源。隔离 home 本身没有这些资源。

AGENTS.md 放进结构化 `project_context`，随系统提示通过所选模型 adapter 变成 **developer message**。`--system-prompt` 替换默认主提示后，**AGENTS 和 cwd 仍在**；`--append-system-prompt` 只是叠加。`--no-context-files` 才关闭说明文件发现。`--tools bash` 可以把四工具降到一个，`--no-tools` 可清空；自定义工具、RPC/SDK 活跃工具设置和扩展还可进一步定制。这是 pi 对 Nipa 最实在的结构优势。

### 2.3 DSH 0.2.1-rc.2

`sdk` 基于完整 `base`，默认系统提示包含 harness 身份、编码 persona、读写/编辑规则、后台 shell job 管理、web 工具、goal 和子代理指导。它的系统文本不算长，**工具声明才是主要固定成本之一**。

本次 macOS 完整 SDK 共 **25 个工具**：`bash`、`create_goal`、`edit`、`exit_plan_mode`、`get_goal`、`glob`、`grep`、`interrupt_agent`、`job_kill`、`job_list`、`job_output`、`list_agents`、`read`、`read_image`、`send_message`、`skill`、`subagent`、`subagent_fork`、`todo_write`、`update_goal`、`web_fetch`、`web_search`、`workflow`、`working_directory`、`write`。

说明发现插件把 AGENTS.md 包在独立 **user-role reminder** 中，cwd 等运行事实另注入 user context。profile 是有序 bundle/patch，不是只换一句身份提示。修改 `personaPrefix` 仍保留其他插件的 guidance；要完整替换可用 system-prompt registry 的 complete section，工具也要单独裁剪，不能把 personaPrefix 误作完整覆盖。

`sdk-minimal` 本次只声明 `bash/read_image/working_directory`，但默认没有 AGENTS。补挂 `agent-instructions` 后，首请求从约 400 增到约 3,493 个估算 token，说明最小化可行，但必须自行维护组合。**与 X59 旧快照不同，当前 minimal bundle 已含 compaction-basic 和图像压缩插件**，不能沿用“minimal 没有压缩”的旧结论。完整 SDK 的行为对照没有换成 minimal。

本次所有 DSH 配置关闭 `session-log-deepseek` 与 package inventory 上传插件，提供方显式用 pi-ai 的 Responses/Chat route；不把 DeepSeek 官方 Messages 路线的能力外推给 CPA。

## 3. 真实模型行为

**正式尝试共 18 次：Codex 4、精简 Codex 6、pi 5、DSH 3。** 其中 11 次同时满足已下单、下载中插话、无提供方错误；另有 6 次受 429 污染、1 次未下单。pi 只有两次无错误的该场景样本，不能声称完成了三次无错误验收。下面先列可直接比较的观测，失败不隐藏。

| 样本 | 插话入模秒 | 首次可见文字秒 | 下单至首次回合结束秒 | 工具调用：总数/插话后 |
|---|---:|---:|---:|---:|
| codex-1 | 11.6 | 13.7 | 25.3 | 11/4 |
| codex-2 | 1.1 | 9.1 | 11.9 | 8/2 |
| codex-4 | 0.8 | 42.2 | 44.8 | 11/5 |
| codex-slim-3 | 2.5 | 30.3 | 34.8 | 5/1 |
| codex-slim-4 | 32.0 | 33.8 | 36.3 | 6/2 |
| codex-slim-6 | 23.6 | 25.1 | 72.1 | 9/4 |
| dsh-1 | 0.2 | 67.2 | 69.2 | 13/6 |
| dsh-2 | 1.8 | 40.7 | 42.8 | 12/6 |
| dsh-3 | 1.0 | 50.8 | 52.8 | 13/4 |
| pi-1 | 0.6 | 12.0 | 15.2 | 13/3 |
| pi-2 | 2.6 | 23.7 | 26.5 | 10/4 |

这些成功样本在下单后 2 秒插话时都还在运行，随后才结束回合；没有把后台 BT 完成作为本轮必需条件一直等到超时。可观察到的区别是额外查状态/查来源与出声的先后。各组并未形成“pi 必然立刻结束、Codex 必然守住下载”的分界。

| 同一工作回合分账 | 初始阶段 input/output token | 已消费插话后 input/output token |
|---|---:|---:|
| codex-1 | 60,865 / 1,780 | 76,933 / 1,231 |
| codex-2 | 58,402 / 1,423 | 52,064 / 588 |
| codex-4 | 93,116 / 1,505 | 118,969 / 1,265 |
| codex-slim-3 | 39,761 / 412 | 24,092 / 166 |
| codex-slim-4 | 41,136 / 360 | 12,458 / 67 |
| codex-slim-6 | 40,166 / 380 | 61,836 / 544 |
| dsh-1 | 40,786 / 925 | 92,711 / 1,274 |
| dsh-2 | 37,795 / 711 | 59,720 / 1,470 |
| dsh-3 | 61,122 / 1,128 | 63,597 / 1,223 |
| pi-1 | 47,174 / 1,413 | 29,196 / 1,133 |
| pi-2 | 31,117 / 864 | 35,744 / 984 |

排除项仍属于已执行的正式尝试：

| 样本 | 事实 | 首次可见文字秒 |
|---|---|---:|
| codex-3 | 初始回合正常结束但只请用户选来源，没有下单；问进度变成新回合 | 59.0 |
| codex-slim-1 | 提供方 429，插话前没有完成下单；不参与延迟/优劣比较 | 18.6 |
| codex-slim-2 | 提供方 429，插话前没有完成下单；不参与延迟/优劣比较 | 35.1 |
| codex-slim-5 | 提供方 429，插话前已下单；不参与延迟/优劣比较 | — |
| pi-3 | 提供方 429，插话前已下单；不参与延迟/优劣比较 | — |
| pi-4 | 提供方 429，插话前已下单；不参与延迟/优劣比较 | 105.2 |
| pi-5 | 提供方 429，插话前已下单；不参与延迟/优劣比较 | — |

429 原文指提供方上游候选账号限额或禁用；没有据此推断 pi 或精简提示本身会触发限额。初轮并行四组，补样改为顺序，仍有 429。原始失败计量、所有逐请求 usage 与重试都保留在压缩证据；未返回 usage 的失败请求不补造 token。

### 3.1 如何解释这些数

“入模”是本地端点第一次收到带有第二条用户消息的请求；“回复”是客户端第一段非思考文字。Codex/pi 按流式文字事件计时，DSH 本次桥复用 SDK 的已提交 assistant 事件，所以是**整条消息提交时**；它没有接上 transient token frames。DSH 延迟不能直接当作纯模型速度排名。完整事件、请求时间与回合结束时间均保留，可区分排队、模型采样和工具执行。

token 按提供方返回的 Responses usage 统计，输入包括缓存命中部分，没有从累计输入中扣掉缓存。中途 steer 仍可能属于同一个宿主回合，因此表中将同一工作回合按“模型尚未消费插话 / 已消费插话”分账；二者相加才是该回合总量。压缩证据保留逐请求 usage、宿主 turn ID 与结束状态，避免把每次采样误叫一个用户回合。CPA 的 reasoning 计量不完整，不能从 reasoning_tokens 为 0 推断没有思考。

这些样本测的是可重复的离线下载停滞场景，没有重现真实 tracker/网络排障的完整 15 分钟链路。下载后 2 秒插话也会影响自然结束时间；“还在忙”不等于它在没有插话时必然无限等待。表中的下单至结束与额外状态查询，描述实际观察到的继续工作，不作这个反事实推断。

### 3.2 能支持的判断

- **接收消息与回应消息不同。** 正式样本能核实新输入进了模型请求，之后仍可能先调用工具。更换 steer 实现本身不会给出“先回答、后排查”的模型行为保证。
- **pi 的主要已证实优势是上下文和可裁剪性。** 当前实验没有证明它能消除沉默，也没有证明短提示必然优于长提示。不同样本与提供方延迟的差异，不能用三个样本算成稳定性能排名。
- **DSH 同样存在完成倾向和不可靠归因。** 有样本在没有额外网络证据时就把 0 peers 归因为源无做种，甚至排除了网络问题；这与夹具的“只知道连不上”不相符。换 harness 不会自动修复模型把猜测当事实的倾向。
- **精简 Codex 不是充分条件。** 移除基础编码提示后仍有继续检查、延迟才回答的情况。剩下的工具指导、种子对完整作品的要求、模型策略都有可能参与，不能通过一个变体完成全部因果拆分。

### 3.3 第四轮原记录说明了什么

原记录中第二条用户 message 实际位于第 220 行，用户消息事件位于第 221 行，时间 **2026-10-17 12:08:11.235 UTC**；第 219 行是 token 统计。接着模型已识别用户在问进度，却继续安排排查。到 **12:15:03.738** 才有 `turn_aborted`，相隔 **412.503 秒**，期间没有用户可见的回复。停止后还有一条新的用户消息“先停一下，告诉我现在什么情况？”，随后才得到总结；不能把这段总结当作 abort 自动产生的响应。

那一刻输入计量约 **139,002 tokens**，其中 **138,624** 为缓存输入；这是长工作链，不只是首包固定提示。记录能排除“消息根本没送到模型”这一解释，也能说明仅有“先告知用户”的种子语句不足以约束其行动。它不能独自证明换 pi 一定有效。本次新版种子更强调先回复，仍观察到跨运行器的同类倾向。

## 4. 能否作为 NipaPlay 后台 agent

| 需求 | Codex 0.144.1 | pi 1.3.0 原生 RPC | DSH 0.2.1-rc.2 |
|---|---|---|---|
| 宿主驱动 | 现有 app-server，已有产品实现 | JSONL stdio，适合 Dart 子进程；prompt 接收成功不代表工作完成 | SDK JSON-RPC；完整控制仍需 core/controller 桥；ACP 能力复用 X62 结论 |
| 中途插话 | `turn/steer` + expectedTurnId；下一可处理边界，不能改写正在进行的采样 | `steer` 在当前 assistant 工具批完成后、下一次 LLM 请求前消费；`follow_up` 等工具与 steering 都耗尽 | SDK `session/prompt` 是 followup；本次小桥显式转 `agent.steer()` 才有 next-step 语义 |
| 停止 | `turn/interrupt`；已有 Nipa 映射 | `clear_queue` 后 `abort`；只 abort 可能继续消费队列 | SDK 无 per-session cancel；桥调用 core cancel，并明确处理 inbox；不能用 kill 整进程替代多会话取消 |
| 工作结束 | turn/completed | 用 `agent_settled` 判断不再自动继续；仅 agent_end 不足 | 结合 session status、turn/end 和子任务 settlement；messageId 只是入队回执 |
| 恢复 | 复用 X49/X59/X62 证据 | `--session`、`switch_session` 等；原生 JSONL 会话/分支 | **新版 SDK 已有 session/resume**，本次冷恢复成功；仍没有 SDK list/read 全套历史面 |
| 压缩 | 原生自动/手动压缩；已有 hook 约束 | 默认按 contextWindow−16,384 触发，保留近期约 20k；RPC compact 与扩展事件可控 | compaction-basic，配置容量阈值/保留比例；完整与当前 minimal 都有，但客户端控制面仍需适配 |
| 记忆 | 现有 SessionStart startup/resume/clear/compact | 不能直接照搬 Codex hooks.json；用扩展在每次请求注入最新磁盘记忆 | 当前 npm CLI 不自带旧 hooks-codex；用自有 context/pre-step 插件并验压缩/恢复边界 |
| 自定义模型 | Responses provider，当前产品已有隔离与 vault | models.json 明确 api/baseUrl/model/key 引用；Chat、Responses 均已假端点跑通，真模型用 Responses | llm-pi-ai route 指定协议/baseURL/apiKeyEnv/model；不能只替换一个 model 名字 |

### 4.1 原生控制实验

用假模型先返回一个运行 2 秒的工具，再接受宿主消息：

- **pi steer**：第二份请求约在插话后 2.01 秒出现，既有工具结果也有 steer marker。
- **pi follow_up**：第二份请求先处理工具结果而没有 follow-up；第三份请求才含 follow-up。它不是“立刻改当前采样”。
- **pi 清队列+停止**：`clear_queue` 返回被清掉的 steer 内容，随后 abort，没有第二次 HTTP 模型请求。
- **DSH core steer 桥**：第二份请求约在插话后 2.06 秒同时包含工具结果与新输入。没有把 SDK followup 冒充 steer。

DSH 桥是实验目录中的原创薄层：复用原来的 SDK server/transport，只给 core 增加 steer/cancel 入口，不重写 agent loop、不重新执行工具。行为实验的 DSH 结果是这条路线，不代表裸 SDK 或 ACP 也有相同能力。

### 4.2 记忆与冷恢复实验

pi 用一个原创扩展在 `context` 事件读取当前 preferences 与 MEMORY.md，注入 request-local 消息。修改磁盘 marker 后，下一请求能看到新版。另用足够长的假对话实际执行 RPC `compact`，确认产生一次压缩模型调用；压缩后仍注入新版记忆。关进程再按 session 文件重开，session ID 相同，历史保留，首请求仍有新版 marker。**这里只证明注入生命周期与保留路径，固定回答不会验证摘要内容质量。**

DSH 则在新进程调用 `session/resume` 恢复旧 SDK session，未发送输入就恢复成功；历史没有作为新事件重放，随后请求仍含旧 steer marker。X59/X62 的“SDK 没有冷恢复”结论只适用于其旧版本，需要在这个小点上更新。没有因此推断 SDK 已有完整历史分页、原生同回合 steer 或单会话取消。

## 5. 分发、维护与迁移成本

许可与更广的安装/ACP 生态见 [ACP 报告及其证据](research/ACP.md)。本次新增版本核对如下；体积为本机独立 npm 安装目录的**逻辑文件字节**，排除符号链接、npm 缓存、模型会话和系统 Node，不能与压缩下载大小混用。

| 项目 | 本次版本/发布时间 | 本机 npm 安装闭包 | 平台与运行要求 |
|---|---|---:|---|
| Codex | 0.144.1，产品固定版本 | 约 297.2 MiB | 原生可执行文件；已有 X59 的 macOS/Windows/Linux 分发设计可复用，不以 npm wrapper 的 Node 当原生运行必需 |
| pi | 1.3.0，2026-10-15 | 约 106.3 MiB | npm 路线 Node ≥22.19.0；release 另有 macOS/Linux/Windows 的 arm64/x64 包。macOS arm64 原生包已实测在没有 Node 的 PATH 下跑通 RPC |
| DSH | 0.2.1-rc.2，2026-10-17 | 约 674.7 MiB | Node 插件树较大，本版本 release 无二进制 assets；沿用 X62 记录的源码根要求：22.x ≥22.19，或 ≥24；顶层 npm 包未声明 engines。此次用 Node 24 跑通 |

pi release 压缩资产约 29.6–31.98 MiB（macOS）、40.6–40.7 MiB（Linux）、41.7–43.0 MiB（Windows）。本次下载的 macOS arm64 包含 77,085,026 字节的 Mach-O 可执行文件；在 `PATH=/usr/bin:/bin` 的隔离环境中启动成功，并跑通原生 RPC→假 Responses 对话，**可以不额外捆绑 Node**。不过该资产的 `--version` 返回 **0.0.0**；分发应固定 release 资产哈希，不能仅按这个输出验版本。正文行为实验仍全部使用 npm 1.3.0，没有混用这份原生资产。

原生 Windows 的默认 bash 路线需要 Git Bash；也有 PowerShell 工具，需要相应选择和适配，不能承诺和 macOS 一样的命令。DSH 的工具选择按平台切换 Bash/PowerShell；Windows/Linux 本次只核对发布与源码，不冒充三平台实机通过。

本机原有 Node 23.11.0 启动 DSH CLI 会无输出退出：发布入口依赖 `import.meta.main`，在此 Node 上没有执行入口。隔离安装 Node 24 后成功。Nipa 分发应固定已验收的 LTS，避免只做宽泛版本比较。实验另装的 Node 目录约 292.8 MiB，含安装载体内容，不是最终捆绑 Node 二进制的大小。

截至查询时 pi 与 DSH 上游均未归档，pi 最近 push 为 2026-10-20，DSH 为 2026-10-17；这只能说明近期仍维护，不是支持承诺。pi、DSH 为 MIT，Codex 为 Apache-2.0；沿用已有许可清单并在真正分发前核对新增依赖。

### 5.1 如果以后采用 pi，NipaPlay 要做什么

1. 按 X59 抽出运行器接口，新增原生 RPC transport，映射 prompt/steer/follow-up、流式消息、工具、错误和 settled；不用 pi-acp 的下一回合队列假装同回合引导。
2. 停止操作清队列再 abort；等待真实 settlement，并处理仍存在的后台工具。切换/恢复会话时处理 replay，避免重复执行产品副作用。
3. 提供 Nipa 专用 system prompt 与工具选择。初期保留 bash/必要读取，进一步可将 `nipa` 封成自定义工具；不要无条件开放编辑器技能、MCP 和第三方扩展发现。
4. 把现有记忆 hook 换成已验收的 pi 扩展：启动、恢复、压缩及每次请求前读最新记忆，限长、去秘密、处理 revision。同步改掉种子中“Codex 管历史”的绑定措辞。
5. 保留用户 endpoint/key vault 的隔离方式，生成临时 models.json 和环境引用；只把本地代理凭据交给模型进程，防止工具继承真实 key。迁移旧 Codex 历史需要单独的导入/保留方案，不能直接打开原 rollout 当 pi session。
6. 选定分发路线：npm 路线固定 Node、pi 包与依赖锁，原生路线固定 release 资产与哈希，并验扩展兼容。完成三平台命令、签名、恢复、断流、取消和模型兼容验收。GLM 5.3 Flash 本次没有测试。

这些都是运行器接入、记忆和分发工作，不是只把可执行文件路径换一下。DSH 还需固定 profile 和控制桥，迁移成本更高，当前没有行为收益支持优先投入。

### 5.2 现有 Codex 路线可以先做的事

- 使用 app-server 的基础指令覆盖，消除编码交付与持续完成的默认拉力；按需要禁用子代理和 goals。别把追加另一段 developer 提示当成删除原提示。
- 将下载停滞作为后台事件处理：同一会话忙时事件应能被宿主合并/展示，避免“agent 守着任务 → 后续无法进来”的闭环。
- 给“怎么样了？”设定可验证的回复要求：先按已有状态说一句，先不授权新的深度排查；必要时使用明确的暂停并汇报路径。宿主显示确定事实时应与模型回复区分。
- 验收应检查真正的 assistant 可见输出时间、steer 消费时间和继续工具数；不要用“已投递”或者思考内容作为已回复。还要检查错误归因，0 peers 本身不能证明是源还是网络问题。

## 6. 证据、复现与限制

- [计量、18 次正式尝试、协议探针与原件哈希](evidence/y15/measurements.json.gz)。
- [发布版本、资产、安装体积、来源文件哈希](evidence/y15/sources.json.gz)。
- [原创实验脚本压缩包](evidence/y15/lab-scripts.tar.gz) 与 [证据说明](evidence/y15/README.md)。

解压到实验目录后，可用 `python3 analyze.py` 从本地原件重算；不要把真实凭据填进脚本或归档。脚本中的路径、固定版本与隔离条件见证据说明。

第一份请求、完整版系统提示、SDK/schema 与上游包留在实验根目录；压缩摘要提供相应 SHA-256，可对照原件。运行脚本不会修改用户 Codex 配置，真实 provider 配置只在父转发器内存里读取。没有 commit、push 或 pub get。结束时已核对没有本次启动的实验 runner、agent 或假端点进程残留；压缩证据哈希、18 次正式尝试的种子一致性、文档本地链接均通过检查，仓库交付物中真实地址与 key 的精确匹配数为 0。

**已知边界偏差，需明确披露：** 最初两次 npm 元数据查询尚未重定向 npm cache，npm 因而向默认 `~/.npm` 写了缓存/日志；之后均改到实验目录。一个尚未加 OS sandbox 的预跑 Codex 工具还写出了 `/tmp/mikan.xml`，这是本次隔离失误。发现后为正式实验增加了继承式写入/网络沙箱；没有为了清理而继续修改边界外文件。这些预跑不进入正式行为比较。产品代码、真实片库、用户 harness 和应用安装均未由本任务修改。

### 一手来源

- [Codex 配置参考](https://developers.openai.com/codex/config-reference/) 与 [app-server](https://developers.openai.com/codex/app-server/)：配置名与公开接口；0.144.1 的具体 payload 以本次二进制捕获和生成 schema 为准。
- [pi 1.3.0 release](https://github.com/earendil-works/pi/releases/tag/v1.3.0)、[CLI](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/cli.md)、[RPC](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/rpc.md)、[RPC commands](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/rpc-commands.md)、[compaction](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/compaction.md)、[extensions](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/extensions.md)。
- [DSH 0.2.1-rc.2 release](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.2.1-rc.2)、[SDK server](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/sdk/server/README.md)、[SDK profile](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/bundle/sdk-app/README.md)、[system prompt](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/core/system-prompt/README.md)、[pi-ai route](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/packages/llm/llm-pi-ai/README.md)。源码路径、配置与界限以本次已安装发布包交叉核对。
