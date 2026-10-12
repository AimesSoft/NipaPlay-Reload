import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'file evidence survives restart, authorizes only checked files, and delivers once',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('x40-constraints-');
    await Directory('${root.path}/hooks').create();
    final program = File('${root.path}/hooks/download.file_completed');
    await program.writeAsString('#!/bin/sh\ncat >> events.jsonl\n');
    expect((await Process.run('chmod', ['755', program.path])).exitCode, 0);
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    final location = HarnessLocation();
    final first = File('${root.path}/first.mp4');
    final second = File('${root.path}/second.mp4');
    await first.writeAsString('data');
    await second.writeAsString('data');
    var store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    var executor = FakeExecutor(type: 'download');
    var hooks = HarnessHooks();
    var engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [executor, hooks]);
    hooks.engine = engine;
    hooks.enable(root, File('${root.path}/endpoint.json'));
    var followups = Followups(store.database, engine, location);
    hooks.observeEvent = followups.hookEvent;
    await engine.start();
    final job = await engine.submit(
        type: 'download', title: 'Fixture', input: {'infoHash': 'fixture'});
    final context = await executor.entered.future;
    await followups.register({
      'when': {
        'event': 'download.file_completed',
        'objectId': '${job.jobId}:0'
      },
      'instruction': 'Read the completed file'
    }, Invocation(origin: 'fixture'));
    final row = {
      'index': 0,
      'jobId': job.jobId,
      'objectId': '${job.jobId}:0',
      'canonicalPath': await first.resolveSymbolicLinks(),
      'path': first.path,
      'local': true,
      'included': true,
      'complete': true,
      'verification': 'verified',
      'actualSize': 4,
      'expectedSize': 4,
      'completedAt': DateTime.now().toUtc().toIso8601String()
    };
    await context.report(checkpoint: {
      'completedFiles': [
        row,
        {
          ...row,
          'index': 1,
          'objectId': '${job.jobId}:1',
          'canonicalPath': second.path,
          'verification': 'unverified'
        }
      ]
    });
    // Simulate a crash before publishing: recovery must still trigger the registered followup.
    await followups.sweep();
    expect((await followups.list()).single['state'], 'ready');
    final late = await followups.register({
      'when': {'event': 'download.file_completed'},
      'instruction': 'Await a future completion, not this recovered old file',
    }, Invocation(origin: 'fixture'));
    await hooks.taskChanged(await engine.get(job.jobId));
    final hook = (await engine.list(type: 'harness.hook')).single;
    await untilState(engine, hook.jobId, JobState.succeeded);
    await hooks.taskChanged(await engine.get(job.jobId));
    expect(await engine.list(type: 'harness.hook'), hasLength(1));
    await hooks.disable();
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(type: 'download');
    hooks = HarnessHooks();
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [executor, hooks]);
    hooks.engine = engine;
    hooks.enable(root, File('${root.path}/endpoint.json'));
    followups = Followups(store.database, engine, location);
    hooks.observeEvent = followups.hookEvent;
    await engine.start();
    await hooks.taskChanged(await engine.get(job.jobId));
    await followups.sweep();
    expect(
        (await followups.list())
            .singleWhere((row) => row['id'] == late['id'])['state'],
        'waiting');
    expect(await engine.list(type: 'harness.hook'), hasLength(1));
    expect(await store.database.query('followup_hook_events'), hasLength(1));
    final media = MediaService(
        store: IdentityStore(store.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => []);
    expect(await media.authorizedPath(first.path),
        await first.resolveSymbolicLinks());
    await expectLater(
        media.authorizedPath(second.path), throwsA(isA<Failure>()));
    await expectLater(media.authorizedPath(root.path, directory: true),
        throwsA(isA<Failure>()));
    await first.delete();
    await Link(first.path).create(second.path);
    await expectLater(
        media.authorizedPath(first.path), throwsA(isA<Failure>()));
    await hooks.disable();
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  }, skip: Platform.isWindows);
}
