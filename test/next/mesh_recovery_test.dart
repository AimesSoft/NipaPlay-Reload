import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipaplay/next/mesh/coordinator.dart';
import 'package:nipaplay/next/mesh/identity.dart';
import 'package:nipaplay/next/mesh/native.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/system_proxy_service.dart';
import 'package:nipaplay/src/rust/api/mesh.dart';
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Vault implements CredentialVault {
  final values = <CredentialRef, String>{};
  @override
  Future<String?> read(CredentialRef ref) async => values[ref];
  @override
  Future<void> write(CredentialRef ref, String secret) async {
    values[ref] = secret;
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    values.remove(ref);
  }
}

// Simulate only the TLS transport. Coordinator HTTP and runtime state machines
// are real; no app, certificates, or native rebuild is needed for this test.
final class _Transport extends RustLibApi {
  final incoming = StreamController<MeshIncoming>();
  late final events = StreamIterator(incoming.stream);
  final replies = <BigInt, Completer<JsonMap>>{};
  var peerPort = 2000;
  var starts = 0;
  var calls = 0;
  var nextId = 0;
  bool peerHasDelivery = false;

  Future<JsonMap> request(JsonMap frame, {String peer = 'peer'}) {
    final id = BigInt.from(++nextId);
    final reply = replies[id] = Completer<JsonMap>();
    incoming.add(MeshIncoming(requestId: id, deviceId: peer, body: jsonEncode(frame)));
    return reply.future.timeout(const Duration(seconds: 2));
  }

