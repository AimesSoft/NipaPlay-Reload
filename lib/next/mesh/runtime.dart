import 'dart:async';
import '../platform/lab_profile.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/mcp.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'host.dart';
import 'message.dart';
import 'coordinator.dart';
import 'discovery.dart';
import 'identity.dart';
import 'native.dart';
import 'device_source.dart';
export 'host.dart' show authorizeMeshPeer;

bool meshActionAllowed(String id) =>
    ['task.', 'download.', 'media.', 'danmaku.', 'playback.', 'subtitle.',
      'history.', 'followup.', 'program.', 'discover.', 'sync.', 'ui.',
      'settings.', 'accounts.', 'state.', 'window.', 'app.', 'diagnostics.',
      'events.', 'network.', 'storage.', 'cache.', 'notification.', 'share.',
      'backup.', 'plugins.', 'chat.', 'memory.', 'appearance.', 'shortcuts.',
      'webdav_quick.'].any(id.startsWith) ||
    const {'agent.wake', 'agent.dispatch', 'agent.dispatch.report',
      'capability.describe', 'activity.report', 'credentials.status', 'credentials.retry',
      'mesh.devices', 'mesh.invoke', 'mesh.invoke_destructive'}.contains(id);

String? meshActionRestriction(String id) => meshActionAllowed(id) ? null :
    'No remote contract is registered for this action; host credential enrollment stays local.';

/// Trust anchors are release inputs, never learned from the coordinator.
const meshProductionIssuerPem = '';

final class MeshRuntime implements MeshDeviceSource {
  MeshRuntime(
      {required this.root,
      required this.vault,
      required this.token,
      this.authorize = authorizeMeshPeer,
      this.forceLoopback = false,
      MeshNative? native})
      : native = native ?? MeshNative();
  final Directory root;
  final CredentialVault vault;
  final Future<String?> Function() token;
  final MeshNative native;
  final Future<Failure?> Function(String, String) authorize;
  final bool forceLoopback;
  Future<JsonMap?> Function(String, Invocation)? returnTarget;
  Future<JsonMap> Function(String, JsonMap)? receiveDelivery;
  Future<JsonMap> Function()? describeSelf;
  Future<JsonMap> Function(String, JsonMap, String)? libraryRequest;
  Future<void> Function()? hostConfigurationChanged;
  JsonMap hostConfiguration = {};
  String _bindHost = '0.0.0.0';
  bool _broadcast = true;
  Harness? _harness;
  MeshCoordinator? _coordinator;
  MeshIdentity? identity;
  MeshDiscovery? _discovery;
  int? _node;
  int _generation = 0;
  Timer? _heartbeat, _loginWatch;
  Future<void> _operations = Future.value();
  Future<void>? _receiver;
  String _status = 'disabled';
  final _hostChanges = StreamController<void>.broadcast();
  Stream<void> get hostChanges => _hostChanges.stream;
  String get status => _status;
  set status(String value) {
    if (value == _status) return;
    _status = value;
    _hostChanges.add(null);
  }
  String? discoveryNotice;
  String? _ca, _account;
  JsonMap? _certificate;
  int _epoch = -1, _interval = 900;
  List<JsonMap> _devices = [], _manual = [];
  final _catalogs = <String, List<JsonMap>>{};
  final _routes = <String, JsonMap>{};
  final _reachability = <String, bool>{};
  final _seen = <String, int>{};
  final _descriptions = <String, JsonMap>{};
  bool _hostFactsLoaded = false;
  Future<void> _replayWrites = Future.value();
  bool _replayLoaded = false;
  final _random = Random.secure();
  bool _closed = false;
  String? _loginIdentity;
  DateTime _nextJoinAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  int get port => _discovery?.port ?? 0;
  String? get accountId => _account;
  bool get issuerAvailable => meshProductionIssuerPem.isNotEmpty ||
      meshDevelopmentHost && Platform.environment['NIPAPLAY_MESH_DEV_CA'] != null;

