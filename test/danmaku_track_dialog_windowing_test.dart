// This regression exercises Flutter's experimental window registry. It does
// not create OS windows or reproduce the native ShowWindow hang itself.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/danmaku_track_offset_button.dart';

class _RejectNativeDialogs extends WindowingOwner {
  int attempts = 0;

  @override
  DialogWindowController createDialogWindowController({
    required DialogWindowControllerDelegate delegate,
    Size? preferredSize,
    BoxConstraints? preferredConstraints,
    BaseWindowController? parent,
    String? title,
    bool decorated = true,
  }) {
    attempts++;
    throw StateError('The track editor must not create a native dialog');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'windowing-enabled track editor stays in its view and root navigator',
      (tester) async {
    final enabled = features.isWindowingEnabled;
    features.isWindowingEnabled = true;
    final previousOwner = tester.binding.windowingOwner;
    final owner = _RejectNativeDialogs();
    tester.binding.windowingOwner = owner;
    addTearDown(() {
      tester.binding.windowingOwner = previousOwner;
      features.isWindowingEnabled = enabled;
    });
    final root = GlobalKey<NavigatorState>();
    final nested = GlobalKey<NavigatorState>();
    final localTheme = ThemeData(colorSchemeSeed: Colors.deepPurple);
    double? result;
    await tester.pumpWidget(WindowManager(
      child: MaterialApp(
        navigatorKey: root,
        home: Navigator(
          key: nested,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Theme(
              data: localTheme,
              child: Scaffold(
                body: DanmakuTrackOffsetButton(
                  trackName: '本地弹幕',
                  offset: 2,
                  onChanged: (value) => result = value,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    final source = tester.element(find.byType(DanmakuTrackOffsetButton));
    final sourceView = View.of(source);
    expect(WindowRegistry.maybeOf(source), isNotNull);
    await tester.tap(find.byIcon(Icons.more_time));
    await tester.pumpAndSettle();
    expect(owner.attempts, 0);
    expect(tester.takeException(), isNull);
    final field = tester.element(find.byType(TextField));
    expect(View.of(field), same(sourceView));
    expect(Theme.of(field).colorScheme, localTheme.colorScheme);
    expect(root.currentState!.canPop(), isTrue);
    expect(nested.currentState!.canPop(), isFalse);
    expect(WindowRegistry.maybeOf(field)!.windows, isEmpty);
    await tester.enterText(find.byType(TextField), '-1.25');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result, -1.25);
    expect(root.currentState!.canPop(), isFalse);
  });
}
