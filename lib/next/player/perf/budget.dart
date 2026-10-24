import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'counters.dart';

export 'counters.dart';

/// The Flutter side of [PlayerPerf]: frame timings and the rebuilds of the
/// player layer. Counting, spans and latencies live in `counters.dart`,
/// which the headless host can reach.
final class FlutterPlayerPerfFrames implements PlayerPerfFrameSource {
  FlutterPlayerPerfFrames._();
  static final instance = FlutterPlayerPerfFrames._();

  RebuildDirtyWidgetCallback? _previousRebuild;

  /// Connects frame recording and registers `ext.nipaplay.player.perf`.
  static void install() {
    PlayerPerf.frameSource = instance;
    PlayerPerf.install();
  }

  @override
  void start() {
    SchedulerBinding.instance.addTimingsCallback(_timings);
    if (kDebugMode) {
      _previousRebuild = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = _rebuilt;
    }
  }

  @override
  void stop() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    if (kDebugMode && debugOnRebuildDirtyWidget == _rebuilt) {
      debugOnRebuildDirtyWidget = _previousRebuild;
    }
    _previousRebuild = null;
  }

  void _timings(List<FrameTiming> timings) {
    for (final t in timings) {
      PlayerPerf.recordFrame(t.buildDuration, t.rasterDuration);
    }
  }

  void _rebuilt(Element element, bool builtOnce) {
    _previousRebuild?.call(element, builtOnce);
    var under = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget.runtimeType.toString() == PlayerPerf.layerType) {
        under = true;
        return false;
      }
      return true;
    });
    if (under) PlayerPerf.count('rebuild.playerLayer');
  }
}
