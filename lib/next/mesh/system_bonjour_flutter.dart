import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// The system's Bonjour (NetService, through a platform channel) on iOS. The
/// system answers and browses for `_nipaplay-mesh._tcp`, needs no multicast
/// entitlement, and is what the local network permission is asked for.
///
/// It speaks the same service as bonjour.dart: the instance is named by the
/// device id and carries `mesh=1`, `deviceId` and `port` in its TXT record,
/// so a desktop and an iPad find each other.
final class SystemBonjour {
  SystemBonjour({
    required this.deviceId,
    required this.port,
    required this.onPeerDiscovered,
  });

  static const _channel = MethodChannel('nipaplay/mesh_bonjour');

  static bool get available => Platform.isIOS;

  final String deviceId;
  final int port;
  final void Function(String deviceId, String host, int port, int ttlSeconds)
      onPeerDiscovered;
  bool _started = false;

  static final _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_onCall);
    try {
      await _channel.invokeMethod<void>('start', {
        'deviceId': deviceId,
        'port': port,
        'serviceType': '_nipaplay-mesh._tcp.',
      });
    } on PlatformException {
      // Discovery only adds hints: the coordinator's addresses remain.
      _started = false;
      _channel.setMethodCallHandler(null);
      rethrow;
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'peer' || call.arguments is! Map) return null;
    final args = call.arguments as Map;
    final peer = args['deviceId'];
    final host = args['host'];
    final peerPort = args['port'];
    final ttl = args['ttl'];
    if (peer is! String ||
        peer == deviceId ||
        !_deviceIdPattern.hasMatch(peer) ||
        host is! String ||
        peerPort is! int ||
        ttl is! int) {
      return null;
    }
    onPeerDiscovered(peer, host, peerPort, ttl);
    return null;
  }

  Future<void> close() async {
    if (!_started) return;
    _started = false;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Closing must finish.
    } on MissingPluginException {
      // No bridge in this build.
    }
  }
}
