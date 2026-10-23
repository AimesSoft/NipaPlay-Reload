import 'package:flutter/foundation.dart';

/// The playback layer's monotonic time.
abstract final class PlayerTime {
  static final _watch = Stopwatch()..start();
  static Duration now() => _watch.elapsed;
}

/// Where the video is, extrapolated from an anchor: what the time line,
/// the time and the facts read, never the kernel. Listeners are told only
/// at a discontinuity (a seek, play or pause, another rate, a drift past
/// [driftLimit]), not as the time moves.
abstract interface class PlaybackClockView implements Listenable {
  /// Where the video is now: pure arithmetic, no native call.
  Duration now();
  bool get advancing;
  double get rate;
}

/// The anchor of a session's position (player-core design §1.3).
final class PlaybackClock extends ChangeNotifier implements PlaybackClockView {
  PlaybackClock({Duration position = Duration.zero})
      : _position = position,
        _at = PlayerTime.now();

  /// A sample this far from the extrapolation re-anchors the clock and is
  /// told to listeners.
  static const driftLimit = Duration(milliseconds: 40);

  Duration _position;
  Duration _at;
  double _rate = 1;
  bool _advancing = false;
  Duration? _limit;
  String _source = 'seek_target';

  Duration get anchorPosition => _position;
  Duration get anchorAt => _at;

  /// What the anchor was taken from: kernel_sample, seek_target, seek_landed…
  String get source => _source;
  @override
  double get rate => _rate;
  @override
  bool get advancing => _advancing;

  /// The end of the media, once known; the clock does not run past it.
  set limit(Duration? limit) => _limit = limit;

  @override
  Duration now() {
    if (!_advancing) return _position;
    final run = (PlayerTime.now() - _at) * _rate;
    final at = _position + run;
    final limit = _limit;
    return limit != null && limit > Duration.zero && at > limit ? limit : at;
  }

  /// Puts the anchor at [position]. Notifies when this is a discontinuity
  /// rather than the same course.
  void anchor(Duration position,
      {required bool advancing, double? rate, required String source}) {
    final nextRate = rate ?? _rate;
    final drift = (now() - position).abs();
    final jump = advancing != _advancing ||
        nextRate != _rate ||
        drift > driftLimit ||
        (!advancing && position != _position);
    _position = position;
    _at = PlayerTime.now();
    _rate = nextRate;
    _advancing = advancing;
    _source = source;
    if (jump) notifyListeners();
  }
}
