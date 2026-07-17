import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/network_settings_content.dart';
import 'package:nipaplay/settings/widgets/media_server_connection_user_agent_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp(
    Widget child, {
    AdaptiveSettingsStyle style = AdaptiveSettingsStyle.desktopTablet,
  }) {
    return ChangeNotifierProvider(
      create: (_) => AppearanceSettingsProvider(),
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdaptiveSettingsScope(
          style: style,
          child: child,
        ),
      ),
    );
  }

  testWidgets('player UA setting explains supported kernels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });

    await tester.pumpWidget(buildApp(const NetworkSettingsContent()));
    await tester.pumpAndSettle();

    expect(find.textContaining('仅 MDK 与 MediaKit 内核支持'), findsOneWidget);
  });

  testWidgets('unified network settings save a sanitized player UA',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });

    await tester.pumpWidget(buildApp(const NetworkSettingsContent()));
    await tester.pumpAndSettle();

    final userAgentTile = find.text('自定义 User-Agent');
    expect(userAgentTile, findsOneWidget);
    await tester.ensureVisible(userAgentTile);
    await tester.tap(userAgentTile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '  NewPlayer/1.0\r\nInjected  ',
    );
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'NewPlayer/1.0Injected',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('connection UA setting loads, sanitizes, and restores default',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.mediaServerConnectionUserAgent: 'StoredClient/1.0',
    });
    addTearDown(() async {
      await MediaServerServiceBase.saveConnectionUserAgent('');
      SharedPreferences.setMockInitialValues({});
    });

    await tester.pumpWidget(
      buildApp(const MediaServerConnectionUserAgentSetting()),
    );
    await tester.pumpAndSettle();
    expect(find.text('StoredClient/1.0'), findsOneWidget);

    final tile = find.text('连接 User-Agent（Jellyfin/Emby）');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '  NewClient/2.0\r\nInjected  ',
    );
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(
      await MediaServerServiceBase.getStoredConnectionUserAgent(),
      'NewClient/2.0Injected',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(
      await MediaServerServiceBase.getStoredConnectionUserAgent(),
      isEmpty,
    );
    expect(
      find.text(MediaServerServiceBase.defaultConnectionUserAgent),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('phone connection UA setting saves through the Cupertino dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await MediaServerServiceBase.saveConnectionUserAgent('PhoneClient/1.0');
    addTearDown(() async {
      await MediaServerServiceBase.saveConnectionUserAgent('');
      SharedPreferences.setMockInitialValues({});
    });

    await tester.pumpWidget(
      buildApp(
        const MediaServerConnectionUserAgentSetting(),
        style: AdaptiveSettingsStyle.phone,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PhoneClient/1.0'), findsOneWidget);

    await tester.tap(find.text('连接 User-Agent（Jellyfin/Emby）'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(cupertino.CupertinoTextField).last,
      'PhoneClient/2.0',
    );
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();

    expect(
      await MediaServerServiceBase.getStoredConnectionUserAgent(),
      'PhoneClient/2.0',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
