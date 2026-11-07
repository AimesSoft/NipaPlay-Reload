import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'playback.dart';
import '../../player/danmaku/layer.dart';
import '../../player/ports/session_playback.dart';
import 'subtitle_layer.dart';
import '../widgets/television_focus.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';
import '../../player/features/capture.dart';
import '../../player/kernel/driver.dart' show PlatformVideoSurface, WidgetSurface;

/// The picture of Next's own playback layer: the kernel's surface, fitted
/// and centred on black, with the subtitle file NipaPlay draws over it
/// ([NextSubtitleLayer]), under the controls. A click plays or pauses, a
/// double click goes full screen, the pointer moving brings the controls
/// up, and the player's keys go to [host]. It reads the surface only,
/// never the kernel (I3), and rebuilds only when the surface changes.
class NextVideoStage extends StatefulWidget {
  const NextVideoStage(
      {super.key, required this.host, this.overlays = const []});
  final VideoStageHost host;
  final List<Widget> overlays;

  @override
  State<NextVideoStage> createState() => _NextVideoStageState();
}

class _NextVideoStageState extends State<NextVideoStage> {
  // A keyboard's keys (space, ←/→, ↑/↓ for the volume). A television's
  // remote sends arrows too, but there they move the focus or seek through
  // the player's own remote handling, and the volume is the television's.
  final bool _keyboard = !TelevisionFocusable.television;

  @override
  void initState() {
    super.initState();
    if (_keyboard) HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    if (_keyboard) HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  bool _key(KeyEvent event) => mounted && widget.host.key(event);

  @override
  Widget build(BuildContext context) {
    final session =
        widget.host is SessionPlayback ? widget.host as SessionPlayback : null;
    if (session?.externalHandoff?.active == true) {
      return const ColoredBox(
          color: Color(0xFF000000),
          child: Center(
              child: Text('在外部播放器中播放\n请在该播放器中控制播放',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFFFFFFF), fontSize: 16, height: 1.8))));
    }
    final scene = ColoredBox(
      color: const Color(0xFF000000),
      child: MouseRegion(
        onHover: (_) => widget.host.pointerMoved(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.host.togglePlay,
          onDoubleTap: () => unawaited(widget.host.toggleFullscreen()),
          child: ValueListenableBuilder<VideoSurface?>(
            valueListenable: widget.host.surface,
            builder: (context, surface, _) => switch (surface) {
              // The system draws it under the window: a hole for it.
              PlatformVideoSurface(:final view) =>
                CustomPaint(painter: const _NativeVideoHole(), child: view),
              WidgetSurface(
                :final view,
                :final aspect,
                :final width,
                :final height
              ) =>
                _fitted(session, aspect, width, height, view),
              TextureSurface(
                :final textureId,
                :final aspect,
                :final width,
                :final height
              ) =>
                _fitted(
                    session,
                    aspect,
                    width,
                    height,
                    Texture(
                        textureId: textureId,
                        filterQuality: FilterQuality.low)),
              _ => const SizedBox.expand(),
            },
          ),
        ),
      ),
    );
    if (session == null) {
      return Stack(fit: StackFit.expand, children: [
        scene,
        IgnorePointer(
            child: RepaintBoundary(
                child: NextSubtitleLayer(overlay: widget.host.subtitleOverlay))),
        ...widget.overlays,
      ]);
    }
    // What NipaPlay draws over the picture: the subtitle file (the kernel's
    // own subtitles are in the picture), then danmaku over it, both under
    // the controls. A capture can leave either out.
    return PlaybackCaptureScene(
        capture: session.capture,
        video: scene,
        overlays: [
          PlaybackCaptureLayer(
              capture: session.capture,
              danmaku: false,
              child: _OverPicture(
                  host: widget.host,
                  session: session,
                  child: RepaintBoundary(
                      child: NextSubtitleLayer(
                          overlay: widget.host.subtitleOverlay)))),
          PlaybackCaptureLayer(
              capture: session.capture,
              danmaku: true,
              child: _OverPicture(
                  host: widget.host,
                  session: session,
                  child: NextDanmakuLayer(playback: session))),
          ...widget.overlays,
        ]);
  }

  /// A picture the layer draws, laid out as the aspect setting says.
  Widget _fitted(SessionPlayback? session, double aspect, int width,
      int height, Widget picture) {
    if (session == null) {
      return Center(
          child: AspectRatio(
              aspectRatio: aspect, child: RepaintBoundary(child: picture)));
    }
    return ValueListenableBuilder<VideoAspectMode>(
      valueListenable: session.aspectMode,
      builder: (context, mode, _) => LayoutBuilder(builder: (context, c) {
        final rect = VideoAspectGeometry.displayRect(
            mode: mode,
            viewport: c.biggest,
            sourceAspect: aspect,
            naturalSize: Size(width.toDouble(), height.toDouble()));
        return ClipRect(
            child: Stack(children: [
          Positioned.fromRect(rect: rect, child: RepaintBoundary(child: picture))
        ]));
      }),
    );
  }
}

/// [child] over the picture as it is laid out. Upright, a phone's picture
/// is a band across the middle of the screen: subtitles and danmaku stay on
/// it, not over the bars above and below. Sideways nothing changes.
class _OverPicture extends StatelessWidget {
  const _OverPicture(
      {required this.host, required this.session, required this.child});
  final VideoStageHost host;
  final SessionPlayback session;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoSurface?>(
        valueListenable: host.surface,
        builder: (context, surface, _) {
          final (aspect, size) = switch (surface) {
            WidgetSurface(:final aspect, :final width, :final height) ||
            TextureSurface(:final aspect, :final width, :final height) =>
              (aspect, Size(width.toDouble(), height.toDouble())),
            _ => (null, Size.zero),
          };
          if (aspect == null) return child;
          return ValueListenableBuilder<VideoAspectMode>(
            valueListenable: session.aspectMode,
            builder: (context, mode, _) => LayoutBuilder(builder: (context, c) {
              final view = c.biggest;
              if (view.width >= view.height) return child;
              final rect = VideoAspectGeometry.displayRect(
                  mode: mode,
                  viewport: view,
                  sourceAspect: aspect,
                  naturalSize: size);
              final band = Rect.fromLTRB(0, math.max(0, rect.top), view.width,
                  math.min(view.height, rect.bottom));
              return Stack(children: [
                Positioned.fromRect(rect: band, child: ClipRect(child: child)),
              ]);
            }),
          );
        },
      );
}

final class _NativeVideoHole extends CustomPainter {
  const _NativeVideoHole();
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
      Offset.zero & size, Paint()..blendMode = BlendMode.clear);
  @override
  bool shouldRepaint(_NativeVideoHole oldDelegate) => false;
}
