import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:nipaplay/services/remote_proxy_diagnostics.dart';
import 'package:nipaplay/services/smb2_native_service.dart';
import 'package:nipaplay/services/smb_service.dart';

class SMBProxyService {
  static const String _portKey = 'smb_proxy_port';
  static const int _defaultPort = 33221;
  static const Duration _stopTimeout = Duration(seconds: 2);

  SMBProxyService._();

  static final SMBProxyService instance = SMBProxyService._();

  // The listener itself is observed inside the proxy isolate; this instance
  // logs root-side lifecycle and probes the proxy over loopback.
  late final _diagnostics = RemoteProxyDiagnostics('SMB', onResume: _onResume);
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _receiveSubscription;
  SendPort? _controlPort;
  int _port = 0;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get port => _port;

  Future<void>? _initializing;
  Future<void>? _stopping;
  int _nextControlId = 1;
  final Map<int, Completer<Object?>> _pendingControl =
      <int, Completer<Object?>>{};
  VoidCallback? _smbListener;

  @visibleForTesting
  Future<void> closeListenerForTesting() async {
    await _sendControlWithAck({'op': 'test_close_listener'});
  }

  Future<void> initialize() async {
    _diagnostics
        .log('initialize running=$_isRunning pending=${_initializing != null}');
    if (kIsWeb) return;
    // A proxy that is stopping must not be handed out again: wait for the
    // stop, then start a fresh one. A stop that begins while this call waits
    // on a shared start or health probe is waited for as well.
    do {
      while (_stopping != null) {
        await _stopping;
      }
      await _ensureListener('initialize-reuse');
    } while (_stopping != null);
  }

  Future<void> _onResume() async {
    if (_stopping == null && _isRunning) {
      await _ensureListener('lifecycle-resumed');
    }
  }

  Future<void> _ensureListener(String reason) async {
    final pending = _initializing ??= _initialize(reason);
    try {
      await pending;
    } finally {
      if (identical(_initializing, pending)) _initializing = null;
    }
  }

  Future<void> _initialize(String reason) async {
    if (_isRunning) {
      final unavailable = await _diagnostics.probe(reason);
      if (_stopping != null) return;
      if (_isRunning) {
        if (unavailable) await _rebindListener(reason);
        return;
      }
    }

    await SMBService.instance.initialize();

    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getInt(_portKey);

    final portsToTry = <int>[];
    void addPort(int? value) {
      if (value == null) return;
      if (portsToTry.contains(value)) return;
      portsToTry.add(value);
    }

    addPort(savedPort);
    addPort(_defaultPort);
    addPort(0);

    final healthToken = RemoteProxyDiagnostics.newHealthToken();
    final receivePort = ReceivePort();
    final startCompleter = Completer<({int port, SendPort controlPort})>();
    startCompleter.future.ignore();

    _receivePort = receivePort;
    _receiveSubscription = receivePort.listen((message) {
      if (!identical(_receivePort, receivePort)) return;
      if (message == null) {
        if (!startCompleter.isCompleted) {
          startCompleter.completeError(
            StateError('SMBProxyService isolate exited before startup'),
          );
        }
        _handleUnexpectedIsolateExit();
        return;
      }
      if (message is! Map) return;
      final type = message['type'];
      if (type == 'started') {
        final startedPort = message['port'];
        final controlPort = message['controlPort'];
        if (startedPort is int &&
            controlPort is SendPort &&
            !startCompleter.isCompleted) {
          startCompleter.complete((port: startedPort, controlPort: controlPort));
        }
        return;
      }
      if (type == 'start_error') {
        if (!startCompleter.isCompleted) {
          startCompleter.completeError(
            StateError('SMBProxyService failed to start: ${message['error']}'),
          );
        }
        return;
      }
      if (type == 'ack') {
        final id = message['id'];
        if (id is int) {
          final completer = _pendingControl.remove(id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(message['result']);
          }
        }
        return;
      }
      if (type == 'resolve_password') {
        unawaited(_handleResolvePasswordRequest(message));
        return;
      }
      if (type == 'log') {
        final line = message['message'];
        if (line is String) debugPrint(line);
      }
    });

    try {
      final isolate = await Isolate.spawn<_SmbProxyStartupArgs>(
        _smbProxyIsolateMain,
        _SmbProxyStartupArgs(
          mainPort: receivePort.sendPort,
          portsToTry: portsToTry,
          healthToken: healthToken,
          initialConnections: _buildConnectionSnapshots(),
          useNativeSmb2: Smb2NativeService.instance.isSupported,
        ),
        onExit: receivePort.sendPort,
        debugName: 'SMBProxyServer',
      );

      _isolate = isolate;
      final started = await startCompleter.future;
      if (!identical(_receivePort, receivePort)) {
        throw StateError('SMBProxyService isolate exited during startup');
      }
      _port = started.port;
      _controlPort = started.controlPort;
      _isRunning = true;
      _diagnostics.attach(_port, healthToken: healthToken);

      final listener = _syncConnectionsSnapshot;
      _smbListener = listener;
      SMBService.instance.addConnectionListener(listener);

      _syncConnectionsSnapshot();
      await _savePort(prefs);
    } catch (e) {
      await _cleanupRootIsolateState(killIsolate: true);
      if (e is StateError) rethrow;
      throw StateError('SMBProxyService failed to start: $e');
    }
  }

