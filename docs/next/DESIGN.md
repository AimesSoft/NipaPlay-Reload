# NipaPlay Next：能力层（Harness）设计

> 状态：M1 设计基线 · 2026-10-10
> 适用分支：`next/capability-layer`

## 1. 一句话

**NipaPlay 的每一项领域能力都是一个带契约的 Action；GUI、Agent、远端设备调用的是同一个 Harness。**

用户表达意图，Agent（Codex）规划并调用 Action，Action 交付可验证的结果。
UI 不是另一套业务实现，而是 Harness 的一个调用者，同时也是 Agent 可以调用的一类 Action（`ui.*`）。

## 2. 概念

| 概念 | 含义 |
|---|---|
| `Action<I, O>` | 一项可调用的领域能力。由 `ActionSpec`（契约）、输入解码和 `run` 组成。 |
| `ActionSpec` | 契约：`id`、`title`、`description`、`effect`、输入 schema、输出 schema。它是唯一事实来源：MCP 工具列表、输入校验、审批策略、契约测试都从它派生。 |
| `Effect` | `read` / `write` / `destructive`。描述副作用等级，决定 MCP `readOnlyHint` / `destructiveHint` 与 Agent 审批策略。 |
| `Schema` | 极小的 JSON Schema 子集，既能输出 JSON Schema，又能校验 JSON 值。 |
| `Outcome<O>` | `Completed(value)` / `NeedsDecision(decision)` / `Failed(failure)`。 |
| `Decision` | Action 无法替用户做主时返回的结构化提问。每个选项都携带一个**可直接执行的** `ActionCall`。 |
| `Failure` | 稳定错误码 + 人类可读说明。Action 内部直接 `throw Failure(...)`。 |
| `Capability` | 一组共享依赖的 Action（例如播放能力持有播放器端口并提供 `playback.*`）。 |
| `Harness` | 内核：注册 Capability、校验输入、执行 Action、把异常归一为 `Outcome`、通知观察者（日志）。 |
| `Invocation` | 一次调用的上下文：`id`（关联 ID）与 `origin`（`gui` / `mcp` / 将来的 `mesh:<device>`）。 |
| Transport | Harness 的外部接口。M1 只有 MCP（Streamable HTTP，仅回环地址）。将来的 Mesh、Web 都是新的 transport，不改 Action。 |

### 2.1 为什么 `NeedsDecision` 是核心

这是 Classic 与 Next 能共存、意图能端到端执行的关键：

- 现在的代码在“需要用户选择”时直接弹对话框（选文件、确认匹配……），Agent 无法参与。
- 在 Harness 里，Action 不弹框，而是返回 `NeedsDecision`。每个选项就是下一次调用（`ActionCall`）。
- Agent 若已能从用户意图决定（例如“播最新那个版本”），直接执行对应选项；否则把选项交给用户。
- 将来的 `ui.present` 可以把选项渲染成按钮，点击直接执行 `ActionCall`，**不需要再触发一次模型推理**。

### 2.2 Effect 与授权

| Effect | 含义 | MCP annotations | 生成的 Codex 审批 |
|---|---|---|---|
| `read` | 无副作用 | `readOnlyHint: true` | 自动 |
| `write` | 有副作用，但可恢复（播放、跳转、改设置） | `readOnlyHint: false, destructiveHint: false` | 自动 |
| `destructive` | 不可恢复（删除数据等） | `destructiveHint: true` | 每次询问 |

授权的**语义**（什么样的意图授权什么操作）写在 Agent 工作区的 `AGENTS.md` 里，这一点沿用 download-harness 的经验。Effect 只是机器可读的兜底边界。

### 2.3 能力即权限

Agent 的上下文必然混入不可信文本：种子标题、网页、弹幕、字幕、插件输出、自进化时读到的 API 文档。`AGENTS.md` 里的约定能降低风险，但它本身不是安全边界。

- **真实世界的副作用只通过 Harness Action 发生。**
  - 文件系统同样以 Action 暴露（如 `fs.list`、`library.organize`），作用域限定在用户授权过的根目录；
  - 在作用域内，Agent 按“计划 → 执行 → 回执”自由操作；
  - 权限由宿主（Harness）强制检查，模型无法绕过。
- **Agent Runtime 自带的通用工具（shell、改文件）不是领域能力的通道。**
  - 默认放在沙箱中，只能在 Nipa 工作区内活动；
  - 凭据不出现在 Agent 可读的位置，只以引用形式存在。
