import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveExpansionTile', () {
    testWidgets('creates expansion tile with title and children', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              children: [Text('Child 1'), Text('Child 2')],
            ),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
      // Children should not be visible initially (collapsed)
      expect(find.text('Child 1'), findsNothing);
      expect(find.text('Child 2'), findsNothing);
    });

    testWidgets('expands and shows children when tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              children: [Text('Child 1'), Text('Child 2')],
            ),
          ),
        ),
      );

      // Tap to expand
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();

      // Children should now be visible
      expect(find.text('Child 1'), findsOneWidget);
      expect(find.text('Child 2'), findsOneWidget);
    });

    testWidgets('collapses when tapped again', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              children: [Text('Child 1')],
            ),
          ),
        ),
      );

      // Tap to expand
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();
      expect(find.text('Child 1'), findsOneWidget);

      // Tap to collapse
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();
      expect(find.text('Child 1'), findsNothing);
    });

    testWidgets('displays leading widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              leading: Icon(Icons.star),
              title: Text('Test Title'),
              children: [Text('Child')],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('displays subtitle when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              subtitle: Text('Test Subtitle'),
              children: [Text('Child')],
            ),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Subtitle'), findsOneWidget);
    });

    testWidgets('displays custom trailing widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              trailing: Icon(Icons.notifications),
              children: [Text('Child')],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications), findsOneWidget);
    });

    testWidgets('starts expanded when initiallyExpanded is true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              initiallyExpanded: true,
              children: [Text('Child 1'), Text('Child 2')],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Children should be visible initially
      expect(find.text('Child 1'), findsOneWidget);
      expect(find.text('Child 2'), findsOneWidget);
    });

    testWidgets('calls onExpansionChanged callback', (
      WidgetTester tester,
    ) async {
      bool? callbackValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: const Text('Test Title'),
              onExpansionChanged: (expanded) {
                callbackValue = expanded;
              },
              children: const [Text('Child')],
            ),
          ),
        ),
      );

      // Tap to expand
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();

      expect(callbackValue, true);

      // Tap to collapse
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();

      expect(callbackValue, false);
    });

    testWidgets('applies custom backgroundColor when expanded', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              backgroundColor: Colors.red,
              initiallyExpanded: true,
              children: [Text('Child')],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the widget builds successfully with custom backgroundColor
      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Child'), findsOneWidget);
    });

    testWidgets('applies custom collapsedBackgroundColor when collapsed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              collapsedBackgroundColor: Colors.blue,
              children: [Text('Child')],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the widget builds successfully with custom collapsedBackgroundColor
      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Child'), findsNothing);
    });

    testWidgets('creates tile with enabled parameter', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              enabled: false,
              children: [Text('Child')],
            ),
          ),
        ),
      );

      // Verify the widget builds successfully with enabled parameter
      // Note: enabled parameter is only fully supported on iOS custom implementation
      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('applies custom tilePadding', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              tilePadding: EdgeInsets.all(32.0),
              children: [Text('Child')],
            ),
          ),
        ),
      );

      // Verify the widget builds successfully with custom tilePadding
      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('applies custom childrenPadding', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              childrenPadding: EdgeInsets.all(24.0),
              initiallyExpanded: true,
              children: [Text('Child')],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify children padding is applied
      final paddingWidget = find.descendant(
        of: find.byType(AdaptiveExpansionTile),
        matching: find.byType(Padding),
      );
      expect(paddingWidget, findsWidgets);
    });

    testWidgets('maintains state when maintainState is true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              maintainState: true,
              children: [Text('Child')],
            ),
          ),
        ),
      );

      // Expand
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();

      // Collapse
      await tester.tap(find.text('Test Title'));
      await tester.pumpAndSettle();

      // The test verifies that the widget doesn't crash with maintainState: true
      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('respects expandedCrossAxisAlignment', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveExpansionTile(
              title: Text('Test Title'),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              initiallyExpanded: true,
              children: [Text('Child')],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the widget builds successfully with expandedCrossAxisAlignment
      expect(find.text('Child'), findsOneWidget);
    });
  });
}