  Future<void> _rebindListener(String reason) async {
    final previousPort = _port;
    final controlPort = _controlPort;
    _diagnostics.log('heal-start reason=$reason');
    _isRunning = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPort = prefs.getInt(_portKey);
      final result = await _sendControlWithAck({
        'op': 'rebind_listener',
        'ports': <int>{
          previousPort,
          if (savedPort != null && savedPort != 0) savedPort,
          _defaultPort,
          0
        }.toList(),
      }).timeout(_stopTimeout);
      if (result is! (int, String) || !identical(_controlPort, controlPort)) {
        throw StateError('SMBProxyService failed to rebind listener');
      }
      final (port, healthToken) = result;
      _port = port;
      _diagnostics.attach(port, healthToken: healthToken);
      _isRunning = _stopping == null;
      await _savePort(prefs);
      _diagnostics.log('heal-complete previousPort=$previousPort');
    } catch (error) {
      _diagnostics
          .log('heal-failed ${RemoteProxyDiagnostics.errorSummary(error)}');
      await _stopProxy();
      rethrow;
    }
  }

  Future<void> _savePort(SharedPreferences prefs) async {
    try {
      await prefs.setInt(_portKey, _port);
    } catch (error) {
      debugPrint('SMB proxy port preference could not be saved: $error');
    }
  }

  Future<void> stop() async {
    final activeStop = _stopping;
    if (activeStop != null) {
      await activeStop;
      return;
    }

    final future = _stopInternal();
    _stopping = future;
    try {
      await future;
    } finally {
      if (identical(_stopping, future)) _stopping = null;
    }
  }

  Future<void> _stopInternal() async {
    _diagnostics.log('stop-request running=$_isRunning');
    // Stop counting as running before the first await, so nothing prepares a
    // connection or builds a URL on a proxy that is going away.
    _isRunning = false;
    try {
      await _initializing;
    } catch (_) {}

    await _stopProxy();
    _diagnostics.log('stop-complete');
  }

  Future<void> _stopProxy() async {
    final controlPort = _controlPort;
    _isRunning = false;
    _port = 0;

    if (controlPort != null) {
      try {
        await _sendControlWithAck({'op': 'stop'}).timeout(_stopTimeout);
      } catch (_) {}
    }

    await _cleanupRootIsolateState(killIsolate: true);
  }

  Future<void> _cleanupRootIsolateState({required bool killIsolate}) async {
    final listener = _smbListener;
    if (listener != null) {
      SMBService.instance.removeConnectionListener(listener);
      _smbListener = null;
    }

    _controlPort = null;
    _isRunning = false;
    _port = 0;
    _diagnostics.detach();

    for (final completer in _pendingControl.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('SMBProxyService stopped'));
      }
    }
    _pendingControl.clear();

    final subscription = _receiveSubscription;
    _receiveSubscription = null;
    final receivePort = _receivePort;
    _receivePort = null;
    receivePort?.close();

    final isolate = _isolate;
    _isolate = null;
    if (killIsolate && isolate != null) {
      isolate.kill(priority: Isolate.immediate);
    }
    await subscription?.cancel();
  }

  void _handleUnexpectedIsolateExit() {
    if (_isolate == null && _receivePort == null) return;
    unawaited(_cleanupRootIsolateState(killIsolate: false));
  }

  /// Resolve [connection]'s password on the root isolate and wait until the
  /// proxy isolate has stored the updated snapshot.
  ///
  /// Calling this before passing an SMB stream URL to a player guarantees the
  /// proxy isolate never needs to call back to the root isolate while playing.
  Future<void> prepareConnection(SMBConnection connection) async {
    await connection.resolvePassword();
    if (!_isRunning || _controlPort == null) return;
    await _sendControlWithAck({
      'op': 'upsert_connection',
      'connection': _serializeConnection(connection),
    });
  }

  String buildStreamUrl(SMBConnection connection, String smbPath) {
    if (!_isRunning || _stopping != null) {
      throw StateError(
          'SMB proxy must be initialized before building a stream URL');
    }
    final fromService = SMBService.instance.getConnection(connection.name) ??
        SMBService.instance.getConnectionByIdOrName(connection.id);
    var normalizedConnection = fromService ?? connection;
    if (connection.passwordIsResolved &&
        !normalizedConnection.passwordIsResolved) {
      normalizedConnection = connection;
    }
    final connName = normalizedConnection.name.trim();
    final normalizedPath = _normalizeSmbPath(smbPath);

    _controlPort?.send({
      'op': 'upsert_connection',
      'connection': _serializeConnection(normalizedConnection),
    });
    if (!normalizedConnection.passwordIsResolved) {
      unawaited(prepareConnection(normalizedConnection).catchError((_) {}));
    }

    final resolvedPort = _port > 0 ? _port : _defaultPort;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: resolvedPort,
      path: '/smb/stream',
      queryParameters: {
        'conn': connName,
        'path': normalizedPath,
      },
    ).toString();
  }

  void _syncConnectionsSnapshot() {
    final controlPort = _controlPort;
    if (controlPort == null || _stopping != null) return;
    controlPort.send({
      'op': 'replace_connections',
      'connections': _buildConnectionSnapshots(),
    });
  }

  List<Map<String, Object?>> _buildConnectionSnapshots() {
    return SMBService.instance.connections
        .map(_serializeConnection)
        .toList(growable: false);
  }

  Map<String, Object?> _serializeConnection(SMBConnection raw) {
    final effective = SMBService.instance.effectiveConnection(raw);
    return <String, Object?>{
      'id': effective.id,
      'name': effective.name.trim(),
      'host': effective.host,
      'port': effective.port,
      'username': effective.username,
      'password': effective.passwordIsResolved ? effective.password : '',
      'passwordResolved': effective.passwordIsResolved,
      'domain': effective.domain,
    };
  }

  Future<Object?> _sendControlWithAck(Map<String, Object?> payload) {
    final controlPort = _controlPort;
    if (controlPort == null) {
      return Future<Object?>.value();
    }
    final id = _nextControlId++;
    final completer = Completer<Object?>();
    _pendingControl[id] = completer;
    controlPort.send(<String, Object?>{
      ...payload,
      'id': id,
    });
    return completer.future;
  }

  Future<void> _handleResolvePasswordRequest(Map<dynamic, dynamic> message) async {
    final requestId = message['id'];
    final connRef = message['conn']?.toString().trim() ?? '';
    final controlPort = _controlPort;
    if (requestId is! int || controlPort == null) return;

    try {
      final resolved = SMBService.instance.getConnection(connRef) ??
          SMBService.instance.getConnectionByIdOrName(connRef);
      if (resolved == null) {
        controlPort.send({
          'op': 'resolve_password_result',
          'id': requestId,
          'ok': false,
          'error': 'SMB connection not found',
        });
        return;
      }
      await resolved.resolvePassword();
      controlPort.send({
        'op': 'resolve_password_result',
        'id': requestId,
        'ok': true,
        'connection': _serializeConnection(resolved),
      });
    } catch (e) {
      controlPort.send({
        'op': 'resolve_password_result',
        'id': requestId,
        'ok': false,
        'error': e.toString(),
      });
    }
  }
}

