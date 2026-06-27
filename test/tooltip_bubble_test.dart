import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tooltip_bubble.dart';
import 'package:nipaplay/themes/nipaplay/widgets/ui_scale_wrapper.dart';

void main() {
  testWidgets('positions tooltip in overlay coordinates when UI is scaled',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const tooltipText = 'Scaled tooltip';
    const anchorKey = Key('tooltip-anchor');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return UiScaleWrapper(
            scale: 1.25,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 200,
                top: 500,
                child: TooltipBubble(
                  text: tooltipText,
                  showOnTop: true,
                  verticalOffset: 8,
                  child: SizedBox(
                    key: anchorKey,
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(anchorKey)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(tooltipText), findsOneWidget);

    final positionedFinder = find.ancestor(
      of: find.text(tooltipText),
      matching: find.byType(Positioned),
    );
    final tooltipPositioned = tester.widget<Positioned>(positionedFinder);

    expect(tooltipPositioned.top, isNotNull);
    expect(tooltipPositioned.top!, lessThan(500));
  });
}
