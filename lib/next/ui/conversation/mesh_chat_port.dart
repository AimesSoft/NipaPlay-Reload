import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

import '../../mesh/nipa_peers.dart';
import 'chat_port.dart';

/// The conversation with Nipa on a device that cannot run her (an iPad): a
/// conversation of the device the person chose, spoken over the mesh.
///
/// What happens in it reaches this port by one long wait on that device
/// (`mesh/chat/events`), not by asking again and again; the rest is one
/// request each way. Nothing here starts a conversation host.
final class MeshChatPort implements ChatPort {
  MeshChatPort(
      {required this.call,
      required this.hostChanges,
      required this.peers,
      this.playback,
      this.retry = const Duration(seconds: 20)}) {
    _subscriptions = [
      peers.changes.listen((_) => _choiceChanged()),
      hostChanges.listen((_) => _meshChanged()),
    ];
    unawaited(_probe());
  }

  /// A request to another device of the account (`MeshRuntime.rpc`).
  final Future<JsonMap> Function(String peer, String method, JsonMap params)
      call;

  /// The mesh says something changed (a device came or went).
  final Stream<void> hostChanges;
  final NipaPeers peers;

  /// What plays here and where (`nowPlaying`, `progress`), said with every
  /// sentence.
  final Map<String, Object?> Function()? playback;

  /// The page the person is on, said with every sentence.
  String? Function()? page;

  /// How long after the device went away it is asked again, when the mesh
  /// itself has not said it is back.
  final Duration retry;

  late final List<StreamSubscription<void>> _subscriptions;
  final _display = StreamController<ChatEvent>.broadcast();
  final _questions = StreamController<ChatEvent>.broadcast();
  final _busy = <String>{};
  bool _disposed = false;
  bool _up = false;
  String? _why;
  String? _servedBy;
  String? _epoch;
  int _sequence = 0;
  int _generation = 0;
  bool _looping = false;
  Timer? _again;
  Future<void>? _probing;

  String? get _peer => peers.chosen;

  final _notes = StreamController<void>.broadcast();

  /// Fires when [note] may have changed.
  Stream<void> get noteChanges => _notes.stream;

  bool _asked = false;

  /// What the conversation's entry says while Nipa cannot be spoken with and
  /// a device is chosen (it is not there, or Nipa is not running on it); null
  /// while she can, and before the device has been asked once.
  String? get note => _peer == null || _up || !_asked ? null : _why;

  void _noteChanged() {
    if (!_notes.isClosed) _notes.add(null);
  }

  @override
  bool get available => _up && _peer != null && _peer == _servedBy;

  @override
  Future<String?> unavailableReason() async {
    await _probe();
    return available ? null : _why ?? _missing();
  }

  String _missing() =>
      _peer == null ? '选一台设备的梨花。在设置的“梨花”里选。' : '${_name()} 现在不在。';

  String _name() => peers.chosenName ?? '那台设备';

  // ---- reaching the device

  void _choiceChanged() {
    if (_peer == _servedBy && _up) return;
    _generation++;
    _up = false;
    _asked = false;
    _servedBy = null;
    _busy.clear();
    _noteChanged();
    unawaited(_probe());
  }

  void _meshChanged() {
    if (_up || _peer == null) return;
    unawaited(_probe());
  }

  Future<void> _probe() => _probing ??= _probeNow().whenComplete(() {
        _probing = null;
      });

  Future<void> _probeNow() async {
    await peers.load();
    final peer = _peer;
    if (_disposed) return;
    if (peer == null) {
      _up = false;
      _servedBy = null;
      _why = _missing();
      _noteChanged();
      return;
    }
    try {
      final state = await call(peer, 'mesh/chat/state', {});
      if (_disposed || peer != _peer) return;
      _epoch = state['epoch'] as String?;
      _sequence = (state['sequence'] as int?) ?? 0;
      _up = true;
      _servedBy = peer;
      _why = null;
      _asked = true;
      _again?.cancel();
      _again = null;
      _noteChanged();
      unawaited(peers.refresh());
      _startListening();
    } on Failure catch (failure) {
      if (_disposed) return;
      _gone(failure);
    }
  }

  /// The device cannot be spoken with: [failure] says why.
  void _gone(Failure failure) {
    _up = false;
    _asked = true;
    _why = _reasonOf(failure);
    _noteChanged();
    _again?.cancel();
    if (_peer != null && !_disposed) {
      _again = Timer(retry, () => unawaited(_probe()));
    }
  }

  String _reasonOf(Failure failure) {
    final reason = failure.details['reason'];
    if (reason == 'not_delivered' ||
        reason == 'device_not_present' ||
        failure.message.contains('revoked or unknown') ||
        failure.message.contains('Mesh is offline')) {
      return '${_name()} 现在不在。';
    }
    if (reason == 'outcome_unknown') {
      return '${_name()} 没有回应。';
    }
    return '${_name()} 上的梨花现在不能用。';
  }

