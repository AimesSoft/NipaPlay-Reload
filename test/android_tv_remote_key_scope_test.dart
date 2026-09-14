import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/android_tv_remote_key_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

KeyDownEvent _press(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.escape,
      timeStamp: Duration.zero,
    );

Widget _app(Widget home, {GlobalKey<NavigatorState>? navigatorKey}) {
  final rootNavigatorKey = navigatorKey ?? GlobalKey<NavigatorState>();
  return ChangeNotifierProvider(
    create: (_) => LargeScreenUiSfxService(),
    child: MaterialApp(
      navigatorKey: rootNavigatorKey,
      builder: (_, child) => NipaplayAndroidTvRemoteKeyScope(
        navigatorKey: rootNavigatorKey,
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android menu and back are distinct; desktop Escape still opens menu',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      NipaplayLargeScreenInputControls.fromKeyEvent(
        _press(LogicalKeyboardKey.contextMenu),
      ),
      NipaplayLargeScreenInputCommand.toggleMenu,
    );
    for (final key in [LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape]) {
      expect(NipaplayLargeScreenInputControls.fromKeyEvent(_press(key)),
          NipaplayLargeScreenInputCommand.back);
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      NipaplayLargeScreenInputControls.fromKeyEvent(
        _press(LogicalKeyboardKey.escape),
      ),
      NipaplayLargeScreenInputCommand.toggleMenu,
    );
  });

  testWidgets('menu toggles once and consumes repeats and key up',
      (tester) async {
    var menuCount = 0;
    await tester.pumpWidget(_app(Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (NipaplayLargeScreenInputControls.fromKeyEvent(event) ==
            NipaplayLargeScreenInputCommand.toggleMenu) {
          menuCount++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: const SizedBox.expand(),
    )));
    await tester.pumpAndSettle();

    expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.contextMenu), isTrue);
    expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.contextMenu),
        isTrue);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.contextMenu), isTrue);
    expect(menuCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(menuCount, 2);
  });

  for (final key in [LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape]) {
    testWidgets('back $key pops only one layer even after focus changes',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(
        const Scaffold(body: Text('root')),
        navigatorKey: navigatorKey,
      ));
      for (final label in ['first', 'second']) {
        navigatorKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => NipaplayLargeScreenContentPage(
            closeOnBack: true,
            child: Focus(autofocus: true, child: Scaffold(body: Text(label))),
          ),
        ));
        await tester.pumpAndSettle();
      }

      expect(
          await tester.sendKeyDownEvent(key,
              physicalKey: PhysicalKeyboardKey.escape),
          isTrue);
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);
      expect(
          await tester.sendKeyRepeatEvent(key,
              physicalKey: PhysicalKeyboardKey.escape),
          isTrue);
      expect(
          await tester.sendKeyUpEvent(key,
              physicalKey: PhysicalKeyboardKey.escape),
          isTrue);
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    });
  }

  testWidgets('unhandled back uses system navigation once', (tester) async {
    var exitCount = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exitCount++;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(
      const Scaffold(body: Text('root')),
      navigatorKey: navigatorKey,
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('plain route')),
    ));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('plain route'), findsNothing);
    expect(exitCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(exitCount, 1);
  });
}
