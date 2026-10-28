# Next 聊天宿主

Next 支持 DeepSeek Harness（DSH）和 Codex 两种会话运行器。通常默认 DSH；运行时、模型与目标宿主的实际状态以设置和 `app.runtime` 为准。本文描述当前接线与边界，阶段性实现和实验保存在 [history.md](history.md)，其中旧默认值和测量不代表当前行为。

## 选择与启动

`AgentRuntimeFixed` 优先读取环境变量 `NIPAPLAY_AGENT_RUNTIME`，再读取实验配置的 `agent-runtime.json`；没有固定值时使用设备设置的 `runtime.json`，再使用宿主默认值。正常桌面默认 DSH；实验 profile 若已有独立 `codex-home/config.toml`，默认保留 Codex。非法运行器或不完整的自定义 DSH 路径报错，不静默切换。见 [dsh_runtime.dart](dsh_runtime.dart)、[host_settings_service.dart](../settings/host_settings_service.dart) 和 [next_runtime.dart](../next_runtime.dart)。

DSH 需要模型路由和可用运行环境；宿主可以下载固定清单的 Node.js 和 DSH，也可通过环境指定安装。模型地址、协议、名称和密钥由宿主管理，密钥通过环境交给 DSH，不能放入仓库、补丁或日志。配置、安装平台和生效方式见 [DSH 高级配置](../../../docs/next/DSH_ADVANCED_CONFIG.md)。Codex 由宿主启动 app-server，使用 Nipa 的 `nipa-base.md`；DSH 通过 SDK profile、Nipa 插件及 persona 前后缀接入。二者读取个人 harness 的 `AGENTS.md`。提示词和插件安装入口见 [next_runtime.dart](../next_runtime.dart)，DSH patch 见 [dsh_runtime.dart](dsh_runtime.dart)。

桌面宿主随 Next 和本机端点生命周期启动或关闭；切换运行器或 harness 会重新连接相应会话。iOS/iPadOS 是 body-only，不启动本地对话宿主，可连接另一台设备的梨花。headless 可在配置运行环境、模型和 Agent 后提供自己的会话；各设备能力与运行状态以实时目录和 `mesh.devices` 为准。

## 会话、历史和记忆

`harness_sessions` 保存每个 harness 的主会话及当前会话指针，并按运行器区分；Codex 与 DSH 的线程不能互相续接。各运行器负责自己的对话历史和上下文压缩，宿主另存有限的过程事实及可展示的消息；压缩后的模型上下文不等于个人记忆或完整历史。切换运行器后原运行器的会话保留，已绑定其线程的后续等待对应宿主可用。

个人 Git harness 的 `memory/preferences.md` 和 `memory/MEMORY.md` 是常驻偏好和索引，其他文件按需读取。用户可在设置中查看、修改；`memory.list/read/edit/delete` 具有路径、版本和大小约束。写入会记录来源，旧 Git 历史与对话历史不会因为删除一条记忆自动消失。不要把密钥写入记忆。Codex 通过 seed 的 session hook 注入；DSH 的 `nipa-memory` 插件在开始、恢复、压缩及有关变化后重建上下文。记忆是历史观察，使用前应核对实时状态。实现见 [chat_host.dart](chat_host.dart)、[nipa-memory.mjs](../../../assets/next/agent/dsh/nipa-memory.mjs) 和 [memory](../memory/)。

## 用户插话与任务后续

用户在活动回合中发消息通过 `turn/steer` 交给当前运行器；宿主检查线程及回合状态。对于宿主产生的后续，DSH 可在活动回合的下一步接收；Codex 后续等待会话空闲。宿主不可用时后续保留，投递状态和不确定结果按队列的回执处理，不把未知投递结果当作未执行。

对话发起的下载、入库和其他支持的任务有各自的自动返回条件；GUI 添加目录、Classic 扫描或来源同步不会自动唤醒梨花处理新入库文件。要等待特定事件或任务，可登记 `followup.register` 并检查其状态；受理不是完成。来源、节流、终态和恢复的具体规则见 [followups README](../followups/README.md) 和 [library_arrivals.dart](../followups/library_arrivals.dart)。

## 子代理

运行器的原生子代理和宿主派发的独立任务都可显示为后台工作；它们共享 harness、文件与宿主事实，不是独立工作副本。任务状态、取消、结果回传及恢复由宿主和运行器按各自契约协调。子代理运行、结果到达和后续重试受运行器及宿主状态约束；不要把已派发当成已完成。相关实现见 [followups](../followups/) 和 [chat_host.dart](chat_host.dart)。

## 权限与诊断

桌面运行器在用户权限下工作，不是隔离沙箱；DSH 使用 `danger-full-access`，Codex 的宿主启动参数也指定该权限和关闭自动审批。它可以操作进程可访问的文件、程序和网络；用户明确授权与宿主强制确认是两层不同的事，不能绕过宿主拒绝。Mesh 加入同账号设备意味着信任设备访问开放能力和可访问文件；远端运行程序另需目标设备授权。具体行为以目标设备的能力与回执为准。

`app.runtime`、`app.capabilities`、`task`、`followup` 和 `diagnostics.operations` 提供不同范围的状态与过程；结果未知不等于失败或回滚。跨设备和 SQL 回执的恢复规则见 [过程事实契约](../../../docs/next/OBSERVABILITY_CONTRACT.md)。日志与反馈需先移除密钥和个人信息。
