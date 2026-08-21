import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/network_settings_content.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phone player UA setting saves without dialog lifecycle errors',
      (tester) async {
    final nestedNavigatorKey = GlobalKey<NavigatorState>();
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.saveCustomPlayerUA('');
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });

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

    await tester.tap(find.text('Custom User-Agent'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoBottomSheet), findsOneWidget);
    await tester.enterText(
      find.byType(EditableText),
      'VLC/3.0.20 LibVLC/3.0.20',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      PlayerFactory.getCustomPlayerUA(),
      'VLC/3.0.20 LibVLC/3.0.20',
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'VLC/3.0.20 LibVLC/3.0.20',
    );
    expect(nestedNavigatorKey.currentState!.canPop(), isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
