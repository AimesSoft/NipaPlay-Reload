import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ui_data/ui_data.dart';
import '../../util/slicer.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/words.dart';
import 'chat_context.dart';
import 'chat_port.dart';
import 'chat_turn.dart';
import 'underway.dart';

export 'chat_context.dart';
export 'chat_turn.dart';

/// A conversation as Codex keeps it, for the session menu.
@immutable
final class ChatSession {
  const ChatSession(this.id, this.title, this.at);
  final String id;

  /// Its first sentence.
  final String title;

  /// Last activity.
  final DateTime? at;
}

/// The conversation with Nipa. There is one: the home shows it expanded or
/// folded away, every other page in the side panel. It is the harness's
/// main session unless you open a new one or pick another in the menu,
/// and it stays that until you choose again.
///
/// Everything said goes into the session shown: a new turn, or, while
/// its turn runs, more for that turn (`steer`). A running turn can be
/// stopped. Turns NipaPlay starts for Nipa (follow-ups, schedules) show
/// in their own session like any other; the home tells about those
/// running elsewhere.
class NipaChat extends ChangeNotifier {
  NipaChat({required this.port, required this.data}) {
    _subs = [
      port.display.listen(_onEvent),
      port.questions.listen(_onQuestion),
      data.changes.listen((_) => _cardsChanged()),
      data.tasks().listen(_tasksChanged),
    ];
    _boot();
  }

  final ChatPort port;
  final NextUiData data;
  late final List<StreamSubscription<Object?>> _subs;
  bool _disposed = false;

  static const quietAfter = Duration(minutes: 3);

  /// Turns read when a session opens; the latest of them read their cards.
  static const historyTurns = 30;
  static const cardTurns = 12;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // —— Sessions ——

  /// The harness's main session, once known.
  String? main;

  /// The session shown. Null: one still to be created by the first thing
  /// you say (a new conversation, or the harness's first main session).
  String? thread;

  /// You opened a new conversation; it is created with what you say.
  bool fresh = false;

  bool get onMain => !fresh && (thread == null || thread == main);

  /// The main session first, then the others, latest first. Helpers'
  /// threads are not among them: they open from the background panel.
  List<ChatSession> sessions = const [];

  /// Helpers' threads, with what each was sent to do.
  final _helpers = <String, String>{};

  void _tasksChanged(List<UiTask> tasks) {
    var changed = false;
    for (final t in tasks) {
      if (t.kind != UiTaskKind.helper || t.threadId == null) continue;
      if (_helpers[t.threadId!] != t.title) {
        _helpers[t.threadId!] = t.title;
        changed = true;
      }
    }
    if (changed) {
      _elsewhere.removeWhere((_, turn) => _helpers.containsKey(turn.threadId));
      unawaited(refreshSessions());
    }
  }

  bool menuOpen = false;

  Timer? _bootTimer;
  bool _booted = false;

  /// Waits for the host, learns the main session and opens it.
  void _boot() {
    Future<void> attempt() async {
      if (_disposed || _booted || !port.available) return;
      _booted = true;
      _bootTimer?.cancel();
      _bootTimer = null;
      await refreshSessions();
      if (thread == null && !fresh && turns.isEmpty && main != null) {
        await _open(main!);
      }
    }

    _bootTimer = Timer.periodic(const Duration(seconds: 1), (_) => attempt());
    unawaited(attempt());
  }

