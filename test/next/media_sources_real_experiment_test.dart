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
    for (final name in ['webdav']) {
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

    final browseTotals = <String, Object?>{};

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
