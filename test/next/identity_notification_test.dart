import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/events/signals.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open(productionWrappers: true);
  });
  tearDown(() async {
    BodySignals.emit = null;
    await f.close();
  });

  test('remote delivery cannot hold local event persistence; dedup stays atomic', () async {
    SharedPreferences.setMockInitialValues({HarnessLocation.storageKey: f.root.path});
    final location = HarnessLocation();
    final followups = Followups(f.jobs.database, f.engine, location);
    final entered = Completer<void>();
    final release = Completer<JsonMap>();
    followups.agentDevice = () => 'unreachable-peer';
    followups.deliverRemote = (_, __) {
      entered.complete();
      return release.future;
    };
    await followups.wake({'instruction': 'Report to the other device'}, Invocation(origin: 'fixture'));
    final sweep = followups.sweep();
    try {
      await entered.future.timeout(const Duration(seconds: 2));
      await Future.wait([
        followups.hookEvent('media.assets.changed', 'work-1', {}),
        followups.hookEvent('download.file_completed', 'same-file', {}),
        followups.hookEvent('download.file_completed', 'same-file', {}),
      ]).timeout(const Duration(seconds: 2));
      final rows = await f.jobs.database.query('followup_hook_events');
      expect(rows.where((r) => r['event'] == 'media.assets.changed'), hasLength(1));
      expect(rows.where((r) => r['event'] == 'download.file_completed'), hasLength(1));
      expect(release.isCompleted, false);
    } finally {
      release.complete({'accepted': true});
      await sweep;
      await followups.close();
      location.dispose();
    }
  });

  test('committed binding is readable during notification wait; timeout releases queue', () async {
    final file = await f.file('E01.mkv');
    final entered = Completer<void>();
    final release = Completer<void>();
    BodySignals.emit = (_, __, ___) {
      if (!entered.isCompleted) entered.complete();
      return release.future;
    };
    final binding = f.call('media.identity.bind_batch', {
      'requestId': 'notification-test', 'entries': [tmdbBinding(file)],
    });
    try {
      await entered.future.timeout(const Duration(seconds: 2));
      final queued = f.service.mutate(() async => 'next mutation ran');
      final receipt = await f.call('media.identity.operation', {'requestId': 'notification-test'});
      expect(receipt['commitStatus'], 'committed');
      expect((receipt['mutationQueue'] as Map)['waiting'], 1);
      final otherOrigin = await f.call('media.identity.operation',
          {'requestId': 'notification-test'}, origin: 'other');
      expect(otherOrigin['commitStatus'], 'not_observed');
      final result = await binding.timeout(const Duration(seconds: 7));
      expect(result['notificationStatus'], 'unconfirmed');
      expect(result['notificationError'], 'notification_timeout');
      expect(await queued, 'next mutation ran');
      expect(f.service.mutationStatus['active'], false);
      final saved = await f.call('media.identity.operation', {'requestId': 'notification-test'});
      expect((saved['receipt'] as Map)['notificationStatus'], 'unconfirmed');
      expect(await f.jobs.database.query('media_binding_operations'), hasLength(1));
    } finally {
      BodySignals.emit = null;
      release.complete();
      await binding;
    }
  });

  test('notification failure does not change a committed transaction into a write failure', () async {
    BodySignals.emit = (_, __, ___) async => throw StateError('fixture notification failure');
    final result = await BodySignals.transaction(f.jobs.database, (tx) async {
      await tx.execute('CREATE TABLE notification_fixture (value TEXT)');
      await tx.insert('notification_fixture', {'value': 'committed'});
      BodySignals.changed('media.assets.changed', 'fixture', {});
      return 'written';
    });
    expect(result, 'written');
    expect((await f.jobs.database.query('notification_fixture')).single['value'], 'committed');
    expect((BodySignals.deliveryStatus['recentUnconfirmed'] as List).last['error'], 'notification_failed');
  });
}
