import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../harness_redaction.dart';
import '../runtime/dsh_manifest.dart';
import 'model.dart';
import 'nipa.dart';
import 'vault.dart';

/// What the headless command line sets for Nipa, as the person at the host:
/// her model (`--model-set`, with the key read from standard input so it is
/// in no argument, no shell history and no log), the switch that turns her
/// off (`--agent-enable`, `--agent-disable`), and what is there
/// (`--agent-status`, `--model-status`, `--model-check`).
///
/// [mode] is one of `model-set`, `model-status`, `model-check`,
/// `model-clear`, `agent-enable`, `agent-disable`, `agent-status`. One JSON
/// object goes to [write]; the exit code is 0 on success and 1 otherwise.
/// A running host sees the files change and acts on them without a restart.
Future<int> runHeadlessAgentCommand(String mode, Directory root,
    {Map<String, String> options = const {},
    bool keyStdin = false,
    Stream<List<int>>? input,
    void Function(String line)? write,
    HttpClient Function()? httpClient}) async {
  final out = write ?? stdout.writeln;
  void say(Map<String, Object?> value) => out(jsonEncode(value));
  try {
    final marker = File(p.join(root.path, 'headless.json'));
    if (!await marker.exists()) {
      if (await root.exists() && !await root.list().isEmpty) {
        throw StateError(
            'Refusing a nonempty directory without a headless.json marker.');
      }
      await root.create(recursive: true);
      await marker
          .writeAsString(jsonEncode({'format': 1, 'host': 'nipaplay-headless'}));
    }
    final vault = HeadlessVault(Directory(p.join(root.path, 'vault')));
    final model = HeadlessModel(root: root, vault: vault);
    switch (mode) {
      case 'model-set':
        String? key;
        if (keyStdin) {
          final text = await utf8.decodeStream(input ?? stdin);
          key = text.replaceFirst(RegExp(r'\r?\n$'), '');
          if (key.isEmpty) throw const FormatException('The key is empty.');
        }
        final facts = await model.save(
            provider: options['--provider'],
            baseUrl: _required(options, '--base-url'),
            model: _required(options, '--model'),
            api: options['--api'] ?? 'responses',
            reasoning: options['--reasoning'],
            key: key);
        say({'status': 'saved', ...facts.toJson()});
        if (!facts.keyConfigured) {
          say({'note': 'No key is kept for this provider and address; run again with --key-stdin.'});
        }
        return 0;
      case 'model-status':
        say({'status': 'model', ...(await model.facts()).toJson()});
        return 0;
      case 'model-check':
        final check = await model.check(httpClient: httpClient);
        say({
          'status': check.ok ? 'ok' : 'failed',
          'message': check.message,
          if (check.latency != null) 'latencyMs': check.latency!.inMilliseconds,
        });
        return check.ok ? 0 : 1;
      case 'model-clear':
        await model.clear();
        say({'status': 'cleared'});
        return 0;
      case 'agent-enable':
      case 'agent-disable':
        await HeadlessAgentSwitch.set(root, mode == 'agent-enable');
        say({'status': 'saved', 'enabled': mode == 'agent-enable'});
        return 0;
      case 'agent-status':
        final platform = DshManifest.hostPlatform();
        say({
          'status': 'agent',
          'enabled': await HeadlessAgentSwitch.enabled(root),
          'model': (await model.facts()).toJson(),
          'runtimeInstalled':
              await Directory(p.join(root.path, 'dsh-runtime')).exists(),
          'platform': platform,
          'note': 'A running host applies these without a restart; '
              'app.runtime says whether Nipa is running.',
        });
        return 0;
      default:
        throw ArgumentError('Unknown agent command $mode.');
    }
  } catch (error) {
    say({'status': 'failed', 'problem': redactHarnessText('$error')});
    return 1;
  }
}

String _required(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) {
    throw ArgumentError('$name is required.');
  }
  return value;
}
