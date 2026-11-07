import 'dart:async';
import 'dart:convert';
import 'package:nipaplay/services/webdav_service.dart';
import 'dart:io';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/login_dialog.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/media_sources/sync.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:nipaplay/services/backup_category.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore jobs;
  late IdentityStore store;
  late MediaSourcesService sources;
  late TaskEngine engine;
  late Harness harness;
  late MemoryVault vault;
  late CredentialStore previous;

  setUp(() async {
    AutoSyncSettings.resetForTesting();
    previous = CredentialStore.instance;
    vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]'
    });
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay',
        packageName: 'nipaplay',
        version: 'test',
        buildNumber: '1',
        buildSignature: '');
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('nipa-source-invariants-');
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    store = IdentityStore(jobs.database, 'test-device');
    sources = MediaSourcesService(store);
    await sources.initialize();
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'test-device',
        executors: mediaSourcesExecutors(sources));
    sources.engine = engine;
    harness = Harness([MediaSourcesCapability(sources), TaskCapability(engine)],
        observers: [JsonlJournal(File('${root.path}/journal.jsonl'))]);
    await engine.start();
  });
  tearDown(() async {
    await engine.close();
    await sources.close();
    await store.closeEvents();
    await jobs.database.close();
    await root.delete(recursive: true);
    CredentialStore.instance = previous;
  });

  Future<JsonMap> call(String name, JsonMap input) async {
    final outcome =
        await harness.invokeJson(name, input, Invocation(origin: 'test'));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(name)!.spec.output.validate(result), isEmpty);
    return result;
  }

  test(
      'metadata editing and list preserve unresolved refs; removal keeps files',
      () async {
    const ref = CredentialRef('webdav_connections', 'one');
    vault.values[ref] = 'never-output-this-password';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'webdav_connections',
        jsonEncode([
          {
            'id': 'one',
            'name': 'First',
            'url': 'http://example.test/dav/',
            'username': 'viewer',
            'password': ref.placeholder,
            'isConnected': false
          },
        ]));
    await sources.initialize();
    final fileId = await store.ensureFile('webdav://one/new.mkv');
    final updated = await call(
        'media.sources.update', {'sourceId': 'webdav:one', 'name': 'Renamed'});
    expect((updated['source'] as Map)['name'], 'Renamed');
    expect(vault.reads, isEmpty);
    expect(vault.writes, isEmpty);
    expect(
        (jsonDecode(prefs.getString('webdav_connections')!) as List)
            .single['password'],
        ref.placeholder);
    await call('media.sources.list', {});
    expect(vault.reads, isEmpty);
    expect(
        (await call(
            'media.sources.remove', {'sourceId': 'webdav:one'}))['removed'],
        true);
    expect((await call('media.sources.list', {}))['sources'], isEmpty);
    expect(await store.ensureFile('webdav://one/new.mkv'), fileId);
    expect((await store.entity(fileId))['revision'], 0);
  });

  test(
      'sync endpoint changes clear credentials; category patches retain settings',
      () async {
    final sync = SyncService(sources);
    await AutoSyncSettings.saveWebDavConfiguration(
        serverUrl: 'http://example.test/dav/',
        username: 'viewer',
        password: 'sync-private',
        remotePath: '/sync',
        intervalMinutes: 15,
        categories: {BackupCategory.watchHistory},
        syncOnRecordChange: true);
    await sync.configure({'intervalMinutes': 20});
    expect(await AutoSyncSettings.getPassword(), 'sync-private');
    expect((await sync.status())['hasPassword'], true);
    expect((await sync.configuration())['categories'], ['watchHistory']);
    await expectLater(
        sync.configure({'categories': <String>[]}), throwsA(isA<Failure>()));
    expect(await AutoSyncSettings.getPassword(), 'sync-private');
    await sync.configure({'url': 'http://other.test/dav'});
    expect(await AutoSyncSettings.getPassword(), '');
    expect((await sync.status())['hasPassword'], false);
    expect(await AutoSyncSettings.getSyncOnRecordChange(), true);
    expect(await AutoSyncSettings.getRemotePath(), '/sync');
    expect(jsonEncode(await sync.status()), isNot(contains('sync-private')));
    final actions = SyncCapability(sync).actions;
    expect(
        actions
            .where((a) => a.spec.input.properties.containsKey('password'))
            .map((a) => a.spec.id),
        ['sync.login']);
    final login = actions.singleWhere((a) => a.spec.id == 'sync.login');
    expect(login.spec.input.properties['password']!.secret, isTrue);
    expect(login.spec.input.properties, contains('userAuthorization'));
  });

  test(
      'refused source credentials are not automatically retried and have no network side effects',
      () async {
    const ref = CredentialRef('webdav_connections', 'denied');
    vault
      ..values[ref] = 'retained-secret'
      ..denied = ref;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'webdav_connections',
        jsonEncode([
          {
            'id': 'denied',
            'name': 'Denied',
            'url': 'http://example.test/dav/',
            'username': 'viewer',
            'password': ref.placeholder,
            'isConnected': false
          },
        ]));
    await sources.initialize();
    for (var i = 0; i < 3; i++) {
      expect(
          await harness.invokeJson('media.sources.browse',
              {'sourceId': 'webdav:denied'}, Invocation(origin: 'test')),
          isA<Failed>());
    }
    expect(vault.reads[ref], 1);
    expect(vault.values[ref], 'retained-secret');
    expect(await jobs.database.query('media_locations'), isEmpty);
    await call('media.sources.list', {});
    expect(vault.reads[ref], 1);
  });

  test('changing source authority preserves secrets but cannot forward them',
      () async {
    const davRef = CredentialRef('webdav_connections', 'dav-origin');
    const smbRef = CredentialRef('smb_connections', 'smb-origin');
    vault.values[davRef] = 'retained-dav-secret';
    vault.values[smbRef] = 'retained-smb-secret';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'webdav_connections',
        jsonEncode([
          {
            'id': 'dav-origin',
            'name': 'DAV',
            'url': 'http://old.test/dav',
            'username': 'viewer',
            'password': davRef.placeholder
          }
        ]));
    await prefs.setString(
        'smb_connections',
        jsonEncode([
          {
            'id': 'smb-origin',
            'name': 'SMB',
            'host': 'old.test',
            'port': 445,
            'username': 'viewer',
            'password': smbRef.placeholder
          }
        ]));
    await sources.initialize();
    await call('media.sources.update',
        {'sourceId': 'webdav:dav-origin', 'url': 'http://other.test/dav'});
    await call('media.sources.update',
        {'sourceId': 'smb:smb-origin', 'host': 'other.test'});
    for (final id in ['webdav:dav-origin', 'smb:smb-origin']) {
      final outcome = await harness.invokeJson(
          'media.sources.browse', {'sourceId': id}, Invocation(origin: 'test'));
      expect(outcome, isA<Failed>());
      expect(jsonEncode(outcome.toEnvelope()),
          contains('credential_origin_changed'));
    }
    expect(vault.reads, isEmpty);
    expect(vault.writes, isEmpty);
    expect(vault.values[davRef], 'retained-dav-secret');
    expect(vault.values[smbRef], 'retained-smb-secret');
    expect(
        (jsonDecode(prefs.getString('webdav_connections')!) as List)
            .single['password'],
        davRef.placeholder);
    expect(
        (jsonDecode(prefs.getString('smb_connections')!) as List)
            .single['password'],
        smbRef.placeholder);
    final sync = await engine.submit(
        type: 'media.sources.sync',
        title: 'Resume sync of original source',
        input: {
          'sourceId': 'smb:smb-origin',
          'url': 'smb://old.test:445',
          'username': 'viewer',
          'libraries': ['/anime']
        });
    final done = await _terminal(engine, sync.jobId);
    expect(done.state, JobState.failed);
    expect(done.error!.message, contains('Source changed'));
    expect(vault.reads, isEmpty);
    expect(await jobs.database.query('media_locations'), isEmpty);
  });

  test('WebDAV and SMB keep LAN and WAN addresses apart through list and put',
      () async {
    final dav = ((await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Both',
      'url': 'http://192.168.1.2/dav/',
      'wanUrl': 'https://nas.example.com/dav'
    }))['source'] as Map)['sourceId'] as String;
    final smb = ((await call('media.sources.add', {
      'type': 'smb',
      'name': 'Remote only',
      'wanHost': 'nas.example.com',
      'wanPort': 4445
    }))['source'] as Map)['sourceId'] as String;
    String bare(Object? url) => '$url'.replaceFirst(RegExp(r'/+$'), '');
    Future<Map<String, Map>> listed() async => {
          for (final row
              in (await call('media.sources.list', {}))['sources'] as List)
            (row as Map)['sourceId'] as String: row
        };
    var rows = await listed();
    expect(bare(rows[dav]!['url']), 'http://192.168.1.2/dav');
    expect(bare(rows[dav]!['wanUrl']), 'https://nas.example.com/dav');
    expect(bare(rows[dav]!['address']), 'http://192.168.1.2/dav');
    expect(rows[smb]!['url'], '');
    expect(rows[smb]!['host'], '');
    expect(rows[smb]!['wanHost'], 'nas.example.com');
    expect(rows[smb]!['wanPort'], 4445);
    expect(rows[smb]!['wanUrl'], 'smb://nas.example.com:4445');
    expect(rows[smb]!['address'], 'smb://nas.example.com:4445');

    // Updating one address keeps the other; an empty string clears.
    await call('media.sources.update',
        {'sourceId': dav, 'wanUrl': 'https://other.example.com'});
    await call(
        'media.sources.update', {'sourceId': smb, 'host': '192.168.1.9'});
    rows = await listed();
    expect(bare(rows[dav]!['url']), 'http://192.168.1.2/dav');
    expect(bare(rows[dav]!['wanUrl']), 'https://other.example.com');
    expect(rows[smb]!['host'], '192.168.1.9');
    expect(rows[smb]!['wanHost'], 'nas.example.com');
    await call('media.sources.update', {'sourceId': dav, 'url': ''});
    expect(
        bare((await listed())[dav]!['address']), 'https://other.example.com');
    for (final bad in [
      {'sourceId': dav, 'wanUrl': ''},
      {'sourceId': dav, 'url': 'http://user:pw@192.168.1.2'},
      {'sourceId': dav, 'wanUrl': 'ftp://nas.example.com'},
      {'sourceId': smb, 'host': '', 'wanHost': ''},
    ]) {
      final outcome = await harness.invokeJson(
          'media.sources.update', bad, Invocation(origin: 'test'));
      expect(outcome, isA<Failed>(), reason: '$bad');
    }
  });

  test('saved credentials follow the set of addresses, not the one in use',
      () async {
    const ref = CredentialRef('webdav_connections', 'dav-dual');
    vault.values[ref] = 'dual-secret';
    final prefs = await SharedPreferences.getInstance();
    // A legacy public address migrates to WAN; its saved origin still covers it.
    await prefs.setString(
        'webdav_connections',
        jsonEncode([
          {
            'id': 'dav-dual',
            'name': 'Dual',
            'url': 'https://nas.example.com/dav',
            'username': 'viewer',
            'password': ref.placeholder,
            'credentialOrigin': 'https://nas.example.com'
          }
        ]));
    await sources.initialize();
    WebDAVConnection current() =>
        sources.webdav.getConnectionByIdOrName('dav-dual')!;
    expect(current().url, '');
    await current().resolvePassword();
    await call('media.sources.update',
        {'sourceId': 'webdav:dav-dual', 'name': 'Dual renamed'});
    await current().resolvePassword();
    // An address of another authority cannot receive the password.
    await call('media.sources.update',
        {'sourceId': 'webdav:dav-dual', 'url': 'http://192.168.1.2'});
    await expectLater(current().resolvePassword(), throwsStateError);
    // Removing it again restores the original set.
    await call(
        'media.sources.update', {'sourceId': 'webdav:dav-dual', 'url': ''});
    await current().resolvePassword();
    expect(vault.values[ref], 'dual-secret');
  });

  test(
      'login exposes secret input with authorization and restart cannot replay a supplied password',
      () async {
    expect(
        harness
            .lookup('media.sources.login')!
            .spec
            .input
            .properties
            .containsKey('password'),
        true);
    expect(
        harness
            .lookup('media.sources.login')!
            .spec
            .input
            .properties['password']!
            .secret,
        true);
    expect(
        harness
            .lookup('media.sources.login')!
            .spec
            .input
            .properties
            .containsKey('userAuthorization'),
        true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'webdav_connections',
        jsonEncode([
          {
            'id': 'one',
            'name': 'Pending',
            'url': 'http://example.test/',
            'username': 'viewer',
            'password': ''
          },
        ]));
    await sources.initialize();
    final job = await engine.submit(
        type: 'media.sources.login',
        title: 'Interrupted supplied login',
        input: {
          'sourceId': 'webdav:one',
          'method': 'password',
          'url': 'http://example.test/',
          'username': 'viewer',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String()
        });
    final done = await _terminal(engine, job.jobId);
    expect(done.state, JobState.failed);
    expect(done.error!.message, contains('discarded at restart'));
    expect(vault.reads, isEmpty);
  });

  test('cancelled password window cannot authenticate or save a secret',
      () async {
    final add = await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Pending',
      'url': 'http://example.test',
      'username': 'viewer'
    });
    final id = (add['source'] as Map)['sourceId'] as String;
    sources.requestPassword = (source, stopped) async => null;
    final login =
        await call('media.sources.login', {'sourceId': id, 'method': 'window'});
    final job = await _terminal(engine, login['jobId'] as String);
    expect(job.state, JobState.cancelled);
    expect(job.input.containsKey('password'), false);
    expect((await sources.source(id))['connected'], false);
    expect(vault.values.values.every((secret) => secret.isEmpty), true);
  });

  test('directory query accepts Unicode and commas but rejects traversal',
      () async {
    final oldHttp = HttpOverrides.current;
    HttpOverrides.global = _DirectHttp();
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await fixture.close(force: true);
      HttpOverrides.global = oldHttp;
    });
    var requests = 0;
    fixture.listen((request) async {
      requests++;
      expect(request.uri.pathSegments, ['files', '剧名', '']);
      request.response
        ..statusCode = 207
        ..headers.contentType = ContentType('application', 'xml')
        ..write('''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:"><D:response>
<D:href>/files/%E5%89%A7%E5%90%8D/</D:href><D:propstat><D:prop>
<D:resourcetype><D:collection/></D:resourcetype></D:prop>
<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response><D:response>
<D:href>/files/%E5%89%A7%E5%90%8D/episode%2C1.mp4</D:href>
<D:propstat><D:prop><D:displayname>episode,1.mp4</D:displayname>
<D:getcontentlength>42</D:getcontentlength>
<D:getlastmodified>Sun, 25 May 2025 14:38:57 GMT</D:getlastmodified>
<D:resourcetype/></D:prop><D:status>HTTP/1.1 200 OK</D:status>
</D:propstat></D:response></D:multistatus>''');
      await request.response.close();
    });
    final added = await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Directory facts',
      'url': 'http://127.0.0.1:${fixture.port}',
    });
    final id = (added['source'] as Map)['sourceId'] as String;
    final result = await call('media.sources.query', {
      'sourceId': id,
      'itemIds': ['/files/剧名/episode,1.mp4'],
    });
    final entry = (result['entries'] as List).single as Map;
    expect((entry['metadata'] as Map)['Size'], 42);
    expect(
        (entry['metadata'] as Map)['LastModified'], '2025-05-25T14:38:57.000Z');
    expect(entry['fileId'], isNull);
    expect(await jobs.database.query('media_locations'), isEmpty);
    final before = requests;
    for (final parent in ['/files/../', '/files/%2e%2e/', '/files/%2f../']) {
      final outcome = await harness.invokeJson(
          'media.sources.browse',
          {
            'sourceId': id,
            'parentId': parent,
          },
          Invocation(origin: 'test'));
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).failure.code, FailureCode.invalidInput);
    }
    expect(requests, before);
  });

  testWidgets(
      'password window prefills nonsecret fields and closes its own route on stop',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'isMinimized' ? false : null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null));
    await tester.pumpWidget(MaterialApp(
        navigatorKey: globals.navigatorKey, home: const SizedBox()));
    final stopFirst = Completer<void>(), stopSecond = Completer<void>();
    final first = showMediaSourceLogin(
        {'name': 'First', 'url': 'http://first.test', 'username': 'first-user'},
        stopFirst.future);
    await tester.pumpAndSettle();
    expect(find.text('http://first.test'), findsOneWidget);
    expect(find.text('first-user'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.take(2).every((f) => f.readOnly), true);
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
        true);
    final second = showMediaSourceLogin({
      'name': 'Second',
      'url': 'http://second.test',
      'username': 'second-user'
    }, stopSecond.future);
    await tester.pumpAndSettle();
    stopFirst.complete();
    await tester.pumpAndSettle();
    expect(await first, isNull);
    expect(find.text('登录 Second'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'user-typed-secret');
    await tester.tap(find.text('登录').last);
    await tester.pumpAndSettle();
    expect(await second, 'user-typed-secret');
  });
}

Future<Job> _terminal(TaskEngine engine, String id) async {
  var job = await engine.get(id);
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!job.state.isTerminal && DateTime.now().isBefore(deadline)) {
    job = await engine.wait(id,
        afterRevision: job.revision, timeout: const Duration(seconds: 1));
  }
  return job;
}

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
