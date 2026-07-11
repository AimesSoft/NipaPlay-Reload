import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ElevatedButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/adaptive_app_page_content.dart';
import 'package:nipaplay/app/app_page_component.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_actions.dart';
import 'package:nipaplay/app/unified_app_pages.dart';
import 'package:nipaplay/app/unified_app_virtual_windows.dart';
import 'package:nipaplay/app/unified_home_components.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/downloads/unified_torrent_page_model.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/media_library/adaptive_media_library_page.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/pages/torrent_download_page.dart';
import 'package:nipaplay/pages/webdav_browser_page.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/unified_setting_content_type.dart';
import 'package:nipaplay/settings/unified_setting_content.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/pages/account/material_account_page.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('unified application pages', () {
    test('settings is an action instead of a primary destination', () {
      final pages = buildUnifiedAppPages(
        availability: const AppPageAvailability(
          showWebDAV: false,
          showDownloader: false,
        ),
      );

      expect(
        pages.map((page) => page.id),
        <String>[
          AppPageIds.home,
          AppPageIds.video,
          AppPageIds.mediaLibrary,
          AppPageIds.account,
        ],
      );
      expect(pages.any((page) => page.id == AppPageIds.settings), isFalse);
      expect(
        pages
            .where((page) => page.id != AppPageIds.video)
            .every((page) => page.actionIds.contains(AppActionIds.settings)),
        isTrue,
      );
    });

    test('optional destinations have one canonical order on every surface', () {
      final pages = buildUnifiedAppPages(
        availability: const AppPageAvailability(
          showWebDAV: true,
          showDownloader: true,
        ),
      );

      expect(
        pages.map((page) => page.id),
        AppPageIds.primaryOrder,
      );
      expect(
        AppDisplaySurface.values,
        containsAll(<AppDisplaySurface>[
          AppDisplaySurface.desktopTablet,
          AppDisplaySurface.phone,
          AppDisplaySurface.television,
        ]),
      );
    });

    test('missing optional destinations fall back to home by id', () {
      final pages = buildUnifiedAppPages(
        availability: const AppPageAvailability(
          showWebDAV: false,
          showDownloader: false,
        ),
      );

      expect(
        effectiveAppPageId(pages, AppPageIds.webdav),
        AppPageIds.home,
      );
      expect(
        effectiveAppPageId(pages, AppPageIds.video),
        AppPageIds.video,
      );
    });

    test('page titles resolve from localization data without a widget context',
        () {
      final pages = buildUnifiedAppPages(
        availability: const AppPageAvailability(
          showWebDAV: false,
          showDownloader: false,
        ),
      );
      final localizations = lookupAppLocalizations(const Locale('zh'));

      expect(pages.first.title(localizations), localizations.tabHome);
    });

    test('settings action targets one shared virtual window definition', () {
      final action = unifiedAppActionById(AppActionIds.settings);
      final window = unifiedAppVirtualWindowById(AppPageIds.settings);
      final localizations = lookupAppLocalizations(const Locale('zh'));

      expect(action?.kind, UnifiedAppActionKind.openView);
      expect(action?.targetViewId, AppPageIds.settings);
      expect(window, isNotNull);
      expect(window!.title(localizations), localizations.settingsLabel);
      expect(window.contentType, UnifiedAppViewContentType.settings);
      expect(window.layout.phoneFloatingTitle, isTrue);
    });

    test('media library has one content type for every surface', () {
      final pages = buildUnifiedAppPages(
        availability: const AppPageAvailability(
          showWebDAV: false,
          showDownloader: false,
        ),
      );
      final mediaLibrary = pages.singleWhere(
        (page) => page.id == AppPageIds.mediaLibrary,
      );

      expect(mediaLibrary.components, hasLength(1));
      expect(
        mediaLibrary.components.single.type,
        AppPageComponentType.mediaLibrary,
      );
      final built = mediaLibrary.build(
        _FakeBuildContext(),
        AppDisplaySurface.phone,
      );
      expect(built, isA<AppDisplaySurfaceScope>());
    });

    test('one registry allocates the shared WebDAV state host', () {
      const component = AppPageComponent(
        id: 'webdav-browser',
        type: AppPageComponentType.webdavBrowser,
      );

      const controls = UnifiedAppControlRegistry();
      final featureHost = controls.build(_FakeBuildContext(), component);

      expect(featureHost, isA<WebDAVBrowserPage>());
    });

    test('all feature components resolve through one state-host registry', () {
      const components = <AppPageComponent>[
        AppPageComponent(
          id: 'home-feed',
          type: AppPageComponentType.homeFeed,
        ),
        AppPageComponent(
          id: 'playback',
          type: AppPageComponentType.playback,
        ),
        AppPageComponent(
          id: 'media-library',
          type: AppPageComponentType.mediaLibrary,
        ),
        AppPageComponent(
          id: 'torrent-tasks',
          type: AppPageComponentType.torrentTasks,
        ),
        AppPageComponent(
          id: 'account',
          type: AppPageComponentType.account,
        ),
      ];
      const controls = UnifiedAppControlRegistry();

      for (final component in components) {
        expect(controls.build(_FakeBuildContext(), component), isNotNull);
      }
      expect(
        controls.build(_FakeBuildContext(), components[0]),
        isA<DashboardHomePage>(),
      );
      expect(
        controls.build(_FakeBuildContext(), components[1]),
        isA<PlayVideoPage>(),
      );
      expect(
        controls.build(_FakeBuildContext(), components[2]),
        isA<AdaptiveMediaLibraryPage>(),
      );
      expect(
        controls.build(_FakeBuildContext(), components[3]),
        isA<TorrentDownloadPage>(),
      );
      expect(
        controls.build(_FakeBuildContext(), components[4]),
        isA<UnifiedAccountPage>(),
      );
    });
  });

  test('settings entries cannot carry per-surface page builders', () {
    final source =
        File('lib/settings/unified_settings_entries.dart').readAsStringSync();

    expect(source, isNot(contains('desktopTabletPageBuilder')));
    expect(source, isNot(contains('phonePageBuilder')));
    expect(source, isNot(contains('phoneHomeTileBuilder')));
    expect(source, isNot(contains('subtitleWidgetBuilder')));
    expect(UnifiedSettingContentType.values, isNotEmpty);
    expect(
      const UnifiedSettingContent(type: UnifiedSettingContentType.general),
      isA<UnifiedSettingContent>(),
    );
  });

  test('home renderers consume one ordered semantic component list', () {
    SharedPreferences.setMockInitialValues(const {});
    final settings = HomeSectionsSettingsProvider();
    final components = buildUnifiedHomeComponents(
      settings: settings,
      hasTodaySeries: true,
      hasRandomRecommendations: false,
      hasLocalLibrary: true,
    );

    expect(
      components.map((component) => component.type),
      <UnifiedHomeComponentType>[
        UnifiedHomeComponentType.hero,
        UnifiedHomeComponentType.todaySeries,
        UnifiedHomeComponentType.continueWatching,
        UnifiedHomeComponentType.remoteLibraries,
        UnifiedHomeComponentType.localLibrary,
      ],
    );
  });

  test('legacy phone feature pages are removed from the dependency graph', () {
    expect(
      File('lib/themes/cupertino/pages/cupertino_media_library_page.dart')
          .existsSync(),
      isFalse,
    );
    expect(
      File('lib/themes/cupertino/pages/cupertino_webdav_browser_control.dart')
          .existsSync(),
      isFalse,
    );
    expect(
      File('lib/themes/cupertino/pages/cupertino_media_server_detail_page.dart')
          .existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_shared_remote_lan_scan_dialog.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_shared_anime_detail_page.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_network_media_management_sheet.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_network_media_library_sheet.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_manual_danmaku_sheet.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_plugin_market_dialog.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory('lib/themes/cupertino/pages/network_media')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      isEmpty,
    );
    final appRegistry =
        File('lib/app/adaptive_app_page_content.dart').readAsStringSync();
    expect(appRegistry, isNot(contains('forSurface')));
    expect(appRegistry, isNot(contains('_CupertinoPageControls')));
  });

  test('media library sections share stable ids and ordering', () {
    final sections = buildUnifiedMediaLibrarySections(
      const MediaLibraryAvailability(
        showLocal: true,
        showWebDAVLibrary: true,
        showWebDAVManagement: true,
        showSMBLibrary: true,
        showSMBManagement: true,
        showShared: true,
        showDandanplay: true,
        showJellyfin: true,
        showEmby: true,
      ),
    );

    expect(sections.first.id, MediaLibrarySectionIds.local);
    expect(sections[1].id, MediaLibrarySectionIds.localManagement);
    expect(sections.last.id, MediaLibrarySectionIds.emby);
    expect(
      sections.first.contentType,
      UnifiedMediaLibraryContentType.mediaCollection,
    );
    expect(sections.first.source, UnifiedMediaLibrarySource.local);
    expect(
      sections.last.server,
      UnifiedMediaLibraryServer.emby,
    );
    expect(
      mediaLibrarySectionIndexById(
        sections,
        MediaLibrarySectionIds.sharedManagement,
      ),
      greaterThan(0),
    );
  });

  test('media library source filtering is shared by every renderer', () {
    final now = DateTime(2026, 7, 10);
    WatchHistoryItem item(String filePath, int animeId, {int minutes = 0}) {
      return WatchHistoryItem(
        filePath: filePath,
        animeName: 'Anime $animeId',
        animeId: animeId,
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: now.add(Duration(minutes: minutes)),
      );
    }

    final history = <WatchHistoryItem>[
      item('/media/local-a.mkv', 1),
      item('/media/local-b.mkv', 1, minutes: 2),
      item('webdav://server/show.mkv', 2),
      item('smb://server/show.mkv', 3),
      item('jellyfin://item', 4),
      item('http://host/api/media/local/share/id', 5),
    ];

    expect(
      mediaLibraryLatestItemsByAnime(
        history,
        UnifiedMediaLibrarySource.local,
      ).single.filePath,
      '/media/local-b.mkv',
    );
    expect(
      mediaLibraryLatestItemsByAnime(
        history,
        UnifiedMediaLibrarySource.webdav,
      ).single.animeId,
      2,
    );
    expect(
      mediaLibraryLatestItemsByAnime(
        history,
        UnifiedMediaLibrarySource.smb,
      ).single.animeId,
      3,
    );
  });

  test('torrent search and sorting use one shared model', () {
    TorrentTask task(int id, String name, int progress) {
      return TorrentTask(
        id: id,
        infoHash: 'hash-$id',
        name: name,
        outputFolder: '/downloads/$name',
        state: 'live',
        progressBytes: progress,
        uploadedBytes: 0,
        totalBytes: 100,
        finished: false,
        downloadSpeedBytesPerSecond: 0,
        uploadSpeedBytesPerSecond: 0,
        error: null,
      );
    }

    final tasks = [task(1, 'Beta', 75), task(2, 'Alpha', 25)];
    expect(
      buildUnifiedTorrentVisibleTasks(
        tasks: tasks,
        scanSummaries: const {},
        query: '',
        sort: UnifiedTorrentTaskSort.name,
      ).map((item) => item.name),
      ['Alpha', 'Beta'],
    );
    expect(
      buildUnifiedTorrentVisibleTasks(
        tasks: tasks,
        scanSummaries: const {},
        query: 'beta',
        sort: UnifiedTorrentTaskSort.latest,
      ).single.id,
      1,
    );
  });

  test('navigation requests carry stable page and section ids', () {
    final notifier = TabChangeNotifier();

    notifier.changePage(AppPageIds.video);
    expect(notifier.targetPageId, AppPageIds.video);
    expect(notifier.targetTabIndex, isNull);

    notifier.changeToMediaLibrarySection(
      MediaLibrarySectionIds.localManagement,
    );
    expect(notifier.targetPageId, AppPageIds.mediaLibrary);
    expect(
      notifier.targetMediaLibrarySectionId,
      MediaLibrarySectionIds.localManagement,
    );
  });

  test('phone renderer can force Cupertino controls on Android', () {
    PlatformInfo.setPlatformOverride(PlatformOverride.android);
    PlatformInfo.setPreferCupertinoControls(true);
    addTearDown(() {
      PlatformInfo.setPreferCupertinoControls(false);
      PlatformInfo.clearPlatformOverride();
    });

    expect(PlatformInfo.isAndroid, isTrue);
    expect(PlatformInfo.prefersCupertinoControls, isTrue);
    expect(PlatformInfo.isIOS26OrHigher(), isFalse);
  });

  testWidgets('adaptive buttons do not fall back to Material on phone Android',
      (tester) async {
    PlatformInfo.setPlatformOverride(PlatformOverride.android);
    PlatformInfo.setPreferCupertinoControls(true);
    addTearDown(() {
      PlatformInfo.setPreferCupertinoControls(false);
      PlatformInfo.clearPlatformOverride();
    });

    await tester.pumpWidget(
      CupertinoApp(
        home: AdaptiveButton(
          label: 'Action',
          onPressed: () {},
        ),
      ),
    );

    expect(find.byType(CupertinoButton), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('Cupertino bottom sheet keeps child navigation inside the sheet',
      (tester) async {
    final bottomBar = BottomBarProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<BottomBarProvider>.value(
        value: bottomBar,
        child: CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              key: const Key('open-sheet'),
              onPressed: () {
                CupertinoBottomSheet.showPage<void>(
                  context: context,
                  title: 'Settings',
                  rootPageBuilder: (sheetContext) => Center(
                    child: CupertinoButton(
                      key: const Key('open-child'),
                      onPressed: () {
                        CupertinoBottomSheetPageNavigator.push<void>(
                          sheetContext,
                          title: 'Child settings',
                          builder: (_) => const AdaptiveSettingsScope(
                            style: AdaptiveSettingsStyle.phone,
                            child: AdaptiveSettingsPage(
                              children: [
                                Text(
                                  'Child page',
                                  key: Key('sheet-child'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: const Text('Open child'),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();

    expect(bottomBar.isBottomBarVisible, isFalse);
    expect(find.byType(CupertinoBottomSheet), findsOneWidget);
    expect(find.byType(CupertinoBottomSheetPageNavigator), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-child')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sheet-child')), findsOneWidget);
    expect(find.text('Child settings'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.byType(AdaptiveScaffold), findsNothing);
    expect(find.byType(CupertinoBottomSheet), findsOneWidget);

    Navigator.of(tester.element(find.byKey(const Key('sheet-child')))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Child settings'), findsNothing);

    Navigator.of(
      tester.element(find.byKey(const Key('open-child'))),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();
    expect(bottomBar.isBottomBarVisible, isTrue);
  });
}

class _FakeBuildContext extends Fake implements BuildContext {}
