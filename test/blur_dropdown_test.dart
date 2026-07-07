import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/ui_scale_wrapper.dart';

void main() {
  testWidgets('positions dropdown in overlay coordinates when UI is scaled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dropdownKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return UiScaleWrapper(
            scale: 1.25,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 200,
                top: 120,
                child: BlurDropdown<String>(
                  dropdownKey: dropdownKey,
                  items: [
                    DropdownMenuItemData(
                      title: 'One',
                      value: 'one',
                      isSelected: true,
                    ),
                    DropdownMenuItemData(title: 'Two', value: 'two'),
                  ],
                  onItemSelected: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('One'));
    await tester.pump();

    expect(find.text('Two'), findsOneWidget);

    final renderBox =
        dropdownKey.currentContext!.findRenderObject()! as RenderBox;
    final overlayBox = tester.renderObject<RenderBox>(find.byType(Overlay));
    final anchorPosition = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final positionedFinder = find.ancestor(
      of: find.text('Two'),
      matching: find.byType(Positioned),
    );
    final dropdownPositioned = tester.widget<Positioned>(positionedFinder);

    expect(
      dropdownPositioned.top,
      closeTo(anchorPosition.dy + renderBox.size.height + 5, 1),
    );
    expect(
      dropdownPositioned.right,
      closeTo(
        overlayBox.size.width - anchorPosition.dx - renderBox.size.width,
        1,
      ),
    );
  });
}
