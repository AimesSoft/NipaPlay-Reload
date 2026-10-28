# NipaPlay Next 架构

本文描述 `next` 分支在 2026-10-28 的实现边界。Next 是 Developer Preview 和研究项目；运行时目录、目标设备事实和实际回执优先于本文。研究假设见 [RESEARCH.md](RESEARCH.md)，能力入口见 [CAPABILITIES.md](CAPABILITIES.md)。

## 判断与执行

用户通过对话表达意图，Agent 查询实时事实、选择方案、判断媒体身份并解释结果。能力层提供文件、候选、状态和操作，不把候选自动当作身份。宿主负责执行、持久任务恢复、事务和回执。个人 harness 是 Agent 可维护的 Git 仓库：工具、经验、记忆和 hooks 可以随实际任务生长；它不是一套固定的能力清单。

```text
用户 ↔ Agent / 会话运行器 ↔ 个人 Git harness（nipa、hooks、记忆、工具）
                                  │ 认证的本机端点
                                  ▼
                          Harness / Action 分派
                                  │
                  NextCore：数据库、领域能力、任务引擎
                         │                   │
                  GUI / 播放器          Mesh → 目标设备的 Core
```

代码组合入口是 `lib/next/next_core.dart`、`next_runtime.dart` 和 `packages/nipa_harness`。Core 打开并迁移 `next.db`，组合领域、执行器和同一个持久任务引擎，启动时恢复任务与媒体投影 outbox。桌面 Runtime 将 Core 接入应用、播放器、端点、会话和 UI；停用 Next 会停止其 Agent 端点与 Mesh，Core 本身由宿主生命周期管理。具体注册和可用性由运行时决定。

## 宿主和运行器

- **桌面 GUI** 提供 Next 自己的首页、媒体库、对话和播放界面，并接入本机媒体、任务与用户在场的操作。Classic 与 Next 不互相隐藏挂载：切换时关闭当前播放会话并保存进度，另一边不自动续播。
- **Headless** 提供无界面的 Core、端点、Mesh 和可配置的对话宿主，适合持有媒体的设备；没有桌面窗口或本地 GUI 播放器就不能假定这些能力可用。安装、数据目录和 DSH 前置见 [HEADLESS.md](HEADLESS.md)。
- **iOS / iPad 的 body-only 角色**：`NextBody.bodyOnly` 在 iOS 为真，提供 Next 界面、能力层、播放器和 Mesh，不启动本地 Agent 端点或对话宿主；对话可选择连接其他设备的 Agent。该角色过滤 `window.*`、`program.*`、`chat.*`、`agent.*`、`memory.*`、`app.quit` 和 `app.restart`，界面不提供本机下载器。具体能力仍以设备的 `app.capabilities` 为准；源码路径不代表所有移动设备已有实机覆盖。
- **会话运行器** 负责模型交互与会话生命周期。代码接入 Codex 和 DeepSeek Harness（DSH）；DSH 使用固定版本和宿主插件，模型、凭据及运行环境需配置。高级配置的生效和恢复边界见 [DSH_ADVANCED_CONFIG.md](DSH_ADVANCED_CONFIG.md)。运行器选择不改变 Action 的领域契约，也不保证任意模型或插件组合可用。

默认个人仓库为 `~/nipaplay-harness`，也可配置路径。启动时宿主先预览官方种子合入并保护个人分支、索引和文件；冲突或中断会暴露状态，不强制覆盖。认证凭据位于仓库外。hooks 把事件交给仓库中的程序，输出记入任务回执；中断的 hook 不自动重跑。

## 数据、任务和投影

设置、观看记录和续播进度按明确契约与 Classic 共用；共享数据不授权 Classic 在 Next 会话中替 Agent 识别。Next 启动、下载完成和扫描登记文件事实，身份由用户或 Agent 核实后显式绑定，也可在支持范围内用 SQL 保存。旧 Classic 身份只经 `media.library.import_history` 显式导入；已提交的 Next 绑定可按 outbox 契约投影给 Classic，回读不会顺便导入其他身份。Classic 模式保留自己的扫描和匹配行为，隔离不会清空已有数据。

任务受理不等于任务成功：通过任务状态、事件及回执检查完成和失败。数据库领域原语与 `db.describe/query/write/undo/receipt` 长期并存；SQL 写入有预演、冲突检查、审计和恢复入口。Mesh 可将支持的能力路由到目标设备，在目标自己的库执行；目录、文件路径、权限、前置条件和回执均属于该设备。目标在线、认证和 Action 的 `remoteCallable` 仍是前提；不能把本机存在的能力视为远程可调用。

对话原始历史和上下文压缩由对应运行器管理；Codex 与 DSH 的会话不能互相续接。宿主另保存过程显示和领域事实；harness 的 `memory/` 保存可由用户查看和修改的偏好、经验和索引。压缩摘要、长期记忆、实时数据库状态不是同一份事实，使用旧记忆前应核对实时状态。

## 失败与恢复

请求送达、Action 完成、事务提交、投影发布和调用方收到响应是不同事实。`outcome_unknown` 表示结果未知，不证明失败或回滚。保留原目标和请求键，先查询任务、领域回执或 `diagnostics.operations`；SQL 使用原 previewId/requestId 查询 `db.receipt` 并依其契约恢复。没有持久幂等契约的写操作不能因断线自动重做。过程记录有保留期限，不能代替持久领域回执；完整步骤与限制见 [OBSERVABILITY_CONTRACT.md](OBSERVABILITY_CONTRACT.md)。

## 规范与验证

本文描述架构和能力边界；实际注册、权限和运行结果以目标设备的实时目录及回执为准。历史 X/Y 报告记录特定版本和环境下的实验，不是当前版本实机验收的证明。已知限制和当前验收状态见 [已知问题](KNOWN_ISSUES.md)。
