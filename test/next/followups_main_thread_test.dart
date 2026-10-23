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
import 'support/main_thread_probe.dart';

/// An old profile's history: tasks long finished and the followups they
/// returned, delivered and completed. Nothing in it is waiting for anything.
Future<void> _seedHistory(Database db, String repository,
    {int downloads = 600,
    int programs = 400,
    int logins = 400,
    int helpers = 600}) async {
  var minute = 0;
  DateTime at() =>
      DateTime.utc(2025, 1, 1).add(Duration(minutes: minute++));
  final returnTo = {
    'threadId': 'old-thread',
    'repository': repository,
    'origin': 'harness_cli:chat:old',
    'invocationId': 'old-call'
  };
  final batch = db.batch();
  void job(Job job) => batch.insert('jobs', {
        'job_id': job.jobId,
        'type': job.type,
        'state': job.state.wireName,
        'revision': job.revision,
        'created_at': job.createdAt.toIso8601String(),
        'snapshot': jsonEncode(job.toStorageJson()),
      });
  void row(JsonMap row) => batch.insert('followups',
      {'id': row['id'], 'state': row['state'], 'snapshot': jsonEncode(row)});
  Job finished(String id, String type, JsonMap input,
      {JsonMap checkpoint = const {}}) {
    final time = at();
    return Job(
        jobId: id,
        type: type,
        title: '$type $id',
        state: JobState.succeeded,
        phase: 'done',
        progress: JobProgress(completed: 1, total: 1, unit: 'items'),
        createdAt: time,
        updatedAt: time.add(const Duration(seconds: 30)),
        ownerDeviceId: 'fixture',
        revision: 6,
        input: input,
        checkpoint: checkpoint,
        receipt: verified(details: {'summary': 'done', 'id': id}));
  }

  JsonMap delivered(String id, Job job, JsonMap extra) {
    final time = job.updatedAt.add(const Duration(seconds: 5)).toIso8601String();
    return {
      'id': id,
      'state': 'completed',
      'title': '回执：${job.title}',
      'instruction': '这是一段已经送达的说明，记录当时让 Nipa 知道的事实。下一步由她决定。',
      'waitingFor': null,
      'repository': repository,
      'threadId': 'old-thread',
      'turnId': 'turn-$id',
      'origin': 'harness_cli:chat:old',
      'invocationId': 'old-call',
      'createdAt': time,
      'updatedAt': time,
      'dispatchedAt': time,
      'reason': null,
      'turnStatus': 'completed',
      ...extra,
    };
  }

  for (var i = 0; i < downloads; i++) {
    final id = 'job-download-$i';
    final files = [
      for (var index = 0; index < 3; index++)
        {
          'objectId': '$id:$index',
          'jobId': id,
          'index': index,
          'path': '/downloads/show-$i/episode-$index.mkv',
          'canonicalPath': '/downloads/show-$i/episode-$index.mkv',
          'expectedSize': 734003200,
          'actualSize': 734003200,
          'completedBytes': 734003200,
          'complete': true,
          'verification': 'verified',
          'local': true,
          'included': true,
          'isVideo': true,
          'imported': true,
          'media': {
            'fileId': 'file-$i-$index',
            'workIds': ['work-$i'],
          },
          'completedAt': at().toIso8601String(),
        }
    ];
    final download = finished(id, 'download',
        {'infoHash': 'hash-$i', 'returnTo': returnTo},
        checkpoint: {'completedFiles': files, 'infoHash': 'hash-$i'});
    job(download);
    row(delivered('followup-download-$id-0', download, {
      'automatic': 'download',
      'condition': {'downloadJobId': id},
      'downloadObjects': [for (final f in files) f['objectId'], 'terminal:$id'],
      'deliverAfter': download.updatedAt.toIso8601String(),
      'trigger': {
        'kind': 'download.facts',
        'jobId': id,
        'title': download.title,
        'facts': [
          for (final f in files)
            {
              'event': 'download.file_completed',
              'objectId': f['objectId'],
              'occurredAt': f['completedAt'],
              'data': {
                'jobId': id,
                'infoHash': 'hash-$i',
                'title': download.title,
                'file': {...f, 'playable': true}
              }
            },
          {
            'event': 'task.terminal',
            'objectId': id,
            'occurredAt': download.updatedAt.toIso8601String(),
            'data': {'jobId': id, 'type': 'download', 'state': 'succeeded'}
          }
        ]
      },
    }));
  }
  for (var i = 0; i < programs; i++) {
    final id = 'job-program-$i';
    final program = finished(id, 'program', {'returnTo': returnTo});
    job(program);
    row(delivered('followup-program-$id', program, {
      'automatic': 'program',
      'condition': {'programJobId': id},
      'deliverAfter': program.updatedAt.toIso8601String(),
      'trigger': {
        'kind': 'program.facts',
        'jobId': id,
        'title': program.title,
        'facts': [
          {
            'event': 'task.terminal',
            'objectId': id,
            'occurredAt': program.updatedAt.toIso8601String(),
            'data': {'jobId': id, 'type': 'program', 'state': 'succeeded'}
          }
        ]
      },
    }));
  }
  for (var i = 0; i < logins; i++) {
    final id = 'job-login-$i';
    final login = finished(id, 'accounts.login', {'returnTo': returnTo});
    job(login);
    row(delivered('followup-user-task-$id', login, {
      'automatic': 'userTask',
      'condition': {'userTaskJobId': id},
      'deliverAfter': login.updatedAt.toIso8601String(),
      'trigger': {
        'kind': 'task.facts',
        'jobId': id,
        'title': login.title,
        'facts': [
          {
            'event': 'task.terminal',
            'objectId': id,
            'occurredAt': login.updatedAt.toIso8601String(),
            'data': {'jobId': id, 'type': 'accounts.login', 'state': 'succeeded'}
          }
        ]
      },
    }));
  }
  for (var i = 0; i < helpers; i++) {
    final id = 'job-helper-$i';
    final helper = finished(id, 'agent.helper',
        {'parentThreadId': 'old-thread', 'repository': repository});
    job(helper);
    row(delivered('followup-helper-$i', helper, {
      'condition': {'jobId': id},
      'hookCursor': 0,
      'trigger': {
        'kind': 'task.terminal',
        'occurredAt': helper.updatedAt.toIso8601String(),
        'jobId': id,
        'state': 'succeeded'
      },
    }));
  }
  await batch.commit(noResult: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late HarnessLocation location;
  late FakeExecutor download;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('followups-main-thread-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    await _seedHistory(store.database, root.path);
    download = FakeExecutor(type: 'download');
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'fixture',
        executors: [download, FakeExecutor(type: 'agent.helper')]);
    await engine.start();
    followups = Followups(store.database, engine, location);
  });
  tearDown(() async {
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  test('a sweep after one task change, over 2000 finished followups and tasks',
      () async {
    final first = MainThreadProbe.start();
    await followups.sweep();
    first.stop();
    final job = await engine.submit(type: 'download', title: '新番', input: {
      'infoHash': 'running',
      'returnTo': {
        'threadId': 'now',
        'repository': root.path,
        'origin': 'harness_cli:chat:now',
        'invocationId': 'now-call'
      }
    });
    final context = await download.entered.future;
    await followups.sweep();
    await context.report(
        progress: JobProgress(completed: 10, total: 100, unit: 'bytes'));
    final probe = MainThreadProbe.start();
    await followups.sweep();
    probe.stop();
    // ignore: avoid_print
    print('first sweep (startup reconcile): $first');
    // ignore: avoid_print
    print('sweep after one task change: $probe');
    expect(await store.database.query('followups'), hasLength(2000));
    expect(job.state, JobState.queued);
  });
}
