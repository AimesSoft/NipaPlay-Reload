# Action 目录覆盖与核查方法

以当前源码为基线，逐项参考 [ACTION_REFERENCE.md](ACTION_REFERENCE.md) 列出 **327 个静态或可枚举动态 Action ID 的源码候选并集**；同名的不同宿主实现合并为一行。这不是任一设备的 Action 数、在线可用数，也不是运行器自带工具、CLI 子命令或个人工具的总数。参数和实际目录始终以运行目标的 `nipa describe` / `list` 及 `app.capabilities` 为准。

## 核对来源

- `packages/nipa_harness/lib/src/action.dart` 定义 ID、标题、说明、effect 和 schema；`Harness` 从实际 Capability 获取目录。持久任务 `task.list/get/wait/cancel` 在 `tasks/actions.dart` 生成。`task_worker.execute` 是引擎内部执行边界，不计入公开目录。
- 桌面 `lib/next/next_core.dart` 组合领域能力；`next_runtime.dart` 加入 GUI、播放、内核、截图与本地桥。`lib/next/headless/core.dart` 单独组合，`headless/ports.dart` 明确过滤 `download.delete` 和 `media.library.import_history`，并用无播放器/Classic 的端口；同名 `media.library.roots.*` 在 headless 与 GUI 使用不同实现。`body/next_body.dart` 在 iOS 剔除 `window.*`、`program.*`、`chat.*`、`agent.*`、`memory.*`、`app.quit`、`app.restart`。这些不意味着其余项目均在所有宿主可用。
- `mesh/runtime.dart` 的白名单定义允许跨设备分派的 Action 名称或前缀，`mesh.delegate` 在发起设备执行。白名单不保证目标已注册、在线、认证、授权或满足服务前置。表格标记只反映静态白名单；动态事实查询目标目录。
- 除字面量 `ActionSpec` 外，核对了 `_spec`、`_action`、`_Operation` 位置参数；播放器 inspection map；任务、设置、记忆、下载、字幕、同步、发现、通知、媒体库 UI 和 Mesh 文件等操作循环；管理绑定、会话、followup、状态、弹幕字段和 batch 等条件/模板。播放器 feature spec 是另一张 map。保护包装可能保留原 ID 或添加确认入口，因此不能只数构造器。
- 每个表行的 ID 都是机器可读取的覆盖映射，并指向定义源码；`nipa describe ACTION` 是当前输入、输出、副作用和确认条件的权威。表格用途是导航摘要，不能替代完整 schema。

## 可重复检查

在仓库根目录执行：

```sh
python3 scripts/next/check_capability_docs.py
```

检查直接 `ActionSpec` 字面量、已知位置参数构造、播放器 inspection map 和已逐一枚举的动态 ID，比较表格中的 ID；当前为 327 对 327。它还冻结 77 个注册相关源码及宿主组合/过滤文件的 SHA-256：这些文件被修改、消失，或扫描到新的注册相关文件时检查失败，要求人工重新审核动态模板并更新基线。该机制有意保守，注释改动也会触发复核；不运行应用，不打开个人数据库，不检查秘密。

这不是 Dart AST 或执行时注册分析器。手工枚举与有限的源码模式可能遗漏隐藏在其他抽象、外部插件、编译条件或未来新写法中的能力；不检查每行用途、effect、宿主标记和 Mesh 白名单在未来是否语义正确。指纹保护已识别文件的变化，不证明基线本身不存在遗漏。未知模板、注册方式或平台差异必须人工追踪；变更后不应只更新哈希使检查通过。需要进一步对比隔离临时环境下 GUI、headless、iOS 和不同版本目标的真实目录，才能验证各宿主具体注册集合；静态检查不包含运行时矩阵或外部来源连通测试。

## 恢复与安全边界

一个被列出的 Action 不承诺自动确认、幂等或撤回。写入 `outcome_unknown` 后保留目标及原键，查持久回执或任务；没有持久幂等契约的写入不要自动重做。`media.mesh_files.confirm` 执行调用方已获用户同意的覆盖或删除，宿主不弹确认。Classic backup 仅覆盖其声明类别，不代表完整 Next 恢复。过程与保留范围见 [过程事实契约](../OBSERVABILITY_CONTRACT.md)。

## 安装版本知识与实时契约

`knowledge.locate` 直接序列化接收宿主注册的 ActionSpec，包含标题、说明、effect、input 和 output；同一个 Action 在不同宿主的契约不由文档表猜测。能力目录变更通知同时对标题、输入和输出 schema 做指纹，变更会进入能力更新记录。完整参数不再手工复制进知识文档。

`python3 scripts/next/build_knowledge.py --check` 检查精选规范、任务指南、文档 SHA-256 和源码引用与知识包是否同步；发布构建重新写入来源版本。运行时的知识来源检查与静态覆盖检查相互补充，但均不能证明所有说明语义正确；新增或改变能力仍需评审任务流程、权限和恢复说明。
