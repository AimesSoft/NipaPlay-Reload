import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/remote_media_library_settings_content.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final surface in [
    AppDisplaySurface.television,
    AppDisplaySurface.phone
  ]) {
    testWidgets(
        'shared clients can be added, edited and cancelled on ${surface.name}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final shared = SharedRemoteLibraryProvider(
        clientFactory: (_) => MockClient(
            (_) async => http.Response('{"success":true,"items":[]}', 200)),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
            ChangeNotifierProvider(create: (_) => JellyfinProvider()),
            ChangeNotifierProvider(create: (_) => EmbyProvider()),
            ChangeNotifierProvider(
                create: (_) => DandanplayRemoteProvider()..initialize()),
            ChangeNotifierProvider(create: (_) => shared),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                AppDisplaySurfaceScope(surface: surface, child: child!),
            home: Scaffold(
              body: AdaptiveSettingsScope(
                style: surface == AppDisplaySurface.phone
                    ? AdaptiveSettingsStyle.phone
                    : AdaptiveSettingsStyle.desktopTablet,
                child: const RemoteMediaLibrarySettingsContent(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> open(String title) async {
        final tile = find.text(title);
        await tester.scrollUntilVisible(tile, 250);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(tile), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      final fields = find.byType(EditableText);
      TvOSRemoteTextInputTarget tvTarget(int index) {
        final field = tester.widget<EditableText>(fields.at(index));
        return findTvOSRemoteTextInputTarget(field.focusNode)!;
      }

      await open('Add Shared Client');
      if (surface == AppDisplaySurface.television) {
        applyTvOSRemoteTextInputValues(tvTarget(0), {
          'displayName': 'Living room',
          'baseUrl': 'http://media.test:1180',
        });
      } else {
        await tester.enterText(fields.at(0), 'Living room');
        await tester.enterText(fields.at(1), 'http://media.test:1180');
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(shared.hosts.single.displayName, 'Living room');
      expect(shared.hosts.single.baseUrl, 'http://media.test:1180');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await open('Edit Shared Client');
      expect(tester.widget<EditableText>(fields.at(0)).controller.text,
          'Living room');
      expect(tester.widget<EditableText>(fields.at(1)).controller.text,
          'http://media.test:1180');
      await tester.enterText(fields.at(1), 'http://discard.test');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(shared.hosts.single.baseUrl, 'http://media.test:1180');

      await open('Edit Shared Client');
      if (surface == AppDisplaySurface.television) {
        applyTvOSRemoteTextInputValue(tvTarget(1), 'http://library.test:1180');
      } else {
        await tester.enterText(fields.at(1), 'http://library.test:1180');
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(shared.hosts.single.displayName, 'Living room');
      expect(shared.hosts.single.baseUrl, 'http://library.test:1180');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }
}
