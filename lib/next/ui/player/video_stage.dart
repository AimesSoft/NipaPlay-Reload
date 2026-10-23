import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'playback.dart';
import '../../player/danmaku/layer.dart';
import '../../player/ports/session_playback.dart';
import 'subtitle_layer.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';
import '../../player/features/capture.dart';

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
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
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
              TextureSurface(
                :final textureId,
                :final aspect,
                :final width,
                :final height
              ) =>
                session == null
                    ? Center(
                        child: AspectRatio(
                            aspectRatio: aspect,
                            child: RepaintBoundary(
                                child: Texture(
                                    textureId: textureId,
                                    filterQuality: FilterQuality.low))))
                    : ValueListenableBuilder<VideoAspectMode>(
                        valueListenable: session.aspectMode,
                        builder: (context, mode, _) =>
                            LayoutBuilder(builder: (context, c) {
                          final rect = VideoAspectGeometry.displayRect(
                              mode: mode,
                              viewport: c.biggest,
                              sourceAspect: aspect,
                              naturalSize:
                                  Size(width.toDouble(), height.toDouble()));
                          return ClipRect(
                              child: Stack(children: [
                            Positioned.fromRect(
                                rect: rect,
                                child: RepaintBoundary(
                                    child: Texture(
                                        textureId: textureId,
                                        filterQuality: FilterQuality.low)))
                          ]));
                        }),
                      ),
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
              child: RepaintBoundary(
                  child:
                      NextSubtitleLayer(overlay: widget.host.subtitleOverlay))),
          PlaybackCaptureLayer(
              capture: session.capture,
              danmaku: true,
              child: NextDanmakuLayer(playback: session)),
          ...widget.overlays,
        ]);
  }
}
