@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/capability.dart';
import 'package:nipaplay/next/mesh/coordinator.dart';
import 'package:nipaplay/next/mesh/identity.dart';
import 'package:nipaplay/next/mesh/native.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/src/rust/frb_generated.dart';

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

final class _Observer implements InvocationObserver {
  final records = <InvocationRecord>[];
  @override
  void onInvocation(InvocationRecord record) => records.add(record);
}

final class _Actions implements Capability {
  _Actions(this.waitStarted, this.waitRelease);
  final Completer<void> waitStarted, waitRelease;
  @override
  List<Action> get actions => [
        _Action('download.echo', Effect.write),
        _Action('download.erase', Effect.destructive),
        _Action('playback.choose', Effect.write),
        _Action('credentials.hidden', Effect.read),
        _Action('task.wait', Effect.read,
            started: waitStarted, release: waitRelease),
      ];
}

final class _Action extends Action<MeshJson, MeshJson> {
  _Action(this.id, this.effect, {this.started, this.release});
  final String id;
  final Effect effect;
  final Completer<void>? started, release;
  @override
  ActionSpec get spec => ActionSpec(
      id: id,
      title: id,
      description: id,
      effect: effect,
      input: const ObjectSchema({'value': StringSchema()},
          additionalProperties: false),
      output: const ObjectSchema({'value': StringSchema()},
          additionalProperties: true));
  @override
  MeshJson decodeInput(JsonMap json) => MeshJson(json);
  @override
  Future<Outcome<MeshJson>> run(MeshJson input, Invocation invocation) async {
    if (id == 'task.wait') {
      started!.complete();
      await release!.future;
    }
    if (id == 'playback.choose') {
      return const NeedsDecision(
          Decision(prompt: 'Choose a remote operation.', options: [
        DecisionOption(
            label: 'Keep',
            call: ActionCall('download.echo', {'value': 'keep'})),
        DecisionOption(
            label: 'Erase',
            call: ActionCall('download.erase', {'value': 'erase'})),
      ]));
    }
    return Completed(MeshJson({...input.json, 'origin': invocation.origin}));
  }
}

String _jwt(int id) => [
      base64Url.encode(utf8.encode('{"alg":"EdDSA"}')).replaceAll('=', ''),
      base64Url
          .encode(utf8.encode(jsonEncode({'userId': id, 'testOnly': true})))
          .replaceAll('=', ''),
      'synthetic-test-signature',
    ].join('.');

final class _Rig {
  _Rig(this.directory, this.caDirectory, this.native);
  final Directory directory, caDirectory;
  final MeshNative native;
  late HttpServer upstream;
  late Process coordinator;
  late Uri base;
  final nodes = <MeshRuntime>[];
  final vault = _Vault();
  final observer = _Observer();
  final waitStarted = Completer<void>(), waitRelease = Completer<void>();
  final logs = <String>[];
  int renewCalls = 0;
  Future<void> start() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/dandanplay/api/v2/login/renew') {
        renewCalls++;
      }
      for (final name in ['x-appid', 'x-timestamp', 'x-signature']) {
        expect(request.headers.value(name), isNull);
      }
      final accepted = request.uri.path == '/dandanplay/api/v2/playhistory' &&
          [
            _jwt(424242),
            _jwt(515151)
          ].any((t) => request.headers.value('authorization') == 'Bearer $t');
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
  }

  Future<MeshRuntime> node(String name, {int account = 424242}) async {
    final root = await Directory('${directory.path}/$name').create();
    final mesh = MeshRuntime(
        root: root,
        vault: vault,
        native: native,
        token: () async => _jwt(account));
    final harness = Harness(
        [_Actions(waitStarted, waitRelease), MeshCapability(mesh)],
        observers: [observer]);
    mesh.attach(harness);
    nodes.add(mesh);
    await mesh.join(
        ca: await File('${caDirectory.path}/ca.pem').readAsString(),
        coordinator: MeshCoordinator(base, () async => _jwt(account)),
        name: name,
        broadcast: false);
    // Loopback is a manually supplied development address.
    await File('${root.path}/mesh.json')
        .writeAsString(jsonEncode({'coordinator': base.toString()}));
    await mesh.setManualAddresses([
      {'kind': 'manual', 'host': '127.0.0.1', 'port': mesh.port}
    ]);
    await mesh.heartbeat(renew: false);
    return mesh;
  }

  Future<String> issue(MeshIdentity identity,
      {String account = '424242',
      int validity = 3600,
      Directory? issuer}) async {
    final ca = issuer ?? caDirectory;
    final process =
        await Process.start('rust/mesh/target/debug/examples/issue', []);
    process.stdin.write(jsonEncode({
      'ca': '${ca.path}/ca.pem',
      'key': '${ca.path}/ca.key',
      'publicKey': identity.publicKey,
      'account': account,
      'validitySeconds': validity
    }));
    await process.stdin.close();
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0, reason: await errors);
    return output;
  }

  Future<void> close() async {
    if (!waitRelease.isCompleted) waitRelease.complete();
    for (final node in nodes.reversed) {
      await node.close();
    }
    coordinator.kill();
    await coordinator.exitCode;
    await upstream.close(force: true);
    expect(renewCalls, 0);
    await directory.delete(recursive: true);
  }
}