class _SmbProxyStartupArgs {
  final SendPort mainPort;
  final List<int> portsToTry;
  final String healthToken;
  final List<Map<String, Object?>> initialConnections;
  final bool useNativeSmb2;

  const _SmbProxyStartupArgs({
    required this.mainPort,
    required this.portsToTry,
    required this.healthToken,
    required this.initialConnections,
    required this.useNativeSmb2,
  });
}

class _SmbProxyConnectionSnapshot {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool passwordResolved;
  final String domain;

  const _SmbProxyConnectionSnapshot({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.passwordResolved,
    required this.domain,
  });

  factory _SmbProxyConnectionSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final rawPort = map['port'];
    return _SmbProxyConnectionSnapshot(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString().trim(),
      host: (map['host'] ?? '').toString(),
      port: rawPort is int
          ? rawPort
          : int.tryParse(rawPort?.toString() ?? '') ?? 445,
      username: (map['username'] ?? '').toString(),
      password: (map['password'] ?? '').toString(),
      passwordResolved: map['passwordResolved'] == true,
      domain: (map['domain'] ?? '').toString(),
    );
  }

  _SmbProxyConnectionSnapshot withResolvedPassword(String resolvedPassword) {
    return _SmbProxyConnectionSnapshot(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: resolvedPassword,
      passwordResolved: true,
      domain: domain,
    );
  }

  SMBConnection toSmbConnection() {
    return SMBConnection(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: password,
      domain: domain,
    );
  }
}

