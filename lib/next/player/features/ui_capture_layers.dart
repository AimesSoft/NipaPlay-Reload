import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';

import '../../capabilities/ui_capture.dart';
import '../kernel/driver.dart';
import '../ports/session_playback.dart';
import 'kernel_features.dart';

/// The video of what plays, as the player exports it, for `ui.capture` on a
/// host where the system draws the video under the Flutter view (Metal layer,
/// platform view) and the Flutter scene has only a hole there.
///
/// Null: the scene already holds the picture (a Flutter texture), or no
/// video is shown. A [UiVideoCapture.failure] says why the video is left out.
Future<UiVideoCapture?> exportVideoLayer(SessionPlayback playback) async {
  final session = playback.session;
  if (session == null || !session.phase.value.open) return null;
  final surface = session.surface.value;
  // A Flutter texture or widget: the scene already holds the picture.
  if (surface is TextureSurface || surface is WidgetSurface) {
    return UiVideoCapture.inScene(
        surface is TextureSurface ? 'flutter_texture' : 'flutter_widget');
  }
  if (surface is! PlatformVideoSurface) return null;
  final boundary = playback.capture.sceneKey.currentContext?.findRenderObject();
  if (boundary is! RenderBox || !boundary.hasSize || !boundary.attached) {
    return const UiVideoCapture.failure(
        'The video stage is not on screen, so the video is left out.');
  }
  final driver = session.driver;
  if (driver is! KernelPictureSnapshot) {
    return const UiVideoCapture.failure(
        'The playing kernel cannot export its picture, so the video is left out.');
  }
  final media = session.media.value;
  final at = session.position;
  final KernelPicture picture;
  try {
    picture = await (driver as KernelPictureSnapshot).snapshotPicture();
  } on KernelFenced {
    return const UiVideoCapture.failure(
        'The playback ended while the picture was exported.');
  } catch (error) {
    return UiVideoCapture.failure(
        'The player could not export its picture: ${error.runtimeType}.');
  }
  final natural = media == null
      ? Size(picture.width.toDouble(), picture.height.toDouble())
      : Size(media.width.toDouble(), media.height.toDouble());
  final inside = VideoAspectGeometry.displayRect(
      mode: playback.aspectMode.value,
      viewport: boundary.size,
      sourceAspect: surface.aspect,
      naturalSize: natural);
  // Through every transform between the stage and the view (the stage may be
  // scaled or moved while the conversation is beside it).
  final onView =
      MatrixUtils.transformRect(boundary.getTransformTo(null), inside);
  return UiVideoCapture(UiVideoLayer(
      picture: picture,
      rect: onView,
      positionMs: at.inMilliseconds,
      kernel: driver.runtimeType.toString()));
}
