import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import '../agent_endpoint.dart';
import '../chat/chat_host.dart';
import '../chat/dsh_runtime.dart';
import '../chat/session_store.dart';
import '../followups/service.dart';
import '../harness_redaction.dart';
import '../memory/recent.dart';
import '../memory/service.dart';
import '../runtime/dsh_manifest.dart';
import '../state/query.dart';
import '../tasks/job_origin.dart';
import 'dsh.dart';
import 'model.dart';

/// Whether this host runs Nipa: `<data>/agent.json` (`{"enabled": false}`
/// turns her off). On unless it says otherwise. Only the person at the host
/// writes it (the command line); no Action or setting reaches it.
abstract final class HeadlessAgentSwitch {
  static File _file(Directory root) => File('${root.path}/agent.json');

  static Future<bool> enabled(Directory root) async {
    final file = _file(root);
    if (!await file.exists()) return true;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is! Map || value['enabled'] != false;
    } on FormatException {
      return true;
    }
  }

  static Future<void> set(Directory root, bool enabled) async {
    await root.create(recursive: true);
    final file = _file(root);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode({'enabled': enabled}), flush: true);
    await pending.rename(file.path);
  }
}

enum HeadlessNipaState {
  /// The agent switch of this host is off.
  disabled,

  /// The model, its key, the runtime or the assets are not there.
  missing,
  starting,
  running,

  /// It was started and did not come up, or has stopped since.
  failed,
}

/// The conversation host on a headless machine: Nipa on DeepSeek Harness,
/// with her own harness repository, memory and hooks. It keeps one
/// [ChatHost] while the agent switch is on and the model, its key and the
/// runtime are in place, and says in plain facts why it is not running when
/// one of them is missing.
///
/// Nothing is polled. The host looks again when a file it depends on changes
/// (`agent.json`, `model.json`, the `dsh-runtime` directory), so a model set
/// from the command line reaches a running host at once. A running host
/// takes a changed model at its next turn, as on the desktop.
final class HeadlessNipa {
  HeadlessNipa(
      {required this.root,
      required this.repository,
      required this.agentAssets,
      required this.model,
      required this.followups,
      required this.engine,
      required this.jobOrigins,
      required this.memory,
      required this.sessions,
      required this.activityPage,
      this.staleSources = const [],
      this.redact,
      Map<String, String>? environment})
      : environment = environment ?? Platform.environment;

  /// The data directory (what the desktop calls Next's root).
  final Directory root;

  /// Nipa's harness repository.
  final Directory repository;

  /// `assets/next/agent`: the manifest and NipaPlay's DSH plugins.
  final Directory agentAssets;
  final HeadlessModel model;
  final Followups followups;
  final TaskEngine engine;
  final JobOrigins jobOrigins;
  final HarnessMemory memory;
  final SessionStore sessions;
  final Future<StateRows> Function(int offset, int limit) activityPage;

  /// Streams that fire when what 动态 shows has grown.
  final List<Stream<Object?>> staleSources;
  final Future<String> Function(String)? redact;
  final Map<String, String> environment;

  /// Set once the endpoint exists (it needs the capabilities built from this).
  late AgentEndpoint endpoint;

  static const _pluginFiles = [
    'nipa-app-server.mjs',
    'nipa-memory.mjs',
    'persona-prefix.md',
    'persona-suffix.md'
  ];

  ChatHost? _host;
  bool _enabled = true, _closed = false;

  /// The host answered its first requests and has its main conversation.
  bool _ready = false;
  HeadlessNipaState _state = HeadlessNipaState.missing;
  String? _reason;
  List<String> _missing = const [];
  DshRuntime? _runtime;
  String? _runtimeSource;
  Future<void> _chain = Future.value();
  final _subscriptions = <StreamSubscription<Object?>>[];
  StreamSubscription<FileSystemEvent>? _rootWatch, _runtimeWatch;
  Timer? _debounce;
  final _changes = StreamController<void>.broadcast();

  /// The conversation host while it is up; null when Nipa is not running
  /// (including while she is still starting).
  ChatHost? get host {
    final host = _host;
    return _ready && host != null && host.available ? host : null;
  }

