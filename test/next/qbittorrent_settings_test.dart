import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/qbittorrent_download_backend.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'download_test_support.dart';
import 'fake_qbittorrent.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late CredentialStore previousStore;
  late MemoryVault memory;
  late FakeQbittorrent fake;
  late Directory root;
  setUp(() async {
    // The test binding answers every HttpClient with 400; this talks to a
    // real local server.
    HttpOverrides.global = null;
    previousStore = CredentialStore.instance;
    memory = MemoryVault();
    CredentialStore.instance = CredentialStore(memory, desktop: true);
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]'
    });
    root = await Directory.systemTemp.createTemp('qbit-settings-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    fake = FakeQbittorrent();
    await fake.start();
  });
  tearDown(() async {
    CredentialStore.instance = previousStore;
    await fake.stop();
    await root.delete(recursive: true);
  });

  Future<NextCore> core() async {
    final core = NextCore(
      root: root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: FakeDownloadBackend(root),
      downloadLibrary: FakeDownloadLibrary(),
      isDownloaderEnabled: () async => true,
      loadImportedKeys: () async => {},
      classic: MemoryClassic(),
      authorizedRoots: () => [root.path],
      mediaProviders: const [],
    );
    await core.ready;
    return core;
  }

  Future<Outcome<JsonEncodable>> invoke(
      NextCore core, String action, JsonMap input) =>
      Harness(core.capabilities)
          .invokeJson(action, input, Invocation(origin: 'test'));

  Future<List<Map>> engines(NextCore core) async {
    final envelope =
        (await invoke(core, 'state.query', {'view': 'downloads.engine'}))
            .toEnvelope();
    expect(envelope['status'], 'completed', reason: jsonEncode(envelope));
    return ((envelope['result'] as Map)['rows'] as List).cast<Map>();
  }

  test('a configured qBittorrent: its login in the vault only, its facts for Nipa',
      () async {
    final next = await core();
    final hub = next.downloads.qbittorrent!;
    final entry = await hub.save(
        name: 'Seedbox',
        address: '${fake.address}/',
        local: false,
        username: fake.username,
        password: fake.password);
    expect(entry.id, 'seedbox');
    expect(entry.address, fake.address.toString());

    // The login is in the vault and nowhere else.
    final file = await File('${root.path}/qbittorrent.json').readAsString();
    expect(file, isNot(contains(fake.password)));
    expect(file, isNot(contains(fake.username)));
    expect(memory.values.values.where((v) => v.contains(fake.password)), hasLength(1));

    final rows = await engines(next);
    final row = rows.singleWhere((r) => r['backend'] == 'qbittorrent');
    expect(row, containsPair('id', 'seedbox'));
    expect(row, containsPair('name', 'Seedbox'));
    expect(row, containsPair('online', true));
    expect(row, containsPair('local', false));
    expect(row, containsPair('version', 'v5.0.4'));
    expect(row, containsPair('apiVersion', '2.11.2'));
    expect(row['address'], fake.address.toString());
    expect(row['limitsSupported'], true);
    expect(row['error'], isNull);
    expect(jsonEncode(rows), isNot(contains(fake.password)));
    expect(jsonEncode(rows), isNot(contains(fake.username)));

    // Torrents the owner put there are not Next's to adopt.
    fake.torrents['c' * 40] =
        FakeTorrent('c' * 40, 'Other', '/seed/dl', [FakeFile('a.mkv', 10)]);
    await next.downloads.refresh();
    expect(await next.engine.list(type: 'download'), isEmpty);
    // But Nipa can see them, and which ones are followed.
    Future<List<Map>> torrents() async {
      final envelope =
          (await invoke(next, 'state.query', {'view': 'downloads.torrents'}))
              .toEnvelope();
      expect(envelope['status'], 'completed', reason: jsonEncode(envelope));
      return ((envelope['result'] as Map)['rows'] as List).cast<Map>();
    }

    final seen = (await torrents()).single;
    expect(seen['infoHash'], 'c' * 40);
    expect(seen['id'], 'seedbox');
    expect(seen['local'], false);
    expect(seen['title'], 'Other');
    expect(seen['savePath'], '/seed/dl');
    expect(seen['jobId'], isNull);

    // Off: said so, with the code, not with a guess.
    await fake.stop();
    final off = (await engines(next)).singleWhere((r) => r['backend'] == 'qbittorrent');
    expect(off['online'], false);
    expect(off['error'], 'unavailable');
    expect(off['version'], isNull);
    expect(off['downloadBytesPerSecond'], isNull);
    await fake.start(Uri.parse(entry.address).port);

    // The name is the reference download.add takes.
    fake.magnetContents['d' * 40] = (name: 'Show', files: [('Show/a.mkv', 10)]);
    final added = await invoke(next, 'download.add', {
      'source': 'magnet:?xt=urn:btih:${'d' * 40}',
      'backend': {'kind': 'qbittorrent', 'id': 'seedbox'}
    });
    expect(added, isA<Completed>(), reason: '${added.toEnvelope()}');
    for (var i = 0; i < 100 && !fake.torrents.containsKey('d' * 40); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(fake.torrents.keys, contains('d' * 40));
    final tracked = await next.engine.list(type: 'download');
    expect(tracked.single.details['backend'], {'kind': 'qbittorrent', 'id': 'seedbox'});
    final followed = (await torrents()).where((r) => r['infoHash'] == 'd' * 40).single;
    expect(followed['jobId'], tracked.single.jobId);
    expect((await torrents()).singleWhere((r) => r['infoHash'] == 'c' * 40)['jobId'], isNull);

    await next.close();

    // It is still there at the next start, with its login.
    final again = await core();
    addTearDown(again.close);
    final reloaded =
        (await engines(again)).singleWhere((r) => r['backend'] == 'qbittorrent');
    expect(reloaded['online'], true);
    expect(again.downloads.qbittorrent!.entries.single.hasLogin, isTrue);
    expect(await again.downloads.qbittorrent!.username('seedbox'), fake.username);
  });

  test('changing and removing keeps the login where it belongs', () async {
    final next = await core();
    addTearDown(next.close);
    final hub = next.downloads.qbittorrent!;
    await hub.save(
        name: 'Seedbox',
        address: fake.address.toString(),
        local: false,
        username: fake.username,
        password: fake.password);
    // Renamed and marked as this computer's: the login stays.
    final changed = await hub.save(
        id: 'seedbox',
        name: 'Seed',
        address: fake.address.toString(),
        local: true);
    expect(changed.id, 'seedbox');
    expect(changed.hasLogin, isTrue);
    expect(hub.backend('seedbox')!.local, isTrue);
    expect(await hub.backend('seedbox')!.list(), isEmpty);
    // A second one with the same name gets its own id.
    final other = await hub.save(
        name: 'Seedbox', address: 'http://nas.lan:8080', local: false);
    expect(other.id, 'seedbox-2');
    expect(other.hasLogin, isFalse);
    // A bad address saves nothing.
    await expectLater(
        hub.save(name: 'x', address: 'ftp://nas', local: false),
        throwsA(isA<Failure>()));
    expect(hub.entries, hasLength(2));

    await hub.remove('seedbox');
    expect(memory.values.values.where((v) => v.contains(fake.password)), isEmpty);
    final failed = await invoke(next, 'download.add', {
      'source': 'magnet:?xt=urn:btih:${'e' * 40}',
      'backend': {'kind': 'qbittorrent', 'id': 'seedbox'}
    });
    expect(failed, isA<Failed>());
    expect((failed as Failed).failure.code, FailureCode.unavailable);
    expect(
        (await engines(next)).where((r) => r['backend'] == 'qbittorrent').map((r) => r['id']),
        ['seedbox-2']);
    expect(QbittorrentDownloadBackend.kind, 'qbittorrent');
  });
}
