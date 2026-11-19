import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/store/npm_package.dart';
import 'package:nipaplay/next/store/rika_store.dart';
import 'package:nipaplay/next/store/store_fetch.dart';
import 'package:nipaplay/next/store/store_index.dart';
import 'package:path/path.dart' as p;

String _sha(List<int> bytes) => sha256.convert(bytes).toString();
String _sri(List<int> bytes) =>
    'sha512-${base64.encode(sha512.convert(bytes).bytes)}';

/// An npm tarball: [files] under `package/`, plus raw [entries] as given.
List<int> _tgz(Map<String, String> files,
    {List<ArchiveFile> entries = const []}) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.add(ArchiveFile.bytes('package/$key', utf8.encode(value)));
  }
  entries.forEach(archive.add);
  return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
}

/// A registry serving [packages] (name -> (manifest, tarball)).
Future<(HttpServer, String)> _registry(
    Map<String, (Map<String, Object?>, List<int>)> packages) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = Uri.decodeComponent(request.uri.path).substring(1);
    for (final MapEntry(key: name, value: (manifest, tarball))
        in packages.entries) {
      if (path == '$name/latest' || path == '$name/${manifest['version']}') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(manifest));
        await request.response.close();
        return;
      }
      if (path == NpmPackages.tarballPath(name, manifest['version'] as String)) {
        request.response.add(tarball);
        await request.response.close();
        return;
      }
    }
    request.response.statusCode = 404;
    await request.response.close();
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

Map<String, Object?> _manifest(String name, List<int> tarball,
        {Map<String, Object?> extra = const {}}) =>
    {
      'name': name,
      'version': '1.0.0',
      'description': '测试包',
      'dist': {'integrity': _sri(tarball)},
      ...extra,
    };

