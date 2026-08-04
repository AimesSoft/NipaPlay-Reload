import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/in_view_dialog.dart';

void main() {
  testWidgets('Windows dialogs stay inside the current Flutter view',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInViewDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('In-view dialog'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('In-view dialog'), findsOneWidget);
    expect(observer.lastPushedRoute, isA<RawDialogRoute<void>>());
    expect(observer.lastPushedRoute, isNot(isA<DialogRoute<void>>()));

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('In-view dialog'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}