  HeadlessNipaState get state => _state;

  /// Why Nipa is not running, in a sentence; null while she is.
  String? get reason => host == null ? _reason : null;

  /// Fires when the facts of [facts] changed.
  Stream<void> get changes => _changes.stream;

  /// Completes when the work asked of this host so far is done.
  Future<void> get settled => _chain;

  /// Begins watching the files Nipa depends on and brings her up if she can
  /// be. Returns at once; [settled] completes when she is up or has said why
  /// not.
  void start() {
    _watchRoot();
    unawaited(reload());
  }

  /// Looks at the switch, the model and the runtime again, and starts or
  /// stops Nipa to match. A running host is left alone (a changed model
  /// reaches it at its next turn).
  Future<void> reload() {
    final next = _chain.then((_) => _reconcile()).catchError(
        (Object error, StackTrace stack) {
      _fail('Nipa could not be brought up: ${redactHarnessText('$error')}');
    });
    return _chain = next;
  }

  void _watchRoot() {
    try {
      _rootWatch = root.watch().listen((event) {
        final names = {
          p.basename(event.path),
          if (event is FileSystemMoveEvent && event.destination != null)
            p.basename(event.destination!),
        };
        if (names.contains('dsh-runtime')) _watchRuntime();
        if (names.any(const {'agent.json', 'model.json', 'dsh-runtime'}.contains)) {
          _later();
        }
      }, onError: (Object _) {});
    } on FileSystemException {
      // A host that cannot watch still reads the files when it is asked to.
    }
    _watchRuntime();
  }

  void _watchRuntime() {
    if (_runtimeWatch != null) return;
    final directory = Directory('${root.path}/dsh-runtime');
    if (!directory.existsSync()) return;
    try {
      _runtimeWatch =
          directory.watch().listen((_) => _later(), onError: (Object _) {});
    } on FileSystemException {
      // See above.
    }
  }

