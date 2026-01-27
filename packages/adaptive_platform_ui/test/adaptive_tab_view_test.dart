import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveTabBarView', () {
    testWidgets('creates tab bar view with tabs', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveTabBarView(
              tabs: const ['Tab 1', 'Tab 2', 'Tab 3'],
              children: const [
                Center(child: Text('Page 1')),
                Center(child: Text('Page 2')),
                Center(child: Text('Page 3')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tab 1'), findsOneWidget);
      expect(find.text('Tab 2'), findsOneWidget);
      expect(find.text('Tab 3'), findsOneWidget);
    });

    testWidgets('switches between tab pages', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveTabBarView(
              tabs: const ['Tab 1', 'Tab 2'],
              children: const [
                Center(child: Text('Page 1')),
                Center(child: Text('Page 2')),
              ],
            ),
          ),
        ),
      );

      // Initial page should be Page 1
      expect(find.text('Page 1'), findsOneWidget);

      // Tap on Tab 2
      await tester.tap(find.text('Tab 2'));
      await tester.pumpAndSettle();

      // Page 2 should be visible
      expect(find.text('Page 2'), findsOneWidget);
    });

    testWidgets('supports swipe gesture', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveTabBarView(
              tabs: const ['Tab 1', 'Tab 2'],
              children: const [
                Center(child: Text('Page 1')),
                Center(child: Text('Page 2')),
              ],
            ),
          ),
        ),
      );

      // Find the PageView widget (it contains the swipeable content)
      final pageView = find.byType(PageView);

      // Swipe left to go to next page
      await tester.drag(pageView, const Offset(-400, 0));
      await tester.pumpAndSettle();

      // Page 2 should be visible after swipe
      expect(find.text('Page 2'), findsOneWidget);
    });

    testWidgets('calls onTabChanged callback', (WidgetTester tester) async {
      int? selectedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveTabBarView(
              tabs: const ['Tab 1', 'Tab 2'],
              children: const [
                Center(child: Text('Page 1')),
                Center(child: Text('Page 2')),
              ],
              onTabChanged: (index) {
                selectedIndex = index;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tab 2'));
      await tester.pumpAndSettle();

      expect(selectedIndex, 1);
    });
  });
}
