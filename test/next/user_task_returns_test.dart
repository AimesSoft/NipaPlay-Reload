import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/accounts/service.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/tasks/user_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';

const _secret = 'user-task-secret-never-in-facts';
const _account = 'user-task-account-name';

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

/// A download.delete that reports which files it removed, like the real one.
final class _Delete extends Action<_Json, _Json> implements Capability {
  @override
  List<Action> get actions => [this, _Read()];
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'download.delete',
      title: 'Delete',
      description: 'Delete files',
      effect: Effect.destructive,
      input: ObjectSchema({'jobId': StringSchema()}, required: ['jobId']),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_Json({
        'job': {'jobId': 'download'},
        'deletedFiles': [
          {'index': 0, 'path': '/fixture/a.mkv'}
        ]
      }));
}

final class _Read extends Action<_Json, _Json> {
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'download.read',
      title: 'Manifest',
      description: '',
      effect: Effect.read,
      input: ObjectSchema({'jobId': StringSchema()}, required: ['jobId']),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_Json({
        'job': {'jobId': 'download'},
        'task': {
          'infoHash': 'synthetic',
          'outputDirectory': '/fixture',
          'files': [
            {
              'path': '/fixture/a.mkv',
              'local': true,
              'expectedSize': 4,
              'included': true
            }
          ]
        }
      }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late HarnessLocation location;

  Future<void> open(List<JobExecutor> executors) async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('user-task-returns-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine =
        TaskEngine(store: store, ownerDeviceId: 'fixture', executors: executors);
    await engine.start();
    followups = Followups(store.database, engine, location);
  }

  tearDown(() async {
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  List<JsonMap> userRows(List<JsonMap> rows) =>
      rows.where((r) => r['automatic'] == 'userTask').toList();
  JsonMap factOf(JsonMap row) =>
      ((row['trigger'] as Map)['facts'] as List).single as JsonMap;
  dynamic dataOf(JsonMap fact) => fact['data'];

  group('task states', () {
    late FakeExecutor login, deletion, sourceLogin;
    setUp(() async {
      login = FakeExecutor(type: 'accounts.login');
      deletion = FakeExecutor(type: 'disk_deletion');
      sourceLogin = FakeExecutor(type: 'media.sources.login');
      await open([login, deletion, sourceLogin]);
    });
    Future<Job> submit(String type, {bool conversation = true}) =>
        engine.submit(type: type, title: type, input: {
          'provider': 'dandanplay',
          'method': 'window',
          'username': _account,
          'action': 'download.delete',
          if (conversation)
            'returnTo': {
              'threadId': 'original',
              'repository': root.path,
              'origin': 'harness_cli:chat:fixture',
              'invocationId': 'ask'
            }
        });

    test('a login that succeeded, failed or was closed comes back once',
        () async {
      final job = await submit('accounts.login');
      final context = await login.entered.future;
      await followups.sweep();
      // Nothing is news while the user has not answered.
      expect(userRows(await followups.list()), isEmpty);
      await context.succeed(verified(details: {
        'provider': 'dandanplay',
        'loggedIn': true,
        'username': _account,
        'method': 'window'
      }));
      await followups.sweep();
      await followups.sweep();
      final rows = userRows(await followups.list());
      expect(rows, hasLength(1));
      expect(rows.single['state'], 'ready');
      expect(rows.single['threadId'], 'original');
      expect(rows.single['instruction'], contains('需要用户本人完成'));
      final fact = factOf(rows.single);
      expect(fact['event'], 'task.terminal');
      expect(fact['objectId'], job.jobId);
      final data = fact['data'] as Map;
      expect(data['type'], 'accounts.login');
      expect(data['state'], 'succeeded');
      expect(data['receipt']['details']['provider'], 'dandanplay');
      expect(data['receipt']['details']['loggedIn'], true);
      expect(data['receipt']['details']['method'], 'window');
      expect(data['receipt']['details'].containsKey('username'), isFalse);
      expect(jsonEncode(rows), isNot(contains(_account)));
    });

    test('a media source login the user finished comes back once', () async {
      final job = await submit('media.sources.login');
      final context = await sourceLogin.entered.future;
      await context.succeed(verified(details: {
        'sourceId': 'smb:nas',
        'connected': true,
        'username': _account
      }));
      await followups.sweep();
      await followups.sweep();
      final rows = userRows(await followups.list());
      expect(rows, hasLength(1));
      expect(rows.single['instruction'], contains('媒体来源'));
      final data = factOf(rows.single)['data'] as Map;
      expect(factOf(rows.single)['objectId'], job.jobId);
      expect(data['type'], 'media.sources.login');
      expect(data['state'], 'succeeded');
      expect(jsonEncode(rows), isNot(contains(_account)));
    });

    test('a failed login says how it ended, without the message or secrets',
        () async {
      final failed = await submit('accounts.login');
      final context = await login.entered.future;
      await context.fail(
          const Failure(FailureCode.unavailable, 'rejected for $_secret'),
          JobReceipt(
              verification: VerificationLevel.acknowledged,
              details: {'provider': 'dandanplay', 'loggedIn': false}));
      await followups.sweep();
      var rows = userRows(await followups.list());
      expect(dataOf(factOf(rows.single))['state'], 'failed');
      expect(dataOf(factOf(rows.single))['errorCode'], 'unavailable');
      expect(dataOf(factOf(rows.single))['receipt']['details']['loggedIn'],
          false);
      expect(jsonEncode(rows), isNot(contains(_secret)));
      expect(rows.single['condition'], {'userTaskJobId': failed.jobId});
    });

    test('a cancelled login comes back too', () async {
      final job = await submit('accounts.login');
      final context = await login.entered.future;
      await engine.cancel(job.jobId);
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.acknowledged,
          details: {'provider': 'dandanplay', 'loggedIn': false}));
      await followups.sweep();
      final rows = userRows(await followups.list());
      expect(rows, hasLength(1));
      expect(dataOf(factOf(rows.single))['state'], 'cancelled');
    });

    test('a deletion that was approved lists what was deleted', () async {
      await submit('disk_deletion');
      final context = await deletion.entered.future;
      await context.succeed(verified(details: {
        'action': 'download.delete',
        'result': {
          'deletedFiles': [
            {'index': 0, 'path': '/fixture/a.mkv'}
          ]
        }
      }));
      await followups.sweep();
      final data = factOf(userRows(await followups.list()).single)['data'] as Map;
      expect(data['state'], 'succeeded');
      expect(data['deleted'], true);
      expect(data['deletedFiles'], [
        {'index': 0, 'path': '/fixture/a.mkv'}
      ]);
    });

    test('a deletion that was refused says nothing was deleted', () async {
      await submit('disk_deletion');
      final context = await deletion.entered.future;
      await context.fail(
          const Failure(FailureCode.conflict, '用户没有同意删除'),
          JobReceipt(
              verification: VerificationLevel.verified,
              details: {'deleted': false, 'reason': 'user_declined'}));
      await followups.sweep();
      await followups.sweep();
      final rows = userRows(await followups.list());
      expect(rows, hasLength(1));
      final data = dataOf(factOf(rows.single)) as Map;
      expect(data['state'], 'failed');
      expect(data['deleted'], false);
      expect(data['deletedFiles'], isEmpty);
      expect(data['receipt']['details']['reason'], 'user_declined');
    });

    test('a followup the conversation registered on the task is the only one',
        () async {
      final job = await submit('accounts.login');
      final context = await login.entered.future;
      await followups.register({
        'when': {'jobId': job.jobId},
        'threadId': 'original',
        'instruction': '登好之后接着做'
      }, Invocation(origin: 'harness_cli'));
      await context.succeed(verified(details: {
        'provider': 'dandanplay',
        'loggedIn': true
      }));
      await followups.sweep();
      await followups.sweep();
      final rows = await followups.list();
      expect(userRows(rows).single['state'], 'cancelled');
      final own = rows.where((r) => r['automatic'] == null).single;
      expect(own['state'], isNot('cancelled'));
      expect((own['trigger'] as Map)['jobId'], job.jobId);
    });

    test('a followup registered after the task ended still owns it', () async {
      final job = await submit('disk_deletion');
      final context = await deletion.entered.future;
      await context.fail(
          const Failure(FailureCode.conflict, '用户没有同意删除'),
          JobReceipt(
              verification: VerificationLevel.verified,
              details: {'deleted': false, 'reason': 'user_declined'}));
      await followups.sweep();
      expect(userRows(await followups.list()).single['state'], 'ready');
      await followups.register({
        'when': {'jobId': job.jobId},
        'threadId': 'original',
        'instruction': '看结果'
      }, Invocation(origin: 'harness_cli'));
      await followups.sweep();
      expect(userRows(await followups.list()).single['state'], 'cancelled');
    });

    test('a task nobody in a conversation asked for returns nowhere',
        () async {
      await submit('accounts.login', conversation: false);
      final context = await login.entered.future;
      await context.succeed(verified());
      await submit('disk_deletion', conversation: false);
      final other = await deletion.entered.future;
      await other.succeed(verified());
      await followups.sweep();
      expect(await followups.list(), isEmpty);
    });
  });

  group('wired to the real services', () {
    late AccountsService accounts;
    late DiskDeletion guard;
    late Harness api;
    late bool approve;
    late Job helper;
    late Invocation chat;

    setUp(() async {
      accounts = AccountsService();
      approve = true;
      guard = DiskDeletion(prompt: (_, __, ___) async => approve);
      await open([
        ...accountExecutors(accounts),
        guard,
        FakeExecutor(type: 'agent.helper')
      ]);
      accounts.attach(engine);
      guard.engine = engine;
      accounts.returnTarget = followups.downloadReturnTarget;
      guard.returnTarget = followups.downloadReturnTarget;
      api = Harness(guard.protect([_Delete()]));
      helper = await engine.submit(
          type: 'agent.helper',
          title: '帮手',
          input: {
            'parentThreadId': 'parent',
            'threadId': 'native-child',
            'repository': root.path
          });
      chat = Invocation(origin: 'harness_cli:helper:${helper.jobId}');
    });
    tearDown(() => accounts.close());

    Future<String> requestDeletion(Invocation who) async {
      final preview = await api.invokeJson('download.delete',
          {'jobId': 'download'}, who);
      final option = (preview as NeedsDecision).decision.options.single.call;
      final requested = await api.invokeJson(option.actionId, option.input, who);
      return ((requested as Completed).value.toJson()['job'] as JsonMap)['jobId']
          as String;
    }

    Future<Job> ended(String id) async {
      var job = await engine.get(id);
      while (!job.state.isTerminal) {
        job = await engine.wait(id, afterRevision: job.revision);
      }
      return job;
    }

    test('approved and declined deletions each return to the asking thread',
        () async {
      final first = await requestDeletion(chat);
      await ended(first);
      approve = false;
      final second = await requestDeletion(chat);
      await ended(second);
      await followups.sweep();
      await followups.sweep();
      final rows = userRows(await followups.list());
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['threadId'] == 'parent'), isTrue);
      final byJob = {for (final r in rows) factOf(r)['objectId']: factOf(r)};
      expect(dataOf(byJob[first]!)['deleted'], true);
      expect(dataOf(byJob[first]!)['deletedFiles'], [
        {'index': 0, 'path': '/fixture/a.mkv'}
      ]);
      expect(dataOf(byJob[second]!)['deleted'], false);
      expect(dataOf(byJob[second]!)['receipt']['details']['reason'],
          'user_declined');
    });

    test('a deletion asked outside any conversation returns nowhere', () async {
      await ended(await requestDeletion(Invocation(origin: 'ui')));
      await followups.sweep();
      expect(userRows(await followups.list()), isEmpty);
    });

    test('a login window the user closes returns to the asking thread',
        () async {
      accounts.requestLogin = (_, __) async => null;
      final result = await accounts.login({'provider': 'dandanplay'}, chat);
      final job = await ended(result['jobId'] as String);
      expect(job.state, JobState.cancelled);
      await followups.sweep();
      final row = userRows(await followups.list()).single;
      expect(row['threadId'], 'parent');
      final data = factOf(row)['data'] as Map;
      expect(data['type'], 'accounts.login');
      expect(data['state'], 'cancelled');
    });

    test('a login whose secret the user gave in conversation is not returned',
        () async {
      accounts.requestLogin = (_, __) async => null;
      var asked = 0;
      final other = AccountsService()
        ..returnTarget = (invocation) async {
          asked++;
          return followups.downloadReturnTarget(invocation);
        };
      final lone = TaskEngine(
          store: MemoryJobStore(),
          ownerDeviceId: 'lone',
          executors: accountExecutors(other));
      other.attach(lone);
      addTearDown(() async {
        await lone.close();
        await other.close();
      });
      final result = await other.login({
        'provider': 'dandanplay',
        'username': _account,
        'password': _secret
      }, chat);
      final job = await lone.get(result['jobId'] as String);
      expect(job.input.containsKey('returnTo'), isFalse);
      expect(asked, 0);
    });
  });
}
