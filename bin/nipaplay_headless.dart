import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipaplay/next/headless/core.dart';
import 'package:nipaplay/next/media/media_probe_io.dart';
import 'package:nipaplay/next/harness_redaction.dart';

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
  for (var i = 0; i < arguments.length; i++) {
    final key = arguments[i];
    if (key == '--help') {
      stdout.writeln('NipaPlay headless\n'
          '  --data ABSOLUTE_DIR (required; independent of GUI data)\n'
          '  --media-root ABSOLUTE_DIR (repeatable; media are read-only)\n'
          '  --port NUMBER (default 0; IPv4 loopback only)\n'
          '  --seed ABSOLUTE_DIR (default assets/next/harness)\n'
          '  --ffprobe ABSOLUTE_EXECUTABLE (optional duration probe)\n'
          '  --stop --data ABSOLUTE_DIR (stop that instance)');
      return;
    }
    if (key == '--stop') {
      stop = true;
      continue;
    }
    if (!{'--data', '--media-root', '--port', '--seed', '--ffprobe'}
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
        port: port);
    final status = await core.start();
    await running.writeAsString(jsonEncode({
      'pid': pid,
      'url': status.url.toString(),
      'data': root.path,
      'mediaRoots': roots,
      'downloaderEnabled': false
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
