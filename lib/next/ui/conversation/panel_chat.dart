import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ui_data/ui_data.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/words.dart';
import 'chat_context.dart';
import 'chat_port.dart';
import 'conversation.dart';
import 'next_sayings.dart';
import 'session_choice.dart';
import 'turn_activity.dart';

export 'chat_context.dart';

/// A conversation as Codex keeps it, for the panel's menu.
@immutable
final class ChatSession {
  const ChatSession(this.id, this.title, this.at);
  final String id;

  /// Its first sentence.
  final String title;

  /// Last activity.
  final DateTime? at;
}

sealed class PanelEntry {}

/// Something you said, with the work it was about and the files you
/// dropped in.
final class YouEntry extends PanelEntry {
  YouEntry(this.text,
      {this.about, this.files = const [], this.echoed = true});
  final String text;
  final String? about;
  final List<String> files;

  /// Codex has it (shown before that, as soon as you send).
  bool echoed;
}

/// One thing Nipa said.
final class NipaEntry extends PanelEntry {
  NipaEntry(this.id, this.text, {this.live = false});
  final String id;
  String text;

  /// Arrived while watching: it is revealed as it streams.
  final bool live;
}

/// What Nipa did in one turn: live while it runs (under what you said),
/// then one line above its reply; opens to the steps.
final class ActivityEntry extends PanelEntry {
  ActivityEntry(this.activity);
  final TurnActivity activity;
}

/// The cards Nipa presented in one turn, with their live state.
final class CardsEntry extends PanelEntry {
  CardsEntry(this.turnId, this.cards);
  final String turnId;
  List<UiCard> cards;
}

/// The side panel's conversation: the current session ([SessionChoice]:
/// the main one unless you picked another), its history from Codex and
/// whatever happens in it live, the list of sessions, and sending (a new
/// turn, or `steer` while one runs).
class PanelChat extends ChangeNotifier {
  PanelChat(
      {required this.port,
      required this.data,
      required this.home,
      required this.choice}) {
    _subs = [
      port.display.listen(_onEvent),
      port.questions.listen(_onQuestion),
      data.changes.listen((_) => _cardsChanged()),
    ];
    home.drivenElsewhere = (thread) => thread == _driving;
    home.onAnswered = dropQuestion;
  }

  final ChatPort port;
  final NextUiData data;

  /// The home's conversation, which shares the host and its threads.
  final Conversation home;

  /// Which session the panel and the home talk to.
  final SessionChoice choice;
  late final List<StreamSubscription<Object?>> _subs;

  static const quietAfter = Conversation.quietAfter;

  /// Turns shown when a session opens; the latest of them read their cards.
  static const historyTurns = 30;
  static const cardTurns = 12;

  // —— Sessions ——
  /// The main session first, then the others, latest first.
  List<ChatSession> sessions = const [];
  bool menuOpen = false;

  // —— The session shown ——
  /// Null: a session still to be created by the first thing you say (a new
  /// conversation, or the harness's first main session).
  String? thread;
  bool _shown = false;

  /// “问 Nipa” on this work's page: it goes along with what you say next.
  UiWork? about;
  List<PanelEntry> entries = [];
  bool loading = false;
  String? trouble;

  /// A turn runs in this session (whoever started it).
  bool running = false;
  bool streaming = false;
  bool working = false;
  bool quiet = false;
  String? _turn;
  DateTime? _quietWaived;

  bool visible = false;
  bool _disposed = false;

  /// The thread the panel started a turn on, until that turn ends.
  String? _driving;

  /// A send waits for the host to be free.
  bool _starting = false;
  String? _lastSaid, _lastInput;

  /// Bumps whenever another session is shown; late results are dropped.
  int _generation = 0;
  final _buffer = <ChatEvent>[];
  final _questions = <String, ChatEvent>{};
  final _chosen = <String, String>{};

  final _userItems = <String>{};
  Timer? _cardsTimer;

  /// Turns watched live during this run, in any session, by turn: Codex's
  /// history keeps only the messages, so their steps come from here when
  /// a session is opened again. The latest [seenTurns] are kept.
  final _seen = <String, TurnActivity>{};
  static const seenTurns = 60;

  ChatEvent? get question => thread == null ? null : _questions[thread];

  List<Map<String, dynamic>> get questionItems {
    final params = question?['params'];
    final list = params is Map ? params['questions'] : null;
    return list is List ? list.whereType<Map<String, dynamic>>().toList() : [];
  }

