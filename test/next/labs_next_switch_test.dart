import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/settings/pages/labs_settings_content.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Labs switch into NipaPlay Next: on a desktop it says what the Agent
/// does on this computer; on an iPad, which runs no Agent, it says what the
/// Agent on the user's other devices can do here.
void main() {
  final original = LabsSettingsContent.device;
  tearDown(() => LabsSettingsContent.device = original);

  Future<void> pumpLabs(WidgetTester tester,
      {required bool desktop,
      required bool iPad,
      Map<String, Object>? prefs}) async {
    LabsSettingsContent.device = () => (desktop: desktop, iPad: iPad);
    SharedPreferences.setMockInitialValues(prefs ?? {});
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
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: LabsSettingsContent(onOpenWebDavQuickSettings: () {})),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'an iPad has the switch, and its consent speaks of the other devices',
      (tester) async {
    await pumpLabs(tester, desktop: false, iPad: true);
    expect(find.text('NipaPlay Next'), findsOneWidget);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('其他设备上的 AI Agent'), findsOneWidget);
    expect(find.textContaining('使用这台电脑'), findsNothing);
  });

  testWidgets('a desktop keeps its own consent', (tester) async {
    await pumpLabs(tester, desktop: true, iPad: false);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('使用这台电脑'), findsOneWidget);
    expect(find.textContaining('其他设备上的 AI Agent'), findsNothing);
  });

  testWidgets('an iPad, once Next is on, can switch to the Next interface',
      (tester) async {
    await pumpLabs(tester,
        desktop: false,
        iPad: true,
        prefs: {SettingsKeys.labsEnableAgentEndpoint: true});
    expect(find.text('使用 Next 界面'), findsOneWidget);
  });

  testWidgets('a phone has no switch', (tester) async {
    await pumpLabs(tester, desktop: false, iPad: false);
    expect(find.text('NipaPlay Next'), findsNothing);
  });
}
