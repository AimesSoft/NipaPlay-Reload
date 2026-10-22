import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/media_sources/source_facts.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/address_probe.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
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
  final previousHttp = HttpOverrides.current;

  setUp(() async {
    HttpOverrides.global = _DirectHttp();
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
    root = await Directory.systemTemp.createTemp('nipa-source-facts-');
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    store = IdentityStore(jobs.database, 'test-device');
    sources = MediaSourcesService(store);
    await sources.initialize();
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'test-device',
        executors: mediaSourcesExecutors(sources));
    sources.engine = engine;
    harness = Harness([MediaSourcesCapability(sources), TaskCapability(engine)]);
    await engine.start();
  });
  tearDown(() async {
    await engine.close();
    await sources.close();
    await store.closeEvents();
    await jobs.database.close();
    await root.delete(recursive: true);
    CredentialStore.instance = previous;
    HttpOverrides.global = previousHttp;
  });

  Future<JsonMap> call(String name, JsonMap input) async {
    final outcome =
        await harness.invokeJson(name, input, Invocation(origin: 'test'));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(name)!.spec.output.validate(result), isEmpty);
    return result;
  }

  Future<Map<String, Map>> listed() async => {
        for (final row in (await call('media.sources.list', {}))['sources']
            as List)
          (row as Map)['sourceId'] as String: row
      };

  Future<int> closedPort() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    return port;
  }

  test('an address never probed is unknown, not unreachable', () async {
    final id = ((await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Fresh',
      'url': 'http://192.168.1.2/dav',
      'wanUrl': 'https://nas.example.com/dav'
    }))['source'] as Map)['sourceId'] as String;
    final row = (await listed())[id]!;
    final addresses = (row['addresses'] as List).cast<Map>();
    expect(addresses.map((a) => a['role']), ['lan', 'wan']);
    for (final address in addresses) {
      expect(address['reachability'], 'unknown');
      expect(address['lastAttemptAt'], isNull);
      expect(address['errorCode'], isNull);
    }
    expect(row['sync'], containsPair('result', null));
    expect(row['lastError'], isNull);
    expect(row['credential'], containsPair('state', 'none'));
  });

  test('each address records its own attempt, with code and latency, across restarts',
      () async {
    final refused = await closedPort();
    final denying = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => denying.close(force: true));
    denying.listen((request) async {
      request.response.statusCode = 401;
      request.response.headers.set('www-authenticate', 'Basic realm="x"');
      await request.response.close();
    });
    final id = ((await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Dual',
      'url': 'http://127.0.0.1:$refused/dav',
      'wanUrl': 'http://127.0.0.1:${denying.port}/dav',
      'username': 'viewer'
    }))['source'] as Map)['sourceId'] as String;
    final connection = sources.webdav.getConnectionByIdOrName(sources.key(id))!;
    expect(await sources.webdav.testConnection(connection), false);
    await sources.facts.flush();

    var row = (await listed())[id]!;
    var addresses = {
      for (final a in (row['addresses'] as List).cast<Map>())
        a['role'] as String: a
    };
    expect(addresses['lan']!['reachability'], 'unreachable');
    expect(addresses['lan']!['errorCode'], 'connection_refused');
    expect(addresses['wan']!['reachability'], 'unreachable');
    expect(addresses['wan']!['errorCode'], 'auth_failed');
    for (final a in addresses.values) {
      expect(DateTime.parse(a['lastAttemptAt'] as String).isUtc, true);
      expect(a['lastFailureAt'], a['lastAttemptAt']);
      expect(a['lastSuccessAt'], isNull);
      expect(a['latencyMs'], isA<int>());
    }

    // A new service over the same preferences still reads them.
    final again = await SourceFacts().read(id);
    expect(((again['addresses'] as Map)['lan'] as Map)['errorCode'],
        'connection_refused');

    // A later success keeps the earlier failure time and clears the code.
    AddressProbes.report(AddressProbe(
        sourceId: id,
        role: 'lan',
        address: 'http://127.0.0.1:$refused/dav',
        at: DateTime.now().toUtc(),
        reachable: true,
        latencyMs: 7));
    await sources.facts.flush();
    row = (await listed())[id]!;
    final lan = (row['addresses'] as List).cast<Map>().first;
    expect(lan['reachability'], 'reachable');
    expect(lan['errorCode'], isNull);
    expect(lan['latencyMs'], 7);
    expect(lan['lastSuccessAt'], isNotNull);
    expect(lan['lastFailureAt'], isNotNull);
  });

  test('probes of a configuration that is not saved leave nothing behind',
      () async {
    AddressProbes.report(AddressProbe(
        sourceId: 'webdav:ghost',
        role: 'lan',
        address: 'http://ghost.example',
        at: DateTime.now().toUtc(),
        reachable: false,
        latencyMs: 1,
        errorCode: 'timeout'));
    await sources.facts.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.contains('ghost')), isEmpty);
  });

  test('a failed check keeps its time and code, and a rejected login is told apart from none',
      () async {
    final denying = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => denying.close(force: true));
    denying.listen((request) async {
      request.response.statusCode = 401;
      await request.response.close();
    });
    final id = ((await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Locked',
      'url': 'http://127.0.0.1:${denying.port}/dav',
      'username': 'viewer'
    }))['source'] as Map)['sourceId'] as String;
    // A login is required by the name but nothing is saved.
    expect(((await listed())[id]!['credential'] as Map)['state'], 'missing');

    final connection = sources.webdav.getConnectionByIdOrName(sources.key(id))!;
    const ref = CredentialRef('webdav_connections', 'locked-secret');
    vault.values[ref] = 'secret-value';
    await sources.webdav.configureConnection(connection.copyWith(
        password: 'secret-value', credentialOrigin: connection.credentialAuthority));
    expect(((await listed())[id]!['credential'] as Map)['state'], 'saved');

    final outcome = await harness.invokeJson(
        'media.sources.check', {'sourceId': id}, Invocation(origin: 'test'));
    expect(outcome, isA<Failed>());
    await sources.facts.flush();
    final row = (await listed())[id]!;
    final check = row['lastCheck'] as Map;
    expect(check['result'], 'failed');
    expect(check['errorCode'], 'auth_failed');
    expect(check['latencyMs'], isA<int>());
    expect((row['lastError'] as Map)['code'], 'auth_failed');
    expect((row['lastError'] as Map)['at'], check['at']);
    final credential = row['credential'] as Map;
    expect(credential['state'], 'rejected');
    expect(credential['lastRejectedAt'], check['at']);
    expect(credential['lastRejectedCode'], 'auth_failed');
    expect(credential['lastVerifiedAt'], isNull);
    // The secret appears nowhere in what is reported.
    expect(jsonEncode(row), isNot(contains('secret-value')));
  });

  test('a failed sync is recorded with its time, code and job; a restart leaves running as interrupted',
      () async {
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => fixture.close(force: true));
    fixture.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'Id': 'away-server'}));
      await request.response.close();
    });
    final id = ((await call('media.sources.add', {
      'type': 'jellyfin',
      'name': 'Away',
      'url': 'http://127.0.0.1:${fixture.port}',
      'username': 'u'
    }))['source'] as Map)['sourceId'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('next.source.$id.libraries', ['lib']);
    final job = (await call('media.sources.sync', {'sourceId': id}))['jobId']
        as String;
    final done = await _terminal(engine, job);
    expect(done.state, JobState.failed);
    await sources.facts.flush();
    var sync = (await listed())[id]!['sync'] as Map;
    expect(sync['result'], 'failed');
    expect(sync['jobId'], job);
    expect(sync['errorCode'], 'login_required');
    expect(sync['finishedAt'], isNotNull);
    expect(sync['lastSuccessAt'], isNull);
    expect(((await listed())[id]!['lastError'] as Map)['code'], sync['errorCode']);

    // A sync left running by a previous process is reported as interrupted.
    await prefs.setString(
        SourceFacts.key(id),
        jsonEncode({
          'sync': {
            'jobId': 'old-job',
            'startedAt': '2026-01-01T00:00:00.000Z',
            'result': 'running'
          }
        }));
    sync = (await listed())[id]!['sync'] as Map;
    expect(sync['result'], 'interrupted');
    expect(sync['startedAt'], '2026-01-01T00:00:00.000Z');
  });

  test('removing a source forgets its facts; changing its address forgets the probes',
      () async {
    final id = ((await call('media.sources.add', {
      'type': 'webdav',
      'name': 'Moving',
      'url': 'http://192.168.1.2/dav'
    }))['source'] as Map)['sourceId'] as String;
    AddressProbes.report(AddressProbe(
        sourceId: id,
        role: 'lan',
        address: 'http://192.168.1.2/dav',
        at: DateTime.now().toUtc(),
        reachable: true,
        latencyMs: 3));
    await sources.facts.flush();
    expect(
        ((await listed())[id]!['addresses'] as List).cast<Map>().single['reachability'],
        'reachable');
    await call('media.sources.update', {'sourceId': id, 'url': 'http://192.168.1.3/dav'});
    expect(
        ((await listed())[id]!['addresses'] as List).cast<Map>().single['reachability'],
        'unknown');
    AddressProbes.report(AddressProbe(
        sourceId: id,
        role: 'lan',
        address: 'http://192.168.1.3/dav',
        at: DateTime.now().toUtc(),
        reachable: true,
        latencyMs: 3));
    await sources.facts.flush();
    await call('media.sources.remove', {'sourceId': id});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SourceFacts.key(id)), isNull);
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
