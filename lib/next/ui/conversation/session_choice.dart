import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chat_port.dart';

/// Which session things go into. Each harness has one main session, kept
/// by the host, and everything goes into it by default: the home's input
/// bar, ⌘K, the avatar. Another session becomes current only when you pick
/// it in the panel or open a new conversation there; picking the main
/// session makes it current again. The host is told what you picked, so the
/// agent's session list says the same.
class SessionChoice extends ChangeNotifier {
  SessionChoice(this.port);
  final ChatPort port;

  /// The main session, once known. Null before the host has said and while
  /// the harness has none yet: the first thing you say creates it.
  String? main;
  Future<void>? _loading;

  /// Another session you picked; null: the main one.
  String? _picked;

  /// You opened a new conversation; it is created with what you say.
  bool fresh = false;

  /// The session shown and talked to. Null: one still to be created (the
  /// new conversation you opened, or the harness's first main session).
  String? get current => fresh ? null : (_picked ?? main);

  bool get onMain => !fresh && _picked == null;

  /// Reads which session is the main one (again, until it is known).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      learn((await port.listThreads())['mainThreadId'] as String?);
    } catch (error) {
      debugPrint('[NextUi] sessions unknown: $error');
    }
    if (main == null) _loading = null;
  }

  /// The host named the main session (with a session list).
  void learn(String? mainThreadId) {
    if (mainThreadId == null || mainThreadId == main) return;
    main = mainThreadId;
    if (_picked == main) _picked = null;
    notifyListeners();
  }

  void pick(String threadId) {
    fresh = false;
    _picked = threadId == main ? null : threadId;
    notifyListeners();
    unawaited(_tellHost(threadId));
  }

  void backToMain() {
    fresh = false;
    _picked = null;
    notifyListeners();
    if (main case final id?) unawaited(_tellHost(id));
  }

  void startNew() {
    fresh = true;
    _picked = null;
    notifyListeners();
  }

  /// The host's current session follows yours; while a turn runs it cannot
  /// switch, and the next turn on yours switches it anyway.
  Future<void> _tellHost(String threadId) async {
    try {
      await port.switchThread(threadId);
    } catch (error) {
      debugPrint('[NextUi] session not switched: $error');
    }
  }

  Future<String?>? _creating;

  /// The session to say something on, created if needed. Null while the
  /// host runs another turn and cannot open one: try again once it is free.
  Future<String?> target() async {
    await load();
    if (current case final id?) return id;
    return _creating ??= _create().whenComplete(() => _creating = null);
  }

  Future<String?> _create() async {
    final opening = fresh;
    final id = opening ? await port.newThread() : await port.mainThread();
    if (id == null) return null;
    if (opening) {
      fresh = false;
      _picked = id;
    } else {
      main = id;
    }
    notifyListeners();
    return id;
  }
}
