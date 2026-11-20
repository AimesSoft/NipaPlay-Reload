import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/store/capability.dart';
import 'package:nipaplay/next/store/rika_store.dart';
import 'package:nipaplay/next/store/sources.dart';
import 'package:nipaplay/next/store/store_fetch.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late RikaStore store;
  late Harness harness;
  HttpServer? registry;
  var restarts = 0;
  late StoreApplyResult restartResult;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('store-capability-');
    final list = await Directory(p.join(temp.path, 'list')).create();
    const skill = '---\nname: dmhy\n---\n用法';
    await File(p.join(list.path, 'skills', 'dmhy', 'SKILL.md'))
        .create(recursive: true)
        .then((f) => f.writeAsString(skill));
    const readme = '# 动漫花园\n说明';
    await File(p.join(list.path, 'skills', 'dmhy', 'README.md'))
        .writeAsString(readme);
    String sha(String text) => sha256.convert(utf8.encode(text)).toString();
    await File(p.join(list.path, 'index.json')).writeAsString(jsonEncode({
      'version': 1,
      'items': [
        {
          'id': 'dmhy',
          'kind': 'skill',
          'name': '动漫花园',
          'version': '1.1.0',
          'description': '在动漫花园搜索资源。',
          'category': 'bt',
          'notices': ['只取公开信息。'],
          'readme': {
            'url': 'skills/dmhy/README.md',
            'sha256': sha(readme),
            'bytes': utf8.encode(readme).length
          },
          'files': [
            {
              'path': 'SKILL.md',
              'url': 'skills/dmhy/SKILL.md',
              'sha256': sha(skill),
              'bytes': utf8.encode(skill).length
            }
          ]
        }
      ]
    }));
    store = RikaStore(
        root: Directory(p.join(temp.path, 'store')),
        fetch: StoreFetch(HttpClient.new),
        listSources: () =>
            storeListSources({'NIPAPLAY_STORE_INDEX': list.path}),
        registries: () async => ['http://127.0.0.1:${registry?.port ?? 9}'],
        provided: () async => null);
    restarts = 0;
    restartResult = const StoreApplyResult.restarted();
    harness = Harness([
      StoreCapability(store, restart: () async {
        restarts++;
        return restartResult;
      }),
    ]);
  });
  tearDown(() async {
    await registry?.close(force: true);
    registry = null;
    await store.close();
    await temp.delete(recursive: true);
  });

  Future<Outcome<JsonEncodable>> call(String action, JsonMap input,
          {String origin = 'gui'}) =>
      harness.invokeJson(action, input, Invocation(origin: origin));

  JsonMap value(Outcome<JsonEncodable> outcome) =>
      (outcome as Completed).value.toJson() as JsonMap;

  test('the list, an official install by the agent, enable and remove',
      () async {
    final listed = value(await call('store.list', {}, origin: 'agent:x'));
    final item = (listed['official'] as List).single as Map;
    expect(item['id'], 'dmhy');
    expect(item['reviewed'], isTrue);
    expect(item['installedVersion'], isNull);
    expect(value(await call('store.readme', {'id': 'dmhy'})),
        containsPair('version', '1.1.0'));
    expect(item['versionSource'], 'officialIndex');

    final installed = value(await call(
        'store.install', {'id': 'dmhy', 'version': '1.1.0'},
        origin: 'agent:x'));
    expect((installed['installed'] as Map)['version'], '1.1.0');
    expect(installed['takesEffect'], contains('next'));
    final after = value(await call('store.list', {}));
    expect(((after['official'] as List).single as Map)['installedVersion'],
        '1.1.0');
    expect((after['official'] as List).single,
        containsPair('installedVersionSource', 'installedRecord'));

    await store.hostFacts();
    final started = value(await call('store.list', {}, origin: 'agent:x'));
    expect(started['loadedAtLastStart'], [
      {'id': 'dmhy', 'version': '1.1.0', 'kind': 'skill'}
    ]);
    value(await call('store.enable', {'id': 'dmhy', 'enabled': false},
        origin: 'agent:x'));
    expect((await store.installed()).single.enabled, isFalse);
    expect(value(await call('store.list', {}))['loadedAtLastStart'],
        started['loadedAtLastStart']);
    value(await call('store.remove', {'id': 'dmhy'}, origin: 'agent:x'));
    expect(await store.installed(), isEmpty);
  });

  test('agent reaches the npm registry and can restart 梨花', () async {
    final preview = value(await call(
        'store.resolve_npm', {'npm': 'some-plugin'},
        origin: 'agent:x'));
    expect(preview, containsPair('requested', 'latest'));
    expect(preview, containsPair('installable', false));
    final npm = await call(
        'store.install',
        {
          'npm': 'some-plugin',
          'version': '1.0.0',
          'kind': 'plugin',
          'integrity': 'sha512-${base64Encode(sha512.convert([]).bytes)}',
        },
        origin: 'agent:x');
    expect((npm as Failed).failure.code, FailureCode.unavailable);
    expect(value(await call('store.apply', {}, origin: 'agent:x')),
        {'status': 'restarted', 'restarted': true});
    expect(restarts, 1);
    restartResult = const StoreApplyResult.notRun('endpoint not running');
    expect(value(await call('store.apply', {})), {
      'status': 'notRun',
      'restarted': false,
      'reason': 'endpoint not running'
    });
    restartResult = const StoreApplyResult.failed('startup failed');
    expect(value(await call('store.apply', {})),
        {'status': 'failed', 'restarted': false, 'error': 'startup failed'});
    expect(restarts, 3);
  });

  test('failed directory removal leaves a visible record for retry', () async {
    value(await call('store.install', {'id': 'dmhy', 'version': '1.1.0'}));
    final parent = p.join(store.root.path, 'skills');
    Future<void> chmod(String mode) async {
      final result = await Process.run('chmod', [mode, parent]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    try {
      await chmod('500');
      await expectLater(
          store.remove('dmhy'), throwsA(isA<FileSystemException>()));
      expect(value(await call('store.list', {}))['installed'], [
        containsPair('id', 'dmhy'),
      ]);
    } finally {
      await chmod('700');
    }
    value(await call('store.remove', {'id': 'dmhy'}));
    expect(await Directory(p.join(parent, 'dmhy')).exists(), isFalse);
    expect(await store.installed(), isEmpty);
  }, skip: Platform.isWindows);

  test('npm install pins the previewed tarball', () async {
    List<int> pack(String text) => gzip.encode(TarEncoder().encode(
        Archive()..addFile(ArchiveFile.string('package/SKILL.md', text))));
    String sri(List<int> bytes) =>
        'sha512-${base64Encode(sha512.convert(bytes).bytes)}';
    const name = 'preview-skill';
    final reviewed = pack('original skill');
    var served = reviewed;
    var downloads = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    registry = server;
    server.listen((request) async {
      if (request.uri.path == '/$name/latest' ||
          request.uri.path == '/$name/1.0.0') {
        request.response.write(jsonEncode({
          'name': name,
          'version': '1.0.0',
          'dist': {'integrity': sri(served)},
        }));
      } else if (request.uri.path == '/$name/-/$name-1.0.0.tgz') {
        downloads++;
        request.response.add(served);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final preview = value(await call('store.resolve_npm', {'npm': name}));
    final install = {
      'npm': name,
      'version': preview['version'],
      'kind': 'skill'
    };
    final unpinned = await call('store.install', install);
    expect((unpinned as Failed).failure.code, FailureCode.invalidInput);
    served = pack('different skill');
    final changed = await call('store.install', {
      ...install,
      'integrity': preview['integrity'] ?? sri(reviewed),
    });
    expect((changed as Failed).failure.code, FailureCode.conflict);
    expect(downloads, 1);
    expect(await store.installed(), isEmpty);
    expect(preview['integrity'], sri(reviewed));

    served = reviewed;
    value(await call(
        'store.install', {...install, 'integrity': preview['integrity']}));
    final item = (await store.installed()).single.item;
    expect(
        await File(p.join(store.root.path, 'skills', item.id, 'SKILL.md'))
            .readAsString(),
        'original skill');
  });

  test('exactly one of id or npm', () async {
    expect((await call('store.install', {})) is Failed, isTrue);
    expect((await call('store.install', {'id': 'dmhy', 'npm': 'x'})) is Failed,
        isTrue);
    final changed =
        await call('store.install', {'id': 'dmhy', 'version': '1.0.0'});
    expect((changed as Failed).failure.code, FailureCode.conflict);
    // An official item without the version the person was told of.
    expect(
        ((await call('store.install', {'id': 'dmhy'})) as Failed)
            .failure
            .message,
        contains('version'));
    final missing =
        await call('store.install', {'id': 'nothing', 'version': '1.0.0'});
    expect((missing as Failed).failure.code, FailureCode.invalidInput);
  });
}
