import 'delegation_chat.dart';

/// What the conversations of a device that cannot run Nipa (an iPad) need of
/// the conversation host here: open a conversation, speak in it, read it, be
/// told what happens in it, stop it, answer her questions. [ChatHost] is the
/// one real implementation; a test supplies a small one.
abstract interface class GuestChat implements DelegationChat {
  /// Display messages of every thread (items, deltas, turn boundaries,
  /// `host/liveness`, `host/reasoning`), each naming its `params.threadId`.
  Stream<Map<String, dynamic>> get threadDisplay;

  /// `item/tool/requestUserInput` requests of every thread.
  Stream<Map<String, dynamic>> get userInputRequests;

  Future<Map<String, dynamic>> steer(String text, {String? onThread});
  Future<void> answerUserInput(Object id, Map<String, List<String>> answers);

  /// Puts the saved display copy of the process back into [history]'s turns.
  Future<void> restoreProcess(String id, Map<String, dynamic> history);

  /// The conversations of this host, as the session menu lists them.
  Future<Map<String, dynamic>> listSessions({String? cursor, int limit = 30});
}