void _smbProxyIsolateMain(_SmbProxyStartupArgs args) {
  // Only the root isolate's debugPrint reaches the app log; forward to it.
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      args.mainPort.send({'type': 'log', 'message': message});
    }
  };
  final state = _SmbProxyIsolateState(
    mainPort: args.mainPort,
    useNativeSmb2: args.useNativeSmb2,
  );
  state.replaceConnections(args.initialConnections);
  unawaited(state.start(args.portsToTry, args.healthToken));
}

class _SmbProxyIsolateState {
  _SmbProxyIsolateState({
    required this.mainPort,
    required this.useNativeSmb2,
  });

  final SendPort mainPort;
  final bool useNativeSmb2;
  final ReceivePort _controlPort = ReceivePort();
  final Map<String, _SmbProxyConnectionSnapshot> _byName =
      <String, _SmbProxyConnectionSnapshot>{};
  final Map<String, _SmbProxyConnectionSnapshot> _byId =
      <String, _SmbProxyConnectionSnapshot>{};
  final Map<int, Completer<_SmbProxyConnectionSnapshot>>
      _pendingPasswordResolves =
      <int, Completer<_SmbProxyConnectionSnapshot>>{};
  int _nextPasswordResolveId = 1;
  final _diagnostics = RemoteProxyDiagnostics('SMB');
  HttpServer? _server;
  bool _stopped = false;

