/// Without Flutter there is no system Bonjour bridge; desktop and headless
/// hosts use the hand-written responder in bonjour.dart.
final class SystemBonjour {
  SystemBonjour({
    required this.deviceId,
    required this.port,
    required this.onPeerDiscovered,
  });

  static bool get available => false;

  final String deviceId;
  final int port;
  final void Function(String deviceId, String host, int port, int ttlSeconds)
      onPeerDiscovered;

  Future<void> start() async {}
  Future<void> close() async {}
}
