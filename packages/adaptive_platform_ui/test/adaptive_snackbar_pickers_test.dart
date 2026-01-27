import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveSnackBar', () {
    testWidgets('shows snackbar with message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Success message',
                    type: AdaptiveSnackBarType.success,
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pumpAndSettle();

      expect(find.text('Success message'), findsOneWidget);
    });

    testWidgets('shows snackbar with different types', (
      WidgetTester tester,
    ) async {
      for (final type in AdaptiveSnackBarType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: '$type message',
                      type: type,
                    );
                  },
                  child: Text('Show ${type.name}'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show ${type.name}'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('message'), findsOneWidget);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('shows snackbar with action button', (
      WidgetTester tester,
    ) async {
      bool actionPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'File deleted',
                    action: 'Undo',
                    onActionPressed: () {
                      actionPressed = true;
                    },
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pumpAndSettle();

      expect(find.text('File deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      expect(actionPressed, isTrue);
    });

    testWidgets('respects custom duration', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Custom duration',
                    duration: const Duration(milliseconds: 500),
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Custom duration'), findsOneWidget);
    });
  });

  group('AdaptiveDatePicker', () {
    testWidgets('shows date picker dialog', (WidgetTester tester) async {
      DateTime? selectedDate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedDate = await AdaptiveDatePicker.show(
                    context: context,
                    initialDate: DateTime(2024, 1, 1),
                  );
                },
                child: const Text('Show Date Picker'),
              ),
            ),
          ),
        ),
      );

      selectedDate;
      await tester.tap(find.text('Show Date Picker'));
      await tester.pumpAndSettle();

      // Date picker dialog should be shown - check for dialog buttons
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('returns selected date', (WidgetTester tester) async {
      DateTime? selectedDate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedDate = await AdaptiveDatePicker.show(
                    context: context,
                    initialDate: DateTime(2024, 6, 15),
                  );
                },
                child: const Text('Pick Date'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Date'));
      await tester.pumpAndSettle();

      // Tap OK button on Android dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(selectedDate, isNotNull);
    });

    testWidgets('respects date range', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveDatePicker.show(
                    context: context,
                    initialDate: DateTime(2024, 6, 15),
                    firstDate: DateTime(2024, 1, 1),
                    lastDate: DateTime(2024, 12, 31),
                  );
                },
                child: const Text('Show Date Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Date Picker'));
      await tester.pumpAndSettle();

      // Date picker dialog should be shown - check for dialog buttons
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('returns null when cancelled', (WidgetTester tester) async {
      DateTime? selectedDate = DateTime(2024, 1, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedDate = await AdaptiveDatePicker.show(
                    context: context,
                    initialDate: DateTime(2024, 6, 15),
                  );
                },
                child: const Text('Pick Date'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Date'));
      await tester.pumpAndSettle();

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selectedDate, isNull);
    });
  });

  group('AdaptiveTimePicker', () {
    testWidgets('shows time picker dialog', (WidgetTester tester) async {
      TimeOfDay? selectedTime;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedTime = await AdaptiveTimePicker.show(
                    context: context,
                    initialTime: const TimeOfDay(hour: 10, minute: 30),
                  );
                },
                child: const Text('Show Time Picker'),
              ),
            ),
          ),
        ),
      );

      selectedTime;
      await tester.tap(find.text('Show Time Picker'));
      await tester.pumpAndSettle();

      // Time picker dialog should be shown - check for dialog buttons
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('returns selected time', (WidgetTester tester) async {
      TimeOfDay? selectedTime;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedTime = await AdaptiveTimePicker.show(
                    context: context,
                    initialTime: const TimeOfDay(hour: 14, minute: 0),
                  );
                },
                child: const Text('Pick Time'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Time'));
      await tester.pumpAndSettle();

      // Tap OK button
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(selectedTime, isNotNull);
    });

    testWidgets('respects 24-hour format', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveTimePicker.show(
                    context: context,
                    initialTime: const TimeOfDay(hour: 14, minute: 30),
                    use24HourFormat: true,
                  );
                },
                child: const Text('Show Time Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Time Picker'));
      await tester.pumpAndSettle();

      // Time picker dialog should be shown - check for dialog buttons
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('returns null when cancelled', (WidgetTester tester) async {
      TimeOfDay? selectedTime = const TimeOfDay(hour: 10, minute: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedTime = await AdaptiveTimePicker.show(
                    context: context,
                    initialTime: const TimeOfDay(hour: 14, minute: 0),
                  );
                },
                child: const Text('Pick Time'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Time'));
      await tester.pumpAndSettle();

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selectedTime, isNull);
    });
  });

  group('AdaptiveScaffold', () {
    testWidgets('creates scaffold with body', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AdaptiveScaffold(body: Text('Scaffold Body'))),
      );

      expect(find.text('Scaffold Body'), findsOneWidget);
    });

    testWidgets('creates scaffold with app bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            appBar: AdaptiveAppBar(title: 'Test App'),
            body: const Text('Content'),
          ),
        ),
      );

      expect(find.text('Test App'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('creates scaffold with bottom navigation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            body: const Text('Home'),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
                AdaptiveNavigationDestination(
                  icon: Icons.search,
                  label: 'Search',
                ),
              ],
              selectedIndex: 0,
              onTap: (index) {},
            ),
          ),
        ),
      );

      expect(find.text('Home'), findsWidgets);
      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('creates scaffold with app bar and bottom navigation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            appBar: AdaptiveAppBar(title: 'App'),
            body: const Center(child: Text('Content')),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
                AdaptiveNavigationDestination(
                  icon: Icons.settings,
                  label: 'Settings',
                ),
              ],
              selectedIndex: 0,
              onTap: (index) {},
            ),
          ),
        ),
      );

      expect(find.text('App'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('creates scaffold without app bar and bottom navigation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveScaffold(body: Text('Minimal Scaffold')),
        ),
      );

      expect(find.text('Minimal Scaffold'), findsOneWidget);
      // No app bar or bottom navigation
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('AdaptiveAppBar', () {
    testWidgets('creates app bar with title', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            appBar: AdaptiveAppBar(title: 'My App'),
            body: const Text('Body'),
          ),
        ),
      );

      expect(find.text('My App'), findsOneWidget);
    });

    testWidgets('creates app bar with actions', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'App',
              actions: [
                AdaptiveAppBarAction(onPressed: () {}, icon: Icons.settings),
              ],
            ),
            body: const Text('Body'),
          ),
        ),
      );

      expect(find.text('App'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('calls action onPressed when tapped', (
      WidgetTester tester,
    ) async {
      bool actionPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'App',
              actions: [
                AdaptiveAppBarAction(
                  onPressed: () {
                    actionPressed = true;
                  },
                  icon: Icons.add,
                ),
              ],
            ),
            body: const Text('Body'),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(actionPressed, isTrue);
    });
  });

  group('AdaptiveBottomNavigationBar', () {
    testWidgets('creates bottom navigation with items', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            body: const Text('Home'),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
                AdaptiveNavigationDestination(
                  icon: Icons.person,
                  label: 'Profile',
                ),
              ],
              selectedIndex: 0,
              onTap: (index) {},
            ),
          ),
        ),
      );

      expect(find.text('Home'), findsWidgets);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('calls onTap when item tapped', (WidgetTester tester) async {
      int selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            body: const Text('Content'),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
                AdaptiveNavigationDestination(
                  icon: Icons.search,
                  label: 'Search',
                ),
              ],
              selectedIndex: selectedIndex,
              onTap: (index) {
                selectedIndex = index;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Search'));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('renders badge counts on items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            body: const Text('Home'),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(
                  icon: Icons.message,
                  label: 'Messages',
                  badgeCount: 5,
                ),
                AdaptiveNavigationDestination(
                  icon: Icons.notifications,
                  label: 'Notifications',
                  badgeCount: 10,
                ),
              ],
              selectedIndex: 0,
              onTap: (index) {},
            ),
          ),
        ),
      );

      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      // Badge counts should be visible
      expect(find.text('5'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });
  });
}
