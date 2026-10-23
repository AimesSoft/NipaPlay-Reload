import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/tasks/nipa_gate.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../packages/nipa_harness/test/task_support.dart';

const _wait = Duration(seconds: 10);

Future<void> _idle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late NipaGate gate;
  late FakeExecutor helper, download;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-nipa-gate-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    gate = NipaGate();
    helper = FakeExecutor(type: 'agent.helper');
    download = FakeExecutor(type: 'download');
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'device-test',
        executors: [NipaGatedExecutor(helper, gate), download]);
    await engine.start();
  });
  tearDown(() async {
    helper.release.complete();
    download.release.complete();
    await engine.close();
    await root.delete(recursive: true);
  });

  test('Nipa\'s own task waits for Next\'s interface; the rest of the '
      'engine runs regardless', () async {
    expect(nipaTaskTypes, containsAll(['agent.helper', 'program', 'harness.hook']));
    await engine.submit(type: 'agent.helper', title: 'helper');
    await engine.submit(type: 'download', title: 'download');
    await download.entered.future.timeout(_wait);
    await _idle();
    expect(helper.executions, 0);
    gate.set(true);
    await helper.entered.future.timeout(_wait);
    expect(helper.executions, 1);
  });

  test('a waiting task asked to stop is handed on at once', () async {
    final job = await engine.submit(type: 'agent.helper', title: 'helper');
    await _idle();
    expect(helper.executions, 0);
    await engine.cancel(job.jobId);
    await helper.entered.future.timeout(_wait);
    expect(helper.executions, 1);
  });

  test('closing again holds what has not started', () async {
    gate.set(true);
    gate.set(false);
    expect(gate.open, isFalse);
    await engine.submit(type: 'agent.helper', title: 'helper');
    await engine.submit(type: 'download', title: 'download');
    await download.entered.future.timeout(_wait);
    await _idle();
    expect(helper.executions, 0);
    gate.set(true);
    await helper.entered.future.timeout(_wait);
    expect(helper.executions, 1);
  });
}
