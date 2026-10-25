import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_hooks.dart';
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
  late HarnessHooks hooks;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('download-stalled-');
    await Directory('${root.path}/hooks').create();
    if (Platform.isWindows) {
      // No shebang and no execute bit: the hook is a Python script by extension.
      await File('${root.path}/hooks/download.stalled.py').writeAsString(
          'import sys\n'
          'open("stalls.jsonl", "ab").write(sys.stdin.buffer.read() + b"\\n")\n');
    } else {
      final program = File('${root.path}/hooks/download.stalled');
      await program.writeAsString(
          '#!/bin/sh\ncat >> stalls.jsonl\necho >> stalls.jsonl\n');
      expect((await Process.run('chmod', ['755', program.path])).exitCode, 0);
    }
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(type: 'download');
    hooks = HarnessHooks();
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'fixture',
        executors: [executor, hooks]);
    hooks.engine = engine;
    hooks.enable(root, File('${root.path}/endpoint.json'));
    await engine.start();
    followups = Followups(store.database, engine, location);
    hooks.observeEvent = followups.hookEvent;
  });
  tearDown(() async {
    await hooks.disable();
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  Future<Job> submit({bool conversation = false}) =>
      engine.submit(type: 'download', title: '没人做种', input: {
        'infoHash': 'abc',
        if (conversation)
          'returnTo': {
            'threadId': 'original',
            'repository': root.path,
            'origin': 'harness_cli:chat:fixture',
            'invocationId': 'download-call'
          }
      });

  JsonMap stall(int index, {String? resumedAt}) => {
        'index': index,
        'at': DateTime.now().toUtc().toIso8601String(),
        'secondsWithoutProgress': 300,
        'completedBytes': 10,
        'totalBytes': 100,
        'connectedPeers': 0,
        'seenPeers': 7,
        'deadPeers': 7,
        if (resumedAt != null) 'resumedAt': resumedAt,
      };

  Future<void> publish(
      JobContext context, Job job, List<JsonMap> stalls) async {
    await context.report(checkpoint: {'stalls': stalls});
    await hooks.taskChanged(await engine.get(job.jobId));
    await hooks.drain();
  }

  Future<List<Job>> hookJobs() async {
    final jobs = await engine.list(type: 'harness.hook');
    for (final job in jobs) {
      await untilState(engine, job.jobId, JobState.succeeded);
    }
    return jobs;
  }

  test('events.describe lists it as a hook and followup event', () {
    expect(HarnessHooks.events, contains('download.stalled'));
  });

  test('a stall runs the hook once; a later stall after new bytes runs again',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    final first = stall(0);
    await publish(context, job, [first]);
    await publish(context, job, [first]);
    var hookRuns = await hookJobs();
    expect(hookRuns, hasLength(1));
    final input = (await engine.get(hookRuns.single.jobId)).input;
    expect(input['event'], 'download.stalled');
    expect(input['objectId'], 'stalled:${job.jobId}:0');
    expect(input['occurredAt'], first['at']);
    final data = input['data'] as Map;
    expect(data['jobId'], job.jobId);
    expect(data['infoHash'], 'abc');
    expect(data['title'], '没人做种');
    expect(data['completedBytes'], 10);
    expect(data['connectedPeers'], 0);
    expect(data['seenPeers'], 7);
    expect(data['deadPeers'], 7);
    expect(data.containsKey('index'), false);
    // New bytes close the stall without an event of their own.
    final closed = {
      ...first,
      'resumedAt': DateTime.now().toUtc().toIso8601String()
    };
    await publish(context, job, [closed]);
    expect(await hookJobs(), hasLength(1));
    // The next stretch is a new occurrence.
    await publish(context, job, [closed, stall(1)]);
    hookRuns = await hookJobs();
    expect(hookRuns, hasLength(2));
    expect(
        (await store.database.query('followup_hook_events',
                where: 'event=?', whereArgs: ['download.stalled']))
            .map((r) => r['object_id']),
        ['stalled:${job.jobId}:0', 'stalled:${job.jobId}:1']);
  });

  test('a passed stall and a finished task publish nothing', () async {
    final job = await submit();
    final context = await executor.entered.future;
    final passed = {
      ...stall(0),
      'resumedAt': DateTime.now().toUtc().toIso8601String()
    };
    await publish(context, job, [passed]);
    expect(await engine.list(type: 'harness.hook'), isEmpty);
    await context.report(checkpoint: {
      'stalls': [stall(1)]
    });
    await context.succeed(verified());
    await hooks.taskChanged(await engine.get(job.jobId));
    expect(await engine.list(type: 'harness.hook'), isEmpty);
    expect(
        await store.database.query('followup_hook_events',
            where: 'event=?', whereArgs: ['download.stalled']),
        isEmpty);
  });

  test('followup.register waits for a download or for any download', () async {
    final job = await submit();
    final other = await engine
        .submit(type: 'download', title: '另一个', input: {'infoHash': 'def'});
    final byJob = await followups.register({
      'when': {'event': 'download.stalled', 'objectId': job.jobId},
      'instruction': '这个下载停滞了'
    }, Invocation(origin: 'fixture'));
    final broad = await followups.register({
      'when': {'event': 'download.stalled'},
      'instruction': '任意下载停滞了'
    }, Invocation(origin: 'fixture'));
    final exact = await followups.register({
      'when': {
        'event': 'download.stalled',
        'objectId': 'stalled:${other.jobId}:0'
      },
      'instruction': '另一个下载'
    }, Invocation(origin: 'fixture'));
    final context = await executor.entered.future;
    await publish(context, job, [stall(0)]);
    await followups.sweep();
    final rows = {for (final r in await followups.list()) r['id']: r};
    expect(rows[byJob['id']]!['state'], 'ready');
    expect((rows[byJob['id']]!['trigger'] as Map)['objectId'],
        'stalled:${job.jobId}:0');
    expect(rows[broad['id']]!['state'], 'ready');
    expect(rows[exact['id']]!['state'], 'waiting');
  });

  test('a registration recovers a stall that was persisted but not published',
      () async {
    final job = await submit();
    final context = await executor.entered.future;
    final registered = await followups.register({
      'when': {'event': 'download.stalled', 'objectId': job.jobId},
      'instruction': '这个下载停滞了'
    }, Invocation(origin: 'fixture'));
    await context.report(checkpoint: {
      'stalls': [stall(0)]
    });
    await followups.sweep();
    final row = (await followups.list())
        .singleWhere((r) => r['id'] == registered['id']);
    expect(row['state'], 'ready');
  });

  test('a conversation download does not get the stall twice', () async {
    final job = await submit(conversation: true);
    final context = await executor.entered.future;
    await followups.register({
      'when': {'event': 'download.stalled', 'objectId': job.jobId},
      'threadId': 'original',
      'instruction': '我自己的说明'
    }, Invocation(origin: 'harness_cli'));
    await publish(context, job, [stall(0)]);
    await followups.sweep();
    await followups.sweep();
    final rows = await followups.list();
    final manual = rows.singleWhere((r) => r['automatic'] == null);
    expect(manual['state'], 'ready');
    for (final row in rows.where((r) => r['automatic'] == 'download')) {
      expect(row['state'], 'cancelled');
      expect((row['trigger'] as Map)['facts'], isEmpty);
    }
  });

  test('without a registration the conversation still receives the stall once',
      () async {
    final job = await submit(conversation: true);
    final context = await executor.entered.future;
    await publish(context, job, [stall(0)]);
    await followups.sweep();
    await followups.sweep();
    final rows = await followups.list();
    expect(rows, hasLength(1));
    final facts = (rows.single['trigger'] as Map)['facts'] as List;
    expect(facts, hasLength(1));
    expect((facts.single as Map)['objectId'], 'stalled:${job.jobId}:0');
  });

  test('a stall before metadata is the same event, with unknown counts null',
      () async {
    final job = await submit(conversation: true);
    final context = await executor.entered.future;
    await publish(context, job, [
      {
        'index': 0,
        'at': DateTime.now().toUtc().toIso8601String(),
        'secondsWithoutProgress': 300,
        'completedBytes': 0,
        'totalBytes': null,
        'connectedPeers': null,
        'seenPeers': null,
        'deadPeers': null,
        'metadata': false,
        'error': {'code': 'unavailable', 'message': '磁力链接解析超时'},
      }
    ]);
    final hook = (await hookJobs()).single;
    final data = (await engine.get(hook.jobId)).input['data'] as Map;
    expect(data['metadata'], false);
    expect(data['totalBytes'], isNull);
    expect(data['seenPeers'], isNull);
    await followups.sweep();
    await followups.sweep();
    final rows = await followups.list();
    final facts = (rows.single['trigger'] as Map)['facts'] as List;
    expect(facts, hasLength(1));
    expect((facts.single as Map)['event'], 'download.stalled');
  });
}
