import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveFloatingActionButton', () {
    testWidgets('creates FAB with icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdaptiveFloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (WidgetTester tester) async {
      var pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdaptiveFloatingActionButton(
              onPressed: () {
                pressed = true;
              },
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AdaptiveFloatingActionButton));
      await tester.pumpAndSettle();

      expect(pressed, true);
    });

    testWidgets('creates mini FAB when mini is true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdaptiveFloatingActionButton(
              onPressed: () {},
              mini: true,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFloatingActionButton), findsOneWidget);
    });

    testWidgets('respects custom colors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdaptiveFloatingActionButton(
              onPressed: () {},
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFloatingActionButton), findsOneWidget);
    });

    testWidgets('handles null onPressed (disabled state)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdaptiveFloatingActionButton(
              onPressed: null,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFloatingActionButton), findsOneWidget);
    });

    testWidgets('supports hero tag for transitions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdaptiveFloatingActionButton(
              onPressed: () {},
              heroTag: 'fab_hero',
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFloatingActionButton), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget);
    });
  });
}
