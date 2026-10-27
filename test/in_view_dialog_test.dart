import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/in_view_dialog.dart';

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform dialogs stay inside the current Flutter view',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
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

  test('lib does not call showDialog directly', () {
    // Experimental desktop windowing promotes showDialog to a native window
    // whose first ShowWindow can deadlock the whole app on Windows (#1020).
    final call = RegExp(r'(?<![\w.])showDialog\s*[<(]|material\.showDialog\s*\(');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('in_view_dialog.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (call.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'Use showInViewDialog instead.');
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