void main() {
  late Directory temp, list, runtime;
  late RikaStore store;
  String? registry;
  HttpServer? server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rika-store-');
    list = await Directory(p.join(temp.path, 'list')).create();
    // A DSH runtime's node_modules, with the packages plugins share.
    runtime = await Directory(p.join(temp.path, 'runtime', 'node_modules'))
        .create(recursive: true);
    for (final name in ['@deepseek-ai/cordis', '@deepseek-ai/schemastery']) {
      final dir = await Directory(p.joinAll([runtime.path, ...name.split('/')]))
          .create(recursive: true);
      await File(p.join(dir.path, 'index.js')).writeAsString('export {}');
    }
    store = RikaStore(
        root: Directory(p.join(temp.path, 'store')),
        fetch: StoreFetch(HttpClient.new),
        listSources: () => [Uri.directory(list.path)],
        registries: () async => [registry!],
        provided: () async => {
              '@deepseek-ai/cordis',
              '@deepseek-ai/schemastery',
              '@deepseek-ai/dsh-llm'
            });
  });
  tearDown(() async {
    await server?.close(force: true);
    server = null;
    await store.close();
    await temp.delete(recursive: true);
  });

  Future<void> writeList(List<Map<String, Object?>> items) =>
      File(p.join(list.path, 'index.json'))
          .writeAsString(jsonEncode({'version': 1, 'items': items}));

  Future<Map<String, Object?>> skill(String id, Map<String, String> files) async {
    final entries = <Map<String, Object?>>[];
    for (final MapEntry(:key, :value) in files.entries) {
      final file = File(p.join(list.path, 'skills', id, key));
      await file.parent.create(recursive: true);
      await file.writeAsString(value);
      final bytes = utf8.encode(value);
      entries.add({
        'path': key,
        'url': 'skills/$id/$key',
        'sha256': _sha(bytes),
        'bytes': bytes.length
      });
    }
    return {
      'id': id,
      'kind': 'skill',
      'name': '动漫花园',
      'version': '1.0.0',
      'description': '在动漫花园搜索资源。',
      'author': 'AimesSoft',
      'category': 'bt',
      'notices': <String>[],
      'files': entries,
    };
  }

  group('official list', () {
    test('a skill installs pinned, and she is told where it is', () async {
      await writeList([
        await skill('dmhy', {
          'SKILL.md': '---\nname: dmhy\n---\n用法',
          'dmhy.py': 'print("ok")',
        })
      ]);
      final installed = await store.installOfficial('dmhy');
      expect(installed.item.reviewed, isTrue);
      final folder = p.join(temp.path, 'store', 'skills', 'dmhy');
      expect(await File(p.join(folder, 'dmhy.py')).readAsString(), 'print("ok")');
      final facts = await store.hostFacts();
      expect(facts.instructions, contains('动漫花园（官方）'));
      expect(facts.instructions, contains(p.join(folder, 'SKILL.md')));
      expect(facts.dshPlugins, isEmpty);

      await store.setEnabled('dmhy', false);
      expect((await store.hostFacts()).instructions, isEmpty);
      await store.remove('dmhy');
      expect(await Directory(folder).exists(), isFalse);
      expect(await store.installed(), isEmpty);
    });

    test('a file that is not what the list pinned is not installed', () async {
      await writeList([
        await skill('dmhy', {'SKILL.md': '用法', 'dmhy.py': 'print("ok")'})
      ]);
      await File(p.join(list.path, 'skills', 'dmhy', 'dmhy.py'))
          .writeAsString('print("changed")');
      await expectLater(store.installOfficial('dmhy'),
          throwsA(isA<StoreFetchException>()));
      expect(await store.installed(), isEmpty);
      expect(
          await Directory(p.join(temp.path, 'store', 'skills', 'dmhy'))
              .exists(),
          isFalse);
    });

    test('unsafe paths, unknown kinds and newer formats are refused', () {
      Map<String, Object?> item(String path) => {
            'id': 'x',
            'kind': 'skill',
            'name': 'x',
            'version': '1.0.0',
            'description': 'x',
            'files': [
              {'path': path, 'url': 'skills/x/a', 'sha256': 'a' * 64, 'bytes': 1}
            ]
          };
      for (final path in ['../escape', '/abs', 'a/../../b', 'C:\\x']) {
        expect(
            () => StoreIndex.parse(jsonEncode({
                  'version': 1,
                  'items': [item(path)]
                })),
            throwsA(isA<StoreFormatException>()),
            reason: path);
      }
      expect(() => StoreIndex.parse('{"version":2,"items":[]}'),
          throwsA(isA<StoreFormatException>()));
      expect(
          () => StoreIndex.parse(jsonEncode({
                'version': 1,
                'items': [
                  {...item('SKILL.md'), 'kind': 'theme'}
                ]
              })),
          throwsA(isA<StoreFormatException>()));
    });
  });

  group('npm packages', () {
    test('a DSH plugin installs, links the runtime packages it shares, and '
        'is loaded by its own patch row', () async {
      final tarball = _tgz({
        'package.json': jsonEncode({
          'name': 'dsh-example',
          'type': 'module',
          'exports': {
            '.': {'default': './lib/index.js'}
          }
        }),
        'lib/index.js': "import '@deepseek-ai/cordis'; export const name = 'x';",
        'cordis.patch.yml':
            '- insert:\n    - id: llm-example\n      name: dsh-example\n',
      });
      (server, registry) = await _registry({
        'dsh-example': (
          _manifest('dsh-example', tarball, extra: {
            'keywords': ['dsh-plugin', 'llm'],
            'peerDependencies': {'@deepseek-ai/cordis': '*'},
            'dependencies': {'@deepseek-ai/schemastery': '^1.0.0'},
          }),
          tarball
        ),
      });
      final installed = await store.installNpm('dsh-example');
      expect(installed.item.id, 'npm-dsh-example');
      expect(installed.item.reviewed, isFalse);
      expect(installed.item.category, 'model');
      expect(installed.item.notices.first, contains('没有经过审核'));
      final facts = await store.hostFacts(runtimeModules: runtime);
      expect(facts.skipped, isEmpty);
      final row = facts.dshPlugins.single;
      expect(row['id'], 'llm-example');
      final modules = p.join(
          temp.path, 'store', 'plugins', 'npm-dsh-example', 'node_modules');
      expect(row['name'], p.join(modules, 'dsh-example', 'lib', 'index.js'));
      for (final peer in ['@deepseek-ai/cordis', '@deepseek-ai/schemastery']) {
        final link = Link(p.joinAll([modules, ...peer.split('/')]));
        expect(await link.target(),
            p.joinAll([runtime.path, ...peer.split('/')]),
            reason: peer);
      }
      // Under Codex no plugin loads; it says why.
      final codex = await store.hostFacts();
      expect(codex.dshPlugins, isEmpty);
      expect(codex.skipped.keys, ['npm-dsh-example']);
    });

    test('a package with SKILL.md installs as a skill', () async {
      final tarball = _tgz({
        'package.json': '{"name":"rika-skill-x"}',
        'SKILL.md': '---\nname: x\n---\n用法',
        'x.py': 'print(1)',
      });
      (server, registry) = await _registry({
        'rika-skill-x': (_manifest('rika-skill-x', tarball), tarball),
      });
      final installed = await store.installNpm('rika-skill-x@1.0.0');
      expect(installed.item.kind, StoreKind.skill);
      expect(installed.item.files.map((f) => f.path), ['SKILL.md', 'x.py']);
      expect((await store.hostFacts()).instructions, contains('rika-skill-x（未审核）'));
    });

    Future<Object?> refusal(Map<String, String> files,
        {Map<String, Object?> extra = const {},
        List<ArchiveFile> entries = const []}) async {
      final tarball = _tgz(files, entries: entries);
      await server?.close(force: true);
      (server, registry) = await _registry({
        'bad-plugin': (
          _manifest('bad-plugin', tarball,
              extra: {'keywords': ['dsh-plugin'], ...extra}),
          tarball
        ),
      });
      try {
        await store.installNpm('bad-plugin');
        return null;
      } on StoreFormatException catch (error) {
        return error.message;
      }
    }

    const plain = {
      'package.json': '{"name":"bad-plugin","main":"index.js"}',
      'index.js': 'export {}',
    };

    test('what the store will not install', () async {
      expect(
          await refusal({
            ...plain,
            'cordis.patch.yml': '- id: nipa-app-server\n  disabled: true\n'
                '- insert:\n    - id: x\n      name: bad-plugin\n',
          }),
          contains('其他插件'));
      expect(
          await refusal(plain, extra: {
            'scripts': {'postinstall': 'node steal.js'}
          }),
          contains('安装脚本'));
      expect(
          await refusal(plain, extra: {
            'dependencies': {'left-pad': '^1.0.0'}
          }),
          contains('left-pad'));
      expect(
          await refusal(plain, entries: [
            ArchiveFile.bytes('package/../../escape.js', utf8.encode('x'))
          ]),
          contains('不安全'));
      expect(await refusal({'package.json': '{"name":"bad-plugin"}'},
              extra: {'keywords': <String>[]}),
          contains('SKILL.md'));
      expect(await store.installed(), isEmpty);
    });

    test('a tarball that is not what npm promised is not installed', () async {
      final tarball = _tgz(plain);
      (server, registry) = await _registry({
        'bad-plugin': (
          _manifest('bad-plugin', _tgz({...plain, 'index.js': 'other'}),
              extra: {'keywords': ['dsh-plugin']}),
          tarball
        ),
      });
      await expectLater(store.installNpm('bad-plugin'),
          throwsA(isA<StoreFetchException>()));
    });

    test('links and symlinks in a tarball are never written', () {
      final link = ArchiveFile.symlink('package/evil', '/etc/passwd');
      final files = readPackageTarball(_tgz(plain, entries: [link]));
      expect(files.keys, unorderedEquals(['package.json', 'index.js']));
      expect(() => readPackageTarball(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<StoreFormatException>()));
    });

    test('spec and id', () {
      expect(NpmPackages.parseSpec('@huai_xin/dsh-workbuddy@0.8.7'),
          ('@huai_xin/dsh-workbuddy', '0.8.7'));
      expect(NpmPackages.parseSpec('dsh-x'), ('dsh-x', 'latest'));
      expect(() => NpmPackages.parseSpec('../evil'),
          throwsA(isA<StoreFormatException>()));
      expect(NpmPackages.idFor('@huai_xin/dsh-workbuddy'),
          'npm-huai-xin-dsh-workbuddy');
    });
  });

  group('review of #1129', () {
    test('an archive that expands without end is stopped at the limit', () {
      final bomb = GZipEncoder().encodeBytes(TarEncoder().encodeBytes(
          Archive()
            ..add(ArchiveFile.bytes(
                'package/zeros.bin', Uint8List(4 << 20)))));
      expect(bomb.length, lessThan(64 << 10));
      expect(
          () => readPackageTarball(bomb, maxBytes: 1 << 20),
          throwsA(isA<StoreFormatException>()
              .having((e) => e.message, 'message', '软件包过大')));
    });

    test('a plugin named nipa-… without a patch loads as the store item, '
        'and a record nobody can read hides nothing else', () async {
      final tarball = _tgz({
        'package.json': '{"name":"nipa-evil","main":"index.js"}',
        'index.js': 'export {}',
      });
      (server, registry) = await _registry({
        'nipa-evil': (
          _manifest('nipa-evil', tarball, extra: {
            'keywords': ['dsh-plugin']
          }),
          tarball
        ),
      });
      final installed = await store.installNpm('nipa-evil');
      expect(installed.item.dsh.single.id, 'npm-nipa-evil');
      // A record this version cannot read (written by another, or damaged).
      final file = File(p.join(temp.path, 'store', 'installed.json'));
      final raw = jsonDecode(await file.readAsString()) as Map;
      (raw['items'] as List).add({'id': 'broken', 'kind': 'theme'});
      await file.writeAsString(jsonEncode(raw));
      expect((await store.installed()).map((i) => i.item.id),
          ['npm-nipa-evil']);
      expect(store.unreadable.keys, ['broken']);
      // Saving keeps it; removing it drops it.
      await store.setEnabled('npm-nipa-evil', false);
      expect(await file.readAsString(), contains('"broken"'));
      await store.remove('broken');
      expect(await file.readAsString(), isNot(contains('"broken"')));
      expect(store.unreadable, isEmpty);
    });

    test('an update whose record cannot be saved leaves the old version',
        () async {
      await writeList([
        await skill('dmhy', {'SKILL.md': '用法', 'dmhy.py': 'v1'})
      ]);
      await store.installOfficial('dmhy');
      await writeList([
        {
          ...await skill('dmhy', {'SKILL.md': '用法', 'dmhy.py': 'v2'}),
          'version': '2.0.0'
        }
      ]);
      // The record's staging file cannot be written.
      await Directory(p.join(temp.path, 'store', 'installed.json.pending'))
          .create();
      await expectLater(store.installOfficial('dmhy'), throwsA(anything));
      expect(
          await File(p.join(temp.path, 'store', 'skills', 'dmhy', 'dmhy.py'))
              .readAsString(),
          'v1');
      expect((await store.installed()).single.item.version, '1.0.0');
    });

    test('an error reply that never ends does not hold the store, and a '
        'starting host does not wait on an install', () async {
      final hanging = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => hanging.close(force: true));
      hanging.listen((request) {
        request.response.statusCode = request.uri.path.contains('-/')
            ? 200
            : 500;
        request.response.bufferOutput = false;
        request.response.add(List.filled(64, 1));
        // Never closed.
      });
      registry = 'http://127.0.0.1:${hanging.port}';
      final watch = Stopwatch()..start();
      await expectLater(
          StoreFetch(HttpClient.new).bytes(
              [Uri.parse('$registry/x/latest')], maxBytes: 1 << 20),
          throwsA(isA<StoreFetchException>()));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));

      // An install stuck in a download, and a host starting meanwhile.
      unawaited(store
          .installNpm('stuck')
          .then<void>((_) {}, onError: (Object _) {}));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final facts = await store
          .hostFacts(runtimeModules: runtime)
          .timeout(const Duration(seconds: 2));
      expect(facts.dshPlugins, isEmpty);
    });

    test('the version the person confirmed, or a conflict', () async {
      await writeList([
        await skill('dmhy', {'SKILL.md': '用法', 'dmhy.py': 'v1'})
      ]);
      await expectLater(store.installOfficial('dmhy', version: '0.9.0'),
          throwsA(isA<StoreChanged>()));
      expect(await store.installed(), isEmpty);
      expect((await store.installOfficial('dmhy', version: '1.0.0')).item.id,
          'dmhy');
      expect(store.protectedPaths, [
        p.join(temp.path, 'store', 'plugins'),
        p.join(temp.path, 'store', 'installed.json'),
      ]);
    });
  });
}
