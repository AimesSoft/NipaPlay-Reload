import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shadow_action_button.dart';

void main() {
  testWidgets('tap and long press invoke separate screenshot actions',
      (tester) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ShadowActionButton(
          icon: Icons.camera_alt_outlined,
          onPressed: () => taps++,
          onLongPress: () => longPresses++,
        ),
      ),
    ));

    await tester.tap(find.byType(ShadowActionButton));
    await tester.pump();
    expect(taps, 1);
    expect(longPresses, 0);

    await tester.longPress(find.byType(ShadowActionButton));
    await tester.pump();
    expect(taps, 1);
    expect(longPresses, 1);
  });
}
