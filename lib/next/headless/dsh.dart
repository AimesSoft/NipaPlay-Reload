import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../chat/dsh_runtime.dart';
import '../harness_redaction.dart';
import '../runtime/dsh_install.dart';
import '../runtime/dsh_manifest.dart';
import '../ui_data/host_settings.dart';

/// Where the headless host finds the runtime Nipa runs on, and how it gets
/// one: DeepSeek Harness on the pinned Node.js, the same trimmed tree the
/// desktop app downloads.
///
/// The headless host has no conversation of its own yet (its description says
/// `conversationHost: false`), so nothing here is started by [HeadlessCore];
/// this is what the host's command line uses to prepare and prove a runtime
/// (`--dsh-install`, `--dsh-status`, `--dsh-check`), and what a conversation
/// host would ask for its [DshRuntime].
///
/// Selection, in order:
///  1. `NIPAPLAY_AGENT_RUNTIME=dsh` with `NIPAPLAY_DSH_NODE` and
///     `NIPAPLAY_DSH_ROOT` (or `NIPAPLAY_DSH_BIN`): an installation of your own.
///  2. The runtime installed under `<data>/dsh-runtime`.
/// `NIPAPLAY_AGENT_RUNTIME=codex` is refused: this host has no Codex.
final class HeadlessDsh {
  HeadlessDsh._(this.data, this.agentAssets, this.install, this._fixed);

  /// [agentAssets] is `assets/next/agent`: it holds `dsh-runtime.json` (the
  /// manifest) and `dsh/` (NipaPlay's DSH plugins and persona).
  factory HeadlessDsh.open(
      {required Directory data,
      required Directory agentAssets,
      Map<String, String>? environment,
      HttpClient Function()? httpClient,
      String? platform,
      DshFallback? fallback}) {
    final env = environment ?? Platform.environment;
    final fixed = AgentRuntimeFixed.read(env);
    if (fixed.kind == AgentRuntimeKind.codex) {
      throw StateError('The headless host runs Nipa on DeepSeek Harness; '
          'NIPAPLAY_AGENT_RUNTIME=codex is not available here.');
    }
    final manifest = DshManifest.parse(
        File(p.join(agentAssets.path, 'dsh-runtime.json')).readAsStringSync());
    return HeadlessDsh._(
        data,
        agentAssets,
        DshInstall(
            root: Directory(p.join(data.path, 'dsh-runtime')),
            manifest: manifest,
            platform: platform ?? DshManifest.hostPlatform(),
            notify: () {},
            httpClient: httpClient ?? HttpClient.new,
            inUse: () => false,
            fallback: fallback ?? DshFallback.npmmirror),
        fixed.dsh);
  }

  final Directory data;
  final Directory agentAssets;
  final DshInstall install;
  final DshRuntime? _fixed;

  /// The runtime to launch, or null while there is none.
  Future<DshRuntime?> locate() async => _fixed ?? await install.runtime();

  /// Whether [locate] answers with an installation of the person's own.
  bool get fixed => _fixed != null;

