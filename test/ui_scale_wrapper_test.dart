import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/ui_scale_wrapper.dart';

void main() {
  for (final scale in [0.5, 0.75, 1.0, 1.3]) {
    testWidgets(
        'scale $scale fills the screen and keeps edge controls clickable',
        (tester) async {
      const screen = Size(960, 540);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Size? viewport;
      Size? mediaSize;
      var taps = 0;
      const buttonKey = Key('bottom-right-action');
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => UiScaleWrapper(
          scale: scale,
          child: child!,
        ),
        home: LayoutBuilder(builder: (context, constraints) {
          viewport = constraints.biggest;
          mediaSize = MediaQuery.sizeOf(context);
          return Stack(children: [
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                key: buttonKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 80, height: 40),
              ),
            ),
          ]);
        }),
      ));

      expect(viewport!.width, closeTo(screen.width / scale, 0.001));
      expect(viewport!.height, closeTo(screen.height / scale, 0.001));
      expect(mediaSize, viewport);
      final corner = tester.getBottomRight(find.byKey(buttonKey));
      expect(corner.dx, closeTo(screen.width, 0.001));
      expect(corner.dy, closeTo(screen.height, 0.001));
      await tester.tapAt(const Offset(959, 539));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
