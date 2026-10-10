# M1 任务书：能力层（Harness）与本机 Agent 端点

> 设计依据：`docs/next/DESIGN.md`（必须先完整阅读）。
> 分支：`next/capability-layer`。

## M1 验收场景

在 Codex App 中打开 NipaPlay 生成的工作区，对它说“继续看《X》”或“播《X》第 3 集”，NipaPlay 开始播放。
同时满足：Labs 开关关闭时，Classic 的行为与 main 完全一致。

---

## 0. 全局规则（每个任务都必须遵守）

### 0.1 你的角色

你是实现者，不是设计者。接口、命名、文件位置都已在 DESIGN.md 和本任务书里确定。
**遇到规格没有覆盖的情况，停下来，在最终报告的「问题」一节写清楚，不要自行发明方案。**

### 0.2 禁止事项

1. **禁止防御性编程**：
   - 不写吞掉异常的 `try/catch`；不写“以防万一”的兜底分支或回退链；
   - 不对非空类型做空判断；不对已经通过 schema 校验的输入重复校验；
   - 异常边界只有 `Harness`（DESIGN §4.1）。Action 内只在领域失败时 `throw Failure(...)`。
2. 不增加规格以外的公开类型、成员、参数、配置项或抽象层。
   - 不写“为了将来扩展”的接口；不写 helper 去重复仓库里已有的工具函数。
3. 不修改白名单以外的文件。
   - 不格式化、不重命名、不“顺手”重构任何无关代码；
   - 不改生成文件（`lib/src/rust/**`、`*.g.dart`）；不改 l10n 的 arb 文件。
4. 不新增依赖（白名单明确列出的除外），不改依赖版本。
5. 不写兼容垫片、TODO 占位、空实现或假数据冒充完成。
6. 测试只测行为：不读取源码字符串做断言，不为了覆盖率测私有细节。
7. 注释只写代码本身无法表达的“为什么”。不写复述代码的注释，不写变更说明式注释。
8. 不运行 `flutter pub get` / `dart pub get` / `pub upgrade`。依赖已由主控预先解析；若解析失败，停止并报告。
9. 不提交 git commit。

### 0.3 风格

- Dart 3 风格：`sealed` / `final` / `base` class、switch 表达式与模式匹配、records。
- 小而直接的函数，名字说明意图。
- 与仓库现有风格一致：2 空格缩进；`dart format` 只作用于你新建或修改的文件。

### 0.4 每个任务的最终报告格式

1. 完成了什么（按文件列出）；
2. 验收命令及其真实输出摘要（失败也要如实写）；
3. 问题：规格没有覆盖、需要主控决定的事项；没有就写“无”。

---

## T1：`packages/nipa_harness`（内核 + MCP transport）

### 目标

实现 DESIGN §4、§5 的全部公开 API 与行为，并配完整单测。

### 允许创建 / 修改的文件

- `packages/nipa_harness/lib/nipa_harness.dart`：只做 export。
- `packages/nipa_harness/lib/mcp.dart`：只做 export。
- `packages/nipa_harness/lib/src/**`：实现文件，自行按概念拆分（如 `schema.dart`、`action.dart`、`outcome.dart`、`harness.dart`、`journal.dart`、`mcp/endpoint.dart`）。
- `packages/nipa_harness/test/**`
- 主控已创建 `pubspec.yaml` / `analysis_options.yaml`，**不要修改**。

### 行为细则

**Schema**

- `validate` 返回全部违规，不在第一个违规处停止。
- path 使用 JSON Pointer，例如 `/episodes/0/path`；根为 `""`。
- `IntegerSchema` 接受 `int`，也接受“值为整数的 `double`”（JSON 数字解码的常见情况），拒绝 `1.5`。
- `NumberSchema` 接受任意 `num`。
- `nullable: false` 时 `null` 违规；`nullable: true` 时 `null` 合法。
- `ObjectSchema`：
  - 未知字段违规；`required` 字段缺失违规；
  - `oneOfRequired`：恰好一组的字段全部出现、且其他组的字段一个都不出现才合法，违规信息要指出期望的组。
  - 非 Map 值违规。Map 的键必须是 String。
- `toJsonSchema`：
  - 输出 `type` / `description` / `enum` / `minimum` / `maximum` / `minLength` / `items` / `properties` / `required` / `additionalProperties: false` / `oneOf`；
  - 没有值的键不输出。

