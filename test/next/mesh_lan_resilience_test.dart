@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/mesh/bonjour.dart';
import 'package:nipaplay/next/mesh/capability.dart';
import 'package:nipaplay/next/mesh/coordinator.dart';
import 'package:nipaplay/next/mesh/discovery.dart';
import 'package:nipaplay/next/mesh/library.dart';
import 'package:nipaplay/next/mesh/library_capability.dart';
import 'package:nipaplay/next/mesh/native.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/system_proxy_service.dart';
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'media_test_support.dart';
import 'support/platform.dart';

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

final class _EchoCapability implements Capability {
  @override
  List<Action> get actions => [_EchoAction()];
}

final class _EchoAction extends Action<MeshJson, MeshJson> {
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'download.echo',
        title: 'download.echo',
        description: 'Echo test payload',
        effect: Effect.write,
        input: ObjectSchema({'value': StringSchema()},
            additionalProperties: false),
        output:
            ObjectSchema({'value': StringSchema()}, additionalProperties: true),
      );
  @override
  MeshJson decodeInput(JsonMap json) => MeshJson(json);
  @override
  Future<Outcome<MeshJson>> run(MeshJson input, Invocation invocation) async =>
      Completed(MeshJson({...input.json, 'origin': invocation.origin}));
}

String _jwt(int id) => [
      base64Url.encode(utf8.encode('{"alg":"EdDSA"}')).replaceAll('=', ''),
      base64Url
          .encode(utf8.encode(jsonEncode({'userId': id, 'testOnly': true})))
          .replaceAll('=', ''),
      'synthetic-test-signature',
    ].join('.');

final class _ControllableCoordinator {
  _ControllableCoordinator(this.directory, this.caDirectory);
  final Directory directory, caDirectory;
  late HttpServer upstream;
  late Process coordinator;
  late HttpServer gate;
  late Uri coordinatorUri;
  late Uri gateUri;
  bool gateOpen = true;
  final requestCounts = <String, int>{};
  final logs = <String>[];

  int countFor(String method, String pathPrefix) =>
      requestCounts['$method $pathPrefix'] ?? 0;

  void resetCounts() => requestCounts.clear();

  Future<void> start() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final accepted = request.uri.path == '/dandanplay/api/v2/playhistory' &&
          request.headers.value('authorization') == 'Bearer ${_jwt(424242)}';
      request.response.statusCode = accepted ? 200 : 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': accepted}));
      await request.response.close();
    });

    final coordSocket =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final coordPort = coordSocket.port;
    await coordSocket.close();
    coordinatorUri = Uri.parse('http://127.0.0.1:$coordPort');

    coordinator = await Process.start(
      meshCoordinatorPath,
      [],
      includeParentEnvironment: false,
      environment: {
          ...windowsSystemEnvironment,
        'MESH_LISTEN_ADDR': '127.0.0.1:$coordPort',
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
      },
    );
    coordinator.stdout.transform(utf8.decoder).listen(logs.add);
    coordinator.stderr.transform(utf8.decoder).listen(logs.add);

    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      try {
        final response =
            await (await client.getUrl(coordinatorUri.resolve('/healthz')))
                .close();
        await response.drain<void>();
        break;
      } on SocketException {
        if (DateTime.now().isAfter(deadline)) {
          fail('Coordinator startup failed: ${logs.join()}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    client.close(force: true);

    gate = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gateUri = Uri.parse('http://127.0.0.1:${gate.port}');
    gate.listen((request) async {
      final key = '${request.method} ${request.uri.path}';
      requestCounts[key] = (requestCounts[key] ?? 0) + 1;
      if (!gateOpen) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      final forwardClient = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final target = coordinatorUri.replace(
          path: request.uri.path,
          query: request.uri.hasQuery ? request.uri.query : null,
        );
        final outReq = await forwardClient.openUrl(request.method, target);
        request.headers.forEach((name, values) {
          if (name.toLowerCase() == 'host') return;
          for (final v in values) {
            outReq.headers.add(name, v);
          }
        });
        final bodyBytes = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        if (bodyBytes.isNotEmpty) {
          outReq.add(bodyBytes);
        }
        final inResp = await outReq.close();
        request.response.statusCode = inResp.statusCode;
        inResp.headers.forEach((name, values) {
          for (final v in values) {
            request.response.headers.add(name, v);
          }
        });
        await inResp.pipe(request.response);
      } finally {
        forwardClient.close(force: true);
      }
    });
  }

  Future<void> close() async {
    await gate.close(force: true);
    coordinator.kill();
    await coordinator.exitCode;
    await upstream.close(force: true);
    await deleteTestDirectory(directory);
  }
}

