import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/network_settings_content.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final isBangumi in [true, false]) {
    for (final save in [false, true]) {
      testWidgets('phone custom API server bangumi=$isBangumi save=$save',
          (tester) async {
        final nestedNavigatorKey = GlobalKey<NavigatorState>();
        SharedPreferences.setMockInitialValues({});
        addTearDown(() => SharedPreferences.setMockInitialValues({}));
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => AppearanceSettingsProvider(),
              ),
              ChangeNotifierProvider(
                create: (_) => BottomBarProvider(),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AppDisplaySurfaceScope(
                surface: AppDisplaySurface.phone,
                child: AdaptiveSettingsScope(
                  style: AdaptiveSettingsStyle.phone,
                  child: Navigator(
                    key: nestedNavigatorKey,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const SizedBox(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        nestedNavigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const NetworkSettingsContent(),
          ),
        );
        await tester.pumpAndSettle();

        final title = isBangumi
            ? 'Custom Bangumi API Server'
            : 'Custom DanDanPlay API Server';
        final tile = find.text(title);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoBottomSheet), findsOneWidget);
        await tester.enterText(
            find.byType(EditableText), 'https://example.com');
        final sheet = find.byType(CupertinoBottomSheet);
        final action = find.descendant(
          of: sheet,
          matching: find.text(save ? 'Use This Server' : 'Cancel'),
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(CupertinoBottomSheet), findsNothing);
        expect(find.byType(NetworkSettingsContent), findsOneWidget);
        expect(nestedNavigatorKey.currentState!.canPop(), isTrue);
        final server = isBangumi
            ? await NetworkSettings.getBangumiServer()
            : await NetworkSettings.getCustomServer();
        if (save) {
          expect(server, 'https://example.com');
        } else {
          expect(server, isNot('https://example.com'));
        }
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    }
  }
}
