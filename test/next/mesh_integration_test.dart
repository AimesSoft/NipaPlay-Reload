@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/capability.dart';
import 'package:nipaplay/next/db/capability.dart';
import 'package:nipaplay/next/db/service.dart';
import 'package:nipaplay/next/mesh/coordinator.dart';
import 'package:nipaplay/next/mesh/identity.dart';
import 'package:nipaplay/next/mesh/native.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/next/mesh/library.dart';
import 'package:nipaplay/next/mesh/files.dart';
import 'package:crypto/crypto.dart';
import 'package:nipaplay/next/mesh/library_capability.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/metadata_facts.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/metadata_provider.dart' show ExternalRef;
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/change_history.dart';
import 'package:nipaplay/next/system/operation_observations.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'media_test_support.dart';
import 'support/platform.dart';

part 'mesh_library_experiment.dart';
part 'mesh_files_experiment.dart';
part 'mesh_headless_experiment.dart';

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
  int? _port;
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
    final port = _port = socket.port;
    await socket.close();
    base = Uri.parse('http://127.0.0.1:$port');
    await _spawnCoordinator();
  }

  /// Stops the coordinator and starts it again on the same address and
  /// database, with [environment] added to its configuration.
  Future<void> restartCoordinator([Map<String, String> environment = const {}]) async {
    coordinator.kill();
    await coordinator.exitCode;
    await _spawnCoordinator(environment);
  }

  Future<void> _spawnCoordinator([Map<String, String> extra = const {}]) async {
    final port = _port!;
    coordinator = await Process.start(
        meshCoordinatorPath,
        [],
        includeParentEnvironment: false,
        environment: {
          ...windowsSystemEnvironment,
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
          ...extra,
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

  Future<MeshRuntime> node(String name, {int account = 424242, Future<Failure?> Function(String, String)? authorize, Future<String?> Function()? token}) async {
    final root = await Directory('${directory.path}/$name').create();
    token ??= () async => _jwt(account);
    final mesh = MeshRuntime(
        root: root,
        vault: vault,
        native: native,
        authorize: authorize ?? authorizeMeshPeer,
        token: token);
    final harness = Harness(
        [_Actions(waitStarted, waitRelease), MeshCapability(mesh)],
        observers: [observer]);
    mesh.attach(harness);
    nodes.add(mesh);
    await mesh.join(
        ca: await File('${caDirectory.path}/ca.pem').readAsString(),
        coordinator: MeshCoordinator(base, token),
        name: name,
        broadcast: false);
    await RemoteControlSettings.addTrustedDevice({
      'clientKey': 'id:${mesh.identity!.deviceId}',
      'clientId': mesh.identity!.deviceId,
      'clientName': name,
    });
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
        await Process.start(meshIssueExamplePath, []);
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
  final reuseX47Evidence = Platform.environment['NIPAPLAY_X47_REUSE_EVIDENCE'] == '1' ? '按任务要求沿用已记录的 X47 实验，不重复运行' : false;
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
                    meshNativeLibraryPath)
                .absolute
                .path)));
    await native.ready();
    final ca = await Process.run(
        meshCoordinatorPath,
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
    SharedPreferences.setMockInitialValues({});
    rig = _Rig(await Directory.systemTemp.createTemp('mesh-tls-'), caDirectory,
        native);
    await rig.start();
  });
  tearDown(() => rig.close());

  test('X47c separate headless process serves catalogue and files', () => x47HeadlessExperiment(rig), skip: Platform.environment['NIPAPLAY_X47_HEADLESS_BINARY'] == null ? '独立 AOT 实验需显式提供构建路径；见 X47_REPORT' : reuseX47Evidence);

  test('X47c catalogue evolution preserves IDs and metadata', () => x47CatalogueEvolution(rig), skip: reuseX47Evidence);

  test('X47c file tools need only Mesh identity and preserve decision effects', () => x47FileToolsExperiment(rig), skip: reuseX47Evidence);

  test('X47c local file primitives work before joining and redact payload journal', () => x47LocalFilesConstraint(rig));

  test('X47c proxy random tokens fixed port and occupied fallback', () => x47ProxyReview(rig));

  test('X47c files outside library and destructive decisions', () => x47FilesExperiment(rig), skip: reuseX47Evidence);

  test('X47 merged library and real TLS video Range and seeking', () => x47LibraryExperiment(rig), timeout: const Timeout(Duration(minutes: 5)), skip: reuseX47Evidence);

  test('library status is readable while a remote catalogue request is still running', () async {
    final a = await rig.node('status-reader'), b = await rig.node('status-owner');
    await a.refreshDevices();
    final data = await x47Data(rig, a);
    await x47Data(rig, b);
    final entered = Completer<void>(), release = Completer<void>();
    final original = b.libraryRequest!;
    b.libraryRequest = (method, input, peer) async {
      if (method == 'mesh/library/snapshot' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
      return original(method, input, peer);
    };
    final pending = data.meshLibrary!.refresh();
    try {
      await entered.future;
      final h = Harness([MeshLibraryCapability(data.meshLibrary!)]);
      final outcome = await h.invokeJson('media.library.status', {}, Invocation(origin: 'test'))
          .timeout(const Duration(seconds: 1));
      final facts = (outcome as Completed).value.toJson();
      expect(facts['refreshInProgress'], true);
      final peer = (facts['peers'] as List).cast<Map>().singleWhere((p) => p['deviceId'] == b.identity!.deviceId);
      expect(peer['refreshing'], true);
      expect(peer['reachability'], 'unknown');
      expect(peer['catalogueFreshness'], 'not_refreshed');
    } finally {
      release.complete();
      await pending;
    }
  });

  test('large rich metadata crosses real TLS without repeating the operation', () async {
    final a = await rig.node('a'), b = await rig.node('b');
    await a.refreshDevices();
    var executions = 0;
    final expected = '中文演职员、角色与完整来源资料' * 80000;
    b.libraryRequest = (method, input, peer) async {
      executions++;
      return {'metadata': expected};
    };
    final result = await a.rpc(b.identity!.deviceId, 'mesh/library/large-test', {});
    expect(result['metadata'], expected);
    expect(executions, 1);
  });

  test('real TLS exposes correlated process facts without recording diagnostic polling', () async {
    final a = await rig.node('observer'), b = await rig.node('observed');
    b.attach(Harness([
      InvocationScopeCapability(_Actions(Completer<void>(), Completer<void>())),
      InvocationScopeCapability(const OperationObservationsCapability()),
    ]));
    await a.refreshDevices();
    final peer = b.identity!.deviceId;
    await a.invoke(peer, 'download.echo', {'value': 'PRIVATE_INPUT'}, destructive: false);
    final outbound = (OperationObservations.current.read({
      'peerId': peer, 'action': 'download.echo',
    })['records'] as List).cast<Map>().singleWhere((r) => r['direction'] == 'outbound');
    Future<JsonMap> query() async {
      final result = await a.invoke(peer, 'diagnostics.operations', {
        'invocationId': outbound['invocationId'],
      }, destructive: false);
      return (result as Completed).value.toJson();
    }
    final facts = await query();
    final records = (facts['records'] as List).cast<Map>();
    expect(records.any((r) => r['stage'] == 'action_completed' && r['action'] == 'download.echo'), true);
    expect(records.any((r) => r['direction'] == 'inbound' &&
        (r['stages'] as List).any((s) => s['stage'] == 'request_received')), true);
    expect(jsonEncode(facts), isNot(contains('PRIVATE_INPUT')));
    final next = await query();
    expect(next['next'], facts['next']);
    expect(OperationObservations.current.read({'action': 'diagnostics.operations'})['records'], isEmpty);
  });

  test('real TLS discovers SQL and recovers write and undo receipts on the target', () async {
    final a = await rig.node('sql-reader'), b = await rig.node('sql-owner');
    await a.refreshDevices();
    final fixture = MediaFixture();
    await fixture.open();
    final database = fixture.jobs.database;
    try {
      await database.insert('media_entities', {'id': 'sql-work', 'kind': 'work', 'revision': 0, 'attributes': '{"title":"SQL target","localOnly":true}'});
      var service = DbService(database);
      b.attach(Harness([DbCapability(service)]));
      final peer = b.identity!.deviceId;
      Future<JsonMap> remote(String action, JsonMap input) async {
        final result = await a.invoke(peer, action, input, destructive: false);
        expect(result, isA<Completed>(), reason: jsonEncode(result.toEnvelope()));
        return (result as Completed).value.toJson();
      }
      final listed = await a.devices(deviceIds: [peer]);
      final actions = ((listed['devices'] as List).single as Map)['actions'] as List;
      expect(actions.map((a) => (a as Map)['id']).toSet(), {'db.describe', 'db.query', 'db.write', 'db.undo', 'db.receipt'});
      await remote('db.describe', {'tables': ['media_entities', 'db_operations']});
      final before = await remote('db.query', {'sql': "SELECT revision FROM media_entities WHERE id='sql-work'"});
      expect((before['rows'] as List).single, {'revision': 0});
      final p = await remote('db.write', {'statements': [{'sql': "UPDATE media_entities SET revision=revision+1 WHERE id='sql-work'"}]});
      final input = <String, Object?>{'previewId': p['previewId']};
      final committedAtTarget = Completer<void>(), releaseRefresh = Completer<void>();
      service.afterCommit = (_) async {
        committedAtTarget.complete();
        await releaseRefresh.future;
        return [];
      };
      // Cut the caller's real TLS node after the transaction is durable but
      // before the response exists. Its next invocation uses a fresh RPC nonce
      // and the same previewId, recovering the domain receipt.
      final lostResponse = a.invoke(peer, 'db.write', input, destructive: false);
      final lost = expectLater(lostResponse, throwsA(isA<Failure>().having(
          (e) => e.details['reason'], 'reason', 'outcome_unknown')));
      await committedAtTarget.future;
      try { await a.stop(); await lost; }
      finally { releaseRefresh.complete(); }
      await a.join(
          ca: await File('${rig.caDirectory.path}/ca.pem').readAsString(),
          coordinator: MeshCoordinator(rig.base, () async => _jwt(424242)),
          name: 'sql-reader', broadcast: false);
      final receipt = await remote('db.receipt', {'kind': 'write', 'requestKey': p['previewId']});
      expect(receipt['state'], 'committed');
      final done = await remote('db.write', input);
      expect(done['committed'], true);
      service = DbService(database);
      b.attach(Harness([DbCapability(service)]));
      expect(await remote('db.write', input), done);
      expect((await database.query('db_commits')).single['origin'], 'mesh:${a.identity!.deviceId}');
      final undoInput = <String, Object?>{'commitId': done['commitId'], 'requestId': 'sql-undo-1'};
      final undone = await remote('db.undo', undoInput);
      b.attach(Harness([DbCapability(DbService(database))]));
      expect(await remote('db.undo', undoInput), undone);
      expect(await database.query('db_commits'), hasLength(2));
      expect((await database.query('media_entities', where: "id='sql-work'")).single['revision'], 0);
      final large = await remote('db.query', {'sql': "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<500) SELECT x, printf('%01900d',x) AS text FROM n", 'limit': 500, 'maxBytes': 1048576});
      expect(large['rowCount'], 500);
      expect(((large['rows'] as List).last as Map)['text'], endsWith('500'));
      expect(utf8.encode(jsonEncode(large)).length, greaterThan(512 * 1024));
    } finally { await fixture.close(); }
  });

  test('real TLS previews merges and undoes on the owner with durable request receipts', () async {
    final a=await rig.node('merge-reader'), b=await rig.node('merge-owner');
    await a.refreshDevices();
    final f=MediaFixture();
    await f.open();
    try {
      for(final id in ['duplicate','survivor']) {
        await f.jobs.database.insert('media_entities',{'id':id,'kind':'work','revision':0,'attributes':'{"title":"Same work","localOnly":true}'});
      }
      b.attach(f.harness);
      final peer=b.identity!.deviceId;
      Future<JsonMap> remote(String action,JsonMap input) async {
        final out=await a.invoke(peer,action,input,destructive:false);
        expect(out,isA<Completed>(),reason:jsonEncode(out.toEnvelope()));
        return (out as Completed).value.toJson();
      }
      final input=<String,Object?>{'sourceWorkId':'duplicate','targetWorkId':'survivor','requestId':'merge-over-mesh','reason':'Same source work'};
      final p=await remote('media.management.merge_work',input);
      expect(p['canCommit'],isTrue);
      final apply={...input,'expectedPlan':p['expectedPlan']};
      final done=await remote('media.management.merge_work',apply);
      await f.reopen();
      b.attach(f.harness);
      expect(await remote('media.management.merge_work',apply),done);
      expect((await f.jobs.database.query('media_work_merges')).single['origin'],'mesh:${a.identity!.deviceId}');
      final undo=<String,Object?>{'mergeId':done['mergeId'],'requestId':'undo-over-mesh','reason':'Restore source'};
      final up=await remote('media.management.undo_merge',undo);
      final undoApply={...undo,'expectedPlan':up['expectedPlan']};
      final undone=await remote('media.management.undo_merge',undoApply);
      expect(await remote('media.management.undo_merge',undoApply),undone);
      expect(await f.jobs.database.query('media_entity_aliases'),isEmpty);
      expect(await f.identities.library(),hasLength(2));
    } finally { await f.close(); }
  });

  test('two real TLS nodes invoke the same Harness and wrap decision effects',
      () async {
    var classicApprovals = 0;
    final a = await rig.node('a'), b = await rig.node('b', authorize: (_, __) async {
      classicApprovals++;
      return const Failure(FailureCode.unavailable, 'Classic receiver is disabled.');
    });
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
    expect(classicApprovals, 0);
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

  test('bulk reads do not spend the durable invocation budget or block presence', () async {
    final a = await rig.node('budget-reader');
    final root = await Directory('${rig.directory.path}/budget-source').create();
    final expiry = DateTime.now().millisecondsSinceEpoch + 3590000;
    await File('${root.path}/mesh-replay.jsonl').writeAsString([
      for (var i = 0; i < 9990; i++) jsonEncode({'keys': [
        '${a.identity!.deviceId}:id:seed-$i', '${a.identity!.deviceId}:nonce:seed-$i'], 'deadline': expiry})
    ].join('\n'));
    final b = await rig.node('budget-source');
    await a.refreshDevices();
    var reads = 0;
    b.libraryRequest = (_, __, ___) async { reads++; return {'data': ''}; };
    final before = await File('${root.path}/mesh-replay.jsonl').length();
    for (var i = 0; i < 25; i++) {
      expect(await a.rpc(b.identity!.deviceId, 'mesh/library/read', {}), {'data': ''});
    }
    expect(reads, 25);
    expect(await File('${root.path}/mesh-replay.jsonl').length(), before);
    expect(await a.rpc(b.identity!.deviceId, 'mesh/presence', {}), isNotEmpty);
  });

  test('stop invalidates a login read suspended during startup', () async {
    final entered = Completer<void>(), token = Completer<String?>();
    final node = MeshRuntime(root: await Directory('${rig.directory.path}/stopping').create(),
      vault: rig.vault, native: native, token: () { entered.complete(); return token.future; });
    final starting = node.startConfigured();
    await entered.future;
    final stopping = node.stop();
    token.complete(null);
    await Future.wait([starting, stopping]);
    expect(node.status, 'disabled');
    expect(node.runtimeFacts['loginWatchActive'], false);
    await node.close();
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
        meshCoordinatorPath,
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
  test('a certificate from the standby root is accepted next to the primary root and nowhere else',
      () async {
    final a = await rig.node('a');
    final standby = await Directory('${rig.directory.path}/standby').create();
    final generated = await Process.run(
        'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator',
        ['--generate-ca', '${standby.path}/ca.pem', '${standby.path}/ca.key']);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());
    final primaryPem = await File('${caDirectory.path}/ca.pem').readAsString();
    final standbyPem = await File('${standby.path}/ca.pem').readAsString();
    final key = await a.identity!.privateKey();
    final fromPrimary = await rig.issue(a.identity!);
    final fromStandby = await rig.issue(a.identity!, issuer: standby);
    // The two roots have the same subject name; the right one must be found
    // by its key, whichever order the bundle lists them in.
    for (final bundle in ['$primaryPem\n$standbyPem', '$standbyPem\n$primaryPem']) {
      await native.validate(bundle, fromPrimary, key, '424242');
      await native.validate(bundle, fromStandby, key, '424242');
    }
    await expectLater(native.validate(primaryPem, fromStandby, key, '424242'), throwsA(anything));
    await expectLater(native.validate(standbyPem, fromPrimary, key, '424242'), throwsA(anything));
  });

  test('a device renews with its key alone after its account token has expired',
      () async {
    await rig.restartCoordinator({'MESH_CERT_VALIDITY_SECONDS': '900'});
    var token = _jwt(424242);
    final a = await rig.node('a', token: () async => token);
    final before = await File('${a.root.path}/mesh-certificate.json').readAsString();
    // The upstream no longer accepts the token (expired): everything that
    // needs the account fails, but the certificate is renewed by the key.
    token = 'expired.token.value';
    await Future<void>.delayed(const Duration(seconds: 1));
    await expectLater(a.heartbeat(renew: true), throwsA(isA<Failure>()));
    final after = await File('${a.root.path}/mesh-certificate.json').readAsString();
    expect(((jsonDecode(after) as JsonMap)['certificate'] as JsonMap)['pem'],
        isNot(((jsonDecode(before) as JsonMap)['certificate'] as JsonMap)['pem']));
    expect(a.status, 'online');
    // Still serving on the LAN with the renewed certificate.
    final b = await rig.node('b');
    await b.refreshDevices();
    expect(b.cachedDevices.where((d) => d['deviceId'] == a.identity!.deviceId), isNotEmpty);
  });

  test('a device whose certificate ran out while its token expired rejoins from its cache by key',
      () async {
    final first = await rig.node('a');
    final root = first.root;
    final identity = first.identity!;
    await first.close();
    // The certificate it holds ran out two seconds after it was issued.
    final short = await rig.issue(identity, validity: 2);
    final saved = jsonDecode(await File('${root.path}/mesh-certificate.json').readAsString()) as JsonMap;
    final notAfter = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2;
    await File('${root.path}/mesh-certificate.json').writeAsString(jsonEncode({
      ...saved,
      'certificate': {'pem': short, 'not_before': notAfter - 100, 'not_after': notAfter},
    }));
    await Future<void>.delayed(const Duration(seconds: 3));
    final mesh = MeshRuntime(
        root: root,
        vault: rig.vault,
        native: native,
        token: () async => 'expired.token.value');
    mesh.attach(Harness([_Actions(rig.waitStarted, rig.waitRelease), MeshCapability(mesh)]));
    rig.nodes.add(mesh);
    await mesh.join(
        ca: await File('${caDirectory.path}/ca.pem').readAsString(),
        coordinator: MeshCoordinator(rig.base, () async => 'expired.token.value'),
        name: 'a',
        broadcast: false);
    expect(mesh.status, 'online');
    expect(mesh.port, greaterThan(0));
    final renewed = jsonDecode(await File('${root.path}/mesh-certificate.json').readAsString()) as JsonMap;
    expect((renewed['certificate'] as JsonMap)['not_after'], greaterThan(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600));
    expect(mesh.cachedDevices, isNotEmpty);
  });

  test('a removed device learns it from the coordinator when it renews and stops serving',
      () async {
    await rig.restartCoordinator({'MESH_CERT_VALIDITY_SECONDS': '900'});
    final a = await rig.node('a');
    final admin = MeshCoordinator(rig.base, () async => _jwt(424242));
    await admin.request('POST', '/mesh/v1/devices/${a.identity!.deviceId}/revoke',
        {'device_id': a.identity!.deviceId});
    admin.close();
    await expectLater(a.heartbeat(renew: true), throwsA(isA<Failure>()));
    expect(a.status, 'device_revoked');
    expect(a.port, 0);
  });
  test('a refused address lookup (expired token) is not repeated on every call',
      () async {
    await rig.restartCoordinator({'RUST_LOG': 'tower_http=debug,info', 'NO_COLOR': '1'});
    var token = _jwt(424242);
    final a = await rig.node('a', token: () async => token);
    final b = await rig.node('b');
    await a.refreshDevices();
    token = 'expired.token.value';
    rig.logs.clear();
    for (var i = 0; i < 4; i++) {
      await expectLater(
          a.invoke(b.identity!.deviceId, 'download.echo', {'value': 'x'},
              destructive: false),
          throwsA(isA<Failure>()));
    }
    final lookups = rig.logs
        .join()
        .split('\n')
        .where((line) =>
            line.contains('method=GET path="/mesh/v1/addresses"') &&
            line.contains('finished processing request'))
        .length;
    expect(lookups, 1, reason: rig.logs.join());
  });
}