**Action id**

- 必须匹配 `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`，否则 `Harness` 构造时抛 `ArgumentError`。

**Harness**

- `invokeJson` 的 `input` 为 `null` 时按 `{}` 处理。
- 非 Map 输入 → `Failed(invalidInput)`，violations 指向根。
- `Invocation.id` 未提供时，生成形如 `inv-<microsecondsSinceEpoch>-<进程内递增序号>` 的 id。
- 每次调用（包括失败）恰好通知每个观察者一次。
- 观察者自身抛出的异常不影响调用结果：这是 Harness 异常边界的一部分，用 `Zone`/`try` 隔离后丢弃。

**InvocationRecord**

- `toJson` 字段为：`invocationId`、`actionId`、`origin`、`effect`（`read`/`write`/`destructive`）、`input`、`status`、`failureCode`（仅失败时）、`startedAt`、`elapsedMs`。

**JsonlJournal**

- 每条记录一行 `jsonEncode(record.toJson())`，追加写入并 flush。父目录不存在时创建。

**MCP**

- 严格按 DESIGN §5 实现。`serve` 绑定 `InternetAddress.loopbackIPv4`。
- `Host` 校验使用实际监听端口（`port: 0` 时取系统分配的端口）。

### 必须覆盖的测试（`dart test`）

- **Schema**：各类型合法 / 非法值；嵌套路径；nullable；未知字段；`oneOfRequired` 的三种情况（恰好一组、零组、两组）；`toJsonSchema` 的精确输出。
- **Harness**：
  - 重复 id、非法 id 抛错；`catalog` 排序；
  - 未知 action → `not_found`；非法输入 → `invalid_input`，且包含 violations；
  - Action 抛 `Failure` → 原样返回；Action 抛其他异常 → `internal`；
  - `NeedsDecision` 的 envelope；观察者记录内容；观察者抛异常不影响结果。
- **JsonlJournal**：只记录指定 effect；多次调用追加多行。
- **MCP handler**（直接调用 `handler`，不起端口）：
  - `initialize` 版本协商（受支持版本回显；不受支持版本返回首项）；
  - 通知返回 202；`ping`；`tools/list` 的名称映射、annotations、inputSchema / outputSchema；
  - `tools/call` 的 completed / needs_decision / failed（`isError`）三种结果；
  - 未知工具 -32602；未知方法 -32601；坏 JSON -32700；数组请求 -32600；
  - 缺 / 错 token 401；坏 Origin 403；坏 Host 403；`GET` 405；其他路径 404。
- **MCP serve**：`port: 0` 起服务，用 `HttpClient` 走一次 `initialize` + `tools/call`，确认只监听 127.0.0.1。

### 验收命令

```bash
cd packages/nipa_harness
dart analyze --fatal-infos
dart test
```

---

## T2：NipaPlay 领域 Capability（`lib/next/capabilities`）

### 目标

实现 DESIGN §6 的 9 个 Action，以纯依赖注入方式包装现有服务，并配单测。

### 允许创建的文件

- `lib/next/capabilities/library_capability.dart`
- `lib/next/capabilities/history_capability.dart`
- `lib/next/capabilities/playback_capability.dart`
- `lib/next/capabilities/navigation_capability.dart`
- `lib/next/capabilities/media_models.dart`：本任务的 DTO 与它们的 `ObjectSchema` 常量
- `lib/next/capabilities/video_player_state_port.dart`：`PlayerPort` 的 `VideoPlayerState` 实现
- `test/next/**`

**不修改任何现有文件。**

### 公共约定

- 每个 Action 一个 `final class`，继承 `Action<I, O>`，`spec` 为 `static const` 加 getter 返回。
  - 输入、输出 DTO 实现 `JsonEncodable`；输出 DTO 的 schema 与 `toJson` 一一对应。
- 时间一律输出为 UTC ISO-8601 字符串。
- 面向 Agent 的文本（`title` / `description` / `Decision.prompt` / 选项 `label`）使用英文。`description` 写清用途、关键语义与返回值含义，1–4 句。
- **作品标题规则**（library 与 history 共用，写在 `media_models.dart` 里的一个顶层函数）：
  - `title`：`BangumiAnime.nameCn`（非空时），否则 `BangumiAnime.name`，否则文件记录的 `animeName`；
  - `originalTitle`：`BangumiAnime.name`，仅当它与 `title` 不同时输出，否则为 `null`；
  - `imageUrl`：`BangumiAnime.imageUrl`（非空时），否则 `null`。

