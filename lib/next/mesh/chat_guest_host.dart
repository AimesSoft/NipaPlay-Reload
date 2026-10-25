import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nipa_harness/nipa_harness.dart';

import '../chat/guest_chat.dart';
import '../harness_redaction.dart';

/// The methods of the guest conversation protocol: a device that cannot run
/// Nipa (an iPad) speaks with the Nipa of another device. Host methods of the
/// mesh, not Actions: Nipa cannot call another device's host method.
const chatGuestMethods = {
  'mesh/chat/state',
  'mesh/chat/threads',
  'mesh/chat/open',
  'mesh/chat/read',
  'mesh/chat/turn',
  'mesh/chat/steer',
  'mesh/chat/interrupt',
  'mesh/chat/answer',
  'mesh/chat/events',
};

final _threadIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

/// The most the events of one answer may weigh, well under the frame limit.
const chatEventsBudget = 600 * 1024;

/// The longest the events call waits for something to happen.
const chatEventsWaitLimit = 55;

/// Older events than this many are dropped; the guest reads the thread again.
const chatEventsKept = 4000;

/// The receiving side of a guest's conversation: the Nipa of this device,
/// seen from a device that cannot run her.
///
/// A guest's conversations are conversations of this device like any other:
/// they are in its conversation list and 动态, the person here can read them
/// and speak in them, and what Nipa does in them is attributed to them. Each
/// is named for its guest (“来自 iPad 的对话”), and every sentence the guest
/// says carries, after it, where the guest said it (the device, its page, what
/// plays) as the guest reported it.
///
/// What happens in a guest's conversation is pushed to it by one long wait
/// (`mesh/chat/events`): the call returns as soon as something happened, or
/// after at most [chatEventsWaitLimit] seconds, and the guest asks again from
/// where it was. Nothing is read from a database to find out.
///
/// Only devices of this account reach here; a guest speaks only in the
/// conversations it opened.
final class ChatGuests {
  ChatGuests(
      {required this.root,
      required this.chat,
      required this.unavailableReason,
      required this.deviceName,
      this.record});

  final Directory root;

  /// The conversation host while Nipa runs on this device; null otherwise.
  final GuestChat? Function() chat;

  /// Why Nipa is not running here, in a sentence.
  final String? Function() unavailableReason;

  /// The name of a device of this account; null for any other.
  final String? Function(String deviceId) deviceName;

  /// Puts a line into 动态 (a guest began a conversation).
  final Future<void> Function(String peer, String title, JsonMap facts)? record;

  File get _file => File('${root.path}/mesh-chat-guests.json');
  Map<String, JsonMap>? _peers;
  Future<void> _serial = Future.value();
  GuestChat? _listening;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _random = Random.secure();

  /// Told apart from the numbering of an earlier run of this host.
  final epoch = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final _log = <_Entry>[];
  var _sequence = 0;
  final _waiters = <Completer<void>>[];
  // A question the guest's thread asks, by request id, until answered.
  final _questions = <Object, String>{};

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _load() async {
    if (_peers != null) return;
    _peers = {};
    if (!await _file.exists()) return;
    try {
      final saved = jsonDecode(await _file.readAsString()) as Map;
      for (final entry in (saved['peers'] as Map? ?? {}).entries) {
        _peers![entry.key as String] =
            Map<String, Object?>.from(entry.value as Map);
      }
    } on FormatException {
      // A damaged record is not a reason to refuse a guest; start afresh.
    }
  }

  Future<void> _save() async {
    await root.create(recursive: true);
    final pending = File('${_file.path}.pending');
    await pending.writeAsString(jsonEncode({'peers': _peers}), flush: true);
    await pending.rename(_file.path);
  }

  List<JsonMap> _threadsOf(String peer) =>
      ((_peers![peer]?['threads'] as List?) ?? const [])
          .map((t) => Map<String, Object?>.from(t as Map))
          .toList();

  String? _ownerOf(String threadId) {
    for (final entry in _peers!.entries) {
      for (final thread in entry.value['threads'] as List? ?? const []) {
        if ((thread as Map)['threadId'] == threadId) return entry.key;
      }
    }
    return null;
  }

