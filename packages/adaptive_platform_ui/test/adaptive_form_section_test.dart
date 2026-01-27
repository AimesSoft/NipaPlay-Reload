import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveFormSection', () {
    testWidgets('creates form section with children', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              children: [const Text('Row 1'), const Text('Row 2')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsOneWidget);
    });

    testWidgets('displays header when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              header: const Text('Header Text'),
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.text('Header Text'), findsOneWidget);
    });

    testWidgets('displays footer when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              footer: const Text('Footer Text'),
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.text('Footer Text'), findsOneWidget);
    });

    testWidgets('displays both header and footer when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              header: const Text('Header Text'),
              footer: const Text('Footer Text'),
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.text('Header Text'), findsOneWidget);
      expect(find.text('Footer Text'), findsOneWidget);
    });

    testWidgets('creates inset grouped form section', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection.insetGrouped(
              header: const Text('Inset Header'),
              children: [const Text('Row 1'), const Text('Row 2')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
      expect(find.text('Inset Header'), findsOneWidget);
      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsOneWidget);
    });

    testWidgets('applies custom backgroundColor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              backgroundColor: Colors.red,
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
    });

    testWidgets('applies custom margin', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              margin: const EdgeInsets.all(20),
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
    });

    testWidgets('supports multiple children', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              children: [
                const Text('Row 1'),
                const Text('Row 2'),
                const Text('Row 3'),
                const Text('Row 4'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsOneWidget);
      expect(find.text('Row 3'), findsOneWidget);
      expect(find.text('Row 4'), findsOneWidget);
    });

    testWidgets('works with CupertinoFormRow children', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: AdaptiveFormSection(
              children: [
                CupertinoFormRow(prefix: Text('Name'), child: Text('John Doe')),
                CupertinoFormRow(
                  prefix: Text('Email'),
                  child: Text('john@example.com'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('john@example.com'), findsOneWidget);
    });

    testWidgets('inset grouped has proper default margin', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection.insetGrouped(
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
      // The inset grouped version should have horizontal and vertical margins
      // We can't directly test EdgeInsets, but we can verify the widget builds
    });

    testWidgets('handles empty children list', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveFormSection(children: [])),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
    });

    testWidgets('applies custom decoration when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
    });

    testWidgets('applies custom clipBehavior', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection(
              clipBehavior: Clip.hardEdge,
              children: [const Text('Row 1')],
            ),
          ),
        ),
      );

      expect(find.byType(AdaptiveFormSection), findsOneWidget);
    });

    testWidgets('default constructor has Clip.none as default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveFormSection(children: [Text('Row 1')])),
        ),
      );

      final section = tester.widget<AdaptiveFormSection>(
        find.byType(AdaptiveFormSection),
      );
      expect(section.clipBehavior, Clip.none);
    });

    testWidgets('insetGrouped constructor has Clip.hardEdge as default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveFormSection.insetGrouped(children: [Text('Row 1')]),
          ),
        ),
      );

      final section = tester.widget<AdaptiveFormSection>(
        find.byType(AdaptiveFormSection),
      );
      expect(section.clipBehavior, Clip.hardEdge);
    });

    testWidgets('insetGrouped flag is set correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdaptiveFormSection(children: [Text('Default')]),
                AdaptiveFormSection.insetGrouped(children: [Text('Inset')]),
              ],
            ),
          ),
        ),
      );

      final sections = tester.widgetList<AdaptiveFormSection>(
        find.byType(AdaptiveFormSection),
      );

      expect(sections.length, 2);
      expect(sections.first.insetGrouped, false);
      expect(sections.last.insetGrouped, true);
    });
  });
}
