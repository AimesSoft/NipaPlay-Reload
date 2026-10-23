import 'package:flutter/widgets.dart';

import '../../player/next_playback.dart';

export '../../player/next_playback.dart';

/// The playback the layer below talks to: Next's, put here by the shell's
/// gate (tests and the fake world put their own).
class NextPlaybackScope extends InheritedWidget {
  const NextPlaybackScope(
      {super.key, required this.playback, required super.child});
  final NextPlayback playback;

  static NextPlayback? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NextPlaybackScope>()
      ?.playback;

  static NextPlayback of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError('No NextPlaybackScope above this widget.'));

  @override
  bool updateShouldNotify(NextPlaybackScope old) => old.playback != playback;
}

/// Rebuilds [builder] when what [selector] reads of the playback changes:
/// read again each time the controls over the video may need redrawing
/// ([NextPlayback.frame]), or as [listenable] says when given (what changes
/// rarely: [NextPlayback.transport]…). [playback] defaults to the one in
/// scope.
class PlaybackSelector<T> extends StatefulWidget {
  const PlaybackSelector({
    super.key,
    this.playback,
    this.listenable,
    required this.selector,
    required this.builder,
    this.child,
  });
  final NextPlayback? playback;
  final Listenable? listenable;
  final T Function(NextPlayback playback) selector;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  @override
  State<PlaybackSelector<T>> createState() => _PlaybackSelectorState<T>();
}

class _PlaybackSelectorState<T> extends State<PlaybackSelector<T>> {
  NextPlayback? _playback;
  Listenable? _source;
  late T _value;

  void _bind() {
    final playback = _playback = widget.playback ?? NextPlaybackScope.of(context);
    _value = widget.selector(playback);
    final source = widget.listenable ?? playback.frame;
    if (identical(source, _source)) return;
    _source?.removeListener(_changed);
    _source = source..addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(PlaybackSelector<T> old) {
    super.didUpdateWidget(old);
    _bind();
  }

  @override
  void dispose() {
    _source?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.selector(_playback!);
    if (value != _value) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);
}