  Future<void> refreshSessions() async {
    if (!port.available) return;
    try {
      final result = await port.listThreads();
      final list = (result['data'] as List? ?? const []).whereType<Map>();
      if (result['mainThreadId'] case final String id) main = id;
      int rank(ChatSession s) => s.id == main ? 0 : 1;
      sessions = [
        for (final t in list)
          if (t['id'] is String && !_helpers.containsKey(t['id']))
            ChatSession(t['id'] as String, _title(t['preview']),
                _time(t['updatedAt'] ?? t['createdAt'])),
      ]..sort((a, b) => rank(a) != rank(b)
          ? rank(a) - rank(b)
          : (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
      _notify();
    } catch (error) {
      debugPrint('[NextUi] sessions failed: $error');
    }
  }

  static String _title(Object? preview) {
    final text = preview is String ? preview.trim() : '';
    if (ChatContext.isFollowup(text)) return 'Nipa 后来说的';
    final said = ChatContext.strip(text);
    return said.isEmpty ? '新的对话' : Words.firstSentence(said);
  }

  static DateTime? _time(Object? value) => switch (value) {
        final num seconds =>
          DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()),
        final String text => DateTime.tryParse(text)?.toLocal(),
        _ => null,
      };

  /// The title of the session shown.
  String get title {
    if (onMain) return 'Nipa';
    final id = thread;
    if (id == null) return '新的对话';
    if (_helpers[id] case final helper?) return helper;
    return sessions.where((s) => s.id == id).firstOrNull?.title ?? 'Nipa';
  }

  void toggleMenu() {
    menuOpen = !menuOpen;
    if (menuOpen) unawaited(refreshSessions());
    _notify();
  }

  void closeMenu() {
    if (!menuOpen) return;
    menuOpen = false;
    _notify();
  }

  /// “新的对话”, only when you ask for it: Codex creates it with the first
  /// thing you say.
  void startNew() {
    fresh = true;
    menuOpen = false;
    _show(null);
  }

  /// Shows [id]. The host's current session moves only when a turn
  /// starts there: looking at a helper must not hold up the main session.
  Future<void> select(String id) async {
    fresh = false;
    menuOpen = false;
    await _open(id);
  }

  Future<void> selectMain() async {
    fresh = false;
    menuOpen = false;
    final id = main;
    if (id == null) return _show(null);
    await _open(id);
  }

  Future<String?>? _creating;

  /// The session to say something on, created if needed. Null while the
  /// host runs another turn and cannot open one.
  Future<String?> _target() async {
    if (thread case final id?) return id;
    if (!fresh && main != null) return thread = main;
    return _creating ??= () async {
      final opening = fresh;
      final id = opening ? await port.newThread() : await port.mainThread();
      if (id == null) return null;
      if (!opening) main = id;
      fresh = false;
      thread = id;
      _notify();
      return id;
    }()
        .whenComplete(() => _creating = null);
  }

  // —— The transcript ——

  List<ChatTurn> turns = [];
  bool loading = false;

  /// Something went wrong that the conversation says once.
  String? trouble;

  /// Bumps whenever another session is shown; late results are dropped.
  int _generation = 0;
  final _buffer = <ChatEvent>[];

  void _show(String? id) {
    _generation++;
    thread = id;
    turns = [];
    loading = false;
    trouble = null;
    quiet = false;
    _buffer.clear();
    _chosen.clear();
    _notify();
  }

  /// Shows [id] with its history; a turn still running goes on live.
  Future<void> _open(String id) async {
    _show(id);
    final generation = _generation;
    loading = true;
    _notify();
    try {
      final history = await port.readThread(id);
      if (generation != _generation) return;
      turns = await _fromHistory(history);
    } catch (error) {
      debugPrint('[NextUi] thread did not open: $error');
      if (generation != _generation) return;
      loading = false;
      trouble = '这段对话没打开，再试一次？';
      _notify();
      return;
    }
    loading = false;
    final buffered = [..._buffer];
    _buffer.clear();
    for (final event in buffered) {
      _apply(event, replay: true);
    }
    if (_questions[id] != null) live?.beginWait();
    _notify();
    final recent = turns.length > cardTurns
        ? turns.sublist(turns.length - cardTurns)
        : turns;
    await Future.wait([for (final t in recent) _refreshCards(t)]);
  }

  Future<List<ChatTurn>> _fromHistory(ChatEvent history) async {
    final slice = Slicer();
    final raw =
        (history['turns'] as List? ?? const []).whereType<Map>().toList();
    final shown = raw.length > historyTurns
        ? raw.sublist(raw.length - historyTurns)
        : raw;
    final list = <ChatTurn>[];
    String? saidIn(Map turn) => (turn['items'] as List? ?? const [])
        .whereType<Map>()
        .where((item) => item['type'] == 'userMessage')
        .map((item) => ChatTurn.saidOf(item)?.text)
        .firstOrNull;
    for (var i = 0; i < shown.length; i++) {
      final turn = shown[i];
      // “重新发” leaves a silent, stopped attempt behind: show it once.
      final said = saidIn(turn);
      if (turn['status'] == 'interrupted' &&
          said != null &&
          i + 1 < shown.length &&
          saidIn(shown[i + 1]) == said &&
          !(turn['items'] as List? ?? const [])
              .whereType<Map>()
              .any((item) => item['type'] == 'agentMessage')) {
        continue;
      }
      list.add(ChatTurn.fromHistory(turn));
      await slice();
    }
    return list;
  }

  /// The turn running in the session shown, if any.
  ChatTurn? get live {
    final last = turns.lastOrNull;
    return last != null && last.running ? last : null;
  }

  bool get running => live != null;

  // —— Seen or not ——

  /// The conversation is on screen (the home expanded, or the panel).
  bool visible = false;

  /// Something Nipa finished while nobody was looking.
  bool unseen = false;

  /// Nipa's latest line for the home: how a conversation ended, or what a
  /// turn that ran unseen came to.
  String? latestLine;

  void setVisible(bool on) {
    if (visible == on) return;
    visible = on;
    if (on) {
      unseen = false;
      _refreshAll();
    } else {
      menuOpen = false;
      final words = turns.lastOrNull?.answer?.text;
      if (words != null) latestLine = Words.firstSentence(words);
    }
    _notify();
  }

  /// Something only the view keeps (an unfolded group) changed.
  void viewChanged() => _notify();

  void markSeen() {
    if (!unseen) return;
    unseen = false;
    _notify();
  }

  // —— Saying something ——

  /// “问 Nipa” on a work's page: it goes along with what you say.
  UiWork? about;

  /// Files dropped in, going with what you say next.
  List<String> attachments = const [];

  void attach(List<String> paths) {
    attachments = [
      ...attachments,
      for (final p in paths)
        if (!attachments.contains(p)) p
    ];
    _notify();
  }

  void detach(String path) {
    attachments = [
      for (final p in attachments)
        if (p != path) p
    ];
    _notify();
  }

  void setAbout(UiWork? work) {
    about = work;
    _notify();
  }

  /// While a video is up under the conversation: reads what plays and
  /// where, the moment you speak. What you say goes with it.
  Future<Watching?> Function()? _watching;

  /// What plays under the conversation, as [Watching.named] names it, once
  /// known: what was said over it need not say so while it plays.
  String? watched;

  /// The player, while it is open: [read] tells what plays and where;
  /// [named] names it, once the library has said what it is (until then
  /// the name stays as it was).
  void watch(Future<Watching?> Function() read, {String? named}) {
    _watching = read;
    if (named == null || watched == named) return;
    watched = named;
    _notify();
  }

  /// The player is gone: what is said goes alone again.
  void unwatch(Future<Watching?> Function() read) {
    if (_watching != read) return;
    _watching = null;
    if (watched == null) return;
    watched = null;
    _notify();
  }

  /// Whether the input takes text now.
  bool get acceptsTyping => !(question != null && secretAsked);

  String get hint {
    if (question != null) return secretAsked ? '这里不输入密码' : '也可以直接说';
    if (attachments.isNotEmpty) return '想让 Nipa 做什么？';
    if (about != null) return '问问《${about!.title}》';
    if (running) return '补充，或者改主意';
    return turns.isEmpty ? '今天想看什么？' : '继续说…';
  }

  ChatTurn? _pending;
  String? _pendingInput;
  bool _cancelQueued = false;

  /// Says [text] with the files dropped in: an answer while Nipa asks,
  /// more for the turn while it runs, otherwise a new turn.
  Future<void> say(String text) async {
    text = text.trim();
    if (!acceptsTyping) return;
    if (question != null) {
      if (text.isNotEmpty) await answerText(text);
      return;
    }
    final files = attachments;
    if (text.isEmpty && files.isEmpty) return;
    trouble = null;
    attachments = const [];
    final asked = about;
    // Where the video is when it is said, not once the library answers.
    final reading = _watching?.call();
    var input = ChatContext.withFiles(text, files);
    if (asked != null) input = ChatContext.about(input, asked);
    final now = reading == null
        ? null
        : await reading.catchError((Object error) {
            debugPrint('[NextUi] what plays is not known: $error');
            return null;
          });
    if (now != null) input = ChatContext.watching(input, now);
    final said = SaidPart(text,
        about: asked?.title, watched: now?.named, files: files, echoed: false);
    final current = live;
    if (current != null && current.queued && identical(current, _pending)) {
      // Still waiting for the host: it all goes out together.
      current.parts.add(said);
      _pendingInput = '${_pendingInput ?? ''}\n\n$input';
      _notify();
      return;
    }
    if (current != null && thread != null && port.busyOn(thread!)) {
      current.parts.add(said);
      quiet = false;
      _notify();
      try {
        await port.steer(input, threadId: thread);
        said.echoed = true;
        _notify();
      } catch (error) {
        debugPrint('[NextUi] steer failed: $error');
        said.echoed = true;
        trouble = '这句没送到，等这一轮结束再说一次？';
        _notify();
      }
      return;
    }
    final turn = ChatTurn()
      ..status = port.busy ? 'queued' : 'inProgress'
      ..parts.add(said);
    turns = [...turns, turn];
    _pending = turn;
    _pendingInput = input;
    quiet = false;
    _quietWaived = null;
    _notify();
    await _start(turn);
  }

  Future<void> _start(ChatTurn turn) async {
    if (!port.available) {
      String? why;
      try {
        why = await port.unavailableReason();
      } catch (error) {
        debugPrint('[NextUi] unavailable reason failed: $error');
      }
      if (port.available) return _start(turn);
      _fail(turn, why ?? 'Nipa 现在还不能开始对话。请打开“设置 Nipa”检查模型和运行环境。');
      return;
    }
    final generation = _generation;
    _cancelQueued = false;
    try {
      while (!_disposed && generation == _generation && !_cancelQueued) {
        final target = await _target();
        if (target == null || port.busy) {
          if (turn.status != 'queued') {
            turn.status = 'queued';
            _notify();
          }
          await _waitUntilFree();
          continue;
        }
        if (turn.status == 'queued') {
          turn.status = 'inProgress';
          turn.startedAt = DateTime.now();
          _notify();
        }
        final response = await port.startTurn(target, _pendingInput ?? '');
        if (response == null) continue;
        final id = turnIdOf(response);
        if (id != null) turn.id = id;
        break;
      }
    } catch (error) {
      debugPrint('[NextUi] turn did not start: $error');
      _fail(turn, '这次没接上，再说一次试试？');
    } finally {
      if (identical(_pending, turn) && turn.id != null) _pending = null;
    }
    _notify();
    unawaited(refreshSessions());
  }

  void _fail(ChatTurn turn, String why) {
    turn
      ..status = 'failed'
      ..endedAt = DateTime.now();
    if (turn.parts.whereType<NoticePart>().every((note) => note.text != why)) {
      turn.parts.add(NoticePart(why));
    }
    if (identical(_pending, turn)) _pending = null;
    _notify();
  }

  Future<void> _waitUntilFree() async {
    while (!_disposed && port.busy && !_cancelQueued) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Timer? _stopTimer;

  /// Stops the running turn. One still waiting for the host is simply not
  /// sent; one that does not end within a few seconds is shown stopped.
  Future<void> stop() async {
    final turn = live;
    if (turn == null) return;
    if (turn.queued) {
      _cancelQueued = true;
      turn
        ..status = 'interrupted'
        ..endedAt = DateTime.now();
      if (identical(_pending, turn)) _pending = null;
      _notify();
      return;
    }
    try {
      await port.interrupt(threadId: thread);
    } catch (error) {
      debugPrint('[NextUi] interrupt failed: $error');
    }
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(seconds: 8), () {
      if (!turn.running) return;
      turn.apply('turn/completed', {
        'turn': {'id': turn.id, 'status': 'interrupted'}
      });
      quiet = false;
      _notify();
    });
  }

  // —— Quiet ——

  /// The running turn has had no event for [quietAfter].
  bool quiet = false;
  DateTime? _quietWaived;

  void _liveness(Map params) {
    final turn = live;
    if (turn == null || turn.queued) return;
    final id = params['turnId'];
    if (turn.id != null && id != null && id != turn.id) return;
    final ago = params['lastEventAgoMs'];
    final silent = ago is num && ago > quietAfter.inMilliseconds;
    final waived = _quietWaived != null &&
        DateTime.now().difference(_quietWaived!) < quietAfter;
    final next = silent && !waived;
    if (next != quiet) {
      quiet = next;
      _notify();
    }
  }

  void keepWaiting() {
    quiet = false;
    _quietWaived = DateTime.now();
    _notify();
  }

  /// “重新发”: stop the silent turn, then say the same again.
  Future<void> resend() async {
    final turn = live;
    if (turn == null) return;
    final said = turn.parts.whereType<SaidPart>().firstOrNull;
    if (said == null) return;
    quiet = false;
    await stop();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((thread != null && port.busyOn(thread!)) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // Shown once: the stopped attempt goes, the same words go out again.
    turns = [
      for (final t in turns)
        if (!identical(t, turn)) t
    ];
    attachments = said.files;
    await say(said.text);
  }

  // —— Questions ——

  /// `requestUserInput`, by session.
  final _questions = <String, ChatEvent>{};
  final _chosen = <String, String>{};

  ChatEvent? get question => thread == null ? null : _questions[thread];

  /// Nipa waits for an answer in some session.
  bool get asking => _questions.isNotEmpty;

  List<Map<String, dynamic>> get questionItems {
    final params = question?['params'];
    final list = params is Map ? params['questions'] : null;
    return list is List ? list.whereType<Map<String, dynamic>>().toList() : [];
  }

  /// Nipa asks for a secret: that is not typed into the conversation.
  bool get secretAsked => questionItems.any((q) => q['isSecret'] == true);

  Map<String, String> get chosen => _chosen;

  Future<void> choose(String questionId, String label) async {
    _chosen[questionId] = label;
    final items = questionItems;
    if (items.every((q) => _chosen.containsKey(q['id']))) {
      return _answer({
        for (final q in items) q['id'] as String: [_chosen[q['id']]!]
      });
    }
    _notify();
  }

  /// “跳过”: no answer to give here.
  Future<void> skip() =>
      _answer({for (final q in questionItems) q['id'] as String: const []});

  /// Typed instead: answers every question not picked yet.
  Future<void> answerText(String text) => _answer({
        for (final q in questionItems)
          q['id'] as String: [_chosen[q['id']] ?? text],
      });

  Future<void> _answer(Map<String, List<String>> answers) async {
    final request = question;
    if (request == null) return;
    live?.endWait();
    _questions.remove(thread);
    _chosen.clear();
    _notify();
    try {
      await port.answer(request['id'] as Object, answers);
    } catch (error) {
      debugPrint('[NextUi] answer failed: $error');
    }
  }

  void _onQuestion(ChatEvent event) {
    final target = threadIdOf(event);
    if (target == null) return;
    _questions[target] = event;
    if (target == thread) {
      _chosen.clear();
      live?.beginWait();
    } else {
      _elsewhere[_turnOf(event['params'] as Map? ?? const {})]?.beginWait();
    }
    if (!visible) unseen = true;
    _notify();
  }

  // —— Events ——

  /// Turns running in sessions not shown, by turn.
  final _elsewhere = <String?, ChatTurn>{};

  static String? _turnOf(Map params) =>
      params['turnId'] as String? ??
      (params['turn'] is Map ? params['turn']['id'] as String? : null);

  void _onEvent(ChatEvent event) {
    final method = event['method'] as String? ?? '';
    final params = event['params'] as Map? ?? const {};
    final about = params['threadId'] as String?;
    switch (method) {
      case 'host/liveness':
        if (about != null && about != thread) return;
        return _liveness(params);
      case 'host/error':
        if (live case final turn? when !turn.queued) {
          _fail(turn, 'Nipa 现在不在，过一会儿再试试。');
        }
        return;
      case 'host/reasoning':
        // The thread's running turn; without one named, the current one's.
        final ChatTurn? turn;
        if (about == null || about == thread) {
          turn = (live != null && !live!.queued)
              ? live
              : (about == null
                  ? _elsewhere.values.where((t) => t.running).lastOrNull
                  : null);
        } else {
          turn = _elsewhere.values
              .where((t) => t.running && t.threadId == about)
              .lastOrNull;
        }
        if (turn != null && !loading && turn.apply(method, params)) {
          _notify();
        }
        return;
    }
    if (method.startsWith('host/')) return;
    final target = threadIdOf(event);
    if (target == null) return;
    if (target != thread) return _watch(method, params, target);
    if (loading) {
      _buffer.add(event);
      return;
    }
    _apply(event);
  }

  ChatTurn? _turnById(String? id) {
    if (id == null) return null;
    for (final t in turns.reversed) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _apply(ChatEvent event, {bool replay = false}) {
    final method = event['method'] as String? ?? '';
    final params = event['params'] as Map? ?? const {};
    final id = _turnOf(params);
    var turn = _turnById(id);
    if (turn == null) {
      final pending = _pending;
      // Only once it is being started: while it waits, a turn that starts
      // is another (a follow-up).
      if (pending != null &&
          pending.id == null &&
          pending.status == 'inProgress') {
        // What you just said: its turn has started.
        pending.id = id;
        turn = pending;
      } else if (method == 'turn/started' || method.startsWith('item/')) {
        turn = ChatTurn(id: id);
        turns = [...turns, turn];
      } else {
        return;
      }
    }
    // A follow-up took the host first: what you said waits on.
    if (identical(turn, _pending) &&
        method.startsWith('item/') &&
        params['item'] is Map &&
        (params['item'] as Map)['type'] == 'userMessage' &&
        ChatTurn.saidOf(params['item'] as Map) == null) {
      final other = ChatTurn(id: turn.id)..followup = true;
      turn.id = null;
      turns = [
        for (final t in turns) ...[if (identical(t, turn)) other, t]
      ];
      turn = other;
    }
    if (replay &&
        (method == 'item/agentMessage/delta' ||
            method == 'item/commandExecution/outputDelta')) {
      // History holds what came before the session was read.
      return;
    }
    if (method == 'turn/started') {
      quiet = false;
      _quietWaived = null;
    }
    _noteHelpers(params);
    final changed = turn.apply(method, params);
    switch (method) {
      case 'item/completed':
        final type = (params['item'] as Map?)?['type'];
        if (type != 'agentMessage' && type != 'userMessage') {
          unawaited(_refreshCards(turn));
        }
      case 'turn/completed':
        quiet = false;
        _stopTimer?.cancel();
        // You were reading its steps: they stay where they are.
        if (turn.parts.any((p) => p is StepsPart && p.open)) {
          turn.unfolded = true;
        }
        if (identical(_pending, turn)) _pending = null;
        if (turn.status == 'failed' && turn.answer == null) {
          trouble = '这次没说完，再说一次试试？';
        }
        if (!visible) {
          final words = turn.lastWords;
          if (words.isNotEmpty) {
            latestLine = Words.firstSentence(words);
            unseen = true;
          }
        }
        unawaited(_refreshCards(turn));
        unawaited(refreshSessions());
    }
    if (changed || method == 'turn/completed') _notify();
  }

  /// A turn in a session not shown: what it is doing, for the home.
  /// Codex's own sub-agents are helpers: their threads are not sessions
  /// of yours, nor what Nipa is doing on the home.
  void _noteHelpers(Map params) {
    final item = params['item'];
    if (item is! Map || item['type'] != 'collabAgentToolCall') return;
    final ids = item['receiverThreadIds'];
    if (ids is! List || ids.isEmpty) return;
    final title = ChatTurn.helperTitle('${item['prompt'] ?? ''}');
    for (final id in ids) {
      _helpers.putIfAbsent('$id', () => title.isEmpty ? '帮手' : title);
    }
    _elsewhere.removeWhere((_, turn) => _helpers.containsKey(turn.threadId));
  }

  void _watch(String method, Map params, String threadId) {
    _noteHelpers(params);
    // Helpers show in the background panel; their result comes back here.
    if (_helpers.containsKey(threadId)) return;
    final id = _turnOf(params);
    if (id == null) return;
    var turn = _elsewhere[id];
    if (turn == null) {
      if (method != 'turn/started') return;
      turn = _elsewhere[id] = ChatTurn(id: id)..threadId = threadId;
      while (_elsewhere.length > 8) {
        _elsewhere.remove(_elsewhere.keys.first);
      }
    }
    final changed = turn.apply(method, params);
    if (method == 'turn/completed') {
      _elsewhere.remove(id);
      final words = turn.lastWords;
      if (words.isNotEmpty) {
        latestLine = Words.firstSentence(words);
        unseen = true;
      }
      unawaited(refreshSessions());
      _notify();
    } else if (changed) {
      if (method == 'item/completed') {
        unawaited(_refreshElsewhere(turn, threadId));
      }
      _notify();
    }
  }

  // —— For the home and the avatar ——

  ChatTurn? get _working {
    final shown = live;
    if (shown != null && !shown.queued) return shown;
    return _elsewhere.values.where((t) => t.running).lastOrNull;
  }

  NipaMood get mood {
    if (asking) return NipaMood.waiting;
    final turn = _working;
    if (turn == null) return NipaMood.idle;
    return turn.doing != null || _preparing != null
        ? NipaMood.acting
        : NipaMood.thinking;
  }

  /// What Nipa is doing now, in a few words; null when it is not.
  String? get doing {
    final turn = _working;
    if (turn == null) return null;
    if (_preparing case final step?) {
      return step.startsWith('在') || step.startsWith('正在') ? step : '在$step';
    }
    if (turn.doing case final phrase?) return '在$phrase';
    return 'Thinking';
  }

  /// What the avatar says on hover.
  String? get moodSentence => switch (mood) {
        NipaMood.waiting => '在等你回答',
        NipaMood.acting || NipaMood.thinking => doing,
        NipaMood.idle => unseen ? '有新消息' : null,
      };

  /// The step a preparation card shows running, while Nipa works.
  String? _preparing;

  /// The latest preparation Nipa showed, for the home's "正在准备" row.
  UiPreparationCard? latestPreparation;

  /// The one work the conversation's last turn settled on (a single work
  /// or episode card); candidates settle nothing.
  UiWork? get settledWork {
    final cards = turns.lastOrNull?.cards ?? const [];
    final works = <UiWork>[];
    for (final card in cards) {
      switch (card) {
        case UiCandidatesCard():
          return null;
        case UiWorkCard(:final work):
          works.add(work);
        case UiEpisodeCard(:final work):
          works.add(work);
        default:
      }
    }
    return works.map((w) => w.workId).toSet().length == 1 ? works.last : null;
  }

  // —— Under way ——

  /// What this conversation set going that is still under way, from its
  /// cards' live state; the latest first.
  List<Underway> get underway {
    final found = <Underway>[];
    final titles = <String>{};
    for (final turn in turns.reversed) {
      for (final card in turn.cards) {
        final item = Underway.of(card);
        if (item != null && titles.add(item.title)) found.add(item);
      }
    }
    return found;
  }

  // —— Cards ——

  Future<void> _refreshCards(ChatTurn turn) async {
    final id = thread, turnId = turn.id;
    if (id == null || turnId == null) return;
    final generation = _generation;
    try {
      final list = await data.cards(threadId: id, turnId: turnId);
      if (_disposed || generation != _generation) return;
      if (list.isEmpty && turn.cards.isEmpty) return;
      turn.cards = list;
      _notePreparation(list, turn.running);
      _notify();
    } catch (error) {
      debugPrint('[NextUi] cards failed: $error');
    }
  }

  Future<void> _refreshElsewhere(ChatTurn turn, String threadId) async {
    final turnId = turn.id;
    if (turnId == null) return;
    try {
      final list = await data.cards(threadId: threadId, turnId: turnId);
      if (_disposed || list.isEmpty) return;
      turn.cards = list;
      _notePreparation(list, turn.running);
      _notify();
    } catch (error) {
      debugPrint('[NextUi] cards failed: $error');
    }
  }

  void _notePreparation(List<UiCard> cards, bool running) {
    for (final card in cards.reversed) {
      if (card is UiPreparationCard) {
        latestPreparation = card;
        _preparing = running
            ? card.steps
                .where((s) => s.state == UiStepState.running)
                .map((s) => s.label)
                .lastOrNull
            : null;
        return;
      }
    }
  }

  void _refreshAll() {
    for (final t in turns) {
      if (t.cards.isNotEmpty || t.running) unawaited(_refreshCards(t));
    }
  }

  Timer? _cardsTimer;

  /// NipaPlay's data moved: cards on screen follow it (at most every
  /// 400 ms); out of sight only the running turn's.
  void _cardsChanged() {
    if (_cardsTimer != null) return;
    _cardsTimer = Timer(const Duration(milliseconds: 400), () {
      _cardsTimer = null;
      if (visible) return _refreshAll();
      if (live case final turn?) unawaited(_refreshCards(turn));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _bootTimer?.cancel();
    _cardsTimer?.cancel();
    _stopTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
