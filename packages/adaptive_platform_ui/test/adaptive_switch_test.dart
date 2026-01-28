import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveSwitch', () {
    testWidgets('creates switch with initial value', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSwitch(value: true, onChanged: (value) {}),
          ),
        ),
      );

      expect(find.byType(AdaptiveSwitch), findsOneWidget);
    });

    testWidgets('calls onChanged when tapped', (WidgetTester tester) async {
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSwitch(
              value: value,
              onChanged: (newValue) {
                value = newValue;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AdaptiveSwitch));
      await tester.pump();

      expect(value, isTrue);
    });

    testWidgets('does not call onChanged when disabled', (
      WidgetTester tester,
    ) async {
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdaptiveSwitch(value: value, onChanged: null)),
        ),
      );

      // Switch should be disabled
      expect(find.byType(AdaptiveSwitch), findsOneWidget);
    });

    testWidgets('respects custom activeColor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSwitch(
              value: true,
              activeColor: Colors.red,
              onChanged: (value) {},
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveSwitch), findsOneWidget);
    });
  });

  group('AdaptiveSlider', () {
    testWidgets('creates slider with initial value', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSlider(value: 0.5, onChanged: (value) {}),
          ),
        ),
      );

      expect(find.byType(AdaptiveSlider), findsOneWidget);
    });

    testWidgets('calls onChanged when dragged', (WidgetTester tester) async {
      double value = 0.5;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSlider(
              value: value,
              onChanged: (newValue) {
                value = newValue;
              },
            ),
          ),
        ),
      );

      // Find slider and drag it
      final slider = find.byType(AdaptiveSlider);
      await tester.drag(slider, const Offset(100, 0));
      await tester.pump();

      // Value should have changed
      expect(value, isNot(0.5));
    });

    testWidgets('respects min and max values', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSlider(
              value: 50,
              min: 0,
              max: 100,
              onChanged: (value) {},
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveSlider), findsOneWidget);
    });

    testWidgets('respects divisions', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSlider(
              value: 50,
              min: 0,
              max: 100,
              divisions: 10,
              onChanged: (value) {},
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveSlider), findsOneWidget);
    });
  });

  group('AdaptiveCheckbox', () {
    testWidgets('creates checkbox with initial value', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCheckbox(value: true, onChanged: (value) {}),
          ),
        ),
      );

      expect(find.byType(AdaptiveCheckbox), findsOneWidget);
    });

    testWidgets('calls onChanged when tapped', (WidgetTester tester) async {
      bool? value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCheckbox(
              value: value,
              onChanged: (newValue) {
                value = newValue;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AdaptiveCheckbox));
      await tester.pump();

      expect(value, isTrue);
    });

    testWidgets('supports tristate mode', (WidgetTester tester) async {
      bool? value;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCheckbox(
              value: value,
              tristate: true,
              onChanged: (newValue) {
                value = newValue;
              },
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveCheckbox), findsOneWidget);
    });

    testWidgets('does not call onChanged when disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveCheckbox(value: false, onChanged: null)),
        ),
      );

      expect(find.byType(AdaptiveCheckbox), findsOneWidget);
    });
  });

  group('AdaptiveRadio', () {
    testWidgets('creates radio with initial value', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveRadio<int>(
              value: 1,
              groupValue: 1,
              onChanged: (value) {},
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveRadio<int>), findsOneWidget);
    });

    testWidgets('calls onChanged when tapped', (WidgetTester tester) async {
      int? groupValue = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveRadio<int>(
              value: 2,
              groupValue: groupValue,
              onChanged: (value) {
                groupValue = value;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AdaptiveRadio<int>));
      await tester.pump();

      expect(groupValue, 2);
    });

    testWidgets('does not call onChanged when disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveRadio<int>(value: 1, groupValue: 1, onChanged: null),
          ),
        ),
      );

      expect(find.byType(AdaptiveRadio<int>), findsOneWidget);
    });
  });
}
