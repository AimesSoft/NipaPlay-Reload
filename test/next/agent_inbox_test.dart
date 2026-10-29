import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/chat/turn_boundaries.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/followups/inbox_capability.dart';
import 'package:nipaplay/next/harness_location.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../packages/nipa_harness/test/task_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late FakeExecutor executor;
  late Followups service;
  late HarnessLocation location;
  final origin = Invocation(origin: 'harness_cli:chat:fixture', id: 'question');
  final input = <String, Object?>{
    'requestId': 'q1',
    'title': '文件整理',
    'body': '要整理文件名吗？',
    'options': ['仅这次', '以后也整理', '保持原样']
  };
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('agent-inbox-');
    SharedPreferences.setMockInitialValues(
        {HarnessLocation.storageKey: root.path});
    location = HarnessLocation();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(type: 'media.scan');
    engine = TaskEngine(
        store: store, ownerDeviceId: 'fixture', executors: [executor]);
    await engine.start();
    service = Followups(store.database, engine, location);
    await TurnBoundaries.write(File('${root.path}/journal.jsonl'), {
      'origin': origin.origin,
      'phase': 'started',
      'threadId': 'original-thread',
      'turnId': 'turn-1'
    });
  });
  tearDown(() async {
    await service.close();
    await engine.close();
    location.dispose();
    await root.delete(recursive: true);
  });

  test(
      'ask returns pending immediately; replay and hide neither answer nor wake',
      () async {
    final row = await service.publishInbox(input, origin, question: true);
    expect(row['state'], 'pending');
    expect(await service.list(), isEmpty);
    expect((await service.publishInbox(input, origin, question: true))['id'],
        row['id']);
    await service.dismissInbox(row['id'] as String);
    final saved = ((await service.inboxList())['items'] as List).single as Map;
    expect(saved['hidden'], true);
    expect(saved['state'], 'pending');
    expect(await service.list(), isEmpty);
    await expectLater(
        service.publishInbox({...input, 'body': 'different'}, origin,
            question: true),
        throwsA(isA<Failure>()));
  });

  test('answer and one original-target delivery survive restart and retry',
      () async {
    final q = await service.publishInbox(input, origin, question: true);
    await service.answerInbox(
        q['id'] as String, '仅这次', Invocation(origin: 'gui'));
    await service.close();
    service = Followups(store.database, engine, location);
    await service.answerInbox(
        q['id'] as String, '仅这次', Invocation(origin: 'gui'));
    final deliveries = await service.list();
    expect(deliveries, hasLength(1));
    expect(deliveries.single['threadId'], 'original-thread');
    expect(deliveries.single['automatic'], 'inboxAnswer');
    expect(((deliveries.single['trigger'] as Map)['facts'] as Map)['answer'],
        '仅这次');
    expect((await service.inboxList())['items'], isEmpty);
    await expectLater(
        service.answerInbox(
            q['id'] as String, '以后也整理', Invocation(origin: 'gui')),
        throwsA(isA<Failure>()));
  });

  test(
      'cancel and missing conversation cannot imply consent; tools reject self-answer',
      () async {
    await expectLater(
        service.publishInbox(input, Invocation(origin: 'gui'), question: true),
        throwsA(isA<Failure>()));
    final q = await service.publishInbox(input, origin, question: true);
    final harness = Harness([InboxCapability(service)]);
    expect(
        await harness.invokeJson(
            'ui.inbox.respond', {'id': q['id'], 'answer': 'yes'}, origin),
        isA<Failed>());
    await service.dismissInbox(q['id'] as String, cancel: true);
    await expectLater(
        service.answerInbox(
            q['id'] as String, 'yes', Invocation(origin: 'gui')),
        throwsA(isA<Failure>()));
    expect(await service.list(), isEmpty);
  });

  test('popup setting hides no records; error message retains exact newlines',
      () async {
    await service.setInboxPreference('notification.agentPopups', false);
    const error = 'HTTP 500\n{"error":"upstream failed"}\npath: /a/b';
    await service.publishInbox({
      'requestId': 'error',
      'title': '失败',
      'body': error,
      'severity': 'error'
    }, Invocation(origin: 'gui'), question: false);
    final page = await service.inboxList();
    expect(page['popupsEnabled'], false);
    expect(((page['items'] as List).single as Map)['body'], error);
  });

  test(
      'failed scan preserves the complete error once and returns failure facts',
      () async {
    final request = await service.folderRequest(Invocation(origin: 'gui'));
    final job = await engine.submit(
        type: 'media.scan',
        title: 'scan',
        input: {'root': root.path, 'folderRequest': request});
    final context = await executor.entered.future;
    const error = Failure(FailureCode.unavailable, 'EIO: original\nsecond line',
        details: {'path': '/fixture/a'},
        violations: [SchemaViolation('root', 'not readable')]);
    await context.fail(
        error,
        JobReceipt(
            verification: VerificationLevel.unverified, details: const {}));
    await service.sweep();
    await service.sweep();
    final row = ((await service.inboxList())['items'] as List).single as Map;
    expect(jsonDecode(row['body'] as String), error.toJson());
    expect(row['jobId'], job.jobId);
    final delivery = (await service.list()).single;
    expect(((delivery['trigger'] as Map)['facts'] as Map)['state'], 'failed');
    await service.close();
    service = Followups(store.database, engine, location);
    await service.sweep();
    expect((await service.inboxList())['items'], hasLength(1));
    expect(await service.list(), hasLength(1));
  });

  Future<void> seedScan(String id,
      {bool explicit = true, JobState state = JobState.succeeded}) async {
    final now = DateTime.now().toUtc();
    final job = Job(
        jobId: id,
        type: 'media.scan',
        title: '扫描',
        state: state,
        phase: 'done',
        progress: JobProgress(completed: 1, unit: 'files'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'fixture',
        revision: 1,
        input: {
          'root': root.path,
          if (explicit)
            'folderRequest':
                await service.folderRequest(Invocation(origin: 'gui'))
        },
        receipt: state == JobState.succeeded
            ? verified(details: {
                'fileIds': ['file-1'],
                'indexed': 1
              })
            : null);
    await store.database.insert('jobs', {
      'job_id': id,
      'type': job.type,
      'state': state.wireName,
      'revision': 1,
      'created_at': now.toIso8601String(),
      'snapshot': jsonEncode(job.toStorageJson())
    });
  }

  test(
      'explicit folder completion queues once; background indexing stays silent',
      () async {
    await seedScan('background', explicit: false);
    await seedScan('explicit');
    await service.sweep();
    await service.sweep();
    final rows = await service.list();
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'followup-folder-explicit');
    expect(rows.single['automatic'], 'folderRequest');
    expect(rows.single['instruction'], contains('ui.ask'));
    await service.close();
    service = Followups(store.database, engine, location);
    await service.sweep();
    expect(await service.list(), hasLength(1));
  });

  test(
      'turning folder organization off cancels pending dispatch; file policy defaults ask',
      () async {
    expect(
        (await service
            .folderRequest(Invocation(origin: 'gui')))!['fileOrganization'],
        'ask');
    await seedScan('explicit');
    await service.sweep();
    await service.setInboxPreference('library.organizeAddedFolders', false);
    await service.sweep();
    expect((await service.list()).single['state'], 'cancelled');
    expect(await service.folderRequest(Invocation(origin: 'gui')), isNull);
  });
}
