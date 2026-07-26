import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/network_settings_content.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HTTP proxy setting is available on desktop native platforms only', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      expect(
        supportsUnifiedHttpProxySetting(isWeb: false, platform: platform),
        isTrue,
      );
    }
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        supportsUnifiedHttpProxySetting(isWeb: false, platform: platform),
        isFalse,
      );
    }
    expect(
      supportsUnifiedHttpProxySetting(
        isWeb: true,
        platform: TargetPlatform.windows,
      ),
      isFalse,
    );
  });

  testWidgets('desktop network settings validate and save the HTTP proxy',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      SharedPreferences.setMockInitialValues({});
      await PlayerFactory.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppearanceSettingsProvider(),
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AdaptiveSettingsScope(
              style: AdaptiveSettingsStyle.desktopTablet,
              child: NetworkSettingsContent(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final proxyTile = find.text('媒体服务器与播放器 HTTP 代理');
      expect(proxyTile, findsOneWidget);
      expect(
        find.textContaining('播放器代理仅支持 MDK/MediaKit 内核'),
        findsOneWidget,
      );
      await tester.ensureVisible(proxyTile);
      await tester.tap(proxyTile);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://proxy:443');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      expect(
        find.text('请输入有效的 http:// 代理地址；不支持 HTTPS 代理端点或 SOCKS。'),
        findsOneWidget,
      );
      var preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(SettingsKeys.playerHttpProxy), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.ensureVisible(proxyTile);
      await tester.tap(proxyTile);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'http://127.0.0.1:8000',
      );
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();

      preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(SettingsKeys.playerHttpProxy),
        'http://127.0.0.1:8000',
      );
      expect(PlayerFactory.getHttpProxy(), 'http://127.0.0.1:8000');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await PlayerFactory.saveHttpProxy('');
      AppHttpProxy.clear();
      SharedPreferences.setMockInitialValues({});
    }
  });
}
