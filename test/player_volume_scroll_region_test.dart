import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/player_volume_scroll_region.dart';

void main() {
  Future<void> scroll(
    WidgetTester tester,
    Offset delta, {
    int milliseconds = 0,
  }) async {
    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(100, 100),
      scrollDelta: delta,
      timeStamp: Duration(milliseconds: milliseconds),
    ));
    await tester.pump();
  }

  Future<void> buildRegion(
    WidgetTester tester, {
    required ValueChanged<double> onVolumeChange,
    bool Function()? isEnabled,
    Widget? child,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: PlayerVolumeScrollRegion(
          isEnabled: isEnabled ?? () => true,
          onVolumeChange: onVolumeChange,
          child: child ?? const ColoredBox(color: Colors.black),
        ),
      ));

  testWidgets('wheel up increases volume and wheel down decreases it',
      (tester) async {
    final changes = <double>[];
    await buildRegion(tester, onVolumeChange: changes.add);

    await scroll(tester, const Offset(0, -20));
    await scroll(tester, const Offset(0, 40));
    await scroll(tester, const Offset(0, -100));
    await scroll(tester, const Offset(20, 0));
    await scroll(tester, const Offset(30, -10));

    expect(changes, [0.05, -0.05, 0.05]);
  });

  testWidgets('precision deltas accumulate and a new gesture drops old residue',
      (tester) async {
    final changes = <double>[];
    await buildRegion(tester, onVolumeChange: changes.add);

    await scroll(tester, const Offset(0, -8), milliseconds: 0);
    await scroll(tester, const Offset(0, -7), milliseconds: 10);
    expect(changes, isEmpty);
    await scroll(tester, const Offset(0, -8), milliseconds: 20);
    expect(changes, [0.05]);

    // The remaining -3 pixels must not leak into a later gesture.
    await scroll(tester, const Offset(0, -17), milliseconds: 1000);
    expect(changes, [0.05]);
    // Reversing direction starts from zero, rather than cancelling -17 first.
    await scroll(tester, const Offset(0, 20), milliseconds: 1010);
    expect(changes, [0.05, -0.05]);
  });

  testWidgets('a disabled player or open menu ignores input without a rebuild',
      (tester) async {
    final changes = <double>[];
    var enabled = true;
    await buildRegion(
      tester,
      isEnabled: () => enabled,
      onVolumeChange: changes.add,
    );

    await scroll(tester, const Offset(0, -10));
    enabled = false;
    await scroll(tester, const Offset(0, -20));
    expect(changes, isEmpty);

    enabled = true;
    await scroll(tester, const Offset(0, -10));
    expect(changes, isEmpty);
    await scroll(tester, const Offset(0, -10));
    expect(changes, [0.05]);
  });

  testWidgets('nested settings lists scroll without also changing volume',
      (tester) async {
    final changes = <double>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await buildRegion(
      tester,
      onVolumeChange: changes.add,
      child: ListView.builder(
        controller: controller,
        itemCount: 100,
        itemExtent: 40,
        itemBuilder: (_, index) => Text('Setting $index'),
      ),
    );

    await scroll(tester, const Offset(0, 40));
    expect(controller.offset, 40);
    expect(changes, isEmpty);
  });
}
