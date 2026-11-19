import 'dart:convert';
import 'dart:io';

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
  var restarts = 0;

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
        listSources: () => storeListSources({'NIPAPLAY_STORE_INDEX': list.path}),
        registries: () async => ['http://127.0.0.1:9'],
        provided: () async => null);
    restarts = 0;
    harness = Harness([
      StoreCapability(store, restart: () async => restarts++),
    ]);
  });
  tearDown(() async {
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
    expect(value(await call('store.readme', {'id': 'dmhy'}))['readme'],
        contains('动漫花园'));

    final installed =
        value(await call('store.install', {'id': 'dmhy', 'version': '1.1.0'},
            origin: 'agent:x'));
    expect((installed['installed'] as Map)['version'], '1.1.0');
    expect(installed['takesEffect'], contains('next'));
    final after = value(await call('store.list', {}));
    expect(((after['official'] as List).single as Map)['installedVersion'],
        '1.1.0');

    value(await call('store.enable', {'id': 'dmhy', 'enabled': false}));
    expect((await store.installed()).single.enabled, isFalse);
    value(await call('store.remove', {'id': 'dmhy'}));
    expect(await store.installed(), isEmpty);
  });

  test('only the person installs an npm package or restarts 梨花', () async {
    final npm = await call('store.install', {'npm': 'some-plugin'},
        origin: 'agent:x');
    expect((npm as Failed).failure.message, contains('Only the person'));
    // Over Mesh is not the person at this device (another device's agent
    // arrives that way too).
    final remote = await call('store.install', {'npm': 'some-plugin'},
        origin: 'mesh:phone');
    expect((remote as Failed).failure.message, contains('Only the person'));
    expect(((await call('store.apply', {}, origin: 'mesh:phone')) as Failed)
        .failure
        .message, contains('ask the person'));
    final apply = await call('store.apply', {}, origin: 'agent:x');
    expect((apply as Failed).failure.message, contains('ask the person'));
    expect(restarts, 0);
    value(await call('store.apply', {}));
    expect(restarts, 1);
    // From the person, the request goes to npm (unreachable here).
    final tried = await call('store.install', {'npm': 'some-plugin'});
    expect((tried as Failed).failure.code, FailureCode.unavailable);
  });

  test('exactly one of id or npm', () async {
    expect((await call('store.install', {})) is Failed, isTrue);
    expect(
        (await call('store.install', {'id': 'dmhy', 'npm': 'x'})) is Failed,
        isTrue);
    final changed =
        await call('store.install', {'id': 'dmhy', 'version': '1.0.0'});
    expect((changed as Failed).failure.code, FailureCode.conflict);
    // An official item without the version the person was told of.
    expect(((await call('store.install', {'id': 'dmhy'})) as Failed).failure.message,
        contains('version'));
    final missing =
        await call('store.install', {'id': 'nothing', 'version': '1.0.0'});
    expect((missing as Failed).failure.code, FailureCode.invalidInput);
  });
}
