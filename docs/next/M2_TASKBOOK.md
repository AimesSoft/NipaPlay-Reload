# M2 任务书：Task Engine 与应用内下载

> 工作方式见 `docs/next/TEAM.md`。设计背景见 `docs/next/DESIGN.md`，调研输入见 `docs/next/research/LONG_RUNNING_OPERATIONS.md`（R2）。

## 目标

把 download-harness 的“Seedbox 上的 qBittorrent + 工位机 worker”收进 NipaPlay：

- 长时间操作成为**持久任务**：有进度，可取消；重启后能恢复；完成与否以可验证的**回执**为准。
- Agent 只在需要判断时介入，其余由确定性执行器完成（稀疏智能）。
- 第一批任务是 BT 下载，以及下载完成后的自动入库。
- **Classic 一同受益**：下载在应用启动时恢复；下完自动入库不再依赖打开下载页。

### 验收场景

在 Codex 工作区中依次说：

1. “下载这个：`magnet:?xt=...`，下完告诉我”
   - Agent 调用 `download.add`，再用有上限的 `task.wait` 反复等待，直到任务结束；
   - 最后根据回执汇报：文件在哪、多大、是否已入库。
2. “播放它”：Agent 用回执中的媒体信息调用 `playback.open`。
3. 中途退出并重启 NipaPlay：下载自动恢复，任务状态连续，不需要打开下载页。

---

## 全局契约（主控决定，实现者不得更改）

### 1. Job 的对外形状

所有任务类 Action 返回的 `job`、`task.get` 与 `task.list` 的条目，都是同一个 JSON 形状。必须包含以下字段；实现者可以增加字段，但不得改变这些字段的语义：

| 字段 | 语义 |
|---|---|
| `jobId` | 稳定 ID；重试、恢复不换 ID |
| `type` | 例如 `download` |
| `title` | 给人看的名称 |
| `state` | `queued` / `running` / `paused` / `needs_decision` / `waiting_retry` / `interrupted` / `cancelling` / `succeeded` / `failed` / `cancelled` |
| `phase` | 当前阶段，如 `downloading`、`verifying`、`importing` |
| `progress` | `{completed, total?, unit}`。总量未知时省略 `total`；不同阶段的单位不混算 |
| `createdAt` / `updatedAt` | UTC ISO-8601 |
| `error` | 失败时为 `{code, message, retryable}` |
| `decision` | `state = needs_decision` 时提供，形状与 Harness 的 `Decision` 相同；执行任一选项的 `call` 即可让任务继续 |
| `receipt` | 终态时提供，见下文 |
| `ownerDeviceId` | 执行设备。Mesh 之前恒为本机安装 ID |

### 2. 状态语义

- `succeeded` 只表示**约定的验证已完成**，不能仅由某个 Future 返回或循环结束来设置。
- 已经发起的外部副作用不会因为取消而被抹掉：取消到达时若副作用已提交，应继续验证，并在回执里记下取消发生的时机。
- 进程退出时仍处于 `running` 的任务，重启后先进入 `interrupted`，由执行器检查实际副作用后再决定恢复、验证还是请求判断，不能直接重跑。

### 3. 回执

回执必须如实记录验证等级：

- `verified`：已回读并核对；
- `acknowledged`：对方确认收到，但未回读核对；
- `unverified`：未做验证。

下载回执至少包含：

- 每个文件的路径、期望大小与实际大小，以及是否已入库；
- 入库结果：对应的媒体库条目，或无法识别的原因。

### 4. 持久化

- 任务、事件、回执、待决判断保存在独立的 `<AppStorage>/next/next.db`（SQLite），不修改任何现有数据库。
- 任务状态的变化与对应事件在同一事务中写入。
- 本机安装 ID 保存在 `<AppStorage>/next/device.json`，作为 Mesh 之前的设备身份占位。

### 5. Action 目录（新增）