  Future<List<JsonMap>> settingsDevices() async {
    if (!_hostFactsLoaded) {
      final file = File('${root.path}/mesh-host-facts.json');
      if (await file.exists()) {
        final facts = jsonDecode(await file.readAsString()) as JsonMap;
        for (final entry in facts.entries) {
          _descriptions[entry.key] = Map<String, Object?>.from(entry.value as Map);
        }
      }
      _hostFactsLoaded = true;
    }
    if (_devices.isEmpty) {
      final file = File('${root.path}/mesh-devices.json');
      if (await file.exists()) {
        final saved = jsonDecode(await file.readAsString()) as JsonMap;
        _devices = (saved['devices'] as List).cast<JsonMap>();
      }
    }
    if (_node != null) await devices();
    final selfDescription = await describeSelf?.call();
    return [for (final device in cachedDevices) {
      ...device,
      'roles': _descriptions[device['deviceId']]?['roles'] ?? <String>[],
      'remotePrograms': device['deviceId'] == identity?.deviceId
        ? (((selfDescription?['programExecution'] as Map?)?['enabled']) == true)
        : (((_descriptions[device['deviceId']]?['programExecution'] as Map?)?['enabled']) == true),
    }];
  }

  Future<void> restartConfigured() async {
    await stop();
    await startConfigured();
  }

  /// Offline until [startConfigured] again: no listener, no login watch, no
  /// heartbeat.
  Future<void> stop() async {
    _loginWatch?.cancel();
    _heartbeat?.cancel();
    await _operations;
    await _stopNode();
    _coordinator?.close();
    _coordinator = null;
    _loginIdentity = null;
    _nextJoinAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _reachability.clear();
    status = 'disabled';
  }
  @override
  List<JsonMap> get cachedDevices => [
        for (final device in _devices)
          {
            'deviceId': device['device_id'],
            'name': device['device_name'],
            'platform': device['platform'],
            'revoked': device['revoked'],
            'online': device['revoked'] == true
                ? false
                : device['device_id'] == identity?.deviceId ? status == 'online'
                : _reachability[device['device_id']],
            'lastSeenAt': device['last_seen_at'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                        (device['last_seen_at'] as int) * 1000,
                        isUtc: true)
                    .toIso8601String(),
          }
      ];
  List<String> get _active => [
        for (final device in _devices)
          if (device['revoked'] == false) device['device_id'] as String,
      ];

  void attach(Harness harness) => _harness = harness;

  /// Only the host configures trust and enables remote access.
  Future<void> startConfigured() async {
    final config = File('${root.path}/mesh.json');
    if (!await config.exists()) return;
    final json = jsonDecode(await config.readAsString()) as JsonMap;
    hostConfiguration = json;
    await hostConfigurationChanged?.call();
    if (json['enabled'] == false) { status = 'disabled'; return; }
    _bindHost = forceLoopback || json['loopbackOnly'] == true ? '127.0.0.1' : '0.0.0.0';
    _broadcast = json['broadcastDiscovery'] as bool? ?? true;
    final caPath = Platform.environment['NIPAPLAY_MESH_DEV_CA'];
    final ca = meshDevelopmentHost && caPath != null
        ? await File(caPath).readAsString()
        : meshProductionIssuerPem;
    if (ca.isEmpty) {
      status = 'issuer_not_configured';
      return;
    }
    _ca = ca;
    _manual = _addresses(json['addresses'] ?? []);
    _coordinator =
        MeshCoordinator(Uri.parse(json['coordinator'] as String), token);
    Future<void> checkLogin() async {
      final value = await token();
      // Keep the token only inside its request; this marker is not a credential.
      final marker = value == null ? null : identityHash(value);
      if (marker == _loginIdentity &&
          (_node != null || DateTime.now().isBefore(_nextJoinAttempt))) {
        return;
      }
      _loginIdentity = marker;
      _nextJoinAttempt = DateTime.now()
          .add(Duration(seconds: _interval + _random.nextInt(90)));
      if (_node != null) await _stopNode();
      if (value == null) {
        status = 'sign_in_required';
        return;
      }
      await join(
          ca: ca,
          coordinator: _coordinator!,
          name: json['name'] as String? ?? Platform.localHostname,
          listenPort: json['port'] as int? ?? (LabProfile.active ? 0 : 47812),
          broadcast: _broadcast);
    }

    await _queue(checkLogin);
    _loginWatch =
        Timer.periodic(const Duration(seconds: 30), (_) => _queue(checkLogin));
  }

