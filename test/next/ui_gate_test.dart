import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:nipaplay/next/ui/player/playback.dart';
import 'player_test_support.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/next_ui_gate.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/next/ui/shell/window_chrome.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With “使用 Next 界面” off, or Next itself off, the gate is Classic alone:
/// visible, focusable, animating, and nothing of Next is built. The window
/// keeps Classic's chrome: Next's native window channel is never called.
void main() {
  final chromeCalls = <MethodCall>[];
  setUp(() {
    chromeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async {
      chromeCalls.add(call);
      return {'leading': 0.0, 'fullScreen': false};
    });
  });

  Future<void> pumpGate(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    globals.nextShellHostsPlayer = true;
    final labs = LabsSettingsProvider(sandboxStatus: () async => false);
    final preference = NextUiPreference();
    await tester.runAsync(() async {
      await labs.ready;
      await preference.ready;
    });
    addTearDown(labs.dispose);
    addTearDown(preference.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: labs),
        ChangeNotifierProvider.value(value: preference),
      ],
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: NextUiGate(classic: Text('classic')),
      ),
    ));
  }

  Future<void> expectClassicOnly(WidgetTester tester) async {
    await tester.pump();
    expect(find.text('classic'), findsOneWidget);
    expect(find.byType(NextShell), findsNothing);
    expect(NextWindowChrome.showing.value, isFalse);
    expect(chromeCalls, isEmpty);
    // Classic's player keeps its tabs: only Next hides them while playing.
    expect(globals.nextShellHostsPlayer, isFalse);
    expect(find.byType(Offstage), findsNothing);
  }

  testWidgets('preference off: Classic only', (tester) async {
    await pumpGate(tester, {SettingsKeys.labsEnableAgentEndpoint: true});
    await expectClassicOnly(tester);
  });

  testWidgets('preference on but Next off: Classic only', (tester) async {
    await pumpGate(tester, {NextUiPreference.key: true});
    await expectClassicOnly(tester);
  });

  testWidgets('both on, on a device without Next (Android): Classic only',
      (tester) async {
    final original = NextUiPreference.deviceHasNext;
    NextUiPreference.deviceHasNext = () => false;
    addTearDown(() => NextUiPreference.deviceHasNext = original);
    await pumpGate(tester, {
      SettingsKeys.labsEnableAgentEndpoint: true,
      NextUiPreference.key: true,
    });
    await expectClassicOnly(tester);
  });
  testWidgets('Next never mounts Classic, including while preferences load',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.labsEnableAgentEndpoint: true,
      NextUiPreference.key: true,
    });
    final supported = NextUiPreference.deviceHasNext;
    NextUiPreference.deviceHasNext = () => true;
    addTearDown(() => NextUiPreference.deviceHasNext = supported);
    final sandbox = Completer<bool>();
    final labs = LabsSettingsProvider(sandboxStatus: () => sandbox.future);
    final preference = NextUiPreference();
    final state = FakePlayerState();
    final playback = FakePlayback(state);
    NextShell.debugServices = (_) => playerTestServices();
    addTearDown(() => NextShell.debugServices = null);
    var mounted = 0, disposed = 0;
    final opened = <String>[];
    final classicLaunches = <String?>[];
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: labs),
        ChangeNotifierProvider.value(value: preference),
      ],
      child: NextPlaybackScope(
          playback: playback,
          child: MaterialApp(
              home: NextUiGate(
                  launchFilePath: '/launch.mkv',
                  openNextFile: (path) async {
                    opened.add(path);
                  },
                  classicBuilder: (path) {
                    classicLaunches.add(path);
                    return _Lifecycle(
                        onMount: () => mounted++, onDispose: () => disposed++);
                  }))),
    ));
    await tester.pump();
    expect(mounted, 0);
    expect(find.byType(NextShell), findsNothing);
    sandbox.complete(false);
    await tester.runAsync(() async {
      await labs.ready;
      await preference.ready;
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(NextShell), findsOneWidget);
    expect(mounted, 0);
    expect(opened, ['/launch.mkv']);
    await preference.setEnabled(false);
    await tester.pump();
    expect(mounted, 1);
    expect(classicLaunches.last, isNull);
    await preference.setEnabled(true);
    await tester.pump();
    expect(disposed, 1);
    expect(opened, ['/launch.mkv']);
    expect(find.byType(_Lifecycle, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox());
    labs.dispose();
    preference.dispose();
  });
}

class _Lifecycle extends StatefulWidget {
  const _Lifecycle({required this.onMount, required this.onDispose});
  final VoidCallback onMount, onDispose;
  @override
  State<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends State<_Lifecycle> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('classic');
}
