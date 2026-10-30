import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/playback_detail_context.dart';

// What the player's menus offer and show: plain values, the same whichever
// playback is behind them.

/// One subtitle the viewer can choose; [off] turns them all off.
@immutable
final class SubtitleChoice {
  const SubtitleChoice.off({this.selected = false})
      : label = '关闭',
        index = -1,
        path = null;
  const SubtitleChoice.embedded(this.label, this.index, {this.selected = false})
      : path = null;
  const SubtitleChoice.file(this.label, String this.path,
      {this.selected = false})
      : index = -1;

  final String label;
  final bool selected;

  /// The embedded track; -1 for a file or off.
  final int index;

  /// The subtitle file; null for an embedded track or off.
  final String? path;

  bool get off => index < 0 && path == null;
}

/// One episode of what plays, in the order the player goes through them.
@immutable
final class EpisodeChoice {
  const EpisodeChoice({
    required this.title,
    this.work,
    this.progress,
    this.current = false,
    this.still,
    this.source,
  });

  final String title;

  /// The work's name, when the episode names it apart from [title].
  final String? work;

  /// 0..1 watched; null when never played.
  final double? progress;
  final bool current;

  /// A frame from where it was last watched (a local path), if any.
  final String? still;

  /// Classic's own entry, which plays it.
  final PlaybackDetailEpisode? source;
}

/// One audio track the viewer can choose.
@immutable
final class AudioChoice {
  const AudioChoice(this.label, this.index,
      {this.selected = false, this.server = false});
  final String label;
  final int index;
  final bool selected;

  /// A track of the stream a Jellyfin or Emby server transcodes, not of the
  /// file the player decodes.
  final bool server;
}

/// A setting turned on a scale: where it is and how far it goes.
@immutable
final class PlayerDial {
  const PlayerDial(this.value, this.min, this.max, this.step, this.unit);
  final double value;
  final double min;
  final double max;
  final double step;
  final DialUnit unit;

  double clamp(double v) {
    final snapped = min + ((v - min) / step).round() * step;
    return double.parse(snapped.clamp(min, max).toStringAsFixed(3));
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerDial &&
      other.value == value &&
      other.min == min &&
      other.max == max &&
      other.step == step &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(value, min, max, step, unit);
}

/// How a dial reads: 80%, 30, 1.25×, +0.5s (earlier or later), 10 秒 (a
/// length of time), 2.5.
enum DialUnit { percent, points, times, seconds, length, decimal }

/// Where on the screen danmaku of a kind run.
enum DanmakuLane { top, bottom, scroll }