  Future<void> start(List<int> portsToTry, String healthToken) async {
    _controlPort.listen((message) {
      if (message is! Map) return;
      unawaited(_handleControlMessage(message));
    });

    try {
      final port = await _bind(portsToTry, healthToken);
      mainPort.send({
        'type': 'started',
        'port': port,
        'controlPort': _controlPort.sendPort,
      });
    } catch (error) {
      _controlPort.close();
      mainPort.send({'type': 'start_error', 'error': error.toString()});
    }
  }

  Future<int> _bind(List<int> portsToTry, String healthToken) async {
    // Register HEAD explicitly before GET so shelf_router does not shadow it
    // with the synthetic body-stripping GET wrapper that forces Content-Length: 0.
    final router = Router()
      ..add('HEAD', '/smb/stream', _handleStreamHead)
      ..add('GET', '/smb/stream', _handleStream)
      ..get(
          '/smb/health',
          (Request request) => Response.ok('ok', headers: {
                RemoteProxyDiagnostics.healthHeader: healthToken,
              }));

    final handler = _diagnostics.wrap(const Pipeline().addHandler(router.call));

    Object? lastError;
    for (final candidatePort in portsToTry) {
      if (_stopped) throw StateError('SMBProxyService stopped during bind');
      try {
        _diagnostics.log('bind-attempt candidatePort=$candidatePort');
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidatePort,
        );
        if (_stopped) {
          await server.close(force: true);
          throw StateError('SMBProxyService stopped during bind');
        }
        _server = server;
        shelf_io.serveRequests(_diagnostics.observe(server), handler);
        return server.port;
      } catch (e) {
        _diagnostics.log(
            'bind-failed candidatePort=$candidatePort ${RemoteProxyDiagnostics.errorSummary(e)}');
        lastError = e;
      }
    }

