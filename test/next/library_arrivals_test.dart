import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/chat/helpers.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/media/library_arrivals.dart';
import 'package:nipaplay/next/state/change_history.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'media_test_support.dart';

JsonMap _file(String name, {String? id, JsonMap? cause, String via = 'local_scan'}) => {
      'path': '/library/$name.mkv',
      if (id != null) 'fileId': id,
      'via': via,
      if (cause != null) 'cause': cause,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late HarnessLocation location;
  late FakeExecutor download, helper;
  late Completer<void> release;
  final running = <String, JobContext>{};
  final dispatched = <JsonMap>[];
  Failure? unavailable;
  var enabled = true;

  void wire(Followups value) {
    value.libraryEnabled = () => enabled;
    value.backgroundDispatch =
        ({required jobId, required title, required instruction}) async {
      if (unavailable != null) throw unavailable!;
      try {
        await engine.submit(jobId: jobId, type: 'agent.helper', title: title, input: {
          'instruction': instruction,
          'background': true,
          'repository': root.path,
          'origin': 'application',
          'invocationId': jobId
        }, details: {
          'source': 'host',
          'background': true
        });
      } on Failure catch (error) {
        if (error.code == FailureCode.conflict) return jobId;
        rethrow;
      }
      dispatched.add({'jobId': jobId, 'title': title, 'instruction': instruction});
      return jobId;
    };
  }

  Future<void> open() async {
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    download = FakeExecutor(type: 'download');
    helper = FakeExecutor(type: 'agent.helper', onExecute: (context) async {
      running[context.job.jobId] = context;
      await release.future;
    });
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'fixture',
        executors: [download, helper]);
    await engine.start();
    followups = Followups(store.database, engine, location);
    wire(followups);
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('library-arrivals-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    release = Completer<void>();
    running.clear();
    dispatched.clear();
    unavailable = null;
    enabled = true;
    await open();
  });
  tearDown(() async {
    release.complete();
    await followups.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  Future<void> add(List<JsonMap> files) async {
    for (final file in files) {
      await followups.libraryFileAdded(file);
    }
  }

  List<JsonMap> libraryRows(List<JsonMap> rows) =>
      rows.where((r) => r['automatic'] == 'library').toList();
  List<JsonMap> factsOf(JsonMap row) =>
      ((row['trigger'] as Map)['facts'] as List).cast<JsonMap>();
  Set<String> pathsOf(JsonMap row) =>
      {for (final fact in factsOf(row)) (fact['data'] as Map)['path'] as String};
  Future<JobContext> entered(String id) async {
    for (var i = 0; i < 100 && running[id] == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return running[id]!;
  }

  group('files the user or the app brought in', () {
    test('one scan is one background dispatch and nothing for a conversation',
        () async {
      await add([
        _file('a', id: 'file-a'),
        _file('b', id: 'file-b', via: 'classic_history'),
        _file('c', id: 'file-c', cause: {'origin': 'gui', 'invocationId': 'ui'}),
      ]);
      await followups.sweep();
      // Files are still arriving as far as NipaPlay can tell: one batch, waiting.
      var rows = libraryRows(await followups.list());
      expect(rows, hasLength(1));
      expect(rows.single['state'], 'ready');
      expect(rows.single['threadId'], isNull);
      expect(factsOf(rows.single), hasLength(3));
      expect(dispatched, isEmpty);

      // The scan ends: the batch goes now.
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(dispatched, hasLength(1));
      expect(dispatched.single['title'], contains('3'));
      final instruction = dispatched.single['instruction'] as String;
      for (final name in ['a', 'b', 'c']) {
        expect(instruction, contains('/library/$name.mkv'));
      }
      expect(instruction, contains('classic_history'));
      expect(instruction, contains('下一步由你决定'));
      rows = libraryRows(await followups.list());
      expect(rows, hasLength(1), reason: 'no second row, no conversation row');
      expect(rows.single['state'], 'completed');
      expect(rows.single['threadId'], isNull);
      expect(rows.single['helperJobId'], dispatched.single['jobId']);
      // Delivering again changes nothing.
      await followups.sweep();
      expect(dispatched, hasLength(1));
    });

    test('files stop arriving, then the batch goes by itself', () async {
      followups.libraryQuiet = const Duration(milliseconds: 120);
      await add([_file('a', id: 'file-a')]);
      await followups.sweep();
      expect(dispatched, isEmpty);
      await add([_file('b', id: 'file-b')]);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await followups.sweep();
      expect(dispatched, isEmpty, reason: 'a new file restarts the quiet time');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await followups.sweep();
      expect(dispatched, hasLength(1));
      expect(dispatched.single['title'], contains('2'));
    });

    test('a long trickle is cut off at the cap counted from its first file', () async {
      followups.libraryQuiet = const Duration(hours: 1);
      followups.libraryMaxWait = Duration.zero;
      await add([_file('a', id: 'file-a')]);
      await followups.sweep();
      expect(dispatched, hasLength(1), reason: 'the cap since the first file');
    });

    test('a batch over the limit continues in the next one, nothing dropped',
        () async {
      followups.libraryBatchLimit = 2;
      await add([for (var i = 0; i < 5; i++) _file('f$i', id: 'file-$i')]);
      await followups.libraryBatchEnded();
      final rows = libraryRows(await followups.list());
      expect(rows.map((r) => factsOf(r).length), [2, 2, 1]);
      // One helper at a time: each batch waits for the one before.
      for (var i = 0; i < 3; i++) {
        await followups.sweep();
        expect(dispatched, hasLength(i + 1));
        await (await entered(dispatched.last['jobId'] as String))
            .succeed(verified(details: {'summary': 'done'}));
        await untilState(engine, dispatched.last['jobId'] as String,
            JobState.succeeded);
      }
      final all = dispatched.map((d) => d['instruction'] as String).join();
      for (var i = 0; i < 5; i++) {
        expect(RegExp('/library/f$i.mkv').allMatches(all), hasLength(1));
      }
    });

    test('the end of the helper is a task entry, with no return to a conversation',
        () async {
      await add([_file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final id = dispatched.single['jobId'] as String;
      await (await entered(id))
          .succeed(verified(details: {'summary': '已补上 TMDB 身份'}));
      await untilState(engine, id, JobState.succeeded);
      await followups.sweep();

      // What 动态 reads: the task's own events, with who started it.
      final events = await store.database
          .query('job_events', where: 'job_id=?', whereArgs: [id]);
      final last = jsonDecode(events.last['snapshot'] as String) as Map;
      expect(last['state'], 'succeeded');
      expect((last['receipt'] as Map)['details'], containsPair('summary', '已补上 TMDB 身份'));
      final origin = (await store.database
              .query('task_origins', where: 'job_id=?', whereArgs: [id]))
          .single;
      expect(origin['origin'], 'application');
      // And nothing was queued for any conversation.
      final rows = await followups.list();
      expect(rows.where((r) => r['threadId'] != null), isEmpty);
      expect(rows.where((r) => r['automatic'] != 'library'), isEmpty);
    });

    test('a background helper registers no return, an ordinary one does',
        () async {
      final helpers = Helpers()
        ..engine = engine
        ..followups = followups;
      followups.helpers = helpers;
      await expectLater(
          helpers.dispatchBackground(jobId: 'x', title: 't', instruction: 'i'),
          throwsA(isA<Failure>()));
      await engine.close();
      store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
      engine = TaskEngine(
          store: store, ownerDeviceId: 'fixture', executors: [helpers]);
      helpers.engine = engine;
      followups = Followups(store.database, engine, location)
        ..helpers = helpers;
      helpers.followups = followups;
      await engine.start();
      await engine.submit(type: 'agent.helper', title: 'quiet', input: {
        'instruction': 'i',
        'background': true,
        'repository': root.path
      });
      await engine.submit(type: 'agent.helper', title: 'asked', input: {
        'instruction': 'i',
        'parentThreadId': 'original',
        'repository': root.path
      });
      for (var i = 0; i < 100 && (await followups.list()).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final rows = await followups.list();
      expect(rows, hasLength(1));
      expect(rows.single['title'], 'asked');
    });
  });

  group('files Nipa brought in', () {
    Future<Job> askingHelper() => engine.submit(
            type: 'agent.helper',
            title: 'asked',
            input: {
              'parentThreadId': 'original',
              'repository': root.path,
              'instruction': 'add the folder'
            });

    test('they go back to the conversation that caused them, with no dispatch',
        () async {
      final asking = await askingHelper();
      final cause = {
        'origin': 'harness_cli:helper:${asking.jobId}',
        'invocationId': 'roots-add'
      };
      await add([
        _file('a', id: 'file-a', cause: cause),
        _file('b', id: 'file-b', cause: cause),
        _file('user', id: 'file-user'),
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();

      final rows = libraryRows(await followups.list());
      expect(rows, hasLength(2));
      final ours = rows.singleWhere((r) => r['threadId'] == 'original');
      expect(ours['origin'], cause['origin']);
      expect(ours['repository'], root.path);
      expect(pathsOf(ours), {'/library/a.mkv', '/library/b.mkv'});
      // No host in this fixture: it waits in line like any followup, unsent.
      expect(ours['state'], 'ready');
      expect(ours['frozen'], true);
      expect(ours['instruction'], contains('你发起的操作'));
      // The user's file is the background kind; Nipa's own never dispatched.
      expect(dispatched, hasLength(1));
      expect(dispatched.single['instruction'], contains('/library/user.mkv'));
      expect(dispatched.single['instruction'], isNot(contains('/library/a.mkv')));
    });

    test('a conversation that is busy keeps its batch queued, in order',
        () async {
      final asking = await askingHelper();
      final cause = {
        'origin': 'harness_cli:helper:${asking.jobId}',
        'invocationId': 'scan-1'
      };
      followups.libraryBatchLimit = 1;
      await add([
        _file('a', id: 'file-a', cause: cause),
        _file('b', id: 'file-b', cause: cause),
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final rows = libraryRows(await followups.list());
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['state']), ['ready', 'ready']);
      expect(rows.map((r) => r['reason']),
          everyElement(contains('Embedded chat host is not running')));
      expect(rows.map(pathsOf), [
        {'/library/a.mkv'},
        {'/library/b.mkv'}
      ]);
    });

    test('a file a download already returned to that conversation is not sent again',
        () async {
      final job = await engine.submit(type: 'download', title: 'CC0', input: {
        'infoHash': 'fixture',
        'returnTo': {
          'threadId': 'original',
          'repository': root.path,
          'origin': 'harness_cli:chat:fixture',
          'invocationId': 'download-call'
        }
      });
      final context = await download.entered.future;
      JsonMap done(int i) => {
            'objectId': '${job.jobId}:$i',
            'jobId': job.jobId,
            'index': i,
            'path': '/library/dl$i.mkv',
            'verification': 'verified',
            'isVideo': true,
            'imported': true,
            'local': true,
            'complete': true,
            'completedAt': DateTime.now().toUtc().toIso8601String(),
            'media': {'fileId': 'file-dl$i', 'workIds': []}
          };
      await context.report(checkpoint: {
        'completedFiles': [done(0)]
      });
      await followups.sweep();
      expect((await followups.list()).single['automatic'], 'download');

      final asking = await askingHelper();
      final here = {
        'origin': 'harness_cli:helper:${asking.jobId}',
        'invocationId': 'x'
      };
      await add([
        _file('dl0', id: 'file-dl0', via: 'download_import', cause: here),
        _file('other', id: 'file-other', cause: here),
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final rows = libraryRows(await followups.list());
      final ours = rows.single;
      expect(ours['threadId'], 'original');
      expect(pathsOf(ours), {'/library/other.mkv'});
      expect(dispatched, isEmpty);
    });

    test('a download return to some other conversation does not cover this one',
        () async {
      final job = await engine.submit(type: 'download', title: 'CC0', input: {
        'infoHash': 'fixture',
        'returnTo': {
          'threadId': 'elsewhere',
          'repository': root.path,
          'origin': 'harness_cli:chat:fixture',
          'invocationId': 'download-call'
        }
      });
      final context = await download.entered.future;
      await context.report(checkpoint: {
        'completedFiles': [
          {
            'objectId': '${job.jobId}:0',
            'jobId': job.jobId,
            'index': 0,
            'path': '/library/dl0.mkv',
            'verification': 'verified',
            'isVideo': true,
            'imported': true,
            'completedAt': DateTime.now().toUtc().toIso8601String(),
            'media': {'fileId': 'file-dl0'}
          }
        ]
      });
      await followups.sweep();
      final asking = await askingHelper();
      await add([
        _file('dl0', id: 'file-dl0', cause: {
          'origin': 'harness_cli:helper:${asking.jobId}',
          'invocationId': 'x'
        })
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(pathsOf(libraryRows(await followups.list()).single),
          {'/library/dl0.mkv'});
    });

    test('a batch of only downloaded files is not sent at all', () async {
      final job = await engine.submit(type: 'download', title: 'CC0', input: {
        'infoHash': 'fixture',
        'returnTo': {
          'threadId': 'original',
          'repository': root.path,
          'origin': 'harness_cli:chat:fixture',
          'invocationId': 'download-call'
        }
      });
      final context = await download.entered.future;
      await context.report(checkpoint: {
        'completedFiles': [
          {
            'objectId': '${job.jobId}:0',
            'jobId': job.jobId,
            'index': 0,
            'path': '/library/dl0.mkv',
            'verification': 'verified',
            'isVideo': true,
            'imported': true,
            'completedAt': DateTime.now().toUtc().toIso8601String(),
            'media': {'fileId': 'file-dl0'}
          }
        ]
      });
      await followups.sweep();
      await add([_file('dl0', id: 'file-dl0', via: 'download_import')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final row = libraryRows(await followups.list()).single;
      expect(row['state'], 'cancelled');
      expect(row['reason'], contains('download return'));
      expect(dispatched, isEmpty);
    });

    test('a download file completed but not yet returned still counts', () async {
      final job = await engine.submit(type: 'download', title: 'CC0', input: {
        'infoHash': 'fixture',
        'returnTo': {
          'threadId': 'original',
          'repository': root.path,
          'origin': 'harness_cli:chat:fixture',
          'invocationId': 'download-call'
        }
      });
      final context = await download.entered.future;
      await context.report(checkpoint: {
        'completedFiles': [
          {
            'objectId': '${job.jobId}:0',
            'jobId': job.jobId,
            'index': 0,
            'path': '/library/dl.mkv',
            'verification': 'verified',
            'isVideo': true,
            'imported': true,
            'media': {'fileId': 'file-dl'}
          }
        ]
      });
      await add([_file('dl', id: 'file-dl', via: 'download_import'), _file('x', id: 'file-x')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(dispatched, hasLength(1));
      expect(dispatched.single['instruction'], contains('/library/x.mkv'));
      expect(dispatched.single['instruction'], isNot(contains('file-dl')));
    });
  });

  group('while a helper is working', () {
    test('new files wait as the next batch, then go once, never twice', () async {
      await add([_file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final first = dispatched.single['jobId'] as String;
      final firstContext = await entered(first);

      await add([_file('b', id: 'file-b')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(dispatched, hasLength(1));
      var next = libraryRows(await followups.list())
          .singleWhere((r) => r['state'] == 'ready');
      expect(next['reason'], contains('still handling'));
      // More files join the waiting batch rather than starting a helper.
      await add([_file('c', id: 'file-c'), _file('a', id: 'file-a')]);
      await followups.sweep();
      next = libraryRows(await followups.list())
          .singleWhere((r) => r['state'] == 'ready');
      expect(pathsOf(next), {'/library/b.mkv', '/library/c.mkv'});

      await firstContext.succeed(verified(details: {'summary': 'ok'}));
      await untilState(engine, first, JobState.succeeded);
      // New files restarted the quiet time of the waiting batch.
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(dispatched, hasLength(2));
      final instruction = dispatched.last['instruction'] as String;
      expect(instruction, contains('/library/b.mkv'));
      expect(instruction, contains('/library/c.mkv'));
      expect(instruction, isNot(contains('/library/a.mkv')));
      await followups.sweep();
      expect(dispatched, hasLength(2));
    });

    test('with no helper available the files wait and are not lost', () async {
      unavailable = const Failure(FailureCode.unavailable, 'Chat host is not running.');
      await add([_file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      var row = libraryRows(await followups.list()).single;
      expect(row['state'], 'ready');
      expect(row['reason'], 'Chat host is not running.');
      unavailable = null;
      await followups.sweep();
      expect(dispatched, hasLength(1));
      row = libraryRows(await followups.list()).single;
      expect(row['state'], 'completed');
    });
  });

  group('the setting', () {
    test('off: nothing is sent and nothing is kept', () async {
      enabled = false;
      await add([_file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(await followups.list(), isEmpty);
      expect(dispatched, isEmpty);
    });

    test('turned off while a batch waits: that batch is not sent', () async {
      await add([_file('a', id: 'file-a')]);
      enabled = false;
      await followups.libraryBatchEnded();
      await followups.sweep();
      final row = libraryRows(await followups.list()).single;
      expect(row['state'], 'cancelled');
      expect(dispatched, isEmpty);
    });
  });

  group('restart', () {
    test('a waiting batch survives and is dispatched exactly once', () async {
      await add([_file('a', id: 'file-a'), _file('b', id: 'file-b')]);
      await followups.close();
      await engine.close();
      await open();
      await followups.libraryBatchEnded();
      await followups.sweep();
      await followups.sweep();
      expect(dispatched, hasLength(1));
      expect(dispatched.single['instruction'], contains('/library/a.mkv'));
      expect(dispatched.single['instruction'], contains('/library/b.mkv'));
    });

    test('files already reported are not reported again, even if announced again',
        () async {
      await add([_file('a', id: 'file-a'), _file('b', id: 'file-b')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(dispatched, hasLength(1));
      await followups.close();
      await engine.close();
      await open();
      await add([
        _file('a', id: 'file-a'),
        _file('renamed', id: 'file-b'),
        _file('b', id: 'file-b')
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(libraryRows(await followups.list()), hasLength(1));
      expect(dispatched, hasLength(1));
    });

    test('a dispatch whose record was lost does not start a second helper',
        () async {
      await add([_file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final id = dispatched.single['jobId'] as String;
      // The row is put back as if the process died before saving "completed".
      final row = libraryRows(await followups.list()).single;
      await store.database.update(
          'followups',
          {
            'state': 'ready',
            'snapshot': jsonEncode({...row, 'state': 'ready'}..remove('helperJobId'))
          },
          where: 'id=?',
          whereArgs: [row['id']]);
      await followups.sweep();
      expect(dispatched, hasLength(1));
      expect((await engine.list(type: 'agent.helper')).map((j) => j.jobId), [id]);
      expect(libraryRows(await followups.list()).single['state'], 'completed');
    });
  });

  group('what each file says', () {
    late MediaFixture fx;
    setUp(() async {
      fx = MediaFixture();
      await fx.open(sources: ['tmdb', 'dandanplay']);
    });
    tearDown(() async => fx.close());

    test('episodes, where each link came from, TMDB, and the door it came in by',
        () async {
      final added = <JsonMap>[];
      final sub = fx.identities.fileChanges.listen(added.add);
      final withTmdb = await fx.file('with-tmdb.mkv');
      final withoutTmdb = await fx.file('without-tmdb.mkv');
      final bare = await fx.file('bare.mkv');
      await fx.call('media.identity.bind_batch', {
        'requestId': 'tmdb',
        'entries': [tmdbBinding(withTmdb)]
      });
      await fx.call('media.identity.bind_batch', {
        'requestId': 'dandanplay',
        'entries': [dandanplayBinding(withoutTmdb)]
      });
      await sub.cancel();
      expect(added.map((f) => f['via']), everyElement('local_scan'));

      final remote = await fx.identities.ensureRemoteFile(
          'jellyfin://item-1', 'jf', {
        'type': 'jellyfin',
        'serverId': 'srv',
        'itemId': 'item-1',
        'name': 'Episode One'
      });
      final facts = await describeLibraryArrivals(fx.identities, [
        for (final file in added) {...file, 'enteredAt': 'now'},
        {'path': 'jellyfin://item-1', 'via': 'media_source', 'enteredAt': 'now'},
      ]);
      JsonMap byId(String id) => facts.singleWhere((f) => f['fileId'] == id);

      final tmdbFile = byId(withTmdb);
      expect(tmdbFile['via'], 'local_scan');
      expect((tmdbFile['works'] as List).single['identities'], {'tmdb': true});
      final episode = (tmdbFile['episodes'] as List).single as Map;
      expect(episode['identitySources'], [
        containsPair('source', 'explicit_binding')
      ]);

      final dandan = byId(withoutTmdb);
      expect((dandan['works'] as List).single['identities'], {'tmdb': false});
      expect(((dandan['episodes'] as List).single as Map)['identitySources'],
          isNotEmpty);

      final unlinked = byId(bare);
      expect(unlinked['episodes'], isEmpty);
      expect(unlinked['works'], isEmpty);

      final source = byId(remote);
      expect(source['path'], 'jellyfin://item-1');
      expect(source['via'], 'media_source');
      expect(source['source'], containsPair('mediaSource', containsPair('itemId', 'item-1')));
      expect(source['source'], containsPair('mediaSource', containsPair('sourceId', 'jf')));
    });

    test('a media source entry, and whoever caused it, reach the followup', () async {
      final sub = fx.identities.fileChanges.listen(
          (file) => followups.libraryFileAdded(file));
      followups.describeLibraryFiles =
          (entries) => describeLibraryArrivals(fx.identities, entries);
      final tmdbFile = await fx.file('scan.mkv');
      await fx.call('media.identity.bind_batch', {
        'requestId': 'tmdb',
        'entries': [tmdbBinding(tmdbFile)]
      });
      // A listing a media source synced, caused by nobody's conversation.
      await fx.identities.ensureRemoteFile('smb://nas/show/01.mkv', 'nas', {
        'type': 'smb',
        'itemId': 'show/01.mkv',
        'name': '01.mkv'
      });
      // Something Nipa did from a conversation.
      await runZoned(
          () => fx.identities.ensureFile('/elsewhere/nipa.mkv'),
          zoneValues: {
            BodyChanges.invocationKey: Invocation(
                origin: 'harness_cli:chat:fixture', id: 'her-call')
          });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await followups.libraryBatchEnded();
      await followups.sweep();

      expect(dispatched, hasLength(1));
      final instruction = dispatched.single['instruction'] as String;
      expect(instruction, contains('smb://nas/show/01.mkv'));
      expect(instruction, contains('media_source'));
      expect(instruction, contains('scan.mkv'));
      expect(instruction, contains('"tmdb":true'));
      expect(instruction, contains('identitySources'));
      // With no chat host to name a thread, her own call falls to the
      // background kind rather than being lost.
      expect(instruction, contains('/elsewhere/nipa.mkv'));
    });

    test('the invocation or task origin that was running is recorded as the cause',
        () async {
      final added = <JsonMap>[];
      final sub = fx.identities.fileChanges.listen(added.add);
      await runZoned(() => fx.identities.ensureFile('/a/one.mkv', via: 'x'),
          zoneValues: {
            BodyChanges.invocationKey:
                Invocation(origin: 'harness_cli:chat:s', id: 'call-1')
          });
      await fx.identities.ensureFile('/a/two.mkv');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(added.first['cause'],
          {'origin': 'harness_cli:chat:s', 'invocationId': 'call-1'});
      expect(added.first['via'], 'x');
      expect(added.last.containsKey('cause'), false);
      expect(added.last['via'], 'path');
    });
  });
}
