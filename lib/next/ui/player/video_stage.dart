import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'playback.dart';
import 'subtitle_layer.dart';
import '../../player/kernel/driver.dart' show PlatformVideoSurface;

/// The picture of Next's own playback layer: the kernel's surface, fitted
/// and centred on black, with the subtitle file NipaPlay draws over it
/// ([NextSubtitleLayer]), under the controls. A click plays or pauses, a
/// double click goes full screen, the pointer moving brings the controls
/// up, and the player's keys go to [host]. It reads the surface only,
/// never the kernel (I3), and rebuilds only when the surface changes.
class NextVideoStage extends StatefulWidget {
  const NextVideoStage({super.key, required this.host});
  final VideoStageHost host;

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
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF000000),
        child: MouseRegion(
          onHover: (_) => widget.host.pointerMoved(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.host.togglePlay,
            onDoubleTap: () => unawaited(widget.host.toggleFullscreen()),
            child: Stack(fit: StackFit.expand, children: [
              ValueListenableBuilder<VideoSurface?>(
                valueListenable: widget.host.surface,
                builder: (context, surface, _) => switch (surface) {
                  // The system draws it under the window: a hole for it.
                  PlatformVideoSurface(:final view) => CustomPaint(
                      painter: const _NativeVideoHole(), child: view),
                  TextureSurface(:final textureId, :final aspect) => Center(
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: RepaintBoundary(
                          child: Texture(
                              textureId: textureId,
                              filterQuality: FilterQuality.low),
                        ),
                      ),
                    ),
                  _ => const SizedBox.expand(),
                },
              ),
              // A text file NipaPlay draws over the picture; the kernel's
              // own subtitles are in the picture.
              RepaintBoundary(
                child: NextSubtitleLayer(overlay: widget.host.subtitleOverlay),
              ),
            ]),
          ),
        ),
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