    throw StateError('Unable to bind loopback port: $lastError');
  }

  Future<void> _handleControlMessage(Map<dynamic, dynamic> message) async {
    final op = message['op'];
    final id = message['id'];

    if (op == 'upsert_connection') {
      final raw = message['connection'];
      if (raw is Map) {
        upsertConnection(_SmbProxyConnectionSnapshot.fromMap(raw));
      }
      if (id is int) {
        mainPort.send({'type': 'ack', 'id': id});
      }
      return;
    }

    if (op == 'replace_connections') {
      final rawList = message['connections'];
      if (rawList is List) {
        replaceConnections(rawList);
      }
      if (id is int) {
        mainPort.send({'type': 'ack', 'id': id});
      }
      return;
    }

    if (op == 'resolve_password_result') {
      if (id is! int) return;
      final completer = _pendingPasswordResolves.remove(id);
      if (completer == null || completer.isCompleted) return;
      if (message['ok'] == true && message['connection'] is Map) {
        final snapshot = _SmbProxyConnectionSnapshot.fromMap(
          message['connection'] as Map,
        );
        upsertConnection(snapshot);
        completer.complete(snapshot);
      } else {
        completer.completeError(
          StateError(message['error']?.toString() ?? 'Credential lookup failed'),
        );
      }
      return;
    }

    if (op == 'rebind_listener' && id is int) {
      (int, String)? result;
      try {
        await _server?.close(force: true);
        _server = null;
        final healthToken = RemoteProxyDiagnostics.newHealthToken();
        final port = await _bind(message['ports'] as List<int>, healthToken);
        result = (port, healthToken);
      } catch (error) {
        _diagnostics
            .log('rebind-failed ${RemoteProxyDiagnostics.errorSummary(error)}');
      }
      mainPort.send({'type': 'ack', 'id': id, 'result': result});
      return;
    }

    if (op == 'test_close_listener' && id is int) {
      await _server?.close(force: true);
      mainPort.send({'type': 'ack', 'id': id});
      return;
    }

    if (op == 'stop') {
      await _shutdown();
      if (id is int) {
        mainPort.send({'type': 'ack', 'id': id});
      }
      _controlPort.close();
    }
  }

  Future<void> _shutdown() async {
    if (_stopped) return;
    _stopped = true;
    for (final completer in _pendingPasswordResolves.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('SMBProxyService stopped'));
      }
    }
    _pendingPasswordResolves.clear();
    await _server?.close(force: true);
    _server = null;
    if (useNativeSmb2) {
      // Dispose the proxy isolate's own Smb2NativeService worker isolate.
      Smb2NativeService.instance.dispose();
    }
  }

  void replaceConnections(List<dynamic> rawList) {
    final nextByName = <String, _SmbProxyConnectionSnapshot>{};
    final nextById = <String, _SmbProxyConnectionSnapshot>{};
    for (final entry in rawList) {
      if (entry is! Map) continue;
      var snapshot = _SmbProxyConnectionSnapshot.fromMap(entry);
      final existing =
          _byId[snapshot.id] ?? _byName[snapshot.name];
      if (!snapshot.passwordResolved &&
          existing != null &&
          existing.id == snapshot.id &&
          existing.username == snapshot.username &&
          existing.passwordResolved) {
        snapshot = snapshot.withResolvedPassword(existing.password);
      }
      if (snapshot.name.isNotEmpty) {
        nextByName[snapshot.name] = snapshot;
      }
      if (snapshot.id.isNotEmpty) {
        nextById[snapshot.id] = snapshot;
      }
    }
    _byName
      ..clear()
      ..addAll(nextByName);
    _byId
      ..clear()
      ..addAll(nextById);
  }

  void upsertConnection(_SmbProxyConnectionSnapshot snapshot) {
    if (snapshot.id.isNotEmpty) {
      final previous = _byId[snapshot.id];
      if (previous != null &&
          previous.name.isNotEmpty &&
          previous.name != snapshot.name) {
        _byName.remove(previous.name);
      }
      _byId[snapshot.id] = snapshot;
    }
    if (snapshot.name.isNotEmpty) {
      _byName[snapshot.name] = snapshot;
    }
  }

  _SmbProxyConnectionSnapshot? _findConnection(String connName) {
    return _byName[connName] ?? _byId[connName];
  }

  Future<_SmbProxyConnectionSnapshot> _ensureCredentials(
    _SmbProxyConnectionSnapshot snapshot,
  ) async {
    if (snapshot.passwordResolved) {
      return snapshot;
    }
    final reqId = _nextPasswordResolveId++;
    final completer = Completer<_SmbProxyConnectionSnapshot>();
    _pendingPasswordResolves[reqId] = completer;
    mainPort.send({
      'type': 'resolve_password',
      'id': reqId,
      'conn': snapshot.name.isNotEmpty ? snapshot.name : snapshot.id,
    });
    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      _pendingPasswordResolves.remove(reqId);
    }
  }

  Future<Response> _handleStream(Request request) {
    return _handleStreamInternal(request, headOnly: false);
  }

  Future<Response> _handleStreamHead(Request request) {
    return _handleStreamInternal(request, headOnly: true);
  }

  Future<Response> _handleStreamInternal(
    Request request, {
    required bool headOnly,
  }) async {
    final connName = request.url.queryParameters['conn']?.trim();
    final rawPath = request.url.queryParameters['path']?.trim();
    if (connName == null ||
        connName.isEmpty ||
        rawPath == null ||
        rawPath.isEmpty) {
      return Response(HttpStatus.badRequest, body: 'Missing conn or path');
    }

    final snapshot = _findConnection(connName);
    if (snapshot == null) {
      return Response(HttpStatus.notFound, body: 'SMB connection not found');
    }

    final _SmbProxyConnectionSnapshot resolvedSnapshot;
    try {
      resolvedSnapshot = await _ensureCredentials(snapshot);
    } on TimeoutException {
      return Response(
        HttpStatus.serviceUnavailable,
        body: 'SMB credentials resolution timed out',
      );
    } catch (e) {
      return Response.internalServerError(body: 'SMB credential error: $e');
    }

    final connection = resolvedSnapshot.toSmbConnection();
    final smbPath = _stripTrailingSlash(_normalizeSmbPath(rawPath));

    if (useNativeSmb2) {
      try {
        // Smb2NativeService.instance is per-isolate: this spawns and uses a
        // worker isolate and FFI contexts owned solely by the proxy isolate.
        final stat = await Smb2NativeService.instance.stat(connection, smbPath);
        if (stat.isDirectory) {
          return Response(HttpStatus.badRequest, body: 'Path is a directory');
        }

        final totalLength = stat.size;
        final contentType = _determineContentType(p.basename(smbPath));

        final rangeHeader = request.headers['range'];
        if (rangeHeader != null) {
          final range = _parseRangeHeader(rangeHeader, totalLength);
          if (range == null) {
            return Response(
              HttpStatus.requestedRangeNotSatisfiable,
              headers: {
                'Content-Range': 'bytes */$totalLength',
              },
            );
          }

          final start = range.start;
          final endExclusive = range.endExclusive;
          final endInclusive = endExclusive - 1;
          final chunkSize = endExclusive - start;

          final headers = <String, String>{
            'Content-Type': contentType,
            'Content-Length': '$chunkSize',
            'Accept-Ranges': 'bytes',
            'Content-Range': 'bytes $start-$endInclusive/$totalLength',
            'Cache-Control': 'no-cache',
          };

          if (headOnly) {
            return Response(HttpStatus.partialContent, headers: headers);
          }

          final stream = Smb2NativeService.instance.openReadStream(
            connection,
            smbPath,
            start: start,
            endExclusive: endExclusive,
          );

          return Response(
            HttpStatus.partialContent,
            body: stream,
            headers: headers,
          );
        }

        final headers = <String, String>{
          'Content-Type': contentType,
          'Content-Length': '$totalLength',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
        };

        if (headOnly) {
          return Response(HttpStatus.ok, headers: headers);
        }

        final stream = Smb2NativeService.instance.openReadStream(
          connection,
          smbPath,
          start: 0,
          endExclusive: totalLength,
        );

        return Response.ok(
          stream,
          headers: headers,
        );
      } catch (e) {
        _diagnostics
            .log('upstream-error ${RemoteProxyDiagnostics.errorSummary(e)}');
        return Response.internalServerError(body: 'SMB stream error: $e');
      }
    }

    SmbConnect? client;
    try {
      client = await SmbConnect.connectAuth(
        host: connection.host,
        username: connection.username,
        password: connection.password,
        domain: connection.domain,
        debugPrint: false,
      );

      final smbFile = await client.file(smbPath);
      if (!smbFile.isExists) {
        await client.close();
        return Response.notFound('File not found');
      }
      if (smbFile.isDirectory()) {
        await client.close();
        return Response(HttpStatus.badRequest, body: 'Path is a directory');
      }

      final totalLength = smbFile.size;
      final contentType = _determineContentType(smbFile.name);

      final rangeHeader = request.headers['range'];
      if (rangeHeader != null) {
        final range = _parseRangeHeader(rangeHeader, totalLength);
        if (range == null) {
          await client.close();
          return Response(
            HttpStatus.requestedRangeNotSatisfiable,
            headers: {
              'Content-Range': 'bytes */$totalLength',
            },
          );
        }

        final start = range.start;
        final endExclusive = range.endExclusive;
        final endInclusive = endExclusive - 1;
        final chunkSize = endExclusive - start;

        final headers = <String, String>{
          'Content-Type': contentType,
          'Content-Length': '$chunkSize',
          'Accept-Ranges': 'bytes',
          'Content-Range': 'bytes $start-$endInclusive/$totalLength',
          'Cache-Control': 'no-cache',
        };

        if (headOnly) {
          await client.close();
          return Response(HttpStatus.partialContent, headers: headers);
        }

        final smbStream = await client.openRead(smbFile, start, endExclusive);
        final stream = _wrapStreamAndCloseClient(client, smbStream);
        client = null;

        return Response(
          HttpStatus.partialContent,
          body: stream,
          headers: headers,
        );
      }

      final headers = <String, String>{
        'Content-Type': contentType,
        'Content-Length': '$totalLength',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      };

      if (headOnly) {
        await client.close();
        return Response(HttpStatus.ok, headers: headers);
      }

      final smbStream = await client.openRead(smbFile);
      final stream = _wrapStreamAndCloseClient(client, smbStream);
      client = null;

      return Response.ok(
        stream,
        headers: headers,
      );
    } catch (e) {
      _diagnostics
          .log('upstream-error ${RemoteProxyDiagnostics.errorSummary(e)}');
      return Response.internalServerError(body: 'SMB stream error: $e');
    } finally {
      if (client != null) {
        try {
          await client.close();
        } catch (_) {
          // ignore
        }
      }
    }
  }

  Stream<List<int>> _wrapStreamAndCloseClient(
    SmbConnect client,
    Stream<Uint8List> smbStream,
  ) async* {
    try {
      await for (final chunk in smbStream) {
        yield chunk;
      }
    } finally {
      try {
        await client.close();
      } catch (_) {
        // ignore
      }
    }
  }
}