  /// Nipa asks for a secret: that is not typed into the conversation.
  bool get secretAsked => questionItems.any((q) => q['isSecret'] == true);

  /// Options picked so far, by question.
  Map<String, String> get chosen => _chosen;

  /// The running turn's activity.
  TurnActivity? _current;

  NipaMood get mood {
    if (question != null) return NipaMood.waiting;
    if (working) return NipaMood.acting;
    if (running) return NipaMood.thinking;
    return NipaMood.idle;
  }

  String get hint {
    if (question != null) return secretAsked ? '这里不输入密码' : '也可以直接说';
    if (about != null) return '问问《${about!.title}》';
    return entries.isEmpty ? '今天想看什么？' : '继续说…';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // —— Opening, choosing a session ——

  /// The panel opens on the current session: the main one unless you
  /// picked another. [threadId] picks that session (the home's “展开”);
  /// [about] goes along with what you say next (“问 Nipa” on its page).
  Future<void> show({String? threadId, UiWork? about}) async {
    visible = true;
    menuOpen = false;
    this.about = about;
    _notify();
    unawaited(refreshSessions());
    await choice.load();
    if (threadId != null) choice.pick(threadId);
    final want = choice.current;
    if (_shown && want == thread) {
      _refreshAllCards();
      return _notify();
    }
    if (want == null) return _showEmpty();
    return _open(want);
  }

  /// Something only the view keeps (an unfolded line) changed.
  void viewChanged() => _notify();

  void hide() {
    visible = false;
    menuOpen = false;
    _notify();
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
  /// thing you say, and it stays current until you pick another session.
  void startNew() {
    choice.startNew();
    _showEmpty();
  }

  /// A session from the menu becomes current (for the home too).
  Future<void> select(String id) {
    choice.pick(id);
    return _open(id);
  }

  /// Back to the main session (still empty when the harness has none: the
  /// next thing you say creates it).
  Future<void> selectMain() async {
    choice.backToMain();
    final id = choice.current;
    if (id == null) return _showEmpty();
    return _open(id);
  }

  void _showEmpty() {
    _generation++;
    _shown = true;
    thread = null;
    entries = [];
    loading = false;
    trouble = null;
    menuOpen = false;
    _resetLive();
    _notify();
  }

  void _resetLive() {
    running = false;
    streaming = false;
    working = false;
    quiet = false;
    _turn = null;
    _quietWaived = null;
    _buffer.clear();
    _chosen.clear();
    _userItems.clear();
    _current = null;
  }

  /// Shows [id] with its history; turns still running continue live.
  Future<void> _open(String id) async {
    final generation = ++_generation;
    _shown = true;
    thread = id;
    entries = [];
    trouble = null;
    menuOpen = false;
    loading = true;
    _resetLive();
    _notify();
    final List<(String, int)> ends;
    try {
      final history = await port.readThread(id);
      if (generation != _generation) return;
      ends = _loadHistory(history);
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
    _notify();
    await _loadHistoryCards(generation, id, ends);
  }

  /// Fills [entries] from Codex's turns. Returns, for the turns whose cards
  /// are read, where each turn's entries end.
  List<(String, int)> _loadHistory(ChatEvent history) {
    final turns = (history['turns'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final shown = turns.length > historyTurns
        ? turns.sublist(turns.length - historyTurns)
        : turns;
    final list = <PanelEntry>[];
    final ends = <(String, int)>[];
    for (var i = 0; i < shown.length; i++) {
      final turn = shown[i];
      final items = (turn['items'] as List? ?? const []).whereType<Map>();
      final said = items
          .where((item) => item['type'] == 'userMessage')
          .map((item) => _youOf(item)?.text)
          .firstOrNull;
      // “重新发” leaves a silent, interrupted attempt behind: show it once.
      if (turn['status'] == 'interrupted' &&
          !items.any((item) => item['type'] == 'agentMessage') &&
          i + 1 < shown.length &&
          said != null) {
        final next = (shown[i + 1]['items'] as List? ?? const [])
            .whereType<Map>()
            .where((item) => item['type'] == 'userMessage')
            .map((item) => _youOf(item)?.text)
            .firstOrNull;
        if (next == said) continue;
      }
      final last = i == shown.length - 1 && turn['status'] == 'inProgress';
      final activity = _seen[turn['id']] ??
          (last ? _liveFromHistory(turn) : TurnActivity.fromHistory(turn));
      var placed = false;
      void place() {
        if (placed || activity == null) return;
        list.add(ActivityEntry(activity));
        placed = true;
      }

      for (final item in items) {
        switch (item['type']) {
          case 'userMessage':
            _userItems.add('${item['id']}');
            if (_youOf(item) case final you?) list.add(you);
            place();
          case 'agentMessage':
            place();
            final text = item['text'] as String? ?? '';
            if (text.isNotEmpty) {
              list.add(NipaEntry(item['id'] as String? ?? '$i', text));
            }
        }
      }
      place();
      final id = turn['id'] as String?;
      if (id != null && i >= shown.length - cardTurns) {
        ends.add((id, list.length));
      }
      if (last) {
        running = true;
        _turn = id;
        _current = activity;
      }
    }
    entries = list;
    return ends;
  }

  /// The turn still running when the session opened: its clock goes on.
  static TurnActivity _liveFromHistory(Map turn) {
    final started = turn['startedAt'];
    final activity = TurnActivity(
        turnId: turn['id'] as String?,
        startedAt: started is num
            ? DateTime.fromMillisecondsSinceEpoch((started * 1000).round())
            : null);
    for (final item in (turn['items'] as List? ?? const []).whereType<Map>()) {
      activity.apply('item/completed', {'item': item});
    }
    return activity;
  }

  Future<void> _loadHistoryCards(
      int generation, String id, List<(String, int)> ends) async {
    try {
      final all = await Future.wait([
        for (final (turn, _) in ends) data.cards(threadId: id, turnId: turn)
      ]);
      if (generation != _generation) return;
      final list = [...entries];
      // Insert from the back so earlier positions stay valid.
      for (var i = ends.length - 1; i >= 0; i--) {
        final (turn, end) = ends[i];
        if (all[i].isEmpty || _cardsOf(turn) != null) continue;
        list.insert(end.clamp(0, list.length), CardsEntry(turn, all[i]));
      }
      entries = list;
      _notify();
    } catch (error) {
      debugPrint('[NextUi] cards failed: $error');
    }
  }

  /// Codex's threads for this harness, the main one first, then latest
  /// first.
  Future<void> refreshSessions() async {
    if (!port.available) return;
    try {
      final result = await port.listThreads();
      final list = (result['data'] as List? ?? const []).whereType<Map>();
      choice.learn(result['mainThreadId'] as String?);
      final main = choice.main;
      int rank(ChatSession s) => s.id == main ? 0 : 1;
      sessions = [
        for (final t in list)
          if (t['id'] is String)
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

  /// What you said in a user message, as it is shown: null for a turn
  /// NipaPlay started for Nipa, or when nothing was said.
  static YouEntry? _youOf(Map item) {
    final content = item['content'];
    final raw = content is List
        ? content
            .whereType<Map>()
            .where((part) => part['type'] == 'text')
            .map((part) => part['text'] as String? ?? '')
            .join()
        : '';
    if (ChatContext.isFollowup(raw)) return null;
    final text = ChatContext.strip(raw);
    final files = ChatContext.files(raw);
    if (text.isEmpty && files.isEmpty) return null;
    return YouEntry(text, about: ChatContext.aboutTitle(raw), files: files);
  }

  // —— Saying something ——

  /// Whether the input takes text now.
  bool get acceptsTyping => !(question != null && secretAsked);

  /// Files dropped into the panel, going with what you say next.
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

  /// The “关于《X》” tag's ×: what you say no longer goes with the work.
  void dropAbout() {
    about = null;
    _notify();
  }

  /// Sends [text] (and the files dropped in): an answer while Nipa asks,
  /// `steer` while this session's turn runs, otherwise a new turn (and, for
  /// a new session, its thread). While the panel is about a work, every
  /// sentence goes with it.
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
    var input = ChatContext.withFiles(text, files);
    if (about case final work?) input = ChatContext.about(input, work);
    final you =
        YouEntry(text, about: about?.title, files: files, echoed: false);
    final current = thread;
    if (current != null && running && port.busy) {
      entries = [...entries, you];
      _notify();
      home.followRound(current, text, steer: true);
      try {
        await port.steer(input);
      } catch (error) {
        debugPrint('[NextUi] steer failed: $error');
      }
      return;
    }
    _current = TurnActivity();
    entries = [...entries, you, ActivityEntry(_current!)];
    _lastSaid = text;
    _lastInput = input;
    running = true;
    streaming = false;
    working = false;
    quiet = false;
    _quietWaived = null;
    _notify();
    await _start(input, text);
  }

  Future<void> _start(String input, String text) async {
    if (!port.available) {
      running = false;
      trouble = 'Nipa 现在不在，过一会儿再试试。';
      _notify();
      return;
    }
    final generation = _generation;
    _starting = true;
    try {
      while (!_disposed && generation == _generation) {
        var target = thread;
        if (target == null) {
          target = await choice.target();
          if (target == null) {
            await _waitUntilFree();
            continue;
          }
          if (generation != _generation) return;
          thread = target;
        }
        _driving = target;
        home.followRound(target, text);
        final response = await port.startTurn(target, input);
        if (response == null) {
          _driving = null;
          await _waitUntilFree();
          continue;
        }
        if (generation == _generation) _turn = turnIdOf(response) ?? _turn;
        break;
      }
    } catch (error) {
      debugPrint('[NextUi] panel turn did not start: $error');
      _driving = null;
      if (generation == _generation) {
        running = false;
        trouble = '这次没接上，再说一次试试？';
      }
    } finally {
      _starting = false;
    }
    _notify();
    unawaited(refreshSessions());
  }

  Future<void> _waitUntilFree() async {
    while (!_disposed && port.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  /// “重新发”: stop the silent turn, then say the same again in this thread.
  Future<void> resend() async {
    if (!running) return;
    final you = entries.whereType<YouEntry>().lastOrNull;
    final text = _lastSaid ?? you?.text;
    if (text == null) return;
    final input = _lastInput ?? text;
    quiet = false;
    _quietWaived = null;
    _notify();
    try {
      if (port.busy) await port.interrupt();
    } catch (error) {
      debugPrint('[NextUi] interrupt failed: $error');
    }
    // What you said was still waiting for another turn: it goes out now.
    if (_starting) return;
    await _waitUntilFree();
    // The same words go out again; Codex echoes them once more. The silent
    // attempt's line starts over.
    you?.echoed = false;
    final line = entries.whereType<ActivityEntry>().lastOrNull;
    if (line != null) {
      _current = TurnActivity();
      entries = [
        for (final e in entries) identical(e, line) ? ActivityEntry(_current!) : e
      ];
    }
    running = true;
    trouble = null;
    _quietWaived = null;
    _notify();
    await _start(input, text);
  }

  /// “再等等”.
  void keepWaiting() {
    quiet = false;
    _quietWaived = DateTime.now();
    _notify();
  }

  // —— Questions ——

  /// An option for one question; sent once every question has one.
  Future<void> choose(String questionId, String label) async {
    _chosen[questionId] = label;
    final items = questionItems;
    if (items.every((q) => _chosen.containsKey(q['id']))) {
      return _answer({for (final q in items) q['id'] as String: [_chosen[q['id']]!]});
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

  /// The turn a question belongs to, whose clock stops while it waits.
  TurnActivity? _asking(ChatEvent request) {
    final params = request['params'];
    final turn = params is Map ? params['turnId'] as String? : null;
    return _seen[turn] ??
        (threadIdOf(request) == thread ? _current : null);
  }

  Future<void> _answer(Map<String, List<String>> answers) async {
    final request = question;
    if (request == null) return;
    _asking(request)?.endWait();
    _questions.remove(thread);
    _chosen.clear();
    _notify();
    try {
      await port.answer(request['id'] as Object, answers);
      home.dropQuestion(request['id'] as Object);
    } catch (error) {
      debugPrint('[NextUi] answer failed: $error');
    }
  }

  /// Answered on the home.
  void dropQuestion(Object requestId) {
    _questions.removeWhere((_, q) {
      if (q['id'] != requestId) return false;
      _asking(q)?.endWait();
      return true;
    });
    _notify();
  }

  void _onQuestion(ChatEvent event) {
    final target = threadIdOf(event);
    if (target == null) return;
    _questions[target] = event;
    if (target == thread) _chosen.clear();
    _asking(event)?.beginWait();
    _notify();
  }

  // —— Events ——

  void _onEvent(ChatEvent event) {
    final method = event['method'] as String? ?? '';
    if (method == 'host/liveness') {
      return _liveness(event['params'] as Map? ?? const {});
    }
    if (method == 'host/error') {
      _driving = null;
      if (running) {
        running = false;
        streaming = false;
        working = false;
        trouble = 'Nipa 现在不在，过一会儿再试试。';
        _notify();
      }
      return;
    }
    if (method == 'host/reasoning') {
      if (running && !loading && (_current?.apply(method, event['params'] as Map? ?? const {}) ?? false)) {
        _notify();
      }
      return;
    }
    if (method.startsWith('host/')) return;
    final target = threadIdOf(event);
    if (target == null) return;
    if (target != thread) {
      _watch(method, event['params'] as Map? ?? const {});
      if (method == 'turn/completed' && target == _driving) _driving = null;
      return;
    }
    if (loading) {
      _buffer.add(event);
      return;
    }
    _apply(event);
  }

  NipaEntry? _nipa(String id) {
    for (final e in entries.reversed) {
      if (e is NipaEntry && e.id == id) return e;
    }
    return null;
  }

  CardsEntry? _cardsOf(String turn) {
    for (final e in entries.reversed) {
      if (e is CardsEntry && e.turnId == turn) return e;
    }
    return null;
  }

  /// A turn reads as: what you said, what Nipa said, the cards it showed.
  /// Words arriving after the cards still go above them.
  NipaEntry _nipaOrNew(String id) {
    final found = _nipa(id);
    if (found != null) return found;
    final created = NipaEntry(id, '', live: true);
    final cards = _turn == null ? null : _cardsOf(_turn!);
    final at = cards == null ? -1 : entries.indexOf(cards);
    entries = at < 0 || entries.skip(at).any((e) => e is YouEntry)
        ? [...entries, created]
        : [...entries.take(at), created, ...entries.skip(at)];
    return created;
  }

  static String? _itemType(Map params) =>
      params['item'] is Map ? params['item']['type'] as String? : null;

  static bool _isTool(String? type) => const {
        'commandExecution',
        'mcpToolCall',
        'dynamicToolCall',
        'fileChange',
        'webSearch',
      }.contains(type);

  void _apply(ChatEvent event, {bool replay = false}) {
    final method = event['method'] as String? ?? '';
    final params = event['params'] as Map? ?? const {};
    if (method == 'turn/started') _startActivity(params);
    final changed = _current?.apply(method, params) ?? false;
    if (_current case final current? when current.turnId != null) {
      _keepSeen(current.turnId!, current);
    }
    if (method == 'turn/completed') _current = null;
    switch (method) {
      case 'turn/started':
        _turn = (params['turn'] as Map?)?['id'] as String? ?? _turn;
        running = true;
        streaming = false;
        working = false;
        quiet = false;
        trouble = null;
        _quietWaived = null;
      case 'item/started' || 'item/completed'
          when _itemType(params) == 'userMessage':
        final item = params['item'] as Map;
        if (!_userItems.add('${item['id']}')) return;
        final said = _youOf(item);
        if (said == null) return;
        final waiting = entries
            .whereType<YouEntry>()
            .where((e) =>
                !e.echoed &&
                e.text == said.text &&
                e.files.length == said.files.length)
            .firstOrNull;
        if (waiting != null) {
          waiting.echoed = true;
          return;
        }
        // Started elsewhere: the bubble goes above this turn's line.
        final line = entries.lastOrNull;
        entries = line is ActivityEntry && line.activity.running
            ? [...entries.take(entries.length - 1), said, line]
            : [...entries, said];
      case 'item/started' when _itemType(params) == 'agentMessage':
        _nipaOrNew(params['item']['id'] as String);
      case 'item/started' when _isTool(_itemType(params)):
        working = true;
        streaming = false;
      case 'item/agentMessage/delta':
        final id = params['itemId'] as String?;
        final delta = params['delta'] as String? ?? '';
        if (id == null || delta.isEmpty) return;
        final entry = _nipa(id);
        // History already holds what came before the panel looked.
        if (replay && entry != null && !entry.live) return;
        (entry ?? _nipaOrNew(id)).text += delta;
        streaming = true;
      case 'item/completed' when _itemType(params) == 'agentMessage':
        final item = params['item'] as Map;
        final text = item['text'] as String? ?? '';
        if (text.isNotEmpty) _nipaOrNew(item['id'] as String).text = text;
        streaming = false;
      case 'item/completed' when _isTool(_itemType(params)):
        working = false;
        if (_turn case final turn?) unawaited(_refreshCards(turn));
      case 'turn/completed':
        final turn = params['turn'] as Map? ?? const {};
        final id = turn['id'] as String? ?? _turn;
        running = false;
        streaming = false;
        working = false;
        quiet = false;
        if (_driving == thread) _driving = null;
        final said = entries.lastIndexWhere((e) => e is YouEntry);
        final answered =
            entries.skip(said + 1).any((e) => e is NipaEntry && e.text.isNotEmpty);
        if ((turn['status'] == 'failed' || turn['error'] != null) &&
            !answered) {
          trouble = '这次没说完，再说一次试试？';
        }
        if (id != null) unawaited(_refreshCards(id));
        unawaited(refreshSessions());
      default:
        if (changed) _notify();
        return;
    }
    _notify();
  }

  /// A turn in a session not shown: its steps, for when it is opened.
  void _watch(String method, Map params) {
    final turn = params['turnId'] as String? ??
        (params['turn'] is Map ? params['turn']['id'] as String? : null);
    if (turn == null) return;
    final activity = method == 'turn/started'
        ? _keepSeen(turn, _seen[turn] ?? TurnActivity(turnId: turn))
        : _seen[turn];
    activity?.apply(method, params);
  }

  TurnActivity _keepSeen(String turn, TurnActivity activity) {
    if (identical(_seen[turn], activity)) return activity;
    _seen[turn] = activity;
    if (_seen.length > seenTurns) _seen.remove(_seen.keys.first);
    return activity;
  }

  /// A turn starts here: the line already shown for what you just said, or
  /// a new one (the home, a follow-up).
  void _startActivity(Map params) {
    final id = (params['turn'] as Map?)?['id'] as String?;
    final current = _current;
    if (current != null && current.running && (current.turnId == null || current.turnId == id)) {
      return;
    }
    _current = TurnActivity(turnId: id);
    entries = [...entries, ActivityEntry(_current!)];
  }

  void _liveness(Map params) {
    if (!running) return;
    final turn = params['turnId'];
    if (_turn != null && turn != null && turn != _turn) return;
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

  // —— What comes next ——

  /// Two or three things you might say after Nipa's last reply, from the
  /// reply and the cards with it; empty while it works or asks.
  List<String> get nextSayings {
    if (running || loading || question != null || quiet || trouble != null) {
      return const [];
    }
    final said = entries.lastIndexWhere((e) => e is YouEntry);
    final after = entries.skip(said + 1).toList();
    final reply = after.whereType<NipaEntry>().lastOrNull?.text ?? '';
    if (reply.isEmpty) return const [];
    return NextSayings.after(reply, [
      for (final e in after.whereType<CardsEntry>()) ...e.cards,
    ]);
  }

  /// What this conversation set going that is still under way: downloads
  /// and the steps waiting after them, from its cards' live state; the
  /// latest first.
  List<Underway> get underway {
    final found = <Underway>[];
    final titles = <String>{};
    for (final entry in entries.reversed.whereType<CardsEntry>()) {
      for (final card in entry.cards) {
        final item = Underway.of(card);
        if (item != null && titles.add(item.title)) found.add(item);
      }
    }
    return found;
  }

  // —— Cards ——

  Future<void> _refreshCards(String turn) async {
    final id = thread;
    if (id == null) return;
    final generation = _generation;
    try {
      final list = await data.cards(threadId: id, turnId: turn);
      if (_disposed || generation != _generation) return;
      final existing = _cardsOf(turn);
      if (existing != null) {
        existing.cards = list;
      } else if (list.isNotEmpty) {
        entries = [...entries, CardsEntry(turn, list)];
      } else {
        return;
      }
      _notify();
    } catch (error) {
      debugPrint('[NextUi] cards failed: $error');
    }
  }

  void _refreshAllCards() {
    for (final e in entries) {
      if (e is CardsEntry) unawaited(_refreshCards(e.turnId));
    }
  }

  /// NipaPlay's data moved: cards on screen follow it (at most every
  /// 400 ms, and only while the panel is open).
  void _cardsChanged() {
    if (!visible || _cardsTimer != null) return;
    _cardsTimer = Timer(const Duration(milliseconds: 400), () {
      _cardsTimer = null;
      _refreshAllCards();
      if (running && _turn != null && _cardsOf(_turn!) == null) {
        unawaited(_refreshCards(_turn!));
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cardsTimer?.cancel();
    home.drivenElsewhere = null;
    home.onAnswered = null;
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
