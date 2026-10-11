import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/next_ui_gate.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With “使用 Next 界面” off, or Next itself off, the gate is Classic alone:
/// visible, focusable, animating, and nothing of Next is built.
void main() {
  Future<void> pumpGate(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
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

  void expectClassicOnly(WidgetTester tester) {
    expect(find.text('classic'), findsOneWidget);
    expect(find.byType(NextShell), findsNothing);
    final offstage = tester.widget<Offstage>(find.ancestor(
        of: find.text('classic'), matching: find.byType(Offstage)));
    expect(offstage.offstage, isFalse);
    final ticker = tester.widget<TickerMode>(find.ancestor(
        of: find.text('classic'), matching: find.byType(TickerMode)).first);
    expect(ticker.enabled, isTrue);
  }

  testWidgets('preference off: Classic only', (tester) async {
    await pumpGate(tester, {SettingsKeys.labsEnableAgentEndpoint: true});
    expectClassicOnly(tester);
  });

  testWidgets('preference on but Next off: Classic only', (tester) async {
    await pumpGate(tester, {NextUiPreference.key: true});
    expectClassicOnly(tester);
  });
}