### Capability 构造函数（依赖全部注入；签名必须完全一致）

```dart
final class LibraryCapability implements Capability {
  LibraryCapability({
    required Iterable<WatchHistoryItem> Function() history,
    required BangumiAnime? Function(int animeId) seriesDetail,
  });
}

final class HistoryCapability implements Capability {
  HistoryCapability({
    required List<WatchHistoryItem> Function() continueWatching,
    required BangumiAnime? Function(int animeId) seriesDetail,
  });
}

enum EpisodeDirection { next, previous }

abstract interface class PlayerPort {
  PlaybackSnapshot snapshot();
  void setPaused(bool paused);
  void seekTo(Duration position);
  Future<void> switchEpisode(EpisodeDirection direction);
}

final class PlaybackCapability implements Capability {
  PlaybackCapability({
    required PlayerPort player,
    required Future<bool> Function(PlayableItem item) start,
    required bool Function() usesExternalPlayer,
    required Future<WatchHistoryItem?> Function(String path) historyItem,
    required Future<WatchHistoryItem?> Function(int animeId, int episodeId) episodeItem,
    required EpisodeFileSelectionService fileSelection,
  });
}

final class NavigationCapability implements Capability {
  NavigationCapability({required void Function(String pageId) changePage});
}

final class VideoPlayerStatePort implements PlayerPort {
  VideoPlayerStatePort(VideoPlayerState state);
}
```

### Action 规格

**`media.library.search`**（read）

- 输入：`{query?: string(minLength 1), limit?: integer 1..200}`，`limit` 默认 50。
- 输出：`{series: SeriesSummary[], total: integer}`。
- 媒体库条目 = `history()` 中满足 `mediaLibraryItemMatchesSource(item, s)` 的条目，`s` 取 `UnifiedMediaLibrarySource.values` 任一。这是现有媒体库页面的同一定义，直接调用该函数。
- 按 `animeId` 分组。
- `query` 不区分大小写，子串匹配作品的 `title`、`originalTitle`，以及该作品任一文件记录的 `animeName`。
- 按最近观看时间倒序。`total` 为截断前的匹配数。
- `SeriesSummary` 字段：
  - `animeId`、`title`、`originalTitle`（nullable）、`imageUrl`（nullable）；
  - `episodeCount`：不同 `episodeId` 的数量，`episodeId` 为空的文件各算一集；
  - `fileCount`；`lastWatchedAt`。

**`media.library.series`**（read）

- 输入：`{animeId: integer}`。
- 输出：`{series: SeriesSummary, episodes: EpisodeEntry[]}`。作品不存在 → `Failure(notFound)`。
- `EpisodeEntry` 为 `{episodeId(nullable), title, files: EpisodeFile[]}`：
  - `title` 取该集最近观看文件的 `episodeTitle`，为空时取文件名（`path` 包的 `basename`）；
  - 排序：`episodeId` 升序，空值排最后，空值之间按 `title`。
- `EpisodeFile` 为 `{path, source: 'local'|'webdav'|'smb', progress(number 0..1), positionMs, durationMs, lastWatchedAt}`：
  - `source` 由 `UnifiedMediaLibrarySource` 判定；
  - 文件按最近观看倒序。

**`history.continue_watching`**（read）

- 输入：`{limit?: integer 1..100}`，默认 20。
- 输出：`{items: ContinueItem[]}`，顺序沿用 `continueWatching()`。
- `ContinueItem` 字段：`path`、`animeId`（nullable）、`seriesTitle`、`episodeId`（nullable）、`episodeTitle`（nullable）、`progress`、`positionMs`、`durationMs`、`lastWatchedAt`。
  - `seriesTitle`：`animeId` 存在时按标题规则；否则取 `animeName`；`animeName` 也为空时取文件名。

**`playback.open`**（write）