| id | effect | 语义 |
|---|---|---|
| `task.list` | read | 列出任务，可按状态或类型筛选 |
| `task.get` | read | 单个任务的完整快照 |
| `task.wait` | read | **有上限的等待**（harness 的 `watch`）：等到指定任务进入终态、发生变化，或超时（上限 60 秒），返回当时的快照。Agent 用它替代轮询 |
| `task.cancel` | write | 请求取消，返回取消请求被受理后的快照 |
| `download.add` | write | 添加磁链或 .torrent（URL 或本地路径），立即返回 `job`（表示已受理，不表示已完成） |
| `download.pause` / `download.resume` | write | 暂停、恢复 |
| `download.remove` | write | 移除任务，**保留**已下载的文件 |
| `download.delete` | destructive | 移除任务并**删除**已下载的数据 |

- 下载目录、并发等沿用现有下载设置，不新增配置项。
- 若同一内容（infoHash）已在下载或已完成，`download.add` 返回已有任务，不重复添加。

### 6. 分层

- Task Engine 内核（Job 模型、状态机、存储端口、执行器接口、`task.*` Action）放在 **`packages/nipa_harness`**，保持纯 Dart。
- SQLite 存储与下载执行器放在 `lib/next/`，接入现有的 `TorrentDownloadService` / Rust librqbit。
- Classic 的下载页与 Next 共用同一个下载会话和同一套入库逻辑，不允许两份实现并存。

---

## 阶段 A：Task Engine

**目标**：一个可复用、可恢复的任务内核，以及 `task.*` Action；接入 `NextRuntime` 并通过 MCP 暴露。

**边界**：

- `packages/nipa_harness`：新增任务内核及其测试；
- `lib/next/`：SQLite 存储、本机安装 ID、`NextRuntime` 接线；
- `test/next/`；
- 附带一个小改动：Labs 页面在显示工作区路径的地方，增加提示“在 Codex 中添加此文件夹为项目并选择信任”（三语）。M1 验收发现 Codex 只为受信任项目加载工作区配置。

**验收**：

- 内核与 SQLite 存储的测试覆盖：状态机合法与非法迁移、事务性、重启恢复（`running → interrupted → 执行器决定`）、`task.wait` 的三种返回（终态、变化、超时）、待决判断的持久化与通过 `call` 继续；
- 用一个测试用的假执行器跑通完整生命周期；
- `dart test`（包内）、`flutter analyze --no-pub lib/next test/next` 与 `flutter test --no-pub test/next` 全部通过。

## 阶段 B：应用内下载

**目标**：BT 下载成为 Task Engine 上的第一个真实任务类型；Classic 下载页随之受益。

**边界**：

- `lib/next/` 中的下载执行器与 `download.*` Action；
- 现有下载相关代码：`lib/services/torrent_download_service.dart`、`lib/pages/torrent_download_page.dart`、`lib/downloads/*`、`lib/providers/downloader_settings_provider.dart`；
- 应用启动接线：`ServiceProvider` 或 `main.dart` 的延迟启动段；
- 不修改 Rust 侧，除非确有必要；需要修改时先停下来提问。

**要求**：

- 下载功能已启用时，应用启动即恢复下载会话，与是否打开下载页、是否开启 Labs 无关。
- 下载完成后的“验证 → 入库”成为任务的阶段。
  - 现有下载页里的自动入库逻辑迁移到执行器中，页面只负责展示。
  - 入库沿用现有扫描与识别服务。
- 恢复时根据 infoHash 重新关联 librqbit 会话中的任务；librqbit 自己的 ID 只是关联句柄，不是 `jobId`。
- `download.delete` 删除数据前确认文件确实位于该任务的输出目录内。

**验收**：

- 执行器测试：用假的会话端口覆盖添加、去重、进度、暂停与恢复、完成后验证、入库、重启恢复、取消时机、删除边界。
- 主控做端到端验收：上面的三个验收场景，外加 Classic 下载页的回归（列表、暂停、恢复、删除、自动入库），由主控在真机上完成。
