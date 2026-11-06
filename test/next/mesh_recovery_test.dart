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
  final incoming = Completer<MeshIncoming>();
  var peerPort = 2000;
  var starts = 0;
  var calls = 0;
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
        return incoming.future;
      case #crateApiMeshMeshUpdateDevices:
        return Future<void>.value();
      case #crateApiMeshMeshStop:
        if (!incoming.isCompleted)
          incoming.completeError(StateError('stopped'));
        return Future<void>.value();
      case #crateApiMeshMeshSend:
        calls++;
        if (args[#device] == 'peer' && args[#port] != peerPort) {
          return Future<String>.error(
              const SocketException('connect: refused'));
        }
        final frame = jsonDecode(args[#body] as String) as Map;
        return Future<String>.value(
            jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': {}}));
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
