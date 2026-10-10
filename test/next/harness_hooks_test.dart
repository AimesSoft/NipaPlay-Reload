import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Job> terminal(TaskEngine engine, String id) async {
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
    root = await Directory.systemTemp.createTemp('hook-constraints-');
    repository = await Directory('${root.path}/harness').create();
    await Directory('${repository.path}/hooks').create();
    store = await SqliteJobStore.open(Directory('${root.path}/state'),
        factory: databaseFactoryFfi);
    hooks = HarnessHooks(timeout: const Duration(milliseconds: 500));
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
  Future<void> program(String text) async {
    final file = File('${repository.path}/hooks/playback.started');
    await file.writeAsString('#!/bin/sh\n$text\n');
    final permissions = await Process.run('chmod', ['755', file.path]);
    expect(permissions.exitCode, 0);
  }

  test(
      'concurrent identical events share one persisted task, receipts retain only sanitized tails',
      () async {
    SecretRedactor.remember(
        const CredentialRef('test', 'token'), 'synthetic-hook-token');
    await program(
        "cat > received.json\nprintf 'synthetic-hook-token\\ncookie=private-cookie\\n'\nprintf 'secret=private-secret\\n' >&2");
    final jobs = await Future.wait(List.generate(
        8,
        (_) => hooks
            .emit('playback.started', '/test.mkv', {'path': '/test.mkv'})));
    expect(jobs.map((j) => j!.jobId).toSet(), hasLength(1));
    await engine.start();
    final job = await terminal(engine, jobs.first!.jobId);
    expect(job.state, JobState.succeeded);
    final raw = jsonEncode(job.toStorageJson());
    for (final value in [
      'synthetic-hook-token',
      'private-cookie',
      'private-secret'
    ]) {
      expect(raw, isNot(contains(value)));
    }
    expect(job.receipt!.details['exitCode'], 0);
    expect(job.receipt!.details['elapsedMs'], isA<int>());
    final received = jsonDecode(
        await File('${repository.path}/received.json').readAsString()) as Map;
    expect(received['event'], 'playback.started');
    expect((await store.events(job.jobId)).last.snapshot['receipt'],
        job.receipt!.toJson());
  }, skip: Platform.isWindows);

  test(
      'timeout and nonzero exit produce failed receipts, never verified success',
      () async {
    await program('exec sleep 5');
    await engine.start();
    final submitted = (await hooks.emit('playback.started', '/slow.mkv', {}))!;
    final job = await terminal(engine, submitted.jobId);
    expect(job.state, JobState.failed);
    expect(job.receipt!.verification, VerificationLevel.unverified);
    expect(job.receipt!.details['timedOut'], true);
    expect(job.receipt!.details['elapsedMs'] as int, lessThan(2000));
    await program('echo failed >&2\nexit 3');
    final failed = await terminal(engine,
        (await hooks.emit('playback.started', '/failure.mkv', {}))!.jobId);
    expect(failed.state, JobState.failed);
    expect(failed.receipt!.details['exitCode'], 3);
    expect(failed.receipt!.details['stderrTail'], contains('failed'));
  }, skip: Platform.isWindows);

  test(
      'interrupted persisted hooks fail honestly without replaying the program',
      () async {
    await program('touch should-not-run');
    final queued =
        (await hooks.emit('playback.started', '/interrupted.mkv', {}))!;
    final now = DateTime.now().toUtc();
    final running = Job.fromJson({
      ...queued.toStorageJson(),
      'state': 'running',
      'revision': 1,
      'updatedAt': now.toIso8601String()
    });
    await store.commit(
        running,
        JobEvent(
            jobId: running.jobId,
            revision: 1,
            kind: 'running',
            at: now,
            snapshot: running.toJson()),
        expectedRevision: 0);
    await engine.start();
    final recovered = await terminal(engine, queued.jobId);
    expect(recovered.state, JobState.failed);
    expect(recovered.receipt!.details['reason'], 'interrupted_no_replay');
    expect(await File('${repository.path}/should-not-run').exists(), false);
  }, skip: Platform.isWindows);
}
