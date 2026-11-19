import 'package:nipa_harness/nipa_harness.dart';

/// When a task's bytes were last seen to grow, and how long since: the
/// `health` facts `download.stalled` is decided from. Only bytes that grow
/// are progress; a report, a keepalive or a read of the same count is not.
///
/// Kept in memory, as the engines' own counters are: time without progress
/// restarts with the process (from its first observation), and a task that
/// is removed is forgotten.
final class ProgressObservations {
  final _byKey = <String,
      ({
    DateTime since,
    DateTime? lastProgress,
    int bytes,
    DateTime at,
    int previousBytes
  })>{};
  final _keyOfHandle = <String, String>{};

  /// Observes [bytes] for the task [handle] (its engine session) whose
  /// identity across sessions is [key] (info hash and output), at [now].
  JsonMap observe(String handle, String key, int bytes, {DateTime? now}) {
    now ??= DateTime.now().toUtc();
    final previous = _byKey[key];
    final observation = (
      since: previous?.since ?? now,
      lastProgress:
          previous != null && bytes > previous.bytes ? now : previous?.lastProgress,
      bytes: bytes,
      at: now,
      previousBytes: previous?.bytes ?? bytes
    );
    _byKey[key] = observation;
    final before = _keyOfHandle[handle];
    if (before != null && before != key) _byKey.remove(before);
    _keyOfHandle[handle] = key;
    return {
      'observedAt': now.toIso8601String(),
      'observingSince': observation.since.toIso8601String(),
      'lastProgressAt': observation.lastProgress?.toIso8601String(),
      'secondsWithoutProgress': now
          .difference(observation.lastProgress ?? observation.since)
          .inSeconds,
      'sampleSeconds': previous == null
          ? 0
          : now.difference(previous.at).inMilliseconds / 1000,
      'checkedBytesChange': bytes - observation.previousBytes,
    };
  }

  /// The task [handle] was removed.
  void forget(String handle) {
    final key = _keyOfHandle.remove(handle);
    if (key != null) _byKey.remove(key);
  }

  int get length => _byKey.length;
}

/// The peer counts librqbit's live snapshot has (null where it has none).
JsonMap peerHealth(Object? stats) {
  final peers = (((stats as Map?)?['live'] as Map?)?['snapshot']
      as Map?)?['peer_stats'] as Map?;
  return {
    'connectedPeers': peers?['live'],
    'seenPeers': peers?['seen'],
    'connectingPeers': peers?['connecting'],
    'queuedPeers': peers?['queued'],
    'deadPeers': peers?['dead'],
  };
}
