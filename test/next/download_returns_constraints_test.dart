import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late HarnessLocation location;
  late FakeExecutor executor;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('download-returns-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(type: 'download');
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'fixture',
        executors: [executor, FakeExecutor(type: 'agent.helper')]);
    await engine.start();
    followups = Followups(store.database, engine, location);
  });
  tearDown(() async {
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });
  Future<Job> submit({bool conversation = true}) =>
      engine.submit(type: 'download', title: 'CC0 合集', input: {
        'infoHash': 'fixture',
        if (conversation)
          'returnTo': {
            'threadId': 'original',
            'repository': root.path,
            'origin': 'harness_cli:chat:fixture',
            'invocationId': 'download-call'
          }
      });
  JsonMap file(Job job, int index, {bool video = true, bool imported = true}) =>
      {
        'objectId': '${job.jobId}:$index',
        'jobId': job.jobId,
        'index': index,
        'path': '/fixture/$index.mp4',
        'verification': 'verified',
        'isVideo': video,
        'imported': imported,
        'local': true,
        'complete': true,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'media': {
          'fileId': 'file-$index',
          'workIds': [],
          'identificationPending': true
        }
      };

  test(
      'coalesced coverage survives reopen without changing task facts or receipt',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0)]
    });
    await followups.sweep();
    final first = (await followups.list()).single;
    expect(first['threadId'], 'original');
    expect(first['state'], 'ready');
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0), file(job, 1)]
    });
    await followups.sweep();
    await context.succeed(verified(details: {
      'fileIds': ['file-0', 'file-1']
    }));
    await followups.sweep();
    final receipt = (await engine.get(job.jobId)).receipt!.toJson();
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'fixture',
        executors: [FakeExecutor(type: 'download')]);
    await engine.start();
    followups = Followups(store.database, engine, location);
    await followups.sweep();
    await followups.sweep();
    final rows = await followups.list();
    expect(rows, hasLength(1));
    expect(rows.single['id'], first['id']);
    expect(rows.single['downloadObjects'],
        ['${job.jobId}:0', '${job.jobId}:1', 'terminal:${job.jobId}']);
    expect(((rows.single['trigger'] as Map)['facts'] as List), hasLength(3));
    expect((await engine.get(job.jobId)).receipt!.toJson(), receipt);
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('a file event carries its binding, and waits while it is pending',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    final pending = {...file(job, 0), 'binding': {'status': 'pending'}};
    await context.report(checkpoint: {
      'completedFiles': [pending]
    });
    await followups.sweep();
    expect(await followups.list(), isEmpty);
    final bound = {
      ...file(job, 0),
      'binding': {
        'status': 'bound',
        'workId': 'work-1',
        'releaseId': 'release-1',
        'episodeIds': ['episode-1']
      }
    };
    await context.report(checkpoint: {
      'completedFiles': [bound]
    });
    await followups.sweep();
    final facts = ((await followups.list()).single['trigger'] as Map)['facts']
        as List;
    expect(facts, hasLength(1));
    expect(((facts.single['data'] as Map)['file'] as Map)['binding'],
        bound['binding']);
  });

  test('an unresolved stall goes back at once, a passed one never', () async {
    final job = await submit();
    final context = await executor.entered.future;
    final at = DateTime.now().toUtc().toIso8601String();
    await context.report(checkpoint: {
      'stalls': [
        {'index': 0, 'at': at, 'resumedAt': at, 'secondsWithoutProgress': 320},
        {
          'index': 1,
          'at': at,
          'secondsWithoutProgress': 300,
          'connectedPeers': 0,
          'seenPeers': 9,
          'deadPeers': 9,
          'completedBytes': 0,
          'totalBytes': 4
        }
      ]
    });
    await followups.sweep();
    final row = (await followups.list()).single;
    expect(row['threadId'], 'original');
    final fact = ((row['trigger'] as Map)['facts'] as List).single as Map;
    expect(fact['event'], 'download.stalled');
    expect(fact['objectId'], 'stalled:${job.jobId}:1');
    expect((fact['data'] as Map)['seenPeers'], 9);
    expect((fact['data'] as Map)['title'], 'CC0 合集');
    expect((fact['data'] as Map).containsKey('index'), false);
    expect(
        DateTime.parse(row['deliverAfter'] as String)
            .isAfter(DateTime.now().toUtc()),
        false);
    await followups.sweep();
    expect(
        (((await followups.list()).single['trigger'] as Map)['facts'] as List),
        hasLength(1));
  });

  test(
      'manual file and terminal returns own facts, including late registration',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    await followups.register({
      'when': {
        'event': 'download.file_completed',
        'objectId': '${job.jobId}:0'
      },
      'threadId': 'original',
      'instruction': '用户自己的说明'
    }, Invocation(origin: 'harness_cli'));
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0), file(job, 1)]
    });
    await followups.sweep();
    var automatic = (await followups.list())
        .where((r) => r['automatic'] == 'download')
        .single;
    expect(((automatic['trigger'] as Map)['facts'] as List).single['objectId'],
        '${job.jobId}:1');
    await followups.register({
      'when': {'jobId': job.jobId},
      'threadId': 'original',
      'instruction': '终态说明'
    }, Invocation(origin: 'harness_cli'));
    await context.fail(
        const Failure(FailureCode.unavailable, 'peer error'),
        JobReceipt(
            verification: VerificationLevel.unverified,
            details: {'reason': 'peer error'}));
    await followups.sweep();
    automatic = (await followups.list())
        .where((r) => r['automatic'] == 'download')
        .single;
    // The end's followup looks at the whole download, so file 1, still
    // waiting in the batch, goes with it.
    expect(automatic['state'], 'cancelled');
    expect(((automatic['trigger'] as Map)['facts'] as List), isEmpty);
    expect(automatic['downloadObjects'], contains('terminal:${job.jobId}'));
    await followups.sweep();
    expect((await followups.list()).where((r) => r['automatic'] == 'download'),
        hasLength(1));
  });

  test('files batched when the end arrives go with the end\'s own followup',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    await followups.register({
      'when': {'jobId': job.jobId},
      'threadId': 'original',
      'instruction': '下完检查每集'
    }, Invocation(origin: 'harness_cli'));
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0)]
    });
    await followups.sweep();
    final rows = await followups.list();
    final first = rows.where((r) => r['automatic'] == 'download').single;
    // The first file is news of its own while the download runs.
    expect(first['state'], 'ready');
    expect((first['trigger'] as Map)['facts'], hasLength(1));
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0), file(job, 1), file(job, 2)]
    });
    await context.succeed(verified(details: {
      'fileIds': ['file-0', 'file-1', 'file-2']
    }));
    await followups.sweep();
    final after = await followups.list();
    expect(after.where((r) => r['automatic'] == null).single['state'],
        isNot('cancelled'));
    final automatic = after.where((r) => r['automatic'] == 'download');
    expect(automatic.every((r) => r['state'] == 'cancelled'), isTrue);
  });

  test('scripts and nonvideo or unregistered files produce no automatic return',
      () async {
    for (final origin in [
      'harness_cli',
      'hook:test',
      'ui',
      'harness_cli:chat:stale'
    ]) {
      expect(await followups.downloadReturnTarget(Invocation(origin: origin)),
          isNull);
    }
    final job = await submit(conversation: false);
    final context = await executor.entered.future;
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0)]
    });
    await context.succeed(verified());
    await followups.sweep();
    expect(await followups.list(), isEmpty);
  });

  test('failure is delivered once with its actual unverified outcome',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    await context.report(checkpoint: {
      'completedFiles': [
        file(job, 0, video: false),
        file(job, 1, imported: false)
      ]
    });
    await followups.sweep();
    expect(await followups.list(), isEmpty);
    await context.fail(
        const Failure(FailureCode.unavailable, 'broken peer'),
        JobReceipt(
            verification: VerificationLevel.unverified,
            details: {'reason': 'broken peer'}));
    await followups.sweep();
    await followups.sweep();
    final facts =
        ((await followups.list()).single['trigger'] as Map)['facts'] as List;
    expect(facts, hasLength(1));
    expect(facts.single['data']['state'], 'failed');
    expect(facts.single['data']['receipt']['verification'], 'unverified');
  });

  test('what the conversation read for itself is not sent back to it',
      () async {
    final helper = await engine.submit(
        type: 'agent.helper',
        title: '下载帮手',
        input: {
          'parentThreadId': 'original',
          'threadId': 'native-child',
          'repository': root.path
        });
    final job = await submit();
    final context = await executor.entered.future;
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0)]
    });
    await followups.sweep();
    // The conversation was busy; meanwhile it read the download itself.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await followups.noteDownloadRead(job.jobId,
        Invocation(origin: 'harness_cli:helper:${helper.jobId}'));
    await followups.sweep();
    var automatic = (await followups.list())
        .where((r) => r['automatic'] == 'download')
        .single;
    expect(automatic['state'], 'cancelled');
    // A file that finishes after the read is news again.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0), file(job, 1)]
    });
    await followups.sweep();
    automatic = (await followups.list())
        .where((r) => r['automatic'] == 'download' && r['state'] != 'cancelled')
        .single;
    expect(((automatic['trigger'] as Map)['facts'] as List)
        .map((f) => (f as Map)['objectId']), ['${job.jobId}:1']);
  });

  test('helper provenance returns to its recorded parent', () async {
    final helper = await engine.submit(
        type: 'agent.helper',
        title: '下载帮手',
        input: {
          'parentThreadId': 'parent',
          'threadId': 'native-child',
          'repository': root.path
        });
    for (final origin in [
      'harness_cli:helper:${helper.jobId}',
      'codex_native:native-child'
    ]) {
      final target =
          await followups.downloadReturnTarget(Invocation(origin: origin));
      expect(target!['threadId'], 'parent');
      expect(target['repository'], root.path);
      expect(target['origin'], origin);
    }
  });

  test('a late broad one-shot takes its actual occurrence', () async {
    final job = await submit();
    final context = await executor.entered.future;
    final first = file(job, 0);
    await context.report(checkpoint: {
      'completedFiles': [first]
    });
    await followups.sweep();
    await followups.register({
      'when': {'event': 'download.file_completed'},
      'threadId': 'original',
      'instruction': '接下一份事实'
    }, Invocation(origin: 'harness_cli'));
    final foreign = file(job, 99);
    foreign['objectId'] = 'another-job:0';
    await followups.hookEvent('download.file_completed', 'another-job:0', {
      'event': 'download.file_completed',
      'objectId': 'another-job:0',
      'occurredAt': foreign['completedAt'],
      'data': {'file': foreign}
    });
    await context.report(checkpoint: {
      'completedFiles': [first, file(job, 1)]
    });
    await followups.sweep();
    final rows = await followups.list();
    final automatic = rows.where((r) => r['automatic'] == 'download').single;
    expect((automatic['trigger'] as Map)['facts'], hasLength(2));
    final manual = rows.where((r) => r['automatic'] == null).single;
    expect((manual['trigger'] as Map)['objectId'], 'another-job:0');
  });
}
