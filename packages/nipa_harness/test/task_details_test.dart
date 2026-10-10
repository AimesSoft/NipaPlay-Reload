import 'package:nipa_harness/nipa_harness.dart';
import 'package:test/test.dart';

import 'task_support.dart';

void main() {
  test(
      'public executor details survive storage and appear consistently in every snapshot',
      () async {
    final store = MemoryJobStore();
    final executor = FakeExecutor();
    final engine =
        TaskEngine(store: store, ownerDeviceId: 'local', executors: [executor]);
    addTearDown(engine.close);
    await engine.start();
    final details = <String, Object?>{
      'component': {'kind': 'test'}
    };
    final job = await engine.submit(
        type: 'test',
        title: 'Details',
        input: {'private': 'input'},
        details: details);
    (details['component'] as JsonMap)['kind'] = 'mutated';
    final context = await executor.entered.future;
    expect(context.job.toJson()['component'], {'kind': 'test'});
    await context.report(checkpoint: {
      'private': 'handle'
    }, details: {
      'component': {'kind': 'updated'},
      'count': 2
    });
    await context.succeed(verified());
    final done = await engine.get(job.jobId);
    final harness = Harness([TaskCapability(engine)]);
    for (final action in ['get', 'wait', 'list']) {
      final outcome = await harness.invokeJson(
          'task.$action',
          action == 'list' ? {} : {'jobId': job.jobId},
          Invocation(origin: 'test')) as Completed<JsonEncodable>;
      final result = outcome.value.toJson();
      final snapshot = action == 'list'
          ? (result['jobs'] as List).single as JsonMap
          : result['job'] as JsonMap;
      expect(snapshot, done.toJson());
      expect(snapshot['component'], {'kind': 'updated'});
      expect(snapshot.containsKey('input'), isFalse);
      expect(snapshot.containsKey('checkpoint'), isFalse);
      expect(snapshot.containsKey('details'), isFalse);
      expect(harness.lookup('task.$action')!.spec.output.validate(result),
          isEmpty);
    }
    expect(Job.fromJson(done.toStorageJson()).details, done.details);
    expect((await store.events(job.jobId)).last.snapshot['component'],
        {'kind': 'updated'});
    final legacy = Map<String, Object?>.from(done.toStorageJson())
      ..remove('details');
    expect(Job.fromJson(legacy).details, isEmpty);
    executor.release.complete();
  });

  test('details cannot overwrite public or storage-only kernel fields',
      () async {
    final executor = FakeExecutor();
    final engine = TaskEngine(
        store: MemoryJobStore(), ownerDeviceId: 'local', executors: [executor]);
    addTearDown(engine.close);
    await engine.start();
    for (final field in [
      'jobId',
      'state',
      'receipt',
      'input',
      'checkpoint',
      'details',
      'sideEffectCommitted'
    ]) {
      await expectLater(
          engine.submit(
              type: 'test', title: 'Reserved', details: {field: 'shadow'}),
          throwsArgumentError);
    }
    expect(await engine.list(), isEmpty);
  });
}