  void _later() {
    if (_closed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(reload());
    });
  }

  void _set(HeadlessNipaState state, String? reason,
      {List<String> missing = const []}) {
    _state = state;
    _reason = reason;
    _missing = missing;
    if (!_changes.isClosed) _changes.add(null);
  }

  void _fail(String reason) => _set(HeadlessNipaState.failed, reason);

  Future<void> _reconcile() async {
    if (_closed) return;
    _enabled = await HeadlessAgentSwitch.enabled(root);
    if (!_enabled) {
      const reason =
          'The agent switch of this host is off; run --agent-enable.';
      await _stopHost(reason);
      _set(HeadlessNipaState.disabled, reason);
      return;
    }
    if (host != null) {
      _set(HeadlessNipaState.running, null);
      return;
    }
    if (_host != null) {
      // The runtime process went away: say so, and start a fresh one.
      await _stopHost('The conversation host stopped.');
    }
    final missing = <String>[];
    final reasons = <String>[];
    DshRuntime? runtime;
    String? source;
    try {
      final dsh = HeadlessDsh.open(
          data: root, agentAssets: agentAssets, environment: environment);
      runtime = await dsh.locate();
      source = dsh.fixed ? 'environment' : 'installed';
    } on StateError catch (error) {
      await _stopHost(error.message);
      _fail(redactHarnessText(error.message));
      return;
    } on FileSystemException {
      missing.add('agentAssets');
      reasons.add('the agent assets are not at ${agentAssets.path} '
          '(--agent-assets)');
    }
    for (final name in _pluginFiles) {
      if (!await File('${agentAssets.path}/dsh/$name').exists() &&
          !missing.contains('agentAssets')) {
        missing.add('agentAssets');
        reasons.add('the agent assets are not at ${agentAssets.path} '
            '(--agent-assets)');
      }
    }
    final facts = await model.facts();
    if (facts.missing.contains('model')) {
      missing.add('model');
      reasons.add('no model is set (--model-set)');
    }
    if (facts.missing.contains('key')) {
      missing.add('key');
      reasons.add('no model key is set (--model-set with --key-stdin)');
    }
    if (runtime == null && !missing.contains('agentAssets')) {
      missing.add('runtime');
      reasons.add('the DeepSeek Harness runtime is not installed '
          '(--dsh-install)');
    }
    _runtime = runtime;
    _runtimeSource = source;
    if (missing.isNotEmpty) {
      final reason = 'Nipa cannot start on this host: ${reasons.join('; ')}.';
      await followups.attach(null, reason: reason);
      _set(HeadlessNipaState.missing, reason, missing: missing);
      return;
    }
    await _startHost(runtime!);
  }

  Future<void> _startHost(DshRuntime runtime) async {
    _set(HeadlessNipaState.starting, 'Nipa is starting.');
    final plugins =
        await Directory('${root.path}/agent/dsh').create(recursive: true);
    for (final name in _pluginFiles) {
      final target = File('${plugins.path}/$name');
      final pending = File('${target.path}.pending');
      await pending.writeAsString(
          await File('${agentAssets.path}/dsh/$name').readAsString(),
          flush: true);
      await pending.rename(target.path);
    }
    final host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        memory: memory,
        sessions: sessions,
        modelLaunch: model.launch,
        dsh: runtime,
        dshPlugins: plugins,
        // The harness's own ./nipa finds this endpoint from the hooks and
        // from her shell alike.
        environment: {'NIPAPLAY_ENDPOINT_FILE': endpoint.credentialFile.path});
    _host = host;
    jobOrigins.threadFor = host.threadForOrigin;
    memory.recent = (current) async {
      final activity = await activityPage(0, 5);
      return recentMemoryFacts(host, await activeJobFacts(engine),
          await followups.activeList(), activity.rows, current,
          activityTotal: activity.total,
          harnessUpdate: endpoint.harnessUpdate,
          finishedHelpers: [
            for (final job in ((await engine.list(type: 'agent.helper'))
                    .where((job) => job.state.isTerminal)
                    .toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
                .take(3))
              job.toJson()
          ],
          redact: redact);
    };
    // The memory block carries the latest 动态; tell the runtime when it grew.
    for (final source in [engine.changes, ...staleSources]) {
      _subscriptions.add(source.listen((_) => host.memoryChanged()));
    }
    _subscriptions.add(host.events.listen((event) {
      if (event['method'] == 'host/error' && identical(_host, host)) {
        _fail('The conversation host stopped: '
            '${(event['params'] as Map)['message']}');
      }
    }));
    try {
      await host.start();
      await host.getMainSession();
      await followups.attach(host);
      if (_closed) return;
      _ready = true;
      _set(HeadlessNipaState.running, null);
    } catch (error) {
      final reason = redactHarnessText(error.toString());
      await _stopHost(reason);
      _fail('Nipa did not come up: $reason');
    }
  }

  Future<void> _stopHost(String reason) async {
    final host = _host;
    if (host == null) return;
    _host = null;
    _ready = false;
    await followups.attach(null, reason: reason);
    jobOrigins.threadFor = null;
    memory.recent = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await host.close();
  }

  /// Non-secret facts of the conversation host, for the device description
  /// and for `app.runtime`.
  JsonMap facts() {
    final live = host;
    final threads = live?.threadLiveness.keys ?? const <String>[];
    return {
      'enabled': _enabled,
      'state': live != null ? HeadlessNipaState.running.name : _state.name,
      'runs': live != null,
      if (live == null && _reason != null) 'reason': _reason,
      if (live == null && _missing.isNotEmpty) 'missing': _missing,
      if (live != null) ...{
        'model': live.model,
        'provider': live.provider,
        'busy': threads.any(live.busyFor),
        'mainThreadId': live.mainThreadId,
      },
    };
  }

  /// The runtime Nipa thinks with, as it is on this host now.
  Future<JsonMap> runtimeFacts() async {
    final platform = DshManifest.hostPlatform();
    final selected = _runtime;
    return {
      'kind': 'dsh',
      'platform': platform,
      'supported': platform != null,
      'installed': selected != null,
      if (selected != null) ...{
        'version': selected.version,
        'source': _runtimeSource,
      },
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _debounce?.cancel();
    await _rootWatch?.cancel();
    await _runtimeWatch?.cancel();
    try {
      await _chain;
    } catch (_) {}
    await _stopHost('NipaPlay is shutting down.');
    await _changes.close();
  }
}