- **授权跟随意图，而不是逐条确认。**
  - `read` / `write` 直接执行；
  - `destructive` 只在用户明确表达过该意图时执行，否则返回 `NeedsDecision`。
- **执行模式由用户选择**：

  | 模式 | Agent Runtime 的通用工具 | 适用 |
  |---|---|---|
  | 标准（默认） | 工作区只读 | 普通用户 |
  | 开发者 | 工作区可写、可联网，用于生成与测试新能力 | 自进化 |
  | 完全信任（显式开启） | 不受沙箱限制 | 自担风险的高级用户 |

## 3. 分层与依赖方向

```
packages/nipa_harness/          纯 Dart，禁止依赖 Flutter 与 NipaPlay
  lib/nipa_harness.dart         内核：Schema / Action / Outcome / Decision / Failure / Harness / Journal
  lib/mcp.dart                  MCP Streamable HTTP transport（依赖 shelf）

lib/next/                       NipaPlay 侧
  capabilities/                 领域 Capability：包装现有 service / provider / VideoPlayerState
  agent_endpoint.dart           MCP 端点生命周期、令牌、工作区生成
  next_runtime.dart             组合根：用真实依赖构建 Harness，跟随 Labs 开关启停端点
```

- `nipa_harness` 是独立 package，由编译器保证内核不依赖 Flutter，将来的 headless Core、Mesh 节点可以直接复用。
- `lib/next/capabilities` 只依赖 `nipa_harness` 与现有服务；不依赖任何主题或页面 Widget。
- 现有代码不依赖 `lib/next`，唯一例外是组合根 `main.dart` 中的一个 Provider 与 Labs 设置项。

## 4. 内核 API（`package:nipa_harness/nipa_harness.dart`）

以下是公开 API 的完整形状。实现不得增加未列出的公开类型或成员。

