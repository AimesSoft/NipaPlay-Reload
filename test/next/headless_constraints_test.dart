import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dart = Platform.environment['NIPAPLAY_TEST_DART'];
  final skip = dart == null
      ? 'Set NIPAPLAY_TEST_DART to the pinned Dart executable.'
      : false;
  late Directory temporary;
  final children = <Process>[];
  final environment = <String, String>{
    for (final e in Platform.environment.entries)
      if (!{'http_proxy', 'https_proxy', 'all_proxy'}
          .contains(e.key.toLowerCase()))
        e.key: e.value,
    'NO_PROXY': '127.0.0.1,localhost',
  };
  List<String> arguments(String root) => [
        '--packages=.dart_tool/package_config.json',
        'bin/nipaplay_headless.dart',
        '--data',
        root,
      ];
  Future<Process> start(String root, {String? media}) async {
    final child = await Process.start(
        dart!,
        [
          ...arguments(root),
          if (media != null) ...['--media-root', media]
        ],
        environment: environment,
        includeParentEnvironment: false);
    children.add(child);
    unawaited(child.stderr.drain<void>());
    final ready = Completer<String>();
    child.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        if (!ready.isCompleted) ready.complete(line);
      },
      onError: (Object error) {
        if (!ready.isCompleted) ready.completeError(error);
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Host exited before startup.'));
        }
      },
    );
    final first = await ready.future.timeout(const Duration(seconds: 20));
    expect((jsonDecode(first) as Map)['status'], 'running');
    return child;
  }

  Future<void> stop(Process child, String root) async {
    final result = await Process.run(dart!, [...arguments(root), '--stop'],
        environment: environment, includeParentEnvironment: false);
    expect(result.exitCode, 0);
    expect(await child.exitCode.timeout(const Duration(seconds: 15)), 0);
    children.remove(child);
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('x43-constraints-');
  });
  tearDown(() async {
    for (final child in children) {
      child.kill();
      await child.exitCode;
    }
    children.clear();
    await temporary.delete(recursive: true);
  });

  test(
      'existing non-headless data is rejected without writing a marker or database',
      () async {
    final sentinel =
        await File('${temporary.path}/classic.data').writeAsString('preserve');
    final result = await Process.run(dart!, arguments(temporary.path),
        environment: environment, includeParentEnvironment: false);
    expect(result.exitCode, isNot(0));
    expect(await sentinel.readAsString(), 'preserve');
    expect(await temporary.list().map((e) => e.uri.pathSegments.last).toList(),
        ['classic.data']);
  }, skip: skip);

  test(
      'one owner per data directory and restart retains device identity and media configuration',
      () async {
    final media = await Directory('${temporary.path}/media').create();
    final root = '${temporary.path}/body';
    final first = await start(root, media: media.path);
    final identityFile = File('$root/device.json');
    final identity = await identityFile.readAsString();
    final endpoint = File('$root/endpoint.json');
    final before = await endpoint.stat();
    final duplicate = await Process.run(dart!, arguments(root),
        environment: environment, includeParentEnvironment: false);
    expect(duplicate.exitCode, isNot(0));
    expect((await endpoint.stat()).modified, before.modified);
    expect(
        (jsonDecode(await File('$root/running.json').readAsString())
            as Map)['pid'],
        first.pid);
    await stop(first, root);
    expect(await endpoint.exists(), false);
    expect(await File('$root/next.db').exists(), true);
    final second = await start(root);
    expect(await identityFile.readAsString(), identity);
    expect(
        (jsonDecode(await File('$root/running.json').readAsString())
            as Map)['mediaRoots'],
        [media.path]);
    await stop(second, root);
  }, skip: skip);
}
