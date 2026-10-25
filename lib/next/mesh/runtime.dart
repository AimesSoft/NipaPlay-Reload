import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/mcp.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
import '../body/next_body.dart';
import '../platform/lab_profile.dart';
import 'coordinator.dart';
import 'chat_guest_host.dart' show chatGuestMethods;
import 'delegation_host.dart' show delegationMethods;
import 'device_source.dart';
import 'discovery.dart';
import 'host.dart';
import 'identity.dart';
import 'install_id.dart';
import 'message.dart';
import 'native.dart';
import 'presence.dart';
import 'system_bonjour.dart';
import 'trust.dart';
export 'host.dart' show authorizeMeshPeer;
export 'trust.dart'
    show meshDefaultCoordinator, meshProductionIssuerPem, inspectMeshTrust;

bool meshActionAllowed(String id) =>
    [
      'task.',
      'download.',
      'media.',
      'danmaku.',
      'playback.',
      'subtitle.',
      'history.',
      'followup.',
      'program.',
      'discover.',
      'sync.',
      'ui.',
      'settings.',
      'accounts.',
      'state.',
      'window.',
      'app.',
      'diagnostics.',
      'events.',
      'network.',
      'storage.',
      'cache.',
      'notification.',
      'share.',
      'backup.',
      'plugins.',
      'chat.',
      'memory.',
      'appearance.',
      'shortcuts.',
      'webdav_quick.',
    ].any(id.startsWith) ||
    const {
      'agent.wake',
      'agent.dispatch',
      'agent.dispatch.report',
      'capability.describe',
      'activity.report',
      'credentials.status',
      'credentials.retry',
      'mesh.devices',
      'mesh.invoke',
      'mesh.invoke_destructive',
    }.contains(id);

String? meshActionRestriction(String id) => meshActionAllowed(id)
    ? null
    : id == 'mesh.delegate'
        ? 'Delegation starts on the device that hands the work over; another device cannot start it on this one.'
        : 'No remote contract is registered for this action; host credential enrollment stays local.';

final class MeshRuntime implements MeshDeviceSource {
  MeshRuntime({
    required this.root,
    required this.vault,
    required this.token,
    this.authorize = authorizeMeshPeer,
    this.coordinatorRetryDelay = const Duration(seconds: 15),
    this.candidateStaggerDelay = const Duration(milliseconds: 250),
    this.unknownPeerRefreshCooldown = const Duration(seconds: 30),
    this.presenceProbeInterval = const Duration(seconds: 30),
    this.toolsPageBytes = 400 * 1024,
    this.candidateLookupBase = const Duration(seconds: 30),
    this.candidateLookupInterval = const Duration(minutes: 10),
    this.interfaceProvider,
    MeshNative? native,
    int Function()? clockSeconds,
  })  : native = native ?? MeshNative(),
        _clockSeconds = clockSeconds;

  final Directory root;
  final CredentialVault vault;
  final Future<String?> Function() token;
  final MeshNative native;
  final Future<Failure?> Function(String, String) authorize;
  final Duration coordinatorRetryDelay;
  final Duration candidateStaggerDelay;
  final Duration unknownPeerRefreshCooldown;

  /// A device that said it is not in front is called again, once, this
  /// rarely: the call that finds it absent also asks it, in the background,
  /// where it is, so a lost "I am back" cannot keep it unreachable.
  final Duration presenceProbeInterval;

  /// One `tools/list` page stays far below the 1 MiB Mesh frame: a Next
  /// interface registers hundreds of Actions whose schemas together exceed it.
  final int toolsPageBytes;

  /// Coordinator address lookups for one peer. The library calls every peer
  /// every few seconds, so a peer that is offline would otherwise cost one
  /// lookup per call and exhaust the account's 60 address requests per hour in
  /// minutes. A lookup is allowed when nothing is cached, when the peer was
  /// reached since the last lookup (its address probably changed: restart,
  /// new IP), or when the gap since the last one has passed; the gap starts at
  /// [candidateLookupBase] and doubles, up to [candidateLookupInterval], while
  /// lookups keep returning the same answer.
  final Duration candidateLookupBase;
  final Duration candidateLookupInterval;
  final Future<List<NetworkInterfaceSnapshot>> Function()? interfaceProvider;
  final int Function()? _clockSeconds;

  Future<JsonMap?> Function(String, Invocation)? returnTarget;
  Future<JsonMap> Function(String, JsonMap)? receiveDelivery;
  Future<JsonMap> Function()? describeSelf;
  Future<JsonMap> Function(String, JsonMap, String)? libraryRequest;

  /// The host methods of delegation (`mesh/agent/*`): another device's Nipa
  /// handing this device's Nipa a task. Not Actions, so Nipa cannot call them
  /// on another device; the method, its params and the authenticated sender.
  Future<JsonMap> Function(String, JsonMap, String)? agentRequest;

  /// The host methods of guest conversations (`mesh/chat/*`): a device that
  /// cannot run Nipa speaking with the Nipa of this one.
  Future<JsonMap> Function(String, JsonMap, String)? chatRequest;
  Future<void> Function()? hostConfigurationChanged;
  JsonMap hostConfiguration = {};

  /// Where the other devices said they are (in front, behind another
  /// application, showing the other interface). Calls to a device that is not
  /// in front fail at once with `device_not_present`.
  final presence = MeshPresence();

  /// What this device is playing, added to the presence it announces.
  JsonMap Function()? presenceFacts;
  String _ownState = PresenceState.foreground;
  DateTime _ownStateAt = DateTime.now().toUtc();
  bool _announcedAbsent = false;
  Future<void> Function()? _loginCheck;
  final _presenceProbeAt = <String, DateTime>{};
  final _presenceProbing = <String>{};
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
  String? coordinatorNotice;
  String? _ca, _account;
  JsonMap? _certificate;
  int _epoch = -1, _interval = 900;
  List<JsonMap> _devices = [], _manual = [];
  final _catalogs = <String, List<JsonMap>>{};
  final _routes = <String, JsonMap>{};
  final _peerCandidates = <String, List<JsonMap>>{};
  final _reachability = <String, bool>{};
  final _seen = <String, int>{};
  final _descriptions = <String, JsonMap>{};
  final _unknownPeerCheckedAt = <String, DateTime>{};
  final _candidateLookupAt = <String, DateTime>{};
  final _candidateLookupGap = <String, Duration>{};
  // A lookup the coordinator refused (an expired account token answers 401):
  // when it was, and how long to leave the coordinator alone about this peer.
  final _candidateLookupRefusedAt = <String, DateTime>{};
  final _candidateLookupRefusedGap = <String, Duration>{};
  final _reachedSinceLookup = <String>{};
  bool _hostFactsLoaded = false;
  bool _routesLoaded = false;
  Future<void> _routeWrites = Future.value();
  Future<void> _replayWrites = Future.value();
  bool _replayLoaded = false;
  Future<void>? _refreshingDevices;
  DateTime _lastDevicesRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  bool _coordinatorSyncPending = false;
  int _retryAttempts = 0;
  final _random = Random.secure();
  bool _closed = false;
  String? _loginIdentity;
  DateTime _nextJoinAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  int get port => _discovery?.port ?? 0;
  String? get accountId => _account;
  bool get coordinatorSyncPending => _coordinatorSyncPending;
  Map<String, JsonMap> get rememberedRoutes => {
        for (final e in _routes.entries)
          e.key: Map<String, Object?>.from(e.value)
      };

  bool get issuerAvailable =>
      _builtInTrust.ok ||
      meshDevelopmentHost &&
          Platform.environment['NIPAPLAY_MESH_DEV_CA'] != null;

  /// The built-in roots, inspected once. A release refuses to start with
  /// roots that are missing, unreadable or not CAs; it never half-trusts.
  static final _builtInTrust = inspectMeshTrust(meshProductionIssuerPem);

