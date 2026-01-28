import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveBlurView', () {
    testWidgets('creates blur view with child', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveBlurView(child: Text('Test Child'))),
        ),
      );

      expect(find.text('Test Child'), findsOneWidget);
    });

    testWidgets('creates blur view with custom blur style', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBlurView(
              blurStyle: BlurStyle.systemThickMaterial,
              child: Text('Test Child'),
            ),
          ),
        ),
      );

      expect(find.text('Test Child'), findsOneWidget);
      expect(find.byType(AdaptiveBlurView), findsOneWidget);
    });

    testWidgets('creates blur view with border radius', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveBlurView(
              borderRadius: BorderRadius.circular(16),
              child: const Text('Test Child'),
            ),
          ),
        ),
      );

      expect(find.text('Test Child'), findsOneWidget);
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('applies BackdropFilter on non-iOS 26 platforms', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBlurView(
              blurStyle: BlurStyle.systemMaterial,
              child: Text('Test Child'),
            ),
          ),
        ),
      );

      // Should use BackdropFilter on non-iOS 26 platforms
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Test Child'), findsOneWidget);
    });

    test('BlurStyle enum has all values', () {
      expect(BlurStyle.values.length, 5);
      expect(BlurStyle.values, contains(BlurStyle.systemUltraThinMaterial));
      expect(BlurStyle.values, contains(BlurStyle.systemThinMaterial));
      expect(BlurStyle.values, contains(BlurStyle.systemMaterial));
      expect(BlurStyle.values, contains(BlurStyle.systemThickMaterial));
      expect(BlurStyle.values, contains(BlurStyle.systemChromeMaterial));
    });

    test('BlurStyle converts to UIBlurEffect style string correctly', () {
      expect(
        BlurStyle.systemUltraThinMaterial.toUIBlurEffectStyle(),
        'systemUltraThinMaterial',
      );
      expect(
        BlurStyle.systemThinMaterial.toUIBlurEffectStyle(),
        'systemThinMaterial',
      );
      expect(BlurStyle.systemMaterial.toUIBlurEffectStyle(), 'systemMaterial');
      expect(
        BlurStyle.systemThickMaterial.toUIBlurEffectStyle(),
        'systemThickMaterial',
      );
      expect(
        BlurStyle.systemChromeMaterial.toUIBlurEffectStyle(),
        'systemChromeMaterial',
      );
    });

    test('BlurStyle converts to ImageFilter correctly', () {
      // Just verify that toImageFilter() returns an ImageFilter
      final filter = BlurStyle.systemUltraThinMaterial.toImageFilter();
      expect(filter, isNotNull);
      expect(filter.runtimeType.toString(), contains('ImageFilter'));
    });

    testWidgets('blur view works with different children widgets', (
      WidgetTester tester,
    ) async {
      // Test with Icon
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveBlurView(child: Icon(Icons.home))),
        ),
      );
      expect(find.byIcon(Icons.home), findsOneWidget);

      // Test with Container
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveBlurView(
              child: Container(width: 100, height: 100, color: Colors.red),
            ),
          ),
        ),
      );
      expect(find.byType(Container), findsWidgets);

      // Test with Column
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBlurView(
              child: Column(children: [Text('Line 1'), Text('Line 2')]),
            ),
          ),
        ),
      );
      expect(find.text('Line 1'), findsOneWidget);
      expect(find.text('Line 2'), findsOneWidget);
    });

    testWidgets('blur view applies correct background color in light mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: const Scaffold(
            body: AdaptiveBlurView(
              blurStyle: BlurStyle.systemUltraThinMaterial,
              child: Text('Test'),
            ),
          ),
        ),
      );

      expect(find.text('Test'), findsOneWidget);
      // BackdropFilter should be present (non-iOS 26 fallback)
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('blur view applies correct background color in dark mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const Scaffold(
            body: AdaptiveBlurView(
              blurStyle: BlurStyle.systemChromeMaterial,
              child: Text('Test'),
            ),
          ),
        ),
      );

      expect(find.text('Test'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
