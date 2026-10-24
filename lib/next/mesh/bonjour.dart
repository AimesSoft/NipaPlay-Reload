import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../platform/lab_profile.dart';

final class BonjourPeerAnnouncement {
  const BonjourPeerAnnouncement({
    required this.deviceId,
    required this.port,
    required this.hosts,
    required this.ttlSeconds,
  });

  final String deviceId;
  final int port;
  final List<String> hosts;
  final int ttlSeconds;
}

final class DecodedBonjourPacket {
  const DecodedBonjourPacket({
    required this.isQueryForService,
    required this.announcements,
  });

  final bool isQueryForService;
  final List<BonjourPeerAnnouncement> announcements;
}

/// DNS-SD / mDNS (_nipaplay-mesh._tcp.local.) responder and browser for desktop
/// and headless hosts. One code path everywhere: it shares UDP 5353 with the
/// system responder (mDNSResponder, avahi) through SO_REUSEPORT and needs no
/// helper process, so there is nothing to orphan when the app is killed and no
/// second owner of the same service name for the system responder to rename.
final class MeshBonjour {
  MeshBonjour({
    required this.deviceId,
    required this.port,
    required this.localAddresses,
    required this.onPeerDiscovered,
    this.mdnsPort = defaultMdnsPort,
    InternetAddress? multicastAddress,
    this.allowInLabProfile = false,
  }) : multicastAddress = multicastAddress ?? InternetAddress(defaultMdnsGroup);

  static const String serviceType = '_nipaplay-mesh._tcp';
  static const String serviceDomain = '_nipaplay-mesh._tcp.local';
  static const String defaultMdnsGroup = '224.0.0.251';
  static const int defaultMdnsPort = 5353;

  static const int _typeA = 1;
  static const int _typePtr = 12;
  static const int _typeTxt = 16;
  static const int _typeAaaa = 28;
  static const int _typeSrv = 33;
  static const int _typeAny = 255;
  static const int _classIn = 1;
  static const int _classInFlush = 0x8001;

  final String deviceId;
  final int port;
  final Future<List<InternetAddress>> Function() localAddresses;
  final void Function(String deviceId, String host, int port, int ttlSeconds)
      onPeerDiscovered;
  final int mdnsPort;
  final InternetAddress multicastAddress;
  final bool allowInLabProfile;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _timer;
  DateTime _lastMulticastAnswer = DateTime.fromMillisecondsSinceEpoch(0);
  bool _closed = false;

  int get boundPort => _socket?.port ?? 0;

