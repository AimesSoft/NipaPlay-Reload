import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/accounts/capability.dart';
import 'package:nipaplay/next/accounts/service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';

class _Direct extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late SqliteJobStore jobs;
  late AccountsService service;
  late TaskEngine engine;
  late Harness harness;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nipa-x14-accounts-');
    StorageService.debugAppStorageDirectoryOverride = root;
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    service = AccountsService();
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'x14',
        executors: accountExecutors(service));
    service.attach(engine);
    harness = Harness([AccountsCapability(service), TaskCapability(engine)],
        observers: [JsonlJournal(File('${root.path}/journal.jsonl'))]);
  });
  tearDown(() async {
    await engine.close();
    await service.close();
    await jobs.close();
    StorageService.debugAppStorageDirectoryOverride = null;
    await root.delete(recursive: true);
  });
  Future<JsonMap> call(String id, JsonMap input) async {
    final outcome =
        await harness.invokeJson(id, input, Invocation(origin: 'x14'));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    return (outcome as Completed).value.toJson();
  }

  Future<Job> terminal(String id) async {
    var job = await engine.get(id);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!job.state.isTerminal && DateTime.now().isBefore(deadline)) {
      job = await engine.wait(id,
          afterRevision: job.revision, timeout: const Duration(seconds: 1));
    }
    expect(job.state.isTerminal, true);
    return job;
  }

  test(
      'login restart cannot replay a conversation secret; job and journal preserve no secret',
      () async {
    const secret = 'x14-conversation-secret-never-persist';
    final result = await call('accounts.login',
        {'provider': 'dandanplay', 'username': 'fixture', 'password': secret});
    final stored = await engine.get(result['jobId'] as String);
    expect(jsonEncode(stored.toStorageJson()).contains(secret), false);
    expect(
        File('${root.path}/journal.jsonl').readAsStringSync().contains(secret),
        false);
    await service.close();
    final recovered = AccountsService();
    recovered.attach(engine);
    final replayEngine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'x14',
        executors: accountExecutors(recovered));
    recovered.engine = replayEngine;
    await replayEngine.start();
    var job = await replayEngine.get(stored.jobId);
    while (!job.state.isTerminal) {
      job = await replayEngine.wait(job.jobId,
          afterRevision: job.revision, timeout: const Duration(seconds: 1));
    }
    expect(job.state, JobState.failed);
    expect(job.error!.message, contains('discarded at restart'));
    expect(jsonEncode(job.toStorageJson()).contains(secret), false);
    await replayEngine.close();
    await recovered.close();
  });

  test(
      'Bangumi Classic loopback preserves omitted fields and reports individual failures',
      () async {
    final oldStore = CredentialStore.instance,
        oldOverrides = HttpOverrides.current;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    HttpOverrides.global = _Direct();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final collection = <String, dynamic>{};
    final listRequests = <Uri>[];
    final episodeStates = <String, int>{};
    server.listen((request) async {
      final path = request.uri.path;
      Object? data;
      if (path == '/v0/me') {
        data = {'id': 14, 'username': 'x14-fixture'};
      } else if (path == '/v0/users/x14-fixture/collections') {
        listRequests.add(request.uri);
        final offset = int.parse(request.uri.queryParameters['offset']!);
        final limit = int.parse(request.uri.queryParameters['limit']!);
        data = {'total': 3, 'data': [
          {'subject_id': 10, 'type': 3, 'rate': 8},
          {'subject_id': 20, 'type': 2, 'rate': 0},
          {'subject_id': 30, 'type': 3, 'rate': 9},
        ].skip(offset).take(limit).toList()};
      } else if (path.endsWith('/999')) {
        request.response.statusCode = 503;
        data = {'description': 'fixture unavailable'};
      } else if (path.endsWith('/episodes/100')) {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        episodeStates['100'] = body['type'] as int;
        data = {};
      } else if (path.endsWith('/episodes')) {
        data = {
          'data': [
            {
              'episode': {'id': 100},
              'type': episodeStates['100'] ?? 0
            }
          ]
        };
      } else if (request.method == 'POST') {
        collection.addAll(Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map));
        data = {};
      } else if (collection.isEmpty) {
        request.response.statusCode = 404;
        data = {};
      } else {
        data = collection;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues(
        {'bangumi_server_url': 'http://127.0.0.1:${server.port}'});
    addTearDown(() async {
      await BangumiApiService.clearAccessToken();
      await server.close(force: true);
      CredentialStore.instance = oldStore;
      HttpOverrides.global = oldOverrides;
    });
    await engine.start();
    final login = await call('accounts.login',
        {'provider': 'bangumi', 'accessToken': 'fixture-bangumi-secret'});
    final logged = await terminal(login['jobId'] as String);
    expect(logged.state, JobState.succeeded,
        reason: jsonEncode(logged.toJson()));
    final page = await call('accounts.collections.list',
      {'provider': 'bangumi', 'statuses': ['doing'], 'limit': 2});
    expect(page['items'], [{'workId': 10, 'status': 'doing', 'rating': 8}]);
    final next = await call('accounts.collections.list',
      {'provider': 'bangumi', 'statuses': ['doing'], 'limit': 2, 'cursor': page['nextCursor']});
    expect(next['items'], [{'workId': 30, 'status': 'doing', 'rating': 9}]);
    expect(next['nextCursor'], isNull);
    expect(listRequests.length, 2);
    expect(listRequests.every((uri) => uri.queryParameters['subject_type'] == '2'), true);
    await call('accounts.collections.update', {
      'provider': 'bangumi',
      'items': [
        {
          'workId': 10,
          'status': 'doing',
          'rating': 8,
          'comment': 'preserved',
          'private': true
        }
      ]
    });
    final changed = await call('accounts.collections.update', {
      'provider': 'bangumi',
      'items': [
        {'workId': 10, 'rating': 9},
        {'workId': 999, 'rating': 7}
      ]
    });
    expect((changed['results'] as List)[1]['status'], 'failed');
    expect(collection,
        {'type': 3, 'rate': 9, 'comment': 'preserved', 'private': true});
    final read = await call('accounts.collections.get', {
      'provider': 'bangumi',
      'workIds': [10]
    });
    expect((read['results'] as List)[0]['result']['collection'], collection);
    await call('accounts.episodes.update', {
      'provider': 'bangumi',
      'items': [
        {'episodeId': 100, 'state': 2}
      ]
    });
    expect(episodeStates['100'], 2);
    final episodes = await call(
        'accounts.episodes.get', {'provider': 'bangumi', 'workId': 10});
    expect((episodes['data'] as Map)['data'][0]['type'], 2);
    expect((await call('accounts.logout', {'provider': 'bangumi'}))['loggedIn'],
        false);
    final stored =
        jsonEncode((await jobs.list()).map((j) => j.toStorageJson()).toList());
    expect(stored.contains('fixture-bangumi-secret'), false);
    expect(
        File('${root.path}/journal.jsonl')
            .readAsStringSync()
            .contains('fixture-bangumi-secret'),
        false);
  });
}
