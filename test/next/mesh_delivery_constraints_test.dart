import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/headless/ports.dart' show HeadlessRepository;
import 'package:nipaplay/next/mesh/delivery.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../packages/nipa_harness/test/task_support.dart';

final class _Vault implements CredentialVault {
  @override
  Future<String?> read(CredentialRef ref) async => null;
  @override
  Future<void> write(CredentialRef ref, String secret) async {}
  @override
  Future<void> delete(CredentialRef ref) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late FakeExecutor executor;
  late MeshRuntime mesh;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('mesh-return-constraints-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(type: 'download');
    engine = TaskEngine(
        store: store, ownerDeviceId: 'workstation', executors: [executor]);
    await engine.start();
    followups =
        Followups(store.database, engine, HeadlessRepository(root.path));
    mesh = MeshRuntime(root: root, vault: _Vault(), token: () async => null);
    attachMeshDelivery(mesh, followups);
  });
  tearDown(() async {
    await followups.close();
    await engine.close();
    await mesh.close();
    await root.delete(recursive: true);
  });
  JsonMap target() => {
        'deviceId': 'mac',
        'threadId': 'original-thread',
        'repository': root.path,
        'origin': 'harness_cli:chat:original',
        'invocationId': 'original-invocation',
        'returnTicket': 'issued-ticket'
      };
  JsonMap file(Job job, int index) => {
        'jobId': job.jobId,
        'index': index,
        'objectId': '${job.jobId}:$index',
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'path': '/remote/$index.mp4',
        'verification': 'verified',
        'isVideo': true,
        'imported': true,
        'local': true,
        'complete': true,
        'media': {'fileId': 'file-$index'}
      };

  test(
      'mesh return target comes from authenticated transport, never current local chat',
      () async {
    final invocation = Invocation(origin: 'mesh:mac');
    final result = await runZoned(
        () => followups.downloadReturnTarget(invocation),
        zoneValues: {#meshReturnTarget: target()});
    expect(result, target());
    expect(await followups.downloadReturnTarget(invocation), isNull);
    expect(
        await followups
            .downloadReturnTarget(Invocation(origin: 'harness_hook:tick')),
        isNull);
  });

  test(
      'lost acknowledgement seals the batch; later files survive as another batch after reopen',
      () async {
    final job = await engine
        .submit(type: 'download', title: '合集', input: {'returnTo': target()});
    final context = await executor.entered.future;
    final delivered = <JsonMap>[];
    followups.deliverRemote = (peer, row) async {
      expect(peer, 'mac');
      delivered.add(Map<String, Object?>.from(row));
      throw const Failure(FailureCode.unavailable, 'ack lost');
    };
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0)]
    });
    await followups.sweep();
    final original = (await followups.list()).single;
    expect(original['remoteSealed'], true);
    expect(original['state'], 'ready');
    await context.report(checkpoint: {
      'completedFiles': [file(job, 0), file(job, 1)]
    });
    await followups.sweep();
    final rows = await followups.list();
    expect(rows, hasLength(2));
    expect(rows.first['downloadObjects'], ['${job.jobId}:0']);
    expect(rows.last['downloadObjects'], ['${job.jobId}:1']);
    await context.succeed(verified());
    await followups.sweep();
    expect((await followups.list()).last['downloadObjects'],
        ['${job.jobId}:1', 'terminal:${job.jobId}']);
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'workstation',
        executors: [FakeExecutor(type: 'download')]);
    await engine.start();
    followups =
        Followups(store.database, engine, HeadlessRepository(root.path));
    await followups.sweep();
    expect((await followups.list()).first['remoteSealed'], true);
    expect((await followups.list()), hasLength(2));
    expect((await engine.get(job.jobId)).receipt!.toJson()['verification'],
        'verified');
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'receiver keeps original target and receipt under duplicate delivery and restart',
      () async {
    final payload = {
      'row': {
        'id': 'remote-batch',
        'automatic': 'download',
        'instruction': '完成事实',
        'title': '合集',
        'invocationId': 'original-invocation',
        'condition': {'downloadJobId': 'remote-job'},
        'downloadObjects': ['remote-job:0'],
        'deliverAfter': DateTime.now().toUtc().toIso8601String(),
        'remoteDeviceId': 'mac',
        'threadId': 'original-thread',
        'repository': root.path,
        'returnTicket': 'issued-ticket',
        'trigger': {
          'kind': 'download.facts',
          'facts': [
            {
              'event': 'download.file_completed',
              'objectId': 'remote-job:0',
              'occurredAt': DateTime.now().toUtc().toIso8601String(),
              'data': {'verified': true}
            }
          ]
        }
      }
    };
    final receipt = await followups.acceptMeshDelivery('workstation', payload,
        target: target());
    expect(
        await followups.acceptMeshDelivery('workstation', payload,
            target: target()),
        receipt);
    var rows = await followups.list();
    expect(rows, hasLength(1));
    expect(rows.single['threadId'], 'original-thread');
    expect(rows.single.containsKey('remoteDeviceId'), false);
    expect(rows.single['sourceDeviceId'], 'workstation');
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(store: store, ownerDeviceId: 'mac', executors: []);
    await engine.start();
    followups =
        Followups(store.database, engine, HeadlessRepository(root.path));
    expect(
        await followups.acceptMeshDelivery('workstation', payload,
            target: target()),
        receipt);
    rows = await followups.list();
    expect(rows, hasLength(1));
    expect(await store.database.query('followup_hook_events'), hasLength(1));
    expect(rows.single['trigger'], (await followups.list()).single['trigger']);
  });

  test('unissued or wrong-peer ticket is rejected before persistence',
      () async {
    final helperStore = await SqliteJobStore.open(
        await Directory('${root.path}/host').create(),
        factory: databaseFactoryFfi);
    final helperEngine =
        TaskEngine(store: helperStore, ownerDeviceId: 'mac', executors: []);
    final host = Followups(
        helperStore.database, helperEngine, HeadlessRepository(root.path));
    final hostMesh = MeshRuntime(
        root: Directory('${root.path}/host'),
        vault: _Vault(),
        token: () async => null);
    attachMeshDelivery(hostMesh, host);
    final issued = await runZoned(
        () => hostMesh.returnTarget!(
            'workstation', Invocation(origin: 'mesh:original')),
        zoneValues: {#meshReturnTarget: target()});
    final row = {
      'id': 'batch',
      'automatic': 'download',
      'invocationId': 'original-invocation',
      'instruction': '完成事实',
      'title': '合集',
      'condition': {'downloadJobId': 'remote-job'},
      'deliverAfter': DateTime.now().toUtc().toIso8601String(),
      'returnTicket': issued!['returnTicket'],
      'threadId': 'original-thread',
      'repository': root.path,
      'trigger': {'facts': []}
    };
    await expectLater(hostMesh.receiveDelivery!('other-device', {'row': row}),
        throwsFormatException);
    row['returnTicket'] = 'unissued';
    await expectLater(hostMesh.receiveDelivery!('workstation', {'row': row}),
        throwsFormatException);
    expect(await host.list(), isEmpty);
    row['returnTicket'] = issued['returnTicket'];
    expect(await hostMesh.receiveDelivery!('workstation', {'row': row}),
        containsPair('accepted', true));
    expect(await host.list(), hasLength(1));
    await host.close();
    await hostMesh.close();
    await helperEngine.close();
  });

  test(
      'wake cannot forge an automatic download return or target a transfer-only host',
      () async {
    final row = {
      'id': 'spoof',
      'automatic': 'meshDownload',
      'invocationId': 'inv',
      'instruction': '完成事实',
      'title': '合集',
      'condition': {'kind': 'wake'},
      'trigger': {'facts': []}
    };
    mesh.hostConfiguration = {
      'roles': ['agent']
    };
    await expectLater(mesh.receiveDelivery!('workstation', {'row': row}),
        throwsFormatException);
    row.remove('automatic');
    mesh.hostConfiguration = {
      'roles': ['download']
    };
    await expectLater(mesh.receiveDelivery!('workstation', {'row': row}),
        throwsFormatException);
    expect(await followups.list(), isEmpty);
  });

  test(
      'script wake follows host agent device; forwarded receipt never starts local chat',
      () async {
    mesh.hostConfiguration = {'agentDeviceId': 'mac'};
    followups.deliverRemote = (peer, row) async {
      expect(peer, 'mac');
      expect(row['threadId'], isNull);
      return {'accepted': true, 'id': 'mac-receipt'};
    };
    await followups.wake({
      'instruction': '目录出现新文件',
      'facts': {'path': '/remote'}
    }, Invocation(origin: 'harness_hook:tick'));
    await followups.sweep();
    final row = (await followups.list()).single;
    expect(row['state'], 'completed');
    expect(row['deliveryState'], 'forwarded');
    expect(row['turnId'], isNull);
    expect(row['remoteReceipt'], {'accepted': true, 'id': 'mac-receipt'});
  });
}
