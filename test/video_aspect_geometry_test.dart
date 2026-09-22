import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';

void main() {
  const viewport = Size(1600, 900);
  const sourceAspect = 4 / 3;

  test('width and height modes use the player viewport', () {
    final width = VideoAspectGeometry.displayRect(
      mode: VideoAspectMode.fitWidth,
      viewport: viewport,
      sourceAspect: sourceAspect,
    );
    final height = VideoAspectGeometry.displayRect(
      mode: VideoAspectMode.fitHeight,
      viewport: viewport,
      sourceAspect: sourceAspect,
    );

    expect(width.width, closeTo(1600, 0.01));
    expect(width.height, closeTo(1200, 0.01));
    expect(height.width, closeTo(1200, 0.01));
    expect(height.height, closeTo(900, 0.01));

    const narrowViewport = Size(1200, 900);
    final wideVideoWidth = VideoAspectGeometry.displayRect(
      mode: VideoAspectMode.fitWidth,
      viewport: narrowViewport,
      sourceAspect: 16 / 9,
    );
    final wideVideoHeight = VideoAspectGeometry.displayRect(
      mode: VideoAspectMode.fitHeight,
      viewport: narrowViewport,
      sourceAspect: 16 / 9,
    );
    expect(wideVideoWidth.width, closeTo(1200, 0.01));
    expect(wideVideoWidth.height, closeTo(675, 0.01));
    expect(wideVideoHeight.width, closeTo(1600, 0.01));
    expect(wideVideoHeight.height, closeTo(900, 0.01));
  });

  test('only actual black bars are removed from screenshots', () {
    final contained = VideoAspectGeometry.visibleVideoRect(
      mode: VideoAspectMode.contain,
      viewport: viewport,
      sourceAspect: sourceAspect,
    );
    final filled = VideoAspectGeometry.visibleVideoRect(
      mode: VideoAspectMode.fill,
      viewport: viewport,
      sourceAspect: sourceAspect,
    );
    final covered = VideoAspectGeometry.visibleVideoRect(
      mode: VideoAspectMode.cover,
      viewport: viewport,
      sourceAspect: sourceAspect,
    );
    final forced = VideoAspectGeometry.visibleVideoRect(
      mode: VideoAspectMode.ratio16x9,
      viewport: viewport,
      sourceAspect: sourceAspect,
    );

    expect(contained.left, closeTo(200, 0.01));
    expect(contained.width, closeTo(1200, 0.01));
    expect(filled, Offset.zero & viewport);
    expect(covered, Offset.zero & viewport);
    expect(forced, Offset.zero & viewport);
  });

  test('original size and scale down have different behavior', () {
    const naturalSize = Size(1920, 1440);
    final original = VideoAspectGeometry.displayRect(
      mode: VideoAspectMode.none,
      viewport: viewport,
      sourceAspect: sourceAspect,
      naturalSize: naturalSize,
    );
    final limited = VideoAspectGeometry.displayRect(
      mode: VideoAspectMode.scaleDown,
      viewport: viewport,
      sourceAspect: sourceAspect,
      naturalSize: naturalSize,
    );

    expect(original.width, closeTo(1920, 0.01));
    expect(original.height, closeTo(1440, 0.01));
    expect(limited.width, closeTo(1200, 0.01));
    expect(limited.height, closeTo(900, 0.01));
  });
}
