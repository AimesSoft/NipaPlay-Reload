import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/intro_skip_button.dart';

void main() {
  testWidgets(
    'skip control shows shadowed content without a visible container',
    (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: IntroSkipButton(onPressed: () => presses++)),
        ),
      );

      final button = tester.widget<TextButton>(find.byType(TextButton));
      final style = button.style!;
      expect(find.byType(OutlinedButton), findsNothing);
      expect(style.backgroundColor!.resolve({}), Colors.transparent);
      expect(
        style.overlayColor!.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      expect(
        style.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(
        style.overlayColor!.resolve({WidgetState.focused}),
        Colors.transparent,
      );
      expect(style.side!.resolve({}), BorderSide.none);
      expect(style.elevation!.resolve({}), 0);
      expect(
        style.foregroundColor!.resolve({WidgetState.focused}),
        isNot(Colors.white),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.fast_forward_rounded));
      final label = tester.widget<Text>(find.text('跳过片头'));
      expect(icon.shadows, isNotEmpty);
      expect(label.style?.shadows, isNotEmpty);

      await tester.tap(find.byType(IntroSkipButton));
      expect(presses, 1);
    },
  );

  testWidgets('skip ending uses the provided label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntroSkipButton(label: '跳过片尾', onPressed: () {}),
        ),
      ),
    );

    expect(find.text('跳过片尾'), findsOneWidget);
    expect(find.text('跳过片头'), findsNothing);
  });
}