  /// The conversation host came, went or was replaced.
  Future<void> attach(GuestChat? host) => _exclusive(() async {
        await _load();
        if (host == null || !host.available) {
          for (final subscription in _subscriptions) {
            await subscription.cancel();
          }
          _subscriptions.clear();
          _listening = null;
          _questions.clear();
          _wake();
          return;
        }
        _use(host);
      });

  void _use(GuestChat host) {
    for (final entry in _peers!.entries) {
      for (final thread in entry.value['threads'] as List? ?? const []) {
        host.threadOrigins[(thread as Map)['threadId'] as String] =
            'harness_cli:chat:delegate-${thread['token']}';
      }
    }
    if (identical(_listening, host)) return;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _listening = host;
    _subscriptions
      ..add(host.threadDisplay.listen((m) => _observe(m, question: false)))
      ..add(host.userInputRequests.listen((m) => _observe(m, question: true)));
  }

  void _observe(Map<String, dynamic> message, {required bool question}) {
    final params = message['params'];
    final threadId = params is Map ? params['threadId'] : null;
    if (threadId is! String || _peers == null) return;
    final owner = _ownerOf(threadId);
    if (owner == null) return;
    if (question && message['id'] != null) {
      _questions[message['id'] as Object] = threadId;
    }
    _log.add(_Entry(++_sequence, owner, threadId, question, message));
    if (_log.length > chatEventsKept) {
      _log.removeRange(0, _log.length - chatEventsKept);
    }
    _wake();
  }

  void _wake() {
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiters.clear();
  }

