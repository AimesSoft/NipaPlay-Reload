import 'dart:async';
import 'dart:io';

// 由 flutter_test 提供。
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/download_runtime.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('启动只投影活动下载 ID，不解码任务快照或加载其他任务', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('perf-download-ids-');
    final store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    try {
      final batch = store.database.batch();
      for (final state in JobState.values) {
        batch.insert('jobs', {
          'job_id': state.name, 'type': 'download', 'state': state.wireName,
          'revision': 0, 'created_at': DateTime.utc(2026).toIso8601String(),
          'snapshot': '{"notAJobSnapshot":true}',
        });
      }
      batch.insert('jobs', {
        'job_id': 'other', 'type': 'program', 'state': JobState.running.wireName,
        'revision': 0, 'created_at': DateTime.utc(2026).toIso8601String(),
        'snapshot': '{"notAJobSnapshot":true}',
      });
      await batch.commit(noResult: true);
      expect(await store.observingDownloadIds(), {'queued', 'running', 'cancelling'});
    } finally {
      await store.close();
      await root.delete(recursive: true);
    }
  });

  test('空闲停止，只有下载任务唤醒观察，完成后再次停止', () {
    fakeAsync((clock) {
      final root = Directory('/tmp/perf-download-observation');
      final jobs = MemoryJobStore();
      final done = Completer<void>();
      final download = FakeExecutor(
          type: 'download',
          onExecute: (context) async {
            await done.future;
            await context.succeed(verified());
          });
      final other = FakeExecutor();
      final engine = TaskEngine(
          store: jobs, ownerDeviceId: 'perf', executors: [download, other]);
      engine.start();
      clock.flushMicrotasks();
      var observations = 0;
      final runtime = DownloadRuntime(
          backend: FakeDownloadBackend(root),
          library: FakeDownloadLibrary(),
          isEnabled: () async => false,
          loadImportedKeys: () async {
            observations++;
            return {};
          })
        ..attach(engine, root);
      var ready = false;
      runtime.start().then((_) => ready = true);
      clock.flushMicrotasks();
      expect(ready, true);
      expect(observations, 1); // 一次启动核对。
      clock.elapse(const Duration(seconds: 60));
      expect(observations, 1);
      expect(clock.nonPeriodicTimerCount, 0);
      engine.submit(type: 'test', title: '其他任务');
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 60));
      expect(observations, 1);
      engine.submit(type: 'download', title: '下载');
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      expect(observations, 2);
      clock.elapse(const Duration(seconds: 10));
      expect(observations, 4);
      done.complete();
      clock.flushMicrotasks();
      expect(jobs.jobs.values.where((j) => j.type == 'download').single.state,
          JobState.succeeded);
      clock.elapse(const Duration(seconds: 60));
      expect(observations, 4);
      expect(clock.nonPeriodicTimerCount, 0);
      runtime.stop();
      engine.close();
      clock.flushMicrotasks();
    });
  });

  test('排队下载维持观察，暂停立即停止，恢复重新启动', () {
    fakeAsync((clock) {
      final root = Directory('/tmp/perf-download-queue');
      final jobs = MemoryJobStore();
      final executor = FakeExecutor(
          type: 'download',
          onRecover: (context) async {
            await context.running();
            await Completer<void>().future;
          });
      final engine =
          TaskEngine(store: jobs, ownerDeviceId: 'perf', executors: [executor]);
      engine.start();
      clock.flushMicrotasks();
      engine.setCapacity('download', 1);
      clock.flushMicrotasks();
      engine.submit(type: 'download', title: '占用下载槽');
      clock.flushMicrotasks();
      final first = jobs.jobs.keys.single;
      var observations = 0;
      final runtime = DownloadRuntime(
          backend: FakeDownloadBackend(root),
          library: FakeDownloadLibrary(),
          isEnabled: () async => false,
          loadImportedKeys: () async {
            observations++;
            return {};
          })
        ..attach(engine, root);
      runtime.start();
      clock.flushMicrotasks();
      engine.submit(type: 'download', title: '排队下载');
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      final id = jobs.jobs.values.singleWhere((j) => j.title == '排队下载').jobId;
      expect(jobs.jobs[id]!.state, JobState.queued);
      final queued = observations;
      engine.pause(first);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      expect(observations, queued + 1);
      engine.pause(id);
      clock.flushMicrotasks();
      executor.release.complete();
      clock.flushMicrotasks();
      final paused = observations;
      clock.elapse(const Duration(seconds: 60));
      expect(observations, paused);
      expect(clock.nonPeriodicTimerCount, 0);
      engine.resume(id);
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      expect(observations, paused + 1);
      runtime.stop();
      engine.close();
      clock.flushMicrotasks();
    });
  });

  test('不支持下载的设备不初始化后端，不读导入记录，不建立观察', () {
    fakeAsync((clock) {
      final root = Directory('/tmp/perf-download-unsupported');
      final backend = FakeDownloadBackend(root);
      final engine = TaskEngine(
          store: MemoryJobStore(),
          ownerDeviceId: 'perf',
          executors: [FakeExecutor(type: 'download')]);
      engine.start();
      clock.flushMicrotasks();
      var importedReads = 0, enabledReads = 0;
      final runtime = DownloadRuntime(
          backend: backend,
          library: FakeDownloadLibrary(),
          supportsDownloads: false,
          isEnabled: () async {
            enabledReads++;
            return true;
          },
          loadImportedKeys: () async {
            importedReads++;
            return {};
          })
        ..attach(engine, root);
      runtime.start();
      clock.flushMicrotasks();
      engine.submit(type: 'download', title: '残留下载');
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 60));
      runtime.refresh();
      clock.flushMicrotasks();
      expect(backend.initializations, 0);
      expect(importedReads, 0);
      expect(enabledReads, 0);
      expect(clock.nonPeriodicTimerCount, 0);
      runtime.stop();
      engine.close();
      clock.flushMicrotasks();
    });
  });
}