  /// [locate], installing the pinned runtime first when there is none.
  /// [progress] hears the download as it goes.
  Future<DshRuntime> ensure({void Function(UiDshRuntime state)? progress}) async {
    if (await locate() case final runtime?) return runtime;
    if (!install.supported) {
      throw StateError('No DeepSeek Harness runtime is pinned for '
          '${install.platform ?? 'this platform'}.');
    }
    Timer? ticker;
    if (progress != null) {
      ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
        progress(await install.state());
      });
    }
    try {
      await install.install();
    } finally {
      ticker?.cancel();
    }
    final state = await install.state();
    if (await locate() case final runtime?) return runtime;
    throw StateError(state.problem ?? 'The DeepSeek Harness runtime was not installed.');
  }

  /// Starts [runtime] the way a conversation host does (the `sdk` profile
  /// with NipaPlay's plugins and persona) against a model address that is
  /// never called, and has it open a thread. Proves the Node.js, the trimmed
  /// tree, its native modules and NipaPlay's plugins load on this machine.
  Future<DshCheck> check(DshRuntime runtime,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final plugins = Directory(p.join(agentAssets.path, 'dsh'));
    final work = await Directory(p.join(data.path, 'dsh-check')).create(recursive: true);
    final harness = await Directory(p.join(work.path, 'harness')).create(recursive: true);
    final home = Directory(p.join(work.path, 'home'));
    if (await home.exists()) await home.delete(recursive: true);
    await Directory(p.join(home.path, 'agents')).create(recursive: true);
    final patch = File(p.join(work.path, 'patch.json'));
    await patch.writeAsString(
        jsonEncode(dshPatch(
            route: const DshRoute(
                baseUrl: 'http://127.0.0.1:9/v1', model: 'check', key: 'unused'),
            plugins: plugins,
            personaPrefix:
                (await File(p.join(plugins.path, 'persona-prefix.md')).readAsString())
                    .trim(),
            personaSuffix:
                (await File(p.join(plugins.path, 'persona-suffix.md')).readAsString())
                    .trim(),
            harness: harness.path,
            version: runtime.version)),
        flush: true);
    final process = await Process.start(runtime.node,
        [runtime.bin, '--profile', 'sdk', '--patch', patch.path],
        workingDirectory: harness.path,
        environment: {
          'DSH_HOME': home.path,
          'DSH_AGENTS_HOME': p.join(home.path, 'agents'),
          'DSH_PERMISSION_MODE': 'danger-full-access',
          'DSH_TELEMETRY_DISABLED': '1',
          'NIPAPLAY_AGENT_RUNTIME': 'dsh',
          DshRoute.keyVariable: 'unused',
        });
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          try {
            return jsonDecode(line);
          } catch (_) {
            return null;
          }
        })
        .where((message) => message is Map)
        .cast<Map>()
        .asBroadcastStream();
    Future<Map> call(int id, String method, Map<String, Object?> params) {
      final answer = lines.firstWhere((m) => m['id'] == id && !m.containsKey('method'));
      process.stdin.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
      return answer;
    }

    try {
      return await () async {
        final init = await call(1, 'initialize', {
          'clientInfo': {'name': 'nipaplay-headless', 'title': 'NipaPlay headless', 'version': '0'},
          'capabilities': {},
        });
        if (init['error'] != null) throw StateError('initialize: ${init['error']}');
        process.stdin.writeln(jsonEncode({'method': 'initialized', 'params': {}}));
        final thread = await call(2, 'thread/start', {
          'cwd': harness.path,
          'model': 'check',
          'modelProvider': DshRoute.provider,
          'sandbox': 'danger-full-access',
          'approvalPolicy': 'never',
        });
        if (thread['error'] != null) throw StateError('thread/start: ${thread['error']}');
        final id = ((thread['result'] as Map)['thread'] as Map)['id'] as String;
        return DshCheck(runtime.version, id);
      }()
          .timeout(timeout);
    } on TimeoutException {
      throw StateError('DeepSeek Harness did not answer within ${timeout.inSeconds} s: '
          '${errors.toString().trim()}');
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError('DeepSeek Harness stopped before it answered '
          '(${errors.toString().trim().split('\n').take(3).join(' | ')})');
    } finally {
      try {
        await process.stdin.close();
      } catch (_) {}
      await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
        process.kill();
        return -1;
      });
    }
  }
}

/// A runtime that started with NipaPlay's plugins and opened a thread.
final class DshCheck {
  const DshCheck(this.version, this.threadId);
  final String version, threadId;
}

/// `--dsh-install`, `--dsh-status`, `--dsh-check` of the headless command
/// line: the runtime Nipa runs on, kept in `<root>/dsh-runtime` beside the
/// rest of the host's data. [mode] is `install`, `status` or `check`; one JSON
/// object per line goes to [write]. The exit code: 0 when a runtime is there
/// (and, for `check`, started), 1 otherwise.
Future<int> runHeadlessDshCommand(String mode, Directory root,
    {String? assets, void Function(String line)? write, Map<String, String>? environment}) async {
  final out = write ?? stdout.writeln;
  final marker = File(p.join(root.path, 'headless.json'));
  if (!await marker.exists()) {
    if (await root.exists() && !await root.list().isEmpty) {
      throw StateError('Refusing a nonempty directory without a headless.json marker.');
    }
    await root.create(recursive: true);
    await marker.writeAsString(jsonEncode({'format': 1, 'host': 'nipaplay-headless'}));
  }
  final agentAssets = Directory(
      assets ?? p.join(Directory.current.path, 'assets', 'next', 'agent'));
  String? last;
  void say(Map<String, Object?> value) {
    final line = jsonEncode(value);
    if (line != last) out(last = line);
  }

  try {
    final dsh = HeadlessDsh.open(
        data: root, agentAssets: agentAssets, environment: environment);
    Map<String, Object?> facts(DshRuntime runtime) => {
          'node': runtime.node,
          'bin': runtime.bin,
          'version': runtime.version,
          'source': dsh.fixed ? 'environment' : 'installed',
        };
    switch (mode) {
      case 'status':
        final runtime = await dsh.locate();
        say({
          'platform': dsh.install.platform,
          'supported': dsh.install.supported,
          'installed': runtime != null,
          if (runtime != null) ...facts(runtime),
        });
        return runtime == null ? 1 : 0;
      case 'install':
        final runtime = await dsh.ensure(
            progress: (state) => say({
                  'status': state.status.name,
                  'receivedBytes': state.receivedBytes,
                  'totalBytes': state.totalBytes,
                }));
        say({'status': UiDshStatus.ready.name, ...facts(runtime)});
        return 0;
      case 'check':
        final runtime = await dsh.locate();
        if (runtime == null) {
          say({'status': UiDshStatus.notInstalled.name});
          return 1;
        }
        final check = await dsh.check(runtime);
        say({'status': 'started', ...facts(runtime), 'threadId': check.threadId});
        return 0;
      default:
        throw ArgumentError('Unknown DSH command $mode.');
    }
  } catch (error) {
    say({'status': 'failed', 'problem': redactHarnessText('$error')});
    return 1;
  }
}