- 输入：`{path?: string(minLength 1), animeId?: integer, episodeId?: integer, startPositionMs?: integer ≥0}`，`oneOfRequired: [['path'], ['animeId','episodeId']]`。
- 输出：`{path: string, player: 'internal'|'external', state: PlaybackSnapshot}`。
- 流程：
  1. `startPositionMs != null && usesExternalPlayer()` → `Failure(unavailable)`，说明外部播放器不支持指定起点。此检查在启动任何播放之前进行。
  2. **按 path**：`historyItem(path)` 为空 → `Failure(notFound)`（只允许打开媒体库或历史中存在的文件）；否则直接得到 `PlayableItem`，不做文件选择。
  3. **按剧集**：`episodeItem(animeId, episodeId)` 为空 → `Failure(notFound)`。否则调用 `fileSelection.resolve(requested, choose: …)`：
     - 若 `choose` 被调用（同一集有多个文件）：记录候选并返回 `null`，随后本 Action 返回 `NeedsDecision`。
       - 每个候选一个选项：`label` 为 `EpisodeFileCandidate.displayPath` 的 basename；`detail` 为 `'${sourceLabel} · ${进度百分比}% watched'`；
       - `call` 为 `playback.open {path: candidate.history.filePath}`，若原请求带 `startPositionMs` 则一并带上。
     - 若 `choose` 未被调用且 `resolve` 返回 `null` → `Failure(notFound)`。
  4. 历史条目转 `PlayableItem` 的规则：`videoPath`=`filePath`，`title`=`animeName`，`subtitle`=`episodeTitle`，`animeId`、`episodeId`、`historyItem`、`mediaKey` 照抄。
  5. `start(item)` 返回 `false` → `Failure(unavailable, retryable: true)`，说明 NipaPlay 当前无法开始播放（例如窗口未就绪）。
  6. 内置播放器且 `startPositionMs != null` 时，`player.seekTo(...)`。
  7. 返回 `path`=最终播放的 `videoPath`、`player`、`state`=`player.snapshot()`。

**`playback.state`**（read）

- 输入：`{}`（`NoInput`）。
- 输出：`{state: PlaybackSnapshot}`。
- `PlaybackSnapshot` 字段：
  - `status`：`PlayerStatus` 的 name；`hasVideo`、`paused`；
  - `path`、`seriesTitle`、`episodeTitle`、`animeId`、`episodeId`：均 nullable；
  - `positionMs`、`durationMs`、`rate`；
  - `canPrevious`、`canNext`。

**`playback.set_paused`**（write）

- 输入：`{paused: boolean}`。
- 输出：`{state}`。
- 无视频（`!snapshot().hasVideo`）→ `Failure(unavailable)`。

**`playback.seek`**（write）

- 输入：`{positionMs?: integer ≥0, offsetMs?: integer}`，`oneOfRequired: [['positionMs'], ['offsetMs']]`。
- 输出：`{state}`。
- 无视频 → `Failure(unavailable)`。目标位置夹在 `[0, durationMs]` 内。

**`playback.switch_episode`**（write）

- 输入：`{direction: 'next'|'previous'}`。
- 输出：`{state}`。
- 无视频，或对应方向的 `canNext`/`canPrevious` 为假 → `Failure(unavailable)`。
- 否则 `await player.switchEpisode(...)` 后返回新状态。

**`ui.navigate`**（write）

- 输入：`{page: AppPageIds.primaryOrder 中的值}`（schema 的 `values` 直接引用该常量）。
- 输出：`{page}`。

**`VideoPlayerStatePort`**

- `snapshot` 读取 `VideoPlayerState` 的现有 getter：
  - `status`、`hasVideo`、`isPaused`；
  - `currentVideoPath`、`animeTitle`、`episodeTitle`、`animeId`、`episodeId`；
  - `position`、`duration`、`playbackRate`；
  - `canPlayPreviousEpisode`、`canPlayNextEpisode`。
- `setPaused` 调用 `pause()` / `play()`；`seekTo` 调用 `seekTo`。
- `switchEpisode` 调用 `playNextEpisode()` / `playPreviousEpisode()`。

### 必须覆盖的测试（`flutter test test/next`）

- 用构造函数注入的假依赖测试每个 Action：正常路径、`notFound` / `unavailable` 路径；
- `playback.open` 的三条路径：按 path、按剧集单文件、按剧集多文件 → `NeedsDecision`，且选项的 `call` 可被 `Harness.invokeJson` 直接执行；
- 外部播放器 + `startPositionMs` → `unavailable`，且 `start` 未被调用；
- **契约测试**：每个 Action 的真实输出 `toJson()` 通过其 `spec.output.validate`（零违规）。
- 测试通过 `Harness.invokeJson` 调用，覆盖从 JSON 输入到 envelope 的完整路径。
- `VideoPlayerStatePort` 不测（需要真实播放器），由 T3 端到端验证。

