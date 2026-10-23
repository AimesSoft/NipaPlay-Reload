import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/state/activity_invocations.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_test_support.dart';
import 'media_test_support.dart';
import 'support/journal_fixture.dart';
import 'support/main_thread_probe.dart';

const _golden = 'test/next/fixtures/activity_journal_expected.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  NextCore? core;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('next-activity-journal-');
  });
  tearDown(() async {
    await core?.close();
    core = null;
    await root.delete(recursive: true);
  });

  Future<NextCore> start() async {
    final started = core = NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => false,
        loadImportedKeys: () async => {},
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    await started.ready;
    await started.harnessLocation.setPath('${root.path}/harness');
    // A task event that names the fixture's write but has no origin itself;
    // 动态 finds the origin through the invocation.
    final at = DateTime.utc(2026, 10, 1, 9);
    final job = Job(
        jobId: 'fixture-job',
        type: 'library.scan',
        title: 'Fixture scan',
        state: JobState.succeeded,
        phase: 'done',
        progress: JobProgress(completed: 1, unit: 'files'),
        createdAt: at,
        updatedAt: at,
        ownerDeviceId: 'fixture-device',
        revision: 0,
        input: {},
        checkpoint: {},
        details: {},
        receipt: JobReceipt(
            verification: VerificationLevel.verified,
            details: {'fileIds': ['file-fixture']}));
    final db = started.media.service.store.database;
    await SqliteJobStore.fromDatabase(db).commit(
        job,
        JobEvent(
            jobId: job.jobId,
            revision: 0,
            kind: 'submitted',
            at: at,
            snapshot: job.toJson()),
        expectedRevision: null);
    await db.update('job_events', {'origin': null, 'invocation_id': fixtureWriteId},
        where: 'job_id=?', whereArgs: [job.jobId]);
    await db.delete('task_origins', where: 'job_id=?', whereArgs: [job.jobId]);
    return started;
  }

  /// The rows 动态 derives from the journal (and the task event that leans
  /// on it), with this run's device ID made stable.
  Future<JsonMap> activity(NextCore core) async {
    final read = await core.state.views['activity']!.readAll!();
    return {
      'rows': [
        for (final row in read.rows)
          if (row['source'] == 'journal' || row['jobId'] == 'fixture-job')
            {
              ...row,
              if (row['deviceId'] == core.deviceId) 'deviceId': '<device>',
            }
      ],
      'warnings': read.warnings,
    };
  }

  test('动态 from an old journal is what reading the whole journal composed',
      () async {
    await writeJournalFixture(File('${root.path}/journal.jsonl'),
        fillerBytes: 400 << 10);
    final shown = await activity(await start());
    if (Platform.environment['NIPA_ACTIVITY_GOLDEN'] == 'write') {
      await File(_golden).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(shown)}\n');
    }
    expect(jsonEncode(shown),
        jsonEncode(jsonDecode(await File(_golden).readAsString())));
    expect((shown['rows'] as List).length, greaterThan(25));
  });

  test('an old journal rotated into archives reads the same', () async {
    final journal = File('${root.path}/journal.jsonl');
    await writeJournalFixture(journal, fillerBytes: 400 << 10);
    final lines = await journal.readAsLines();
    final archive = JournalAppender.archiveDirectory(journal);
    await archive.create();
    final cut = [lines.length ~/ 3, 2 * lines.length ~/ 3];
    await File('${archive.path}/journal-20261001T000000.000000Z.jsonl')
        .writeAsString('${lines.sublist(0, cut[0]).join('\n')}\n');
    await File('${archive.path}/journal-20261002T000000.000000Z.jsonl')
        .writeAsString('${lines.sublist(cut[0], cut[1]).join('\n')}\n');
    await journal.writeAsString('${lines.sublist(cut[1]).join('\n')}\n');
    expect(jsonEncode(await activity(await start())),
        jsonEncode(jsonDecode(await File(_golden).readAsString())));
  });

  Future<(List<int>, MainThreadProbe)> queries(NextCore core) async {
    final walls = <int>[];
    final probe = MainThreadProbe.start();
    for (var i = 0; i < 5; i++) {
      final clock = Stopwatch()..start();
      await core.state.views['activity']!.readAll!();
      walls.add(clock.elapsedMilliseconds);
      probe.mark('query $i');
    }
    probe.stop();
    return (walls..sort(), probe);
  }

  test('a 60 MB journal does not change what a 动态 query costs', () async {
    final empty = await start();
    await empty.activityInvocations.settled();
    final (baseline, _) = await queries(empty);
    await empty.close();
    core = null;
    await root.delete(recursive: true);
    root = await Directory.systemTemp.createTemp('next-activity-journal-');

    final journal = File('${root.path}/journal.jsonl');
    await writeJournalFixture(journal, fillerBytes: 60 << 20);
    // The one-time read of the old journal, on its own.
    final copy = Directory('${root.path}/backfill');
    await copy.create();
    await journal.copy('${copy.path}/journal.jsonl');
    final database = await openNextDatabase(copy, factory: databaseFactoryFfi);
    final backfillProbe = MainThreadProbe.start();
    final backfillClock = Stopwatch()..start();
    await ActivityInvocations(database, File('${copy.path}/journal.jsonl'))
        .settled();
    backfillClock.stop();
    backfillProbe.stop();
    await database.close();

    final started = await start();
    await started.activityInvocations.settled();
    final (walls, probe) = await queries(started);
    expect(jsonEncode(await activity(started)),
        jsonEncode(jsonDecode(await File(_golden).readAsString())));
    // ignore: avoid_print
    print('backfill of ${journal.lengthSync() >> 20} MB: '
        '${backfillClock.elapsedMilliseconds} ms, main $backfillProbe\n'
        '动态 query wall (ms, sorted): no journal $baseline, '
        '60 MB journal $walls\n$probe');
    // 动态 does not read journal.jsonl: what is in it no longer matters.
    await journal.writeAsString('{"event":"replaced"}\n');
    expect(jsonEncode(await activity(started)),
        jsonEncode(jsonDecode(await File(_golden).readAsString())));
    expect(walls[walls.length ~/ 2], lessThan(baseline[baseline.length ~/ 2] + 50));
    expect(probe.longestMs, lessThan(16));
    expect(backfillProbe.longestMs, lessThan(50));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
