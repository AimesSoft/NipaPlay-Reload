@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/followups/service.dart';
import 'package:nipaplay/next/headless/ports.dart' show HeadlessRepository;
import 'package:nipaplay/next/mesh/capability.dart';
import 'package:nipaplay/next/mesh/coordinator.dart';
import 'package:nipaplay/next/mesh/delegation.dart';
import 'package:nipaplay/next/mesh/delegation_host.dart';
import 'package:nipaplay/next/mesh/delegation_wiring.dart';
import 'package:nipaplay/next/mesh/native.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mesh_delegation_support.dart';

final class _Vault implements CredentialVault {
  final values = <CredentialRef, String>{};
  @override
  Future<String?> read(CredentialRef ref) async => values[ref];
  @override
  Future<void> write(CredentialRef ref, String secret) async =>
      values[ref] = secret;
  @override
  Future<void> delete(CredentialRef ref) async => values.remove(ref);
}

String _jwt(int id) => [
      base64Url.encode(utf8.encode('{"alg":"EdDSA"}')).replaceAll('=', ''),
      base64Url
          .encode(utf8.encode(jsonEncode({'userId': id, 'testOnly': true})))
          .replaceAll('=', ''),
      'synthetic-test-signature',
    ].join('.');

/// One device: its mesh node and what delegation puts around it.
final class _Device {
  _Device(this.mesh, this.root);
  final MeshRuntime mesh;
  final Directory root;
  late SqliteJobStore store;
  late TaskEngine engine;
  late Followups followups;
  late MeshDelegations sender;
  late AgentDelegations receiver;
  final chat = FakeChat();
  bool running = true, attached = false;

  String get id => mesh.identity!.deviceId;

  /// Delegation as the real hosts wire it, except that the conversation host
  /// is [chat] while [running] (a real one needs a model).
  Future<void> wire({bool realReceiver = false}) async {
    attached = true;
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    sender = createMeshDelegations(mesh);
    engine = TaskEngine(
        store: store, ownerDeviceId: id, executors: [sender]);
    await engine.start();
    followups = Followups(store.database, engine, HeadlessRepository(root.path));
    final wired = attachMeshDelegation(mesh, sender, engine, followups);
    if (realReceiver) {
      receiver = wired;
      return;
    }
    receiver = AgentDelegations(
        root: root,
        chat: () => running ? chat : null,
        unavailableReason: () => 'Next chat host is disabled.',
        deviceName: mesh.deviceName,
        startedTasks: (_, __) async => const []);
    mesh.agentRequest = receiver.handle;
    await receiver.attach(chat);
  }

  Future<void> close() async {
    if (!attached) return;
    await followups.close();
    await engine.close();
    await chat.close();
  }
}

