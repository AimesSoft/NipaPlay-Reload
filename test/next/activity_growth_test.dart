import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/state/activity_invocations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// #1114: the interface's own polling (`ui.inbox.list` 171,572 rows,
/// 636 MB) grew next.db without bound.
void main() {
  sqfliteFfiInit();

  test('动态 keeps the interface actions, not the reads the viewer polls', () {
    bool shown(String action, Effect? effect) =>
        activityRecordsInvocation(action, conflict: false, effect: effect);
    for (final read in unshownInterfaceReads) {
      expect(shown(read, Effect.read), isFalse, reason: read);
    }
    expect(shown('ui.capture', Effect.read), isTrue);
    expect(shown('ui.open', Effect.write), isTrue);
    expect(shown('ui.shelves.put', Effect.write), isTrue);
    // A stored row: kept because it was shown when it was stored.
    expect(shown('ui.open', null), isTrue);
    expect(shown('discover.calendar', Effect.read), isTrue);
    expect(activityRecordsInvocation('ui.inbox.list', conflict: true), isTrue);
  });

  test('a polled read is no row and its journal line keeps no result', () {
    final line = {
      'invocationId': 'i1',
      'actionId': 'ui.inbox.list',
      'origin': 'gui',
      'effect': 'read',
      'status': 'completed',
      'startedAt': '2026-11-16T08:51:00.000Z',
      'elapsedMs': 3,
      'input': {'offset': 0, 'limit': 30},
      'result': {'items': []},
    };
    expect(activityInvocationRow(line), isNull);
    expect(activityInvocationRow({...line, 'actionId': 'ui.capture'}),
        isNotNull);
  });

  test(
      'upgrading removes the polled rows, keeps the others and gives the '
      'space back', () async {
    final root = await Directory.systemTemp.createTemp('next-activity-growth-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/next.db');
    var db = await openNextDatabase(root, factory: databaseFactoryFfi);
    final version = await db.getVersion();
    // What an earlier version left: ~40 MB of inbox polls and a few rows
    // 动态 shows.
    final result = jsonEncode({'items': List.filled(40, 'x' * 100)});
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (var i = 0; i < 10000; i++) {
        batch.insert('activity_invocations', {
          'invocation_id': 'poll-$i',
          'action_id': unshownInterfaceReads[i % unshownInterfaceReads.length],
          'origin': 'gui',
          'status': 'completed',
          'started_at': '2026-11-16T08:51:00.000Z',
          'elapsed_ms': 3,
          'input': '{}',
          'result': result,
        });
      }
      for (final action in ['ui.open', 'ui.capture', 'discover.calendar']) {
        batch.insert('activity_invocations', {
          'invocation_id': 'kept-$action',
          'action_id': action,
          'origin': 'harness_cli:chat:t',
          'status': 'completed',
          'started_at': '2026-11-16T08:52:00.000Z',
          'elapsed_ms': 3,
          'input': '{}',
          'result': '{"opened":true}',
        });
      }
      await batch.commit(noResult: true);
    });
    // Before the purge; the handover tables that follow it are created
    // idempotently.
    await db.setVersion(version - 2);
    await db.close();
    final before = file.lengthSync();
    expect(before, greaterThan(32 << 20));

    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(db.close);
    expect(await db.getVersion(), version);
    final rows = await db.query('activity_invocations',
        columns: ['action_id'], orderBy: 'action_id');
    expect(rows.map((r) => r['action_id']),
        ['discover.calendar', 'ui.capture', 'ui.open']);
    expect(
        (await db.rawQuery('PRAGMA freelist_count')).single.values.single, 0);
    expect(file.lengthSync(), lessThan(before ~/ 4));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a small amount of free space does not VACUUM at every start',
      () async {
    final root = await Directory.systemTemp.createTemp('next-activity-small-');
    addTearDown(() => root.delete(recursive: true));
    var db = await openNextDatabase(root, factory: databaseFactoryFfi);
    await db.execute('CREATE TABLE probe (v TEXT)');
    for (var i = 0; i < 50; i++) {
      await db.insert('probe', {'v': 'y' * 4000});
    }
    await db.delete('probe');
    final free = (await db.rawQuery('PRAGMA freelist_count')).single.values.single
        as int;
    expect(free, greaterThan(0));
    await db.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(db.close);
    expect(
        (await db.rawQuery('PRAGMA freelist_count')).single.values.single, free);
  });

  test('oversized result payloads are bounded while keeping summary fields',
      () {
    final huge = 'x' * (activityResultMaxBytes + 4096);
    final row = activityInvocationRow({
      'invocationId': 'big-1',
      'actionId': 'ui.open',
      'origin': 'gui',
      'effect': 'write',
      'status': 'completed',
      'startedAt': '2026-11-16T08:51:00.000Z',
      'elapsedMs': 4,
      'input': {},
      'result': {'opened': true, 'blob': huge},
    });
    expect(row, isNotNull);
    final encoded = row!['result'] as String;
    expect(encoded.length, lessThanOrEqualTo(activityResultMaxBytes));
    final decoded = jsonDecode(encoded) as Map;
    expect(decoded['opened'], isTrue);
    expect(decoded['_truncated'], isTrue);
    expect(decoded['_originalBytes'], greaterThan(activityResultMaxBytes));
  });

  test('retention pruning bounds activity_invocations to the newest rows',
      () async {
    final root = await Directory.systemTemp.createTemp('next-activity-prune-');
    addTearDown(() => root.delete(recursive: true));
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(db.close);
    final observer = ActivityInvocations(
      db,
      File('${root.path}/journal.jsonl'),
      maxRows: 5,
    );
    final harness = Harness([_OpenCapability()], observers: [observer]);
    for (var i = 0; i < 12; i++) {
      await harness.invokeJson(
          'ui.open', {'step': i}, Invocation(origin: 'gui', id: 'inv-$i'));
      // Give distinct started_at ordering deterministically.
      await db.update(
          'activity_invocations',
          {
            'started_at':
                DateTime.utc(2026, 11, 16, 8, i).toIso8601String(),
          },
          where: 'invocation_id=?',
          whereArgs: ['inv-$i']);
    }
    await observer.settled();
    final rows = await db.query('activity_invocations',
        columns: ['invocation_id'], orderBy: 'started_at ASC');
    expect(rows.map((r) => r['invocation_id']).toList(),
        ['inv-7', 'inv-8', 'inv-9', 'inv-10', 'inv-11']);
    await observer.close();
  });
}

final class _OpenCapability implements Capability {
  @override
  List<Action> get actions => [
        ClassicAction(
          const ActionSpec(
            id: 'ui.open',
            title: 'open',
            description: 'test write action',
            effect: Effect.write,
            input: ObjectSchema({}, additionalProperties: true),
            output: ObjectSchema({}, additionalProperties: true),
          ),
          (input, _) async => {'opened': true},
        ),
      ];
}
