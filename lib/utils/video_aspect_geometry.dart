import 'dart:ui';
import 'dart:math' as math;

/// How the video frame is placed inside the player viewport.
enum VideoAspectMode {
  contain,
  cover,
  fill,
  fitWidth,
  fitHeight,
  none,
  scaleDown,
  ratio16x9,
  ratio4x3,
}

/// The same placement is used by the player and by screenshot black-bar crop.
class VideoAspectGeometry {
  const VideoAspectGeometry._();

  static Rect displayRect({
    required VideoAspectMode mode,
    required Size viewport,
    required double sourceAspect,
    Size? naturalSize,
  }) {
    if (viewport.isEmpty) return Rect.zero;
    final aspect = sourceAspect > 0 ? sourceAspect : 16 / 9;
    final stageAspect = viewport.width / viewport.height;
    final fittedWidth =
        stageAspect > aspect ? viewport.height * aspect : viewport.width;
    final fittedHeight =
        stageAspect > aspect ? viewport.height : viewport.width / aspect;

    double width;
    double height;
    switch (mode) {
      case VideoAspectMode.fill:
        width = viewport.width;
        height = viewport.height;
        break;
      case VideoAspectMode.cover:
        final scale = stageAspect > aspect
            ? viewport.width / fittedWidth
            : viewport.height / fittedHeight;
        width = fittedWidth * scale;
        height = fittedHeight * scale;
        break;
      case VideoAspectMode.fitWidth:
        width = viewport.width;
        height = width / aspect;
        break;
      case VideoAspectMode.fitHeight:
        height = viewport.height;
        width = height * aspect;
        break;
      case VideoAspectMode.ratio16x9:
      case VideoAspectMode.ratio4x3:
        final forcedAspect = mode == VideoAspectMode.ratio16x9 ? 16 / 9 : 4 / 3;
        width = stageAspect > forcedAspect
            ? viewport.height * forcedAspect
            : viewport.width;
        height = width / forcedAspect;
        break;
      case VideoAspectMode.none:
      case VideoAspectMode.scaleDown:
        if (naturalSize == null || naturalSize.isEmpty) {
          width = fittedWidth;
          height = fittedHeight;
        } else {
          width = naturalSize.width;
          height = width / aspect;
          if (mode == VideoAspectMode.scaleDown) {
            final scale = math.min(
              1.0,
              math.min(viewport.width / width, viewport.height / height),
            );
            width *= scale;
            height *= scale;
          }
        }
        break;
      case VideoAspectMode.contain:
        width = fittedWidth;
        height = fittedHeight;
        break;
    }

    return Rect.fromCenter(
      center: viewport.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  static Rect visibleVideoRect({
    required VideoAspectMode mode,
    required Size viewport,
    required double sourceAspect,
    Size? naturalSize,
  }) {
    final frame = displayRect(
      mode: mode,
      viewport: viewport,
      sourceAspect: sourceAspect,
      naturalSize: naturalSize,
    );
    return frame.intersect(Offset.zero & viewport);
  }
}
