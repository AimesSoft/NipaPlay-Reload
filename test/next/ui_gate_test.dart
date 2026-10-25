import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
    final offstage = tester.widget<Offstage>(find.ancestor(
        of: find.text('classic'), matching: find.byType(Offstage)));
    expect(offstage.offstage, isFalse);
    final ticker = tester.widget<TickerMode>(find
        .ancestor(of: find.text('classic'), matching: find.byType(TickerMode))
        .first);
    expect(ticker.enabled, isTrue);
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
}
