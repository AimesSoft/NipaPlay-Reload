# 应用组合点

`ServiceProvider.initialize` 在原生应用启动时创建唯一的 `NextCore`，等待
`core.ready`。Core 暴露 `root`、`deviceId`、`engine`、`downloads`、`media`、
`danmaku`、`settings`、`credentials`、`credentialVault` 和 `capabilities`；
Classic 下载页使用 `core.downloads`，`NextRuntime` 把
`core.capabilities` 注册到 Harness。Labs 只启停 Agent 端点，销毁
`NextRuntime` 也不关闭 Core。应用宿主结束 Core 生命周期时调用 `core.close()`。

启动顺序：读取设备身份 → 打开并迁移 `next.db` → 创建领域运行时（媒体先导入
旧历史）→ 收集全部执行器创建 TaskEngine → 向各领域注入同一引擎并收集
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
Mesh 与回环 MCP 共用分派器；Mesh 生命周期由 Core 管理，不依赖 Labs 开关。
Mesh 的身份、证书和去重文件独立持久化，不新增 `next.db` 迁移。

`test/next/capability_coverage_baseline.json` 保存 Action id/effect 与设置
key/effect/scope，并同时维护 `capabilities`、`primaryActions` 契约、
`compatibility` 映射与 `behaviorScenarios`。覆盖率测试从真实 Core 和运行时能力
生成目录，断言包含基线；旧任务恢复与新只读分析分别保留真实 Effect。
新增能力时运行 `NIPA_EXPORT_COVERAGE=1 ~/development/flutter-3.44.6/bin/flutter
test --no-pub test/next/capability_coverage_test.dart`，快照导出到系统临时目录的
`nipa-capability-coverage.json`；核对后合入新增能力、契约与映射，已有项不得删除或降权。