String _normalizeSmbPath(String rawPath) {
  if (rawPath.isEmpty) {
    return '/';
  }
  var normalized = rawPath.replaceAll('\\', '/');
  if (!normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  normalized = normalized.replaceAll(RegExp(r'/{2,}'), '/');
  return normalized;
}

String _stripTrailingSlash(String value) {
  if (value.length <= 1) {
    return value;
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String _determineContentType(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  switch (ext) {
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mkv':
      return 'video/x-matroska';
    case '.mov':
      return 'video/quicktime';
    case '.avi':
      return 'video/x-msvideo';
    case '.flv':
      return 'video/x-flv';
    case '.ts':
    case '.mpeg':
    case '.mpg':
      return 'video/mpeg';
    case '.webm':
      return 'video/webm';
    default:
      return 'application/octet-stream';
  }
}

_HttpRange? _parseRangeHeader(String rangeHeader, int totalLength) {
  if (totalLength <= 0) {
    return null;
  }
  if (!rangeHeader.startsWith('bytes=')) {
    return null;
  }

  final rangeSpec = rangeHeader.substring('bytes='.length);
  final firstRange = rangeSpec.split(',').first.trim();
  final match = RegExp(r'^(\d*)-(\d*)$').firstMatch(firstRange);
  if (match == null) {
    return null;
  }

  final startStr = match.group(1) ?? '';
  final endStr = match.group(2) ?? '';
  if (startStr.isEmpty && endStr.isEmpty) {
    return null;
  }

  int start;
  int endInclusive;

  if (startStr.isEmpty) {
    final suffixLength = int.tryParse(endStr);
    if (suffixLength == null || suffixLength <= 0) {
      return null;
    }
    if (suffixLength >= totalLength) {
      start = 0;
    } else {
      start = totalLength - suffixLength;
    }
    endInclusive = totalLength - 1;
  } else {
    start = int.tryParse(startStr) ?? -1;
    if (start < 0 || start >= totalLength) {
      return null;
    }

    if (endStr.isEmpty) {
      endInclusive = totalLength - 1;
    } else {
      endInclusive = int.tryParse(endStr) ?? -1;
      if (endInclusive < start) {
        return null;
      }
      if (endInclusive >= totalLength) {
        endInclusive = totalLength - 1;
      }
    }
  }

  final endExclusive = endInclusive + 1;
  return _HttpRange(start: start, endExclusive: endExclusive);
}

class _HttpRange {
  final int start;
  final int endExclusive;

  const _HttpRange({
    required this.start,
    required this.endExclusive,
  });
}
