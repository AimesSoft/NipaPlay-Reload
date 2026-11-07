import 'dart:async';

import '../system/foreground.dart';

/// Push peers have no timer. Only peers which did not advertise push get a
/// foreground-only compatibility refresh, at most once a minute.
final class CatalogueUpdates {
  CatalogueUpdates(this.refresh, {this.onError});
  final Future<void> Function(Set<String>? peers) refresh;
  final void Function(Object, StackTrace)? onError;
  final _legacy = <String>{};
  final _push = <String>{};
  StreamSubscription<bool>? _foreground;
  Timer? _timer;
  bool _closed = false, _running = false, _all = false;
  final _pending = <String>{};

  void start() {
    if (_closed || _foreground != null) return;
    _foreground = NextForeground.changes.listen((active) {
      _schedule();
      if (active) changed();
    });
    _schedule();
  }

  void peer(String id, {required bool push}) {
    if (push) {
      _legacy.remove(id);
      _push.add(id);
    } else {
      _push.remove(id);
      _legacy.add(id);
    }
    _schedule();
  }

  void retain(Set<String> ids) {
    _legacy.retainAll(ids);
    _push.retainAll(ids);
    _schedule();
  }

  void failed(String id) {
    // A network failure does not revoke an already negotiated push protocol.
    if (!_push.contains(id)) peer(id, push: false);
  }

  void _schedule() {
    if (_closed || !NextForeground.active || _legacy.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      NextRefreshMetrics.record('mesh.legacy.periodic');
      changed(peers: Set.of(_legacy));
    });
  }

  /// Changes arriving during a refresh get another delivery, rather than
  /// disappearing into the in-flight future.
  void changed({Set<String>? peers}) {
    if (_closed) return;
    if (peers == null) {
      _all = true;
    } else {
      _pending.addAll(peers);
    }
    if (_running || _foreground == null || !NextForeground.active) return;
    _running = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (!_closed &&
          _foreground != null &&
          NextForeground.active &&
          (_all || _pending.isNotEmpty)) {
        final peers = _all ? null : Set<String>.of(_pending);
        _all = false;
        _pending.clear();
        try {
          NextRefreshMetrics.record('mesh.refresh');
          await refresh(peers);
        } catch (error, stack) {
          onError?.call(error, stack);
        }
      }
    } finally {
      _running = false;
    }
  }

  bool get polling => _timer != null;
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _foreground?.cancel();
    _foreground = null;
    _all = false;
    _pending.clear();
  }

  Future<void> close() async {
    _closed = true;
    await stop();
  }
}
