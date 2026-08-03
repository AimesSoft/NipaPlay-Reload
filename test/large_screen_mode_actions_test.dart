import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_actions.dart';

void main() {
  test('large-screen mode control is permanent on desktop and tablet', () {
    expect(
      shouldOfferLargeScreenModeControl(
        isDesktopOrTablet: true,
        isTelevisionSurface: false,
      ),
      isTrue,
    );
    expect(
      shouldOfferLargeScreenModeControl(
        isDesktopOrTablet: false,
        isTelevisionSurface: false,
      ),
      isFalse,
    );
    expect(
      shouldOfferLargeScreenModeControl(
        isDesktopOrTablet: true,
        isTelevisionSurface: true,
      ),
      isFalse,
    );
  });

  testWidgets('inactive large-screen mode control stays at the top right',
      (tester) async {
    var toggleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Stack(
          children: [
            NipaplayLargeScreenModeActionsOverlay(
              isDarkMode: false,
              isLargeScreenLayoutActive: false,
              topPadding: 12,
              rightPadding: 16,
              showWindowsButtons: false,
              isMaximized: false,
              onToggleLargeScreen: () => toggleCount += 1,
              onToggleThemeFromOrigin: (_) async {},
              onOpenSettings: () {},
              onMinimize: () {},
              onMaximizeRestore: () {},
              onClose: () {},
            ),
          ],
        ),
      ),
    );

    final toggle = find.byType(LargeScreenModeToggleIconButton);
    expect(toggle, findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: toggle, matching: find.byType(Positioned)),
    );
    expect(positioned.top, 12);
    expect(positioned.right, 16);

    await tester.tap(toggle);
    expect(toggleCount, 1);
  });
}