  String identityHash(String tokenValue) {
    // No token or JWT payload is exposed through status, files or journal.
    return base64Url.encode(sha256.convert(utf8.encode(tokenValue)).bytes);
  }

  Future<void> _queue(Future<void> Function() operation) {
    final next = _operations.then((_) async {
      if (_closed) return;
      try {
        await operation();
      } on Failure catch (failure) {
        status = failure.message;
      } catch (error) {
        status = 'mesh_error:${error.runtimeType}';
      }
    });
    _operations = next;
    return next;
  }

  Future<void> join(
      {required String ca,
      required MeshCoordinator coordinator,
      required String name,
      int listenPort = 0,
      bool broadcast = true}) async {
    if (_harness == null) {
      throw StateError('Attach the Core Harness before joining Mesh.');
    }
    _ca = ca;
    if (forceLoopback) _bindHost = '127.0.0.1';
    _broadcast = broadcast;
    _coordinator = coordinator;
    identity ??= await MeshIdentity.load(root, vault, native);
    final own = identity!;
    if (!_replayLoaded) {
      final file = File('${root.path}/mesh-replay.jsonl');
      if (await file.exists()) {
        for (final line in await file.readAsLines()) {
          final record = jsonDecode(line) as JsonMap;
          final deadline = record['deadline'] as int;
          if (deadline > DateTime.now().millisecondsSinceEpoch) {
            for (final key in (record['keys'] as List).cast<String>()) {
              _seen[key] = deadline;
            }
          }
        }
      }
      _replayLoaded = true;
      await _compactReplay();
    }
    final cache = File('${root.path}/mesh-certificate.json');
    final fields = [
      'register',
      own.publicKey,
      name,
      Platform.operatingSystem,
      '1'
    ];
    JsonMap registration;
    if (await cache.exists()) {
      registration =
          await coordinator.request('POST', '/mesh/v1/devices/renew', {
        'device_id': own.deviceId,
        'device_public_key': own.publicKey,
        'proof': await own.proof(
            ['renew', own.publicKey, own.deviceId], _nonce(), _nowSeconds),
      });
    } else {
      registration =
          await coordinator.request('POST', '/mesh/v1/devices/register', {
        'device_public_key': own.publicKey,
        'device_name': name,
        'platform': Platform.operatingSystem,
        'app_version': '1',
        'proof': await own.proof(fields, _nonce(), _nowSeconds),
      });
    }
    if (registration['device_id'] != own.deviceId) {
      throw const FormatException('Coordinator device identity mismatch.');
    }
    _account = registration['account_id'] as String;
    _certificate = registration['certificate'] as JsonMap;
    await native.validate(
        ca, _certificate!['pem'] as String, await own.privateKey(), _account!);
    await cache.writeAsString(jsonEncode(registration), flush: true);
    _interval =
        max(900, registration['heartbeat_interval_seconds'] as int? ?? 900);
    await refreshDevices();
    await _compactReplay();
    _node = await native.start(
        ca: ca,
        certificate: _certificate!['pem'] as String,
        key: await own.privateKey(),
        account: _account!,
        allowed: _active,
        bind: '$_bindHost:$listenPort');
    final node = _node!;
    final generation = ++_generation;
    _receiver = _receive(node, generation);
    _discovery = MeshDiscovery(own.deviceId, await native.port(node));
    if (broadcast) {
      try {
        await _discovery!.start();
      } on SocketException {
        discoveryNotice =
            'LAN broadcast unavailable; coordinator candidates remain available.';
      }
    }
    await heartbeat(renew: false);
    status = 'online';
    _scheduleHeartbeat();
  }

