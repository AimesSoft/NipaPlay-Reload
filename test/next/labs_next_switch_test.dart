import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/next/ui/shell/next_ui_gate.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/player/playback.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/settings/pages/labs_settings_content.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_test_support.dart';

/// The Labs switch into NipaPlay Next: on a desktop it says what the Agent
/// does on this computer; on an iPad or an iPhone, which run no Agent, it
/// says what the Agent on the user's other devices can do here. Android has
/// no switch.
void main() {
  final original = LabsSettingsContent.device;
  tearDown(() => LabsSettingsContent.device = original);

  Future<(LabsSettingsProvider, NextUiPreference)> pumpLabs(WidgetTester tester,
      {required bool desktop,
      required bool iPad,
      bool iPhone = false,
      bool routed = false,
      bool sandboxed = false,
      Map<String, Object>? prefs}) async {
    LabsSettingsContent.device =
        () => (desktop: desktop, iPad: iPad, iPhone: iPhone);
    SharedPreferences.setMockInitialValues(prefs ?? {});
    final labs = LabsSettingsProvider(sandboxStatus: () async => sandboxed);
    final preference = NextUiPreference();
    addTearDown(labs.dispose);
    addTearDown(preference.dispose);
    await tester.runAsync(() async {
      await labs.ready;
      await preference.ready;
    });
    final page =
        Scaffold(body: LabsSettingsContent(onOpenWebDavQuickSettings: () {}));
    Widget app = MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: routed
          ? NextUiGate(
              classic: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => page)),
                    child: const Text('Open labs'),
                  ),
                ),
              ),
            )
          : page,
    );
    if (routed) {
      final supported = NextUiPreference.deviceHasNext;
      NextUiPreference.deviceHasNext = () => true;
      NextShell.debugServices = (_) => playerTestServices();
      addTearDown(() {
        NextUiPreference.deviceHasNext = supported;
        NextShell.debugServices = null;
      });
      app = NextPlaybackScope(
          playback: FakePlayback(FakePlayerState()), child: app);
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: labs),
        ChangeNotifierProvider.value(value: preference),
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
      ],
      child: app,
    ));
    await tester.pumpAndSettle();
    if (routed) {
      await tester.tap(find.text('Open labs'));
      await tester.pumpAndSettle();
    }
    return (labs, preference);
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

  testWidgets('an authorized iPad re-enters Next with the same single switch',
      (tester) async {
    final (labs, preference) = await pumpLabs(tester,
        desktop: false,
        iPad: true,
        prefs: {SettingsKeys.labsEnableAgentEndpoint: true});
    expect(find.text('使用 Next 界面'), findsNothing);
    expect(preference.enabled, isFalse);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    expect(labs.enableAgentEndpoint, isTrue);
    expect(preference.enabled, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('an iPhone has the switch, and its consent speaks of this iPhone',
      (tester) async {
    await pumpLabs(tester, desktop: false, iPad: false, iPhone: true);
    expect(find.text('NipaPlay Next'), findsOneWidget);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('这台 iPhone 上的 NipaPlay'), findsOneWidget);
    expect(find.textContaining('iPad'), findsNothing);
    expect(find.textContaining('使用这台电脑'), findsNothing);
  });

  testWidgets('an Android phone has no switch', (tester) async {
    await pumpLabs(tester, desktop: false, iPad: false);
    expect(find.text('NipaPlay Next'), findsNothing);
  });

  testWidgets('confirmation enables both preferences and exposes Next home',
      (tester) async {
    final (labs, preference) =
        await pumpLabs(tester, desktop: true, iPad: false, routed: true);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    expect(labs.enableAgentEndpoint, isFalse);
    expect(preference.enabled, isFalse);
    await tester.tap(find.text('我了解风险，开启'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(labs.enableAgentEndpoint, isTrue);
    expect(preference.enabled, isTrue);
    final saved = await SharedPreferences.getInstance();
    expect(saved.getBool(SettingsKeys.labsEnableAgentEndpoint), isTrue);
    expect(saved.getBool(NextUiPreference.key), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NextShell), findsOneWidget);
    expect(find.byType(LabsSettingsContent), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel preserves Classic and keeps Labs open', (tester) async {
    final (labs, preference) =
        await pumpLabs(tester, desktop: true, iPad: false, routed: true);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(labs.enableAgentEndpoint, isFalse);
    expect(preference.enabled, isFalse);
    expect(find.byType(LabsSettingsContent), findsOneWidget);
    expect(find.byType(NextShell), findsNothing);
  });

  testWidgets('the disclosure includes Mesh, full permissions and liability',
      (tester) async {
    await pumpLabs(tester, desktop: true, iPad: false);
    expect(find.textContaining('梨花驱动的媒体库'), findsOneWidget);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    for (final text in [
      '当前系统用户',
      '每一步都会再次弹窗确认',
      '远程程序运行',
      '模型服务商',
      '离线备份',
      'MIT',
      'AimesSoft',
      '依法不得排除',
    ]) {
      expect(find.textContaining(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sandboxed builds cannot enable Next', (tester) async {
    final (labs, preference) =
        await pumpLabs(tester, desktop: true, iPad: false, sandboxed: true);
    await tester.tap(find.text('NipaPlay Next'));
    await tester.pumpAndSettle();
    expect(labs.enableAgentEndpoint, isFalse);
    expect(preference.enabled, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
