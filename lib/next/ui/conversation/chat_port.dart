import 'dart:async';

import '../../chat/chat_host.dart';
import '../../harness_redaction.dart';
import '../../next_runtime.dart';

typedef ChatEvent = Map<String, dynamic>;

/// What the interface needs from a chat host. The production port wraps
/// `NextRuntime.chat` (X23); development experiments may script one.
abstract interface class ChatPort {
  /// A host is running and can take a turn.
  bool get available;

  /// The host's current session has a turn running (ours or a
  /// follow-up's); a turn on another session waits for it.
  bool get busy;

  /// A turn runs on [threadId] (helpers run beside the current session).
  bool busyOn(String threadId);

  /// Display messages: items, deltas, turn boundaries, `host/liveness`.
  Stream<ChatEvent> get display;

  /// `item/tool/requestUserInput` requests.
  Stream<ChatEvent> get questions;

  /// Gets the durable main thread. Null while another turn is running.
  Future<String?> mainThread();

  /// Explicitly opens a fresh conversation. Null while another turn is running.
  Future<String?> newThread();

  /// Codex's threads for this harness, most recent first, the main one
  /// marked: `{data: [{id, preview, updatedAt, isMain, isCurrent, …}],
  /// mainThreadId, currentThreadId, nextCursor}`.
  Future<ChatEvent> listThreads({String? cursor});

  /// Makes [threadId] the host's current session. Null while a turn runs.
  Future<String?> switchThread(String threadId);

  /// Starts a turn on [threadId]. Returns the server's response, or null
  /// while another turn is running.
  Future<ChatEvent?> startTurn(String threadId, String text);

  /// Adds input to the turn running on [threadId] (default: the current
  /// session's).
  Future<void> steer(String text, {String? threadId});

  /// A thread with its turns and their items (Codex's own history).
  Future<ChatEvent> readThread(String threadId);
  Future<void> interrupt({String? threadId});
  Future<void> answer(Object requestId, Map<String, List<String>> answers);
  void dispose();
}

/// The production port over the embedded Codex host.
final class ChatHostPort implements ChatPort {
  ChatHostPort(this.runtime) {
    runtime.addListener(_attach);
    // The host is created before it finishes starting and the runtime does
    // not always notify again; re-check cheaply.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _attach());
    _attach();
  }

  final NextRuntime runtime;
  late final Timer _poll;
  ChatHost? _host;
  StreamSubscription<ChatEvent>? _displaySub, _questionSub;
  final _display = StreamController<ChatEvent>.broadcast();
  final _questions = StreamController<ChatEvent>.broadcast();

  void _attach() {
    final host = runtime.chat;
    if (identical(host, _host)) return;
    _displaySub?.cancel();
    _questionSub?.cancel();
    _host = host;
    if (host != null) {
      // Every session's events; the host's own ones name their thread.
      _displaySub = host.threadDisplay.listen(_display.add);
      _questionSub = host.userInputRequests.listen(_questions.add);
    }
  }

  ChatHost? get _current {
    _attach();
    return _host;
  }

  @override
  bool get available => _current?.available ?? false;

  @override
  bool get busy => _current?.busy ?? false;

  @override
  bool busyOn(String threadId) => _current?.busyFor(threadId) ?? false;

  @override
  Stream<ChatEvent> get display => _display.stream;

  @override
  Stream<ChatEvent> get questions => _questions.stream;

  @override
  Future<String?> mainThread() async {
    final host = _current;
    if (host == null) throw StateError('chat host unavailable');
    return host.prepareFollowup(null);
  }

  @override
  Future<String?> newThread() async {
    final host = _current;
    if (host == null) throw StateError('chat host unavailable');
    if (host.busy) return null;
    return (await host.newConversation())['thread']['id'] as String;
  }

  @override
  Future<ChatEvent> listThreads({String? cursor}) async {
    final host = _current;
    if (host == null) throw StateError('chat host unavailable');
    return host.listSessions(cursor: cursor);
  }

  @override
  Future<String?> switchThread(String threadId) async {
    final host = _current;
    if (host == null) throw StateError('chat host unavailable');
    if (host.busy) return null;
    return (await host.switchSession(threadId))['thread']['id'] as String;
  }

  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    final host = _current;
    if (host == null) throw StateError('chat host unavailable');
    return host.startFollowup(threadId, text);
  }

  @override
  Future<void> steer(String text, {String? threadId}) async =>
      _current?.steer(text, onThread: threadId);

  /// Redacted like the live display stream, so history shows what the
  /// live view showed. The saved process was redacted as it was saved, so
  /// only the runtime's history is redacted here; the process goes back in
  /// after, read off the main isolate.
  @override
  Future<ChatEvent> readThread(String threadId) async {
    final host = _current;
    if (host == null) throw StateError('chat host unavailable');
    final history = Map<String, dynamic>.from(redactHarnessJson(
        await host.readThread(threadId, withProcess: false)) as Map);
    await host.restoreProcess(threadId, history);
    return history;
  }

  @override
  Future<void> interrupt({String? threadId}) async =>
      _current?.interrupt(onThread: threadId);

  @override
  Future<void> answer(
          Object requestId, Map<String, List<String>> answers) async =>
      _current?.answerUserInput(requestId, answers);

  @override
  void dispose() {
    _poll.cancel();
    runtime.removeListener(_attach);
    _displaySub?.cancel();
    _questionSub?.cancel();
    _display.close();
    _questions.close();
  }
}

/// Reads the turn ID from a `turn/start` response.
String? turnIdOf(ChatEvent? response) {
  final turn = response?['turn'];
  return turn is Map ? turn['id'] as String? : null;
}

/// The thread an event belongs to, when it says.
String? threadIdOf(ChatEvent event) {
  final params = event['params'];
  if (params is! Map) return null;
  return params['threadId'] as String? ??
      (params['thread'] is Map ? params['thread']['id'] as String? : null);
}