### 验收命令

```bash
flutter analyze lib/next test/next
flutter test test/next
```

---

## T3：运行时装配、Agent 端点、工作区与 Labs 开关

### 目标

Labs 开关打开后，NipaPlay 在 `127.0.0.1:47811` 提供 MCP 端点，并生成 Codex 工作区；关闭后端点停止。

### 允许创建 / 修改的文件

- 新建 `lib/next/next_runtime.dart`、`lib/next/agent_endpoint.dart`、`lib/next/agent_workspace.dart`
- 新建 `test/next/agent_workspace_test.dart`、`test/next/agent_endpoint_test.dart`
- 修改 `lib/constants/settings_keys.dart`：新增 `labsEnableAgentEndpoint = 'labs_enable_agent_endpoint'`
- 修改 `lib/providers/labs_settings_provider.dart`：新增 `enableAgentEndpoint` 与 `setEnableAgentEndpoint`，写法与现有两个开关完全一致
- 修改 `lib/settings/pages/labs_settings_content.dart`：新增一个开关和一个状态区
- 修改 `lib/main.dart`：在 `MultiProvider` 的 providers 末尾追加一项（见下）

`assets/next/AGENTS.md` 与 `pubspec.yaml`（已注册该 asset 与 `nipa_harness` 依赖）由主控提供，**不要修改**。

### 规格

**`AgentEndpointStatus`**（`agent_endpoint.dart`）

```dart
sealed class AgentEndpointStatus { const AgentEndpointStatus(); }
final class AgentEndpointStopped extends AgentEndpointStatus { const AgentEndpointStopped(); }
final class AgentEndpointRunning extends AgentEndpointStatus {
  const AgentEndpointRunning({required this.url, required this.workspace});
  final Uri url;              // http://127.0.0.1:47811/mcp
  final Directory workspace;
}
final class AgentEndpointFailed extends AgentEndpointStatus {
  const AgentEndpointFailed(this.message);
  final String message;
}
```

**`AgentEndpoint`**

```dart
final class AgentEndpoint {
  AgentEndpoint({
    required Harness harness,
    required Directory root,        // <AppStorage>/next
    required String appVersion,
    required String agentsMd,       // assets/next/AGENTS.md 的内容
    int port = 47811,
  });
  Future<AgentEndpointStatus> start();
  Future<void> stop();
}
```

`start()` 的步骤：

1. 读取 `root/endpoint.json` 中的 `token`。文件不存在时：
   - 生成 32 字节 `Random.secure()` 随机数，base64url 编码、去掉 padding 作为 token；
   - 写入该文件；非 Windows 平台用 `chmod 600` 设置权限。
2. 构造 `McpEndpoint`：
   - `serverInfo`：name `nipaplay`、title `NipaPlay`、version `appVersion`；
   - `instructions`：一段英文，说明“先查询再行动；`needs_decision` 时，若用户意图已能确定选项就执行该选项的 `call`，否则询问用户；遵循工作区 `AGENTS.md`”。
3. `serve(port: port)`。端口被占用等 `SocketException` → 返回 `AgentEndpointFailed`，消息包含端口号。这是 `start()` 唯一允许处理的异常。
4. 调用 `writeAgentWorkspace(...)`，然后返回 `AgentEndpointRunning`。

`stop()` 关闭 server。重复调用 `start()` / `stop()` 幂等。

**`writeAgentWorkspace`**（`agent_workspace.dart`）

```dart
Future<void> writeAgentWorkspace({
  required Directory directory,     // root/workspace
  required Uri url,
  required String token,
  required List<ActionSpec> catalog,
  required String agentsMd,
});
```

- 写入 `AGENTS.md`（内容为 `agentsMd` 原文）。
- 写入 `.codex/config.toml`，内容恰好如下，`<tool>` 为 destructive action 的 MCP 工具名（`.`→`_`）；M1 没有 destructive action，因此不会出现 tools 段：