void main() {
  late Directory directory, caDirectory;
  late MeshNative native;
  late String caPem;
  late HttpServer upstream;
  late Process coordinator;
  late Uri base;
  final vault = _Vault();
  final devices = <_Device>[];
  final logs = <String>[];

  setUpAll(() async {
    sqfliteFfiInit();
    caDirectory = await Directory.systemTemp.createTemp('mesh-peers-ca-');
    final bundled = Platform.environment['NIPAPLAY_MESH_TEST_LIBRARY'];
    if (Platform.isMacOS && bundled != null) {
      DynamicLibrary.open(
          '${File(bundled).absolute.parent.parent.path}/FlutterMacOS.framework/FlutterMacOS');
    }
    Future<void>? initialized;
    native = MeshNative(
      initialize: () => initialized ??= RustLib.init(
        externalLibrary: ExternalLibrary.open(File(bundled ??
                'rust/target/debug/librust_lib_nipaplay.${Platform.isMacOS ? 'dylib' : 'so'}')
            .absolute
            .path),
      ),
    );
    await native.ready();
    final ca = await Process.run(
        'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator',
        [
          '--generate-dev-ca',
          '${caDirectory.path}/ca.pem',
          '${caDirectory.path}/ca.key'
        ]);
    expect(ca.exitCode, 0, reason: ca.stderr.toString());
    caPem = await File('${caDirectory.path}/ca.pem').readAsString();
  });
  tearDownAll(() async => caDirectory.delete(recursive: true));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('mesh-peers-');
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final accepted = request.uri.path == '/dandanplay/api/v2/playhistory' &&
          [_jwt(424242), _jwt(515151)]
              .any((t) => request.headers.value('authorization') == 'Bearer $t');
      request.response.statusCode = accepted ? 200 : 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': accepted}));
      await request.response.close();
    });
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    base = Uri.parse('http://127.0.0.1:$port');
    coordinator = await Process.start(
        'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator',
        [],
        includeParentEnvironment: false,
        environment: {
          'MESH_LISTEN_ADDR': '127.0.0.1:$port',
          'MESH_DATABASE_PATH': '${directory.path}/coordinator.db',
          'MESH_CA_CERT_FILE': '${caDirectory.path}/ca.pem',
          'MESH_CA_KEY_FILE': '${caDirectory.path}/ca.key',
          'DANDANPLAY_GATEWAY_BASE':
              'http://127.0.0.1:${upstream.port}/dandanplay/',
          'MESH_ACCOUNT_CLAIM_POINTER': '/userId',
          'NO_PROXY': '127.0.0.1,localhost,::1',
          'HTTP_PROXY': '',
          'HTTPS_PROXY': '',
          'ALL_PROXY': '',
        });
    coordinator.stdout.transform(utf8.decoder).listen(logs.add);
    coordinator.stderr.transform(utf8.decoder).listen(logs.add);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      try {
        final response =
            await (await client.getUrl(base.resolve('/healthz'))).close();
        await response.drain<void>();
        break;
      } on SocketException {
        if (DateTime.now().isAfter(deadline)) {
          fail('Coordinator startup: ${logs.join()}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    client.close(force: true);
  });

  tearDown(() async {
    for (final device in devices.reversed) {
      await device.close();
      await device.mesh.close();
    }
    devices.clear();
    coordinator.kill();
    await coordinator.exitCode;
    await upstream.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<_Device> join(String name,
      {int account = 424242,
      Directory? existing,
      bool wire = true,
      bool realReceiver = false,
      List<Map>? notices}) async {
    final root = existing ?? await Directory('${directory.path}/$name').create();
    final mesh = MeshRuntime(
        root: root,
        vault: vault,
        native: native,
        authorize: (_, __) async => null,
        token: () async => _jwt(account),
        unknownPeerRefreshCooldown: const Duration(milliseconds: 100));
    mesh.attach(Harness([MeshCapability(mesh)]));
    // A screen listens before the node starts, as the application does.
    if (notices != null) mesh.joinNotices.listen(notices.add);
    await mesh.join(
        ca: caPem,
        coordinator: MeshCoordinator(base, () async => _jwt(account)),
        name: name,
        broadcast: false);
    await File('${root.path}/mesh.json')
        .writeAsString(jsonEncode({'coordinator': base.toString()}));
    await mesh.setManualAddresses([
      {'kind': 'manual', 'host': '127.0.0.1', 'port': mesh.port}
    ]);
    await mesh.heartbeat(renew: false);
    final device = _Device(mesh, root);
    if (wire) await device.wire(realReceiver: realReceiver);
    devices.add(device);
    return device;
  }

  test('where a node listens: every interface unless the host says loopback only', () {
    expect(MeshRuntime.bindHostFor({}), '0.0.0.0');
    expect(MeshRuntime.bindHostFor({'loopbackOnly': false}), '0.0.0.0');
    expect(MeshRuntime.bindHostFor({'loopbackOnly': true}), '127.0.0.1');
  });

  test('the other Nipa\'s reason travels over mutual TLS when she is not running there', () async {
    final a = await join('mac');
    final b = await join('workstation', realReceiver: true);
    await a.mesh.refreshDevices();
    // B has no conversation host at all (nothing attached it).
    await expectLater(
        a.sender.delegate({'deviceId': b.id, 'task': 'anything'},
            Invocation(origin: 'harness_cli')),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.unavailable)
            .having((f) => f.message, 'message',
                allOf(contains('workstation'), contains('Embedded chat host is not running.')))));
    expect(await a.engine.list(type: 'agent.delegate'), isEmpty);
  });

  test('a task is handed over, followed to its end and its cancellation reaches the other turn', () async {
    final a = await join('mac');
    final b = await join('workstation');
    await a.mesh.refreshDevices();
    final invocation = Invocation(origin: 'harness_cli');

    final started = await a.sender.delegate({
      'deviceId': b.id,
      'task': '看看你的片库里有什么，整理成一张清单。',
      'references': [
        {'kind': 'note', 'text': 'from the Mac'}
      ]
    }, invocation);
    final id = started['jobId'] as String;
    final thread = (started['remote'] as Map)['threadId'] as String;
    // On the other device it is a conversation of its own, naming its source.
    expect(b.chat.titles[thread], '来自 mac 的委托');
    expect(b.chat.started.single.$2, contains('来自 mac 上的 Nipa 的委托。'));
    expect(b.chat.started.single.$2, contains('看看你的片库里有什么'));

    b.chat.step(thread);
    b.chat.say(thread, '我先读了片库。有 3 部作品。');
    await until(() async {
      final job = await a.engine.get(id);
      return job.details['steps'] == 1 &&
          job.details['lastSentence'] == '有 3 部作品';
    }, 'progress crossed the wire');

    b.chat.say(thread, '清单：甲、乙、丙。');
    b.chat.finish(thread);
    await until(() async => (await a.engine.get(id)).state == JobState.succeeded,
        'the task ended');
    final details = (await a.engine.get(id)).receipt!.details;
    expect(details['summary'], contains('清单：甲、乙、丙。'));
    expect(details['deviceName'], 'workstation');

    // The next task continues the conversation of the same device.
    final second = await a.sender.delegate(
        {'deviceId': b.id, 'task': '再加一列'}, invocation);
    expect((second['remote'] as Map)['threadId'], thread);
    expect((second['remote'] as Map)['conversationContinued'], true);
    await until(() async => b.chat.busyFor(thread), 'the second turn runs');

    // Cancelling the local task cancels the other device's turn.
    await a.engine.cancel(second['jobId'] as String);
    await until(
        () async => (await a.engine.get(second['jobId'] as String)).state ==
            JobState.cancelled,
        'cancelled');
    expect(b.chat.interrupted, [thread]);
    expect((await a.engine.get(second['jobId'] as String)).receipt!.details['remoteStopped'], true);
  });

  test('a device of another account cannot hand work to Nipa', () async {
    final a = await join('mac');
    final c = await join('stranger', account: 515151);
    await expectLater(
        c.mesh.rpc(a.id, 'mesh/agent/turn',
            {'delegationId': 'delegation-0001', 'text': 'hello'}),
        throwsA(isA<Failure>()));
    expect(a.chat.started, isEmpty);
    // Nor does it appear among A's devices to delegate to.
    await a.mesh.refreshDevices();
    await expectLater(
        a.sender.delegate({'deviceId': c.id, 'task': 'x'}, Invocation(origin: 'harness_cli')),
        throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.notFound)));
  });

  test('a removed device is refused at once, both ways', () async {
    final a = await join('mac');
    final b = await join('workstation');
    await a.mesh.refreshDevices();
    // Works before.
    final before = await b.mesh.rpc(a.id, 'mesh/agent/turn',
        {'delegationId': 'delegation-0001', 'text': 'hello'});
    expect(before['state'], 'inProgress');

    await a.mesh.revoke(b.id);

    // B still thinks it belongs; A's node refuses it without waiting for any
    // heartbeat.
    await expectLater(
        b.mesh.rpc(a.id, 'mesh/agent/turn',
            {'delegationId': 'delegation-0002', 'text': 'hello again'}),
        throwsA(isA<Failure>()));
    expect(a.chat.started, hasLength(1));
    // And A no longer hands it work.
    await expectLater(
        a.sender.delegate({'deviceId': b.id, 'task': 'x'}, Invocation(origin: 'harness_cli')),
        throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.notFound)));
    final listed = (await a.mesh.devices(includeCatalog: false))['devices'] as List;
    expect(listed.cast<Map>().singleWhere((d) => d['deviceId'] == b.id)['revoked'], true);
    // A device cannot remove itself.
    await expectLater(a.mesh.revoke(a.id), throwsA(isA<Failure>()));
  });

  test('a device that joins is announced once to a screen, and only recorded by a host without one', () async {
    final notices = <Map>[];
    final a = await join('mac', notices: notices);
    // The first roster is the baseline: nothing in it is news.
    await a.mesh.refreshDevices();
    await a.mesh.joinsSettled;
    expect(notices, isEmpty);

    final b = await join('ipad');
    await a.mesh.refreshDevices();
    await a.mesh.joinsSettled;
    await pumpEventQueue();
    expect(notices.map((n) => n['name']), ['ipad']);
    expect(notices.single['deviceId'], b.id);
    // Not again for the same device in this run.
    await a.mesh.refreshDevices();
    await a.mesh.joinsSettled;
    await pumpEventQueue();
    expect(notices, hasLength(1));

    var seen = ((await a.mesh.devices(includeCatalog: false))['devices'] as List)
        .cast<Map>()
        .singleWhere((d) => d['deviceId'] == b.id);
    expect(seen['firstSeenAt'], isNotNull);
    expect(seen['acknowledged'], false);

    // Unanswered, it is announced again the next time this device starts.
    await a.close();
    await a.mesh.close();
    devices.remove(a);
    final again = <Map>[];
    final restarted =
        await join('mac', existing: a.root, wire: false, notices: again);
    await restarted.mesh.joinsSettled;
    await pumpEventQueue();
    expect(again.map((n) => n['deviceId']), [b.id]);

    // Answered, never again.
    await restarted.mesh.acknowledgeJoin(b.id);
    await restarted.mesh.close();
    devices.remove(restarted);
    final none = <Map>[];
    final third =
        await join('mac', existing: a.root, wire: false, notices: none);
    await third.mesh.refreshDevices();
    await third.mesh.joinsSettled;
    await pumpEventQueue();
    expect(none, isEmpty);
    seen = ((await third.mesh.devices(includeCatalog: false))['devices'] as List)
        .cast<Map>()
        .singleWhere((d) => d['deviceId'] == b.id);
    expect(seen['acknowledged'], true);
  });
}