```dart
// ── JSON ──────────────────────────────────────────────
typedef JsonMap = Map<String, Object?>;

abstract interface class JsonEncodable {
  JsonMap toJson();
}

final class NoInput implements JsonEncodable {
  const NoInput();
  @override
  JsonMap toJson() => const {};
}

// ── Schema ────────────────────────────────────────────
sealed class Schema {
  const Schema({this.description, this.nullable = false});
  final String? description;
  final bool nullable;

  /// JSON Schema (draft 2020-12 subset)。nullable 输出为 type: [<type>, "null"]。
  JsonMap toJsonSchema();

  /// 返回全部违规；空列表表示合法。path 使用 JSON Pointer（根为 ""）。
  List<SchemaViolation> validate(Object? value);
}

final class StringSchema extends Schema {
  const StringSchema({super.description, super.nullable, this.values, this.minLength});
  final List<String>? values; // 输出为 enum
  final int? minLength;
}

final class IntegerSchema extends Schema {
  const IntegerSchema({super.description, super.nullable, this.minimum, this.maximum});
  final int? minimum;
  final int? maximum;
}

final class NumberSchema extends Schema {
  const NumberSchema({super.description, super.nullable, this.minimum, this.maximum});
  final num? minimum;
  final num? maximum;
}

final class BooleanSchema extends Schema {
  const BooleanSchema({super.description, super.nullable});
}

final class ArraySchema extends Schema {
  const ArraySchema(this.items, {super.description, super.nullable});
  final Schema items;
}

final class ObjectSchema extends Schema {
  const ObjectSchema(
    this.properties, {
    this.required = const [],
    this.oneOfRequired = const [],
    super.description,
    super.nullable,
  });
  final Map<String, Schema> properties;
  final List<String> required;

  /// 互斥的必填组：恰好一组的全部字段出现，且其它组的字段都不出现。
  /// 例：[['path'], ['animeId', 'episodeId']]。输出为 oneOf: [{required: [...]}, ...]。
  final List<List<String>> oneOfRequired;
  // 始终输出 additionalProperties: false，并校验未知字段。
}

final class SchemaViolation implements JsonEncodable {
  const SchemaViolation(this.path, this.message);
  final String path;
  final String message;
}

// ── Contract ──────────────────────────────────────────
enum Effect { read, write, destructive }

final class ActionSpec {
  const ActionSpec({
    required this.id,          // ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ，如 playback.open
    required this.title,       // 简短标题
    required this.description, // 面向 Agent：做什么、何时使用、关键语义
    required this.effect,
    required this.input,
    required this.output,
  });
  final String id;
  final String title;
  final String description;
  final Effect effect;
  final ObjectSchema input;
  final ObjectSchema output;
}

abstract base class Action<I extends JsonEncodable, O extends JsonEncodable> {
  const Action();
  ActionSpec get spec;

  /// json 已通过 spec.input 校验，可直接按 schema 读取，无需再做防御性检查。
  I decodeInput(JsonMap json);

  Future<Outcome<O>> run(I input, Invocation invocation);
}

abstract interface class Capability {
  List<Action> get actions;
}

// ── Outcome ───────────────────────────────────────────
sealed class Outcome<O extends JsonEncodable> {
  const Outcome();

  /// {"status":"completed","result":{...}}
  /// {"status":"needs_decision","decision":{...}}
  /// {"status":"failed","error":{...}}
  JsonMap toEnvelope();
}

final class Completed<O extends JsonEncodable> extends Outcome<O> {
  const Completed(this.value);
  final O value;
}

final class NeedsDecision<O extends JsonEncodable> extends Outcome<O> {
  const NeedsDecision(this.decision);
  final Decision decision;
}

final class Failed<O extends JsonEncodable> extends Outcome<O> {
  const Failed(this.failure);
  final Failure failure;
}

final class Decision implements JsonEncodable {
  const Decision({required this.prompt, required this.options});
  final String prompt;
  final List<DecisionOption> options;
}

final class DecisionOption implements JsonEncodable {
  const DecisionOption({required this.label, this.detail, required this.call});
  final String label;
  final String? detail;
  final ActionCall call;
}

final class ActionCall implements JsonEncodable {
  const ActionCall(this.actionId, this.input);
  ActionCall.of(Action action, JsonEncodable input) : this(action.spec.id, input.toJson());
  final String actionId;
  final JsonMap input;
  // toJson: {"action": actionId, "input": input}
}

enum FailureCode {
  invalidInput,  // wire: invalid_input
  notFound,      // not_found
  unavailable,   // unavailable：前置条件不满足（如没有正在播放的视频）
  conflict,      // conflict
  internal;      // internal：未预期异常，只由 Harness 产生

  String get wireName;
}

final class Failure implements Exception, JsonEncodable {
  const Failure(this.code, this.message, {this.retryable = false, this.violations = const []});
  final FailureCode code;
  final String message;
  final bool retryable;
  final List<SchemaViolation> violations;
  // toJson: {"code": wireName, "message", "retryable", "violations"?: [...]}（violations 为空时省略）
}

// ── Kernel ────────────────────────────────────────────
final class Invocation {
  Invocation({required this.origin, String? id});
  final String id;      // 未提供时由内核生成，进程内唯一
  final String origin;  // 'gui' | 'mcp' | ...
}

/// 只为已注册 action 的调用产生；未知 action id 不产生记录。
final class InvocationRecord implements JsonEncodable {
  // invocationId, actionId, origin, effect, input(Object?：调用方给出的原始 JSON 输入；
  // 类型化调用时为 input.toJson()), status(envelope status), failureCode?,
  // startedAt(UTC ISO-8601), elapsedMs
}

abstract interface class InvocationObserver {
  void onInvocation(InvocationRecord record);
}

final class Harness {
  /// id 不合法或重复时抛 ArgumentError（这是装配期编程错误，应尽早暴露）。
  Harness(Iterable<Capability> capabilities, {List<InvocationObserver> observers = const []});

  /// 按 id 排序。
  List<ActionSpec> get catalog;

  Action? lookup(String actionId);

  /// 类型化调用（GUI）。
  Future<Outcome<O>> invoke<I extends JsonEncodable, O extends JsonEncodable>(
      Action<I, O> action, I input, Invocation invocation);

  /// JSON 调用（transport）。顺序：查找（未知 id → Failed(notFound)）→
  /// 校验 spec.input（违规 → Failed(invalidInput, violations)）→ decodeInput → run。
  Future<Outcome<JsonEncodable>> invokeJson(String actionId, Object? input, Invocation invocation);
}

/// 把 effect 属于 [effects] 的调用以 JSON Lines 追加到 file。
final class JsonlJournal implements InvocationObserver {
  JsonlJournal(File file, {Set<Effect> effects = const {Effect.write, Effect.destructive}});
}
```

### 4.1 Harness 的异常边界

`Harness` 是整个能力层**唯一**捕获一切异常的地方：

