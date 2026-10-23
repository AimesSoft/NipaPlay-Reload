import 'dart:async';
import 'dart:collection';

import 'package:nipa_harness/nipa_harness.dart';

/// Who drives the process's one playback kernel.
enum KernelOwner { classic, next }

/// What happened to the lease, as reported in facts.
final class ArbiterEvent {
  ArbiterEvent(this.kind, this.owner, this.lease, this.reason)
      : at = DateTime.now().toUtc();

  /// acquired, released, evicted, violation or redirected.
  final String kind;
  final KernelOwner owner;
  final int? lease;
  final String reason;
  final DateTime at;

  JsonMap toJson() => {
        'kind': kind,
        'owner': owner.name,
        'lease': lease,
        'reason': reason,
        'at': at.toIso8601String(),
      };
}

/// The process's one playback kernel lease (player-core design §1.3, I1):
/// only its holder creates and opens a playback kernel. Taking it from the
/// other side first runs that side's evictor (its own way of closing what
/// it plays, progress saved) and waits for it to finish.
///
/// Next's session layer takes it for each session and gives it back once
/// that session's kernel is gone. Classic does not take it: while Next's
/// interface is open every Classic open is handed to Next (the redirect in
/// `VideoPlayerState.initializePlayer`), and Classic's player, if it still
/// plays when Next takes the lease, is closed by its evictor ([busy]).
final class KernelArbiter {
  KernelArbiter();

  static final instance = KernelArbiter();
  static const violationCapacity = 50;
  static const historyCapacity = 100;

  KernelLease? _lease;
  int _sequence = 0;
  Future<void> _turn = Future.value();
  final _evictors = <KernelOwner, Future<void> Function(String reason)>{};
  final _busy = <KernelOwner, bool Function()>{};
  final _violations = ListQueue<ArbiterEvent>();
  final _history = ListQueue<ArbiterEvent>();
  final _counts = <String, int>{};
  final _events = StreamController<ArbiterEvent>.broadcast(sync: true);

  KernelOwner? get owner => _lease?.owner;
  KernelLease? get lease => _lease;
  Stream<ArbiterEvent> get events => _events.stream;
  List<ArbiterEvent> get violations => List.unmodifiable(_violations);

  /// [evict] closes what [who] plays and returns once its kernel is gone.
  /// [busy] tells whether [who] plays without holding the lease (Classic
  /// in its own interface): it is closed the same way when the other side
  /// takes the lease.
  void registerEvictor(
      KernelOwner who, Future<void> Function(String reason) evict,
      {bool Function()? busy}) {
    _evictors[who] = evict;
    if (busy != null) _busy[who] = busy;
  }

  /// The lease for [who], taken from the other side if it holds it. One
  /// acquisition at a time, in the order asked.
  Future<KernelLease> acquire(KernelOwner who, {required String reason}) {
    final result = _turn.then((_) => _acquire(who, reason));
    _turn = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<KernelLease> _acquire(KernelOwner who, String reason) async {
    final held = _lease;
    if (held != null && held.owner == who) return held;
    if (held != null) {
      final evict = _evictors[held.owner];
      if (evict != null) await evict(reason);
      _emit(ArbiterEvent('evicted', held.owner, held.id, reason));
      held._held = false;
      _lease = null;
    } else {
      final other =
          who == KernelOwner.next ? KernelOwner.classic : KernelOwner.next;
      if (_busy[other]?.call() ?? false) {
        await _evictors[other]?.call(reason);
        _emit(ArbiterEvent('evicted', other, null, reason));
      }
    }
    final lease = _lease = KernelLease._(this, who, ++_sequence);
    _emit(ArbiterEvent('acquired', who, lease.id, reason));
    return lease;
  }

  void _release(KernelLease lease) {
    if (!identical(_lease, lease)) return;
    lease._held = false;
    _lease = null;
    _emit(ArbiterEvent('released', lease.owner, lease.id, 'released'));
  }

  /// [who] opened a kernel through [via]: a violation when another side
  /// holds the lease.
  void noteOpen(KernelOwner who, String via) {
    final held = _lease;
    if (held == null || held.owner == who) return;
    final violation = ArbiterEvent('violation', who, held.id, via);
    _violations.add(violation);
    while (_violations.length > violationCapacity) {
      _violations.removeFirst();
    }
    _emit(violation);
  }

  /// [from] asked to open media through [via] and was handed to the other
  /// side instead (Classic's opens while Next's interface is open).
  void noteRedirect(KernelOwner from, String via) =>
      _emit(ArbiterEvent('redirected', from, _lease?.id, via));

  void _emit(ArbiterEvent event) {
    _history.add(event);
    while (_history.length > historyCapacity) {
      _history.removeFirst();
    }
    final key = '${event.kind}:${event.owner.name}';
    _counts[key] = (_counts[key] ?? 0) + 1;
    _events.add(event);
  }

  /// The holder, the violations, how often each side acquired, released or
  /// was evicted since launch, and the latest events.
  JsonMap facts({int recent = 10}) => {
        'owner': owner?.name,
        'lease': _lease?.id,
        'violations': [for (final v in _violations) v.toJson()],
        'counts': Map.of(_counts),
        'recent': [
          for (final e in _history.toList().reversed.take(recent)) e.toJson()
        ],
      };
}

/// The right to drive the playback kernel, until [release].
final class KernelLease {
  KernelLease._(this._arbiter, this.owner, this.id);
  final KernelArbiter _arbiter;
  final KernelOwner owner;
  final int id;
  bool _held = true;
  bool get held => _held;

  /// Only once the kernel is gone (or fenced and stopped).
  Future<void> release() async => _arbiter._release(this);
}
