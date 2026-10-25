import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/bonjour.dart';

/// Windows' own responder (the DNS Client service) already holds UDP 5353.
/// NipaPlay's responder must share the port with it and with a second
/// NipaPlay on the same machine (SO_REUSEADDR; Windows has no SO_REUSEPORT),
/// and still hear the other's announcement on the multicast group.
void main() {
  test('two responders on the default mDNS port hear each other', () async {
    // Device IDs are 43 characters (an unpadded base64url SHA-256).
    final idA = 'a${'A' * 42}', idB = 'b${'B' * 42}';
    final heard = <String, Completer<void>>{
      idA: Completer<void>(),
      idB: Completer<void>(),
    };
    Future<List<InternetAddress>> addresses() async =>
        [InternetAddress('192.168.77.7')];
    MeshBonjour make(String id, String peer) => MeshBonjour(
          deviceId: id,
          port: 47001,
          localAddresses: addresses,
          allowInLabProfile: true,
          onPeerDiscovered: (device, host, port, ttl) {
            if (device == peer && !heard[id]!.isCompleted) {
              heard[id]!.complete();
            }
          },
        );
    final a = make(idA, idB), b = make(idB, idA);
    try {
      await a.start();
      await b.start();
      expect(a.boundPort, MeshBonjour.defaultMdnsPort,
          reason: 'bound to the mDNS port');
      expect(b.boundPort, MeshBonjour.defaultMdnsPort);
      a.sendQuery();
      b.sendQuery();
      await Future.wait([
        heard[idA]!.future,
        heard[idB]!.future,
      ]).timeout(const Duration(seconds: 15));
    } finally {
      await a.close();
      await b.close();
    }
  }, skip: Platform.isWindows ? null : 'The default-port sharing is checked on Windows');
}
