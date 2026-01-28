import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveSegmentedControl', () {
    testWidgets('creates segmented control with labels', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AdaptiveSegmentedControl(
                  labels: const ['One', 'Two', 'Three'],
                  selectedIndex: 0,
                  height: 40.0,
                  onValueChanged: (index) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);
    });

    testWidgets('calls onValueChanged when segment tapped', (
      WidgetTester tester,
    ) async {
      int selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AdaptiveSegmentedControl(
                  labels: const ['One', 'Two', 'Three'],
                  selectedIndex: selectedIndex,
                  height: 40.0,
                  onValueChanged: (index) {
                    selectedIndex = index;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Two'));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('respects custom icon color', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AdaptiveSegmentedControl(
                  labels: const ['A', 'B'],
                  selectedIndex: 0,
                  height: 40.0,
                  iconColor: Colors.red,
                  onValueChanged: (index) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('AdaptiveAlertDialog', () {
    testWidgets('shows alert dialog with title and message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveAlertDialog.show(
                    context: context,
                    title: 'Alert',
                    message: 'This is a message',
                    actions: [AlertAction(title: 'OK', onPressed: () {})],
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Alert'), findsOneWidget);
      expect(find.text('This is a message'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('calls action onPressed when button tapped', (
      WidgetTester tester,
    ) async {
      bool actionPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveAlertDialog.show(
                    context: context,
                    title: 'Confirm',
                    message: 'Are you sure?',
                    actions: [
                      AlertAction(
                        title: 'Yes',
                        onPressed: () {
                          actionPressed = true;
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(actionPressed, isTrue);
    });

    testWidgets('shows dialog with input field', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveAlertDialog.inputShow(
                    context: context,
                    title: 'Enter Name',
                    input: const AdaptiveAlertDialogInput(
                      placeholder: 'Your name',
                    ),
                    actions: [AlertAction(title: 'Submit', onPressed: () {})],
                  );
                },
                child: const Text('Show Input Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Input Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Enter Name'), findsOneWidget);
      // Check for text field widget (EditableText is the base for both TextField and CupertinoTextField)
      expect(find.byType(EditableText), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('respects destructive action style', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AdaptiveAlertDialog.show(
                    context: context,
                    title: 'Delete',
                    message: 'Delete this item?',
                    actions: [
                      AlertAction(
                        title: 'Cancel',
                        style: AlertActionStyle.cancel,
                        onPressed: () {},
                      ),
                      AlertAction(
                        title: 'Delete',
                        style: AlertActionStyle.destructive,
                        onPressed: () {},
                      ),
                    ],
                  );
                },
                child: const Text('Show Delete Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Delete Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('AdaptiveContextMenu', () {
    testWidgets('creates context menu with actions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveContextMenu(
              actions: [
                AdaptiveContextMenuAction(
                  title: 'Edit',
                  icon: Icons.edit,
                  onPressed: () {},
                ),
                AdaptiveContextMenuAction(
                  title: 'Delete',
                  icon: Icons.delete,
                  onPressed: () {},
                ),
              ],
              child: Container(
                width: 100,
                height: 100,
                color: Colors.blue,
                child: const Text('Long press me'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Long press me'), findsOneWidget);
    });

    testWidgets('shows menu on long press', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveContextMenu(
              actions: [
                AdaptiveContextMenuAction(
                  title: 'Share',
                  icon: Icons.share,
                  onPressed: () {},
                ),
              ],
              child: const Text('Long press'),
            ),
          ),
        ),
      );

      await tester.longPress(find.text('Long press'));
      await tester.pumpAndSettle();

      // Menu should appear (on Android as PopupMenu)
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('calls action onPressed when action tapped', (
      WidgetTester tester,
    ) async {
      bool actionPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveContextMenu(
              actions: [
                AdaptiveContextMenuAction(
                  title: 'Action',
                  icon: Icons.check,
                  onPressed: () {
                    actionPressed = true;
                  },
                ),
              ],
              child: const Text('Long press'),
            ),
          ),
        ),
      );

      await tester.longPress(find.text('Long press'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(actionPressed, isTrue);
    });
  });

  group('AdaptivePopupMenuButton', () {
    testWidgets('creates popup menu button with text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptivePopupMenuButton.text<String>(
              label: 'Options',
              height: 40.0,
              items: const [
                AdaptivePopupMenuItem(label: 'Edit', value: 'edit'),
                AdaptivePopupMenuItem(label: 'Delete', value: 'delete'),
              ],
              onSelected: (index, item) {},
            ),
          ),
        ),
      );

      expect(find.text('Options'), findsOneWidget);
    });

    testWidgets('shows menu when button tapped', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptivePopupMenuButton.text<String>(
              label: 'Menu',
              height: 40.0,
              items: const [
                AdaptivePopupMenuItem(label: 'Item 1', value: '1'),
                AdaptivePopupMenuItem(label: 'Item 2', value: '2'),
              ],
              onSelected: (index, item) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });

    testWidgets('calls onSelected when item tapped', (
      WidgetTester tester,
    ) async {
      String? selectedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptivePopupMenuButton.text<String>(
              label: 'Select',
              height: 40.0,
              items: const [
                AdaptivePopupMenuItem(label: 'Option A', value: 'a'),
              ],
              onSelected: (index, item) {
                selectedValue = item.value;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Option A'));
      await tester.pumpAndSettle();

      expect(selectedValue, 'a');
    });

    testWidgets('creates icon popup menu button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptivePopupMenuButton.icon<String>(
              icon: Icons.more_vert,
              items: const [
                AdaptivePopupMenuItem(label: 'Settings', value: 'settings'),
              ],
              onSelected: (index, item) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });
}
