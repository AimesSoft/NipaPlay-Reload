import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ui_data/ui_data.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/words.dart';
import 'chat_context.dart';
import 'chat_port.dart';
import 'session_choice.dart';
import 'turn_activity.dart';

/// The home's conversation: the latest round on the stage (state B) and
/// whatever Nipa does on its own afterwards (state C). What you say here
/// always goes into the main session ([SessionChoice]), whatever the side
/// panel shows; the stage shows only its latest round.
///
/// Events come from [ChatPort.display]. Cards come from
/// [NextUiData.cards]; the agent presents them, NipaPlay resolves them.
class Conversation extends ChangeNotifier {
  Conversation(
      {required this.port, required this.data, required this.choice}) {
    _subs = [
      port.display.listen(_onEvent),
      port.questions.listen(_onQuestion),
      data.changes.listen((_) {
        _refreshCards();
        _refreshBackgroundCards();
      }),
    ];
  }

  final ChatPort port;
  final NextUiData data;
  final SessionChoice choice;
  late final List<StreamSubscription<Object?>> _subs;

  static const quietAfter = Duration(minutes: 3);
  static const idleAfter = Duration(minutes: 10);

  // —— The stage (state B) ——
  /// The stage is showing.
  bool staged = false;
  String? said;

  /// Files that went with [said].
  List<String> saidFiles = const [];
  String reply = '';

  /// Our turn is running, or waiting for the host to be free.
  bool inProgress = false;
  bool streaming = false;
  bool working = false;
  List<UiCard> cards = const [];
  ChatEvent? question;
  String? trouble;

  /// Three minutes without any event during our turn.
  bool quiet = false;

  /// What Nipa does in this round: the live line, then “想了 … · … 步”.
  TurnActivity? round;

  String? _thread, _turn;

  /// A turn of ours is being started: its first events have no turn to
  /// match yet.
  bool _expecting = false;

  /// The thread on the stage, for the panel's “展开”.
  String? get threadId => _thread;

  /// A thread whose turn the side panel started: not background work.
  bool Function(String threadId)? drivenElsewhere;

  /// A question was answered here (the panel drops its copy).
  void Function(Object requestId)? onAnswered;
  final _messages = <String, StringBuffer>{};
  String? _latestMessage;
  Timer? _idle;
  DateTime? _quietWaived;
  bool _disposed = false;

  // —— Background (state C) ——
  bool backgroundActive = false;
  String? _backgroundThread, _backgroundTurn;
  final _backgroundText = StringBuffer();
  String? _backgroundItem;
  String? _activityFromCards;

  /// Something Nipa finished while nobody was looking.
  bool unseen = false;

  /// Nipa's latest line for the home: a conclusion or a follow-up result.
  String? latestLine;

  /// The latest preparation Nipa showed, for the "正在准备" row's steps.
  UiPreparationCard? latestPreparation;

  NipaMood get mood {
    if (question != null) return NipaMood.waiting;
    if (backgroundActive || working) return NipaMood.acting;
    if (inProgress) return NipaMood.thinking;
    return NipaMood.idle;
  }

  /// What the avatar says on hover.
  String? get moodSentence => switch (mood) {
        NipaMood.waiting => '在等你回答',
        NipaMood.acting => activity ?? '在忙',
        NipaMood.thinking => '在想',
        NipaMood.idle => unseen ? '有新消息' : null,
      };

  /// What Nipa is doing in the background, as a short sentence.
  String? get activity {
    if (!backgroundActive && !working) return null;
    if (_activityFromCards != null) return _activityFromCards;
    if (backgroundActive && _backgroundText.isNotEmpty) {
      return Words.firstSentence(_backgroundText.toString());
    }
    return null;
  }

  /// Thinking dots: our turn runs and no reply text is arriving.
  bool get thinking => inProgress && !streaming && question == null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // —— Saying something ——

  /// Says [text] (with the [files] dropped on the input bar) on the home, in
  /// the main session: a new round on the stage, or more for the round
  /// still running.
  Future<void> say(String text, {List<String> files = const []}) async {
    text = text.trim();
    if (text.isEmpty && files.isEmpty) return;
    _touch();
    if (question != null) {
      if (text.isNotEmpty) await answerText(text);
      return;
    }
    final input = ChatContext.withFiles(text, files);
    final sameRound = staged && _thread != null && _thread == choice.main;
    if (sameRound && inProgress && port.busy && _turn != null) {
      said = text;
      saidFiles = files;
      _notify();
      try {
        await port.steer(input);
      } catch (error) {
        debugPrint('[NextUi] steer failed: $error');
      }
      return;
    }
    staged = true;
    said = text;
    saidFiles = files;
    _input = input;
    reply = '';
    cards = const [];
    trouble = null;
    quiet = false;
    round = TurnActivity();
    inProgress = true;
    streaming = false;
    working = false;
    _turn = null;
    _messages.clear();
    _latestMessage = null;
    _thread = null;
    _notify();
    await _start(input);
  }

  /// What went to Nipa for [said], files included, for “重新发”.
  String? _input;

