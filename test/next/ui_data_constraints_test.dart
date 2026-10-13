import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/capability.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/ui_data/metadata_facts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late UiDataService service;
  late Harness harness;
  late FakeExecutor executor;
  late FakeExecutor helperExecutor;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('ui-data-constraints-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor();
    helperExecutor = FakeExecutor(type: 'agent.helper');
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [executor, helperExecutor]);
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
    harness = Harness([UiDataCapability(service)]);
    for (final id in ['w1', 'w2'])
      await store.database.insert('media_entities', {
        'id': id,
        'kind': 'work',
        'attributes': jsonEncode({'title': id == 'w1' ? '葬送的芙莉莲' : '孤独摇滚！'})
      });
    await File('${root.path}/journal.jsonl').writeAsString('${jsonEncode({
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

  test('helper cards and tasks retain thread, summary and unknown progress', () async {
    final job = await engine.submit(type: 'agent.helper', title: '补齐弹幕',
        input: {'parentThreadId': 'parent'}, details: {
          'threadId': 'helper-thread', 'startedAt': '2026-10-12T00:00:00Z',
          'currentActivity': '正在整理弹幕',
          'source': 'codexNative',
        });
    final context = await helperExecutor.entered.future;
    final task = (await service.tasks().first).single;
    expect(task.kind, UiTaskKind.helper);
    expect(task.source, 'codexNative');
    expect(task.title, '补齐弹幕');
    expect(task.threadId, 'helper-thread');
    expect(task.parentThreadId, 'parent');
    expect(task.currentActivity, '正在整理弹幕');
    expect(task.progress, isNull);
    await File('${root.path}/journal.jsonl').writeAsString('${jsonEncode({
      'event': 'chat.turn_boundary', 'origin': 'harness_cli:helper:${job.jobId}',
      'threadId': 'helper-thread', 'turnId': 'helper-turn', 'phase': 'started',
    })}\n', mode: FileMode.append);
    expect(await harness.invokeJson('ui.present', {'cards': [
      {'kind': 'task', 'taskId': job.jobId}
    ]}, Invocation(origin: 'harness_cli:helper:${job.jobId}')), isA<Completed>());
    expect(await service.cards(threadId: 'parent'), isEmpty);
    expect(await service.cards(threadId: 'helper-thread'), hasLength(1));
    await context.succeed(JobReceipt(verification: VerificationLevel.verified,
        details: {'summary': '九集已检查'}));
    final finished = (await service.tasks().first).single;
    expect(finished.summary, '九集已检查');
    expect(finished.progress, isNull);
  });

  test('artwork batches keep provenance and source files; invalid batch cannot edit metadata', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffaa4422), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 48);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('${root.path}/input.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose(); picture.dispose();
    JsonMap entry(String id, String kind) => {'entityId': id, 'kind': kind,
      'file': file.path, 'source': {'label': 'fixture source', 'url': 'https://example.test/art'}};
    final before = await store.database.query('media_metadata_edits');
    expect(await call('media.artwork.set', {'entries': [entry('w1', 'poster'), entry('w2', 'still')]}), isA<Failed>());
    expect(await store.database.query('media_metadata_edits'), before);
    expect(await call('media.artwork.set', {'entries': [{...entry('w1', 'poster'), 'url': 'https://example.test/a'}]}), isA<Failed>());
    expect(await store.database.query('media_metadata_edits'), before);
    final saved = await call('media.artwork.set', {'entries': [entry('w1', 'poster'), entry('w1', 'logo')]});
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
    expect(edits.every((e) => e['origin'] == 'harness_cli:chat:fixture' && e['invocation_id'] != null), true);
    final metadata = (await service.media.store.mergedMetadata('w1'))['fields'] as Map;
    expect((metadata['artwork.poster'] as Map)['source'], {'label': 'fixture source', 'url': 'https://example.test/art'});
    final facts = await service.metadataFacts('w1');
    expect((facts['fields'] as Map)['poster']['path'], work.artwork.poster);
    expect(facts['heroImage'], 'poster');
    await service.media.store.overrideField('w1', 'overview', '中文简介', Invocation(origin: 'mcp'), language: 'zh-CN');
    expect(((await service.metadataFacts('w1'))['fields'] as Map)['overview']['language'], 'zh-CN');
    await service.media.store.overrideField('w1', 'overview', 'English synopsis', Invocation(origin: 'mcp'));
    expect(((await service.metadataFacts('w1'))['fields'] as Map)['overview']['language'], 'unknown');
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
    await File('${root.path}/journal.jsonl').writeAsString(
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
}