  Future<MeshIncoming> next() async {
    if (!await events.moveNext()) throw StateError('stopped');
    return events.current;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #crateApiMeshMeshGenerateKey:
        return Future<String>.value('key');
      case #crateApiMeshMeshPublicKey:
        return Future<String>.value(base64Url.encode(List.filled(32, 1)));
      case #crateApiMeshMeshSign:
        return Future<String>.value('signature');
      case #crateApiMeshMeshValidateCertificate:
        return Future<String>.value('valid');
      case #crateApiMeshMeshStart:
        starts++;
        return Future<int>.value(1);
      case #crateApiMeshMeshPort:
        return Future<int>.value(1000);
      case #crateApiMeshMeshNext:
        return next();
      case #crateApiMeshMeshRespond:
        replies.remove(args[#requestId])!.complete(jsonDecode(args[#body] as String) as JsonMap);
        return Future<void>.value();
      case #crateApiMeshMeshUpdateDevices:
        return Future<void>.value();
      case #crateApiMeshMeshStop:
        unawaited(incoming.close());
        return Future<void>.value();
      case #crateApiMeshMeshSend:
        calls++;
        if (args[#device] == 'peer' && args[#port] != peerPort) {
          return Future<String>.error(
              const SocketException('connect: refused'));
        }
        final frame = jsonDecode(args[#body] as String) as Map;
        return Future<String>.value(jsonEncode({
          'jsonrpc': '2.0', 'id': frame['id'], 'result': {},
          if (frame['method'] == 'mesh/presence') 'deliveryPending': peerHasDelivery,
        }));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test(
      'report recovers without probing offline peers; manual refresh finds a new port without restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('');
    final transport = _Transport();
    RustLib.initMock(api: transport);
    final root = await Directory.systemTemp.createTemp('mesh-recovery-');
    final native = MeshNative(initialize: () async {});
    final vault = _Vault();
    final identity = await MeshIdentity.load(root, vault, native);
    final own = identity.deviceId;
    final roster = {
      'success': true,
      'account_id': 'account',
      'revocation_epoch': 0,
      'devices': [
        {'device_id': own, 'device_name': 'self', 'revoked': false},
        {'device_id': 'peer', 'device_name': 'peer', 'revoked': false},
      ],
    };
    await File('${root.path}/mesh-certificate.json').writeAsString(jsonEncode({
      'device_id': own,
      'account_id': 'account',
      'certificate': {
        'pem': 'test',
        'not_after': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 864000
      },
    }));
    await File('${root.path}/mesh-devices.json')
        .writeAsString(jsonEncode(roster));
    final replay = File('${root.path}/mesh-replay.jsonl');
    await replay.writeAsString('{"keys":["unfinished');
    var reportsFail = true;
    var queriesFail = false;
    var advertisedPort = 2000;
    var queryCount = 0;
    var reports = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      JsonMap reply = {'success': true, 'revocation_epoch': 0};
      if (request.method == 'POST') {
        reports++;
        if (reportsFail) {
          request.response.statusCode = 503;
          reply = {'success': false, 'error': 'unavailable'};
        }
      } else if (request.uri.path.endsWith('/devices')) {
        reply = roster;
      } else {
        queryCount++;
        if (queriesFail) {
          request.response.statusCode = 503;
          reply = {'success': false, 'error': 'unavailable'};
        } else {
          reply = {
            'success': true,
            'candidates': [
              {'kind': 'manual', 'host': '127.0.0.1', 'port': advertisedPort},
            ]
          };
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(reply));
      await request.response.close();
    });
    final runtime = MeshRuntime(
        root: root,
        vault: vault,
        native: native,
        token: () async => 'test',
        authorize: (_, __) async => null,
        coordinatorRetryDelay: const Duration(milliseconds: 40),
        candidateLookupBase: const Duration(milliseconds: 25),
        interfaceProvider: () async => const []);
    runtime.attach(Harness([]));
    try {
      await runtime.join(
          ca: 'test',
          name: 'self',
          broadcast: false,
          coordinator: MeshCoordinator(
              Uri.parse('http://127.0.0.1:${server.port}'),
              () async => 'test'));
      expect(runtime.coordinatorSyncPending, isTrue);
      reportsFail = false;
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (runtime.coordinatorSyncPending) {
        if (DateTime.now().isAfter(deadline)) fail('report did not recover');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(transport.calls, 0,
          reason: 'coordinator recovery is silent for offline peers');
      await runtime.devices(deviceIds: ['peer'], includeCatalog: false);
      expect(runtime.cachedDevices.last['online'], isTrue);
      transport.peerPort = 3000;
      queriesFail = true;
      await runtime.devices(deviceIds: ['peer'], includeCatalog: false);
      expect(runtime.cachedDevices.last['online'], isFalse);
      expect(runtime.coordinatorSyncPending, isFalse,
          reason:
              'a failed address query does not mark the local report failed');
      queriesFail = false;
      advertisedPort = 3000;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final refresh = runtime.refreshDiscovery();
      expect(identical(refresh, runtime.refreshDiscovery()), isTrue);
      await refresh;
      await runtime.devices(deviceIds: ['peer'], includeCatalog: false);
      expect(runtime.cachedDevices.last['online'], isTrue);
      expect(runtime.rememberedRoutes['peer']?['port'], 3000);
      expect(transport.starts, 1,
          reason: 'refresh does not replace the listener');
      final count = queryCount;
      expect((await runtime.refreshDiscovery())['refreshRequested'], isFalse);
      expect(queryCount, count, reason: 'repeated clicks are throttled');

      expect(await replay.readAsString(), isEmpty);
      final reads = <String>[];
      runtime.chatRequest = (method, params, peer) async {
        expect(peer, 'peer');
        reads.add(method);
        return {};
      };
      var sequence = 0;
      JsonMap frame(String method, [JsonMap params = const {}]) {
        final id = '${'a' * 24}${++sequence}';
        return {
          'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params,
          'mesh': {'invocationId': id, 'nonce': 'nonce_$id',
            'deadline': DateTime.now().millisecondsSinceEpoch + 60000},
        };
      }
      runtime.hasDelivery = (peer) async => peer == 'peer';
      for (final method in ['mesh/chat/state', 'mesh/chat/threads',
        'mesh/chat/read', 'mesh/chat/events']) {
        final read = frame(method);
        final first = await transport.request(read);
        expect(first['result'], isNotNull);
        if (method == 'mesh/chat/events' || method == 'mesh/chat/state') {
          expect(first['deliveryPending'], true);
        }
        expect((await transport.request(read))['result'], isNotNull);
      }
      expect(reads, hasLength(8));
      expect(await replay.readAsString(), isEmpty);
      runtime.deliveryRequest = (peer, method, params) async {
        expect(peer, 'peer');
        expect(method, 'mesh/delivery/pull');
        expect(params['deviceId'], 'someone else');
        return {'rows': []};
      };
      final pull = frame('mesh/delivery/pull', {'deviceId': 'someone else'});
      expect((await transport.request(pull))['result'], {'rows': []});
      final replayed = await transport.request(pull);
      expect((replayed['error'] as Map)['data']['details']['reason'], 'replayed_invocation');
      expect(await replay.readAsLines(), hasLength(1));

      final pulled = Completer<String>();
      runtime.pullDelivery = (peer) async => pulled.complete(peer);
      await runtime.rpc('peer', 'mesh/presence', const {});
      expect(pulled.isCompleted, isFalse);
      transport.peerHasDelivery = true;
      await runtime.rpc('peer', 'mesh/presence', const {});
      expect(await pulled.future, 'peer');

      final devices = roster['devices'] as List<Map<String, Object?>>;
      final peer = devices.last;
      expect(runtime.deviceDeliveryFact('peer').failure, isNull);
      peer['last_seen_at'] = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch ~/ 1000;
      await runtime.refreshDevices();
      expect(runtime.deviceDeliveryFact('peer').failure, '目标设备已 7 天未上线');
      expect(runtime.deviceRemoved('peer'), isFalse);
      peer['revoked'] = true;
      await runtime.refreshDevices();
      expect(runtime.deviceDeliveryFact('peer').failure, '目标设备已撤销');
      expect(runtime.deviceRemoved('peer'), isTrue);
      devices.removeLast();
      await runtime.refreshDevices();
      expect(runtime.deviceDeliveryFact('peer').failure, '目标设备已不在账号设备名单中');
      expect(runtime.deviceRemoved('peer'), isTrue);
      await runtime.stop();
      final stoppedReports = reports;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(reports, stoppedReports);
    } finally {
      await runtime.close();
      await server.close(force: true);
      await root.delete(recursive: true);
      RustLib.dispose();
    }
  });
}
