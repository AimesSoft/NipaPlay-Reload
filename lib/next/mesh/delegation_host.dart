import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nipa_harness/nipa_harness.dart';

import '../chat/delegation_chat.dart';
import '../chat/delegation_message.dart';
import '../harness_redaction.dart';

/// The methods of the delegation protocol. They are host methods of the
/// mesh, not Actions: Nipa cannot call another device's host method, only
/// the `mesh.delegate` Action on her own device does.
const delegationMethods = {
  'mesh/agent/turn',
  'mesh/agent/wait',
  'mesh/agent/interrupt',
};

final _delegationId = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

/// The longest reply sent back in one piece; the conversation itself keeps
/// all of it and says where it is.
const delegationReplyLimit = 60000;

/// Item types that are a step Nipa took (a command, a tool, a file change).
const _stepItems = {
  'commandExecution',
  'fileChange',
  'mcpToolCall',
  'dynamicToolCall',
  'collabAgentToolCall',
  'webSearch',
};

/// The receiving side of a delegation: another device's Nipa hands this
/// device's Nipa a task. A delegation opens (or continues) a conversation on
/// this device, with the sender named before the task, so the person here
/// sees it in the conversation list and 动态 and can read it and speak in it.
///
/// One delegation conversation per sending device. A new task from that
/// device continues it while it is idle; while someone is speaking in it or a
/// delegated turn is running there, the new task opens another conversation,
/// so no task waits silently behind another.
///
/// Only devices of this account reach here (the mesh admits no others); the
/// caller still names the sender, and a delegation can be waited on or
/// stopped only by the device that made it.
final class AgentDelegations {
  AgentDelegations(
      {required this.root,
      required this.chat,
      required this.unavailableReason,
      required this.deviceName,
      this.startedTasks,
      this.record});

  final Directory root;

  /// The conversation host while Nipa runs on this device; null otherwise.
  final DelegationChat? Function() chat;

  /// Why Nipa is not running here, in a sentence.
  final String? Function() unavailableReason;

  /// The name of a device of this account; null for any other.
  final String? Function(String deviceId) deviceName;

  /// Tasks started from [threadId] since [since] (their ids, types, states),
  /// as facts for the sender.
  final Future<List<JsonMap>> Function(String threadId, DateTime since)?
      startedTasks;

  /// Puts a line into 动态 for a delegation (it began; how it ended): [peer]
  /// is the sending device, [title] a short line, [facts] what happened.
  final Future<void> Function(String peer, String title, JsonMap facts)? record;

  void _note(_Tracked tracked, String title, JsonMap facts) {
    final write = record;
    if (write == null) return;
    unawaited(write(tracked.from, title, {
      'delegationId': tracked.id,
      'threadId': tracked.threadId,
      ...facts,
    }).catchError((Object _) {}));
  }

