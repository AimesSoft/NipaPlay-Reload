import 'package:nipa_harness/nipa_harness.dart';

/// Where a device with a screen is, as it last said so: in front, behind
/// another application (or the lock screen), or showing the other interface.
/// Only 'foreground' means the device can be called.
abstract final class PresenceState {
  static const foreground = 'foreground';
  static const background = 'background';
  static const classic = 'classic';
  static const all = {foreground, background, classic};
}

final class PresenceFact {
  const PresenceFact({
    required this.state,
    required this.at,
    required this.received,
    this.nowPlaying,
    this.progress,
  });

  final String state;

  /// When the device says it happened (its own clock).
  final DateTime at;

  /// When this device heard it.
  final DateTime received;
  final JsonMap? nowPlaying;
  final JsonMap? progress;

  bool get present => state == PresenceState.foreground;

  JsonMap toJson() => {
        'state': state,
        'present': present,
        'at': at.toUtc().toIso8601String(),
        'receivedAt': received.toUtc().toIso8601String(),
        if (nowPlaying != null) 'nowPlaying': nowPlaying,
        if (progress != null) 'progress': progress,
      };
}

/// The last presence fact of each other device. Unknown means present: a
/// device that never said anything (a desktop, a headless host, an older
/// build) is called as before.
final class MeshPresence {
  final _facts = <String, PresenceFact>{};

  PresenceFact? of(String device) => _facts[device];

  /// A device that last said it is not in front. Calls to it fail at once.
  bool absent(String device) => _facts[device]?.present == false;

  /// Records what a device announced. Returns false for a malformed fact or
  /// one older than what is held (messages cross, so order is by [at]).
  bool record(String device, Object? params, {DateTime? now}) {
    if (params is! Map) return false;
    final state = params['state'];
    if (state is! String || !PresenceState.all.contains(state)) return false;
    final stated = params['at'] is String
        ? DateTime.tryParse(params['at'] as String)
        : null;
    final received = now ?? DateTime.now();
    final at = stated ?? received;
    final held = _facts[device];
    if (held != null && at.isBefore(held.at)) return false;
    JsonMap? small(Object? value) {
      if (value is! Map) return null;
      final text = value.toString();
      return text.length > 2048 ? null : Map<String, Object?>.from(value);
    }

    _facts[device] = PresenceFact(
        state: state,
        at: at,
        received: received,
        nowPlaying: small(params['nowPlaying']),
        progress: small(params['progress']));
    return true;
  }

  void forget(String device) => _facts.remove(device);
  void retain(Set<String> devices) =>
      _facts.removeWhere((id, _) => !devices.contains(id));
}
