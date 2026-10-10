# 设置注册表任务书：让设置成为 Agent 的接口

> 工作方式见 `docs/next/TEAM.md`。调研输入：`research/CAPABILITY_COVERAGE.md`（R7，尤其 §3、§4）。

## 目标

- 用户能在设置里改的，Agent 都能用同样的权限改，例如“弹幕小一点”“字幕延迟 0.5 秒”“以后默认用外部播放器”。
- 每次修改都可以追溯：谁改的、何时、为什么。“以后都这样”因此成为可查询、可撤销的偏好记录。
- Classic 设置页与 Agent 共用同一个注册表，只有一个事实来源。

### 验收场景

- 播放中对 Codex 说“弹幕太吵了，小一点、透明一点，以后都这样”：
  - Agent 先 `settings.describe {domain: 'danmaku'}`，再执行两次 `settings.set`，并附上理由；
  - 播放器立即生效，重启后仍然保持；
  - 用 `settings.history` 能看到这两次修改的 `changedBy: agent`、时间与理由。
- 在 Classic 设置页手动改同一项，`settings.history` 中记录为 `changedBy: user`。
- `settings.describe` 的结果中找不到任何秘密项或扩权项；对它们调用 `get` / `set` 一律失败。

---

## 全局契约

### 1. 设置项 schema

以 R7 §4.1 为基础：

- 字段：`key`、`title`、`description`（面向 Agent）、`type`、取值约束、`default`、`scope`（`user` / `device`）、`apply`（`immediate` / `reload_player` / `reload_server` / `restart_app`）、`storage`。
- 注册表的 `key` 与物理存储键分开。**迁移期不改物理键**，读写仍经过现有的 setter 与存储，保证 Classic 照常工作。

### 2. 来源（provenance）

- `changedBy` 与 `origin` **由宿主依据 `Invocation.origin` 写入**：`gui → user`，`mcp → agent`，`mesh:<id> → mesh:<id>`，迁移写入记为 `migration`。模型无法自称“用户改的”。
- `reason` 是可选文本，由调用方提供，只用于展示与记忆，不参与任何授权判断。
- 每次修改向 `next.db` 追加一条变更记录（键、旧值、新值、来源、理由、`invocationId`、`revision`），记录只追加不覆盖。该表作为 `next.db` 的新迁移，通过 NextCore 追加。

### 3. 禁止开放项（由注册表强制执行）

- 秘密类：令牌、密码、API 密钥、凭据引用的值。
- 扩权类：Agent 端点开关、执行模式、审批策略、局域网远程访问与遥控接收端、插件安装权限，以及任何会扩大 Agent 自身权限的设置。
- 这些项**不出现在 `describe` 中**，`get` / `set` 返回 `not_found`。维护一份显式的禁止清单，并用测试断言它们不出现在运行时目录中。

### 4. Action

| id | effect | 语义 |
|---|---|---|
| `settings.describe` | read | 按 domain 或关键词列出设置项 schema 与当前值；只包含本机可见、可开放的项 |
| `settings.get` | read | 当前值、`revision`、`scope`、`apply`，以及最近一次修改的来源 |
| `settings.set` | write | `{key, value, reason?, expectedRevision?}`。校验类型与范围；`revision` 不匹配时返回 `conflict`；返回生效方式（`apply`） |
| `settings.reset` | write | 恢复默认值，同样记录来源 |
| `settings.history` | read | 某个键，或最近若干条的变更记录 |

- `settings.set` 永远是 `write`。真正破坏性的操作（例如清空缓存、删除连接）保留为独立的 destructive Action，不通过 `settings.set` 完成。
- `apply` 不是 `immediate` 时，Action 只返回生效方式，不自行重载或重启。

### 5. Classic 共存

- Classic 设置页与播放器菜单调用的 setter，内部改为经过注册表写入，记录来源 `user`。页面的外观与行为不变。
- `PlayerRemoteControlBridge` 已有的参数描述迁入注册表，作为同一份数据源；遥控接口的对外行为不变。

### 6. 覆盖率只升不降

- 按 R7 §4.5 实现：基线快照（Action id 与设置 key，含 effect 与 scope），测试断言“当前集合 ⊇ 基线”。
- 每个设置项至少有一条“读默认值 → set → get 回读 → 复原”的往返测试，用的是真实 setter 与内存存储。
- 不使用源码字符串断言。

## 范围（本阶段）

- 注册表核心、来源记录、禁止清单、`settings.*` Action、覆盖率基线机制；
- 首批迁移的域：**播放器、弹幕、字幕**（R7 §4.4 的 P1–P3）；
- 外观、网络、下载器、插件、实验室等其余域，在后续批次迁移。

## 验收

- 单元与契约测试；
- 上述验收场景由主控做端到端验收。