  /// The end of a delegation, said once.
  void _noteEnd(_Tracked tracked) {
    if (tracked.noted || !tracked.terminal) return;
    tracked.noted = true;
    _note(
        tracked,
        '来自 ${tracked.fromName} 的委托${switch (tracked.state) {
          'completed' => '已完成',
          'failed' => '失败了',
          _ => '被中断了',
        }}',
        {
          'state': tracked.state,
          'steps': tracked.steps,
          if (tracked.error != null) 'error': tracked.error,
          if (tracked.lastSentence != null) 'lastSentence': tracked.lastSentence,
        });
  }

  File get _file => File('${root.path}/mesh-delegations.json');
  Map<String, JsonMap>? _conversations, _delegations;
  Future<void> _serial = Future.value();
  final _tracked = <String, _Tracked>{};
  final _byThread = <String, _Tracked>{};
  DelegationChat? _listening;
  StreamSubscription<Map<String, dynamic>>? _events;
  final _random = Random.secure();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _load() async {
    if (_conversations != null) return;
    _conversations = {};
    _delegations = {};
    if (!await _file.exists()) return;
    try {
      final saved = jsonDecode(await _file.readAsString()) as Map;
      for (final entry in (saved['conversations'] as Map? ?? {}).entries) {
        _conversations![entry.key as String] =
            Map<String, Object?>.from(entry.value as Map);
      }
      for (final entry in (saved['delegations'] as Map? ?? {}).entries) {
        _delegations![entry.key as String] =
            Map<String, Object?>.from(entry.value as Map);
      }
    } on FormatException {
      // A damaged record is not a reason to refuse work; start it afresh.
    }
  }

  Future<void> _save() async {
    final delegations = _delegations!;
    if (delegations.length > 100) {
      final oldest = delegations.entries.toList()
        ..sort((a, b) => (a.value['startedAt'] as String)
            .compareTo(b.value['startedAt'] as String));
      for (final entry in oldest.take(delegations.length - 100)) {
        delegations.remove(entry.key);
      }
    }
    await root.create(recursive: true);
    final pending = File('${_file.path}.pending');
    await pending.writeAsString(
        jsonEncode({
          'conversations': _conversations,
          'delegations': delegations,
        }),
        flush: true);
    await pending.rename(_file.path);
  }

  /// The conversation host came, went or was replaced. A conversation made
  /// for a delegation is attributed to itself again, and a delegated turn
  /// that can no longer end is said to have been interrupted.
  Future<void> attach(DelegationChat? host) => _exclusive(() async {
        await _load();
        if (host == null || !host.available) {
          await _events?.cancel();
          _events = null;
          _listening = null;
          for (final tracked in _tracked.values) {
            tracked.interrupt('Nipa stopped on this device before the turn ended.');
            _noteEnd(tracked);
          }
          return;
        }
        _use(host);
      });

  void _use(DelegationChat host) {
    for (final entry in _conversations!.entries) {
      host.threadOrigins[entry.value['threadId'] as String] =
          'harness_cli:chat:delegate-${entry.value['token']}';
    }
    if (identical(_listening, host)) return;
    _events?.cancel();
    _listening = host;
    _events = host.events.listen((message) => _onEvent(host, message));
  }

  void _onEvent(DelegationChat host, Map<String, dynamic> message) {
    final params = message['params'];
    if (params is! Map) return;
    final tracked = _byThread[params['threadId']];
    if (tracked == null || tracked.terminal || tracked.completing) return;
    switch (message['method']) {
      case 'turn/started':
        tracked.turnId ??= (params['turn'] as Map?)?['id'] as String?;
      case 'item/completed':
        final item = params['item'];
        if (item is! Map) return;
        if (_stepItems.contains(item['type'])) {
          tracked.steps++;
          tracked.bump();
        } else if (item['type'] == 'agentMessage') {
          final sentence = lastSentence(item['text'] as String? ?? '');
          if (sentence != null) {
            tracked.lastSentence = sentence;
            tracked.bump();
          }
        }
      case 'turn/completed':
        final turn = params['turn'] as Map;
        if (tracked.turnId != null && turn['id'] != tracked.turnId) return;
        tracked.completing = true;
        unawaited(_complete(host, tracked, turn).catchError((Object error) {
          tracked.finish('failed', redactHarnessText('$error'));
          _noteEnd(tracked);
        }));
    }
  }

  Future<void> _complete(
      DelegationChat host, _Tracked tracked, Map turn) async {
    final status = turn['status'] as String? ?? 'completed';
    final error = (turn['error'] as Map?)?['message'] as String?;
    String? reply;
    var truncated = false;
    List<JsonMap>? tasks;
    try {
      final history = await host.readThread(tracked.threadId, withProcess: false);
      final done = (history['turns'] as List)
          .cast<Map>()
          .where((t) => t['id'] == turn['id'])
          .firstOrNull;
      if (done != null) {
        final text = [
          for (final item in (done['items'] as List).cast<Map>())
            if (item['type'] == 'agentMessage') item['text'] as String
        ].join('\n');
        final safe = redactHarnessText(text);
        truncated = safe.length > delegationReplyLimit;
        reply = truncated ? safe.substring(0, delegationReplyLimit) : safe;
      }
    } catch (_) {
      // The reply stays unread; the state is still the turn's.
    }
    try {
      tasks = await startedTasks?.call(tracked.threadId, tracked.startedAt);
    } catch (_) {}
    tracked.turnId ??= turn['id'] as String?;
    tracked.reply = reply;
    tracked.replyTruncated = truncated;
    tracked.startedTasks = tasks;
    tracked.finish(status, error == null ? null : redactHarnessText(error));
    _noteEnd(tracked);
    await _exclusive(() async {
      final record = _delegations?[tracked.id];
      if (record != null) {
        record.addAll(tracked.persisted());
        await _save();
      }
    });
  }

  /// A host method of the delegation protocol, from the authenticated
  /// device [peer].
  Future<JsonMap> handle(String method, JsonMap params, String peer) async {
    final id = params['delegationId'];
    if (id is! String || !_delegationId.hasMatch(id)) {
      throw const Failure(FailureCode.invalidInput,
          'delegationId must be 8 to 128 letters, digits, - or _.');
    }
    return switch (method) {
      'mesh/agent/turn' => _turn(id, params, peer),
      'mesh/agent/wait' => _wait(id, params, peer),
      'mesh/agent/interrupt' => _interrupt(id, peer),
      _ => throw const Failure(FailureCode.invalidInput, 'Unknown method.'),
    };
  }

  String _newToken() => List.generate(10, (_) => _random.nextInt(36))
      .map((n) => n.toRadixString(36))
      .join();

  Future<JsonMap> _turn(String id, JsonMap params, String peer) =>
      _exclusive(() async {
        final name = deviceName(peer);
        if (name == null) {
          throw const Failure(FailureCode.unavailable,
              'Only a device of this account may hand work to Nipa here.');
        }
        final text = params['text'];
        if (text is! String || text.trim().isEmpty || text.length > 200000) {
          throw const Failure(FailureCode.invalidInput,
              'text must be 1 to 200000 characters.');
        }
        final refs = params['refs'];
        if (refs != null &&
            (refs is! List || refs.length > 32 || refs.any((r) => r is! Map))) {
          throw const Failure(FailureCode.invalidInput,
              'refs must be at most 32 objects.');
        }
        await _load();
        final existing = _delegations![id];
        if (existing != null) {
          // The same task asked again (the answer was lost): what is already
          // there, not a second turn.
          if (existing['from'] != peer) {
            throw const Failure(FailureCode.conflict, 'delegationId is taken.');
          }
          return {..._open(id, peer).snapshot(), 'repeated': true};
        }
        final host = chat();
        if (host == null || !host.available) {
          throw Failure(FailureCode.unavailable,
              unavailableReason() ?? 'Nipa is not running on this device.');
        }
        _use(host);
        var threadId = _conversations![peer]?['threadId'] as String?;
        var continued = false;
        if (threadId != null) {
          if (host.busyFor(threadId)) {
            threadId = null;
          } else {
            try {
              await host.readThread(threadId, withProcess: false);
              continued = true;
            } catch (_) {
              threadId = null;
            }
          }
        }
        if (threadId == null) {
          final token = _newToken();
          threadId = await host.delegationThread(token, '来自 $name 的委托');
          _conversations![peer] = {
            'threadId': threadId,
            'token': token,
            'deviceName': name,
          };
          host.threadOrigins[threadId] = 'harness_cli:chat:delegate-$token';
        }
        final tracked = _Tracked(id, peer, threadId, fromName: name);
        _tracked[id] = tracked;
        _byThread[threadId] = tracked;
        // Recorded before the turn starts: a turn that ends at once must find
        // its record to settle.
        _delegations![id] = {
          'from': peer,
          'startedAt': tracked.startedAt.toUtc().toIso8601String(),
          ...tracked.persisted(),
        };
        final Map<String, dynamic> started;
        try {
          started = await host.startThreadTurn(
              threadId, delegationMessage(id, name, text, refs as List?));
        } catch (error) {
          _tracked.remove(id);
          _delegations!.remove(id);
          if (identical(_byThread[threadId], tracked)) _byThread.remove(threadId);
          throw Failure(FailureCode.unavailable,
              'Nipa could not take the task: ${redactHarnessText('$error')}');
        }
        tracked.turnId ??= (started['turn'] as Map?)?['id'] as String?;
        _delegations![id]!.addAll(tracked.persisted());
        await _save();
        _note(tracked, '来自 $name 的委托', {
          'conversationContinued': continued,
          'task': text.length > 200 ? '${text.substring(0, 200)}…' : text,
        });
        return {
          ...tracked.snapshot(),
          'conversationContinued': continued,
          'deviceName': name,
        };
      });

  Future<JsonMap> _wait(String id, JsonMap params, String peer) async {
    final since = params['since'] is int ? params['since'] as int : -1;
    final seconds =
        params['waitSeconds'] is int ? (params['waitSeconds'] as int).clamp(0, 55) : 0;
    final tracked = await _find(id, peer);
    await _reconcile(tracked);
    if (!tracked.terminal && tracked.version <= since && seconds > 0) {
      final changed = Completer<void>();
      tracked.waiters.add(changed);
      await changed.future.timeout(Duration(seconds: seconds), onTimeout: () {});
      tracked.waiters.remove(changed);
      await _reconcile(tracked);
    }
    return tracked.snapshot();
  }

  Future<JsonMap> _interrupt(String id, String peer) async {
    final tracked = await _find(id, peer);
    await _reconcile(tracked);
    final host = chat();
    if (!tracked.terminal &&
        host != null &&
        host.available &&
        host.busyFor(tracked.threadId)) {
      await host.interrupt(onThread: tracked.threadId);
    }
    return tracked.snapshot();
  }

  Future<_Tracked> _find(String id, String peer) => _exclusive(() async {
        await _load();
        return _open(id, peer);
      });

  /// The delegation [id] of [peer]. Call with the records loaded.
  _Tracked _open(String id, String peer) {
    final record = _delegations![id];
    if (record == null || record['from'] != peer) {
      throw const Failure(FailureCode.notFound, 'Unknown delegation.');
    }
    final live = _tracked[id];
    if (live != null) return live;
    // Known from before this run: it ended, or this host went away before it
    // could.
    final tracked = _Tracked.fromRecord(id, record);
    _tracked[id] = tracked;
    return tracked;
  }

  /// A turn the host does not report as running has ended (its event may
  /// still be on the way: the host knows before it tells) or can no longer
  /// end. The conversation says which.
  Future<void> _reconcile(_Tracked tracked) async {
    if (tracked.terminal || tracked.completing) return;
    final host = chat();
    if (host == null || !host.available) {
      tracked.interrupt('Nipa stopped on this device before the turn ended.');
      _noteEnd(tracked);
      return;
    }
    if (host.busyFor(tracked.threadId)) return;
    tracked.completing = true;
    try {
      final history = await host.readThread(tracked.threadId, withProcess: false);
      final turns = (history['turns'] as List).cast<Map>();
      final turn = tracked.turnId == null
          ? turns.lastOrNull
          : turns.where((t) => t['id'] == tracked.turnId).firstOrNull;
      if (turn != null && turn['status'] != 'inProgress') {
        await _complete(host, tracked, turn);
        return;
      }
    } catch (_) {
      // Unreadable: the turn cannot be said to be anywhere.
    }
    tracked.completing = false;
    tracked.interrupt('The turn is no longer running on this device.');
    _noteEnd(tracked);
  }
}

