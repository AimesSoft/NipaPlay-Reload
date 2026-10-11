import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/smb2_native_service_ffi.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X12 real isolated source round trips', () async {
    final credentials =
        jsonDecode(File('/tmp/nipa-next/testservers.json').readAsStringSync())
            as Map;
    for (final name in ['jellyfin', 'emby', 'webdav']) {
      final c = credentials[name] as Map;
      expect(
          Uri.parse((c['base_url'] ?? c['url']) as String).host, '127.0.0.1');
    }
    expect((credentials['smb'] as Map)['host'], '127.0.0.1');
    final oldVault = CredentialStore.instance;
    final oldHttp = HttpOverrides.current;
    final vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    HttpOverrides.global = _DirectHttp();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]'
    });
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay',
        packageName: 'nipaplay',
        version: 'X12',
        buildNumber: '1',
        buildSignature: '');
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('nipa-x12-');
    final jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final identities = IdentityStore(jobs.database, 'x12-experiment');
    final service = MediaSourcesService(identities);
    await service.initialize();
    final engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'x12-experiment',
        executors: mediaSourcesExecutors(service));
    service.engine = engine;
    final journal = File('${root.path}/journal.jsonl');
    final harness = Harness(
        [MediaSourcesCapability(service), TaskCapability(engine)],
        observers: [JsonlJournal(journal)]);
    await engine.start();
    addTearDown(() async {
      await engine.close();
      await service.close();
      await identities.closeEvents();
      await jobs.database.close();
      Smb2NativeService.instance.dispose();
      await root.delete(recursive: true);
      CredentialStore.instance = oldVault;
      HttpOverrides.global = oldHttp;
      debugDefaultTargetPlatformOverride = null;
    });

    Future<JsonMap> call(String id, JsonMap input) async {
      final outcome = await harness.invokeJson(
          id, input, Invocation(origin: 'x12-experiment'));
      expect(outcome, isA<Completed>(),
          reason: jsonEncode(outcome.toEnvelope()));
      final result = (outcome as Completed).value.toJson();
      expect(harness.lookup(id)!.spec.output.validate(result), isEmpty,
          reason: id);
      return result;
    }

    Future<Job> wait(JsonMap result) async {
      var job = await engine.get(result['jobId'] as String);
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!job.state.isTerminal && DateTime.now().isBefore(deadline)) {
        job = await engine.wait(job.jobId,
            afterRevision: job.revision, timeout: const Duration(seconds: 15));
      }
      expect(job.state, JobState.succeeded, reason: jsonEncode(job.toJson()));
      return job;
    }

    Future<String> add(String type) async {
      final c = credentials[type] as Map;
      final result = await call('media.sources.add', {
        'type': type,
        'name': 'X12 $type',
        'username': c['user_name'],
        if (type == 'smb') ...{'host': c['host'], 'port': c['port']} else
          'url': c['base_url'] ?? c['url'],
      });
      final source = result['source'] as JsonMap;
      print('X12 add $type: ${jsonEncode(source)}');
      return source['sourceId'] as String;
    }

    final jellyfin = await add('jellyfin');
    final jc = credentials['jellyfin'] as Map;
    final quick = await call('media.sources.login',
        {'sourceId': jellyfin, 'method': 'quickConnect'});
    print('X12 initiate Quick Connect: ${jsonEncode(quick)}');
    final approval = await _administratorRequest(
        jc, '/QuickConnect/Authorize?code=${quick['code']}',
        method: 'POST');
    expect(approval, isTrue);
    print('X12 approve on server: $approval');
    final quickJob = await wait(quick);
    print('X12 Quick Connect task: ${jsonEncode(quickJob.receipt!.toJson())}');
    expect(
        vault.values.keys.any((ref) => ref.namespace == 'media_source_login'),
        isFalse);

    final password = await call('media.sources.login',
        {'sourceId': jellyfin, 'password': jc['password']});
    print('X12 initiate user-provided password: ${jsonEncode(password)}');
    final passwordJob = await wait(password);
    print('X12 password task: ${jsonEncode(passwordJob.receipt!.toJson())}');
    final libraries =
        await call('media.sources.libraries', {'sourceId': jellyfin});
    print('X12 Jellyfin libraries: ${jsonEncode(libraries)}');
    final anime = (libraries['libraries'] as List)
        .cast<Map>()
        .singleWhere((l) => l['name'] == '番剧')['id'] as String;
    print('X12 select 番剧: ${jsonEncode(await call('media.sources.select', {
          'sourceId': jellyfin,
          'libraries': [anime]
        }))}');
    final folder = await call(
        'media.sources.browse', {'sourceId': jellyfin, 'parentId': anime});
    print('X12 Jellyfin folder: ${jsonEncode(folder)}');
    final episodes = await call('media.sources.browse',
        {'sourceId': jellyfin, 'parentId': anime, 'recursive': true});
    expect(episodes['total'], 6);
    expect(
        (episodes['entries'] as List)
            .every((entry) => (entry as Map)['fileId'] != null),
        isTrue);
    print('X12 Jellyfin episodes: ${jsonEncode(episodes)}');
    print(
        'X12 live connection check: ${jsonEncode(await call('media.sources.check', {
          'sourceId': jellyfin
        }))}');
    final sync =
        await wait(await call('media.sources.sync', {'sourceId': jellyfin}));
    expect(sync.receipt!.details['indexed'], 6);
    print('X12 Jellyfin sync: ${jsonEncode(sync.receipt!.toJson())}');
    final locations = await jobs.database.query('media_locations',
        where: 'locator LIKE ?', whereArgs: ['jellyfin://%']);
    expect(locations, hasLength(6));
    for (final entry in (episodes['entries'] as List).cast<Map>()) {
      expect(await identities.ensureFile(entry['path'] as String),
          entry['fileId']);
    }
    print(
        'X12 unified index: files=${locations.length}, Classic paths reuse same fileIds=true');

    final emby = await add('emby');
    await wait(await call('media.sources.login', {
      'sourceId': emby,
      'password': (credentials['emby'] as Map)['password']
    }));
    final el = await call('media.sources.libraries', {'sourceId': emby});
    final eanime = (el['libraries'] as List)
        .cast<Map>()
        .singleWhere((l) => l['name'] == '番剧')['id'] as String;
    final eb = await call('media.sources.browse',
        {'sourceId': emby, 'parentId': eanime, 'recursive': true});
    expect(eb['total'], 6);
    print('X12 Emby browse: ${jsonEncode(eb)}');
    final browseTotals = <String, Object?>{
      'jellyfin': episodes['total'],
      'emby': eb['total']
    };

    for (final type in ['smb', 'webdav']) {
      final id = await add(type);
      await wait(await call('media.sources.login', {
        'sourceId': id,
        'password': (credentials[type] as Map)['password']
      }));
      final libraries = await call('media.sources.libraries', {'sourceId': id});
      print('X12 $type libraries: ${jsonEncode(libraries)}');
      final pending = ['/anime/'];
      final visited = <String>{};
      final contents = <Map>[];
      while (pending.isNotEmpty) {
        final parent = pending.removeAt(0);
        if (!visited.add(parent)) continue;
        final page = await call(
            'media.sources.browse', {'sourceId': id, 'parentId': parent});
        for (final entry in (page['entries'] as List).cast<Map>()) {
          if (entry['isDirectory'] == true) {
            pending.add(entry['id'] as String);
          } else {
            contents.add(entry);
          }
        }
      }
      expect(contents, hasLength(6));
      browseTotals[type] = contents.length;
      print('X12 $type browse: ${jsonEncode({
            'sourceId': id,
            'entries': contents,
            'total': contents.length
          })}');
    }

    // A separate loopback sharing endpoint exercises the Classic shared client;
    // it does not connect to the user's running NipaPlay.
    final sharingServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    const sharedPassword = 'x12-ephemeral-shared-password';
    final sharedAuthorization =
        'Basic ${base64Encode(utf8.encode('viewer:$sharedPassword'))}';
    sharingServer.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.headers.value('authorization') != sharedAuthorization) {
        request.response.statusCode = 401;
        request.response.write('{}');
      } else if (request.uri.path.endsWith('/animes/114')) {
        request.response.write(jsonEncode({
          'episodes': [
            for (var i = 1; i <= 6; i++)
              {
                'shareId': 'x12-$i',
                'title': '莉可丽丝 $i',
                'fileName': 'Lycoris-$i.mkv',
                'streamPath': '/api/media/local/share/stream/x12-$i',
                'fileExists': true,
              }
          ]
        }));
      } else {
        request.response.write(jsonEncode({
          'success': true,
          'items': [
            {'animeId': 114, 'name': '莉可丽丝', 'episodeCount': 6}
          ]
        }));
      }
      await request.response.close();
    });
    final sharing = SharedRemoteLibraryProvider();
    addTearDown(() async {
      sharing.dispose();
      await sharingServer.close(force: true);
    });
    while (sharing.isInitializing) {
      await Future<void>.delayed(Duration.zero);
    }
    service.shared = sharing;
    final sharedAdd = await call('media.sources.add', {
      'type': 'nipaplay',
      'name': 'X12 isolated sharing endpoint',
      'url': 'http://127.0.0.1:${sharingServer.port}',
      'username': 'viewer'
    });
    final sharedId = (sharedAdd['source'] as Map)['sourceId'] as String;
    final sharedLogin = await wait(await call('media.sources.login',
        {'sourceId': sharedId, 'password': sharedPassword}));
    await call('media.sources.select', {
      'sourceId': sharedId,
      'libraries': ['114']
    });
    final sharedBrowse = await call(
        'media.sources.browse', {'sourceId': sharedId, 'parentId': '114'});
    expect(sharedBrowse['total'], 6);
    browseTotals['nipaplayLoopbackFixture'] = sharedBrowse['total'];
    final sharedSync =
        await wait(await call('media.sources.sync', {'sourceId': sharedId}));
    expect(sharedSync.receipt!.details['indexed'], 6);
    print(
        'X12 NipaPlay loopback fixture: login=${sharedLogin.state.wireName}, browse=${sharedBrowse['total']}, indexed=${sharedSync.receipt!.details['indexed']}, sharedClassicClient=true');
    print('X12 browse totals: ${jsonEncode(browseTotals)}');

    final prefs = await SharedPreferences.getInstance();
    final observable = jsonEncode({
      'preferences': {for (final k in prefs.getKeys()) k: prefs.get(k)},
      'jobs': [for (final job in await engine.list()) job.toStorageJson()],
      'journal': journal.readAsStringSync(),
      'logs': [for (final row in DebugLogService().logEntries) row.message],
      'sources': await service.list(),
    });
    for (final c in credentials.values.cast<Map>()) {
      for (final field in ['password', 'access_token']) {
        if (c[field] is String)
          expect(observable.contains(c[field] as String), isFalse);
      }
    }
    for (final secret in vault.values.values.where((s) => s.isNotEmpty)) {
      expect(observable.contains(secret), isFalse);
    }
    expect(
        vault.values[CredentialRef('server_profiles', service.key(jellyfin))],
        isNotEmpty);
    print(
        'X12 secrets: vaultOnly=true, journal/jobs/preferences/logs contain no password/token=true');
  },
      skip: !const bool.fromEnvironment('NIPA_X12_REAL'),
      timeout: const Timeout(Duration(minutes: 4)));
}

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

Future<Object?> _administratorRequest(Map credentials, String path,
    {required String method}) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.openUrl(
        method, Uri.parse('${credentials['base_url']}$path'));
    request.headers.set('Authorization',
        'MediaBrowser Client="X12 approval", Device="Test", DeviceId="X12", Version="1", Token="${credentials['access_token']}"');
    final response = await request.close();
    expect(response.statusCode, 200);
    return jsonDecode(await utf8.decoder.bind(response).join());
  } finally {
    client.close(force: true);
  }
}