  bool get _needsCertificateRenewal {
    final cert = _certificate;
    if (cert == null) return true;
    final notAfter = cert['not_after'];
    if (notAfter is! int) return true;
    return notAfter - _nowSeconds < 86400;
  }

  Future<void> _loadHostFacts() async {
    if (_hostFactsLoaded) return;
    final file = File('${root.path}/mesh-host-facts.json');
    if (await file.exists()) {
      final facts = jsonDecode(await file.readAsString()) as JsonMap;
      for (final entry in facts.entries) {
        _descriptions[entry.key] =
            Map<String, Object?>.from(entry.value as Map);
      }
    }
    _hostFactsLoaded = true;
  }

  Future<List<JsonMap>> settingsDevices() async {
    await _loadHostFacts();
    if (_devices.isEmpty) {
      final file = File('${root.path}/mesh-devices.json');
      if (await file.exists()) {
        final saved = jsonDecode(await file.readAsString()) as JsonMap;
        _devices = (saved['devices'] as List).cast<JsonMap>();
      }
    }
    if (_node != null) await devices();
    final selfDescription = await describeSelf?.call();
    return [
      for (final device in cachedDevices)
        {
          ...device,
          'roles': _descriptions[device['deviceId']]?['roles'] ?? <String>[],
          'remotePrograms': device['deviceId'] == identity?.deviceId
              ? (((selfDescription?['programExecution'] as Map?)?['enabled']) ==
                  true)
              : (((_descriptions[device['deviceId']]?['programExecution']
                      as Map?)?['enabled']) ==
                  true),
        }
    ];
  }

  Future<void> restartConfigured() async {
    await stop();
    await startConfigured();
  }

  /// Where the node listens for a host configuration (`mesh.json`): every
  /// interface (mutual TLS is what guards it), or only this machine when it
  /// says `loopbackOnly`. A headless host is no exception: the device that
  /// serves the others from a closet must be reachable by them.
  static String bindHostFor(JsonMap configuration) =>
      configuration['loopbackOnly'] == true ? '127.0.0.1' : '0.0.0.0';

