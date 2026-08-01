import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('television layout can default on without overriding a saved choice',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    expect(
      await LargeScreenModePreferences.load(defaultValue: true),
      isTrue,
    );

    SharedPreferences.setMockInitialValues(
      const {LargeScreenModePreferences.key: false},
    );
    expect(
      await LargeScreenModePreferences.load(defaultValue: true),
      isFalse,
    );
  });

  testWidgets('hover scaling keeps every button surface unscaled',
      (tester) async {
    final previousHighlightStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() {
      FocusManager.instance.highlightStrategy = previousHighlightStrategy;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 220,
            height: 56,
            child: NipaplayLargeScreenFocusableAction(
              onActivate: () {},
              focusScale: 1.1,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const Row(
                children: [
                  Icon(Icons.settings),
                  SizedBox(width: 8),
                  Text('设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final hoverRegion = tester.widget<MouseRegion>(
      find.descendant(
        of: find.byType(FocusableActionDetector),
        matching: find.byType(MouseRegion),
      ),
    );
    hoverRegion.onEnter?.call(const PointerEnterEvent());
    await tester.pumpAndSettle();

    final contentScale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(AnimatedContainer),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(contentScale.scale, 1.1);
    expect(
      find.ancestor(
        of: find.byType(AnimatedContainer),
        matching: find.byType(AnimatedScale),
      ),
      findsNothing,
    );
  });

  testWidgets('remote select activates the focused large-screen action',
      (tester) async {
    var activationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NipaplayLargeScreenFocusableAction(
            autofocus: true,
            onActivate: () => activationCount += 1,
            child: const Text('播放'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(activationCount, 1);
  });
}
