import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Job _job(String id, int revision, {String phase = 'queued', String? note}) {
  final at = DateTime.utc(2026, 10, 23, 0, 0, revision);
  return Job(
      jobId: id,
      type: id.startsWith('d') ? 'download' : 'media.scan',
      title: 'Job $id',
      state: JobState.queued,
      phase: phase,
      progress: JobProgress(completed: 0, unit: 'items'),
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: at,
      ownerDeviceId: 'device-test',
      revision: revision,
      input: {'n': revision, if (note != null) 'note': note});
}

Future<void> _commit(SqliteJobStore store, Job job) => store.commit(
    job,
    JobEvent(
        jobId: job.jobId,
        revision: job.revision,
        kind: 'fixture',
        at: job.updatedAt,
        snapshot: job.toJson()),
    expectedRevision: job.revision == 0 ? null : job.revision - 1);

void main() {
  sqfliteFfiInit();
  late Directory root;
  late SqliteJobStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('job-store-cache-');
    store = await SqliteJobStore.open(Directory('${root.path}/db'),
        factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test('an unchanged job is not decoded again; a changed one is', () async {
    for (final id in ['d1', 'd2', 's1']) {
      await _commit(store, _job(id, 0));
    }
    final first = await store.list();
    expect(first.map((j) => j.jobId), ['d1', 'd2', 's1']);
    final second = await store.list();
    for (var i = 0; i < first.length; i++) {
      expect(identical(first[i], second[i]), isTrue);
    }
    expect(identical(await store.get('d2'), second[1]), isTrue);

    await _commit(store, _job('d2', 1, phase: 'downloading', note: 'moved'));
    final third = await store.list();
    expect(identical(third[0], first[0]), isTrue);
    expect(identical(third[2], first[2]), isTrue);
    expect(third[1].revision, 1);
    expect(third[1].phase, 'downloading');
    expect(third[1].input['note'], 'moved');
    expect((await store.get('d2'))!.revision, 1);
  });

  test('filters and order are those of storage', () async {
    await _commit(store, _job('d1', 0));
    await _commit(store, _job('s1', 0));
    await _commit(store, _job('d2', 0));
    expect((await store.list(type: 'download')).map((j) => j.jobId),
        ['d1', 'd2']);
    expect((await store.list(type: 'media.scan')).map((j) => j.jobId), ['s1']);
    expect((await store.list(state: JobState.running)), isEmpty);
    expect(await store.get('missing'), isNull);
  });

  test('a job written by another store on the same database is read fresh',
      () async {
    await _commit(store, _job('d1', 0));
    expect((await store.list()).single.revision, 0);
    final other = SqliteJobStore.fromDatabase(store.database);
    await _commit(other, _job('d1', 1, phase: 'elsewhere'));
    final job = (await store.list()).single;
    expect(job.revision, 1);
    expect(job.phase, 'elsewhere');
  });

  test('a large history is listed without decoding it again', () async {
    for (var i = 0; i < 200; i++) {
      await _commit(store,
          _job('d$i', 0, note: List.filled(2000, 'x').join()));
    }
    await store.list();
    final watch = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await store.list();
    }
    // ignore: avoid_print
    print('20 lists of 200 cached jobs: ${watch.elapsedMilliseconds} ms');
    expect((await store.list()).length, 200);
  });
}