  /// Offline until [startConfigured] again: no listener, no login watch, no
  /// heartbeat.
  Future<void> stop() async {
    _loginWatch?.cancel();
    _heartbeat?.cancel();
    _deferredRefresh?.cancel();
    _deferredRefresh = null;
    await _operations;
    await _stopNode();
    await _routeWrites;
    _coordinator?.close();
    _coordinator = null;
    _loginIdentity = null;
    _nextJoinAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _reachability.clear();
    _coordinatorSyncPending = false;
    _retryAttempts = 0;
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
                : device['device_id'] == identity?.deviceId
                    ? status == 'online'
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
    // Mesh is on by default: `mesh.json` exists only once the user changed an
    // advanced setting, and then it says what differs from the defaults.
    final config = File('${root.path}/mesh.json');
    final json = await config.exists()
        ? jsonDecode(await config.readAsString()) as JsonMap
        : <String, Object?>{};
    hostConfiguration = json;
    await hostConfigurationChanged?.call();
    if (json['enabled'] == false) {
      status = 'disabled';
      return;
    }
    _bindHost = bindHostFor(json);
    _broadcast = json['broadcastDiscovery'] as bool? ?? true;
    // A development build takes its issuer from the environment, or, where a
    // process cannot be given one (an iPad), from a file in the data directory.
    final devFile = File('${root.path}/mesh-dev-ca.pem');
    final caPath = Platform.environment['NIPAPLAY_MESH_DEV_CA'] ??
        (meshDevelopmentHost && await devFile.exists() ? devFile.path : null);
    final ca = meshDevelopmentHost && caPath != null
        ? await File(caPath).readAsString()
        : meshProductionIssuerPem;
    if (caPath == null || !meshDevelopmentHost) {
      if (!_builtInTrust.ok) {
        status = 'issuer_not_configured';
        return;
      }
    } else if (ca.isEmpty) {
      status = 'issuer_not_configured';
      return;
    }
    _ca = ca;
    _manual = _addresses(json['addresses'] ?? []);
    final configured = json['coordinator'];
    _coordinator = MeshCoordinator(
        Uri.parse(configured is String && configured.trim().isNotEmpty
            ? configured.trim()
            : meshDefaultCoordinator),
        token);
    Future<void> checkLogin() async {
      final value = await token();
      // Keep the token only inside its request; this marker is not a credential.
      final marker = value == null ? null : identityHash(value);
      if (marker == _loginIdentity &&
          (_node != null || DateTime.now().isBefore(_nextJoinAttempt))) {
        return;
      }
      _loginIdentity = marker;
      _nextJoinAttempt = DateTime.now().add(coordinatorRetryDelay);
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

    _loginCheck = checkLogin;
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
        if (_node != null) {
          _noteCoordinatorFailure(failure);
        } else {
          status = failure.message;
        }
      } catch (error) {
        if (_node == null) {
          status = 'mesh_error:${error.runtimeType}';
        } else {
          _noteCoordinatorFailure(error);
        }
      }
    });
    _operations = next;
    return next;
  }

  Future<void> _loadRoutes() async {
    if (_routesLoaded) return;
    _routesLoaded = true;
    final file = File('${root.path}/mesh-routes.json');
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final routes =
          decoded['routes'] is Map ? decoded['routes'] as Map : decoded;
      for (final entry in routes.entries) {
        final peer = entry.key;
        final route = entry.value;
        if (peer is String &&
            route is Map &&
            route['host'] is String &&
            (route['host'] as String).isNotEmpty &&
            route['port'] is int &&
            (route['port'] as int) >= 1 &&
            (route['port'] as int) <= 65535) {
          _routes[peer] = {
            'kind': route['kind'] is String ? route['kind'] : 'lan',
            'host': route['host'],
            'port': route['port'],
          };
        }
      }
      if (decoded['candidates'] is Map) {
        for (final entry in (decoded['candidates'] as Map).entries) {
          if (entry.key is String && entry.value is List) {
            _peerCandidates[entry.key as String] = [
              for (final item in entry.value as List)
                if (item is Map) Map<String, Object?>.from(item),
            ];
          }
        }
      }
    } catch (_) {
      // Corrupted route cache is ignored and rebuilt on next successful route.
    }
  }

  /// R1 starts from these two files, so a crash while writing must leave the
  /// previous copy intact rather than a truncated one.
  Future<void> _writeAtomic(String name, String content) async {
    final tmp = File('${root.path}/$name.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename('${root.path}/$name');
  }

  Future<void> _persistRoutes() {
    final snapshot = jsonEncode({
      'routes': _routes,
      'candidates': _peerCandidates,
    });
    _routeWrites = _routeWrites.then((_) async {
      final tmp = File('${root.path}/mesh-routes.json.tmp');
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename('${root.path}/mesh-routes.json');
    }).catchError((_) {});
    return _routeWrites;
  }

  Future<void> _saveRoute(String peer, JsonMap candidate) async {
    final normalized = <String, Object?>{
      'kind': candidate['kind'] ?? 'lan',
      'host': candidate['host'],
      'port': candidate['port'],
    };
    final current = _routes[peer];
    _routes[peer] = normalized;
    if (current == null ||
        current['host'] != normalized['host'] ||
        current['port'] != normalized['port'] ||
        current['kind'] != normalized['kind']) {
      await _persistRoutes();
    }
  }

  Future<void> _removeRoute(String peer) async {
    if (_routes.remove(peer) != null) {
      await _persistRoutes();
    }
  }

  Future<({bool hasValidCert, bool hasCachedDevices})> _loadCachedState(
    String ca,
    MeshIdentity own,
  ) async {
    var hasValidCert = false;
    var hasCachedDevices = false;
    final certFile = File('${root.path}/mesh-certificate.json');
    if (await certFile.exists()) {
      try {
        final saved = jsonDecode(await certFile.readAsString()) as JsonMap;
        final account = saved['account_id'];
        final cert = saved['certificate'];
        if (saved['device_id'] == own.deviceId &&
            account is String &&
            account.isNotEmpty &&
            cert is Map &&
            cert['pem'] is String &&
            cert['not_after'] is int) {
          await native.validate(
            ca,
            cert['pem'] as String,
            await own.privateKey(),
            account,
          );
          _account = account;
          _certificate = Map<String, Object?>.from(cert);
          _interval =
              max(900, saved['heartbeat_interval_seconds'] as int? ?? 900);
          hasValidCert = true;
        }
      } catch (_) {
        hasValidCert = false;
      }
    }

    if (hasValidCert) {
      final devicesFile = File('${root.path}/mesh-devices.json');
      if (await devicesFile.exists()) {
        try {
          final saved = jsonDecode(await devicesFile.readAsString()) as JsonMap;
          if (saved['account_id'] == _account && saved['devices'] is List) {
            final devices = [
              for (final d in saved['devices'] as List)
                Map<String, Object?>.from(d as Map),
            ];
            final epoch = saved['revocation_epoch'] as int? ?? 0;
            _devices = devices;
            if (epoch > _epoch) _epoch = epoch;
            hasCachedDevices = true;
          }
        } catch (_) {
          hasCachedDevices = false;
        }
      } else if (_devices.isNotEmpty) {
        hasCachedDevices = true;
      }
    }
    return (hasValidCert: hasValidCert, hasCachedDevices: hasCachedDevices);
  }

  Future<void> _startNode({
    required int listenPort,
    required bool broadcast,
  }) async {
    final own = identity!;
    _node = await native.start(
      ca: _ca!,
      certificate: _certificate!['pem'] as String,
      key: await own.privateKey(),
      account: _account!,
      allowed: _active,
      bind: '$_bindHost:$listenPort',
    );
    final node = _node!;
    final generation = ++_generation;
    _receiver = _receive(node, generation);
    final actualPort = await native.port(node);
    _discovery = MeshDiscovery(
      own.deviceId,
      actualPort,
      interfaces: interfaceProvider,
    );
    if (broadcast || SystemBonjour.available) {
      try {
        await _discovery!.start();
      } catch (_) {
        // Discovery only adds hints; whatever goes wrong here (port taken,
        // no multicast, sandbox) must not stop the node from joining.
        discoveryNotice =
            'LAN broadcast unavailable; coordinator candidates remain available.';
      }
    }
  }

  Future<JsonMap> _enrollOrRenew({
    required MeshCoordinator coordinator,
    required MeshIdentity own,
    required String name,
    required bool hasCertificateFile,
  }) async {
    final registerFields = [
      'register',
      own.publicKey,
      name,
      Platform.operatingSystem,
      '1',
    ];
    if (hasCertificateFile) {
      try {
        return await _renewRequest(coordinator, own);
      } on Failure catch (e) {
        if (e.message.contains('device_revoked')) {
          await _markRevoked();
          throw _revokedFailure;
        }
        if (!e.message.contains('device_not_found')) rethrow;
      }
    }
    return coordinator.request('POST', '/mesh/v1/devices/register', {
      'device_public_key': own.publicKey,
      'device_name': name,
      'platform': Platform.operatingSystem,
      'app_version': '1',
      'proof': await own.proof(registerFields, _nonce(), _nowSeconds),
    });
  }

  /// Renewal is proved by the device key alone (no account token), so it keeps
  /// working after the token has expired. Only the first join needs the token.
  Future<JsonMap> _renewRequest(MeshCoordinator coordinator, MeshIdentity own) async =>
      coordinator.request(
          'POST',
          '/mesh/v1/devices/renew',
          {
            'device_id': own.deviceId,
            'device_public_key': own.publicKey,
            'proof': await own.proof(
                ['renew', own.publicKey, own.deviceId], _nonce(), _nowSeconds),
          },
          false);

  static const _revokedFailure = Failure(
      FailureCode.unavailable, 'This Mesh device has been revoked.');

  /// The coordinator refused this device because it was removed: stop serving.
  Future<void> _markRevoked() async {
    status = 'device_revoked';
    await _stopNode();
  }

  Future<void> _applyRegistration(
    String ca,
    MeshIdentity own,
    JsonMap registration,
  ) async {
    if (registration['device_id'] != own.deviceId) {
      throw const FormatException('Coordinator device identity mismatch.');
    }
    final account = registration['account_id'] as String;
    final cert = Map<String, Object?>.from(registration['certificate'] as Map);
    await native.validate(
      ca,
      cert['pem'] as String,
      await own.privateKey(),
      account,
    );
    _account = account;
    _certificate = cert;
    _interval =
        max(900, registration['heartbeat_interval_seconds'] as int? ?? 900);
    await _writeAtomic('mesh-certificate.json', jsonEncode(registration));
  }

  Future<void> join({
    required String ca,
    required MeshCoordinator coordinator,
    required String name,
    int listenPort = 0,
    bool broadcast = true,
  }) async {
    if (_harness == null) {
      throw StateError('Attach the Core Harness before joining Mesh.');
    }
    _ca = ca;
    _broadcast = broadcast;
    _coordinator = coordinator;
    identity ??= await MeshIdentity.load(root, vault, native,
        // A device that is only a body names its key by a random installation
        // number, not by where it is installed, and starts a new identity when
        // the vault has lost the key (a restored backup) instead of refusing.
        installId: NextBody.bodyOnly ? await meshInstallId(root) : null);
    final own = identity!;
    await _loadRoutes();
    if (!_replayLoaded) {
      final file = File('${root.path}/mesh-replay.jsonl');
      if (await file.exists()) {
        for (final line in await file.readAsLines()) {
          if (line.trim().isEmpty) continue;
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

    final cacheFile = File('${root.path}/mesh-certificate.json');
    final hasCertificateFile = await cacheFile.exists();
    var cached = await _loadCachedState(ca, own);

    var newlyEnrolled = false;
    if (!cached.hasValidCert) {
      newlyEnrolled = !hasCertificateFile;
      final registration = await _enrollOrRenew(
        coordinator: coordinator,
        own: own,
        name: name,
        hasCertificateFile: hasCertificateFile,
      );
      await _applyRegistration(ca, own, registration);
      // A renewal (needs no account token) leaves the roster this device last
      // knew usable: it can serve the LAN at once instead of waiting for a
      // token that may have expired.
      if (!newlyEnrolled) cached = await _loadCachedState(ca, own);
    }

    if (cached.hasValidCert && cached.hasCachedDevices) {
      if (!_active.contains(own.deviceId)) {
        status = 'device_revoked';
        throw const Failure(
            FailureCode.unavailable, 'This Mesh device has been revoked.');
      }
      await _compactReplay();
      await _startNode(listenPort: listenPort, broadcast: broadcast);
      status = 'online';
      _announceOnline();
      try {
        await heartbeat(renew: _needsCertificateRenewal);
        _coordinatorSyncPending = false;
        _retryAttempts = 0;
        coordinatorNotice = null;
        _scheduleHeartbeat();
      } catch (error) {
        if (status == 'device_revoked') rethrow;
        // R1: the coordinator is unreachable, rate-limited or answering
        // nonsense (captive portal); keep working on the LAN with the cached
        // certificate and roster and retry in the background.
        _heartbeat?.cancel();
        _noteCoordinatorFailure(error);
      }
      return;
    }

    if (cached.hasValidCert && _needsCertificateRenewal) {
      final renewed = await _enrollOrRenew(
        coordinator: coordinator,
        own: own,
        name: name,
        hasCertificateFile: true,
      );
      await _applyRegistration(ca, own, renewed);
    }

    await refreshDevices();
    await _compactReplay();
    await _startNode(listenPort: listenPort, broadcast: broadcast);
    await _reportAddressesAndSyncEpoch();
    status = 'online';
    _announceOnline();
    _coordinatorSyncPending = false;
    _retryAttempts = 0;
    coordinatorNotice = null;
    if (newlyEnrolled) {
      unawaited(notifyDevicesChanged(reason: 'joined'));
    }
    _scheduleHeartbeat();
  }

  Future<void> _reportAddressesAndSyncEpoch() async {
    final own = identity!;
    final response = await _coordinator!.request('POST', '/mesh/v1/addresses', {
      'device_id': own.deviceId,
      'candidates': [
        if (_bindHost != '127.0.0.1') ...await _discovery!.localCandidates(),
        ..._manual,
      ].take(32).toList(),
    });
    _interval =
        max(900, response['heartbeat_interval_seconds'] as int? ?? _interval);
    final remoteEpoch = response['revocation_epoch'] as int?;
    if (remoteEpoch != null && remoteEpoch != _epoch) {
      await refreshDevices();
    }
  }

  Future<void>? _refreshQueued;

  /// Fetches the roster. A refresh that is already on the wire may have been
  /// answered before the change this caller knows about (a device that just
  /// registered), so it is never handed back as the caller's result: callers
  /// that arrive while one is running share a single follow-up refresh.
  Future<void> refreshDevices() {
    final inFlight = _refreshingDevices;
    if (inFlight == null) {
      final operation = _doRefreshDevices().whenComplete(() {
        _refreshingDevices = null;
      });
      _refreshingDevices = operation;
      return operation;
    }
    return _refreshQueued ??=
        inFlight.then<void>((_) {}, onError: (_) {}).then((_) {
      _refreshQueued = null;
      return refreshDevices();
    });
  }

  Timer? _deferredRefresh;
  int _claimedEpochHandled = -1;

  /// A peer says the roster changed. A revocation we have not seen (its epoch
  /// is ahead of ours and of any claim already acted on) is fetched at once:
  /// that is what makes a revoked device lose access everywhere immediately.
  /// Any other notice is limited to one refresh per
  /// [unknownPeerRefreshCooldown]; inside that window a single deferred
  /// refresh is left behind (a timer that exists only because a push arrived),
  /// so a chatty or confused peer cannot spend the coordinator's rate limit.
  Future<void> _refreshForPeerNotice({required int? claimedEpoch}) async {
    final revocation = claimedEpoch != null &&
        claimedEpoch > _epoch &&
        claimedEpoch > _claimedEpochHandled;
    if (revocation) {
      _claimedEpochHandled = claimedEpoch;
    } else {
      final wait = unknownPeerRefreshCooldown -
          DateTime.now().difference(_lastDevicesRefresh);
      if (wait > Duration.zero) {
        final noticedAt = DateTime.now();
        _deferredRefresh ??= Timer(wait, () {
          _deferredRefresh = null;
          if (_closed || _node == null) return;
          // A refresh that happened after the notice (a heartbeat, a stranger's
          // verification) already carries what the notice announced.
          if (_lastDevicesRefresh.isAfter(noticedAt)) return;
          unawaited(refreshDevices().catchError(_noteCoordinatorFailure));
        });
        return;
      }
    }
    try {
      await refreshDevices();
    } catch (error) {
      if (status == 'device_revoked') rethrow;
      _noteCoordinatorFailure(error);
    }
  }

  Future<void> _doRefreshDevices() async {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw const Failure(FailureCode.unavailable, 'Mesh is not configured.');
    }
    final response = await coordinator.request('GET', '/mesh/v1/devices');
    if (_account != null && response['account_id'] != _account) {
      throw const FormatException('Coordinator account mismatch.');
    }
    _account ??= response['account_id'] as String?;
    final devices = (response['devices'] as List).cast<JsonMap>();
    final epoch = response['revocation_epoch'] as int;
    if (epoch < _epoch) {
      throw const FormatException(
          'Coordinator revocation epoch went backwards.');
    }
    _devices = devices;
    _epoch = epoch;
    presence.retain({for (final d in devices) d['device_id'] as String});
    _lastDevicesRefresh = DateTime.now();
    _catalogs.removeWhere((id, _) => !_active.contains(id));
    if (_node case final node?) await native.update(node, _active);
    final revokedSelf =
        identity != null && !_active.contains(identity!.deviceId);
    await _writeAtomic('mesh-devices.json', jsonEncode(response));
    if (revokedSelf) {
      await _stopNode();
      status = 'device_revoked';
      throw const Failure(
          FailureCode.unavailable, 'This Mesh device has been revoked.');
    }
    // Remembering who is new never delays or fails a roster refresh.
    final roster = [for (final device in _devices) Map<String, Object?>.from(device)];
    _joinWork = _joinWork.then((_) => _noteJoins(roster)).catchError((Object _) {});
    _hostChanges.add(null);
  }

  Future<void> heartbeat({bool renew = true}) async {
    final own = identity!;
    // The certificate is renewed first and by the device key alone: an account
    // token that has expired must not leave the device to drop out of the mesh
    // when its certificate runs out.
    Object? renewError;
    if (renew && _needsCertificateRenewal) {
      try {
        await _renewCertificate(own);
      } catch (error) {
        if (status == 'device_revoked') rethrow;
        renewError = error;
      }
    }
    JsonMap? response;
    Object? addressError;
    try {
      response = await _coordinator!.request('POST', '/mesh/v1/addresses', {
        'device_id': own.deviceId,
        'candidates': [
          if (_bindHost != '127.0.0.1') ...await _discovery!.localCandidates(),
          ..._manual,
        ].take(32).toList(),
      });
    } catch (error) {
      addressError = error;
    }
    // A revoked device cannot report addresses but must still learn its
    // revocation; an unreachable coordinator would only fail a second time.
    final unreachable = addressError is Failure && addressError.retryable;
    if (!unreachable && status != 'device_revoked') {
      try {
        await refreshDevices();
      } catch (error) {
        if (status == 'device_revoked') rethrow;
        // With an expired token the roster cannot be read; the renewal above
        // does not depend on it, and its own failure (if any) is reported.
        addressError ??= error;
      }
    }
    if (renewError != null) {
      Error.throwWithStackTrace(renewError, StackTrace.current);
    }
    if (addressError != null) {
      Error.throwWithStackTrace(addressError, StackTrace.current);
    }
    _interval =
        max(900, response!['heartbeat_interval_seconds'] as int? ?? _interval);
    _coordinatorSyncPending = false;
    _retryAttempts = 0;
    coordinatorNotice = null;
  }

  Future<void> _renewCertificate(MeshIdentity own) async {
    final JsonMap renewed;
    try {
      renewed = await _renewRequest(_coordinator!, own);
    } on Failure catch (failure) {
      if (failure.message.contains('device_revoked')) {
        await _markRevoked();
        throw _revokedFailure;
      }
      rethrow;
    }
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
    await _writeAtomic('mesh-certificate.json', jsonEncode(renewed));
    await _startNode(listenPort: bindPort, broadcast: _broadcast);
  }

  /// A coordinator call failed while the LAN node keeps running: remember it
  /// and make sure one retry is pending. Never resets a pending timer, so
  /// frequent callers cannot starve the heartbeat or inflate its back-off.
  void _noteCoordinatorFailure(Object error) {
    coordinatorNotice = error is Failure
        ? error.message
        : 'Mesh coordinator returned an unexpected response.';
    _coordinatorSyncPending = true;
    if (_heartbeat?.isActive != true) _scheduleHeartbeat(retry: true);
  }

  void _scheduleHeartbeat({bool retry = false}) {
    _heartbeat?.cancel();
    if (_closed || _node == null) return;
    final Duration delay;
    if (retry || _coordinatorSyncPending) {
      final factor = 1 << min(_retryAttempts, 6);
      final retryMs = coordinatorRetryDelay.inMilliseconds * factor;
      final maxMs = _interval * 1000;
      delay = Duration(milliseconds: min(retryMs, maxMs));
      _retryAttempts++;
    } else {
      delay = Duration(
          seconds: _interval + _random.nextInt(max(1, _interval ~/ 10)));
    }
    _heartbeat = Timer(delay, () async {
      await _queue(() => heartbeat());
      if (!_closed && _node != null) {
        _scheduleHeartbeat(retry: _coordinatorSyncPending);
      }
    });
  }

  /// Broadcasts `mesh/devices/changed` to all other active peers so they
  /// immediately refresh their device list without polling every 30s.
  Future<void> notifyDevicesChanged({
    String reason = 'changed',
    String? targetDeviceId,
  }) async {
    if (_node == null || identity == null) return;
    final ownId = identity!.deviceId;
    final peers = [
      for (final id in _active)
        if (id != ownId && id != targetDeviceId) id,
    ];
    if (peers.isEmpty) return;
    await Future.wait([
      for (final peer in peers)
        rpc(peer, 'mesh/devices/changed', {
          'reason': reason,
          if (targetDeviceId != null) 'deviceId': targetDeviceId,
          'revocationEpoch': _epoch,
        }).then<void>((_) {}, onError: (_) {}),
    ]);
  }

  /// Removes [deviceId] from the account's devices: it loses access at once
  /// everywhere (this device closes its sessions and refuses its connections
  /// before this returns; the others are told). Only the person at a host
  /// asks for this; no Action reaches it.
  Future<void> revoke(String deviceId) async {
    if (deviceId == identity?.deviceId) {
      throw const Failure(FailureCode.invalidInput,
          'A device cannot remove itself; leave the mesh instead.');
    }
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw const Failure(FailureCode.unavailable, 'Mesh is not configured.');
    }
    await coordinator.request(
        'POST', '/mesh/v1/devices/$deviceId/revoke', {'device_id': deviceId});
    await refreshDevices();
    await acknowledgeJoin(deviceId);
    await notifyDevicesChanged(reason: 'revoked', targetDeviceId: deviceId);
  }

  /// The name of an active device of this account; null for any other.
  String? deviceName(String deviceId) {
    for (final device in _devices) {
      if (device['device_id'] == deviceId && device['revoked'] == false) {
        return device['device_name'] as String? ?? deviceId;
      }
    }
    return null;
  }

  // Devices seen for the first time. A device that appears in the roster and
  // was never seen here is announced once to the screens (a prompt with "not
  // me") until someone answers; a host without a screen only records it.
  final _joinNotices = StreamController<JsonMap>.broadcast();
  Map<String, JsonMap>? _known;
  final _announced = <String>{};
  Future<void> _knownWrites = Future.value();
  Future<void> _joinWork = Future.value();

  /// Completes when the devices seen so far have been looked at for newcomers
  /// (what was found has been announced and recorded).
  Future<void> get joinsSettled => _joinWork;

  /// A device that is new to this one and has not been answered for yet:
  /// `deviceId`, `name`, `platform`, `firstSeenAt`.
  Stream<JsonMap> get joinNotices => _joinNotices.stream;

  File get _knownFile => File('${root.path}/mesh-known-devices.json');

  Future<void> _loadKnown() async {
    if (_known != null) return;
    final known = <String, JsonMap>{};
    var baseline = true;
    if (await _knownFile.exists()) {
      baseline = false;
      try {
        final saved = jsonDecode(await _knownFile.readAsString()) as JsonMap;
        for (final entry in (saved['devices'] as Map? ?? {}).entries) {
          known[entry.key as String] =
              Map<String, Object?>.from(entry.value as Map);
        }
      } on FormatException {
        baseline = true;
      }
    }
    _known = known;
    _knownBaseline = baseline;
  }

  bool _knownBaseline = false;

  Future<void> _writeKnown() {
    final snapshot = jsonEncode({'devices': _known});
    return _knownWrites = _knownWrites.then((_) async {
      final pending = File('${_knownFile.path}.pending');
      await pending.writeAsString(snapshot, flush: true);
      await pending.rename(_knownFile.path);
    });
  }

  Future<void> _noteJoins(List<JsonMap> roster) async {
    await _loadKnown();
    final known = _known!;
    final self = identity?.deviceId;
    final now = DateTime.now().toUtc().toIso8601String();
    var changed = false;
    for (final device in roster) {
      final id = device['device_id'] as String;
      if (device['revoked'] == true || known.containsKey(id)) continue;
      // The first roster this device ever reads is not news: everything in it
      // was there before, as is this device itself.
      known[id] = {
        'name': device['device_name'],
        'platform': device['platform'],
        'firstSeenAt': now,
        'acknowledged': _knownBaseline || id == self,
      };
      changed = true;
    }
    _knownBaseline = false;
    if (changed) await _writeKnown();
    for (final entry in known.entries) {
      if (entry.value['acknowledged'] == true ||
          entry.key == self ||
          !_active.contains(entry.key) ||
          !_announced.add(entry.key)) {
        continue;
      }
      _joinNotices.add({'deviceId': entry.key, ...entry.value});
    }
  }

  /// The person at a screen answered for [deviceId] (it is theirs, or it was
  /// removed): it is not announced again.
  Future<void> acknowledgeJoin(String deviceId) async {
    await _joinWork;
    await _loadKnown();
    final entry = _known![deviceId];
    if (entry == null || entry['acknowledged'] == true) return;
    entry['acknowledged'] = true;
    await _writeKnown();
  }

  /// What this device knows of when a device first appeared.
  JsonMap _joinFacts(String deviceId) {
    final entry = _known?[deviceId];
    if (entry == null) return const {};
    return {
      'firstSeenAt': entry['firstSeenAt'],
      'acknowledged': entry['acknowledged'] == true,
    };
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

  /// The other devices of the account and whether Nipa runs on each: live
  /// for a device that answers, as last seen for one that does not.
  /// `{deviceId, name, online, agent: {runs, busy, model, reason?}?}`.
  Future<List<JsonMap>> agentDevices() async {
    final listed = await devices(includeCatalog: false);
    await _loadHostFacts();
    final self = identity?.deviceId;
    return [
      for (final device in (listed['devices'] as List).cast<JsonMap>())
        if (device['device_id'] != self && device['revoked'] != true)
          {
            'deviceId': device['device_id'],
            'name': device['device_name'],
            'online': device['online'] == true,
            'agent': device['online'] == true
                ? ((device['description'] as Map?)?['agent'])
                : (_descriptions[device['device_id']]?['agent']),
          }
    ];
  }

  Future<JsonMap> devices({
    List<String>? deviceIds,
    bool includeCatalog = true,
  }) async {
    // The roster is refreshed on heartbeats and on "devices changed" pushes,
    // never per call: reading it must not spend the coordinator's rate limit.
    if (_node == null) return {'status': status, 'devices': <Object?>[]};
    await _joinWork;
    return {
      'status': status,
      if (discoveryNotice != null) 'discoveryNotice': discoveryNotice,
      'devices': [
        for (final device in _devices)
          if (deviceIds == null || deviceIds.contains(device['device_id']))
            {
              ...await _describe(device, includeCatalog: includeCatalog),
              ..._joinFacts(device['device_id'] as String),
            },
      ]
    };
  }

  Future<JsonMap> _describe(
    JsonMap device, {
    bool includeCatalog = true,
  }) async {
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
      presence.record(id, description['presence']);
      _descriptions[id] = {
        'roles': description['roles'] ??
            [
              if (description['host'] != null) description['host'],
              if (description['conversationHost'] == true) 'conversation',
            ],
        'programExecution': {
          'enabled':
              (description['programExecution'] as Map?)?['enabled'] == true
        },
        // Kept for a device that is away: whether Nipa ran there when it was
        // last seen.
        if (description['agent'] is Map) 'agent': description['agent'],
      };
      await File('${root.path}/mesh-host-facts.json')
          .writeAsString(jsonEncode(_descriptions), flush: true);
      return {
        ...device,
        'deviceId': id,
        'online': true,
        if (presence.of(id) case final fact?) 'presence': fact.toJson(),
        if (includeCatalog) 'actions': tools,
        'description': description
      };
    } on Failure {
      _reachability[id] = false;
      return {
        ...device,
        'deviceId': id,
        'online': false,
        if (presence.of(id) case final fact?) 'presence': fact.toJson(),
        if (includeCatalog) 'actions': _catalogs[id] ?? <Object?>[]
      };
    }
  }

  Future<List<JsonMap>> _catalog(String peer) async {
    final tools = <JsonMap>[];
    String? cursor;
    // MCP pagination: a page carries `nextCursor` until the list is complete.
    for (var page = 0; page < 64; page++) {
      final result =
          await rpc(peer, 'tools/list', {if (cursor != null) 'cursor': cursor});
      tools.addAll((result['tools'] as List).cast<JsonMap>());
      cursor = result['nextCursor'] as String?;
      if (cursor == null) break;
    }
    if (cursor != null) {
      throw const Failure(
          FailureCode.unavailable, 'Remote Action catalog has too many pages.');
    }
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
    final targetReturn = {
              'download.add',
              'program.run',
              'followup.register',
            }.contains(action) &&
            invocation != null
        ? await returnTarget?.call(peer, invocation)
        : null;
    final result = await rpc(peer, 'tools/call', {
      'name': target['name'],
      'arguments': input,
      'meshDestructive': destructive,
      if (targetReturn != null)
        'returnTo': {...targetReturn, 'deviceId': identity!.deviceId},
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

  Future<List<JsonMap>> _coordinatorCandidatesFor(String peer) async {
    final coordinator = _coordinator;
    final cached = _peerCandidates[peer];
    final lookedUp = _candidateLookupAt[peer];
    if (coordinator == null) return cached ?? const [];
    final refusedAt = _candidateLookupRefusedAt[peer];
    if (refusedAt != null &&
        DateTime.now().difference(refusedAt) <
            (_candidateLookupRefusedGap[peer] ?? candidateLookupBase)) {
      return cached ?? const [];
    }
    // With something cached, a coordinator known to be unreachable and the
    // backoff window both mean "use it"; without any answer yet, try anyway.
    if (cached != null &&
        lookedUp != null &&
        (_coordinatorSyncPending ||
            !_reachedSinceLookup.contains(peer) &&
                DateTime.now().difference(lookedUp) <
                    (_candidateLookupGap[peer] ?? candidateLookupBase))) {
      return cached;
    }
    try {
      final response = await coordinator.request(
          'GET', '/mesh/v1/addresses?device_id=$peer');
      final list = (response['candidates'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      final unchanged =
          cached != null && jsonEncode(cached) == jsonEncode(list);
      final gap = _candidateLookupGap[peer] ?? candidateLookupBase;
      _candidateLookupGap[peer] =
          unchanged && !_reachedSinceLookup.contains(peer)
              ? Duration(
                  milliseconds: min(gap.inMilliseconds * 2,
                      candidateLookupInterval.inMilliseconds))
              : candidateLookupBase;
      _reachedSinceLookup.remove(peer);
      _candidateLookupRefusedAt.remove(peer);
      _candidateLookupRefusedGap.remove(peer);
      _peerCandidates[peer] = list;
      _candidateLookupAt[peer] = DateTime.now();
      unawaited(_persistRoutes());
      return list;
    } on Failure catch (failure) {
      if (!failure.retryable) {
        // The coordinator answered and said no (an account token that has
        // expired, a device it no longer knows). Retrying every few seconds
        // would only spend its rate limit: leave it alone for a while, longer
        // each time, and let the call go on with what is known (the other
        // routes, the remembered one).
        final gap = _candidateLookupRefusedGap[peer] ?? candidateLookupBase;
        _candidateLookupRefusedAt[peer] = DateTime.now();
        _candidateLookupRefusedGap[peer] = Duration(
            milliseconds:
                min(gap.inMilliseconds * 2, candidateLookupInterval.inMilliseconds));
      }
      _noteCoordinatorFailure(failure);
      return _peerCandidates[peer] ?? const [];
    }
  }

  static bool _isConnectStageError(Object error) {
    if (error is SocketException) return true;
    final text = error.toString();
    return text.contains('connect:');
  }

  Future<JsonMap> rpc(String peer, String method, JsonMap params,
      {JsonMap? replayFrame, bool ungated = false}) async {
    final node = _node;
    if (node == null) {
      throw const Failure(FailureCode.unavailable, 'Mesh is offline.');
    }
    if (!ungated && peer != identity?.deviceId && presence.absent(peer)) {
      _probePresence(peer);
      throw _notPresent(peer);
    }
    if (!_active.contains(peer)) {
      final isKnownRevoked =
          _devices.any((d) => d['device_id'] == peer && d['revoked'] == true);
      final now = DateTime.now();
      final lastCheck = _unknownPeerCheckedAt[peer];
      if (!isKnownRevoked &&
          (lastCheck == null ||
              now.difference(lastCheck) >= unknownPeerRefreshCooldown)) {
        _unknownPeerCheckedAt[peer] = now;
        try {
          await refreshDevices();
        } on Failure {
          // Offline coordinator fallback preserves existing roster.
        }
      } else if (_refreshingDevices case final inFlight?) {
        // The peer was checked moments ago (it just connected and is being
        // verified): that refresh decides, not the roster from before it.
        try {
          await inFlight;
        } on Failure {
          // Offline coordinator fallback preserves existing roster.
        }
      }
      if (!_active.contains(peer)) {
        throw const Failure(
            FailureCode.unavailable, 'Mesh device is revoked or unknown.');
      }
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
    await _loadRoutes();
    final remembered = _routes[peer];
    final localAddresses = await (_discovery?.localLanAddresses() ??
        Future.value(const <InternetAddress>[]));
    final localHosts = [for (final addr in localAddresses) addr.address];
    final rawCandidates = <JsonMap>[
      if (remembered != null) {...remembered, 'priority': 1000},
      if (peer == identity!.deviceId)
        {'kind': 'lan', 'host': '127.0.0.1', 'port': port, 'priority': 2000},
      ...(_discovery?.hints(peer) ?? const <JsonMap>[]),
      if (peer != identity!.deviceId)
        // A remembered route never waits on the coordinator; its other cached
        // candidates are the fallback if the route went stale.
        ...(remembered == null
            ? await _coordinatorCandidatesFor(peer)
            : _peerCandidates[peer] ?? const <JsonMap>[]),
    ];
    final candidates =
        rankMeshCandidates(rawCandidates, localHosts: localHosts);
    if (candidates.isEmpty) {
      if (remembered != null) {
        await _removeRoute(peer);
        return rpc(peer, method, params,
            replayFrame: frame, ungated: ungated);
      }
      throw meshNotDelivered(peer, 'no known address');
    }

    try {
      final winner = await _attemptCandidates(
        node: node,
        peer: peer,
        method: method,
        frame: frame,
        candidates: candidates,
      );
      await _saveRoute(peer, winner.candidate);
      _reachedSinceLookup.add(peer);
      return winner.result;
    } on Failure catch (failure) {
      if (remembered != null &&
          failure.code == FailureCode.unavailable &&
          failure.retryable &&
          const {'not_delivered', 'outcome_unknown'}
              .contains(failure.details['reason'])) {
        await _removeRoute(peer);
        return rpc(peer, method, params,
            replayFrame: frame, ungated: ungated);
      }
      rethrow;
    }
  }

  Future<({JsonMap candidate, JsonMap result})> _attemptCandidates({
    required int node,
    required String peer,
    required String method,
    required JsonMap frame,
    required List<JsonMap> candidates,
  }) async {
    final encodedFrame = jsonEncode(frame);
    final completer = Completer<({JsonMap candidate, JsonMap result})>();
    var launched = 0;
    var active = 0;
    var finished = false;
    var hadPostConnectFailure = false;
    // What stopped each candidate before the request left this device.
    String? connectCause;
    Failure? rpcFailure;
    FormatException? formatError;
    Timer? staggerTimer;

    void finishWithError(Object error) {
      if (finished) return;
      finished = true;
      staggerTimer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    void finishWithSuccess(JsonMap candidate, JsonMap result) {
      if (finished) return;
      finished = true;
      staggerTimer?.cancel();
      if (!completer.isCompleted) {
        completer.complete((candidate: candidate, result: result));
      }
    }

    late void Function() launchNextIfPossible;

    void checkCompletion() {
      if (finished) return;
      if (active == 0) {
        final canLaunchMore = launched < candidates.length &&
            !(method == 'tools/call' && hadPostConnectFailure);
        if (canLaunchMore) {
          launchNextIfPossible();
          return;
        }
        if (formatError != null) {
          finishWithError(formatError!);
        } else if (rpcFailure != null) {
          finishWithError(rpcFailure!);
        } else if (hadPostConnectFailure) {
          // The request was on the wire when the connection broke: the other
          // device may have acted on it.
          finishWithError(meshOutcomeUnknown(peer, method));
        } else {
          finishWithError(meshNotDelivered(peer, connectCause));
        }
      }
    }

    launchNextIfPossible = () {
      if (finished ||
          launched >= candidates.length ||
          (method == 'tools/call' && hadPostConnectFailure)) {
        return;
      }
      final index = launched++;
      final candidate = candidates[index];
      active++;
      unawaited(() async {
        try {
          final body = await native.send(
            node,
            candidate['host'] as String,
            candidate['port'] as int,
            peer,
            encodedFrame,
          );
          if (finished) return;
          final Object? decoded;
          try {
            decoded = jsonDecode(body);
          } on FormatException catch (e) {
            formatError ??= e;
            return;
          }
          if (decoded is! JsonMap ||
              decoded['jsonrpc'] != '2.0' ||
              decoded['id'] != frame['id']) {
            formatError ??=
                const FormatException('Mesh RPC response mismatch.');
            return;
          }
          if (decoded['error'] != null) {
            final error = decoded['error'] as JsonMap;
            if (error['code'] == -32001 && error['data'] is JsonMap) {
              final denial = error['data'] as JsonMap;
              finishWithError(Failure(
                  FailureCode.values
                      .firstWhere((c) => c.wireName == denial['code']),
                  denial['message'] as String));
              return;
            }
            if (error['code'] == -32600 && active > 1) {
              // Another concurrent candidate already delivered this frame and
              // is still awaiting its response. Keep waiting for that winner.
              hadPostConnectFailure = true;
              rpcFailure ??= const Failure(
                  FailureCode.invalidInput, 'Remote RPC rejected the request.');
              return;
            }
            finishWithError(const Failure(
                FailureCode.invalidInput, 'Remote RPC rejected the request.'));
            return;
          }
          finishWithSuccess(candidate, decoded['result'] as JsonMap);
        } catch (error) {
          if (finished) return;
          if (!_isConnectStageError(error)) {
            hadPostConnectFailure = true;
          } else {
            connectCause ??= meshConnectCause(error);
          }
        } finally {
          active--;
          checkCompletion();
        }
      }());
    };

    launchNextIfPossible();
    if (candidates.length > 1 && !finished) {
      staggerTimer = Timer.periodic(candidateStaggerDelay, (timer) {
        if (finished ||
            launched >= candidates.length ||
            (method == 'tools/call' && hadPostConnectFailure)) {
          timer.cancel();
          return;
        }
        launchNextIfPossible();
      });
    }

    return completer.future;
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
    if (event.body == '\u0000mesh-verify-peer') {
      final knownRevoked = _devices
          .any((d) => d['device_id'] == event.deviceId && d['revoked'] == true);
      final now = DateTime.now();
      final last = _unknownPeerCheckedAt[event.deviceId];
      if (!_active.contains(event.deviceId) &&
          !knownRevoked &&
          (last == null ||
              now.difference(last) >= unknownPeerRefreshCooldown)) {
        _unknownPeerCheckedAt[event.deviceId] = now;
        try {
          await refreshDevices();
        } catch (_) {}
      }
      try {
        await native.respond(
          node,
          event.requestId,
          jsonEncode({
            'result': {'allowed': _active.contains(event.deviceId)}
          }),
        );
      } catch (_) {}
      return;
    }
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
        response = {
          'jsonrpc': '2.0',
          'id': frame['id'],
          'result': {
            'deviceId': identity!.deviceId,
            'name': hostConfiguration['name'] ?? Platform.localHostname,
            'platform': Platform.operatingSystem,
            'agentDeviceId': hostConfiguration['agentDeviceId'],
            'roles': hostConfiguration['roles'] ?? <String>[],
            'presence': ownPresence(),
            'storage': hostConfiguration['storage'] ?? <Object?>[],
            if (describeSelf != null) ...await describeSelf!(),
            if (_harness!.lookup('app.capabilities') != null)
              'capabilities': (await _harness!.invokeJson('app.capabilities',
                      {}, Invocation(origin: 'mesh:describe')))
                  .toEnvelope(),
          }
        };
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if (frame['method'] == 'mesh/devices/changed') {
        final params = frame['params'] is JsonMap
            ? frame['params'] as JsonMap
            : const <String, Object?>{};
        final reportedEpoch = params['revocationEpoch'];
        await _refreshForPeerNotice(
            claimedEpoch: reportedEpoch is int ? reportedEpoch : null);
        response = {
          'jsonrpc': '2.0',
          'id': frame['id'],
          'result': {
            'accepted': true,
            'revocationEpoch': _epoch,
          }
        };
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if (frame['method'] == 'mesh/presence') {
        final accepted = presence.record(event.deviceId, frame['params']);
        if (accepted) _hostChanges.add(null);
        response = {
          'jsonrpc': '2.0',
          'id': frame['id'],
          'result': {'accepted': accepted, 'presence': ownPresence()}
        };
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if (frame['method'] == 'mesh/delivery') {
        if (receiveDelivery == null) {
          throw const FormatException('No delivery host.');
        }
        final result =
            await receiveDelivery!(event.deviceId, frame['params'] as JsonMap);
        response = {'jsonrpc': '2.0', 'id': frame['id'], 'result': result};
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if (delegationMethods.contains(frame['method']) ||
          chatGuestMethods.contains(frame['method'])) {
        final host = delegationMethods.contains(frame['method'])
            ? agentRequest
            : chatRequest;
        if (host == null) {
          throw const FormatException('No agent host.');
        }
        try {
          final result = await host(frame['method'] as String,
              (frame['params'] as JsonMap?) ?? const {}, event.deviceId);
          response = {'jsonrpc': '2.0', 'id': frame['id'], 'result': result};
        } on Failure catch (failure) {
          // The reason travels: a Nipa that cannot take a task says why.
          response = {
            'jsonrpc': '2.0',
            'id': frame['id'],
            'error': {
              'code': -32001,
              'message': failure.message,
              'data': {
                'code': failure.code.wireName,
                'message': failure.message,
              }
            }
          };
        }
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      if ((frame['method'] as String).startsWith('mesh/library/')) {
        if (libraryRequest == null) {
          throw const FormatException('No library host.');
        }
        final result = await libraryRequest!(frame['method'] as String,
            frame['params'] as JsonMap, event.deviceId);
        response = {'jsonrpc': '2.0', 'id': frame['id'], 'result': result};
        await native.respond(node, event.requestId, jsonEncode(response));
        return;
      }
      final params = frame['params'] as JsonMap?;
      final returnTo = params?['returnTo'];
      if (returnTo != null &&
          (returnTo is! JsonMap ||
              returnTo['deviceId'] != event.deviceId ||
              returnTo['threadId'] is! String ||
              returnTo['repository'] is! String)) {
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
      response = await runZoned(
              () => rpc.handle(
                  frame, Invocation(origin: 'mesh:${event.deviceId}', id: id)),
              zoneValues: {#meshReturnTarget: returnTo}) ??
          {'jsonrpc': '2.0', 'id': null, 'result': <String, Object?>{}};
      if (frame['method'] == 'tools/list') {
        response = _toolsListPage(response, params?['cursor']);
      }
      final result = response['result'] as JsonMap?;
      if (result?.containsKey('structuredContent') == true) {
        // Mesh consumers decode structuredContent; duplicating it as escaped
        // text can exceed the frame limit even when the complete result fits.
        result!['content'] = [
          {
            'type': 'text',
            'text': 'Complete Action outcome is in structuredContent.'
          }
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

  /// Cuts the full `tools/list` answer to one page of at most
  /// [toolsPageBytes] (always at least one tool); `cursor` is the index of the
  /// first tool of the page, and `nextCursor` is absent on the last page.
  JsonMap _toolsListPage(JsonMap response, Object? cursor) {
    final result = response['result'];
    if (result is! JsonMap || result['tools'] is! List) return response;
    final tools = (result['tools'] as List).cast<JsonMap>();
    final start =
        cursor == null ? 0 : (cursor is String ? int.tryParse(cursor) : null);
    if (start == null || start < 0 || start > tools.length) {
      throw const FormatException('Invalid tools/list cursor.');
    }
    var bytes = 0, end = start;
    while (end < tools.length) {
      bytes += utf8.encode(jsonEncode(tools[end])).length;
      if (end > start && bytes > toolsPageBytes) break;
      end++;
    }
    return {
      ...response,
      'result': {
        ...result,
        'tools': tools.sublist(start, end),
        if (end < tools.length) 'nextCursor': '$end',
      },
    };
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

  int get _nowSeconds => _clockSeconds != null
      ? _clockSeconds()
      : DateTime.now().millisecondsSinceEpoch ~/ 1000;

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

  // ---- presence and the lifecycle of a device with a screen

  /// This device's own presence, as it tells the others.
  JsonMap ownPresence() => {
        'state': _ownState,
        'at': _ownStateAt.toIso8601String(),
        ...?presenceFacts?.call(),
      };

  Failure _notPresent(String peer) {
    final fact = presence.of(peer);
    return Failure(
        FailureCode.unavailable,
        'device_not_present: the device is not in front, so nothing was sent.',
        retryable: true,
        details: {
          'reason': 'device_not_present',
          'deviceId': peer,
          if (fact != null) 'lastPresence': fact.toJson(),
        });
  }

  /// Tells every other device where this one is. A device that is itself
  /// absent is still told: that is how it learns this one is back.
  Future<void> announcePresence(String state) async {
    assert(PresenceState.all.contains(state));
    _ownState = state;
    _ownStateAt = DateTime.now().toUtc();
    _announcedAbsent = state != PresenceState.foreground;
    final own = identity?.deviceId;
    if (_node == null || own == null) return;
    final params = ownPresence();
    await Future.wait([
      for (final peer in _active)
        if (peer != own)
          rpc(peer, 'mesh/presence', params, ungated: true)
              .timeout(const Duration(seconds: 3))
              .then<void>((_) {}, onError: (_) {}),
    ]);
  }

  void _announceOnline() {
    if (!_announcedAbsent && !NextBody.bodyOnly) return;
    unawaited(announcePresence(PresenceState.foreground));
  }

  /// A device that said it is not in front may have come back without the
  /// others hearing (the announcement is lost, or it was sent while they were
  /// away). The call that was refused asks it once, without waiting.
  void _probePresence(String peer) {
    final now = DateTime.now();
    final last = _presenceProbeAt[peer];
    if (_presenceProbing.contains(peer) ||
        (last != null && now.difference(last) < presenceProbeInterval)) {
      return;
    }
    _presenceProbeAt[peer] = now;
    _presenceProbing.add(peer);
    unawaited(() async {
      try {
        final description = await rpc(peer, 'mesh/describe', {}, ungated: true)
            .timeout(const Duration(seconds: 5));
        final fact = description['presence'];
        if (!presence.record(peer, fact) && fact == null) {
          presence.record(peer, {
            'state': PresenceState.foreground,
            'at': DateTime.now().toUtc().toIso8601String(),
          });
        }
        _hostChanges.add(null);
      } catch (_) {
        // Still away: the next refused call asks again.
      } finally {
        _presenceProbing.remove(peer);
      }
    }());
  }

  /// The application went behind another one, or the screen locked. The
  /// system may now take the listening socket; the others are told first.
  Future<void> enterBackground() => announcePresence(PresenceState.background);

  /// Back in front: the listener may have been taken while away, so it is
  /// opened again on the same port, the addresses are reported afresh (the
  /// network may have changed), and the others are told.
  Future<void> enterForeground() async {
    _ownState = PresenceState.foreground;
    _ownStateAt = DateTime.now().toUtc();
    await resumeListening();
    // What waits on the mesh (a conversation with another device's Nipa)
    // looks again: the system may have cut its connections while behind.
    if (!_hostChanges.isClosed) _hostChanges.add(null);
    await announcePresence(PresenceState.foreground);
  }

  Future<void> resumeListening() => _queue(() async {
        if (_closed || _coordinator == null) return;
        if (_node == null) {
          // Not joined yet (offline at launch): try now, not at the next tick.
          _nextJoinAttempt = DateTime.fromMillisecondsSinceEpoch(0);
          await _loginCheck?.call();
          return;
        }
        final bindPort = port;
        await _stopNode();
        await _startNode(listenPort: bindPort, broadcast: _broadcast);
        status = 'online';
        try {
          await heartbeat(renew: _needsCertificateRenewal);
          _scheduleHeartbeat();
        } catch (error) {
          if (status == 'device_revoked') rethrow;
          _heartbeat?.cancel();
          _noteCoordinatorFailure(error);
        }
      });

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
    _deferredRefresh?.cancel();
    await _operations;
    await _stopNode();
    await _replayWrites;
    await _routeWrites;
    _coordinator?.close();
    await _hostChanges.close();
    await _joinWork;
    await _joinNotices.close();
    await _knownWrites;
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

/// The request never left this device: the connection or the handshake failed
/// first, so the other device did nothing. [cause] says what stopped it.
Failure meshNotDelivered(String peer, String? cause) => Failure(
        FailureCode.unavailable,
        'not_delivered: the request was not sent'
        '${cause == null ? '' : ' ($cause)'}.',
        retryable: true,
        details: {
          'reason': 'not_delivered',
          'deviceId': peer,
          'stage': 'connect',
          if (cause != null) 'cause': cause,
        });

/// The request was sent and the connection broke before an answer came: the
/// other device may or may not have done it. A call that changes something
/// ([method] `tools/call`) is not repeated blindly.
Failure meshOutcomeUnknown(String peer, String method) => Failure(
        FailureCode.unavailable,
        'outcome_unknown: the request was sent and no answer came back; '
        'the device may have done it. Ask it what happened before repeating.',
        retryable: method != 'tools/call',
        details: {
          'reason': 'outcome_unknown',
          'deviceId': peer,
          'stage': 'after_send',
        });

/// A short, address-free reason for a connect-stage error.
String meshConnectCause(Object error) {
  var text = '$error';
  final at = text.indexOf('connect:');
  if (at >= 0) text = text.substring(at + 'connect:'.length);
  text = text.trim().split('\n').first;
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}
