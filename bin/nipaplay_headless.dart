import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipaplay/next/headless/agent_cli.dart';
import 'package:nipaplay/next/headless/core.dart';
import 'package:nipaplay/next/headless/dsh.dart';
import 'package:nipaplay/next/media/media_probe_io.dart';
import 'package:nipaplay/next/harness_redaction.dart';
import 'package:nipaplay/next/headless/vault.dart';
import 'package:nipaplay/security/credential_vault.dart';

Future<String> _canonicalDirectory(String path) async {
  if (await Directory(path).exists()) {
    return Directory(path).resolveSymbolicLinks();
  }
  final parent = p.dirname(path);
  if (parent == path) {
    throw ArgumentError('Data path has no existing ancestor.');
  }
  return p.join(await _canonicalDirectory(parent), p.basename(path));
}

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  var stop = false;
  var enroll = false;
  var enrollCredential = false;
  String? dshMode, agentMode;
  var keyStdin = false;
  for (var i = 0; i < arguments.length; i++) {
    final key = arguments[i];
    if (key == '--help') {
      stdout.writeln('NipaPlay headless\n'
          '  --data ABSOLUTE_DIR (required; independent of GUI data)\n'
          '  --media-root ABSOLUTE_DIR (repeatable; indexing/download destinations are read-only)\n'
          '  --port NUMBER (default 0; IPv4 loopback only)\n'
          '  --seed ABSOLUTE_DIR (default assets/next/harness)\n'
          '  --ffprobe ABSOLUTE_EXECUTABLE (optional duration probe)\n'
          '  --native-library ABSOLUTE_LIBRARY (default beside executable)\n'
          '  --enroll-token-stdin --data DIR (host-only account enrollment)\n'
          '  --enroll-credential-stdin --credential-namespace NAME --credential-key KEY --data DIR (host-only vault enrollment)\n'
          '  Host files in data: mesh.json (trust/join), download.json (network configuration), network.json (gateway routing)\n'
          '  --stop --data ABSOLUTE_DIR (stop that instance)\n'
          '  The runtime Nipa runs on (DeepSeek Harness on the pinned Node.js), kept in data/dsh-runtime:\n'
          '  --dsh-install --data DIR (download and unpack it; official sources, then npmmirror)\n'
          '  --dsh-status --data DIR (which runtime would be launched)\n'
          '  --dsh-check --data DIR (start it with NipaPlay plugins and open a thread, no model call)\n'
          '  --agent-assets ABSOLUTE_DIR (default assets/next/agent: dsh-runtime.json and dsh/)\n'
          '  NIPAPLAY_AGENT_RUNTIME=dsh with NIPAPLAY_DSH_NODE and NIPAPLAY_DSH_ROOT name an installation of your own\n'
          '  Nipa on this host (the person at the host sets these; Nipa cannot):\n'
          '  --model-set --base-url URL --model NAME [--provider NAME] [--api responses|chat] [--reasoning low|medium|high] [--key-stdin] --data DIR\n'
          '      (the key is read from standard input, never from an argument: printf %s "\$KEY" | ... --key-stdin)\n'
          '  --model-status | --model-check | --model-clear --data DIR\n'
          '  --agent-enable | --agent-disable | --agent-status --data DIR (the switch that lets Nipa run on this host)\n'
          '  A running host applies these without a restart. Talk to her with ./nipa chat in the host harness.');
      return;
    }
    if (key == '--enroll-token-stdin') { enroll = true; continue; }
    if (key == '--enroll-credential-stdin') { enrollCredential = true; continue; }
    if (key == '--dsh-install' || key == '--dsh-status' || key == '--dsh-check') {
      dshMode = key.substring(6);
      continue;
    }
    if (key == '--key-stdin') { keyStdin = true; continue; }
    if (const {
      '--model-set', '--model-status', '--model-check', '--model-clear',
      '--agent-enable', '--agent-disable', '--agent-status'
    }.contains(key)) {
      agentMode = key.substring(2);
      continue;
    }
    if (key == '--stop') {
      stop = true;
      continue;
    }
    if (!{'--data', '--media-root', '--port', '--seed', '--ffprobe', '--native-library',
          '--credential-namespace', '--credential-key', '--agent-assets',
          '--provider', '--base-url', '--model', '--api', '--reasoning'}
            .contains(key) ||
        i + 1 == arguments.length) {
      stderr.writeln('Invalid option: $key');
      exitCode = 64;
      return;
    }
    final value = arguments[++i];
    if (key == '--media-root') {
      options[key] = '${options[key] ?? ''}$value\u0000';
    } else {
      options[key] = value;
    }
  }
  final data = options['--data'];
  if (data == null || !p.isAbsolute(data)) {
    stderr.writeln('--data must be an absolute, isolated directory.');
    exitCode = 64;
    return;
  }
  final root = Directory(await _canonicalDirectory(p.normalize(data)));
  if (dshMode != null) {
    exitCode = await runHeadlessDshCommand(dshMode, root, assets: options['--agent-assets']);
    return;
  }
  if (agentMode != null) {
    exitCode = await runHeadlessAgentCommand(agentMode, root,
        options: options, keyStdin: keyStdin);
    return;
  }
  if (keyStdin || const {'--provider', '--base-url', '--model', '--api', '--reasoning'}
      .any(options.containsKey)) {
    stderr.writeln('--key-stdin and the model options belong to --model-set.');
    exitCode = 64;
    return;
  }
  if (enroll || enrollCredential) {
    final marker = File(p.join(root.path, 'headless.json'));
    if (!await marker.exists()) {
      throw StateError('Initialize the isolated headless data directory before enrollment.');
    }
    final configuration = jsonDecode(await marker.readAsString()) as Map;
    if (configuration['format'] != 1 || configuration['host'] != 'nipaplay-headless') {
      throw StateError('Unrecognized headless data directory.');
    }
    if (enroll && enrollCredential) throw ArgumentError('Choose one host enrollment mode.');
    final namespace = enroll ? 'preferences' : options['--credential-namespace'];
    final key = enroll ? 'dandanplay_token' : options['--credential-key'];
    if (namespace == null || namespace.isEmpty || namespace.contains('\u0000') ||
        key == null || key.isEmpty || key.contains('\u0000')) {
      throw ArgumentError('Credential namespace and key are required.');
    }
    final supplied = await stdin.transform(utf8.decoder).join();
    final value = enroll ? supplied.trim() : supplied;
    if (value.isEmpty || value.length > 4096 || enroll && RegExp(r'\s').hasMatch(value)) throw StateError('invalid_credential_input');
    await HeadlessVault(Directory(p.join(root.path, 'vault'))).write(CredentialRef(namespace, key), value);
    stdout.writeln('Host credential enrolled.');
    return;
  }
  if (options.containsKey('--credential-namespace') || options.containsKey('--credential-key')) {
    throw ArgumentError('Credential references belong to host enrollment mode.');
  }
  final running = File(p.join(root.path, 'running.json'));
  final stopRequest = File(p.join(root.path, 'stop.request'));
  if (stop) {
    final facts = jsonDecode(await running.readAsString()) as Map;
    await stopRequest.writeAsString('${facts['pid']}', flush: true);
    stdout.writeln('Stop requested for PID ${facts['pid']}.');
    return;
  }
  final marker = File(p.join(root.path, 'headless.json'));
  final configuration = await marker.exists()
      ? Map<String, Object?>.from(
          jsonDecode(await marker.readAsString()) as Map)
      : <String, Object?>{'format': 1, 'host': 'nipaplay-headless'};
  if (configuration['format'] != 1 ||
      configuration['host'] != 'nipaplay-headless') {
    throw StateError('Unrecognized headless data directory.');
  }
  final roots = options.containsKey('--media-root')
      ? options['--media-root']!
          .split('\u0000')
          .where((r) => r.isNotEmpty)
          .map(p.normalize)
          .toList()
      : (configuration['mediaRoots'] as List? ?? []).cast<String>();
  for (final r in roots) {
    if (!p.isAbsolute(r) || !await Directory(r).exists()) {
      throw ArgumentError('Media root must be an existing absolute directory.');
    }
    final real = await Directory(r).resolveSymbolicLinks();
    if (p.equals(real, root.path) ||
        p.isWithin(real, root.path) ||
        p.isWithin(root.path, real)) {
      throw ArgumentError(
          'Data directory must be separate from read-only media roots.');
    }
  }
  final port = int.parse(options['--port'] ?? '${configuration['port'] ?? 0}');
  if (port < 0 || port > 65535) throw ArgumentError('Port must be 0–65535.');
  headlessFfprobe = options['--ffprobe'] ?? configuration['ffprobe'] as String?;
  if (headlessFfprobe case final executable?) {
    if (!p.isAbsolute(executable) || !await File(executable).exists()) {
      throw ArgumentError(
          '--ffprobe must name an existing absolute executable.');
    }
  }
  await root.create(recursive: true);
  if (!await marker.exists()) {
    if (!await root.list().isEmpty) {
      throw StateError(
          'Refusing a nonempty directory without a headless.json marker.');
    }
  }
  final lock = await File(p.join(root.path, 'instance.lock'))
      .open(mode: FileMode.append);
  await lock.lock();
  HeadlessCore? core;
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Timer? stopTimer;
  try {
    final pendingConfig = File('${marker.path}.pending');
    await pendingConfig.writeAsString(
        jsonEncode({
          ...configuration,
          'mediaRoots': roots,
          'port': port,
          'ffprobe': headlessFfprobe
        }),
        flush: true);
    await pendingConfig.rename(marker.path);
    if (await stopRequest.exists()) await stopRequest.delete();
    final seedRoot = Directory(options['--seed'] ??
        p.join(Directory.current.path, 'assets', 'next', 'harness'));
    final seed = <String, List<int>>{};
    await for (final file
        in seedRoot.list(recursive: true, followLinks: false)) {
      if (file is! File) continue;
      final relative = p.relative(file.path, from: seedRoot.path);
      if (relative.split(p.separator).contains('.codex')) continue;
      seed[relative] = await file.readAsBytes();
    }
    core = HeadlessCore(
        root: root,
        repository: Directory(p.join(root.path, 'harness')),
        mediaRoots: roots,
        seed: seed,
        agentAssets: Directory(options['--agent-assets'] ??
            p.join(Directory.current.path, 'assets', 'next', 'agent')),
        nativeLibrary: options['--native-library'],
        port: port);
    final status = await core.start();
    await running.writeAsString(jsonEncode({
      'pid': pid,
      'url': status.url.toString(),
      'data': root.path,
      'mediaRoots': roots,
      'downloaderEnabled': true
    }));
    stdout.writeln(jsonEncode({
      'status': 'running',
      'pid': pid,
      'url': status.url.toString(),
      'data': root.path,
      'endpointFile': core.endpoint.credentialFile.path
    }));
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    subscriptions.add(ProcessSignal.sigint.watch().listen((_) => finish()));
    if (!Platform.isWindows) {
      subscriptions.add(ProcessSignal.sigterm.watch().listen((_) => finish()));
    }
    stopTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (stopRequest.existsSync() && stopRequest.readAsStringSync() == '$pid') {
        finish();
      }
    });
    await done.future;
    await core.close();
    stdout.writeln(jsonEncode({'status': 'stopped', 'pid': pid}));
  } catch (error, stack) {
    stderr.writeln(redactHarnessText('$error\n$stack'));
    exitCode = 1;
  } finally {
    stopTimer?.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await core?.close();
    if (await running.exists()) await running.delete();
    if (await stopRequest.exists()) await stopRequest.delete();
    await lock.unlock();
    await lock.close();
  }
}
