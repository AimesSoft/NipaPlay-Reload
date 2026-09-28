import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';
import 'package:nipaplay/widgets/video_surface_layout.dart';

void main() {
  testWidgets('native aspect fit keeps the full surface after resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const surfaceKey = ValueKey('surface');
    for (final viewport in [const Size(400, 800), const Size(800, 400)]) {
      for (final aspect in [16 / 9, 9 / 16]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox.fromSize(
                size: viewport,
                child: VideoSurfaceLayout(
                  mode: VideoAspectMode.contain,
                  sourceAspect: aspect,
                  handlesAspectFit: true,
                  child: const SizedBox.expand(key: surfaceKey),
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byKey(surfaceKey)), viewport);
      }
    }
  });

  testWidgets('texture players and explicit aspect modes keep their geometry', (
    tester,
  ) async {
    const viewport = Size(800, 400);
    const surfaceKey = ValueKey('surface');
    for (final native in [false, true]) {
      for (final mode in VideoAspectMode.values) {
        if (native && mode == VideoAspectMode.contain) continue;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox.fromSize(
                size: viewport,
                child: VideoSurfaceLayout(
                  mode: mode,
                  sourceAspect: 4 / 3,
                  naturalSize: const Size(640, 480),
                  handlesAspectFit: native,
                  child: const SizedBox.expand(key: surfaceKey),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byKey(surfaceKey)),
          VideoAspectGeometry.displayRect(
            mode: mode,
            viewport: viewport,
            sourceAspect: 4 / 3,
            naturalSize: const Size(640, 480),
          ).size,
        );
      }
    }
  });
}