  /// Waits for the completions still writing (shutdown).
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _wake();
    await _serial;
  }

  /// A host method of the protocol, from the authenticated device [peer].
  Future<JsonMap> handle(String method, JsonMap params, String peer) async {
    final name = deviceName(peer);
    if (name == null) {
      throw const Failure(FailureCode.unavailable,
          'Only a device of this account may speak with Nipa here.');
    }
    await _exclusive(_load);
    if (method == 'mesh/chat/events') return _events(params, peer);
    final host = _running();
    return switch (method) {
      'mesh/chat/state' => _state(host),
      'mesh/chat/threads' => _threads(host, peer),
      'mesh/chat/open' => _open(host, params, peer, name),
      'mesh/chat/read' => _read(host, params, peer),
      'mesh/chat/turn' => _turn(host, params, peer, name),
      'mesh/chat/steer' => _steer(host, params, peer),
      'mesh/chat/interrupt' => _interrupt(host, params, peer),
      'mesh/chat/answer' => _answer(host, params, peer),
      _ => throw const Failure(FailureCode.invalidInput, 'Unknown method.'),
    };
  }

  GuestChat _running() {
    final host = chat();
    if (host == null || !host.available) {
      throw Failure(FailureCode.unavailable,
          unavailableReason() ?? 'Nipa is not running on this device.');
    }
    _use(host);
    return host;
  }

  /// What the guest needs to know before it speaks: whether Nipa is here.
  JsonMap _state(GuestChat host) => {
        'runs': true,
        'model': host.model,
        'epoch': epoch,
        'sequence': _sequence,
      };

  String _thread(JsonMap params, String peer) {
    final id = params['threadId'];
    if (id is! String || !_threadIdPattern.hasMatch(id)) {
      throw const Failure(FailureCode.invalidInput, 'threadId is not valid.');
    }
    if (_ownerOf(id) != peer) {
      throw const Failure(
          FailureCode.notFound, 'This conversation is not this device\'s.');
    }
    return id;
  }

  Future<JsonMap> _threads(GuestChat host, String peer) async {
    final mine = {for (final t in _threadsOf(peer)) t['threadId'] as String};
    final listed = await host.listSessions(limit: 100);
    final main = _peers![peer]?['main'] as String?;
    return {
      'epoch': epoch,
      'mainThreadId': main,
      'data': [
        for (final item in (listed['data'] as List? ?? const []))
          if (item is Map && mine.contains(item['id']))
            {
              'id': item['id'],
              if (item['preview'] != null) 'preview': item['preview'],
              if (item['updatedAt'] != null) 'updatedAt': item['updatedAt'],
              if (item['createdAt'] != null) 'createdAt': item['createdAt'],
            }
      ],
    };
  }

  String _newToken() =>
      'ipad-${List.generate(10, (_) => _random.nextInt(36)).map((n) => n.toRadixString(36)).join()}';

  /// The guest's main conversation, or (with `new`) another one.
  Future<JsonMap> _open(
          GuestChat host, JsonMap params, String peer, String name) =>
      _exclusive(() async {
        final fresh = params['new'] == true;
        final record =
            _peers!.putIfAbsent(peer, () => {'threads': <Object?>[]});
        final main = record['main'] as String?;
        if (!fresh && main != null) {
          try {
            await host.readThread(main, withProcess: false);
            return {'threadId': main, 'epoch': epoch};
          } catch (_) {
            // Gone from the runtime: a new main one takes its place.
          }
        }
        final token = _newToken();
        final id = await host.delegationThread(token, '来自 $name 的对话');
        host.threadOrigins[id] = 'harness_cli:chat:delegate-$token';
        final threads = _threadsOf(peer)
          ..add({'threadId': id, 'token': token, 'deviceName': name});
        if (threads.length > 50) threads.removeRange(0, threads.length - 50);
        record['threads'] = threads;
        if (!fresh || main == null) record['main'] = id;
        await _save();
        final write = this.record;
        if (write != null) {
          unawaited(write(peer, '$name 开了一段对话', {
            'threadId': id,
            'deviceId': peer,
          }).catchError((Object _) {}));
        }
        return {'threadId': id, 'epoch': epoch, 'created': true};
      });

  Future<JsonMap> _read(GuestChat host, JsonMap params, String peer) async {
    final id = _thread(params, peer);
    final turns =
        params['turns'] is int ? (params['turns'] as int).clamp(1, 200) : 30;
    final history = Map<String, dynamic>.from(await redactHarnessJsonOffMain(
        await host.readThread(id, withProcess: false)) as Map);
    await host.restoreProcess(id, history);
    var list = (history['turns'] as List? ?? const []).toList();
    if (list.length > turns) list = list.sublist(list.length - turns);
    // Whole turns, newest first kept, until the answer fits the frame.
    var size = 0;
    final kept = <Object?>[];
    for (final turn in list.reversed) {
      final weight = jsonEncode(turn).length;
      if (kept.isNotEmpty && size + weight > chatEventsBudget) break;
      size += weight;
      kept.add(turn);
    }
    history['turns'] = kept.reversed.toList();
    return {
      'thread': history,
      'epoch': epoch,
      'sequence': _sequence,
      'busy': host.busyFor(id),
    };
  }

  /// What the guest says, and where it said it. The line after the sentence
  /// is what the interface adds to every message (it is taken off again where
  /// the message is shown); it says only what the guest reported.
  static String sentence(
      String text, String name, String peer, Object? context) {
    final facts = <String>[];
    if (context is Map) {
      final page = context['page'];
      if (page is String && page.isNotEmpty) facts.add('页面：$page');
      final playing = context['nowPlaying'];
      if (playing is Map) {
        final work = playing['work'];
        final episode = playing['episode'];
        if (work is String) {
          facts.add('在播放《$work》${episode is String ? ' $episode' : ''}');
        }
        if (playing['paused'] == true) facts.add('已暂停');
      }
      final progress = context['progress'];
      if (progress is Map && progress['durationMs'] is int) {
        facts.add('位置 ${_clock(progress['positionMs'])} / '
            '${_clock(progress['durationMs'])}');
      }
    }
    final where = facts.isEmpty ? '' : '（${facts.join('；')}）';
    return '$text\n\n[NipaPlay 界面] 这句话是在「$name」的对话面板里说的$where。'
        '设备 ID：$peer。以上是 $name 自己报告的。';
  }

  static String _clock(Object? milliseconds) {
    final s = milliseconds is int ? milliseconds ~/ 1000 : 0;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  Future<JsonMap> _turn(
      GuestChat host, JsonMap params, String peer, String name) async {
    final id = _thread(params, peer);
    final text = params['text'];
    if (text is! String || text.trim().isEmpty || text.length > 200000) {
      throw const Failure(
          FailureCode.invalidInput, 'text must be 1 to 200000 characters.');
    }
    if (host.busyFor(id)) {
      throw const Failure(FailureCode.conflict,
          'A turn is running in this conversation; say it as more for that turn.');
    }
    try {
      final started = await host.startThreadTurn(
          id, sentence(text.trimRight(), name, peer, params['context']));
      return {...started, 'epoch': epoch};
    } catch (error) {
      throw Failure(FailureCode.unavailable,
          'Nipa could not take it: ${redactHarnessText('$error')}');
    }
  }

  Future<JsonMap> _steer(GuestChat host, JsonMap params, String peer) async {
    final id = _thread(params, peer);
    final text = params['text'];
    if (text is! String || text.trim().isEmpty || text.length > 200000) {
      throw const Failure(
          FailureCode.invalidInput, 'text must be 1 to 200000 characters.');
    }
    if (!host.busyFor(id)) {
      throw const Failure(
          FailureCode.conflict, 'No turn is running in this conversation.');
    }
    try {
      await host.steer(text, onThread: id);
    } catch (error) {
      throw Failure(FailureCode.unavailable,
          'Nipa could not take it: ${redactHarnessText('$error')}');
    }
    return {'accepted': true};
  }

  Future<JsonMap> _interrupt(
      GuestChat host, JsonMap params, String peer) async {
    final id = _thread(params, peer);
    if (host.busyFor(id)) await host.interrupt(onThread: id);
    return {'accepted': true};
  }

  Future<JsonMap> _answer(GuestChat host, JsonMap params, String peer) async {
    final request = params['requestId'];
    final answers = params['answers'];
    final thread = request == null ? null : _questions[request];
    if (request == null ||
        thread == null ||
        _ownerOf(thread) != peer ||
        answers is! Map) {
      throw const Failure(FailureCode.notFound, 'No such question.');
    }
    await host.answerUserInput(request, {
      for (final entry in answers.entries)
        '${entry.key}': [for (final a in entry.value as List) '$a'],
    });
    _questions.remove(request);
    return {'accepted': true};
  }

  /// What happened in the guest's conversations after [after], waiting up to
  /// `waitSeconds` for something when nothing has yet. `reset` says the
  /// events the guest has not seen are gone (this host started again, or too
  /// much happened): it reads its conversation again.
  Future<JsonMap> _events(JsonMap params, String peer) async {
    final after = params['after'] is int ? params['after'] as int : 0;
    final seconds = params['waitSeconds'] is int
        ? (params['waitSeconds'] as int).clamp(0, chatEventsWaitLimit)
        : 0;
    final known = params['epoch'];
    final stale = known != null && known != epoch;
    JsonMap collect() {
      final oldest = _log.isEmpty ? _sequence + 1 : _log.first.sequence;
      final lost = stale || after + 1 < oldest;
      if (lost) {
        return {
          'epoch': epoch,
          'sequence': _sequence,
          'reset': true,
          'events': <Object?>[],
        };
      }
      var size = 0;
      var last = after;
      final events = <JsonMap>[];
      for (final entry in _log) {
        if (entry.sequence <= after) continue;
        if (entry.owner != peer) {
          last = entry.sequence;
          continue;
        }
        final wire = {
          'seq': entry.sequence,
          'question': entry.question,
          'message': entry.message,
        };
        final weight = jsonEncode(wire).length;
        if (events.isNotEmpty && size + weight > chatEventsBudget) break;
        size += weight;
        events.add(wire);
        last = entry.sequence;
      }
      // Entries for other guests are passed over, so the guest does not meet
      // them again.
      final more = last < _sequence;
      return {
        'epoch': epoch,
        'sequence': last,
        'events': events,
        'more': more && events.isNotEmpty,
      };
    }

    var result = collect();
    final empty = (result['events'] as List).isEmpty && result['reset'] != true;
    if (empty && seconds > 0) {
      final changed = Completer<void>();
      _waiters.add(changed);
      await changed.future
          .timeout(Duration(seconds: seconds), onTimeout: () {});
      _waiters.remove(changed);
      result = collect();
    }
    return result;
  }
}

final class _Entry {
  _Entry(this.sequence, this.owner, this.threadId, this.question, this.message);
  final int sequence;
  final String owner, threadId;
  final bool question;
  final Map<String, dynamic> message;
}
