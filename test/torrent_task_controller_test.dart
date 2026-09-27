import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/downloads/torrent_task_controller.dart';
import 'package:nipaplay/models/torrent_task.dart';

TorrentTask task(String state,
        {bool finished = false, bool initializingPaused = false}) =>
    TorrentTask.fromMap({
      'id': 1,
      'stats': {
        'state': state,
        'finished': finished,
        'initializing_paused': initializingPaused
      }
    });

void main() {
  test('refreshes immediately after a task action without a timer tick',
      () async {
    var state = 'live';
    final controller =
        TorrentTaskController(loadTasks: () async => [task(state)]);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.run(1, () async => state = 'paused');
    expect(controller.tasks.single.isPaused, isTrue);
    expect(controller.isBusy(1), isFalse);
  });

  test('a stale in-flight poll cannot overwrite the post-action snapshot',
      () async {
    final stalePoll = Completer<List<TorrentTask>>();
    var calls = 0;
    final controller = TorrentTaskController(loadTasks: () {
      calls++;
      return calls == 1 ? stalePoll.future : Future.value([task('paused')]);
    });
    addTearDown(controller.dispose);
    final poll = controller.refresh();
    final action = controller.run(1, () async {});
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBusy(1), isTrue);
    stalePoll.complete([task('live')]);
    await Future.wait([poll, action]);
    expect(calls, 2);
    expect(controller.tasks.single.isPaused, isTrue);
  });

  test(
      'a busy task prevents duplicate actions but does not block another task or refresh',
      () async {
    final blocked = Completer<void>();
    var loads = 0;
    final controller = TorrentTaskController(loadTasks: () async {
      loads++;
      return [];
    });
    addTearDown(controller.dispose);
    final first = controller.run(1, () => blocked.future);
    expect(
        await controller.run(1, () async => fail('duplicate action')), isFalse);
    expect(await controller.run(2, () async {}), isTrue);
    await controller.refresh();
    expect(loads, greaterThanOrEqualTo(2));
    expect(controller.isBusy(1), isTrue);
    blocked.complete();
    await first;
  });

  test('errors release a task and allow retry', () async {
    final controller = TorrentTaskController(loadTasks: () async => []);
    addTearDown(controller.dispose);
    await expectLater(controller.run(1, () async => throw StateError('disk')),
        throwsStateError);
    expect(controller.isBusy(1), isFalse);
    expect(await controller.run(1, () async {}), isTrue);
  });

  test('disposal during an action does not notify disposed listeners',
      () async {
    final blocked = Completer<void>();
    final controller = TorrentTaskController(loadTasks: () async => []);
    final action = controller.run(1, () => blocked.future);
    controller.dispose();
    blocked.complete();
    await action;
  });

  test('initialization pause survives JSON parsing and can resume', () {
    final paused = task('initializing', initializingPaused: true);
    expect(paused.isPaused, isTrue);
    expect(paused.canResume, isTrue);
    expect(paused.isActive, isFalse);
    expect(paused.displayState, '已暂停');
    expect(paused.copyWith(files: []).isPaused, isTrue);
  });

  test(
      'error offers retry; a finished seeding task can pause without counting as downloading',
      () {
    expect(task('error').canResume, isTrue);
    expect(task('error').toggleLabel, '重试');
    final seeding = task('live', finished: true);
    expect(seeding.isActive, isFalse);
    expect(seeding.canResume, isFalse);
    expect(seeding.toggleLabel, '暂停做种');
    expect(task('paused', finished: true).toggleLabel, '继续做种');
    expect(task('live').canPlay, isTrue);
    expect(task('initializing').canPlay, isFalse);
  });
}
