import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/system_views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Job> _terminal(TaskEngine engine, String id) async {
  var job = await engine.get(id);
  while (!job.state.isTerminal) {
    job = await engine.wait(id,
        afterRevision: job.revision, timeout: const Duration(seconds: 3));
  }
  return job;
}

void main() {
  late Directory root, repository;
  late SqliteJobStore store;
  late HarnessHooks hooks;
  late TaskEngine engine;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('hook-status-');
    repository = await Directory('${root.path}/harness').create();
    await Directory('${repository.path}/hooks').create();
    store = await SqliteJobStore.open(Directory('${root.path}/state'),
        factory: databaseFactoryFfi);
    // None of these tests is about the timeout. A short one only turns a slow
    // machine into a SIGKILLed hook, so the product default stays; it costs
    // nothing when hooks exit at once.
    hooks = HarnessHooks();
    engine =
        TaskEngine(store: store, ownerDeviceId: 'test', executors: [hooks]);
    hooks.engine = engine;
    hooks.enable(repository, File('${root.path}/private/endpoint.json'));
  });
  tearDown(() async {
    await hooks.disable();
    await engine.close();
    await root.delete(recursive: true);
  });

  Future<void> write(String name, String text, {String mode = '755'}) async {
    final file = File('${repository.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
    expect((await Process.run('chmod', [mode, file.path])).exitCode, 0);
  }

  Future<Map<String, Map>> hookRows() async => {
        for (final row in ((await hooks.status())['hooks'] as List).cast<Map>())
          '${row['event'] ?? row['program']}': row
      };

  test('a hook is ready, ignored for lack of the execute bit, absent or unrecognized',
      () async {
    await write('hooks/playback.started', '#!/bin/sh\nexit 0\n');
    await write('hooks/playback.ended', '#!/bin/sh\nexit 0\n', mode: '644');
    await write('hooks/notes.txt', 'not an event', mode: '644');
    await write('hooks/schedules.json', '[]', mode: '644');
    final rows = await hookRows();
    expect(rows['playback.started']!['state'], 'ready');
    expect(rows['playback.started']!['program'], 'playback.started');
    expect(rows['playback.started']!['runs'], 0);
    expect(rows['playback.ended']!['state'], 'not_executable');
    expect(rows['download.completed']!['state'], 'absent');
    expect(rows['download.completed']!['program'], isNull);
    expect(rows['notes.txt']!['state'], 'unrecognized');
    expect(rows['notes.txt']!['event'], isNull);
    expect(rows.containsKey('schedules.json'), false);
    for (final event in HarnessHooks.events) {
      expect(rows.containsKey(event), true, reason: event);
    }
  }, skip: Platform.isWindows);

  test('the last run of a hook is told with its time, exit code and duration',
      () async {
    await write('hooks/playback.started', '#!/bin/sh\nexit 3\n');
    await engine.start();
    final submitted = (await hooks.emit('playback.started', '/a.mkv', {}))!;
    final job = await _terminal(engine, submitted.jobId);
    final row = (await hookRows())['playback.started']!;
    expect(row['runs'], 1);
    expect(row['lastState'], 'failed');
    expect(row['lastExitCode'], 3);
    expect(row['lastElapsedMs'], isA<int>());
    expect(row['lastJobId'], job.jobId);
    expect(DateTime.parse(row['lastRunAt'] as String).isUtc, true);
    expect(DateTime.parse(row['lastFinishedAt'] as String).isUtc, true);
  }, skip: Platform.isWindows);

  test('schedules: valid and invalid entries with reasons, next time, none run while one is invalid',
      () async {
    await write('hooks/ok.sh', '#!/bin/sh\nexit 0\n');
    await write('hooks/plain.sh', '#!/bin/sh\nexit 0\n', mode: '644');
    await write(
        'hooks/schedules.json',
        jsonEncode([
          {'id': 'a', 'program': 'hooks/ok.sh', 'everySeconds': 60},
          {'id': 'b', 'program': 'hooks/plain.sh', 'dailyAt': '03:30'},
          {'id': 'c', 'program': '../outside.sh', 'everySeconds': 5},
          {'id': 'd', 'program': 'hooks/ok.sh'},
          {'id': 'a', 'program': 'hooks/ok.sh', 'everySeconds': 10},
          'text',
        ]),
        mode: '644');
    final status = (await hooks.status())['schedules'] as Map;
    expect(status['file'], 'invalid');
    expect(status['error'], contains('none of the schedules'));
    final entries = (status['entries'] as List).cast<Map>();
    expect(entries.map((e) => e['valid']),
        [false, true, false, false, false, false]);
    expect(entries[0]['reason'], 'Schedule ids must be unique.');
    expect(entries[2]['reason'], contains('relative path inside'));
    expect(entries[3]['reason'], contains('exactly one'));
    expect(entries[5]['reason'], contains('schedule object'));
    expect(entries[1]['programState'], 'not_executable');
    // The tick refuses a file with an invalid entry: nothing is due.
    await hooks.schedules.tick(DateTime.now());
    for (final e in ((await hooks.status())['schedules'] as Map)['entries']
        as List) {
      expect((e as Map)['nextDueAt'], isNull);
    }
  }, skip: Platform.isWindows);

  test('next time, late ticks and overlapping runs are counted and the last run is kept',
      () async {
    await write('hooks/ok.sh', '#!/bin/sh\nexit 0\n');
    await write(
        'hooks/schedules.json',
        jsonEncode([
          {'id': 'every', 'program': 'hooks/ok.sh', 'everySeconds': 30},
          {'id': 'daily', 'program': 'hooks/missing.sh', 'dailyAt': '03:30'},
        ]),
        mode: '644');
    // Near the real clock, so the timer's own ticks find nothing due.
    final t0 = DateTime.now().toUtc();
    await hooks.schedules.tick(t0);
    var status = (await hooks.status())['schedules'] as Map;
    expect(status['file'], 'valid');
    expect(status['active'], true);
    expect(status['lastTickAt'], t0.toIso8601String());
    var entries = (status['entries'] as List).cast<Map>();
    expect(entries[0]['nextDueAt'],
        t0.add(const Duration(seconds: 30)).toIso8601String());
    expect(entries[0]['skippedLate'], 0);
    expect(entries[1]['programState'], 'absent');
    expect(DateTime.parse(entries[1]['nextDueAt'] as String).isUtc, true);

    // The application slept past the due time: that occurrence is dropped.
    final late = t0.add(const Duration(seconds: 120));
    await hooks.schedules.tick(late);
    status = (await hooks.status())['schedules'] as Map;
    entries = (status['entries'] as List).cast<Map>();
    expect(entries[0]['skippedLate'], 1);
    expect(entries[0]['lastSkippedDueAt'],
        t0.add(const Duration(seconds: 30)).toIso8601String());
    expect(entries[0]['lastStartedDueAt'], isNull);

    // On time: the occurrence is started and its run is reported.
    await engine.start();
    final due = DateTime.parse(entries[0]['nextDueAt'] as String);
    await hooks.schedules.tick(due.add(const Duration(milliseconds: 500)));
    await hooks.drain();
    final job = (await engine.list(type: 'harness.hook')).single;
    await _terminal(engine, job.jobId);
    entries = ((await hooks.status())['schedules'] as Map)['entries']
        .cast<Map>() as List<Map>;
    expect(entries[0]['lastStartedDueAt'], due.toUtc().toIso8601String());
    expect(entries[0]['runs'], 1);
    expect(entries[0]['lastState'], 'succeeded');
    expect(entries[0]['lastExitCode'], 0);
    expect(entries[0]['skippedWhileRunning'], 0);

    hooks.schedules.skippedRunning('every', due);
    entries = ((await hooks.status())['schedules'] as Map)['entries']
        .cast<Map>() as List<Map>;
    expect(entries[0]['skippedWhileRunning'], 1);
  }, skip: Platform.isWindows);

  test('a file that is not JSON is one invalid row; an absent file has no rows',
      () async {
    var rows = await _query(hooks, 'harness.schedules');
    expect(rows, isEmpty);
    expect(((await hooks.status())['schedules'] as Map)['file'], 'absent');
    await write('hooks/schedules.json', '{not json', mode: '644');
    rows = await _query(hooks, 'harness.schedules');
    expect(rows, hasLength(1));
    expect(rows.single['valid'], false);
    expect(rows.single['index'], isNull);
    expect(rows.single['file'], 'invalid');
    expect(rows.single['reason'], isA<String>());
  });

  test('the views describe their fields and answer queries without a harness',
      () async {
    await write('hooks/playback.started', '#!/bin/sh\nexit 0\n');
    final state = StateCapability(
        systemStateViews(SystemStatusSources()..hooks = hooks.status));
    final harness = Harness([state]);
    final described = (await harness.invokeJson(
            'state.describe', {}, Invocation(origin: 'test')))
        .toEnvelope();
    final names = [
      for (final v in (described['result'] as Map)['views'] as List)
        (v as Map)['view']
    ];
    expect(names, containsAll(['harness.hooks', 'harness.schedules']));
    expect(names, isNot(contains('media.sources')));
    final queried = (await harness.invokeJson(
            'state.query',
            {
              'view': 'harness.hooks',
              'filter': {
                'state': {'eq': 'ready'}
              }
            },
            Invocation(origin: 'test')))
        .toEnvelope();
    final rows = ((queried['result'] as Map)['rows'] as List).cast<Map>();
    expect(rows.single['event'], 'playback.started');
  }, skip: Platform.isWindows);
}

Future<List<Map>> _query(HarnessHooks hooks, String view) async {
  final state = StateCapability(
      systemStateViews(SystemStatusSources()..hooks = hooks.status));
  final result = (await Harness([state]).invokeJson(
          'state.query', {'view': view}, Invocation(origin: 'test')))
      .toEnvelope();
  expect(result['status'], 'completed', reason: jsonEncode(result));
  return ((result['result'] as Map)['rows'] as List).cast<Map>();
}
