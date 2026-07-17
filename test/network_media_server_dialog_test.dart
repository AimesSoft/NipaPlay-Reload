import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('phone Jellyfin settings builds in a Cupertino-only tree',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final jellyfinProvider = JellyfinProvider();
    addTearDown(jellyfinProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<JellyfinProvider>.value(
            value: jellyfinProvider,
          ),
          ChangeNotifierProvider<JellyfinTranscodeProvider>.value(
            value: JellyfinTranscodeProvider(),
          ),
        ],
        child: const CupertinoApp(
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.phone,
            child: CupertinoPageScaffold(
              child: NetworkMediaServerDialog(
                serverType: MediaServerType.jellyfin,
                embedded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('转码设置'), findsOneWidget);

    await tester.tap(find.text('转码设置'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('启用转码'), findsOneWidget);
  });
}
