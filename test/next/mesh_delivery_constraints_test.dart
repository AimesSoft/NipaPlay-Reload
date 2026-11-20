import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/followups/migration.dart';
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
  late FakeExecutor programExecutor;
  late MeshRuntime mesh;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('mesh-return-constraints-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    executor = FakeExecutor(type: 'download');
    programExecutor = FakeExecutor(type: 'program');
    engine = TaskEngine(
        store: store, ownerDeviceId: 'workstation', executors: [executor, programExecutor]);
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

  Future<void> outbox(String id, String peer) async {
    final row = {
      'id': id,
      'invocationId': id,
      'state': 'ready',
      'remoteDeviceId': peer,
      'condition': {'kind': 'wake'},
      'trigger': <String, Object?>{},
      'title': 'Wake',
      'instruction': 'Wake',
      'repository': root.path,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await store.database.insert('followups', {
      'id': id, 'state': 'ready', 'snapshot': jsonEncode(row),
    });
  }

  test('failed push is pulled once, scoped to the recipient and serialized with retry', () async {
    await outbox('one', 'mac');
    var pushes = 0;
    followups.deliverRemote = (_, __) async {
      pushes++;
      throw const Failure(FailureCode.unavailable, 'cannot connect to target');
    };
    await followups.sweep();
    final source = (await followups.list()).single;
    expect(source['remoteAttempts'], 1);
    expect(source['remoteRetryAt'], isNotNull);
    expect(await mesh.hasDelivery!('mac'), isTrue);
    expect(await mesh.hasDelivery!('other'), isFalse);
    expect(await mesh.deliveryRequest!('other', 'mesh/delivery/pull', {
      'deviceId': 'mac',
    }), {'rows': []});
    await mesh.deliveryRequest!('other', 'mesh/delivery/ack', {
      'id': 'one',
      'receipt': {'id': 'followup-mesh-workstation-one', 'accepted': true},
    });
    expect((await followups.list()).single['state'], 'ready');

    final box = await mesh.deliveryRequest!('mac', 'mesh/delivery/pull', {});
    final delivered = (box['rows'] as List).single as JsonMap;
    final retryable = {...source, 'remoteRetryAt': '2000-01-01T00:00:00Z'};
    await store.database.update('followups', {'snapshot': jsonEncode(retryable)},
        where: 'id=?', whereArgs: ['one']);
    final destRoot = await root.createTemp('destination-');
    final destStore = await SqliteJobStore.open(destRoot, factory: databaseFactoryFfi);
    final destEngine = TaskEngine(store: destStore, ownerDeviceId: 'mac', executors: []);
    await destEngine.start();
    final dest = Followups(destStore.database, destEngine, HeadlessRepository(destRoot.path));
    final destMesh = MeshRuntime(root: destRoot, vault: _Vault(), token: () async => null)
      ..hostConfiguration = {'roles': ['agent']};
    attachMeshDelivery(destMesh, dest);
    try {
      final receipts = await Future.wait([
        destMesh.receiveDelivery!('workstation', {'row': delivered}),
        destMesh.receiveDelivery!('workstation', {'row': delivered}),
      ]);
      expect(receipts.first, receipts.last);
      expect((await dest.list()).where((row) => row['sourceFollowupId'] == 'one'), hasLength(1));
      expect(await destStore.database.query('followup_events',
          where: "type='followup.received'"), hasLength(1));
      final ack = {'id': 'one', 'receipt': receipts.first};
      await Future.wait([
        followups.sweep(),
        mesh.deliveryRequest!('mac', 'mesh/delivery/ack', ack),
        mesh.deliveryRequest!('mac', 'mesh/delivery/ack', ack),
      ]);
      await followups.sweep();
      final done = (await followups.list()).single;
      expect(pushes, 1);
      expect(done['state'], 'completed');
      expect(done['remoteReceipt'], receipts.first);
      expect(done['remoteAttempts'], isNull);
      expect(done['remoteRetryAt'], isNull);
      expect(await mesh.hasDelivery!('mac'), isFalse);
      expect(await store.database.query('followup_events',
          where: "type='followup.forwarded'"), hasLength(1));
    } finally {
      await destMesh.close();
      await dest.close();
      await destEngine.close();
      await destRoot.delete(recursive: true);
    }
  });

  for (final reason in ['目标设备已撤销', '目标设备已不在账号设备名单中', '目标设备已 7 天未上线']) {
    test('roster failure is terminal and manually retryable: $reason', () async {
      await outbox('one', 'mac');
      followups.remoteDeviceFact = (_) => (failure: reason, staleAt: null);
      var pushes = 0;
      followups.deliverRemote = (_, __) async {
        pushes++;
        return {'accepted': true};
      };
      await followups.sweep();
      await followups.sweep();
      final failed = (await followups.list()).single;
      expect(failed['state'], 'execution_failed');
      expect(failed['reason'], reason);
      expect(pushes, 0);
      expect(await store.database.query('followup_events',
          where: "type='followup.execution_failed'"), hasLength(1));
      followups.remoteDeviceFact = (_) => (failure: null, staleAt: null);
      final retried = await followups.retry('one', Invocation(origin: 'test'));
      expect(retried['state'], 'ready');
      await followups.sweep();
      expect(pushes, 1);
      expect((await followups.list()).single['state'], 'completed');
    });
  }
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

  test('inbox answers require the issued peer and return to the original thread once', () async {
    final question = await runZoned(() => followups.publishInbox({
      'requestId': 'disk-choice', 'title': '目录', 'body': '整理吗？'
    }, Invocation(origin: 'mesh:mac'), question: true),
      zoneValues: {#meshReturnTarget: target()});
    final replay = await runZoned(() => followups.publishInbox({
      'body': '整理吗？', 'title': '目录', 'requestId': 'disk-choice'
    }, Invocation(origin: 'mesh:mac'), question: true),
      zoneValues: {#meshReturnTarget: {...target(), 'returnTicket': 'new-ticket', 'invocationId': 'retry'}});
    expect(replay['id'], question['id']);
    await followups.answerInbox(question['id'] as String, '仅这次', Invocation(origin: 'gui'));
    final row = (await followups.list()).single;
    await File('${root.path}/mesh-return-targets.json').writeAsString(jsonEncode({
      'issued-ticket': {'peer': 'workstation-peer', ...target()}
    }));
    await expectLater(mesh.receiveDelivery!('wrong-peer', {'row': row}), throwsFormatException);
    await expectLater(mesh.receiveDelivery!('workstation-peer', {'row': {...row, 'threadId': 'another'}}), throwsFormatException);
    await expectLater(mesh.receiveDelivery!('workstation-peer', {'row': {...row}..remove('returnTicket')}), throwsFormatException);
    final accepted = await mesh.receiveDelivery!('workstation-peer', {'row': row});
    expect(await mesh.receiveDelivery!('workstation-peer', {'row': row}), accepted);
    final received = (await followups.list()).where((r) => r['sourceDeviceId'] != null).single;
    expect(received['threadId'], 'original-thread');
    expect(received['automatic'], 'inboxAnswer');
    expect((received['trigger'] as Map)['facts'], containsPair('answer', '仅这次'));
  });

  test('remote manual subscription returns through its issued target and owns the automatic fact', () async {
    final job = await engine.submit(type: 'program', title: 'subscribed', input: {'returnTo': target()});
    final subscription = await runZoned(() => followups.register({
      'instruction': 'custom completion instruction', 'when': {'jobId': job.jobId}},
      Invocation(origin: 'mesh:mac')), zoneValues: {#meshReturnTarget: target()});
    expect(subscription['repository'], root.path);
    expect(subscription['threadId'], 'original-thread');
    expect(subscription['remoteDeviceId'], 'mac');
    final delivered = <JsonMap>[];
    followups.deliverRemote = (peer, row) async { delivered.add(row); return {'accepted': true}; };
    await (await programExecutor.entered.future).succeed(verified(details: {'exitCode': 0}));
    await followups.sweep();
    expect(delivered, hasLength(1));
    expect(delivered.single['automatic'], 'subscription');
    expect((await followups.list()).where((r) => r['automatic'] == 'program').single['state'], 'cancelled');
    await File('${root.path}/mesh-return-targets.json').writeAsString(jsonEncode({
      'issued-ticket': {'peer': 'workstation-peer', ...target()}
    }));
    final accepted = await mesh.receiveDelivery!('workstation-peer', {'row': delivered.single});
    expect(accepted['accepted'], true);
    expect(await mesh.receiveDelivery!('workstation-peer', {'row': delivered.single}), accepted);
    final received = (await followups.list()).where((r) => r['automatic'] == 'meshSubscription').single;
    expect(received['threadId'], 'original-thread');
    expect(received['condition'], {'kind': 'mesh.subscription.facts'});
    expect(() => mesh.receiveDelivery!('wrong-peer', {'row': delivered.single}), throwsFormatException);
  });

  test('program completion retains the issued thread across lost ACK and reopen', () async {
    await engine.submit(type: 'program', title: '远端抽帧',
        input: {'returnTo': target()}, details: {'command': 'ffmpeg fixture'});
    final context = await programExecutor.entered.future;
    await context.succeed(verified(details: {'exitCode': 0, 'elapsedMs': 18,
        'stdoutTail': 'finished', 'stderrTail': '', 'command': 'ffmpeg fixture'}));
    followups.deliverRemote = (_, row) async {
      expect(row['threadId'], 'original-thread');
      throw const Failure(FailureCode.unavailable, 'ack lost');
    };
    await followups.sweep();
    final row = (await followups.list()).single;
    expect(row['automatic'], 'program');
    expect(row['remoteSealed'], true);
    final dynamic trigger = row['trigger'];
    expect(trigger['facts'][0]['data']['receipt']['details']['stdoutTail'], 'finished');
    await followups.sweep();
    expect(await followups.list(), hasLength(1));
    await followups.close();
    await engine.close();
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    engine = TaskEngine(store: store, ownerDeviceId: 'workstation',
        executors: [FakeExecutor(type: 'program')]);
    await engine.start();
    followups = Followups(store.database, engine, HeadlessRepository(root.path));
    await followups.sweep();
    expect(await followups.list(), hasLength(1));
    expect((await followups.list()).single['returnTicket'], 'issued-ticket');
  });

  test('an unreachable device is retried less often and recorded once', () async {
    await engine.submit(type: 'program', title: '远端抽帧',
        input: {'returnTo': target()}, details: {'command': 'ffmpeg fixture'});
    final context = await programExecutor.entered.future;
    await context.succeed(verified(details: {'exitCode': 0, 'elapsedMs': 18,
        'stdoutTail': 'finished', 'stderrTail': '', 'command': 'ffmpeg fixture'}));
    var tries = 0;
    followups.deliverRemote = (_, row) async {
      tries++;
      throw Failure(FailureCode.unavailable,
          tries.isOdd ? 'connect timeout' : 'Mesh is offline.');
    };
    Future<int> pendingEvents() async => (await store.database.query(
            'followup_events',
            where: "type = 'followup.pending'"))
        .length;
    Future<void> due() async {
      final row = (await store.database.query('followups')).single;
      final snapshot = jsonDecode(row['snapshot'] as String) as Map;
      snapshot['remoteRetryAt'] = '2000-01-01T00:00:00.000Z';
      await store.database.update('followups',
          {'snapshot': jsonEncode(snapshot)}, where: 'id=?', whereArgs: [row['id']]);
    }
    final waits = <int>[];
    for (var i = 0; i < 4; i++) {
      if (i > 0) await due();
      final before = DateTime.now().toUtc();
      await followups.sweep();
      final row = (await followups.list()).single;
      expect(row['remoteAttempts'], i + 1);
      waits.add(DateTime.parse(row['remoteRetryAt'] as String)
          .difference(before)
          .inSeconds);
    }
    expect(tries, 4);
    // 30 s, then doubling.
    expect(waits.map((w) => (w / 30).round()), [1, 2, 4, 8]);
    // The alternating reasons of one run of failures are one event.
    expect(await pendingEvents(), 1);
  });

  test('the migration keeps only the latest pending event of each followup',
      () async {
    final db = store.database;
    Future<void> add(String id, String type) => db.insert('followup_events', {
          'followup_id': id, 'at': '2026-11-20T00:00:00Z', 'type': type,
          'origin': 'application', 'facts': '{}'});
    for (final id in ['a', 'b']) {
      await db.insert('followups', {
        'id': id, 'state': 'ready', 'snapshot': '{}'
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await add('a', 'followup.registered');
    for (var i = 0; i < 5; i++) {
      await add('a', 'followup.pending');
    }
    await add('b', 'followup.pending');
    await add('a', 'followup.sealed');
    final latest = (await db.rawQuery(
            "SELECT MAX(sequence) AS s FROM followup_events WHERE followup_id = 'a' AND type = 'followup.pending'"))
        .single['s'];
    await purgeFollowupRetryNoise(db);
    final kept = await db.query('followup_events',
        columns: ['followup_id', 'type', 'sequence'], orderBy: 'sequence');
    expect(kept.map((r) => '${r['followup_id']} ${r['type']}'), [
      'a followup.registered',
      'a followup.pending',
      'b followup.pending',
      'a followup.sealed',
    ]);
    expect(kept[1]['sequence'], latest);
  });

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