  Future<void> _start(String text) async {
    if (!port.available) {
      inProgress = false;
      trouble = 'Nipa 现在不在，过一会儿再试试。';
      _notify();
      return;
    }
    try {
      while (!_disposed) {
        _thread ??= await choice.mainTarget();
        if (_thread == null) {
          await _waitUntilFree();
          continue;
        }
        // Another turn in the same session (a follow-up) goes first.
        await _waitUntilFree();
        _expecting = true;
        final response = await port.startTurn(_thread!, text);
        if (response == null) {
          _expecting = false;
          continue;
        }
        _turn = turnIdOf(response) ?? _turn;
        _expecting = false;
        break;
      }
    } catch (error) {
      debugPrint('[NextUi] turn did not start: $error');
      _expecting = false;
      inProgress = false;
      trouble = '这次没接上，再说一次试试？';
    }
    _notify();
  }

  Future<void> _waitUntilFree() async {
    while (!_disposed && port.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  /// “重新发”: stop the silent turn and say the same thing again.
  Future<void> resend() async {
    final text = _input ?? said;
    if (text == null) return;
    try {
      if (port.busy) await port.interrupt();
    } catch (error) {
      debugPrint('[NextUi] interrupt failed: $error');
    }
    await _waitUntilFree();
    quiet = false;
    reply = '';
    cards = const [];
    round = TurnActivity();
    inProgress = true;
    _notify();
    await _start(text);
  }

  /// “再等等”.
  void keepWaiting() {
    quiet = false;
    _quietWaived = DateTime.now();
    _notify();
  }

  // —— Questions ——

  List<Map<String, dynamic>> get questionItems {
    final params = question?['params'];
    final list = params is Map ? params['questions'] : null;
    return list is List ? list.whereType<Map<String, dynamic>>().toList() : [];
  }

  Future<void> answerText(String answer) async {
    final request = question;
    if (request == null) return;
    final items = questionItems;
    question = null;
    round?.endWait();
    _notify();
    try {
      await port.answer(request['id'] as Object, {
        for (final q in items) q['id'] as String: [answer],
      });
      onAnswered?.call(request['id'] as Object);
    } catch (error) {
      debugPrint('[NextUi] answer failed: $error');
    }
  }

  /// Answered in the panel.
  void dropQuestion(Object requestId) {
    if (question?['id'] != requestId) return;
    question = null;
    round?.endWait();
    _notify();
  }

  /// The panel said [text] on [threadId]. On the stage's thread the stage
  /// follows that round (a new one, or the running one steered); once the
  /// stage is gone the panel simply owns the thread.
  void followRound(String threadId, String text, {bool steer = false}) {
    if (threadId != _thread) return;
    if (!staged) {
      if (!steer) _thread = null;
      return;
    }
    _touch();
    said = text;
    saidFiles = const [];
    _input = null;
    if (!steer) {
      round = TurnActivity();
      reply = '';
      cards = const [];
      trouble = null;
      quiet = false;
      question = null;
      inProgress = true;
      streaming = false;
      working = false;
      _turn = null;
      _expecting = true;
      _messages.clear();
      _latestMessage = null;
    }
    _notify();
  }

  void _onQuestion(ChatEvent event) {
    final thread = threadIdOf(event);
    if (thread != null &&
        thread != _thread &&
        (drivenElsewhere?.call(thread) ?? false)) {
      return;
    }
    question = event;
    if (thread == _thread) round?.beginWait();
    if (!staged) unseen = true;
    _notify();
  }

  // —— Leaving the stage ——

  /// Back to state A (Esc, or ten quiet minutes). Nipa's line becomes the
  /// conclusion of this round.
  void dismiss() {
    if (!staged) return;
    staged = false;
    _idle?.cancel();
    if (!inProgress && reply.isNotEmpty) {
      latestLine = Words.firstSentence(reply);
    }
    _notify();
  }

  void markSeen() {
    if (!unseen) return;
    unseen = false;
    _notify();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(idleAfter, () {
      if (staged && !inProgress) dismiss();
    });
  }

  // —— Events ——

  void _onEvent(ChatEvent event) {
    final method = event['method'] as String? ?? '';
    final params = event['params'] is Map
        ? Map<String, dynamic>.from(event['params'] as Map)
        : const <String, dynamic>{};
    if (method == 'host/liveness') return _liveness(params);
    if (method == 'host/reasoning') {
      if (inProgress && (round?.apply(method, params) ?? false)) _notify();
      return;
    }
    if (method.startsWith('host/')) return;
    final thread = threadIdOf(event);
    final turn =
        params['turnId'] ?? (params['turn'] is Map ? params['turn']['id'] : null);
    // The stage's round. Another turn on the same session (a follow-up in
    // the main session) is background work, as anywhere else.
    final ourTurn = turn != null && turn == _turn;
    final ours = thread != null
        ? thread == _thread && (ourTurn || (_expecting && _turn == null))
        : (inProgress && (turn == null || ourTurn));
    if (ours) {
      _ours(method, params);
    } else if (thread == null || !(drivenElsewhere?.call(thread) ?? false)) {
      _background(method, params, thread);
    }
  }

  void _liveness(Map<String, dynamic> params) {
    if (!inProgress || _turn == null) return;
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

  static String? _itemType(Map<String, dynamic> params) =>
      params['item'] is Map ? params['item']['type'] as String? : null;

  static bool _isTool(String? type) => const {
        'commandExecution',
        'mcpToolCall',
        'fileChange',
        'webSearch',
      }.contains(type);

  void _ours(String method, Map<String, dynamic> params) {
    _touch();
    quiet = false;
    if (method == 'turn/started' && (round == null || !round!.running)) {
      round = TurnActivity();
    }
    final changed = round?.apply(method, params) ?? false;
    switch (method) {
      case 'turn/started':
        _turn = (params['turn'] as Map?)?['id'] as String? ?? _turn;
        _expecting = false;
        inProgress = true;
      case 'item/started':
        final type = _itemType(params);
        if (type == 'agentMessage') {
          final id = params['item']['id'] as String;
          _messages[id] = StringBuffer();
          _latestMessage = id;
        } else if (_isTool(type)) {
          working = true;
          streaming = false;
        }
      case 'item/agentMessage/delta':
        final id = params['itemId'] as String?;
        final delta = params['delta'] as String? ?? '';
        if (id == null || delta.isEmpty) break;
        (_messages[id] ??= StringBuffer()).write(delta);
        _latestMessage ??= id;
        if (id == _latestMessage) {
          reply = _messages[id].toString();
          streaming = true;
        }
      case 'item/completed':
        final type = _itemType(params);
        final item = params['item'] as Map;
        if (type == 'agentMessage') {
          final text = item['text'] as String? ?? '';
          if (text.isNotEmpty) {
            _messages[item['id'] as String] = StringBuffer(text);
            if (item['id'] == _latestMessage || _latestMessage == null) {
              reply = text;
            }
          }
          streaming = false;
        } else if (_isTool(type)) {
          working = false;
          _refreshCards();
        }
      case 'turn/completed':
        final turn = params['turn'] as Map? ?? const {};
        inProgress = false;
        streaming = false;
        working = false;
        final status = turn['status'];
        if (status == 'failed' || turn['error'] != null) {
          trouble = reply.isEmpty ? '这次没说完，再说一次试试？' : null;
        }
        if (reply.isNotEmpty && !staged) {
          latestLine = Words.firstSentence(reply);
          unseen = true;
        }
        _refreshCards();
      default:
        if (changed) _notify();
        return;
    }
    _notify();
  }

  void _background(String method, Map<String, dynamic> params, String? thread) {
    switch (method) {
      case 'turn/started':
        backgroundActive = true;
        _backgroundThread = thread;
        _backgroundTurn = (params['turn'] as Map?)?['id'] as String?;
        _backgroundText.clear();
        _backgroundItem = null;
        _activityFromCards = null;
      case 'item/started':
        if (_itemType(params) == 'agentMessage') {
          _backgroundItem = params['item']['id'] as String?;
          _backgroundText.clear();
        }
      case 'item/agentMessage/delta':
        if (params['itemId'] == _backgroundItem || _backgroundItem == null) {
          _backgroundText.write(params['delta'] as String? ?? '');
        }
      case 'item/completed':
        if (_itemType(params) == 'agentMessage') {
          final text = (params['item'] as Map)['text'] as String? ?? '';
          if (text.isNotEmpty) {
            _backgroundText
              ..clear()
              ..write(text);
          }
        } else {
          _refreshBackgroundCards();
        }
      case 'turn/completed':
        if (!backgroundActive) return;
        backgroundActive = false;
        _activityFromCards = null;
        if (_backgroundText.isNotEmpty) {
          latestLine = Words.firstSentence(_backgroundText.toString());
          unseen = true;
        }
        _refreshBackgroundCards();
      default:
        return;
    }
    _notify();
  }

  Future<void> _refreshCards() async {
    final thread = _thread;
    if (thread == null) return;
    final turn = _turn;
    try {
      final list = await data.cards(threadId: thread, turnId: turn);
      if (_disposed || thread != _thread || turn != _turn) return;
      cards = list;
      for (final card in list.reversed) {
        if (card is UiPreparationCard) {
          latestPreparation = card;
          break;
        }
      }
      _notify();
    } catch (error) {
      debugPrint('[NextUi] cards failed: $error');
    }
  }

  Future<void> _refreshBackgroundCards() async {
    final thread = _backgroundThread;
    if (thread == null) return;
    try {
      final list = await data.cards(threadId: thread, turnId: _backgroundTurn);
      if (_disposed || thread != _backgroundThread) return;
      String? running;
      for (final card in list) {
        if (card is UiPreparationCard) {
          latestPreparation = card;
          for (final step in card.steps) {
            if (step.state == UiStepState.running) running = step.label;
          }
        }
      }
      _activityFromCards = backgroundActive && running != null
          ? (running.startsWith('在') || running.startsWith('正在')
              ? running
              : '在$running')
          : null;
      _notify();
    } catch (error) {
      debugPrint('[NextUi] cards failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