  Future<JsonMap> _call(String method, JsonMap params) async {
    final peer = _peer;
    if (peer == null) throw ChatUnavailable(_missing());
    try {
      return await call(peer, method, params);
    } on Failure catch (failure) {
      final reason = failure.details['reason'];
      final transport = reason == 'not_delivered' ||
          reason == 'outcome_unknown' ||
          reason == 'device_not_present' ||
          failure.message.contains('revoked or unknown') ||
          failure.message.contains('Mesh is offline');
      if (transport) {
        _gone(failure);
        throw ChatUnavailable(
            reason == 'outcome_unknown' && method == 'mesh/chat/turn'
                ? '${_name()} 没有回应，这句话可能已经送到了。'
                : _reasonOf(failure));
      }
      if (failure.code == FailureCode.unavailable) {
        _gone(failure);
        throw ChatUnavailable(_reasonOf(failure));
      }
      rethrow;
    }
  }

  // ---- what happens there

  void _startListening() {
    if (_looping || _disposed) return;
    _looping = true;
    unawaited(_listen(_generation));
  }

  Future<void> _listen(int generation) async {
    try {
      while (!_disposed && generation == _generation && _up) {
        final peer = _peer;
        if (peer == null) return;
        final JsonMap answer;
        try {
          answer = await call(peer, 'mesh/chat/events', {
            'after': _sequence,
            'epoch': _epoch,
            'waitSeconds': 25,
          });
        } on Failure catch (failure) {
          if (!_disposed && generation == _generation) _gone(failure);
          return;
        }
        if (_disposed || generation != _generation) return;
        _epoch = answer['epoch'] as String?;
        _sequence = (answer['sequence'] as int?) ?? _sequence;
        if (answer['reset'] == true) {
          _busy.clear();
          _display.add({'method': 'host/resync', 'params': const {}});
          continue;
        }
        for (final event in (answer['events'] as List? ?? const [])) {
          if (event is! Map) continue;
          final message = Map<String, dynamic>.from(event['message'] as Map);
          _track(message);
          (event['question'] == true ? _questions : _display).add(message);
        }
      }
    } finally {
      _looping = false;
      // The device went away while it was said to be there: ask again later.
      if (!_disposed && generation == _generation && !_up) {
        _again ??= Timer(retry, () => unawaited(_probe()));
      }
    }
  }

  void _track(ChatEvent message) {
    final params = message['params'];
    if (params is! Map) return;
    final thread = params['threadId'];
    if (thread is! String) return;
    switch (message['method']) {
      case 'turn/started':
        _busy.add(thread);
      case 'turn/completed':
        _busy.remove(thread);
    }
  }

  // ---- ChatPort

  @override
  bool get busy => _busy.isNotEmpty;

  @override
  bool busyOn(String threadId) => _busy.contains(threadId);

  @override
  Stream<ChatEvent> get display => _display.stream;

  @override
  Stream<ChatEvent> get questions => _questions.stream;

  @override
  Future<String?> mainThread() async =>
      (await _call('mesh/chat/open', {}))['threadId'] as String;

  @override
  Future<String?> newThread() async =>
      (await _call('mesh/chat/open', {'new': true}))['threadId'] as String;

  @override
  Future<ChatEvent> listThreads({String? cursor}) =>
      _call('mesh/chat/threads', {});

  @override
  Future<String?> switchThread(String threadId) async => threadId;

  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    try {
      final started = await _call('mesh/chat/turn', {
        'threadId': threadId,
        'text': text,
        'context': {
          if (page?.call() case final page?) 'page': page,
          ...?playback?.call(),
        },
      });
      _track({
        'method': 'turn/started',
        'params': {'threadId': threadId}
      });
      return started;
    } on Failure catch (failure) {
      // A turn is running there: this one waits for it.
      if (failure.code == FailureCode.conflict) return null;
      rethrow;
    }
  }

  @override
  Future<void> steer(String text, {String? threadId}) async {
    if (threadId == null) return;
    await _call('mesh/chat/steer', {'threadId': threadId, 'text': text});
  }

  @override
  Future<ChatEvent> readThread(String threadId) async {
    final answer = await _call('mesh/chat/read', {'threadId': threadId});
    if (answer['busy'] == true) {
      _busy.add(threadId);
    } else {
      _busy.remove(threadId);
    }
    return Map<String, dynamic>.from(answer['thread'] as Map);
  }

  @override
  Future<void> interrupt({String? threadId}) async {
    if (threadId == null) return;
    await _call('mesh/chat/interrupt', {'threadId': threadId});
  }

  @override
  Future<void> answer(
      Object requestId, Map<String, List<String>> answers) async {
    await _call(
        'mesh/chat/answer', {'requestId': requestId, 'answers': answers});
  }

  @override
  void dispose() {
    _disposed = true;
    _again?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _display.close();
    _questions.close();
    _notes.close();
  }
}
