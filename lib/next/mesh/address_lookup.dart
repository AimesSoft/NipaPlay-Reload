import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:nipa_harness/nipa_harness.dart';

/// Address reads have their own retry budget, independent of local reports.
/// Cached routes remain usable while the coordinator is unavailable.
final class MeshAddressLookup {
  MeshAddressLookup({
    required this.cache,
    required this.request,
    required this.onChanged,
    required this.baseDelay,
    required this.maxDelay,
    this.onCooldownEnded,
    DateTime Function()? now,
    Timer Function(Duration delay, void Function() callback)? schedule,
  })  : _now = now ?? DateTime.now,
        _schedule = schedule ?? Timer.new;

  final Map<String, List<JsonMap>> cache;
  final Future<JsonMap> Function(String peer) request;
  final void Function() onChanged;

  /// A shared cooldown (a 429, an unavailable coordinator) has run out.
  /// Nothing else asks again by itself when the reports themselves succeed
  /// all along (#1101); this is told once per cooldown, so that what is
  /// waiting for an address asks for it.
  final void Function()? onCooldownEnded;
  final Timer Function(Duration delay, void Function() callback) _schedule;
  Timer? _cooldown;
  final Duration baseDelay, maxDelay;
  final DateTime Function() _now;
  final _pending = <String, Future<List<JsonMap>>>{};
  final _lookedUp = <String, DateTime>{};
  final _gaps = <String, Duration>{};
  final _peerRetryAt = <String, DateTime>{};
  final _peerFailureGaps = <String, Duration>{};
  final _reached = <String>{};
  final _peerFailures = <String, Failure>{};
  DateTime? retryAt;
  Failure? failure;
  Duration? _failureGap;
  int _generation = 0;

  Duration _grow(Duration gap) => Duration(
      milliseconds: min(gap.inMilliseconds * 2, maxDelay.inMilliseconds));

  void reached(String peer) => _reached.add(peer);

  /// Forget stale successful answers, but never bypass a server cooldown.
  void refresh(Iterable<String> peers) {
    for (final peer in peers) {
      _lookedUp.remove(peer);
      _gaps.remove(peer);
    }
  }

  /// A successful control request proves transport recovery, but says
  /// nothing about an address-query quota or an authentication refusal.
  void coordinatorReached() {
    if (failure?.retryable == true && failure?.details['httpStatus'] != 429) {
      retryAt = null;
      failure = null;
      _failureGap = null;
    }
  }

  void _armCooldown() {
    final until = retryAt;
    if (until == null || onCooldownEnded == null) return;
    _cooldown?.cancel();
    final wait = until.difference(_now());
    _cooldown = _schedule(wait.isNegative ? Duration.zero : wait, () {
      _cooldown = null;
      final again = retryAt;
      // Lengthened while waiting (a later 429): wait for that instead.
      if (again != null && _now().isBefore(again)) return _armCooldown();
      onCooldownEnded!();
    });
  }

  /// What is known of [peer]'s address, for diagnostics: how many routes
  /// are cached and since when, and when and why it is next asked for.
  JsonMap peerFacts(String peer) {
    final now = _now();
    final shared =
        retryAt != null && now.isBefore(retryAt!) ? retryAt : null;
    final own = _peerRetryAt[peer] != null && now.isBefore(_peerRetryAt[peer]!)
        ? _peerRetryAt[peer]
        : null;
    final next = own == null || (shared != null && shared.isAfter(own))
        ? shared
        : own;
    final why = own != null ? _peerFailures[peer] : (shared != null ? failure : null);
    return {
      'cachedRoutes': cache[peer]?.length ?? 0,
      'cachedAt': _lookedUp[peer]?.toUtc().toIso8601String(),
      if (next != null) 'retryAt': next.toUtc().toIso8601String(),
      if (why != null) 'error': why.toJson(),
    };
  }

  void reset() {
    _cooldown?.cancel();
    _cooldown = null;
    _peerFailures.clear();
    _generation++;
    _pending.clear();
    _lookedUp.clear();
    _gaps.clear();
    _peerRetryAt.clear();
    _peerFailureGaps.clear();
    _reached.clear();
    retryAt = null;
    failure = null;
    _failureGap = null;
  }

  Future<List<JsonMap>> resolve(String peer) {
    if (_pending[peer] case final pending?) return pending;
    final now = _now();
    final cached = cache[peer] ?? const <JsonMap>[];
    if ((retryAt != null && now.isBefore(retryAt!)) ||
        (_peerRetryAt[peer] != null && now.isBefore(_peerRetryAt[peer]!))) {
      return Future.value(cached);
    }
    final last = _lookedUp[peer];
    if (last != null &&
        !_reached.contains(peer) &&
        now.difference(last) < (_gaps[peer] ?? baseDelay)) {
      return Future.value(cached);
    }
    late final Future<List<JsonMap>> work;
    work = _fetch(peer, _generation).whenComplete(() {
      if (identical(_pending[peer], work)) _pending.remove(peer);
    });
    _pending[peer] = work;
    return work;
  }

  Future<List<JsonMap>> _fetch(String peer, int generation) async {
    try {
      final response = await request(peer);
      if (generation != _generation) return cache[peer] ?? const [];
      final list = (response['candidates'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      final unchanged = cache.containsKey(peer) &&
          jsonEncode(cache[peer]) == jsonEncode(list);
      _gaps[peer] = unchanged && !_reached.contains(peer)
          ? _grow(_gaps[peer] ?? baseDelay)
          : baseDelay;
      _reached.remove(peer);
      _peerRetryAt.remove(peer);
      _peerFailureGaps.remove(peer);
      _peerFailures.remove(peer);
      cache[peer] = list;
      _lookedUp[peer] = _now();
      // An unrelated in-flight read can succeed after another read got 429.
      // Its success must not erase that shared cooldown.
      if (retryAt == null || !_now().isBefore(retryAt!)) {
        retryAt = null;
        failure = null;
        _failureGap = null;
      }
      onChanged();
      return list;
    } on Failure catch (error) {
      if (generation != _generation) return cache[peer] ?? const [];
      final shared = error.retryable ||
          const [401, 403].contains(error.details['httpStatus']);
      var gap = shared
          ? (_failureGap ?? baseDelay)
          : (_peerFailureGaps[peer] ?? baseDelay);
      final seconds = error.details['retryAfterSeconds'];
      if (seconds is int && seconds > gap.inSeconds) {
        gap = Duration(seconds: seconds);
      }
      if (shared) {
        final until = _now().add(gap);
        if (retryAt == null || until.isAfter(retryAt!)) retryAt = until;
        failure = error;
        _failureGap = _grow(gap);
        _armCooldown();
      } else {
        _peerRetryAt[peer] = _now().add(gap);
        _peerFailureGaps[peer] = _grow(gap);
        _peerFailures[peer] = error;
      }
      return cache[peer] ?? const [];
    }
  }
}