/// The last sentence of [text], at most 200 characters; null when it has none.
String? lastSentence(String text) {
  final parts = text
      .split(RegExp(r'[。！？!?\n]+|(?<=[.])\s'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  final sentence = redactHarnessText(parts.last);
  return sentence.length > 200 ? '${sentence.substring(0, 200)}…' : sentence;
}

final class _Tracked {
  _Tracked(this.id, this.from, this.threadId, {this.fromName = ''})
      : startedAt = DateTime.now();

  _Tracked.fromRecord(this.id, JsonMap record)
      : from = record['from'] as String,
        threadId = record['threadId'] as String,
        turnId = record['turnId'] as String?,
        startedAt = DateTime.parse(record['startedAt'] as String),
        steps = record['steps'] as int? ?? 0,
        lastSentence = record['lastSentence'] as String?,
        reply = record['reply'] as String?,
        replyTruncated = record['replyTruncated'] == true,
        error = record['error'] as String?,
        startedTasks = (record['startedTasks'] as List?)?.cast<JsonMap>(),
        state = record['state'] as String? ?? 'inProgress',
        fromName = '',
        noted = true,
        version = 1 {
    if (state == 'inProgress') {
      state = 'interrupted';
      error = 'Nipa stopped on this device before the turn ended.';
      endedAt = DateTime.now();
    } else {
      endedAt = DateTime.tryParse(record['endedAt'] as String? ?? '');
    }
  }

  final String id, from;
  final String threadId;

  /// The sending device's name, as it was when the task came.
  final String fromName;

  /// The end was put into 动态.
  bool noted = false;
  String? turnId;
  final DateTime startedAt;
  DateTime? endedAt;
  String state = 'inProgress';
  int steps = 0, version = 0;
  String? lastSentence, error, reply;
  bool replyTruncated = false, completing = false;
  List<JsonMap>? startedTasks;
  final waiters = <Completer<void>>[];

  bool get terminal => state != 'inProgress';

  void bump() {
    version++;
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    waiters.clear();
  }

  void finish(String status, String? failure) {
    if (terminal) return;
    state = status;
    error = failure;
    endedAt = DateTime.now();
    bump();
  }

  void interrupt(String why) {
    if (terminal) return;
    finish('interrupted', why);
  }

  JsonMap persisted() => {
        'threadId': threadId,
        'turnId': turnId,
        'state': state,
        'steps': steps,
        if (lastSentence != null) 'lastSentence': lastSentence,
        if (error != null) 'error': error,
        if (reply != null) 'reply': reply,
        if (replyTruncated) 'replyTruncated': true,
        if (startedTasks != null) 'startedTasks': startedTasks,
        if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
      };

  JsonMap snapshot() => {
        'delegationId': id,
        'threadId': threadId,
        'turnId': turnId,
        'state': state,
        'steps': steps,
        if (lastSentence != null) 'lastSentence': lastSentence,
        'version': version,
        'elapsedMs':
            (endedAt ?? DateTime.now()).difference(startedAt).inMilliseconds,
        if (error != null) 'error': error,
        if (terminal) ...{
          if (reply != null) 'reply': reply,
          if (replyTruncated) 'replyTruncated': true,
          if (startedTasks != null) 'startedTasks': startedTasks,
        },
      };
}
