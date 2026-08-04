import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_preferences.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mouse tap activates once when child also handles the tap',
      (tester) async {
    var activationCount = 0;
    void activate() => activationCount++;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NipaplayLargeScreenFocusableAction(
            onActivate: activate,
            child: GestureDetector(
              onTap: activate,
              child: const Icon(Icons.tune),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();

    expect(activationCount, 1);
  });

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

  testWidgets('non-focusable menu row leaves nested step buttons focusable',
      (tester) async {
    final decreaseFocusNode = FocusNode();
    addTearDown(decreaseFocusNode.dispose);
    var decreaseCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NipaplayLargeScreenFocusableAction(
          child: Row(
            children: [
              NipaplayLargeScreenFocusableAction(
                focusNode: decreaseFocusNode,
                onActivate: () => decreaseCount += 1,
                child: const Icon(Icons.remove),
              ),
              const Text('100%'),
            ],
          ),
        ),
      ),
    );

    decreaseFocusNode.requestFocus();
    await tester.pump();
    expect(decreaseFocusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(decreaseCount, 1);
  });

  testWidgets('vertical navigation exits large-screen text editing',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var upperActivationCount = 0;
    var lowerActivationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NipaplayLargeScreenFocusableAction(
                    autofocus: true,
                    onActivate: () => upperActivationCount += 1,
                    child: const Text('媒体库标签'),
                  ),
                  const SizedBox(height: 24),
                  NipaplayLargeScreenTextInput(
                    controller: controller,
                    hintText: '搜索媒体库',
                  ),
                  const SizedBox(height: 24),
                  NipaplayLargeScreenFocusableAction(
                    onActivate: () => lowerActivationCount += 1,
                    child: const Text('媒体卡片'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(upperActivationCount, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(lowerActivationCount, 1);
  });

  testWidgets('selected action is focused and exposes selection feedback',
      (tester) async {
    final otherFocusNode = FocusNode();
    addTearDown(otherFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              NipaplayLargeScreenFocusableAction(
                isSelected: true,
                onActivate: () {},
                child: const Text('Current sort'),
              ),
              NipaplayLargeScreenFocusableAction(
                focusNode: otherFocusNode,
                onActivate: () {},
                child: const Text('Other sort'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = find.text('Current sort');
    expect(Focus.of(tester.element(label)).hasFocus, isTrue);

    final semantics = tester.getSemantics(label);
    expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);

    otherFocusNode.requestFocus();
    await tester.pumpAndSettle();

    final selectedAction = find.ancestor(
      of: label,
      matching: find.byType(NipaplayLargeScreenFocusableAction),
    );
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(
        of: selectedAction,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final foregroundDecoration = surface.foregroundDecoration! as BoxDecoration;
    expect(decoration.color, isNot(const Color(0x08000000)));
    expect(foregroundDecoration.border!.top.color, isNot(Colors.transparent));
  });

  testWidgets('default action has no selection semantics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NipaplayLargeScreenFocusableAction(
          onActivate: () {},
          child: const Text('Regular action'),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.text('Regular action'));
    expect(semantics.flagsCollection.isSelected, ui.Tristate.none);
    expect(semantics.flagsCollection.isButton, isFalse);
  });

  testWidgets('selected action scrolls into view when initially offscreen',
      (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: ListView.builder(
              controller: scrollController,
              scrollCacheExtent: const ScrollCacheExtent.viewport(20),
              itemExtent: 60,
              itemCount: 20,
              itemBuilder: (context, index) {
                return NipaplayLargeScreenFocusableAction(
                  isSelected: index == 19,
                  onActivate: () {},
                  child: Text('Sort $index'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
    final viewport = tester.getRect(find.byType(ListView));
    final selected = tester.getRect(find.text('Sort 19'));
    expect(selected.top, greaterThanOrEqualTo(viewport.top));
    expect(selected.bottom, lessThanOrEqualTo(viewport.bottom));
  });
}
