import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/unified_settings_page.dart';
import 'package:nipaplay/themes/cupertino/utils/cupertino_glass_navigation_insets.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_app_page_actions.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_page_actions_scope.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The settings landing page observes this service but doesn't invoke plugins.
class _IdlePluginService extends ChangeNotifier implements PluginService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NipaPlay',
      packageName: 'nipaplay',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(PlatformInfo.clearPlatformOverride);

  for (final iosVersion in [18, 26, 27]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'iOS $iosVersion ${brightness.name}: library settings opens across its touch area',
        (tester) async {
          PlatformInfo.setPlatformOverride(
            PlatformOverride.ios,
            iosVersion: iosVersion,
          );
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final controller = CupertinoPageActionsController();
          final navigatorKey = GlobalKey<NavigatorState>();
          final theme = ThemeNotifier();
          addTearDown(controller.dispose);
          addTearDown(theme.dispose);
          var morePresses = 0;
          final owner = Object();
          final moreAction = CupertinoPageAction(
            id: 'media-library-more',
            label: '媒体库操作',
            icon: CupertinoIcons.ellipsis,
            onPressed: () => morePresses++,
          );

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<PluginService>(
                  create: (_) => _IdlePluginService(),
                ),
                ChangeNotifierProvider(create: (_) => AppLanguageProvider()),
                ChangeNotifierProvider(create: (_) => BottomBarProvider()),
                ChangeNotifierProvider(create: (_) => EmbyProvider()),
                ChangeNotifierProvider(create: (_) => JellyfinProvider()),
                ChangeNotifierProvider(create: (_) => SettingsProvider()),
                ChangeNotifierProvider.value(value: theme),
              ],
              child: CupertinoApp(
                navigatorKey: navigatorKey,
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: CupertinoThemeData(brightness: brightness),
                home: AppDisplaySurfaceScope(
                  surface: AppDisplaySurface.phone,
                  child: CupertinoPageActionsScope(
                    controller: controller,
                    child: CupertinoPageScaffold(
                      child: Stack(
                        children: [
                          AdaptiveMediaLibraryScaffold(
                            sections: const [],
                            selectedSection: null,
                            onSectionSelected: (_) {},
                            onSectionOrderChanged: (_) {},
                            onRemoteAccess: () {},
                            onAddMedia: () {},
                            child: ListView(
                              children: const [SizedBox(height: 1500)],
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: resolvePageActionsTrailingOffset(
                              viewPaddingRight: 0,
                              iosMajorVersion: iosVersion,
                            ),
                            child: const CupertinoAppPageActions(
                              actionIds: [
                                AppActionIds.toggleTheme,
                                AppActionIds.settings,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Like entering the library, add its menu after the toolbar exists.
          controller.setActions(owner, [moreAction]);
          await tester.pumpAndSettle();

          final settings = find.byKey(const ValueKey(AppActionIds.settings));
          expect(tester.getSize(settings), const Size.square(44));
          final bounds = tester.getRect(settings);
          for (final x in [2.0, 22.0, 42.0]) {
            for (final y in [2.0, 22.0, 42.0]) {
              await tester.tapAt(bounds.topLeft + Offset(x, y));
              await tester.pumpAndSettle();
              expect(find.byType(UnifiedSettingsPage), findsOneWidget);
              navigatorKey.currentState!.pop();
              await tester.pumpAndSettle();
            }
          }

          // A natural tap may move slightly before the finger lifts.
          final gesture = await tester.startGesture(bounds.center);
          await gesture.moveBy(const Offset(4, 3));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(find.byType(UnifiedSettingsPage), findsOneWidget);
          navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();

          expect(morePresses, 0);
          expect(theme.themeMode, ThemeMode.system);
          await tester.tap(find.byKey(const ValueKey('media-library-more')));
          await tester.pumpAndSettle();
          expect(morePresses, 1);

          // Leaving and re-entering must preserve the settings target.
          controller.reset();
          await tester.pumpAndSettle();
          expect(tester.getRect(settings), bounds);
          controller.setActions(owner, [moreAction]);
          await tester.pumpAndSettle();
          await tester.tap(settings);
          await tester.pumpAndSettle();
          expect(find.byType(UnifiedSettingsPage), findsOneWidget);
          navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();

          final settingsIcon = find.descendant(
            of: settings,
            matching: find.byType(Icon),
          );
          Focus.of(tester.element(settingsIcon)).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(find.byType(UnifiedSettingsPage), findsOneWidget);
          navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