- `Failure` → `Failed(failure)`；
- 其它异常 → `Failed(Failure(FailureCode.internal, '<actionId> failed: <error>'))`，并通过观察者记录。

Action 内部不写兜底 `try/catch`。遇到领域失败就 `throw Failure(...)`，其余异常自然向上抛。

## 5. MCP Transport（`package:nipa_harness/mcp.dart`）

```dart
final class McpServerInfo {
  const McpServerInfo({required this.name, required this.title, required this.version});
}

final class McpEndpoint {
  McpEndpoint(this.harness, {required this.serverInfo, required this.token, this.instructions});
  final Harness harness;
  final McpServerInfo serverInfo;
  final String token;
  final String? instructions; // initialize 结果里的 instructions

  /// 处理 /mcp 的 shelf Handler（含鉴权与 Origin/Host 校验）。
  Handler get handler;

  /// 只绑定 127.0.0.1。port 为 0 时由系统分配。
  Future<HttpServer> serve({required int port});
}

/// action id → MCP 工具名（`.` → `_`）。端点与工作区审批配置共用这一规则。
String mcpToolName(String actionId);
```

协议要点（MCP Streamable HTTP，无状态，不发 `Mcp-Session-Id`）：

- 只接受 `POST /mcp`；`GET` / `DELETE` 返回 405；其它路径返回 404。
- 鉴权：`Authorization: Bearer <token>`，常量时间比较，失败返回 401。
- 防 DNS rebinding：`Host` 必须是 `127.0.0.1:<port>` 或 `localhost:<port>`；若带 `Origin`，其 host 必须是 `127.0.0.1` 或 `localhost`，否则返回 403。
- 请求体是单个 JSON-RPC 2.0 消息（不支持 batch，数组返回 -32600）。
- 通知（无 `id`）返回 202，无响应体；请求返回 `application/json`。
- `initialize`：在支持的版本 `['2025-11-25', '2025-06-18', '2025-03-26']` 中，若客户端请求的版本受支持就回显，否则返回列表首项。
  - capabilities：`{"tools": {"listChanged": false}}`；
  - 带 `serverInfo` 与 `instructions`。
- 支持 `ping`、`tools/list`、`tools/call`；其余方法返回 -32601。
- tools/list 中的工具名：`id` 中的 `.` 替换为 `_`（`playback.open` → `playback_open`）。
  - 构造时检测映射冲突，冲突抛 `ArgumentError`。
  - 每个工具包含：`name`、`title`、`description`、`inputSchema`、`outputSchema`、`annotations`。
  - `outputSchema` 是 envelope schema，其中 `result` 为 action 输出 schema。
  - `annotations` 包含 `title`、`readOnlyHint`、`destructiveHint`、`idempotentHint: false`、`openWorldHint: false`。
- tools/call：
  - 未知工具 → JSON-RPC 错误 -32602。
  - 其余一律返回工具结果 `{"content":[{"type":"text","text":<envelope JSON>}],"structuredContent":<envelope>,"isError":<status == failed>}`。
  - 输入校验失败也属于工具结果（`isError: true`），这样模型可以自行修正。
- JSON 解析失败 → -32700；缺 `jsonrpc: "2.0"` / `method` → -32600。

## 6. M1 的 Action 目录

| id | effect | 作用 |
|---|---|---|
| `media.library.search` | read | 在本机媒体库（本地 / WebDAV / SMB 已识别作品）中按名称查找作品 |
| `media.library.series` | read | 一部作品的全部剧集与文件（含观看进度） |
| `history.continue_watching` | read | “继续观看”列表 |
| `playback.open` | write | 在本机播放：指定文件 `path`，或指定 `animeId`+`episodeId`；可选 `startPositionMs` |
| `playback.state` | read | 当前播放状态 |
| `playback.set_paused` | write | 暂停 / 继续 |
| `playback.seek` | write | 绝对 `positionMs` 或相对 `offsetMs` |
| `playback.switch_episode` | write | `next` / `previous` |
| `ui.navigate` | write | 切换主页面（UI 也是工具） |

`playback.open` 按剧集打开时，若同一集存在多个文件，返回 `NeedsDecision`，每个选项是 `playback.open {path}`。

## 7. Agent 工作区

NipaPlay 在应用支持目录下生成一个 Codex 项目目录（download-harness 的产品化形态）：

