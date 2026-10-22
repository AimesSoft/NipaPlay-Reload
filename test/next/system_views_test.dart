import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

/// A builtin backend that reports a rate and a session limit, as the native
/// engine does.
final class _RateBackend
    implements DownloadBackend, BandwidthDownloadBackend {
  _RateBackend(this.inner);
  final FakeDownloadBackend inner;
  bool paused = false;
  @override
  DownloadBackendRef get reference => inner.reference;
  @override
  String? get credentialRef => inner.credentialRef;
  @override
  Future<void> initialize() => inner.initialize();
  @override
  Future<List<DownloadSnapshot>> list() async => [
        for (final s in await inner.list())
          DownloadSnapshot(
              handle: s.handle,
              infoHash: s.infoHash,
              title: s.title,
              output: s.output,
              completed: s.completed,
              total: s.total,
              finished: s.finished,
              paused: paused,
              downloadSpeedBytesPerSecond: 1234,
              uploadSpeedBytesPerSecond: 56,
              files: s.files)
      ];
  @override
  Future<DownloadSnapshot> read(String handle) => inner.read(handle);
  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
          {Future<void>? stopRequested}) =>
      inner.add(request, stopRequested: stopRequested);
  @override
  Future<void> pause(String handle) => inner.pause(handle);
  @override
  Future<void> resume(String handle) => inner.resume(handle);
  @override
  Future<void> remove(String handle) => inner.remove(handle);
  @override
  Future<void> delete(String handle) => inner.delete(handle);
  @override
  Future<int?> readSize(DownloadFile file) => inner.readSize(file);
  @override
  Future<JsonMap> bandwidth(JsonMap input) async => {
        'supported': true,
        'sessionInitialized': true,
        'actual': {
          'downloadBytesPerSecond': 0,
          'uploadBytesPerSecond': 65536
        }
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late CredentialStore previousStore;
  setUp(() {
    previousStore = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]'
    });
  });
  tearDown(() => CredentialStore.instance = previousStore);

  Future<NextCore> core(Directory root, DownloadBackend backend,
      {bool enabled = true}) async {
    final core = NextCore(
      root: root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: backend,
      downloadLibrary: FakeDownloadLibrary(),
      isDownloaderEnabled: () async => enabled,
      loadImportedKeys: () async => {},
      classic: MemoryClassic(),
      authorizedRoots: () => [root.path],
      mediaProviders: const [],
    );
    await core.ready;
    return core;
  }

  Future<JsonMap> call(NextCore core, String action, JsonMap input) async {
    final harness = Harness(core.capabilities);
    final envelope = (await harness.invokeJson(
            action, input, Invocation(origin: 'test')))
        .toEnvelope();
    expect(envelope['status'], 'completed', reason: jsonEncode(envelope));
    return (envelope['result'] as Map).cast<String, Object?>();
  }

  Future<List<Map>> rows(NextCore core, String view,
          [JsonMap query = const {}]) async =>
      ((await call(core, 'state.query', {'view': view, ...query}))['rows']
              as List)
          .cast<Map>();

  Future<Directory> temp() async {
    final root = await Directory.systemTemp.createTemp('system-views-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    addTearDown(() => root.delete(recursive: true));
    return root;
  }

  test('every system view is described, with a description that states facts',
      () async {
    final root = await temp();
    final next = await core(root, FakeDownloadBackend(root));
    addTearDown(next.close);
    final described = await call(next, 'state.describe', {});
    final names = [
      for (final v in described['views'] as List) (v as Map)['view'] as String
    ];
    const expected = [
      'media.sources',
      'media.source_addresses',
      'accounts',
      'network.routes',
      'network.observations',
      'storage.volumes',
      'storage.directories',
      'library.scan',
      'app.update',
      'harness.hooks',
      'harness.schedules',
      'downloads.engine',
    ];
    expect(names, containsAll(expected));
    for (final name in expected) {
      final one = ((await call(next, 'state.describe', {'view': name}))['views']
              as List)
          .single as Map;
      expect(one['description'], isA<String>(), reason: name);
      expect((one['fields'] as Map).keys, isNotEmpty, reason: name);
    }
  });

  test('download engines: counts, rate and limits per backend', () async {
    final root = await temp();
    final fake = FakeDownloadBackend(root)..present = true;
    final next = await core(root, _RateBackend(fake));
    addTearDown(next.close);
    await next.downloads.refresh();
    final engines = {
      for (final row in await rows(next, 'downloads.engine'))
        row['backend'] as String: row
    };
    expect(engines.keys, ['builtin', 'http']);
    final builtin = engines['builtin']!;
    expect(builtin['enabled'], true);
    expect(builtin['total'], 1);
    expect(builtin['running'] + builtin['queued'] + builtin['paused'] +
            builtin['waiting'] + builtin['finished'],
        1);
    expect(builtin['downloadBytesPerSecond'], 1234);
    expect(builtin['uploadBytesPerSecond'], 56);
    expect(builtin['limitsSupported'], true);
    expect(builtin['sessionInitialized'], true);
    expect(builtin['downloadLimitBytesPerSecond'], 0);
    expect(builtin['uploadLimitBytesPerSecond'], 65536);
    final http = engines['http']!;
    expect(http['total'], 0);
    expect(http['limitsSupported'], false);
    expect(http['downloadLimitBytesPerSecond'], isNull);
    expect(http['downloadBytesPerSecond'], 0);
    expect(DateTime.parse(builtin['observedAt'] as String).isUtc, true);

    // A paused or finished task adds no rate.
    fake.finished = true;
    final finished = (await rows(next, 'downloads.engine',
        {'filter': {'backend': {'eq': 'builtin'}}})).single;
    expect(finished['downloadBytesPerSecond'], 0);
  });

  test('with downloads off the backends are not asked and rates are unknown',
      () async {
    final root = await temp();
    final fake = FakeDownloadBackend(root);
    final next = await core(root, _RateBackend(fake), enabled: false);
    addTearDown(next.close);
    final before = fake.initializations;
    for (final row in await rows(next, 'downloads.engine')) {
      expect(row['enabled'], false);
      expect(row['downloadBytesPerSecond'], isNull);
      expect(row['sessionInitialized'], isNull);
    }
    expect(fake.initializations, before);
  });

  test('a backend that fails reports its code instead of a rate', () async {
    final root = await temp();
    final fake = FakeDownloadBackend(root)..online = false;
    final next = await core(root, _RateBackend(fake));
    addTearDown(next.close);
    final builtin = (await rows(next, 'downloads.engine',
        {'filter': {'backend': {'eq': 'builtin'}}})).single;
    expect(builtin['downloadBytesPerSecond'], isNull);
    expect(builtin['error'], 'unavailable');
  });

  test('source, account, scan, update, network and storage views read the live parts',
      () async {
    final root = await temp();
    final next = await core(root, FakeDownloadBackend(root));
    addTearDown(next.close);
    await next.mediaSources.ensureInitialized();
    await next.mediaSources.configure({
      'type': 'webdav',
      'name': 'Nas',
      'url': 'http://192.168.1.2/dav',
      'wanUrl': 'https://nas.example.com/dav',
      'username': 'viewer'
    });
    final sources = await rows(next, 'media.sources');
    expect(sources.single['name'], 'Nas');
    expect(sources.single['addressCount'], 2);
    expect(sources.single['credentialState'], 'missing');
    expect(sources.single['syncResult'], isNull);
    final addresses = await rows(next, 'media.source_addresses',
        {'filter': {'reachability': {'eq': 'unknown'}}});
    expect(addresses.map((a) => a['role']), ['lan', 'wan']);
    expect(await rows(next, 'media.source_addresses',
        {'filter': {'reachability': {'eq': 'unreachable'}}}), isEmpty);
    // The relation reads the same rows under the source.
    final related = (await call(next, 'state.query', {
      'view': 'media.sources',
      'include': {'addressRows': {}}
    }))['rows'] as List;
    expect((((related.single as Map)['addressRows'] as Map)['rows'] as List),
        hasLength(2));

    final accounts = await rows(next, 'accounts');
    expect(accounts.map((a) => a['provider']), ['dandanplay', 'bangumi']);
    expect(accounts.map((a) => a['loggedIn']), [false, false]);

    // Without a Classic scan service the view says so instead of an empty scan.
    final unattached = (await Harness(next.capabilities).invokeJson(
            'state.query', {'view': 'library.scan'}, Invocation(origin: 'test')))
        .toEnvelope();
    expect(unattached['status'], 'failed');
    final classic = ScanService.forTesting(
        completedFilesProcessor: (_) async => [], startupAction: () async {});
    addTearDown(classic.dispose);
    next.classicScan.scan = classic;
    final scan = (await rows(next, 'library.scan')).single;
    expect(scan['scanning'], false);
    expect(scan['failedFileCount'], 0);

    final update = (await rows(next, 'app.update')).single;
    expect(update['checked'], false);
    expect(update['checkedAt'], isNull);

    final routes = await rows(next, 'network.routes');
    expect(routes.map((r) => r['provider']), ['proxy', 'dandanplay']);
    expect(routes.first['mode'], isA<String>());
    expect(await rows(next, 'network.observations'), isA<List>());

    final volumes = await rows(next, 'storage.volumes');
    expect(volumes, isNotEmpty);
    final directories = await rows(next, 'storage.directories');
    expect(directories.map((d) => d['role']), contains('downloads'));
    expect(jsonEncode([sources, accounts]), isNot(contains('password')));
  });
}
