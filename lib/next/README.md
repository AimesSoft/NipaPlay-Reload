# 应用组合点

`ServiceProvider.initialize` 在原生应用启动时创建唯一的 `NextCore`，等待
`core.ready`。Core 暴露 `root`、`deviceId`、`engine`、`downloads`、`media`、
`danmaku`、`settings`、`credentials`、`credentialVault` 和 `capabilities`；
Classic 下载页使用 `core.downloads`，`NextRuntime` 把
`core.capabilities` 注册到 Harness。Labs 只启停 Agent 端点，销毁
`NextRuntime` 也不关闭 Core。应用宿主结束 Core 生命周期时调用 `core.close()`。

只读公开状态通过 `state.describe` / `state.query` 提供，契约与边界见 [state/README.md](state/README.md)。Agent 用 `nipa list` 读取当前全部能力。

`app.capabilities` 返回当前宿主功能、provider/source 前置、设置键和逐 Action 的
远程范围；`nipa describe app` 是此族说明。GUI 和纯 Dart 宿主共用在线 provider
工厂与弹弹play网关客户端，秘密只通过宿主保险库引用读取。详情见
[无界面宿主](../../docs/next/HEADLESS.md) 和 [X53 报告](../../docs/next/X53_REPORT.md)。

启动顺序：读取设备身份 → 打开并迁移 `next.db` → 创建领域运行时（索引文件；旧身份仅由显式
`media.library.import_history` 导入）→ 收集全部执行器创建 TaskEngine → 向各领域注入同一引擎并收集
Capability → `engine.start()` 恢复持久任务 → 启动下载会话观察与页面外自动入库
→ 恢复媒体投影 outbox。领域不得创建引擎或打开数据库。

新增领域（如 MB 弹幕）沿用同一模式：接收 Core 的数据库与设备身份（弹幕还接收
MA 的身份存储），提供执行器及 Capability，在 `NextCore` 中参与组合，并在
`engine.start()` 前完成引擎注入。后续恢复工作放在引擎启动之后。
迁移实现保留在各领域目录，按发布顺序追加到 `next_database.dart` 的
`_migrations`，不改已发布位置：v1 任务表，v2 媒体身份表，MB 从 v3 追加。
新库和旧库共用这一迁移序列。`SqliteJobStore.open` 仅供独立存储测试使用；
应用使用 Core 已打开的连接构造 `SqliteJobStore.fromDatabase`。

设置域接收同一数据库，由 `NextCore.settings` 提供注册表和五个 `settings.*`
Action；在 v3 弹幕后追加设置变更表迁移 v4。
`settings/application_settings.dart` 绑定播放器、弹幕、字幕的现有 setter 和
SharedPreferences 物理键。Classic setter 通过 `SettingsAccess.persist` 记录
来源，页面和播放器菜单继续调用原 setter；遥控桥从条目读取原协议参数描述。
设置与播放器 provider 在生命周期内接入绑定，关闭 Core 前排空来源写入。
非 immediate 的 Action 仅保存偏好并返回生效方式，Classic 原有重载行为保留。

Core 同时组合 `credentials.status`。凭据读写经宿主保险库，设置注册表禁止
保险库的标量键、含秘密的连接列表及插件字符串存储键；密钥不进入设置变更表。
保险库不新增数据库迁移。媒体能力原语在 v4 后追加迁移 v5；现有版本位置保持不变。

Core 同时创建 `mesh`、注册三个 `mesh.*` Action 与 `mesh.addressCandidates` 设置，
在领域恢复完成后启动宿主配置的 Mesh。`NextRuntime` 将应用 Harness 交回 Core，
Mesh 与回环 MCP 共用分派器；Mesh 生命周期由 Core 管理，随 Next 的启用与停用；无界面宿主通过自己的启动配置启用。
Mesh 的身份、证书和去重文件独立持久化，不新增 `next.db` 迁移。

开启 Next 时，`AgentEndpoint` 从 `assets/next/harness/` 创建用户仓库，默认
`~/nipaplay-harness`；`next.harnessPath` 设置和实验室共用 `HarnessLocation`。
创建时不会覆盖已有路径。初次种子包含无令牌的 Codex 配置、`nipa`、hooks 说明。
应用在 `next/harness-seed` 维护本地 git 历史，种子内容变化时提交一次。

`nipa status.instance` 与 `app.instance` 读取同一进程事实：PID、可执行文件和
应用包路径、主窗口标题/ID、实验配置和版本。`ui.open` 观察实际可见的 Classic
页面或详情；`ui.capture` 把当前进程主窗口保存为临时 PNG，回执含实例事实、尺寸、局限，
以及 `method`、`includesNativeVideo`：macOS 上用窗口合成截图（含原生视频层与 Erika 弹幕，
只截本应用自己的窗口，不需要录屏权限）；其他平台只有 Flutter 内容，原生覆盖层不在其中，
回执如实写明。系统窗口边框、其他窗口和外部播放器始终不在其中。文件属于宿主设备，不经 Mesh 传输。
新 harness 从它克隆，远端名为 `nipaplay`，分支为 `main`。启动时先验证远端指向本机种子，
自动抓取并用 `merge-tree` 预览；干净结果才以快进更新（必要时创建保留双方历史的合并提交）。
冲突或未提交内容阻挡时保持文件与索引原状，不 stash/reset，也不改远端配置；Git 2.38 以下不能预览时跳过。
`status.harnessSeed.merged` 和 `autoUpdate` 报告实际合并与本次结果，回执写到种子旁的 `harness-update.json`，
更新或待处理事实注入 GUI 与 headless 的最近记忆。CLI 默认列能力索引与任务概况，
`list/status --full` 取完整内容，`describe ACTION` 取单项契约。
令牌每次开启轮换，写到仓库外的用户私有 `endpoint.json`；MCP `/mcp` 与 CLI
`/harness` 共用认证和 Harness，CLI 调用来源为 `harness_cli`。

Core 注册 `harness.hook` 执行器；NextRuntime 仅在 Next 开启时订阅下载任务的
成功变更、提交后的新增文件和播放器的首次 playing 状态。事件交给用户仓库的
同名可执行程序，标准输入为 JSON，输出脱敏后写入同一任务系统的回执。
中断 hooks 不重跑。复现实验见 `scripts/next/x3_experiment.dart`；测试守住凭据
隔离、仓库不改写、去重与失败回执等数据约束。

能力执行的过程事实契约见 [可观测性契约](../../docs/next/OBSERVABILITY_CONTRACT.md)。
`diagnostics.operations` 给当前进程的调用阶段与关联 ID；`db.receipt` 给同一来源的持久 SQL 提交证明。
传输完成、Action 返回、数据库提交、界面更新与播放成功分别观察，不互相替代。