```
<AppSupport>/next/workspace/
  AGENTS.md              Nipa 的“领域宪法”：意图到授权的语义、验证规则、不可信输入
  .codex/config.toml     [mcp_servers.nipaplay]：url、Authorization 头、按 Effect 生成的审批策略
```

用户在 Codex App 中把该目录添加为项目，即可用自然语言操作 NipaPlay。
令牌只保存在 `<AppSupport>/next/endpoint.json`（权限 0600），不进入 SharedPreferences，因此不会被备份或同步。

## 8. 后端与节点服务：download-harness 的超集

download-harness 中写死的部分，在 NipaPlay Next 中都是可替换的能力：

| 能力 | 可选实现 |
|---|---|
| 下载后端（`DownloadBackend`） | 应用内 rqbit（M2）、Seedbox 上的 qBittorrent WebUI API、Mesh 中的其他 NipaPlay 节点、Agent 生成的新协议适配器（如 Transmission、aria2） |
| 传输（`sync.transfer` 任务） | 把完成的文件从后端搬到存储节点：SFTP 续传（harness worker 的做法）、NipaPlay 节点间的 HTTP Range、SMB 等，同样是可替换的能力 |
| 节点服务 | 存储节点、播放节点、转码节点（例如工位机为电视转码），由设备能力决定角色 |

每个任务都记录它的后端与执行设备（`ownerDeviceId`）。由谁执行先按规则决定，规则无法决定时交给 Agent 判断。

## 9. 演进路线（M1 之后）

1. **Task Engine**：下载 / 扫描 / 同步成为持久任务，带回执与事件；只在需要判断时唤醒 Agent。M2 先做任务内核与应用内 BT 下载，Classic 下载页一同受益（`M2_TASKBOOK.md`）。
   - **Agent 刮削**：扫描与识别成为任务。高置信度由确定性程序绑定；有歧义的文件生成持久化 Decision，由 Agent（可联网查证）或用户判断。元数据多来源共存（弹弹play、Bangumi、TMDB……），一个文件或剧集挂多个外部 ID；弹弹play 的 episodeId 仍是弹幕匹配的根基。调研见 `research/METADATA_IDENTIFICATION.md`。
   - **多平台弹幕聚合**：每个平台是一个 `DanmakuSource`，契约从第一天起按插件接口设计；多个来源合并进播放器现有的多轨弹幕。弹幕源是第 5 步“可演化能力”的第一类。研究阶段只用公开接口与用户自己的登录态，不绕过会员、DRM 或付费墙。调研见 `research/DANMAKU_AGGREGATION.md`。
2. **GUI 迁移**：Classic 页面逐步改为调用 Harness。`Invocation` 增加 `interactive`，GUI 调用时由宿主把 `NeedsDecision` 渲染为对话框。
3. **Next Shell**：内嵌 Codex App Server；`ui.present` 组件目录；`ui.layout.patch` 首页布局。
4. **Preference Memory**：带来源与理由的结构化偏好。
5. **Capability Registry**：Agent 生成的能力经“校验 → 审批 → 注册 → 回滚”纳入 Harness。
6. **Mesh**：Harness 通过新的 transport 跨设备调用；`playback.handoff`。
   - **信任根是同一账号**（2026-10-10 决定）。登录同一账号（当前为经 NipaPlay 网关验证的弹弹play 账号）的设备自动互信。
     - 每个安装仍有一对 Ed25519 设备密钥，公钥登记在账号下；设备之间用设备密钥双向认证，可逐台吊销；新设备加入时通知已有设备。
     - 协调服务部署在现有 NipaPlay 服务器上（与网关、`nipaplay-relay` 同处），提供账号下的设备列表与可达地址候选。设备优先直连，不可达时走 relay；经过 relay 的流量用设备密钥端到端加密。
     - 本地优先：设备互认后缓存设备列表，服务器不可用时局域网内照常工作。
     - 二维码 / PIN 配对（`research/LAN_SECURITY.md` 的 B 档）降级为无账号时的备选方案。
     - 原因：校园网等环境常禁止广播、隔离客户端、跨网段，纯局域网发现与配对不可靠。
   - 现有局域网 API（`0.0.0.0:1180`，遥控接收端默认开启时就会启动）没有统一鉴权，存在凭据泄露、SSRF、任意文件读取等问题，详见 `research/LAN_SECURITY.md`。
   - 2026-10-10 决定：这些问题不单独热修，随设备身份与配对（该报告的 B 档）一起解决，作为 Mesh 的第一步。
