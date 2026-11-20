import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/events/signals.dart';
import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  late Completer<void> notification;
  late Completer<void> entered;
  setUp(() async {
    f = MediaFixture();
    await f.open(productionWrappers: true);
    notification = Completer<void>();
    entered = Completer<void>();
    BodySignals.emit = (_, __, ___) {
      if (!entered.isCompleted) entered.complete();
      return notification.future;
    };
  });
  tearDown(() async {
    BodySignals.emit = null;
    if (!notification.isCompleted) notification.complete();
    await f.close();
  });
  Future<String> refresh() async {
    final result = await f.service.submit('media.metadata.refresh', {
      'ref': {
        'provider': 'tmdb',
        'objectType': 'movie',
        'externalId': '9301',
        'scope': ''
      },
      'language': 'zh-CN',
    });
    return result.jobId;
  }

  Future<Job> terminal(String id) async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end)) {
      final job = await f.engine.get(id);
      if (job.state.isTerminal) return job;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Task did not finish');
  }

  test('partial scan reports all failed paths and confirmed disc structure',
      () async {
    BodySignals.emit = null;
    final root = await f.media.resolveSymbolicLinks();
    final disc = '$root/Disc';
    final marker = File('$disc/BDMV/MovieObject.bdmv');
    await marker.create(recursive: true);
    for (var index = 0; index < 11; index++) {
      final clip = File('$disc/menu/nested/bad-$index.mkv');
      await clip.create(recursive: true);
    }
    final good = File('$disc/CERTIFICATE/good.mkv');
    await good.create(recursive: true);
    await good.writeAsString('good');
    final ordinary = File('$root/ordinary/menu/bad.mkv');
    await ordinary.create(recursive: true);
    await Directory('$root/ordinary/BDMV/index.bdmv')
        .create(recursive: true);
    f.durationProbe = (path) async {
      if (path.contains('/menu/'))
        throw const Failure(FailureCode.unavailable, 'probe fixture failure');
      return 1000;
    };
    final job = await f.service.submit('media.scan', {'root': f.media.path});
    final done = await terminal(job.jobId);
    expect(done.state, JobState.succeeded);
    expect(done.error, isNull);
    final details = done.receipt!.details;
    expect(details['outcome'], 'partial');
    expect(details['indexed'], 1);
    expect(details['failedProbes'], 12);
    final errors = (details['probeErrors'] as List).cast<Map>();
    expect(errors, hasLength(12));
    final menuErrors = errors.where((error) => error['disc'] != null);
    expect(menuErrors, hasLength(11));
    expect(menuErrors.first['disc'], {
      'kind': 'bluray',
      'root': disc,
      'directory': '$disc/menu',
      'markers': [marker.path],
    });
    expect(
        errors.singleWhere((error) => error['path'] == ordinary.path)['disc'],
        isNull);
    expect(errors.first['error']['message'], 'probe fixture failure');
    expect((details['discFiles'] as List).single['disc']['directory'],
        '$disc/CERTIFICATE');
  });
  for (final outcome in ['success', 'failure']) {
    test('scan reports $outcome when no files are indexed', () async {
      BodySignals.emit = null;
      if (outcome == 'failure') {
        await File('${f.media.path}/bad.mkv').writeAsString('bad');
      }
      f.durationProbe = (_) async =>
          throw const Failure(FailureCode.unavailable, 'probe fixture failure');
      final job = await f.service.submit('media.scan', {'root': f.media.path});
      final done = await terminal(job.jobId);
      expect(done.state,
          outcome == 'failure' ? JobState.failed : JobState.succeeded);
      expect(done.receipt!.details['outcome'], outcome);
      expect(done.receipt!.details['indexed'], 0);
      expect(
          done.receipt!.details['failedProbes'], outcome == 'failure' ? 1 : 0);
    });
  }
  for (final cancel in [false, true]) {
    test('reconcile committed movie with blocked notification, cancel=$cancel',
        () async {
      final id = await refresh();
      await entered.future;
      final info = await f.call('task.get', {'jobId': id});
      expect((info['execution'] as Map)['reconciliationSupported'], true);
      expect((await f.engine.get(id)).checkpoint['snapshotId'], isNotNull);
      if (cancel) await f.engine.cancel(id);
      await f.call('task.reconcile', {'jobId': id});
      final done = await f.engine.get(id);
      expect(done.state, cancel ? JobState.cancelled : JobState.succeeded);
      expect(done.sideEffectCommitted, true);
      expect(done.receipt!.details['notificationStatus'], 'unconfirmed');
      expect(f.engine.isActive(id), false);
      expect(f.tmdb.requests, hasLength(1));
      notification.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await f.engine.get(id)).revision, done.revision);
    });
  }
  test('notification timeout does not strand a committed refresh', () async {
    final id = await refresh();
    await entered.future;
    final done = await terminal(id);
    expect(done.state, JobState.succeeded);
    expect(done.details['notificationError'], 'notification_timeout');
    expect(done.receipt!.details['refreshed'], true);
  });
  test('unfinished fetch cannot reconcile; cancellation prevents late writes',
      () async {
    final fetched = Completer<void>();
    final release = Completer<void>();
    f.tmdb.entered = fetched;
    f.tmdb.release = release;
    final id = await refresh();
    await fetched.future;
    await expectLater(f.engine.reconcile(id), throwsA(isA<Failure>()));
    expect((await f.engine.get(id)).state, JobState.running);
    await f.engine.cancel(id);
    expect((await terminal(id)).state, JobState.cancelled);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await f.jobs.database.query('media_snapshots'), isEmpty);
  });
}
