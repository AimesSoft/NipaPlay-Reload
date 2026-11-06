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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Map<String, List<JsonMap>> cache;
  final Future<JsonMap> Function(String peer) request;
  final void Function() onChanged;
  final Duration baseDelay, maxDelay;
  final DateTime Function() _now;
  final _pending = <String, Future<List<JsonMap>>>{};
  final _lookedUp = <String, DateTime>{};
  final _gaps = <String, Duration>{};
  final _peerRetryAt = <String, DateTime>{};
  final _peerFailureGaps = <String, Duration>{};
  final _reached = <String>{};
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

  void reset() {
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
      } else {
        _peerRetryAt[peer] = _now().add(gap);
        _peerFailureGaps[peer] = _grow(gap);
      }
      return cache[peer] ?? const [];
    }
  }
}
