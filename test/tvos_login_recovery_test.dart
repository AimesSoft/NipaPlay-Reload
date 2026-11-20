import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_anime_detail_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openDetail(
    WidgetTester tester, {
    required Future<BangumiAnime> Function(int) loader,
    SharedRemoteAnimeSummary? summary,
    Future<List<SharedRemoteEpisode>> Function()? episodes,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LargeScreenUiSfxService()),
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: NipaplayLargeScreenModeScope(
          isActive: true,
          child: NipaplayLargeScreenAnimeDetailPage(
            animeId: 42,
            animeLoader: loader,
            sharedSummary: summary,
            sharedEpisodeLoader: episodes,
            sharedEpisodeBuilder: episodes == null
                ? null
                : (_) => PlayableItem(videoPath: 'test.mp4'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('anonymous detail Select opens login instead of closing detail',
      (tester) async {
    await openDetail(tester,
        loader: (_) async => throw DandanplayLoginRequired());
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('登录弹弹play'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('登录弹弹play账号'), findsOneWidget);
    expect(find.text('用户名/邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('登录弹弹play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('error retry receives Select and runs the loader again',
      (tester) async {
    var attempts = 0;
    await openDetail(tester, loader: (_) async {
      attempts++;
      throw Exception('offline');
    });
    expect(attempts, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'shared-library files load even when online metadata requires login',
      (tester) async {
    var loadedEpisodes = false;
    await openDetail(
      tester,
      loader: (_) async => throw DandanplayLoginRequired(),
      summary: SharedRemoteAnimeSummary(
        animeId: 42,
        name: 'My own media',
        nameCn: null,
        summary: 'Library metadata',
        imageUrl: null,
        lastWatchTime: DateTime(2026),
        episodeCount: 0,
        hasMissingFiles: false,
      ),
      episodes: () async {
        loadedEpisodes = true;
        return [];
      },
    );
    expect(loadedEpisodes, isTrue);
    expect(find.text('My own media'), findsWidgets);
    expect(find.text('登录弹弹play'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