  Future<void> start() async {
    if (LabProfile.active && !allowInLabProfile) return;
    _closed = false;
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        mdnsPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    } on SocketException {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          mdnsPort,
          reuseAddress: true,
        );
      } on SocketException {
        return;
      }
    }
    if (_closed) {
      socket.close();
      return;
    }
    _socket = socket;
    try {
      socket.multicastLoopback = true;
    } on SocketException {
      // Loopback delivery is a nicety (same-host instances), not a need.
    }
    if (multicastAddress.rawAddress[0] >= 224 &&
        multicastAddress.rawAddress[0] <= 239) {
      await _joinGroup(socket);
    }
    _subscription = socket.listen(_onSocketEvent);
    await announce();
    sendQuery();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(announce());
    });
  }

  /// Joins the group on the default interface and on every non-virtual
  /// interface that has an IPv4 address, so a multi-homed host hears peers on
  /// all its real networks. Interfaces that refuse are skipped.
  Future<void> _joinGroup(RawDatagramSocket socket) async {
    try {
      socket.joinMulticast(multicastAddress);
    } on SocketException {
      // Isolated or loopback-only hosts have no default multicast interface.
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        if (isVirtualInterface(interface.name)) continue;
        try {
          socket.joinMulticast(multicastAddress, interface);
        } on SocketException {
          // Already joined through the default interface, or not multicast.
        }
      }
    } on SocketException {
      // Interface listing can fail in sandboxes; the default join stands.
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) break;
      if (datagram.data.isEmpty || datagram.data.length > 9000) continue;
      final decoded = decodePacket(
        datagram.data,
        sender: datagram.address,
        ownHostName: '$deviceId.local',
      );
      if (decoded == null) continue;
      if (decoded.isQueryForService) {
        if (datagram.port == defaultMdnsPort || datagram.port == mdnsPort) {
          // A real mDNS querier listens on the group: answer once per second
          // at most, however many peers ask at the same time.
          final now = DateTime.now();
          if (now.difference(_lastMulticastAnswer) >=
              const Duration(seconds: 1)) {
            _lastMulticastAnswer = now;
            unawaited(announce());
          }
        } else {
          // Legacy one-shot resolvers query from an ephemeral port and expect
          // the answer back there.
          unawaited(announce(
              targetAddress: datagram.address, targetPort: datagram.port));
        }
      }
      for (final item in decoded.announcements) {
        if (item.deviceId == deviceId) continue;
        for (final host in item.hosts) {
          onPeerDiscovered(item.deviceId, host, item.port, item.ttlSeconds);
        }
      }
    }
  }

  void sendQuery({InternetAddress? targetAddress, int? targetPort}) {
    final socket = _socket;
    if (socket == null || _closed) return;
    final packet = encodeQuery();
    try {
      socket.send(
        packet,
        targetAddress ?? multicastAddress,
        targetPort ?? (mdnsPort == 0 ? defaultMdnsPort : mdnsPort),
      );
    } on SocketException {
      // Ignore transient network errors on multicast send.
    }
  }

  Future<void> announce({
    int ttlSeconds = 120,
    InternetAddress? targetAddress,
    int? targetPort,
  }) async {
    final socket = _socket;
    if (socket == null || _closed) return;
    final addresses = await localAddresses();
    final packet = encodeAnnouncement(
      deviceId: deviceId,
      port: port,
      addresses: addresses,
      ttlSeconds: ttlSeconds,
    );
    try {
      socket.send(
        packet,
        targetAddress ?? multicastAddress,
        targetPort ?? (mdnsPort == 0 ? defaultMdnsPort : mdnsPort),
      );
    } on SocketException {
      // Ignore transient network errors on multicast send.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    if (_socket != null) {
      try {
        final packet = encodeAnnouncement(
          deviceId: deviceId,
          port: port,
          addresses: const [],
          ttlSeconds: 0,
        );
        _socket!.send(
          packet,
          multicastAddress,
          mdnsPort == 0 ? defaultMdnsPort : mdnsPort,
        );
      } catch (_) {}
    }
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  static Uint8List encodeQuery({
    String service = serviceDomain,
    int type = _typePtr,
  }) {
    final builder = BytesBuilder(copy: false);
    final header = ByteData(12);
    header.setUint16(0, 0); // ID
    header.setUint16(2, 0x0000); // standard query
    header.setUint16(4, 1); // QDCOUNT = 1
    header.setUint16(6, 0);
    header.setUint16(8, 0);
    header.setUint16(10, 0);
    builder.add(header.buffer.asUint8List());
    builder.add(_encodeDomainName(service));
    final qTail = ByteData(4);
    qTail.setUint16(0, type);
    qTail.setUint16(2, _classIn);
    builder.add(qTail.buffer.asUint8List());
    return builder.toBytes();
  }

  static Uint8List encodeAnnouncement({
    required String deviceId,
    required int port,
    required List<InternetAddress> addresses,
    int ttlSeconds = 120,
  }) {
    final instanceName = '$deviceId.$serviceDomain';
    final hostName = '$deviceId.local';
    final answers = <Uint8List>[];
    final additionals = <Uint8List>[];

    // 1. PTR record: _nipaplay-mesh._tcp.local -> <deviceId>._nipaplay-mesh._tcp.local
    answers.add(_encodeRecord(
      name: serviceDomain,
      type: _typePtr,
      recordClass: _classIn,
      ttl: ttlSeconds,
      rdata: _encodeDomainName(instanceName),
    ));

    // 2. SRV record: <deviceId>._nipaplay-mesh._tcp.local -> port + <deviceId>.local
    final srvBuilder = BytesBuilder(copy: false);
    final srvHead = ByteData(6);
    srvHead.setUint16(0, 0); // priority
    srvHead.setUint16(2, 0); // weight
    srvHead.setUint16(4, port);
    srvBuilder.add(srvHead.buffer.asUint8List());
    srvBuilder.add(_encodeDomainName(hostName));
    answers.add(_encodeRecord(
      name: instanceName,
      type: _typeSrv,
      recordClass: _classInFlush,
      ttl: ttlSeconds,
      rdata: srvBuilder.toBytes(),
    ));

    // 3. TXT record: mesh=1, deviceId=<id>, port=<port>
    final txtBuilder = BytesBuilder(copy: false);
    for (final entry in ['mesh=1', 'deviceId=$deviceId', 'port=$port']) {
      final bytes = utf8.encode(entry);
      txtBuilder.addByte(bytes.length);
      txtBuilder.add(bytes);
    }
    answers.add(_encodeRecord(
      name: instanceName,
      type: _typeTxt,
      recordClass: _classInFlush,
      ttl: ttlSeconds,
      rdata: txtBuilder.toBytes(),
    ));

    // 4. A / AAAA records for local LAN addresses
    for (final addr in addresses) {
      if (addr.type == InternetAddressType.IPv4) {
        additionals.add(_encodeRecord(
          name: hostName,
          type: _typeA,
          recordClass: _classInFlush,
          ttl: ttlSeconds,
          rdata: Uint8List.fromList(addr.rawAddress),
        ));
      } else if (addr.type == InternetAddressType.IPv6) {
        additionals.add(_encodeRecord(
          name: hostName,
          type: _typeAaaa,
          recordClass: _classInFlush,
          ttl: ttlSeconds,
          rdata: Uint8List.fromList(addr.rawAddress),
        ));
      }
    }

    final builder = BytesBuilder(copy: false);
    final header = ByteData(12);
    header.setUint16(0, 0); // ID = 0 for mDNS
    header.setUint16(2, 0x8400); // QR=1, AA=1
    header.setUint16(4, 0); // QDCOUNT
    header.setUint16(6, answers.length); // ANCOUNT
    header.setUint16(8, 0); // NSCOUNT
    header.setUint16(10, additionals.length); // ARCOUNT
    builder.add(header.buffer.asUint8List());
    for (final record in answers) {
      builder.add(record);
    }
    for (final record in additionals) {
      builder.add(record);
    }
    return builder.toBytes();
  }

  /// The same virtual-adapter test discovery.dart uses for candidate
  /// addresses; set by [MeshDiscovery] so the two never disagree.
  static bool Function(String name) isVirtualInterface =
      (name) => name.startsWith('lo');

  static DecodedBonjourPacket? decodePacket(
    Uint8List packet, {
    InternetAddress? sender,
    String? ownHostName,
  }) {
    if (packet.length < 12) return null;
    final view = ByteData.sublistView(packet);
    final flags = view.getUint16(2);
    final isResponse = (flags & 0x8000) != 0;
    final qdCount = view.getUint16(4);
    final anCount = view.getUint16(6);
    final nsCount = view.getUint16(8);
    final arCount = view.getUint16(10);

    var offset = 12;
    var isQueryForService = false;

    for (var i = 0; i < qdCount; i++) {
      final qName = _readDomainName(packet, offset);
      if (qName == null) return null;
      offset = qName.nextOffset;
      if (offset + 4 > packet.length) return null;
      final qType = view.getUint16(offset);
      offset += 4;
      final lower = qName.name.toLowerCase();
      if (!isResponse &&
          ownHostName != null &&
          lower == ownHostName.toLowerCase() &&
          (qType == _typeA || qType == _typeAaaa || qType == _typeAny)) {
        isQueryForService = true;
      }
      if (!isResponse &&
          (lower == serviceDomain || lower.endsWith('.$serviceDomain')) &&
          (qType == _typePtr ||
              qType == _typeSrv ||
              qType == _typeTxt ||
              qType == _typeAny)) {
        isQueryForService = true;
      }
    }

    final totalRecords = anCount + nsCount + arCount;
    final srvByInstance = <String, ({int port, String target, int ttl})>{};
    final txtByInstance = <String, Map<String, String>>{};
    final ptrInstances = <String, int>{};
    final hostsByTarget = <String, List<String>>{};

    for (var i = 0; i < totalRecords; i++) {
      if (offset >= packet.length) break;
      final rName = _readDomainName(packet, offset);
      if (rName == null) return null;
      offset = rName.nextOffset;
      if (offset + 10 > packet.length) return null;
      final rType = view.getUint16(offset);
      final ttl = view.getUint32(offset + 4);
      final rdLength = view.getUint16(offset + 8);
      offset += 10;
      if (offset + rdLength > packet.length) return null;
      final rdataStart = offset;
      offset += rdLength;

      final name = rName.name;
      final lowerName = name.toLowerCase();

      if (rType == _typePtr && lowerName == serviceDomain) {
        final target = _readDomainName(packet, rdataStart);
        if (target != null) {
          ptrInstances[target.name] = ttl;
        }
      } else if (rType == _typeSrv && lowerName.endsWith('.$serviceDomain')) {
        if (rdLength >= 6) {
          final srvPort = view.getUint16(rdataStart + 4);
          final target = _readDomainName(packet, rdataStart + 6);
          if (target != null) {
            srvByInstance[name] = (
              port: srvPort,
              target: target.name.toLowerCase(),
              ttl: ttl,
            );
          }
        }
      } else if (rType == _typeTxt && lowerName.endsWith('.$serviceDomain')) {
        final entries = <String, String>{};
        var pos = rdataStart;
        final end = rdataStart + rdLength;
        while (pos < end) {
          final len = packet[pos++];
          if (pos + len > end) break;
          final text = utf8.decode(
            packet.sublist(pos, pos + len),
            allowMalformed: true,
          );
          pos += len;
          final eq = text.indexOf('=');
          if (eq > 0) {
            entries[text.substring(0, eq)] = text.substring(eq + 1);
          }
        }
        txtByInstance[name] = entries;
      } else if (rType == _typeA && rdLength == 4) {
        final ip = InternetAddress.fromRawAddress(
          Uint8List.sublistView(packet, rdataStart, rdataStart + 4),
          type: InternetAddressType.IPv4,
        ).address;
        (hostsByTarget[lowerName] ??= <String>[]).add(ip);
      } else if (rType == _typeAaaa && rdLength == 16) {
        final ip = InternetAddress.fromRawAddress(
          Uint8List.sublistView(packet, rdataStart, rdataStart + 16),
          type: InternetAddressType.IPv6,
        ).address;
        (hostsByTarget[lowerName] ??= <String>[]).add(ip);
      }
    }

    final announcements = <BonjourPeerAnnouncement>[];
    final candidateInstances = <String>{
      ...ptrInstances.keys,
      ...srvByInstance.keys,
      ...txtByInstance.keys,
    };
    final deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

    for (final instance in candidateInstances) {
      if (!instance.toLowerCase().endsWith('.$serviceDomain')) continue;
      final prefix = instance.substring(
        0,
        instance.length - serviceDomain.length - 1,
      );
      final txt = txtByInstance[instance];
      final srv = srvByInstance[instance];
      final id = txt?['deviceId'] ?? prefix;
      if (!deviceIdPattern.hasMatch(id)) continue;
      final resolvedPort = srv?.port ?? int.tryParse(txt?['port'] ?? '') ?? 0;
      final ttl = srv?.ttl ?? ptrInstances[instance] ?? 120;
      if (ttl > 0 && (resolvedPort < 1 || resolvedPort > 65535)) continue;
      final targetHost = srv?.target ?? '${id.toLowerCase()}.local';
      final hosts = <String>[
        ...?hostsByTarget[targetHost],
        if (sender != null && !sender.isLoopback) sender.address,
        if (hostsByTarget[targetHost] == null && sender != null) sender.address,
      ];
      final uniqueHosts = <String>[];
      for (final h in hosts) {
        if (h.isNotEmpty && !uniqueHosts.contains(h)) {
          uniqueHosts.add(h);
        }
      }
      announcements.add(
        BonjourPeerAnnouncement(
          deviceId: id,
          port: resolvedPort,
          hosts: uniqueHosts,
          ttlSeconds: ttl,
        ),
      );
    }

    return DecodedBonjourPacket(
      isQueryForService: isQueryForService,
      announcements: announcements,
    );
  }

  static Uint8List _encodeRecord({
    required String name,
    required int type,
    required int recordClass,
    required int ttl,
    required Uint8List rdata,
  }) {
    final builder = BytesBuilder(copy: false);
    builder.add(_encodeDomainName(name));
    final meta = ByteData(10);
    meta.setUint16(0, type);
    meta.setUint16(2, recordClass);
    meta.setUint32(4, ttl);
    meta.setUint16(8, rdata.length);
    builder.add(meta.buffer.asUint8List());
    builder.add(rdata);
    return builder.toBytes();
  }

  static Uint8List _encodeDomainName(String domain) {
    final normalized = domain.replaceFirst(RegExp(r'\.+$'), '');
    final builder = BytesBuilder(copy: false);
    if (normalized.isNotEmpty) {
      for (final label in normalized.split('.')) {
        final bytes = utf8.encode(label);
        if (bytes.isEmpty || bytes.length > 63) {
          throw FormatException('Invalid DNS label in $domain');
        }
        builder.addByte(bytes.length);
        builder.add(bytes);
      }
    }
    builder.addByte(0);
    return builder.toBytes();
  }

  static ({String name, int nextOffset})? _readDomainName(
    Uint8List packet,
    int startOffset,
  ) {
    final labels = <String>[];
    var offset = startOffset;
    var jumped = false;
    var nextOffset = startOffset;
    var hops = 0;

    while (true) {
      if (offset >= packet.length || ++hops > 128) return null;
      final len = packet[offset];
      if (len == 0) {
        if (!jumped) nextOffset = offset + 1;
        break;
      }
      if ((len & 0xC0) == 0xC0) {
        if (offset + 1 >= packet.length) return null;
        final pointer = ((len & 0x3F) << 8) | packet[offset + 1];
        if (!jumped) nextOffset = offset + 2;
        jumped = true;
        offset = pointer;
        continue;
      }
      if ((len & 0xC0) != 0) return null;
      offset += 1;
      if (offset + len > packet.length) return null;
      labels.add(
        utf8.decode(packet.sublist(offset, offset + len), allowMalformed: true),
      );
      offset += len;
      if (!jumped) nextOffset = offset;
    }

    return (name: labels.join('.'), nextOffset: nextOffset);
  }
}
