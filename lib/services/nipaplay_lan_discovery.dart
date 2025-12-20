import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const int nipaplayLanDiscoveryPort = 32123;

class NipaPlayLanDiscoveredServer {
  const NipaPlayLanDiscoveredServer({
    required this.ip,
    required this.port,
    this.hostname,
  });

  final String ip;
  final int port;
  final String? hostname;

  String get baseUrl => 'http://$ip:$port';
}

class NipaPlayLanDiscoveryProtocol {
  static const int protocolVersion = 1;

  static const String requestType = 'nipaplay_discover';
  static const String responseType = 'nipaplay_discover_response';

  static Uint8List buildRequestBytes() {
    return Uint8List.fromList(utf8.encode(json.encode(<String, dynamic>{
      'type': requestType,
      'v': protocolVersion,
    })));
  }

  static Uint8List buildResponseBytes({required int webPort}) {
    return Uint8List.fromList(utf8.encode(json.encode(<String, dynamic>{
      'type': responseType,
      'v': protocolVersion,
      'app': 'NipaPlay',
      'hostname': Platform.localHostname,
      'os': Platform.operatingSystem,
      'port': webPort,
    })));
  }

  static bool isValidRequestPayload(Map<String, dynamic> payload) {
    return payload['type'] == requestType && payload['v'] == protocolVersion;
  }

  static NipaPlayLanDiscoveredServer? tryParseResponse(Datagram datagram) {
    final payload = _tryDecodeJson(datagram.data);
    if (payload == null) return null;
    if (payload['type'] != responseType) return null;
    if (payload['v'] != protocolVersion) return null;
    if (payload['app'] != 'NipaPlay') return null;

    final rawPort = payload['port'];
    final port = rawPort is int ? rawPort : int.tryParse(rawPort?.toString() ?? '');
    if (port == null || port <= 0 || port > 65535) return null;

    final hostname = payload['hostname'] is String ? payload['hostname'] as String : null;
    return NipaPlayLanDiscoveredServer(
      ip: datagram.address.address,
      port: port,
      hostname: hostname,
    );
  }

  static Map<String, dynamic>? _tryDecodeJson(Uint8List data) {
    try {
      final decoded = json.decode(utf8.decode(data));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class NipaPlayLanDiscoveryResponder {
  RawDatagramSocket? _socket;
  int _webPort = 1180;

  bool get isRunning => _socket != null;

  Future<void> start({required int webPort}) async {
    _webPort = webPort;
    if (_socket != null) {
      return;
    }

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        nipaplayLanDiscoveryPort,
        reuseAddress: true,
      );

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final payload = _tryDecodeJson(datagram!.data);
          if (payload == null) continue;
          if (!NipaPlayLanDiscoveryProtocol.isValidRequestPayload(payload)) continue;

          final response = NipaPlayLanDiscoveryProtocol.buildResponseBytes(webPort: _webPort);
          try {
            socket.send(response, datagram.address, datagram.port);
          } catch (_) {
            // ignore send failures
          }
        }
      });

      _socket = socket;
      debugPrint('NipaPlayLanDiscoveryResponder: started on UDP $nipaplayLanDiscoveryPort');
    } catch (e) {
      debugPrint('NipaPlayLanDiscoveryResponder: start failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      _socket?.close();
    } catch (_) {
      // ignore
    } finally {
      _socket = null;
    }
  }

  static Map<String, dynamic>? _tryDecodeJson(Uint8List data) {
    try {
      final decoded = json.decode(utf8.decode(data));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
