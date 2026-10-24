import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import '../platform/lab_profile.dart';
import 'bonjour.dart';
import 'system_bonjour.dart';

typedef NetworkInterfaceSnapshot = ({
  String name,
  List<InternetAddress> addresses,
});

final _virtualInterfacePattern = RegExp(
  r'^(docker|br-|veth|virbr|lxcbr|cni|flannel|cali|podman|nerdctl|colima|'
  r'utun|tun|tap|wg|tailscale|zt|gif|stf|awdl|llw|anpi|ipsec|ppp|vmnet|vboxnet|lo)'
  r'|vethernet|wsl|hyper-v|docker',
  caseSensitive: false,
);

/// Returns true when [name] is a virtual, tunnel, bridge, or container adapter
/// that should not be advertised as a LAN address candidate.
bool isVirtualNetworkInterface(String name) =>
    _virtualInterfacePattern.hasMatch(name.trim());

/// Returns true when [address] is a non-loopback, non-link-local, non-multicast
/// unicast address suitable for LAN candidate advertisement.
bool isUsableLanAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && raw.length == 4) {
    if (raw[0] == 0 || raw[0] == 127) return false;
    if (raw[0] == 169 && raw[1] == 254) return false;
    if (raw[0] == 255 && raw[1] == 255 && raw[2] == 255 && raw[3] == 255) {
      return false;
    }
  }
  if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
    final allZero = raw.every((b) => b == 0);
    if (allZero) return false;
  }
  return true;
}

bool _isPrivateIpv4(List<int> raw) {
  if (raw.length != 4) return false;
  if (raw[0] == 10) return true;
  if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return true;
  if (raw[0] == 192 && raw[1] == 168) return true;
  return false;
}

/// Computes subnet affinity between [candidateHost] and [localHosts].
/// Positive when [candidateHost] shares a /24 or /16 (or IPv6 /64) with a local
/// interface; negative when [candidateHost] is a private LAN IP on a completely
/// unrelated subnet.
int subnetAffinityScore(String candidateHost, Iterable<String> localHosts) {
  final candidate = InternetAddress.tryParse(candidateHost);
  if (candidate == null) return 0;
  if (candidate.isLoopback) return 600;
  final cRaw = candidate.rawAddress;

  if (candidate.type == InternetAddressType.IPv4 && cRaw.length == 4) {
    var best = 0;
    for (final host in localHosts) {
      final local = InternetAddress.tryParse(host);
      if (local == null || local.type != InternetAddressType.IPv4) continue;
      final lRaw = local.rawAddress;
      if (lRaw.length != 4) continue;
      if (cRaw[0] == lRaw[0] && cRaw[1] == lRaw[1] && cRaw[2] == lRaw[2]) {
        if (500 > best) best = 500;
      } else if (cRaw[0] == lRaw[0] && cRaw[1] == lRaw[1]) {
        if (300 > best) best = 300;
      } else if (_isPrivateIpv4(cRaw) &&
          _isPrivateIpv4(lRaw) &&
          cRaw[0] == lRaw[0]) {
        if (150 > best) best = 150;
      }
    }
    if (best > 0) return best;
    if (_isPrivateIpv4(cRaw) && localHosts.isNotEmpty) {
      return -60;
    }
    return 0;
  }

  if (candidate.type == InternetAddressType.IPv6 && cRaw.length == 16) {
    var best = 0;
    for (final host in localHosts) {
      final local = InternetAddress.tryParse(host);
      if (local == null || local.type != InternetAddressType.IPv6) continue;
      final lRaw = local.rawAddress;
      if (lRaw.length != 16) continue;
      var same64 = true;
      for (var i = 0; i < 8; i++) {
        if (cRaw[i] != lRaw[i]) {
          same64 = false;
          break;
        }
      }
      if (same64) {
        if (500 > best) best = 500;
      } else if (cRaw[0] == lRaw[0] && cRaw[1] == lRaw[1]) {
        if (200 > best) best = 200;
      }
    }
    return best;
  }

  return 0;
}

/// Orders and deduplicates candidate routes:
/// 1. Remembered last-working route (priority >= 1000)
/// 2. Discovery hints and same-subnet LAN candidates
/// 3. Manual / public / overlay candidates
/// 4. Unrelated-subnet private LAN candidates
List<JsonMap> rankMeshCandidates(
  Iterable<JsonMap> candidates, {
  Iterable<String> localHosts = const [],
}) {
  final hostList = localHosts.toList(growable: false);
  final scored = <({JsonMap candidate, int score, int index})>[];
  var index = 0;
  for (final raw in candidates) {
    final host = raw['host'];
    final port = raw['port'];
    if (host is! String ||
        host.isEmpty ||
        port is! int ||
        port < 1 ||
        port > 65535) {
      continue;
    }
    final basePriority = (raw['priority'] as int?) ?? 0;
    final affinity = subnetAffinityScore(host, hostList);
    final score = basePriority >= 1000
        ? basePriority * 10 + (affinity > 0 ? affinity : 0)
        : basePriority + affinity;
    scored.add((candidate: raw, score: score, index: index++));
  }
  scored.sort((a, b) {
    final cmp = b.score.compareTo(a.score);
    return cmp != 0 ? cmp : a.index.compareTo(b.index);
  });
  final seen = <String>{};
  final result = <JsonMap>[];
  for (final item in scored) {
    final key = '${item.candidate['host']}:${item.candidate['port']}';
    if (seen.add(key)) {
      result.add(item.candidate);
    }
  }
  return result;
}

