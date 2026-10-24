import 'liveness.dart';

/// What the receiving side of a delegation (another device's Nipa handing her
/// a task) needs of the conversation host on this device. [ChatHost] is the
/// one real implementation; a test supplies a small one.
abstract interface class DelegationChat {
  bool get available;
  String? get model;
  String? get provider;

  /// The origin each side conversation is attributed to, by thread id. A
  /// delegation conversation is listed here so what Nipa does in it is
  /// attributed to it and not to the conversation of the person at this device.
  Map<String, String> get threadOrigins;

  /// Wire messages of every thread, in order.
  Stream<Map<String, dynamic>> get events;

  bool busyFor(String threadId);
  ChatLiveness livenessFor(String threadId);

  /// Opens a conversation for delegated work without selecting it: the
  /// conversation the person is in, and its durable pointer, stay as they are.
  /// [token] names the conversation in attribution (`harness_cli:chat:delegate-<token>`).
  Future<String> delegationThread(String token, String title);

  Future<Map<String, dynamic>> startThreadTurn(String id, String text);
  Future<Map<String, dynamic>> readThread(String id, {bool withProcess});
  Future<Map<String, dynamic>> interrupt({String? onThread});

  /// The conversations of this device's Nipa (for the device description).
  Future<int?> conversationCount();
}