void main() {
  late Directory caDirectory;
  late MeshNative native;
  late String caPem;

  setUpAll(() async {
    sqfliteFfiInit();
    caDirectory = await Directory.systemTemp.createTemp('mesh-lan-ca-');
    final bundledLibrary = Platform.environment['NIPAPLAY_MESH_TEST_LIBRARY'];
    if (Platform.isMacOS && bundledLibrary != null) {
      DynamicLibrary.open(
          '${File(bundledLibrary).absolute.parent.parent.path}/FlutterMacOS.framework/FlutterMacOS');
    }
    Future<void>? initialized;
    native = MeshNative(
      initialize: () => initialized ??= RustLib.init(
        externalLibrary: ExternalLibrary.open(
          File(bundledLibrary ??
                  meshNativeLibraryPath)
              .absolute
              .path,
        ),
      ),
    );
    await native.ready();
    final ca = await Process.run(
      meshCoordinatorPath,
      [
        '--generate-dev-ca',
        '${caDirectory.path}/ca.pem',
        '${caDirectory.path}/ca.key',
      ],
    );
    expect(ca.exitCode, 0, reason: ca.stderr.toString());
    caPem = await File('${caDirectory.path}/ca.pem').readAsString();
  });

  tearDownAll(() async {
    AppHttpProxy.clear();
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('');
    await caDirectory.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppHttpProxy.clear();
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('');
  });

  test(
      'MeshCoordinator uses AppHttpProxy and SystemProxyService while keeping loopback DIRECT',
      () async {
    AppHttpProxy.set('http://127.0.0.1:7890');
    expect(
      MeshCoordinator.resolveProxy(
          Uri.parse('https://nipaplay.aimes-soft.com/mesh/v1/devices')),
      'PROXY 127.0.0.1:7890',
    );
    expect(
      MeshCoordinator.resolveProxy(
          Uri.parse('http://127.0.0.1:18082/mesh/v1/devices')),
      'DIRECT',
    );
    expect(
      MeshCoordinator.resolveProxy(
          Uri.parse('http://localhost:18082/mesh/v1/devices')),
      'DIRECT',
    );

    AppHttpProxy.clear();
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('''
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 8899
  HTTPSEnable : 1
  HTTPSProxy : 127.0.0.1
  HTTPSPort : 8899
}
''');
    expect(
      MeshCoordinator.resolveProxy(
          Uri.parse('https://nipaplay.aimes-soft.com/mesh/v1/devices')),
      'PROXY 127.0.0.1:8899;DIRECT',
    );

    // Verify a live coordinator client actually routes through the configured proxy.
    final proxyRequests = <String>[];
    final proxyServer =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    proxyServer.listen((socket) async {
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      proxyRequests.add(line);
      socket.destroy();
    });
    try {
      AppHttpProxy.set('http://127.0.0.1:${proxyServer.port}');
      final coordinator = MeshCoordinator(
        Uri.parse('https://nipaplay.aimes-soft.com/mesh'),
        () async => _jwt(424242),
      );
      try {
        await expectLater(
          coordinator.request('GET', '/mesh/v1/devices'),
          throwsA(isA<Failure>()),
        );
        expect(proxyRequests, isNotEmpty);
        expect(proxyRequests.first, contains('nipaplay.aimes-soft.com:443'));
      } finally {
        coordinator.close();
      }
    } finally {
      await proxyServer.close();
    }
  });

  test(
      'R13: virtual interfaces are excluded and candidate ranking prioritizes remembered and same-subnet routes',
      () async {
    final discovery = MeshDiscovery(
      'A' * 43,
      47812,
      interfaces: () async => [
        (
          name: 'en0',
          addresses: [
            InternetAddress('192.168.1.10'),
            InternetAddress('fe80::1'),
          ],
        ),
        (
          name: 'docker0',
          addresses: [InternetAddress('172.17.0.1')],
        ),
        (
          name: 'br-9a8b7c',
          addresses: [InternetAddress('172.18.0.1')],
        ),
        (
          name: 'utun4',
          addresses: [InternetAddress('10.8.0.2')],
        ),
        (
          name: 'veth01',
          addresses: [InternetAddress('172.19.0.2')],
        ),
        (
          name: 'awdl0',
          addresses: [InternetAddress('169.254.10.20')],
        ),
      ],
    );

    final local = await discovery.localCandidates();
    expect(local, hasLength(1));
    expect(local.single['host'], '192.168.1.10');
    expect(local.single['port'], 47812);

    final rawCandidates = <JsonMap>[
      {'kind': 'lan', 'host': '172.17.0.1', 'port': 47812, 'priority': 100},
      {'kind': 'manual', 'host': '203.0.113.10', 'port': 47812, 'priority': 50},
      {'kind': 'lan', 'host': '192.168.1.25', 'port': 47812, 'priority': 100},
      {'kind': 'lan', 'host': '192.168.1.25', 'port': 47812, 'priority': 50},
    ];

    // On the home LAN (192.168.1.10): same-subnet 192.168.1.25 comes first,
    // then public manual 203.0.113.10, and unrelated private 172.17.0.1 last.
    final homeRanked =
        rankMeshCandidates(rawCandidates, localHosts: ['192.168.1.10']);
    expect(
      homeRanked.map((c) => c['host']).toList(),
      ['192.168.1.25', '203.0.113.10', '172.17.0.1'],
    );

    // With a remembered route, the remembered route always comes first.
    final withRemembered = rankMeshCandidates(
      [
        ...rawCandidates,
        {
          'kind': 'manual',
          'host': '203.0.113.10',
          'port': 47812,
          'priority': 1000
        },
      ],
      localHosts: ['192.168.1.10'],
    );
    expect(withRemembered.first['host'], '203.0.113.10');

    // Outside home (e.g. cellular/hotspot 172.20.10.2): public address comes
    // before unreachable home LAN private IP 192.168.1.25.
    final awayRanked = rankMeshCandidates(
      [
        {'kind': 'lan', 'host': '192.168.1.25', 'port': 47812, 'priority': 100},
        {
          'kind': 'public',
          'host': '203.0.113.10',
          'port': 47812,
          'priority': 50
        },
      ],
      localHosts: ['172.20.10.2'],
    );
    expect(
      awayRanked.map((c) => c['host']).toList(),
      ['203.0.113.10', '192.168.1.25'],
    );
  });

  test(
      'R13: Bonjour DNS-SD packet codec and live UDP discovery exchange peer hints',
      () async {
    const idA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const idB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

    final packet = MeshBonjour.encodeAnnouncement(
      deviceId: idA,
      port: 47812,
      addresses: [InternetAddress('192.168.1.42')],
      ttlSeconds: 120,
    );
    final decoded = MeshBonjour.decodePacket(packet);
    expect(decoded, isNotNull);
    expect(decoded!.isQueryForService, isFalse);
    expect(decoded.announcements, hasLength(1));
    expect(decoded.announcements.single.deviceId, idA);
    expect(decoded.announcements.single.port, 47812);
    expect(decoded.announcements.single.hosts, contains('192.168.1.42'));

    final query = MeshBonjour.encodeQuery();
    final decodedQuery = MeshBonjour.decodePacket(query);
    expect(decodedQuery, isNotNull);
    expect(decodedQuery!.isQueryForService, isTrue);

    // A resolver asking for the instance's own host name (what Apple's
    // NWBrowser does after it found the service) is answered too.
    final hostQuery =
        MeshBonjour.encodeQuery(service: 'someone.local', type: 1);
    expect(MeshBonjour.decodePacket(hostQuery)!.isQueryForService, isFalse);
    expect(
        MeshBonjour.decodePacket(hostQuery, ownHostName: 'someone.local')!
            .isQueryForService,
        isTrue);

    // Live socket exchange between two MeshBonjour instances on loopback.
    final discoveredByA = Completer<(String, String, int)>();
    final bonjourA = MeshBonjour(
      deviceId: idA,
      port: 41001,
      localAddresses: () async => [InternetAddress('192.168.1.11')],
      mdnsPort: 0,
      multicastAddress: InternetAddress.loopbackIPv4,
      allowInLabProfile: true,
      onPeerDiscovered: (peer, host, port, ttl) {
        if (!discoveredByA.isCompleted) {
          discoveredByA.complete((peer, host, port));
        }
      },
    );
    final bonjourB = MeshBonjour(
      deviceId: idB,
      port: 41002,
      localAddresses: () async => [InternetAddress('192.168.1.22')],
      mdnsPort: 0,
      multicastAddress: InternetAddress.loopbackIPv4,
      allowInLabProfile: true,
      onPeerDiscovered: (_, __, ___, ____) {},
    );
    try {
      await bonjourA.start();
      await bonjourB.start();
      // B sends a query to A's port, or B announces directly to A's port.
      await bonjourB.announce(
        targetAddress: InternetAddress.loopbackIPv4,
        targetPort: bonjourA.boundPort,
      );
      final (peer, host, port) =
          await discoveredByA.future.timeout(const Duration(seconds: 3));
      expect(peer, idB);
      expect(host, '192.168.1.22');
      expect(port, 41002);
    } finally {
      await bonjourA.close();
      await bonjourB.close();
    }
  });

  test(
      'R1, R2, R13 end-to-end: offline cache start, <1 day renewal rule, staggered parallel connect, route persistence, and rate-limit safety',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('mesh-lan-e2e-');
    final env = _ControllableCoordinator(tempDir, caDirectory);
    await env.start();
    final vault = _Vault();
    var simulatedNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final activeNodes = <MeshRuntime>[];

    Future<MeshRuntime> createNode(
      String name, {
      Directory? existingRoot,
      List<NetworkInterfaceSnapshot> interfaces = const [],
      Duration retryDelay = const Duration(milliseconds: 150),
    }) async {
      final root =
          existingRoot ?? await Directory('${tempDir.path}/$name').create();
      final runtime = MeshRuntime(
        root: root,
        vault: vault,
        native: native,
        authorize: (_, __) async => null,
        token: () async => _jwt(424242),
        coordinatorRetryDelay: retryDelay,
        candidateStaggerDelay: const Duration(milliseconds: 250),
        unknownPeerRefreshCooldown: const Duration(milliseconds: 100),
        // One tool per page: every catalogue read in this test has to be
        // reassembled from pages.
        toolsPageBytes: 1,
        interfaceProvider: () async => interfaces,
        clockSeconds: () => simulatedNow,
      );
      final harness = Harness([_EchoCapability(), MeshCapability(runtime)]);
      runtime.attach(harness);
      activeNodes.add(runtime);
      return runtime;
    }

    try {
      // 1. Initial enrollment of node A and node B.
      final a = await createNode('node-a');
      final b = await createNode('node-b');
      await File('${a.root.path}/mesh.json')
          .writeAsString(jsonEncode({'coordinator': env.gateUri.toString()}));
      await File('${b.root.path}/mesh.json')
          .writeAsString(jsonEncode({'coordinator': env.gateUri.toString()}));

      await a.join(
        ca: caPem,
        coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
        name: 'node-a',
        broadcast: false,
      );
      await a.setManualAddresses([
        {'kind': 'manual', 'host': '127.0.0.1', 'port': a.port}
      ]);
      await a.heartbeat(renew: false);

      await b.join(
        ca: caPem,
        coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
        name: 'node-b',
        broadcast: false,
      );
      await b.setManualAddresses([
        {'kind': 'manual', 'host': '127.0.0.1', 'port': b.port}
      ]);
      await b.heartbeat(renew: false);

      // Node A automatically learns about newly joined Node B when B connects
      // or via mesh/devices/changed, and invoking B works.
      final firstCall = await a.invoke(
        b.identity!.deviceId,
        'download.echo',
        {'value': 'ping'},
        destructive: false,
      );
      expect((firstCall as Completed).value.toJson()['value'], 'ping');

      // Verify route persistence file was written.
      final routesFileA = File('${a.root.path}/mesh-routes.json');
      expect(await routesFileA.exists(), isTrue);
      expect(a.rememberedRoutes[b.identity!.deviceId]?['port'], b.port);

      // 2. Test R13 staggered parallel candidate attempts:
      // Create a hanging TCP socket that accepts connections but never completes
      // TLS handshake (would block for 10s if tried sequentially).
      final hangingServer =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final acceptedSockets = <Socket>[];
      hangingServer.listen(acceptedSockets.add);
      try {
        await b.setManualAddresses([
          // Higher priority (overlay/manual) hanging port first, real port second:
          {'kind': 'overlay', 'host': '127.0.0.1', 'port': hangingServer.port},
          {'kind': 'manual', 'host': '127.0.0.1', 'port': b.port},
        ]);
        await b.heartbeat(renew: false);
        // Clear A's remembered route so A fetches both candidates from coordinator.
        await routesFileA.delete();
        final aPort = a.port;
        final bPort = b.port;
        await a.close();
        activeNodes.remove(a);

        // Restart A with fresh certificate (> 6 days remaining).
        env.resetCounts();
        final aRestarted = await createNode(
          'node-a',
          existingRoot: Directory('${tempDir.path}/node-a'),
        );
        await aRestarted.join(
          ca: caPem,
          coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
          name: 'node-a',
          listenPort: aPort,
          broadcast: false,
        );
        // Item 2 check: Certificate has >1 day remaining, so join MUST NOT renew!
        expect(env.countFor('POST', '/mesh/v1/devices/renew'), 0);

        final watch = Stopwatch()..start();
        final parallelOutcome = await aRestarted.invoke(
          b.identity!.deviceId,
          'download.echo',
          {'value': 'staggered-race'},
          destructive: false,
        );
        watch.stop();
        expect(
          (parallelOutcome as Completed).value.toJson()['value'],
          'staggered-race',
        );
        // Must succeed via 250ms staggered parallel attempt, well under the 10s timeout!
        expect(watch.elapsedMilliseconds, lessThan(2500));
        expect(
          aRestarted.rememberedRoutes[b.identity!.deviceId]?['port'],
          bPort,
        );

        // Make sure B also remembers A's route in mesh-routes.json.
        await b.invoke(
          aRestarted.identity!.deviceId,
          'download.echo',
          {'value': 'warm-route-b'},
          destructive: false,
        );

        // 3. Test R1: Stop both nodes, shut down coordinator gate, and cold-start
        // both nodes completely offline using cached certificates, cached device
        // rosters, and persisted routes!
        await aRestarted.close();
        activeNodes.remove(aRestarted);
        await b.close();
        activeNodes.remove(b);

        env.gateOpen = false;
        env.resetCounts();

        var aOffline = await createNode(
          'node-a',
          existingRoot: Directory('${tempDir.path}/node-a'),
          retryDelay: const Duration(milliseconds: 200),
        );
        var bOffline = await createNode(
          'node-b',
          existingRoot: Directory('${tempDir.path}/node-b'),
          retryDelay: const Duration(milliseconds: 200),
        );

        await aOffline.join(
          ca: caPem,
          coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
          name: 'node-a',
          listenPort: aPort,
          broadcast: false,
        );
        await bOffline.join(
          ca: caPem,
          coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
          name: 'node-b',
          listenPort: bPort,
          broadcast: false,
        );

        expect(aOffline.status, 'online');
        expect(bOffline.status, 'online');
        expect(aOffline.coordinatorSyncPending, isTrue);
        expect(bOffline.coordinatorSyncPending, isTrue);

        // Both nodes can invoke each other and list devices over LAN while
        // coordinator is completely unreachable!
        final offlineCallAB = await aOffline.invoke(
          bOffline.identity!.deviceId,
          'download.echo',
          {'value': 'lan-works-offline'},
          destructive: false,
        );
        expect(
          (offlineCallAB as Completed).value.toJson()['value'],
          'lan-works-offline',
        );

        final offlineDevices = await aOffline.devices();
        expect(offlineDevices['status'], 'online');
        final listedB = (offlineDevices['devices'] as List)
            .cast<JsonMap>()
            .singleWhere((d) => d['deviceId'] == bOffline.identity!.deviceId);
        expect(listedB['online'], isTrue);
        expect(
            (listedB['actions'] as List).cast<JsonMap>().map((a) => a['id']),
            containsAll(<String>[
              'download.echo',
              'mesh.devices',
              'mesh.invoke',
              'mesh.invoke_destructive',
            ]));
        // Offline: neither the join, the device list nor the route lookup
        // spent a single coordinator request on the roster or on addresses.
        expect(env.countFor('GET', '/mesh/v1/devices'), 0);
        expect(env.countFor('GET', '/mesh/v1/addresses'), 0);

        // 4. Simulate certificate having <1 day (< 86400s) left before bringing
        // coordinator back online, and verify background recovery renews the
        // certificate and refreshes the device list.
        for (final node in [aOffline, bOffline]) {
          final certFile = File('${node.root.path}/mesh-certificate.json');
          final certJson = jsonDecode(await certFile.readAsString()) as JsonMap;
          (certJson['certificate'] as JsonMap)['not_after'] =
              (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
          await certFile.writeAsString(jsonEncode(certJson), flush: true);
        }
        // Re-join while still offline so the <1 day cached expiry is loaded.
        await aOffline.close();
        activeNodes.remove(aOffline);
        await bOffline.close();
        activeNodes.remove(bOffline);
        aOffline = await createNode(
          'node-a',
          existingRoot: Directory('${tempDir.path}/node-a'),
          retryDelay: const Duration(milliseconds: 200),
        );
        bOffline = await createNode(
          'node-b',
          existingRoot: Directory('${tempDir.path}/node-b'),
          retryDelay: const Duration(milliseconds: 200),
        );
        await aOffline.join(
          ca: caPem,
          coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
          name: 'node-a',
          listenPort: aPort,
          broadcast: false,
        );
        await bOffline.join(
          ca: caPem,
          coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
          name: 'node-b',
          listenPort: bPort,
          broadcast: false,
        );
        expect(aOffline.coordinatorSyncPending, isTrue);
        expect(bOffline.coordinatorSyncPending, isTrue);

        env.resetCounts();
        env.gateOpen = true;

        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (aOffline.coordinatorSyncPending ||
            bOffline.coordinatorSyncPending ||
            env.countFor('POST', '/mesh/v1/devices/renew') < 2) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Timed out waiting for coordinator recovery: '
              'aPending=${aOffline.coordinatorSyncPending}, '
              'bPending=${bOffline.coordinatorSyncPending}, '
              'renews=${env.countFor("POST", "/mesh/v1/devices/renew")}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        expect(aOffline.coordinatorSyncPending, isFalse);
        expect(bOffline.coordinatorSyncPending, isFalse);
        expect(env.countFor('POST', '/mesh/v1/devices/renew'),
            greaterThanOrEqualTo(2));
        expect(
            env.countFor('GET', '/mesh/v1/devices'), greaterThanOrEqualTo(2));

        // Reset clock back to real time for subsequent operations.
        simulatedNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await aOffline.heartbeat(renew: true);
        await bOffline.heartbeat(renew: true);

        // 5. Test R2: Three devices running MeshLibrary concurrently do not
        // poll GET /mesh/v1/devices on library refresh, and revocation
        // propagates immediately via mesh/devices/changed notification.
        final c = await createNode('node-c');
        await File('${c.root.path}/mesh.json')
            .writeAsString(jsonEncode({'coordinator': env.gateUri.toString()}));
        await c.join(
          ca: caPem,
          coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
          name: 'node-c',
          broadcast: false,
        );
        await c.setManualAddresses([
          {'kind': 'manual', 'host': '127.0.0.1', 'port': c.port}
        ]);
        await c.heartbeat(renew: false);
        await c.notifyDevicesChanged(reason: 'joined');

        Future<UiDataService> attachLibrary(MeshRuntime node) async {
          final jobs =
              await SqliteJobStore.open(node.root, factory: databaseFactoryFfi);
          final identities =
              IdentityStore(jobs.database, node.identity!.deviceId);
          final media = MediaService(
            store: identities,
            providers: [],
            classic: MemoryClassic(),
            authorizedRoots: () => [tempDir.path],
          );
          final engine = TaskEngine(
            store: jobs,
            ownerDeviceId: identities.ownerDeviceId,
            executors: [],
          );
          await engine.start();
          final sources = StateSources();
          final danmaku = DanmakuService(
            store: DanmakuStore(identities),
            sources: [],
            player: NoPlayer(),
          );
          final state = StateCapability(publicStateViews(
            media: media,
            settings: SettingsRegistry(jobs.database, []),
            danmaku: danmaku,
            mesh: node,
            sources: sources,
          ));
          final ui = UiDataService(
            media,
            engine,
            state,
            sources,
            node.root,
            vault,
          );
          ui.subtitles = SubtitleLibrary(
            media,
            node.root,
            probe: (_) async => {'subtitles': <JsonMap>[]},
          );
          ui.meshLibrary = MeshLibrary(ui, node);
          registerMergedLibrary(state, ui.meshLibrary!);
          await ui.meshLibrary!.start();
          await ui.start();
          addTearDown(() async {
            await ui.close();
            await engine.close();
          });
          return ui;
        }

        final uiA = await attachLibrary(aOffline);
        final uiB = await attachLibrary(bOffline);
        final uiC = await attachLibrary(c);

        env.resetCounts();
        for (var i = 0; i < 5; i++) {
          await uiA.meshLibrary!.refresh();
          await uiB.meshLibrary!.refresh();
          await uiC.meshLibrary!.refresh();
        }
        // R2: Library refreshes must NOT trigger coordinator GET /mesh/v1/devices!
        expect(env.countFor('GET', '/mesh/v1/devices'), 0);

        // Now Node A revokes Node C: Node B must immediately learn of the
        // revocation via mesh/devices/changed without waiting for a heartbeat.
        await aOffline.revoke(c.identity!.deviceId);
        final bViewOfC = bOffline.cachedDevices
            .singleWhere((d) => d['deviceId'] == c.identity!.deviceId);
        expect(bViewOfC['revoked'], isTrue);
      } finally {
        for (final s in acceptedSockets) {
          s.destroy();
        }
        await hangingServer.close();
      }
    } finally {
      for (final node in activeNodes.reversed) {
        await node.close();
      }
      await env.close();
    }
  });

  test(
      'Bonjour on the real mDNS port: two members in one process join the group without throwing',
      () async {
    final a = MeshBonjour(
      deviceId: 'a' * 43,
      port: 41001,
      localAddresses: () async => const [],
      onPeerDiscovered: (_, __, ___, ____) {},
      allowInLabProfile: true,
    );
    final b = MeshBonjour(
      deviceId: 'b' * 43,
      port: 41002,
      localAddresses: () async => const [],
      onPeerDiscovered: (_, __, ___, ____) {},
      allowInLabProfile: true,
    );
    try {
      // `joinMulticast` fails with an OSError (EADDRINUSE on a second join of
      // the same interface), which once escaped MeshBonjour.start and stopped
      // the whole node from finishing its join.
      await a.start();
      await b.start();
    } finally {
      await a.close();
      await b.close();
    }
  });

  test(
      'R2: a peer cannot spend the coordinator budget with change notices, and an offline peer costs no repeated address lookups',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('mesh-lan-budget-');
    final env = _ControllableCoordinator(tempDir, caDirectory);
    await env.start();
    final vault = _Vault();
    final nodes = <MeshRuntime>[];
    Future<MeshRuntime> join(String name) async {
      final root = await Directory('${tempDir.path}/$name').create();
      final runtime = MeshRuntime(
        root: root,
        vault: vault,
        native: native,
        authorize: (_, __) async => null,
        token: () async => _jwt(424242),
        interfaceProvider: () async => const [],
      );
      runtime.attach(Harness([_EchoCapability(), MeshCapability(runtime)]));
      nodes.add(runtime);
      await File('${root.path}/mesh.json')
          .writeAsString(jsonEncode({'coordinator': env.gateUri.toString()}));
      await runtime.join(
        ca: caPem,
        coordinator: MeshCoordinator(env.gateUri, () async => _jwt(424242)),
        name: name,
        broadcast: false,
      );
      await runtime.setManualAddresses([
        {'kind': 'manual', 'host': '127.0.0.1', 'port': runtime.port}
      ]);
      await runtime.heartbeat(renew: false);
      return runtime;
    }

    try {
      final a = await join('budget-a');
      final b = await join('budget-b');

      // A refresh already on the wire may predate what the caller knows, so
      // concurrent callers get one follow-up, not the stale in-flight answer.
      env.resetCounts();
      await Future.wait(
          [a.refreshDevices(), a.refreshDevices(), a.refreshDevices()]);
      expect(env.countFor('GET', '/mesh/v1/devices'), 2);
      final completed = await a.invoke(
          b.identity!.deviceId, 'download.echo', {'value': 'x'},
          destructive: false);
      expect(completed, isA<Completed>());

      // B floods A with "roster changed" notices that carry no new revocation.
      env.resetCounts();
      for (var i = 0; i < 20; i++) {
        await b.rpc(a.identity!.deviceId, 'mesh/devices/changed',
            {'reason': 'flood', 'revocationEpoch': 0});
      }
      expect(env.countFor('GET', '/mesh/v1/devices'), 0,
          reason: 'notices inside the cooldown are merged, not forwarded');

      // B goes away; A keeps calling it (the library does every few seconds).
      final bId = b.identity!.deviceId;
      await b.close();
      nodes.remove(b);
      env.resetCounts();
      for (var i = 0; i < 6; i++) {
        // Nothing listens there: the connection fails first, the request never
        // left, and the failure says so (not "unknown").
        await expectLater(
            a.rpc(bId, 'mesh/describe', {}),
            throwsA(isA<Failure>()
                .having((f) => f.details['reason'], 'reason', 'not_delivered')
                .having((f) => f.details['stage'], 'stage', 'connect')
                .having((f) => f.retryable, 'retryable', true)));
      }
      expect(env.countFor('GET', '/mesh/v1/addresses'), lessThanOrEqualTo(1),
          reason:
              'one lookup for the failure after a success, none for the repeats');
    } finally {
      for (final node in nodes.reversed) {
        await node.close();
      }
      await env.close();
    }
  });
}
