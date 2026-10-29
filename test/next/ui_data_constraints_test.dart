import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/chat/turn_boundaries.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/capability.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/ui_data/metadata_facts.dart';
import 'package:nipaplay/next/ui_data/library_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';
import 'package:path/path.dart' as ppath;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late UiDataService service;
  late Harness harness;
  late FakeExecutor executor;
  late FakeExecutor helperExecutor;
  late StateSources sources;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('ui-data-constraints-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor();
    helperExecutor = FakeExecutor(type: 'agent.helper');
    engine = TaskEngine(store: store, ownerDeviceId: 'fixture', executors: [
      executor,
      helperExecutor,
      FakeExecutor(type: 'download', onExecute: (c) => c.succeed(verified())),
    ]);
    await engine.start();
    final media = MediaService(
        store: IdentityStore(store.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    sources = StateSources();
    service = UiDataService(
        media,
        engine,
        StateCapability([
          StateView(
              name: 'library.files',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (offset, limit) async => [])
        ]),
        sources,
        root,
        MemoryVault());
    harness = Harness([UiDataCapability(service)]);
    for (final id in ['w1', 'w2'])
      await store.database.insert('media_entities', {
        'id': id,
        'kind': 'work',
        'attributes': jsonEncode({'title': id == 'w1' ? '葬送的芙莉莲' : '孤独摇滚！'})
      });
    await File(ppath.join(root.path, 'journal.jsonl'))
        .writeAsString('${jsonEncode({
          'event': 'chat.turn_boundary',
          'origin': 'harness_cli:chat:fixture',
          'threadId': 'thread',
          'turnId': 'turn',
          'phase': 'started'
        })}\n');
  });
  tearDown(() async {
    await service.close();
    await engine.close();
    await root.delete(recursive: true);
  });
  Future<Outcome> call(String action, JsonMap input) => harness.invokeJson(
      action, input, Invocation(origin: 'harness_cli:chat:fixture'));

  test('home resolves only the Classic locators it was given', () async {
    final locator = ppath.join(root.path, 'media', 'Classic episode.mkv');
    await store.database.insert('media_entities', {
      'id': 'release-home',
      'kind': 'release',
      'parent_id': 'w1',
      'attributes': jsonEncode({'title': '第一季'})
    });
    await store.database.insert('media_entities', {
      'id': 'episode-home',
      'kind': 'episode',
      'parent_id': 'release-home',
      'attributes': jsonEncode({'title': '第一集', 'number': '1'})
    });
    await store.database.insert('media_entities', {
      'id': 'file-home',
      'kind': 'file',
      'attributes': jsonEncode({
        'probe': {'durationMs': 1440000}
      })
    });
    await store.database.insert('media_file_episodes', {
      'file_id': 'file-home',
      'episode_id': 'episode-home',
      'relation': 'exact',
      'ordinal': 0
    });
    await store.database.insert('media_locations', {
      'id': 'location-home',
      'file_id': 'file-home',
      'source': 'local',
      'owner_device_id': 'fixture',
      'locator': locator,
      'available': 1
    });
    sources.continueWatching = () => [
          {'filePath': locator, 'watchProgress': .4}
        ];
    sources.history = () => [
          {'filePath': locator, 'watchProgress': .4}
        ];

    final home = await service.home();
    final shelf = home.shelves
        .singleWhere((shelf) => shelf.kind == UiShelfKind.continueWatching);
    expect(shelf.items.single.work.workId, 'w1');
    expect(shelf.items.single.episode?.episodeId, 'episode-home');
  });

  test('task remains readable after its source work disappears', () async {
    service.libraryData = LibraryDataService(service);
    final job = await engine.submit(
        type: 'agent.helper',
        title: '来源任务',
        input: {
          'workId': sourceEntityId('work', 'jellyfin:missing', 'missing')
        });
    final context = await helperExecutor.entered.future;
    final task = (await service.tasks().first).single;
    expect(task.taskId, job.jobId);
    expect(task.type, 'agent.helper');
    expect(task.artwork, isNull);
    await context.succeed(
        JobReceipt(verification: VerificationLevel.verified, details: {}));
  });

  test('episode observations use latest position and exclude scan timestamps',
      () async {
    await store.database.insert('media_entities', {
      'id': 'r-progress',
      'kind': 'release',
      'parent_id': 'w1',
      'attributes': '{}'
    });
    await store.database.insert('media_entities', {
      'id': 'e-progress',
      'kind': 'episode',
      'parent_id': 'r-progress',
      'attributes': jsonEncode({'number': '1'})
    });
    JsonMap file(String id, int position, int duration, String at) => {
          'fileId': id,
          'episodeId': 'e-progress',
          'attributes': '{}',
          'startMs': 100,
          'endMs': 1100,
          'progress': {
            'positionMs': position,
            'durationMs': duration,
            'progress': position / 1100,
            'lastWatchedAt': at
          }
        };
    var episodes = await service.localEpisodes('w1',
        files: LocalFiles([file('scan', 0, 0, '2026-10-26T20:00:00Z')]));
    expect(episodes.single.lastPlayedAt, isNull);
    episodes = await service.localEpisodes('w1',
        files: LocalFiles([
          file('old', 900, 1100, '2026-10-25T20:00:00Z'),
          file('new', 500, 1100, '2026-10-26T20:00:00Z'),
        ]));
    expect(episodes.single.position, const Duration(milliseconds: 400));
    expect(episodes.single.progress, .4);
    expect(episodes.single.lastPlayedAt, DateTime.utc(2026, 10, 26, 20));
  });

  test(
      'a download whose work is not known goes by its own name, never its hash',
      () async {
    const release =
        '[LoliHouse] Sousou no Frieren - 05 [WebRip 1080p HEVC-10bit AAC][简繁内封字幕]';
    for (final title in [
      release,
      '葬送的芙莉莲 05.torrent',
      'c9e15763f722f23e98a29decdfae341b98d53056',
      'C9E15763F722F23E98A29DECDFAE341B98D53056.torrent',
    ]) {
      await engine.submit(type: 'download', title: title);
    }
    final tasks = await service.tasks().first;
    expect(
        [for (final t in tasks) t.title],
        unorderedEquals([
          '下载 $release',
          '下载 葬送的芙莉莲 05',
          '下载',
          '下载',
        ]));
    expect({for (final t in tasks) t.action}, {'下载'});
    expect([for (final t in tasks) t.workTitle].nonNulls, isEmpty,
        reason: 'a download is not a work');
  });

  for (final resume in [false, true]) {
    test('task stream reconciles completion before '
        '${resume ? 'resuming' : 'starting'} observation', () async {
      if (resume) await service.start();
      final job = await engine.submit(type: executor.type, title: '下载恢复');
      final context = await executor.entered.future;
      await context.report(
          progress: JobProgress(completed: 67, total: 100, unit: 'bytes'));
      final tasks = StreamIterator(service.tasks());
      addTearDown(tasks.cancel);
      expect(await tasks.moveNext(), isTrue);
      expect(tasks.current.single.state, UiTaskState.running);
      expect(tasks.current.single.progress, .67);

      if (resume) await service.pause();
      await context.succeed(verified());
      expect((await engine.get(job.jobId)).state, JobState.succeeded);
      await service.start();

      // No further engine event is needed to clear the old progress.
      expect(await tasks.moveNext().timeout(const Duration(seconds: 2)), isTrue);
      expect(tasks.current.single.state, UiTaskState.finished);
      expect(tasks.current.single.progress, 1);
    });
  }

  test('the live task list decodes only a bounded recent window', () async {
    final ids = <String>[];
    for (var i = 0; i < 80; i++) {
      final job = await engine.submit(type: 'download', title: 'window-$i');
      ids.add(job.jobId);
      await untilState(engine, job.jobId, JobState.succeeded);
    }
    final tasks = await service.tasks().first;
    expect(tasks, hasLength(64));
    expect(tasks.map((task) => task.taskId), contains(ids.last));
    expect(tasks.map((task) => task.taskId), isNot(contains(ids.first)));
  });

  test('helper cards and tasks retain thread, summary and unknown progress',
      () async {
    final job =
        await engine.submit(type: 'agent.helper', title: '补齐弹幕', input: {
      'parentThreadId': 'parent'
    }, details: {
      'threadId': 'helper-thread',
      'startedAt': '2026-10-12T00:00:00Z',
      'currentActivity': '正在整理弹幕',
      'source': 'codexNative',
    });
    final context = await helperExecutor.entered.future;
    final task = (await service.tasks().first).single;
    expect(task.kind, UiTaskKind.helper);
    expect(task.type, 'agent.helper');
    expect(task.source, 'codexNative');
    expect(task.title, '补齐弹幕');
    expect(task.threadId, 'helper-thread');
    expect(task.parentThreadId, 'parent');
    expect(task.currentActivity, '正在整理弹幕');
    expect(task.progress, isNull);
    await File(ppath.join(root.path, 'journal.jsonl')).writeAsString(
        '${jsonEncode({
              'event': 'chat.turn_boundary',
              'origin': 'harness_cli:helper:${job.jobId}',
              'threadId': 'helper-thread',
              'turnId': 'helper-turn',
              'phase': 'started',
            })}\n',
        mode: FileMode.append);
    expect(
        await harness.invokeJson(
            'ui.present',
            {
              'cards': [
                {'kind': 'task', 'taskId': job.jobId}
              ]
            },
            Invocation(origin: 'harness_cli:helper:${job.jobId}')),
        isA<Completed>());
    expect(await service.cards(threadId: 'parent'), isEmpty);
    expect(await service.cards(threadId: 'helper-thread'), hasLength(1));
    await context.succeed(JobReceipt(
        verification: VerificationLevel.verified,
        details: {'summary': '九集已检查'}));
    final finished = (await service.tasks().first).single;
    expect(finished.summary, '九集已检查');
    expect(finished.progress, isNull);
  });

  test(
      'artwork batches keep provenance and source files; invalid batch cannot edit metadata',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffaa4422), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 48);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File(ppath.join(root.path, 'input.png'));
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    JsonMap entry(String id, String kind) => {
          'entityId': id,
          'kind': kind,
          'file': file.path,
          'source': {
            'label': 'fixture source',
            'url': 'https://example.test/art'
          }
        };
    final before = await store.database.query('media_metadata_edits');
    expect(
        await call('media.artwork.set', {
          'entries': [entry('w1', 'poster'), entry('w2', 'still')]
        }),
        isA<Failed>());
    expect(await store.database.query('media_metadata_edits'), before);
    expect(
        await call('media.artwork.set', {
          'entries': [
            {...entry('w1', 'poster'), 'url': 'https://example.test/a'}
          ]
        }),
        isA<Failed>());
    expect(await store.database.query('media_metadata_edits'), before);
    final saved = await call('media.artwork.set', {
      'entries': [entry('w1', 'poster'), entry('w1', 'logo')]
    });
    expect(saved, isA<Completed>());
    final receipt = (saved as Completed).value.toJson()['entries'] as List;
    await file.delete();
    final work = (await service.work('w1'))!;
    expect(await File(work.artwork.poster!).exists(), true);
    expect(receipt.first['path'], work.artwork.poster);
    expect(receipt.first['sha256'], hasLength(64));
    expect(work.artwork.tint, 0xffaa4422);
    final edits = await store.database.query('media_metadata_edits');
    expect(edits, hasLength(2));
    expect(
        edits.every((e) =>
            e['origin'] == 'harness_cli:chat:fixture' &&
            e['invocation_id'] != null),
        true);
    final metadata =
        (await service.media.store.mergedMetadata('w1'))['fields'] as Map;
    expect((metadata['artwork.poster'] as Map)['source'],
        {'label': 'fixture source', 'url': 'https://example.test/art'});
    final facts = await service.metadataFacts('w1');
    expect((facts['fields'] as Map)['poster']['path'], work.artwork.poster);
    expect(facts['heroImage'], 'poster');
    await service.media.store.overrideField(
        'w1', 'overview', '中文简介', Invocation(origin: 'mcp'),
        language: 'zh-CN');
    expect(
        ((await service.metadataFacts('w1'))['fields'] as Map)['overview']
            ['language'],
        'zh-CN');
    await service.media.store.overrideField(
        'w1', 'overview', 'English synopsis', Invocation(origin: 'mcp'));
    expect(
        ((await service.metadataFacts('w1'))['fields'] as Map)['overview']
            ['language'],
        'unknown');
  });

  test(
      'shelves validate every reference before replacement; removal keeps facts',
      () async {
    final original = {
      'placement': 'shelf',
      'id': 'tonight',
      'title': '适合今晚',
      'items': [
        {'workId': 'w1', 'note': '今晚看一集。'}
      ]
    };
    expect(await call('ui.shelves.put', original), isA<Completed>());
    final saved = await store.database.query('ui_shelves');
    expect(
        await call('ui.shelves.put', {
          ...original,
          'items': [
            {'workId': 'w2'},
            {'workId': 'missing'}
          ]
        }),
        isA<Failed>());
    expect(await store.database.query('ui_shelves'), saved);
    expect(await call('ui.shelves.put', {...original, 'note': 'job-secret-id'}),
        isA<Failed>());
    expect(await store.database.query('ui_shelves'), saved);
    await service.removeShelf('tonight');
    expect(await store.database.query('ui_shelves'), isEmpty);
    final facts = await store.database.query('body_changes',
        where: 'type=?', whereArgs: ['ui.shelf_removed']);
    expect(facts.single['actor'], 'user');
    expect(decodeMediaJson(facts.single['facts'])['entityIds'], ['w1']);
    expect(await store.database.query('media_entities'), hasLength(2));
  });

  test('removing one shelf item keeps the other and records the removed work',
      () async {
    await call('ui.shelves.put', {
      'placement': 'shelf',
      'id': 'two',
      'title': '今晚看什么',
      'items': [
        {'workId': 'w1'},
        {'workId': 'w2'}
      ]
    });
    await service.removeShelf('two', workId: 'w1');
    final shelf = decodeMediaJson(
        (await store.database.query('ui_shelves')).single['payload']);
    expect(shelf['items'], [
      {'workId': 'w2'}
    ]);
    final event = (await store.database.query('body_changes',
            where: 'type=?', whereArgs: ['ui.shelf_removed']))
        .single;
    expect(event['actor'], 'user');
    expect(decodeMediaJson(event['facts'])['entityIds'], ['w1']);
    expect(await call('ui.shelves.remove', {'id': 'two', 'workId': 'w1'}),
        isA<Failed>());
    expect(
        await store.database.query('body_changes',
            where: 'type=?', whereArgs: ['ui.shelf_removed']),
        hasLength(1));
  });

  test('ui.present takes the current turn from the chat host, not the journal',
      () async {
    final journal = File(ppath.join(root.path, 'journal.jsonl'));
    Map<String, Object?> boundary(String phase) => {
          'event': 'chat.turn_boundary',
          'origin': 'harness_cli:chat:memory',
          'threadId': 'thread-m',
          'turnId': 'turn-m',
          'phase': phase,
        };
    Future<Outcome> present() => harness.invokeJson(
        'ui.present',
        {
          'cards': [
            {'kind': 'work', 'workId': 'w1'}
          ]
        },
        Invocation(origin: 'harness_cli:chat:memory'));
    await TurnBoundaries.write(journal, boundary('started'));
    await journal.delete();
    final shown = await present();
    expect(shown, isA<Completed>());
    expect((shown as Completed).value.toJson()['turnId'], 'turn-m');
    await TurnBoundaries.write(journal, boundary('completed'));
    expect(await present(), isA<Failed>());
  });

  test('card batches reject missing references and supplied state atomically',
      () async {
    expect(
        await call('ui.present', {
          'cards': [
            {'kind': 'work', 'workId': 'w1'},
            {'kind': 'task', 'taskId': 'missing'}
          ]
        }),
        isA<Failed>());
    expect(await store.database.query('ui_presentations'), isEmpty);
    expect(
        await call('ui.present', {
          'cards': [
            {
              'kind': 'preparation',
              'title': '准备好了',
              'steps': [
                {'label': '下载', 'taskId': 'missing', 'state': 'done'}
              ]
            }
          ]
        }),
        isA<Failed>());
    expect(await store.database.query('ui_presentations'), isEmpty);
    expect(await call('ui.present', {'cards': []}), isA<Failed>());
    final external = await harness.invokeJson(
        'ui.present',
        {
          'cards': [
            {'kind': 'work', 'workId': 'w1'}
          ]
        },
        Invocation(origin: 'harness_cli'));
    expect(external, isA<Failed>());
    await File(ppath.join(root.path, 'journal.jsonl')).writeAsString(
        '${jsonEncode({
              'event': 'chat.turn_boundary',
              'origin': 'harness_cli:chat:fixture',
              'threadId': 'thread',
              'turnId': 'turn',
              'phase': 'completed'
            })}\n',
        mode: FileMode.append);
    expect(
        await call('ui.present', {
          'cards': [
            {'kind': 'work', 'workId': 'w1'}
          ]
        }),
        isA<Failed>());
  });

  test('choices offer distinct answers and read back as a choices card',
      () async {
    Future<Outcome> present(Map<String, Object?> card) => call('ui.present', {
          'cards': [card]
        });
    expect(
        await present({
          'kind': 'choices',
          'options': [
            {'label': '只有一个'}
          ]
        }),
        isA<Failed>());
    expect(
        await present({
          'kind': 'choices',
          'options': [
            {'label': '同名'},
            {'label': '同名'}
          ]
        }),
        isA<Failed>());
    expect(
        await present({
          'kind': 'choices',
          'question': '要哪个版本？',
          'options': [
            {'label': 'BD 合集', 'detail': '1080p · 8 GB', 'recommended': true},
            {'label': '先来一集'}
          ]
        }),
        isA<Completed>());
    final card = (await service.cards(threadId: 'thread', turnId: 'turn'))
        .single as UiChoicesCard;
    expect(card.question, '要哪个版本？');
    expect(card.options.map((o) => o.label), ['BD 合集', '先来一集']);
    expect(card.options.first.recommended, isTrue);
    expect(card.options.last.detail, isNull);
  });

  test('presentation stores references, preserves task receipts, and reopens',
      () async {
    final job = await engine.submit(type: 'test', title: 'private job-id');
    final context = await executor.entered.future;
    final input = {
      'cards': [
        {
          'kind': 'preparation',
          'title': '正在准备',
          'workId': 'w1',
          'steps': [
            {'label': '下载', 'taskId': job.jobId}
          ]
        }
      ]
    };
    expect(await call('ui.present', input), isA<Completed>());
    final saved = await store.database.query('ui_presentations');
    expect(jsonDecode(saved.single['cards'] as String), input['cards']);
    await context.succeed(verified(details: {'unchangedReceipt': true}));
    executor.release.complete();
    final receipt = (await engine.get(job.jobId)).receipt!.toJson();
    final card = (await service.cards(threadId: 'thread', turnId: 'turn'))
        .single as UiPreparationCard;
    expect(card.steps.single.state, UiStepState.done);
    expect(card.steps.single.progress, 1);
    expect((await engine.get(job.jobId)).receipt!.toJson(), receipt);
    await service.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [FakeExecutor()]);
    await engine.start();
    final media = MediaService(
        store: IdentityStore(store.database, 'fixture'),
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    final sources = StateSources();
    service = UiDataService(
        media,
        engine,
        StateCapability([
          StateView(
              name: 'library.files',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (offset, limit) async => [])
        ]),
        sources,
        root,
        MemoryVault());
    expect(await store.database.query('ui_presentations'), saved);
    expect((await service.cards(threadId: 'thread')).single,
        isA<UiPreparationCard>());
    expect((await engine.get(job.jobId)).receipt!.toJson(), receipt);
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'a turn shows an identical card once; results say so and name the conversation',
      () async {
    Future<JsonMap> present(List<Map<String, Object?>> cards) async {
      final outcome = await call('ui.present', {'cards': cards});
      return ((outcome as Completed).value as dynamic).toJson() as JsonMap;
    }

    final first = await present([
      {'kind': 'work', 'workId': 'w1'}
    ]);
    expect(first['conversation'], 'main');
    expect(first['cards'], [
      {'index': 0, 'alreadyShown': false}
    ]);
    final again = await present([
      {'kind': 'work', 'workId': 'w1'},
      {'kind': 'work', 'workId': 'w2'},
      {'kind': 'work', 'workId': 'w2'},
    ]);
    expect(again['cards'], [
      {'index': 0, 'alreadyShown': true},
      {'index': 1, 'alreadyShown': false},
      {'index': 2, 'alreadyShown': true},
    ]);
    await present([
      {'kind': 'work', 'workId': 'w1'}
    ]);
    expect(await store.database.query('ui_presentations'), hasLength(3));
    final shown = await service.cards(threadId: 'thread', turnId: 'turn');
    expect(
        [for (final c in shown) (c as UiWorkCard).work.workId], ['w1', 'w2']);

    Map<String, Object?> choices(String second) => {
          'kind': 'choices',
          'options': [
            {'label': '清掉'},
            {'label': second}
          ]
        };
    expect((await present([choices('留着')]))['cards'], [
      {'index': 0, 'alreadyShown': false}
    ]);
    expect((await present([choices('先不管')]))['cards'], [
      {'index': 0, 'alreadyShown': false}
    ]);
    expect((await present([choices('留着')]))['cards'], [
      {'index': 0, 'alreadyShown': true}
    ]);
    expect(
        (await service.cards(threadId: 'thread', turnId: 'turn'))
            .whereType<UiChoicesCard>(),
        hasLength(2));

    // The same work in another turn is shown there.
    await File(ppath.join(root.path, 'journal.jsonl')).writeAsString(
        '${jsonEncode({
              'event': 'chat.turn_boundary',
              'origin': 'harness_cli:chat:fixture',
              'threadId': 'thread',
              'turnId': 'turn2',
              'phase': 'started'
            })}\n',
        mode: FileMode.append);
    expect(
        (await present([
          {'kind': 'work', 'workId': 'w1'}
        ]))['cards'],
        [
          {'index': 0, 'alreadyShown': false}
        ]);
    expect(
        await service.cards(threadId: 'thread', turnId: 'turn2'), hasLength(1));
    expect((await service.cards(threadId: 'thread')).whereType<UiWorkCard>(),
        hasLength(3));
  });

  test('a helper thread reports its cards went to the subagent conversation',
      () async {
    final job = await engine.submit(
        type: 'agent.helper',
        title: '清理残留',
        input: {'parentThreadId': 'thread'},
        details: {'threadId': 'helper-thread', 'source': 'codexNative'});
    await helperExecutor.entered.future;
    for (final origin in [
      'harness_cli:helper:${job.jobId}',
      'codex_native:helper-thread'
    ]) {
      await File(ppath.join(root.path, 'journal.jsonl')).writeAsString(
          '${jsonEncode({
                'event': 'chat.turn_boundary',
                'origin': origin,
                'threadId': 'helper-thread',
                'turnId': 'helper-turn',
                'phase': 'started'
              })}\n',
          mode: FileMode.append);
      final outcome = await harness.invokeJson(
          'ui.present',
          {
            'cards': [
              {'kind': 'work', 'workId': 'w1'}
            ]
          },
          Invocation(origin: origin));
      final result =
          ((outcome as Completed).value as dynamic).toJson() as JsonMap;
      expect(result['conversation'], 'subagent');
      expect(result['threadId'], 'helper-thread');
    }
  });
}
