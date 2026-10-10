# 第 1、4 批实现报告

分支：`next/capability-layer`。未提交 commit，未 push，未运行 pub get。
`assets/next/AGENTS.md` 未修改。

## 1. 完成了什么

- MCP initialize instructions、Action 描述与相关字段说明改为能力、数据、副作用、限制和错误语义；删除调用顺序指导。同步修正 DESIGN 与历史任务书，标记研究中的旧流程方案已被 §2.3 取代。
- `media.metadata.override` 支持 Agent。宿主记录 actor、origin、invocationId；mode 区分 persistent、correction 和 clear，默认 persistent 保持兼容。SQLite v6 迁移保留旧 GUI 覆盖，并持久记录编辑审计。
- Core 注册 `state.describe` / `state.query`。支持筛选、投影、排序、声明关系与分页；描述从注册契约生成。查询无业务写入、扫描、刷新或线上请求。
- 公开结果用闭合字段白名单；秘密、认证配置、原始任务 input/checkpoint、原始异常与任意自由 details 不可见。URL 去除认证组件，授权外或不存在的原生 locator 不显示。
- 旧 getter 保留调用 ID、输入输出及已有行为；覆盖率基线维护能力、主要契约、兼容映射和行为场景。当前为 63 项能力、58 个主要 Action、63 个兼容映射；63 个可调用 Action、127 项设置。
- 离线体验断言通过：一次查询取得 TMDB 作品的全部两集、两个文件、身份绑定和真实观看进度；全部注册视图的查询结果排除秘密，查询前后 SQLite total_changes 不变。

视图清单（20 个；字段说明由 `state.describe` 生成）：

- `library.works`、`library.seasons`、`library.episodes`、`library.files`
- `library.classic_series`、`library.classic_episodes`
- `media.entities`、`media.identities`、`media.bindings`
- `history.entries`、`history.continue_watching`
- `tasks`、`task_events`、`task_receipts`
- `settings.changes`、`downloads`
- `danmaku.bindings`、`danmaku.tracks`、`danmaku.datasets`
- `mesh.devices`

## 2. 决策

- 新出口读取数据库公开投影与已有内存，不委托有注册、迁移或刷新行为的旧 getter。Classic 的识别作品视图保持 Dandanplay ID 语义，Next 视图使用跨来源实体 ID。
- 默认 50 行，根页与关联合计最多 200 行，数组字段最多 200 项；最多扫描 5000 行、两级关联、1000 ms、256 KiB 输出、64 KiB 输入，以及两个未结束的来源读取。分页与资源截断均显式报告。
- 游标对实时观察分页；snapshotId=null，不声称跨 Classic、Next、播放器和 Mesh 有全局事务快照。超出扫描窗口的排序按窗口进行，并返回专门警告。关联截断带独立查询表达式。
- 设置历史值通过对应 SettingEntry 的 schema 投影，以 JSON 文本返回，避免引入另一份设置类型定义。Mesh 只读已缓存设备与可达性观察。
- 普通元数据修正在出现更新的已接受来源快照后失效；持久覆盖独立于调用者身份。clear 也保留宿主来源审计。
- Classic 文件名的 URL 回退在新公开视图中使用 URI path，避免认证参数落入标题；旧 Classic getter 和展示行为保留。

查询协议与限制见 `lib/next/state/README.md`，注册实现见 `lib/next/state/views.dart`。

## 3. 验收命令与真实输出

全部使用 `~/development/flutter-3.44.6`，测试使用夹具或回环服务，不访问线上服务。

```text
cd packages/nipa_harness
~/development/flutter-3.44.6/bin/dart test
00:00 +87: All tests passed!
```

```text
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next test/next
No issues found! (ran in 2.5s)
```

```text
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next --reporter expanded
Capability coverage: 63 abilities, 58 primary actions, 63 compatibility mappings; 63 callable actions, 127 settings.
00:25 +328: All tests passed!
```

另外，`git diff --check` 通过。查询专项覆盖筛选与投影、分页游标、超预算续查、关联与字段截断、输出大小、耗时与并发、来源异常脱敏、历史 ID 关联、旧 getter 等价投影、Classic URL 标题脱敏及只读不变量；迁移和元数据测试覆盖旧覆盖保留、Agent/GUI actor、普通修正失效与清除审计。

## 4. 问题

无需要主控决定的事项。