void main() {
  late Directory caDirectory;
  late MeshNative native;
  late _Rig rig;
  setUpAll(() async {
    for (final args in [
      ['build', '--manifest-path', 'rust/Cargo.toml'],
      [
        'build',
        '--manifest-path',
        'server/nipaplay-mesh-coordinator/Cargo.toml'
      ],
      [
        'build',
        '--manifest-path',
        'rust/mesh/Cargo.toml',
        '--example',
        'issue'
      ],
    ]) {
      final result = await Process.run('cargo', args);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }
    caDirectory = await Directory.systemTemp.createTemp('mesh-dev-ca-');
    final bundledLibrary = Platform.environment['NIPAPLAY_MESH_TEST_LIBRARY'];
    if (Platform.isMacOS && bundledLibrary != null) {
      // flutter_tester does not have the application's framework search path.
      DynamicLibrary.open(
          '${File(bundledLibrary).absolute.parent.parent.path}/FlutterMacOS.framework/FlutterMacOS');
    }
    Future<void>? initialized;
    native = MeshNative(
        initialize: () => initialized ??= RustLib.init(
            externalLibrary: ExternalLibrary.open(File(bundledLibrary ??
                    'rust/target/debug/librust_lib_nipaplay.${Platform.isMacOS ? 'dylib' : 'so'}')
                .absolute
                .path)));
    await native.ready();
    final ca = await Process.run(
        'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator',
        [
          '--generate-dev-ca',
          '${caDirectory.path}/ca.pem',
          '${caDirectory.path}/ca.key'
        ]);
    expect(ca.exitCode, 0, reason: ca.stderr.toString());
  });
  tearDownAll(() async {
    await caDirectory.delete(recursive: true);
  });
  setUp(() async {
    rig = _Rig(await Directory.systemTemp.createTemp('mesh-tls-'), caDirectory,
        native);
    await rig.start();
  });
  tearDown(() => rig.close());

  test('two real TLS nodes invoke the same Harness and wrap decision effects',
      () async {
    final a = await rig.node('a'), b = await rig.node('b');
    await a.refreshDevices();
    final listed = await a.devices();
    final devices = (listed['devices'] as List).cast<JsonMap>();
    final remote =
        devices.singleWhere((d) => d['deviceId'] == b.identity!.deviceId);
    expect(remote['online'], true);
    final cached = a.cachedDevices
        .singleWhere((device) => device['deviceId'] == b.identity!.deviceId);
    expect(cached['name'], remote['device_name']);
    expect(cached['platform'], remote['platform']);
    expect(cached['online'], true);
    expect(
        DateTime.parse(cached['lastSeenAt'] as String).millisecondsSinceEpoch,
        (remote['last_seen_at'] as int) * 1000);
    expect(cached.keys, isNot(contains('device_public_key')));
    expect((remote['actions'] as List).map((a) => (a as JsonMap)['id']),
        isNot(contains('credentials.hidden')));
    final echo = (remote['actions'] as List)
        .cast<JsonMap>()
        .singleWhere((action) => action['id'] == 'download.echo');
    expect((echo['outputSchema'] as JsonMap)['properties'], contains('value'));
    final result = await a.invoke(
        b.identity!.deviceId, 'download.echo', {'value': 'hello'},
        destructive: false);
    expect(result.toEnvelope()['result'],
        {'value': 'hello', 'origin': 'mesh:${a.identity!.deviceId}'});
    expect(
        (await b.invoke(
            a.identity!.deviceId, 'download.echo', {'value': 'back'},
            destructive: false)),
        isA<Completed>());
    final denied = a.invoke(b.identity!.deviceId, 'download.erase', {},
        destructive: false);
    await expectLater(
        denied,
        throwsA(isA<Failure>()
            .having((e) => e.code, 'code', FailureCode.invalidInput)));
    await expectLater(
        a.invoke(b.identity!.deviceId, 'download.echo', {}, destructive: true),
        throwsA(isA<Failure>()));
    final choice = await a.invoke(b.identity!.deviceId, 'playback.choose', {},
        destructive: false) as NeedsDecision;
    expect(choice.decision.options.map((o) => o.call.actionId),
        ['mesh.invoke', 'mesh.invoke_destructive']);
    final call = choice.decision.options.last.call;
    expect(call.input['deviceId'], b.identity!.deviceId);
    final local = Harness([MeshCapability(a)]);
    expect(
        await local.invokeJson(
            call.actionId, call.input, Invocation(origin: 'test')),
        isA<Completed>());
    final path = await File('${a.root.path}/mesh-identity.json').readAsString();
    expect(path, isNot(contains(await a.identity!.privateKey())));
    final old = a.identity!;
    final loaded = await MeshIdentity.load(a.root, rig.vault, native);
    expect(loaded.deviceId, old.deviceId);
    expect(a.identity!.deviceId, isNot(b.identity!.deviceId));
  });

  test(
      'replayed invocation id, repeated nonce, and expired deadline never execute twice',
      () async {
    final a = await rig.node('a'), b = await rig.node('b');
    await a.refreshDevices();
    final frame = <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'rpc-1',
      'method': 'tools/call',
      'params': {
        'name': 'download_echo',
        'arguments': {'value': 'once'},
        'meshDestructive': false
      },
      'mesh': {
        'invocationId': 'test-invocation-0123456789',
        'nonce': 'test-nonce-01234567890123',
        'deadline': DateTime.now().millisecondsSinceEpoch + 60000
      },
    };
    await a.rpc(b.identity!.deviceId, 'tools/call', {}, replayFrame: frame);
    await expectLater(
        a.rpc(b.identity!.deviceId, 'tools/call', {}, replayFrame: frame),
        throwsA(isA<Failure>()));
    final peerId = b.identity!.deviceId;
    await b.close();
    final restarted = await rig.node('b');
    expect(restarted.identity!.deviceId, peerId);
    await a.rpc(peerId, 'tools/list', {});
    await expectLater(a.rpc(peerId, 'tools/call', {}, replayFrame: frame),
        throwsA(isA<Failure>()));
    (frame['mesh'] as JsonMap)['invocationId'] =
        'test-invocation-different-012345';
    await expectLater(
        a.rpc(b.identity!.deviceId, 'tools/call', {}, replayFrame: frame),
        throwsA(isA<Failure>()));
    (frame['mesh'] as JsonMap)['nonce'] = 'test-nonce-different-0123456';
    (frame['mesh'] as JsonMap)['deadline'] =
        DateTime.now().millisecondsSinceEpoch - 1;
    await expectLater(
        a.rpc(b.identity!.deviceId, 'tools/call', {}, replayFrame: frame),
        throwsA(isA<Failure>()));
    expect(rig.observer.records.where((r) => r.actionId == 'download.echo'),
        hasLength(1));
  });

  test('heartbeat revocation aborts a live TLS call and refuses new sessions',
      () async {
    final a = await rig.node('a'), b = await rig.node('b');
    await a.refreshDevices();
    final pending =
        a.invoke(b.identity!.deviceId, 'task.wait', {}, destructive: false);
    final rejected = expectLater(pending, throwsA(isA<Failure>()));
    await rig.waitStarted.future;
    // Simulate another signed-in host revoking the caller.
    final admin = MeshCoordinator(rig.base, () async => _jwt(424242));
    await admin.request(
        'POST',
        '/mesh/v1/devices/${a.identity!.deviceId}/revoke',
        {'device_id': a.identity!.deviceId});
    admin.close();
    await b.heartbeat(renew: false);
    await rejected.timeout(const Duration(seconds: 2));
    await expectLater(
        a.invoke(b.identity!.deviceId, 'download.echo', {}, destructive: false),
        throwsA(isA<Failure>()));
    await expectLater(a.heartbeat(renew: false), throwsA(isA<Failure>()));
    expect(a.status, 'device_revoked');
    expect(a.port, 0);
  });

  test(
      'valid chains from a different account are rejected before Harness dispatch',
      () async {
    final a = await rig.node('a'), b = await rig.node('b', account: 515151);
    // Native caller knows the public destination, but the account must still match.
    final leaf = await rig.issue(a.identity!);
    final node = await native.start(
        ca: await File('${caDirectory.path}/ca.pem').readAsString(),
        certificate: leaf,
        key: await a.identity!.privateKey(),
        account: '424242',
        allowed: [a.identity!.deviceId, b.identity!.deviceId],
        bind: '127.0.0.1:0');
    try {
      await expectLater(
          native.send(node, '127.0.0.1', b.port, b.identity!.deviceId, '{}'),
          throwsA(anything));
      expect(rig.observer.records, isEmpty);
    } finally {
      await native.stop(node);
    }
  });

  test('an expired client certificate is rejected by real mutual TLS',
      () async {
    final a = await rig.node('a'), b = await rig.node('b');
    final leaf = await rig.issue(a.identity!, validity: 2);
    final node = await native.start(
        ca: await File('${caDirectory.path}/ca.pem').readAsString(),
        certificate: leaf,
        key: await a.identity!.privateKey(),
        account: '424242',
        allowed: [a.identity!.deviceId, b.identity!.deviceId],
        bind: '127.0.0.1:0');
    try {
      await Future<void>.delayed(const Duration(seconds: 3));
      await expectLater(
          native.send(node, '127.0.0.1', b.port, b.identity!.deviceId, '{}'),
          throwsA(anything));
      expect(rig.observer.records, isEmpty);
    } finally {
      await native.stop(node);
    }
  });

  test('an untrusted issuer is rejected by real mutual TLS', () async {
    final a = await rig.node('a'), b = await rig.node('b');
    final rogue = await Directory('${rig.directory.path}/rogue').create();
    final ca = await Process.run(
        'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator',
        ['--generate-dev-ca', '${rogue.path}/ca.pem', '${rogue.path}/ca.key']);
    expect(ca.exitCode, 0);
    final leaf = await rig.issue(a.identity!, issuer: rogue);
    final node = await native.start(
        ca: '${await File('${caDirectory.path}/ca.pem').readAsString()}\n${await File('${rogue.path}/ca.pem').readAsString()}',
        certificate: leaf,
        key: await a.identity!.privateKey(),
        account: '424242',
        allowed: [a.identity!.deviceId, b.identity!.deviceId],
        bind: '127.0.0.1:0');
    try {
      await expectLater(
          native.send(node, '127.0.0.1', b.port, b.identity!.deviceId, '{}'),
          throwsA(anything));
      expect(rig.observer.records, isEmpty);
    } finally {
      await native.stop(node);
    }
  });
}
