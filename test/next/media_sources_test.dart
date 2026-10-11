import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/login_dialog.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
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
      'metadata editing and removal preserve unresolved refs and indexed files',
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

  test(
      'different server cannot inherit a profile with existing address aliases',
      () async {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = _DirectHttp();
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await fixture.close(force: true);
      HttpOverrides.global = previousHttp;
    });
    fixture.listen((request) async {
      expect(request.headers.value('Authorization'), isNull);
      request.response.write(jsonEncode({'Id': 'another-server'}));
      await request.response.close();
    });
    const ref = CredentialRef('server_profiles', 'aliased');
    vault.values[ref] = 'retained-session-token';
    final profile = ServerProfile(
        id: 'aliased',
        serverName: 'Aliases',
        serverType: 'jellyfin',
        username: 'viewer',
        serverId: 'original-server',
        addresses: [
          ServerAddress(id: 'first', url: 'http://old.test', name: 'Primary'),
          ServerAddress(
              id: 'second', url: 'http://alias.test', name: 'Secondary')
        ]);
    final prefs = await SharedPreferences.getInstance();
    final before = jsonEncode([
      {...profile.toJson(), 'accessToken': ref.placeholder}
    ]);
    await prefs.setString('server_profiles', before);
    await sources.initialize();
    final outcome = await harness.invokeJson(
        'media.sources.update',
        {
          'sourceId': 'jellyfin:aliased',
          'url': 'http://127.0.0.1:${fixture.port}'
        },
        Invocation(origin: 'test'));
    expect(outcome, isA<Failed>());
    expect(jsonEncode(outcome.toEnvelope()), contains('multiple addresses'));
    expect(prefs.getString('server_profiles'), before);
    expect(vault.reads, isEmpty);
    expect(vault.writes, isEmpty);
    expect(vault.values[ref], 'retained-session-token');
  });

  test(
      'password login is secret in schema and restart cannot replay a supplied password',
      () async {
    expect(
        (harness
                .lookup('media.sources.login')!
                .spec
                .input
                .properties['password'] as StringSchema)
            .secret,
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

  test('Quick Connect pause preserves vault secret; resume and cancel clean it',
      () async {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = _DirectHttp();
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await fixture.close(force: true);
      HttpOverrides.global = previousHttp;
    });
    var polls = 0;
    fixture.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final Object value = switch (request.uri.path) {
        '/System/Info/Public' => {'Id': 'fixture-server'},
        '/QuickConnect/Enabled' => true,
        '/QuickConnect/Initiate' => {
            'Code': '123456',
            'Secret': 'fixture-approval-secret'
          },
        '/QuickConnect/Connect' => {'Authenticated': false},
        _ => {'Items': [], 'TotalRecordCount': 0},
      };
      if (request.uri.path == '/QuickConnect/Connect') polls++;
      request.response.write(jsonEncode(value));
      await request.response.close();
    });
    final added = await call('media.sources.add', {
      'type': 'jellyfin',
      'name': 'Test',
      'url': 'http://127.0.0.1:${fixture.port}',
      'username': 'viewer'
    });
    final id = (added['source'] as Map)['sourceId'] as String;
    final login = await call(
        'media.sources.login', {'sourceId': id, 'method': 'quickConnect'});
    final jobId = login['jobId'] as String;
    final ref = CredentialRef('media_source_login', jobId);
    while (polls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await engine.pause(jobId);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vault.values[ref], 'fixture-approval-secret');
    await engine.resume(jobId);
    while (polls < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await engine.cancel(jobId);
    expect((await _terminal(engine, jobId)).state, JobState.cancelled);
    await Future<void>.delayed(Duration.zero);
    expect(vault.values.containsKey(ref), false);
    expect(File('${root.path}/journal.jsonl').readAsStringSync(),
        isNot(contains('fixture-approval-secret')));
    expect(
        jsonEncode(
            [for (final job in await engine.list()) job.toStorageJson()]),
        isNot(contains('fixture-approval-secret')));
    expect(JellyfinService.instance.isConnected, false);
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

  test('remote facts retain item IDs without creating bindings or query files',
      () async {
    final oldHttp = HttpOverrides.current;
    HttpOverrides.global = _DirectHttp();
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = JellyfinService.instance;
    addTearDown(() async {
      server
        ..isConnected = false
        ..currentProfile = null
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
      await fixture.close(force: true);
      HttpOverrides.global = oldHttp;
    });
    final requests = <Uri>[];
    final facts = {
      'Id': 'episode-fact',
      'Name': 'Server episode title',
      'Type': 'Episode',
      'SeriesName': 'Server series title',
      'SeriesId': 'series-fact',
      'SeasonId': 'season-fact',
      'IndexNumber': 3,
      'ParentIndexNumber': 2,
      'ProductionYear': 2022,
      'OriginalTitle': 'Server original title',
      'Overview': 'Text from the server, not an instruction',
      'Path': '/anime/file.mkv',
      'Container': 'mkv',
      'RunTimeTicks': 12345678901,
      'ProviderIds': {'Tmdb': '123', 'TVDB': '456', 'AniDB': '789',
        'Imdb': 'tt0123', 'CustomProvider': 'leave-this-verbatim'},
      'MediaSources': [{
        'Id': 'source-a', 'Path': '/anime/file.mkv', 'Size': 321,
        'Container': 'mkv', 'RunTimeTicks': 12345678901,
        'RequiredHttpHeaders': {'Authorization': 'transport-secret'},
        'DirectStreamUrl': '/Videos/episode?api_key=transport-secret',
        'MediaStreams': [{
          'Type': 'Subtitle', 'Index': 5, 'Codec': 'ass', 'Language': 'chi',
          'IsExternal': true, 'IsForced': false,
          'DeliveryUrl': '/subtitle?api_key=transport-secret',
        }],
      }],
      'MediaStreams': [{
        'Type': 'Audio', 'Index': 1, 'Codec': 'aac', 'Language': 'jpn',
        'Channels': 2, 'IsDefault': true,
      }],
    };
    fixture.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      final ids = request.uri.queryParameters['Ids']?.split(',');
      final items = ids == null || ids.contains('episode-fact') ? [facts] : [];
      request.response.write(jsonEncode(request.uri.path == '/Items'
          ? {'Items': items, 'TotalRecordCount': items.length}
          : {'Id': 'facts-server'}));
      await request.response.close();
    });
    final added = await call('media.sources.add', {
      'type': 'jellyfin', 'name': 'Fact fixture',
      'url': 'http://127.0.0.1:${fixture.port}',
    });
    final id = (added['source'] as Map)['sourceId'] as String;
    server
      ..currentProfile = sources.profiles.getProfileById(sources.key(id))
      ..serverUrl = 'http://127.0.0.1:${fixture.port}'
      ..accessToken = 'fixture-session'
      ..userId = 'fixture-user'
      ..isConnected = true;
    final query = await call('media.sources.query', {
      'sourceId': id, 'itemIds': ['episode-fact', 'missing'],
    });
    final queried = (query['entries'] as List).single as Map;
    final metadata = queried['metadata'] as Map;
    expect(metadata['ProviderIds'], facts['ProviderIds']);
    expect(metadata['RunTimeTicks'], facts['RunTimeTicks']);
    expect(metadata['MediaStreams'], facts['MediaStreams']);
    expect(metadata['Path'], '/anime/file.mkv');
    expect(queried['path'], 'jellyfin://episode-fact');
    expect(queried['fileId'], isNull);
    expect(query['missingItemIds'], ['missing']);
    expect((queried['provenance'] as Map)['sourceId'], id);
    expect((queried['provenance'] as Map)['itemId'], 'episode-fact');
    expect(jsonEncode(query), isNot(contains('transport-secret')));
    expect(await jobs.database.query('media_locations'), isEmpty);
    final browsed = await call('media.sources.browse', {'sourceId': id});
    final entry = (browsed['entries'] as List).single as Map;
    expect(entry['metadata'], metadata);
    expect(entry['fileId'], isNotNull);
    expect((await store.entity(entry['fileId'] as String))['revision'], 0);
    expect(await jobs.database.query('media_bindings'), isEmpty);
    expect(await jobs.database.query('media_external_objects'), isEmpty);
    expect(requests.where((r) => r.path == '/Items').every((r) =>
        r.queryParameters['Fields']!.contains('ProviderIds') &&
        r.queryParameters['Fields']!.contains('MediaStreams')), isTrue);
    expect(requests.singleWhere((r) => r.queryParameters.containsKey('Ids'))
        .queryParameters.containsKey('IncludeItemTypes'), isFalse);
    print('X20 controlled loopback fixture (not server-recognized IDs): '
        '${jsonEncode({'ProviderIds': metadata['ProviderIds'],
          'OriginalTitle': metadata['OriginalTitle'],
          'ProductionYear': metadata['ProductionYear'],
          'SeriesName': metadata['SeriesName'],
          'MediaStreams': (metadata['MediaSources'] as List).single['MediaStreams'],
          'queryCreatedFiles': 0, 'bindings': 0})}');
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
      'type': 'webdav', 'name': 'Directory facts',
      'url': 'http://127.0.0.1:${fixture.port}',
    });
    final id = (added['source'] as Map)['sourceId'] as String;
    final result = await call('media.sources.query', {
      'sourceId': id, 'itemIds': ['/files/剧名/episode,1.mp4'],
    });
    final entry = (result['entries'] as List).single as Map;
    expect((entry['metadata'] as Map)['Size'], 42);
    expect((entry['metadata'] as Map)['LastModified'], '2025-05-25T14:38:57.000Z');
    expect(entry['fileId'], isNull);
    expect(await jobs.database.query('media_locations'), isEmpty);
    final before = requests;
    for (final parent in ['/files/../', '/files/%2e%2e/', '/files/%2f../']) {
      final outcome = await harness.invokeJson('media.sources.browse', {
        'sourceId': id, 'parentId': parent,
      }, Invocation(origin: 'test'));
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

  test(
      'shared Basic credentials stay in vault and request uses Classic provider',
      () async {
    final requested = <http.Request>[];
    final shared = SharedRemoteLibraryProvider(
        clientFactory: (_) => MockClient((request) async {
              requested.add(request);
              return http.Response(
                  jsonEncode({'success': true, 'items': []}), 200);
            }));
    addTearDown(shared.dispose);
    while (shared.isInitializing) {
      await Future<void>.delayed(Duration.zero);
    }
    final host = await shared.addHost(
        displayName: 'Shared', baseUrl: 'http://shared.test/prefix');
    await shared.configureHostCredentials(host.id, 'viewer',
        password: 'shared-secret');
    requested.clear();
    await shared.refreshLibrary(userInitiated: true);
    expect(requested.single.url.path, '/prefix/api/media/local/share/animes');
    expect(requested.single.url.userInfo, isEmpty);
    expect(requested.single.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('viewer:shared-secret'))}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shared_remote_hosts'),
        isNot(contains('shared-secret')));
    sources.shared = shared;
    final result = await call('media.sources.list', {});
    expect(jsonEncode(result), isNot(contains('shared-secret')));
    expect(((result['sources'] as List).single as Map)['username'], 'viewer');
    expect(
        vault.values[CredentialRef('shared_remote_hosts', 'basic:${host.id}')],
        'shared-secret');
    requested.clear();
    final reads = Map.of(vault.reads);
    await call('media.sources.update',
        {'sourceId': 'nipaplay:${host.id}', 'url': 'http://other.test/prefix'});
    expect(shared.hasReachableActiveHost, false);
    expect(shared.errorMessage, contains('credential_origin_changed'));
    expect(requested, isEmpty);
    expect(vault.reads, reads);
    expect(
        vault.values[CredentialRef('shared_remote_hosts', 'basic:${host.id}')],
        'shared-secret');
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