  Future<void> refreshDevices() async {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw const Failure(FailureCode.unavailable, 'Mesh is not configured.');
    }
    final response = await coordinator.request('GET', '/mesh/v1/devices');
    if (response['account_id'] != _account) {
      throw const FormatException('Coordinator account mismatch.');
    }
    final devices = (response['devices'] as List).cast<JsonMap>();
    final epoch = response['revocation_epoch'] as int;
    if (epoch < _epoch) {
      throw const FormatException(
          'Coordinator revocation epoch went backwards.');
    }
    _devices = devices;
    _epoch = epoch;
    _catalogs.removeWhere((id, _) => !_active.contains(id));
    if (_node case final node?) await native.update(node, _active);
    final revokedSelf =
        identity != null && !_active.contains(identity!.deviceId);
    await File('${root.path}/mesh-devices.json')
        .writeAsString(jsonEncode(response), flush: true);
    if (revokedSelf) {
      await _stopNode();
      status = 'device_revoked';
      throw const Failure(
          FailureCode.unavailable, 'This Mesh device has been revoked.');
    }
  }

  Future<void> heartbeat({bool renew = true}) async {
    final own = identity!;
    final JsonMap response;
    try {
      response = await _coordinator!.request('POST', '/mesh/v1/addresses', {
        'device_id': own.deviceId,
        'candidates': [if (_bindHost != '127.0.0.1') ...await _discovery!.localCandidates(), ..._manual]
            .take(32)
            .toList(),
      });
    } finally {
      // A revoked device cannot report addresses but must still learn its revocation.
      await refreshDevices();
    }
    _interval =
        max(900, response['heartbeat_interval_seconds'] as int? ?? _interval);
    if (renew && (_certificate!['not_after'] as int) - _nowSeconds < 86400) {
      final renewed =
          await _coordinator!.request('POST', '/mesh/v1/devices/renew', {
        'device_id': own.deviceId,
        'device_public_key': own.publicKey,
        'proof': await own.proof(
            ['renew', own.publicKey, own.deviceId], _nonce(), _nowSeconds),
      });
      if (renewed['account_id'] != _account ||
          renewed['device_id'] != own.deviceId) {
        throw const FormatException('Renewed Mesh identity mismatch.');
      }
      await native.validate(
          _ca!,
          (renewed['certificate'] as JsonMap)['pem'] as String,
          await own.privateKey(),
          _account!);
      final bindPort = port;
      await _stopNode();
      _certificate = renewed['certificate'] as JsonMap;
      await File('${root.path}/mesh-certificate.json')
          .writeAsString(jsonEncode(renewed), flush: true);
      _node = await native.start(
          ca: _ca!,
          certificate: _certificate!['pem'] as String,
          key: await own.privateKey(),
          account: _account!,
          allowed: _active,
          bind: '$_bindHost:$bindPort');
      _receiver = _receive(_node!, ++_generation);
      _discovery = MeshDiscovery(own.deviceId, bindPort);
      if (_broadcast) await _discovery!.start();
    }
  }

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer(
        Duration(seconds: _interval + _random.nextInt(max(1, _interval ~/ 10))),
        () async {
      await _queue(() => heartbeat());
      if (!_closed && _node != null) _scheduleHeartbeat();
    });
  }

  Future<void> revoke(String deviceId) async {
    await _coordinator!.request(
        'POST', '/mesh/v1/devices/$deviceId/revoke', {'device_id': deviceId});
    await refreshDevices();
  }

  Future<void> setManualAddresses(Object? value) async {
    _manual = _addresses(value);
    final file = File('${root.path}/mesh.json');
    if (!await file.exists()) {
      throw const Failure(
          FailureCode.unavailable, 'Host must configure Mesh first.');
    }
    final config = jsonDecode(await file.readAsString()) as JsonMap;
    config['addresses'] = _manual;
    await file.writeAsString(jsonEncode(config), flush: true);
    // Changed hints are advertised at the next scheduled heartbeat.
  }

  Future<List<JsonMap>> manualAddresses() async {
    final file = File('${root.path}/mesh.json');
    if (!await file.exists()) return [];
    return _addresses(
        (jsonDecode(await file.readAsString()) as JsonMap)['addresses'] ?? []);
  }

  Future<JsonMap> devices({List<String>? deviceIds, bool includeCatalog = true}) async {
    if (_node == null) return {'status': status, 'devices': <Object?>[]};
    await refreshDevices();
    return {
      'status': status,
      if (discoveryNotice != null) 'discoveryNotice': discoveryNotice,
      'devices': [
        for (final device in _devices)
          if (deviceIds == null || deviceIds.contains(device['device_id']))
            await _describe(device, includeCatalog: includeCatalog),
      ]
    };
  }

  Future<JsonMap> _describe(JsonMap device, {bool includeCatalog = true}) async {
    final id = device['device_id'] as String;
    if (device['revoked'] == true) {
      _reachability[id] = false;
      return {
        ...device,
        'deviceId': id,
        'online': false,
        'actions': <Object?>[]
      };
    }
    try {
      final tools = includeCatalog ? await _catalog(id) : null;
      _reachability[id] = true;
      final description = await rpc(id, 'mesh/describe', {});
      _descriptions[id] = {
        'roles': description['roles'] ?? [
          if (description['host'] != null) description['host'],
          if (description['conversationHost'] == true) 'conversation',
        ],
        'programExecution': {'enabled':
          (description['programExecution'] as Map?)?['enabled'] == true},
      };
      await File('${root.path}/mesh-host-facts.json')
          .writeAsString(jsonEncode(_descriptions), flush: true);
      return {...device, 'deviceId': id, 'online': true,
        if (includeCatalog) 'actions': tools,
        'description': description};
    } on Failure {
      _reachability[id] = false;
      return {
        ...device,
        'deviceId': id,
        'online': false,
        if (includeCatalog) 'actions': _catalogs[id] ?? <Object?>[]
      };
    }
  }

  Future<List<JsonMap>> _catalog(String peer) async {
    final result = await rpc(peer, 'tools/list', {});
    final tools = (result['tools'] as List).cast<JsonMap>();
    final actions = [
      for (final tool in tools)
        {
          'id': (tool['_meta'] as JsonMap)['nipaplay/actionId'],
          'effect': (tool['_meta'] as JsonMap)['nipaplay/effect'],
          'name': tool['name'],
          'title': tool['title'],
          'description': tool['description'],
          'inputSchema': tool['inputSchema'],
          'outputSchema': (tool['_meta'] as JsonMap)['nipaplay/outputSchema'],
        }
    ];
    _catalogs[peer] = actions;
    return actions;
  }

  Future<Outcome<JsonEncodable>> invoke(
      String peer, String action, JsonMap input,
      {required bool destructive, Invocation? invocation}) async {
    if (!meshActionAllowed(action)) {
      throw const Failure(
          FailureCode.invalidInput, 'Action is outside the Mesh scope.');
    }
    final catalog = await _catalog(peer);
    final matches = catalog.where((entry) => entry['id'] == action);
    if (matches.isEmpty) {
      throw const Failure(
          FailureCode.notFound, 'Remote action is unavailable.');
    }
    final target = matches.single;
    if ((target['effect'] == 'destructive') != destructive) {
      throw Failure(
          FailureCode.invalidInput,
          destructive
              ? 'mesh.invoke_destructive only accepts destructive actions.'
              : 'Use mesh.invoke_destructive for this action.');
    }
    final targetReturn = {'download.add', 'program.run', 'followup.register'}.contains(action) && invocation != null
        ? await returnTarget?.call(peer, invocation) : null;
    final result = await rpc(peer, 'tools/call', {
      'name': target['name'],
      'arguments': input,
      'meshDestructive': destructive,
      if (targetReturn != null) 'returnTo': {...targetReturn,
        'deviceId': identity!.deviceId},
    });
    final envelope = result['structuredContent'] as JsonMap;
    switch (envelope['status']) {
      case 'completed':
        return Completed(MeshJson(envelope['result'] as JsonMap));
      case 'failed':
        final error = envelope['error'] as JsonMap;
        final code =
            FailureCode.values.firstWhere((c) => c.wireName == error['code']);
        return Failed(Failure(code, error['message'] as String,
            retryable: error['retryable'] as bool,
            violations: [
              for (final v in (error['violations'] as List? ?? []))
                SchemaViolation(
                    (v as JsonMap)['path'] as String, v['message'] as String)
            ]));
      case 'needs_decision':
        final decision = envelope['decision'] as JsonMap;
        return NeedsDecision(
            Decision(prompt: decision['prompt'] as String, options: [
          for (final option in (decision['options'] as List).cast<JsonMap>())
            _decisionOption(peer, option, catalog),
        ]));
      default:
        throw const FormatException('Invalid Mesh outcome envelope.');
    }
  }

  DecisionOption _decisionOption(
      String peer, JsonMap option, List<JsonMap> catalog) {
    final call = option['call'] as JsonMap;
    final target = catalog.where((entry) => entry['id'] == call['action']);
    if (target.isEmpty) {
      throw const Failure(FailureCode.invalidInput,
          'Remote decision action is outside Mesh scope.');
    }
    return DecisionOption(
        label: option['label'] as String,
        detail: option['detail'] as String?,
        call: ActionCall(
            target.single['effect'] == 'destructive'
                ? 'mesh.invoke_destructive'
                : 'mesh.invoke',
            {
              'deviceId': peer,
              'action': call['action'],
              'input': call['input']
            }));
  }

  Future<JsonMap> rpc(String peer, String method, JsonMap params,
      {JsonMap? replayFrame}) async {
    final node = _node;
    if (node == null) {
      throw const Failure(FailureCode.unavailable, 'Mesh is offline.');
    }
    if (!_active.contains(peer)) {
      throw const Failure(
          FailureCode.unavailable, 'Mesh device is revoked or unknown.');
    }
    final frame = replayFrame ??
        {
          'jsonrpc': '2.0',
          'id': _nonce(),
          'method': method,
          'params': params,
          'mesh': {
            'invocationId': _nonce(),
            'nonce': _nonce(),
            'deadline': DateTime.now().millisecondsSinceEpoch + 3600000
          },
        };
    final remembered = _routes[peer];
    final candidates = <JsonMap>[
      if (_routes[peer] case final route?) {...route, 'priority': 1000},
      if (peer == identity!.deviceId) {'host': '127.0.0.1', 'port': port},
      ..._discovery!.hints(peer),
      if (remembered == null && peer != identity!.deviceId)
        ...((await _coordinator!.request(
                    'GET', '/mesh/v1/addresses?device_id=$peer'))['candidates']
                as List)
            .cast<JsonMap>(),
    ]..sort((a, b) =>
        ((b['priority'] as int?) ?? 0).compareTo((a['priority'] as int?) ?? 0));
    for (final candidate in candidates) {
      final String body;
      try {
        body = await native.send(node, candidate['host'] as String,
            candidate['port'] as int, peer, jsonEncode(frame));
      } catch (_) {
        // A connection error can follow execution; never retry an ambiguous call.
        if (method == 'tools/call') {
          throw const Failure(FailureCode.unavailable,
              'Remote call outcome is unknown; query its task before retrying.');
        }
        continue;
      }
      final response = jsonDecode(body) as JsonMap;
      if (response['jsonrpc'] != '2.0' || response['id'] != frame['id']) {
        throw const FormatException('Mesh RPC response mismatch.');
      }
      if (response['error'] != null) {
        final error = response['error'] as JsonMap;
        if (error['code'] == -32001 && error['data'] is JsonMap) {
          final denial = error['data'] as JsonMap;
          throw Failure(
              FailureCode.values.firstWhere((c) => c.wireName == denial['code']),
              denial['message'] as String);
        }
        throw const Failure(
            FailureCode.invalidInput, 'Remote RPC rejected the request.');
      }
      _routes[peer] = candidate;
      return response['result'] as JsonMap;
    }
    if (remembered != null) {
      _routes.remove(peer);
      return rpc(peer, method, params, replayFrame: replayFrame);
    }
    throw const Failure(FailureCode.unavailable,
        'No authenticated direct route to Mesh device.',
        retryable: true);
  }

  Future<void> _receive(int node, int generation) async {
    while (_node == node && _generation == generation) {
      final MeshMessage event;
      try {
        event = await native.next(node);
      } catch (_) {
        if (_node == node && !_closed) status = 'mesh_listener_stopped';
        return;
      }
      unawaited(_dispatch(node, event));
    }
  }

  Future<void> _dispatch(int node, MeshMessage event) async {
    JsonMap response;
    try {
      final frame = jsonDecode(event.body);
      if (frame is! JsonMap) throw const FormatException('Invalid frame.');
      final metadata = frame['mesh'];
      if (metadata is! JsonMap ||
          metadata['invocationId'] is! String ||
          metadata['nonce'] is! String ||
          metadata['deadline'] is! int) {
        throw const FormatException('Missing replay guard.');
      }
      final id = metadata['invocationId'] as String,
          nonce = metadata['nonce'] as String;
      final deadline = metadata['deadline'] as int,
          now = DateTime.now().millisecondsSinceEpoch;
      if (!RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(id) ||
          !RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(nonce) ||
          deadline <= now ||
          deadline > now + 3600000) {
        throw const FormatException('Invalid replay guard.');
      }
      _seen.removeWhere((_, expiry) => expiry < now);
      final idKey = '${event.deviceId}:id:$id',
          nonceKey = '${event.deviceId}:nonce:$nonce';
      if (_seen.containsKey(idKey) ||
          _seen.containsKey(nonceKey) ||
          _seen.length >= 20000) {
        throw const FormatException('Replayed invocation.');
      }
      _seen[idKey] = deadline;
      _seen[nonceKey] = deadline;
      _replayWrites = _replayWrites
          .then((_) => File('${root.path}/mesh-replay.jsonl').writeAsString(
              '${jsonEncode({
                    'keys': [idKey, nonceKey],
                    'deadline': deadline
                  })}\n',
              mode: FileMode.append,
              flush: true));
      await _replayWrites;
      if (_node != node ||
          !_active.contains(event.deviceId) ||
          deadline <= DateTime.now().millisecondsSinceEpoch) {
        throw const Failure(
            FailureCode.unavailable, 'Mesh peer was revoked or disconnected.');
      }
      // Enrollment and the authenticated active peer set above authorize this
      // body. Domain decisions still run on the receiving host's Harness.
      if (frame['method'] == 'mesh/describe') {
        response = {'jsonrpc': '2.0', 'id': frame['id'], 'result': {
          'deviceId': identity!.deviceId,
          'name': hostConfiguration['name'] ?? Platform.localHostname,
          'platform': Platform.operatingSystem,
          'agentDeviceId': hostConfiguration['agentDeviceId'],
          'roles': hostConfiguration['roles'] ?? <String>[],
          'storage': hostConfiguration['storage'] ?? <Object?>[],
          if (describeSelf != null) ...await describeSelf!(),
          if (_harness!.lookup('app.capabilities') != null)
            'capabilities': (await _harness!.invokeJson('app.capabilities', {},
                Invocation(origin: 'mesh:describe'))).toEnvelope(),
        }};
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if (frame['method'] == 'mesh/delivery') {
        if (receiveDelivery == null) throw const FormatException('No delivery host.');
        final result = await receiveDelivery!(event.deviceId, frame['params'] as JsonMap);
        response = {'jsonrpc': '2.0', 'id': frame['id'], 'result': result};
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if ((frame['method'] as String).startsWith('mesh/library/')) {
        if (libraryRequest == null) throw const FormatException('No library host.');
        final result = await libraryRequest!(frame['method'] as String,
            frame['params'] as JsonMap, event.deviceId);
        response = {'jsonrpc': '2.0', 'id': frame['id'], 'result': result};
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      final params = frame['params'] as JsonMap?;
      final returnTo = params?['returnTo'];
      if (returnTo != null && (returnTo is! JsonMap ||
          returnTo['deviceId'] != event.deviceId ||
          returnTo['threadId'] is! String || returnTo['repository'] is! String)) {
        throw const FormatException('Invalid return target.');
      }
      final rpc = McpRpc(_harness!,
          serverInfo: const McpServerInfo(
              name: 'nipaplay-mesh', title: 'NipaPlay Mesh', version: '1'),
          include: (spec) => meshActionAllowed(spec.id),
          includeActionIds: true,
          authorize: (spec, params) => (spec.effect == Effect.destructive) !=
                  (params['meshDestructive'] == true)
              ? const Failure(FailureCode.invalidInput,
                  'Mesh effect authorization mismatch.')
              : null);
      response = await runZoned(() => rpc.handle(
              frame, Invocation(origin: 'mesh:${event.deviceId}', id: id)),
          zoneValues: {#meshReturnTarget: returnTo}) ??
          {'jsonrpc': '2.0', 'id': null, 'result': <String, Object?>{}};
      final result = response['result'] as JsonMap?;
      if (result?.containsKey('structuredContent') == true) {
        // Mesh consumers decode structuredContent; duplicating it as escaped
        // text can exceed the frame limit even when the complete result fits.
        result!['content'] = [
          {'type': 'text', 'text': 'Complete Action outcome is in structuredContent.'}
        ];
      }
    } on FormatException {
      response = McpRpc.error(
          _rpcId(event.body), -32600, 'Invalid or replayed Mesh request.');
    } catch (_) {
      response =
          McpRpc.error(_rpcId(event.body), -32603, 'Mesh request failed.');
    }
    try {
      await native.respond(node, event.requestId, jsonEncode(response));
    } catch (_) {
      // Closing/revoked peers no longer have a response channel.
      status = _node == node ? 'peer_disconnected' : status;
    }
  }

  Object? _rpcId(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map ? json['id'] : null;
    } on FormatException {
      return null;
    }
  }

  String _nonce() => base64Url
      .encode(List.generate(24, (_) => _random.nextInt(256)))
      .replaceAll('=', '');
  int get _nowSeconds => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  Future<void> _compactReplay() async {
    _seen.removeWhere(
        (_, expiry) => expiry <= DateTime.now().millisecondsSinceEpoch);
    _replayWrites = _replayWrites.then((_) async {
      final file = File('${root.path}/mesh-replay.jsonl.tmp');
      final lines = [
        for (final entry in _seen.entries)
          jsonEncode({
            'keys': [entry.key],
            'deadline': entry.value
          })
      ].join('\n');
      await file.writeAsString(lines.isEmpty ? '' : '$lines\n', flush: true);
      await file.rename('${root.path}/mesh-replay.jsonl');
    });
    await _replayWrites;
  }

  Future<void> _stopNode() async {
    _heartbeat?.cancel();
    final node = _node;
    _node = null;
    _generation++;
    if (node != null) await native.stop(node);
    await _receiver;
    _receiver = null;
    await _discovery?.close();
    _discovery = null;
  }

  Future<void> close() async {
    _closed = true;
    _loginWatch?.cancel();
    _heartbeat?.cancel();
    await _operations;
    await _stopNode();
    await _replayWrites;
    _coordinator?.close();
    await _hostChanges.close();
  }
}

List<JsonMap> _addresses(Object? value) {
  if (value is! List || value.length > 16) {
    throw const FormatException('At most 16 manual addresses are allowed.');
  }
  return [for (final entry in value) _address(entry)];
}

List<SchemaViolation> meshAddressViolations(Object? value) {
  try {
    _addresses(value);
    return [];
  } on FormatException catch (error) {
    return [SchemaViolation('/value', error.message)];
  }
}

JsonMap _address(Object? value) {
  if (value is! JsonMap ||
      !['overlay', 'public', 'manual', 'relay'].contains(value['kind']) ||
      value['host'] is! String ||
      (value['host'] as String).isEmpty ||
      (value['host'] as String).length > 255 ||
      RegExp(r'[\s/@?#]').hasMatch(value['host'] as String) ||
      value['port'] is! int ||
      (value['port'] as int) < 1 ||
      (value['port'] as int) > 65535) {
    throw const FormatException('Invalid manual Mesh address.');
  }
  return {
    'kind': value['kind'],
    'host': value['host'],
    'port': value['port'],
    'priority': 50,
    'expires_in': 3600
  };
}

final class MeshJson implements JsonEncodable {
  const MeshJson(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}
