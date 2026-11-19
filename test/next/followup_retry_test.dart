import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';

/// #1122: the reminder of a failed background followup can deliver it again
/// now, or stop it, and opens its conversation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late HarnessLocation location;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-followup-retry-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [FakeExecutor()]);
    await engine.start();
    followups = Followups(store.database, engine, location);
  });
  tearDown(() async {
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  final invocation = Invocation(origin: 'gui', id: 'retry-test');

  Future<JsonMap> registered() async {
    final job =
        await engine.submit(type: 'test', title: 'Helper finished', input: {});
    return followups.register({
      'when': {'jobId': job.jobId},
      'instruction': 'Tell the person what the helper found',
      'title': '帮手找到的番',
      'threadId': 'thread-main',
    }, Invocation(origin: 'harness_cli', id: 'register'));
  }

  /// As the dispatcher leaves a followup after the model provider failed.
  Future<void> put(String id, String state, Map<String, Object?> fields) async {
    final rows =
        await store.database.query('followups', where: 'id=?', whereArgs: [id]);
    final row = jsonDecode(rows.single['snapshot'] as String) as Map;
    row
      ..addAll(fields)
      ..['state'] = state;
    await store.database.update(
        'followups', {'state': state, 'snapshot': jsonEncode(row)},
        where: 'id=?', whereArgs: [id]);
  }

  test('one waiting for its automatic delivery is delivered again now',
      () async {
    final id = (await registered())['id'] as String;
    await put(id, 'ready', {
      'retryAt': DateTime.now().toUtc().add(const Duration(minutes: 8)).toIso8601String(),
      'attempts': 2,
      'failedTurns': ['turn-1', 'turn-2'],
      'turnId': null,
    });
    final retried = await followups.retry(id, invocation);
    expect(retried['state'], 'ready');
    expect(retried.containsKey('retryAt'), isFalse);
    expect(retried['attempts'], 2, reason: 'a manual delivery is not counted');
    expect(retried['failedTurns'], ['turn-1', 'turn-2']);
    final events = await store.database.query('followup_events',
        where: 'followup_id=? AND origin=?', whereArgs: [id, 'gui']);
    expect(events, isNotEmpty);
  });

  test('one that failed for good is delivered once more', () async {
    final id = (await registered())['id'] as String;
    await put(id, 'execution_failed', {
      'attempts': 5,
      'turnId': 'turn-6',
      'turnStatus': 'failed',
    });
    final retried = await followups.retry(id, invocation);
    expect(retried['state'], 'ready');
    expect(retried['turnId'], isNull);
    expect(retried['turnStatus'], isNull);
  });

  test('others are refused: still waiting, delivered elsewhere', () async {
    final id = (await registered())['id'] as String;
    await expectLater(followups.retry(id, invocation),
        throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.conflict)));
    await put(id, 'execution_failed', {'remoteDeviceId': 'mac'});
    await expectLater(followups.retry(id, invocation),
        throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.conflict)));
  });

  test('stopping one waiting for its automatic delivery cancels it', () async {
    final id = (await registered())['id'] as String;
    await put(id, 'ready', {
      'retryAt': DateTime.now().toUtc().add(const Duration(minutes: 2)).toIso8601String()
    });
    expect((await followups.cancel(id, invocation))['state'], 'cancelled');
  });

  test('a reminder about a followup opens its conversation', () async {
    final followup = await registered();
    final notice = await followups.publishInbox({
      'requestId': 'followup-${followup['id']}-retrying',
      'title': '「帮手找到的番」暂时没能完成',
      'body': 'model returned no content',
      'severity': 'error',
      'followupId': followup['id'],
    }, invocation, question: false);
    expect((notice['target'] as Map)['threadId'], followup['threadId']);
    expect((notice['request'] as Map)['followupId'], followup['id']);
    await expectLater(
        followups.publishInbox({
          'requestId': 'x',
          'title': 't',
          'body': 'b',
          'followupId': 'missing'
        }, invocation, question: false),
        throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.notFound)));
  });
}