final class MeshDiscovery {
  MeshDiscovery(
    this.deviceId,
    this.port, {
    Future<List<NetworkInterfaceSnapshot>> Function()? interfaces,
    this.onPeerHint,
    this.enableBonjour = true,
    this.bonjourPort = MeshBonjour.defaultMdnsPort,
    this.allowInLabProfile = false,
  }) : _interfaces = interfaces;

  final String deviceId;
  final int port;
  final Future<List<NetworkInterfaceSnapshot>> Function()? _interfaces;
  final void Function(String peerDeviceId)? onPeerHint;
  final bool enableBonjour;
  final int bonjourPort;
  final bool allowInLabProfile;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _broadcast;
  MeshBonjour? _bonjour;
  SystemBonjour? _systemBonjour;
  final _hints = <String, List<({JsonMap address, DateTime expires})>>{};
  static const discoveryPort = 32124;

  static Future<List<NetworkInterfaceSnapshot>> _systemInterfaces() async => [
        for (final interface in await NetworkInterface.list())
          (name: interface.name, addresses: interface.addresses),
      ];

  Future<List<InternetAddress>> localLanAddresses() async {
    final interfaces = await (_interfaces?.call() ?? _systemInterfaces());
    final seen = <String>{};
    return [
      for (final interface in interfaces)
        if (!isVirtualNetworkInterface(interface.name))
          for (final address in interface.addresses)
            if (isUsableLanAddress(address) && seen.add(address.address))
              address,
    ];
  }

  Future<List<JsonMap>> localCandidates() async => [
        for (final address in await localLanAddresses())
          {
            'kind': 'lan',
            'host': address.address,
            'port': port,
            'priority': 100,
            'expires_in': 3600,
          },
      ];

  void recordHint(
    String peer,
    String host,
    int peerPort, {
    Duration ttl = const Duration(seconds: 90),
    int priority = 200,
    String source = 'lan',
  }) {
    if (peer == deviceId || host.isEmpty || peerPort < 1 || peerPort > 65535) {
      return;
    }
    // A link-local address (fe80::, 169.254/16) has no meaning without the
    // interface it was heard on, so it cannot be dialled from here.
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null && parsed.isLinkLocal) return;
    final now = DateTime.now();
    final list = _hints[peer] ??= <({JsonMap address, DateTime expires})>[];
    list.removeWhere(
      (entry) =>
          entry.expires.isBefore(now) ||
          (entry.address['host'] == host && entry.address['port'] == peerPort),
    );
    if (ttl <= Duration.zero) {
      if (list.isEmpty) _hints.remove(peer);
      return;
    }
    list.insert(0, (
      address: {
        'kind': 'lan',
        'host': host,
        'port': peerPort,
        'priority': priority,
        'source': source,
      },
      expires: now.add(ttl),
    ));
    onPeerHint?.call(peer);
  }

  List<JsonMap> hints(String peer) {
    final now = DateTime.now();
    final list = _hints[peer];
    if (list == null) return [];
    list.removeWhere((entry) => entry.expires.isBefore(now));
    if (list.isEmpty) {
      _hints.remove(peer);
      return [];
    }
    return [for (final entry in list) entry.address];
  }

  Future<void> start() async {
    if (LabProfile.active && !allowInLabProfile) return;
    if (SystemBonjour.available) {
      // The system's Bonjour alone: no hand-written mDNS and no UDP
      // broadcast (the latter needs a multicast entitlement Apple grants on
      // request, and it fails with exceptions where it is not granted).
      final system = _systemBonjour = SystemBonjour(
        deviceId: deviceId,
        port: port,
        onPeerDiscovered: (peer, host, peerPort, ttlSeconds) {
          recordHint(
            peer,
            host,
            peerPort,
            ttl: Duration(seconds: ttlSeconds),
            priority: 220,
            source: 'bonjour',
          );
        },
      );
      await system.start();
      return;
    }
    if (enableBonjour) {
      MeshBonjour.isVirtualInterface = isVirtualNetworkInterface;
      _bonjour = MeshBonjour(
        deviceId: deviceId,
        port: port,
        localAddresses: localLanAddresses,
        mdnsPort: bonjourPort,
        allowInLabProfile: allowInLabProfile,
        onPeerDiscovered: (peer, host, peerPort, ttlSeconds) {
          recordHint(
            peer,
            host,
            peerPort,
            ttl: Duration(seconds: ttlSeconds),
            priority: 220,
            source: 'bonjour',
          );
        },
      );
      await _bonjour!.start();
    }
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
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
        recordHint(
          json['deviceId'] as String,
          datagram.address.address,
          json['port'] as int,
          ttl: const Duration(seconds: 90),
          priority: 200,
          source: 'udp',
        );
      } on FormatException {
        // Untrusted UDP packets are hints; malformed packets carry no identity.
      }
    });
    void announce() {
      try {
        socket.send(
          utf8.encode(
              jsonEncode({'mesh': 1, 'deviceId': deviceId, 'port': port})),
          InternetAddress('255.255.255.255'),
          discoveryPort,
        );
      } on SocketException {
        // Ignore transient network errors when no broadcast route is present.
      }
    }

    announce();
    _broadcast = Timer.periodic(const Duration(seconds: 30), (_) => announce());
  }

  Future<void> close() async {
    _broadcast?.cancel();
    _broadcast = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    await _bonjour?.close();
    _bonjour = null;
    await _systemBonjour?.close();
    _systemBonjour = null;
  }
}
