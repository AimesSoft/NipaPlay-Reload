import 'package:flutter/widgets.dart';

import '../utils/video_aspect_geometry.dart';

/// Sizes the rendering surface independently from the video inside it.
class VideoSurfaceLayout extends StatelessWidget {
  const VideoSurfaceLayout({
    super.key,
    required this.mode,
    required this.sourceAspect,
    required this.handlesAspectFit,
    required this.child,
    this.naturalSize,
  });

  final VideoAspectMode mode;
  final double sourceAspect;
  final bool handlesAspectFit;
  final Size? naturalSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the surface full-size for native aspect-fit renderers. Shrinking
        // it to the video rectangle also clips their subtitles and danmaku.
        // Other aspect modes still use the host's existing placement policy.
        final size = handlesAspectFit && mode == VideoAspectMode.contain
            ? constraints.biggest
            : VideoAspectGeometry.displayRect(
                mode: mode,
                viewport: constraints.biggest,
                sourceAspect: sourceAspect,
                naturalSize: naturalSize,
              ).size;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