```toml
[mcp_servers.nipaplay]
url = "<url>"
http_headers = { Authorization = "Bearer <token>" }
default_tools_approval_mode = "auto"

[mcp_servers.nipaplay.tools.<tool>]
approval_mode = "prompt"
```

- 两个文件都是整文件覆盖写入。

**`NextRuntime`**（`next_runtime.dart`）

```dart
final class NextRuntime extends ChangeNotifier {
  /// 组合根：用真实服务构建 Harness 与 AgentEndpoint，并跟随 Labs 开关启停端点。
  factory NextRuntime.fromContext(BuildContext context);
  Harness get harness;
  AgentEndpointStatus get endpointStatus;
}
```

- 依赖装配：
  - `LibraryCapability`：`history` 取 `ServiceProvider.watchHistoryProvider.history`；`seriesDetail` 取 `BangumiService.instance.getAnimeDetailsFromMemory`。
  - `HistoryCapability`：`continueWatching` 取 `ServiceProvider.watchHistoryProvider.continueWatchingItems`。
  - `PlaybackCapability`：
    - `player` 为 `VideoPlayerStatePort(context.read<VideoPlayerState>())`；
    - `start` 为 `(item) => PlaybackService().play(item, episodeFileSelectionHandled: true)`；
    - `usesExternalPlayer` 为 `() => context.read<SettingsProvider>().useExternalPlayer`（在 `fromContext` 里先取得 provider 实例再闭包，不在闭包里保存 `context`）；
    - `historyItem` 为 `WatchHistoryManager.getHistoryItem`；`episodeItem` 为 `WatchHistoryManager.getHistoryItemByEpisode`；
    - `fileSelection` 为 `EpisodeFileSelectionService()`。
  - `NavigationCapability`：`changePage` 取 `context.read<TabChangeNotifier>().changePage`。
  - `Harness` 的 observers 为 `[JsonlJournal(File('<root>/journal.jsonl'))]`。
- `root` = `StorageService.getAppStorageDirectory()` 下的 `next` 子目录；`agentsMd` 用 `rootBundle.loadString('assets/next/AGENTS.md')`；`appVersion` 用 `PackageInfo.fromPlatform()`。这些异步准备在 runtime 内部完成，完成前端点状态为 `AgentEndpointStopped`。
- 监听 `LabsSettingsProvider`：先 `await labs.ready`，此后 `enableAgentEndpoint` 为真则 `start()`，为假则 `stop()`。状态变化时 `notifyListeners()`。
- `dispose` 时停止端点并移除监听。

**`main.dart`**：在 providers 列表末尾追加：

```dart
if (!kIsWeb)
  ChangeNotifierProvider(lazy: false, create: NextRuntime.fromContext),
```

**Labs 页面**

- 新开关：
  - 标题 `Agent 接口（NipaPlay Next）` / `Agent 介面（NipaPlay Next）` / `Agent Endpoint (NipaPlay Next)`；
  - 副标题说明“在本机开放 MCP 接口，可在 Codex 中用对话操作 NipaPlay”，三语；
  - 仅在 `globals.isDesktop` 时显示；文本使用页面现有的 `_text` 函数。
- 开关打开时，用 `Consumer<NextRuntime>` 显示状态：
  - Running：显示 url 与工作区路径，并提供 `AdaptiveSettingsTile.button`“打开工作区文件夹”，调用 `FolderOpener.open(workspace.path)`；
  - Failed：显示错误信息；
  - Stopped：显示“正在启动…”。
- 只使用页面里已有的组件，不新增 Widget 类。

### 必须覆盖的测试

- `agent_workspace_test`：生成的 `AGENTS.md` 与 `config.toml` 内容精确匹配。用一个带 destructive action 的假 catalog 验证 tools 段。
- `agent_endpoint_test`：
  - 用临时目录与 `port: 0`（测试中允许传 0）启动，验证 token 文件创建、权限为 600（非 Windows），且重启后 token 不变；
  - 验证带 token 的 `initialize` 成功；端口占用时返回 `AgentEndpointFailed`。
- `NextRuntime` 不写单测（依赖完整 Provider 树），由端到端验收覆盖。

### 验收命令

```bash
flutter analyze lib/next lib/settings/pages/labs_settings_content.dart lib/providers/labs_settings_provider.dart lib/main.dart test/next
flutter test test/next
```
