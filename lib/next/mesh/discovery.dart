import 'dart:async';
import '../platform/lab_profile.dart';
import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';

final class MeshDiscovery {
  MeshDiscovery(this.deviceId, this.port);
  final String deviceId;
  final int port;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _broadcast;
  final _hints = <String, ({JsonMap address, DateTime expires})>{};
  static const discoveryPort = 32124;

  Future<List<JsonMap>> localCandidates() async => [
        for (final interface in await NetworkInterface.list())
          for (final address in interface.addresses)
            if (!address.isLoopback && !address.isLinkLocal)
              {
                'kind': 'lan',
                'host': address.address,
                'port': port,
                'priority': 100,
                'expires_in': 3600
              },
      ];
  List<JsonMap> hints(String peer) {
    _hints.removeWhere((_, entry) => entry.expires.isBefore(DateTime.now()));
    final hint = _hints[peer];
    return hint == null ? [] : [hint.address];
  }

  Future<void> start() async {
    if (LabProfile.active) return;
    final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, discoveryPort,
        reuseAddress: true);
    socket.broadcastEnabled = true;
    _socket = socket;
    _subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || datagram.data.length > 1024) return;
      try {
        final json = jsonDecode(utf8.decode(datagram.data));
        if (json is! Map ||
            json['mesh'] != 1 ||
            json['deviceId'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$')
                .hasMatch(json['deviceId'] as String) ||
            json['port'] is! int ||
            (json['port'] as int) < 1 ||
            (json['port'] as int) > 65535 ||
            json['deviceId'] == deviceId) {
          return;
        }
        _hints[json['deviceId'] as String] = (
          address: {
            'kind': 'lan',
            'host': datagram.address.address,
            'port': json['port'],
            'priority': 200
          },
          expires: DateTime.now().add(const Duration(seconds: 90))
        );
      } on FormatException {
        // Untrusted UDP packets are hints; malformed packets carry no identity.
      }
    });
    void announce() => socket.send(
        utf8.encode(
            jsonEncode({'mesh': 1, 'deviceId': deviceId, 'port': port})),
        InternetAddress('255.255.255.255'),
        discoveryPort);
    announce();
    _broadcast = Timer.periodic(const Duration(seconds: 30), (_) => announce());
  }

  Future<void> close() async {
    _broadcast?.cancel();
    await _subscription?.cancel();
    _socket?.close();
  }
}
