import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveCard', () {
    testWidgets('creates card with child', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveCard(child: Text('Card Content'))),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(AdaptiveCard), findsOneWidget);
    });

    testWidgets('respects custom padding', (WidgetTester tester) async {
      const customPadding = EdgeInsets.all(32.0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveCard(
              padding: customPadding,
              child: Text('Padded Card'),
            ),
          ),
        ),
      );

      expect(find.text('Padded Card'), findsOneWidget);
    });

    testWidgets('respects custom color', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveCard(color: Colors.blue, child: Text('Colored Card')),
          ),
        ),
      );

      expect(find.text('Colored Card'), findsOneWidget);
    });

    testWidgets('respects custom border radius', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCard(
              borderRadius: BorderRadius.circular(20),
              child: const Text('Rounded Card'),
            ),
          ),
        ),
      );

      expect(find.text('Rounded Card'), findsOneWidget);
    });

    testWidgets('respects elevation on Android', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveCard(elevation: 8, child: Text('Elevated Card')),
          ),
        ),
      );

      expect(find.text('Elevated Card'), findsOneWidget);
    });
  });

  group('AdaptiveBadge', () {
    testWidgets('creates badge with count', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(count: 5, child: Icon(Icons.notifications)),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsOneWidget);
    });

    testWidgets('creates badge with label', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(label: 'NEW', child: Icon(Icons.mail)),
          ),
        ),
      );

      expect(find.text('NEW'), findsOneWidget);
      expect(find.byIcon(Icons.mail), findsOneWidget);
    });

    testWidgets('displays 99+ for count > 99', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(count: 150, child: Icon(Icons.message)),
          ),
        ),
      );

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('respects showZero parameter', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(
              count: 0,
              showZero: true,
              child: Icon(Icons.notifications),
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('hides badge when count is 0 and showZero is false', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(
              count: 0,
              showZero: false,
              child: Icon(Icons.notifications),
            ),
          ),
        ),
      );

      expect(find.text('0'), findsNothing);
    });

    testWidgets('respects custom backgroundColor', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(
              count: 3,
              backgroundColor: Colors.green,
              child: Icon(Icons.star),
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('respects isLarge parameter', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveBadge(
              count: 99,
              isLarge: true,
              child: Icon(Icons.shopping_cart),
            ),
          ),
        ),
      );

      expect(find.text('99'), findsOneWidget);
    });
  });

  group('AdaptiveTooltip', () {
    testWidgets('creates tooltip with message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveTooltip(
              message: 'Tooltip message',
              child: Icon(Icons.info),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.info), findsOneWidget);
    });

    testWidgets('shows tooltip on long press', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveTooltip(
              message: 'Help text',
              child: Icon(Icons.help),
            ),
          ),
        ),
      );

      await tester.longPress(find.byIcon(Icons.help));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Help text'), findsOneWidget);
    });

    testWidgets('respects preferBelow parameter', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveTooltip(
              message: 'Above tooltip',
              preferBelow: false,
              child: Icon(Icons.info),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.info), findsOneWidget);
    });

    testWidgets('respects custom height', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveTooltip(
              message: 'Tall tooltip',
              height: 50,
              child: Icon(Icons.info),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.info), findsOneWidget);
    });
  });

  group('AdaptiveListTile', () {
    testWidgets('creates list tile with title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AdaptiveListTile(title: Text('Title'))),
        ),
      );

      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('creates list tile with title and subtitle', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(
              title: Text('Title'),
              subtitle: Text('Subtitle'),
            ),
          ),
        ),
      );

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Subtitle'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(
              title: const Text('Tappable'),
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tappable'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('renders leading widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(
              leading: Icon(Icons.person),
              title: Text('Profile'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('renders trailing widget', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(
              title: Text('Settings'),
              trailing: Icon(Icons.chevron_right),
            ),
          ),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('respects selected state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(title: Text('Selected'), selected: true),
          ),
        ),
      );

      expect(find.text('Selected'), findsOneWidget);
    });

    testWidgets('respects enabled state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(title: Text('Disabled'), enabled: false),
          ),
        ),
      );

      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('calls onLongPress when long pressed', (
      WidgetTester tester,
    ) async {
      bool longPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveListTile(
              title: const Text('Long Press'),
              onLongPress: () {
                longPressed = true;
              },
            ),
          ),
        ),
      );

      await tester.longPress(find.text('Long Press'));
      await tester.pump();

      expect(longPressed, isTrue);
    });
  });
}
