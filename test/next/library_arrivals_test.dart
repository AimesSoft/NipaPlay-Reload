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

JsonMap _file(String name,
        {String? id, JsonMap? cause, String via = 'local_scan'}) =>
    {
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
  var enabled = true;

  Future<void> open() async {
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    download = FakeExecutor(type: 'download');
    helper = FakeExecutor(
        type: 'agent.helper',
        onExecute: (context) async {
          await release.future;
        });
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [download, helper]);
    await engine.start();
    followups = Followups(store.database, engine, location);
    followups.libraryEnabled = () => enabled;
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('library-arrivals-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    release = Completer<void>();
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
  Set<String> pathsOf(JsonMap row) => {
        for (final fact in factsOf(row)) (fact['data'] as Map)['path'] as String
      };
  Future<Job> askingHelper() =>
      engine.submit(type: 'agent.helper', title: 'asked', input: {
        'parentThreadId': 'original',
        'repository': root.path,
        'instruction': 'add the folder'
      });

  Future<JsonMap> causeForHelper() async => {
        'origin': 'harness_cli:helper:${(await askingHelper()).jobId}',
        'invocationId': 'roots-add',
      };

  Future<void> addForConversation(List<JsonMap> files) async {
    final cause = await causeForHelper();
    await add([
      for (final file in files) {...file, 'cause': cause}
    ]);
  }

  group('未由对话引入的文件', () {
    test('用户、应用及无法定位对话的调用不登记回访或启动助手', () async {
      await add([
        _file('scan', id: 'scan'),
        _file('history', id: 'history', via: 'classic_history'),
        _file('server', id: 'server', via: 'media_source'),
        _file('gui', cause: {'origin': 'gui', 'invocationId': 'ui'}),
        _file('unknown', cause: {
          'origin': 'harness_cli:chat:missing',
          'invocationId': 'call'
        }),
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(await followups.list(), isEmpty);
      expect(await engine.list(type: 'agent.helper'), isEmpty);
    });

    test('旧版本留下的后台批次取消，重启后也不派发', () async {
      await addForConversation([_file('old', id: 'old')]);
      final row = libraryRows(await followups.list()).single;
      row['batchKey'] = 'background';
      row['threadId'] = null;
      await store.database.update('followups', {'snapshot': jsonEncode(row)},
          where: 'id=?', whereArgs: [row['id']]);
      await followups.close();
      await engine.close();
      await open();
      await followups.libraryBatchEnded();
      await followups.sweep();
      final cancelled = libraryRows(await followups.list()).single;
      expect(cancelled['state'], 'cancelled');
      expect(cancelled['reason'], contains('no conversation'));
      expect(await engine.list(type: 'agent.helper'), hasLength(1));
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
      await followups.close();
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

  group('对话文件的批次', () {
    test('新文件延后静默期限，到期才冻结事实', () async {
      followups.libraryQuiet = const Duration(milliseconds: 200);
      await addForConversation([_file('a', id: 'file-a')]);
      await followups.sweep();
      var row = libraryRows(await followups.list()).single;
      expect(row['frozen'], isNot(true));
      final firstDue = DateTime.parse(row['deliverAfter'] as String);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await addForConversation([_file('b', id: 'file-b')]);
      await followups.sweep();
      row = libraryRows(await followups.list()).single;
      final due = DateTime.parse(row['deliverAfter'] as String);
      expect(due.isAfter(firstDue), true);
      expect(row['frozen'], isNot(true));
      final remaining = due.difference(DateTime.now().toUtc());
      if (!remaining.isNegative)
        await Future<void>.delayed(
            remaining + const Duration(milliseconds: 20));
      await followups.sweep();
      row = libraryRows(await followups.list()).single;
      expect(row['frozen'], true);
      expect(pathsOf(row), {'/library/a.mkv', '/library/b.mkv'});
    });

    test('持续到来的文件仍受首个文件的最长等待限制', () async {
      followups.libraryQuiet = const Duration(hours: 1);
      followups.libraryMaxWait = Duration.zero;
      await addForConversation([_file('a', id: 'file-a')]);
      await followups.sweep();
      expect(libraryRows(await followups.list()).single['frozen'], true);
    });

    test('超出上限分批，路径与文件身份重复均不再次登记', () async {
      followups.libraryBatchLimit = 2;
      await addForConversation([
        for (var i = 0; i < 5; i++) _file('f$i', id: 'file-$i'),
        _file('renamed', id: 'file-0'),
        _file('f1', id: 'another-id'),
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final rows = libraryRows(await followups.list());
      expect(rows.map((r) => factsOf(r).length), [2, 2, 1]);
      expect(rows.map((r) => r['frozen']), everyElement(true));
      expect(rows.expand(pathsOf).toSet(),
          {for (var i = 0; i < 5; i++) '/library/f$i.mkv'});
    });

    test('待发批次重启后保留，再次通告不重复登记', () async {
      await addForConversation(
          [_file('a', id: 'file-a'), _file('b', id: 'file-b')]);
      final id = libraryRows(await followups.list()).single['id'];
      await followups.close();
      await engine.close();
      await open();
      await addForConversation(
          [_file('renamed', id: 'file-b'), _file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      await followups.sweep();
      final row = libraryRows(await followups.list()).single;
      expect(row['id'], id);
      expect(row['state'], 'ready');
      expect(row['frozen'], true);
      expect(pathsOf(row), {'/library/a.mkv', '/library/b.mkv'});
    });
  });

  group('files Nipa brought in', () {
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
      expect(rows, hasLength(1));
      final ours = rows.singleWhere((r) => r['threadId'] == 'original');
      expect(ours['origin'], cause['origin']);
      expect(ours['repository'], root.path);
      expect(pathsOf(ours), {'/library/a.mkv', '/library/b.mkv'});
      // No host in this fixture: it waits in line like any followup, unsent.
      expect(ours['state'], 'ready');
      expect(ours['frozen'], true);
      expect(ours['instruction'], contains('你发起的操作'));
      expect(await engine.list(type: 'agent.helper'), hasLength(1));
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

    test(
        'a file a download already returned to that conversation is not sent again',
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
      await addForConversation(
          [_file('dl0', id: 'file-dl0', via: 'download_import')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      final row = libraryRows(await followups.list()).single;
      expect(row['state'], 'cancelled');
      expect(row['reason'], contains('download return'));
    });

    test('a download file completed but not yet returned still counts',
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
      await addForConversation([
        _file('dl', id: 'file-dl', via: 'download_import'),
        _file('x', id: 'file-x')
      ]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(pathsOf(libraryRows(await followups.list()).single),
          {'/library/x.mkv'});
    });
  });

  group('the setting', () {
    test('off: nothing is sent and nothing is kept', () async {
      enabled = false;
      await addForConversation([_file('a', id: 'file-a')]);
      await followups.libraryBatchEnded();
      await followups.sweep();
      expect(await followups.list(), isEmpty);
    });

    test('turned off while a batch waits: that batch is not sent', () async {
      await addForConversation([_file('a', id: 'file-a')]);
      enabled = false;
      await followups.libraryBatchEnded();
      await followups.sweep();
      final row = libraryRows(await followups.list()).single;
      expect(row['state'], 'cancelled');
    });
  });

  group('what each file says', () {
    late MediaFixture fx;
    setUp(() async {
      fx = MediaFixture();
      await fx.open(sources: ['tmdb', 'dandanplay']);
    });
    tearDown(() async => fx.close());

    test(
        'episodes, where each link came from, TMDB, and the door it came in by',
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
        {
          'path': 'jellyfin://item-1',
          'via': 'media_source',
          'enteredAt': 'now'
        },
      ]);
      JsonMap byId(String id) => facts.singleWhere((f) => f['fileId'] == id);

      final tmdbFile = byId(withTmdb);
      expect(tmdbFile['via'], 'local_scan');
      expect((tmdbFile['works'] as List).single['identities'], {'tmdb': true});
      final episode = (tmdbFile['episodes'] as List).single as Map;
      expect(episode['identitySources'],
          [containsPair('source', 'explicit_binding')]);

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
      expect(source['source'],
          containsPair('mediaSource', containsPair('itemId', 'item-1')));
      expect(source['source'],
          containsPair('mediaSource', containsPair('sourceId', 'jf')));
    });

    test('只回访可定位到对话的调用，媒体源同步和普通扫描不唤起',
        () async {
      final cause = await causeForHelper();
      final sub = fx.identities.fileChanges
          .listen((file) => followups.libraryFileAdded(file));
      followups.describeLibraryFiles =
          (entries) => describeLibraryArrivals(fx.identities, entries);
      final tmdbFile = await fx.file('scan.mkv');
      await fx.call('media.identity.bind_batch', {
        'requestId': 'tmdb',
        'entries': [tmdbBinding(tmdbFile)]
      });
      // A listing a media source synced, caused by nobody's conversation.
      await fx.identities.ensureRemoteFile('smb://nas/show/01.mkv', 'nas',
          {'type': 'smb', 'itemId': 'show/01.mkv', 'name': '01.mkv'});
      // Something Nipa did from a conversation.
      await runZoned(() => fx.identities.ensureFile('/elsewhere/nipa.mkv'),
          zoneValues: {
            BodyChanges.invocationKey:
                Invocation(origin: cause['origin'] as String, id: 'her-call')
          });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await followups.libraryBatchEnded();
      await followups.sweep();

      final row = libraryRows(await followups.list()).single;
      expect(row['threadId'], 'original');
      expect(pathsOf(row), {'/elsewhere/nipa.mkv'});
      final described = factsOf(row).single['data'] as Map;
      expect(described['via'], 'path');
      expect(row['invocationId'], 'her-call');
    });

    test(
        'the invocation or task origin that was running is recorded as the cause',
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
