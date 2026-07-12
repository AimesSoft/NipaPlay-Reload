import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ElevatedButton, MaterialApp, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
import 'package:nipaplay/media_library/adaptive_library_management_overview.dart';
import 'package:nipaplay/media_library/media_collection_empty_content.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/pages/account/account_page_view_model.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/pages/torrent_download_page.dart';
import 'package:nipaplay/pages/webdav_browser_page.dart';
import 'package:nipaplay/playback/adaptive_playback_entry_view.dart';
import 'package:nipaplay/playback/unified_playback_entry_model.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/unified_setting_content_type.dart';
import 'package:nipaplay/settings/unified_setting_content.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_library_management_overview.dart';
import 'package:nipaplay/themes/nipaplay/pages/account/material_account_page.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('unified application pages', () {
    testWidgets('application chrome inherits the selected display surface',
        (tester) async {
      AppDisplaySurface? observedSurface;
      final themeContext = ThemeBuildContext(
        themeNotifier: ThemeNotifier(),
        navigatorKey: GlobalKey<NavigatorState>(),
        launchFilePath: null,
        environment: const ThemeEnvironment(
          isDesktop: false,
          isPhone: true,
          isWeb: false,
        ),
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[],
        settings: const <String, dynamic>{},
        overlayBuilder: (child) => child,
        homeBuilders: <AppDisplaySurface, Widget Function()>{
          AppDisplaySurface.phone: () => Builder(
                builder: (context) {
                  observedSurface = AppDisplaySurfaceScope.of(context);
                  return const SizedBox.shrink();
                },
              ),
        },
      );

      await tester.pumpWidget(themeContext.buildHome(AppDisplaySurface.phone));

      expect(observedSurface, AppDisplaySurface.phone);
    });

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
    final generalSource = File(
      'lib/settings/pages/general_settings_content.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('desktopTabletPageBuilder')));
    expect(source, isNot(contains('phonePageBuilder')));
    expect(source, isNot(contains('phoneHomeTileBuilder')));
    expect(source, isNot(contains('subtitleWidgetBuilder')));
    expect(source, isNot(contains('UnifiedSettingInlineControlType')));
    expect(source, isNot(contains('AutoUpdateSettingTile')));
    expect(source, contains('context.watch<PluginService>()'));
    expect(generalSource, contains('AutoUpdateSettingTile'));
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

  test('library management extends its root renderer into mounted folders', () {
    final management = File(
      'lib/themes/nipaplay/widgets/library_management_tab.dart',
    ).readAsStringSync();
    final removedBrowser = File(
      'lib/media_library/adaptive_library_folder_browser.dart',
    );

    expect(management, contains('_MountedLibraryLocation'));
    expect(management, contains('_buildMountedDirectoryItems'));
    expect(management, contains('AdaptiveLibraryManagementOverview'));
    expect(management, isNot(contains('_buildMountedLibrary')));
    expect(management, isNot(contains('AdaptiveLibraryFolderBrowser')));
    expect(management, isNot(contains('CupertinoBottomSheet.show(')));
    expect(management, isNot(contains('_openPhoneLocalFolder')));
    expect(removedBrowser.existsSync(), isFalse);
  });

  test('phone page actions use native iOS 26 and Flutter glass groups', () {
    final mediaControls = File(
      'lib/media_library/adaptive_media_library_controls.dart',
    ).readAsStringSync();
    final mediaPage = File(
      'lib/media_library/adaptive_media_library_page.dart',
    ).readAsStringSync();
    final pageActions = File(
      'lib/themes/cupertino/widgets/cupertino_app_page_actions.dart',
    ).readAsStringSync();
    final glassGroup = File(
      'lib/themes/cupertino/widgets/cupertino_glass_button_group.dart',
    ).readAsStringSync();
    final nativeGroup = File(
      'packages/adaptive_platform_ui/ios/Classes/iOS26ButtonGroupView.swift',
    ).readAsStringSync();
    final nativeGroupWidget = File(
      'packages/adaptive_platform_ui/lib/src/widgets/ios26/'
      'ios26_button_group.dart',
    ).readAsStringSync();
    final plugin = File(
      'packages/adaptive_platform_ui/ios/Classes/'
      'AdaptivePlatformUiPlugin.swift',
    ).readAsStringSync();

    expect(mediaControls, isNot(contains('_CupertinoHeaderButton')));
    expect(mediaPage, contains("id: 'media-library-more'"));
    expect(mediaPage, contains('CupertinoBottomSheet.show<String>'));
    expect(mediaPage, contains('heightRatio: 0.94'));
    expect(mediaPage, isNot(contains('heightRatio: 0.32')));
    expect(pageActions, contains('for (final action in pageActions)'));
    expect(glassGroup, contains('PlatformInfo.isIOS26OrHigher()'));
    expect(glassGroup, contains('IOS26ButtonGroup('));
    expect(glassGroup, contains('GlassButtonGroup.icons'));
    expect(glassGroup, contains('useOwnLayer: true'));
    expect(glassGroup, isNot(contains('UiKitView')));
    expect(nativeGroup, contains('UIToolbar()'));
    expect(nativeGroup, contains('UIBarButtonItemGroup.fixedGroup'));
    expect(nativeGroup, contains('barItem.sharesBackground = true'));
    expect(nativeGroup, isNot(contains('UISegmentedControl')));
    expect(nativeGroupWidget, contains("ios26_button_group"));
    expect(plugin, contains('iOS26ButtonGroupViewFactory'));
  });

  test('phone primary pages share one header and desktop background renderer',
      () {
    final home = File(
      'lib/themes/cupertino/widgets/cupertino_home_page_controls.dart',
    ).readAsStringSync();
    final account = File(
      'lib/themes/nipaplay/pages/account/material_account_page.dart',
    ).readAsStringSync();
    final media = File(
      'lib/media_library/adaptive_media_library_controls.dart',
    ).readAsStringSync();
    final phoneRoot = File(
      'lib/themes/cupertino/pages/cupertino_main_page.dart',
    ).readAsStringSync();
    final header = File(
      'lib/themes/cupertino/widgets/cupertino_app_page_header.dart',
    ).readAsStringSync();

    expect(home, contains("CupertinoAppPageHeader(title: '主页')"));
    expect(account, contains('title: AccountPageViewModel.title'));
    expect(media, contains("CupertinoAppPageHeader(title: '媒体库'"));
    expect(home, isNot(contains('statusBarHeight + 58')));
    expect(account, isNot(contains('statusBarHeight + 58')));
    expect(header, contains('fontSize: 30'));
    expect(phoneRoot, contains('BackgroundWithBlur('));
  });

  test('phone home icon buttons use neutral Cupertino label colors', () {
    final home = File(
      'lib/themes/cupertino/widgets/cupertino_home_page_controls.dart',
    ).readAsStringSync();
    final glassGroup = File(
      'lib/themes/cupertino/widgets/cupertino_glass_button_group.dart',
    ).readAsStringSync();

    expect(home, contains('_buildCupertinoHomeIconButton('));
    expect(home, contains('CupertinoColors.label'));
    expect(home, contains('color: effectiveColor'));
    expect(glassGroup, contains('CupertinoColors.label'));
    expect(glassGroup, contains('Icon(item.icon, color: iconColor)'));
  });

  test('phone notifications sit higher and use neutral colors', () {
    final notification = File(
      'lib/themes/nipaplay/widgets/blur_snackbar.dart',
    ).readAsStringSync();

    expect(notification,
        contains('final baseBottomOffset = 16 + safePadding.bottom'));
    expect(
      notification,
      contains('isPhoneSurface ? baseBottomOffset * 2 : baseBottomOffset'),
    );
    expect(notification, contains('const Color(0xF2252527)'));
    expect(notification, contains('const Color(0xFAF7F7F8)'));
    expect(notification, contains('final actionForeground = textColor'));
    expect(notification, isNot(contains('AppAccentColors.current')));
  });

  test('phone modal choices all use the shared Cupertino bottom sheet', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => !file.path.endsWith(
            'themes/cupertino/widgets/cupertino_bottom_sheet.dart',
          ),
        );
    final directPopupUsers = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains('showCupertinoModalPopup') ||
          source.contains('CupertinoActionSheet') ||
          source.contains('AdaptivePopupMenuButton')) {
        directPopupUsers.add(file.path);
      }
    }

    expect(directPopupUsers, isEmpty);
    expect(
      File(
        'lib/themes/cupertino/widgets/cupertino_modal_popup.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('today anime search separates shared state from surface renderers', () {
    final host = File(
      'lib/themes/nipaplay/widgets/tag_search_widget.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/search/tag_search_controller.dart',
    ).readAsStringSync();
    final phoneView = File(
      'lib/themes/cupertino/widgets/cupertino_tag_search_view.dart',
    ).readAsStringSync();

    expect(host, contains('TagSearchController('));
    expect(host, contains('CupertinoTagSearchView('));
    expect(
        controller, contains('abstract interface class TagSearchDataSource'));
    expect(controller, contains('class TagSearchController'));
    expect(phoneView, contains('CupertinoBottomSheetContentLayout('));
    expect(phoneView, contains('CupertinoTextField('));
    expect(phoneView, contains('AdaptiveSlider('));
    expect(phoneView, isNot(contains('CupertinoSlider(')));
    expect(
      phoneView,
      contains('activeColor: CupertinoTheme.of(context).primaryColor'),
    );
    expect(phoneView, contains('CupertinoColors.label'));
    expect(phoneView, contains('copyWith(color: label)'));
    expect(phoneView, isNot(contains("package:flutter/material.dart")));
  });

  test('phone media pages share one neutral containerless search toolbar', () {
    final collection = File(
      'lib/media_library/adaptive_media_collection_view.dart',
    ).readAsStringSync();
    final management = File(
      'lib/themes/nipaplay/widgets/library_management_tab.dart',
    ).readAsStringSync();
    final toolbar = File(
      'lib/themes/cupertino/widgets/cupertino_media_search_toolbar.dart',
    ).readAsStringSync();
    final sectionPicker = File(
      'lib/themes/cupertino/widgets/cupertino_media_library_section_picker.dart',
    ).readAsStringSync();

    expect(collection, contains('CupertinoMediaSearchToolbar('));
    expect(collection, isNot(contains('_phoneToolbarButton')));
    expect(collection, isNot(contains('AdaptiveButtonStyle.glass')));
    expect(management, contains('CupertinoMediaSearchToolbar('));
    expect(management, isNot(contains('_buildPhoneLibraryToolbarButton')));
    expect(management, isNot(contains('CupertinoGlassButtonGroup(')));
    expect(toolbar, contains('static const double controlHeight = 38'));
    expect(toolbar, contains('CupertinoSearchTextField('));
    expect(toolbar, contains('CupertinoColors.label'));
    expect(sectionPicker, contains('mainAxisSize: MainAxisSize.min'));
    expect(sectionPicker, isNot(contains('width: 240')));
  });

  test('phone anime detail respects its bottom sheet title area', () {
    final detailShell = File(
      'lib/themes/nipaplay/widgets/anime_detail_shell.dart',
    ).readAsStringSync();

    expect(detailShell, contains('CupertinoBottomSheetScope.maybeOf(context)'));
    expect(detailShell, contains('bottomSheetScope?.contentTopInset'));
    expect(detailShell, contains('12 + phoneTopInset'));
    expect(detailShell, contains('fontSize: 18'));
  });

  test('phone anime detail and account share the native segmented control', () {
    final detailShell = File(
      'lib/themes/nipaplay/widgets/anime_detail_shell.dart',
    ).readAsStringSync();
    final account = File(
      'lib/themes/nipaplay/pages/account/material_account_page.dart',
    ).readAsStringSync();

    expect(detailShell, contains('AdaptiveSegmentedControl('));
    expect(detailShell, contains("labels: const ['简介', '剧集']"));
    expect(detailShell, isNot(contains('TabBar(')));
    expect(account, contains('AdaptiveSegmentedControl('));
  });

  test('account content has one model and surface-specific renderers', () {
    final account = File(
      'lib/themes/nipaplay/pages/account/material_account_page.dart',
    ).readAsStringSync();
    final desktop = File(
      'lib/themes/nipaplay/pages/account/desktop_account_view.dart',
    ).readAsStringSync();
    final phoneDandanplay = File(
      'lib/themes/cupertino/pages/account/sections/'
      'dandanplay_account_section.dart',
    ).readAsStringSync();
    final phoneBangumi = File(
      'lib/themes/cupertino/pages/account/sections/bangumi_section.dart',
    ).readAsStringSync();

    expect(account, contains('final data = _buildAccountPageViewModel();'));
    expect(
      account,
      contains('DesktopAccountView(data: data, userActivity: userActivity)'),
    );
    expect(account, contains('data: data.dandanplay'));
    expect(account, contains('data: data.bangumi'));
    expect(account, isNot(contains('_buildDandanplayPage')));
    expect(account, isNot(contains('_buildBangumiPage')));
    expect(account, isNot(contains('_buildLargeScreen')));
    expect(desktop, contains('class DesktopAccountView'));
    expect(
      RegExp(r'Expanded\([\s\S]*data\.dandanplay').hasMatch(desktop),
      isTrue,
    );
    expect(
      RegExp(r'Expanded\([\s\S]*data\.bangumi').hasMatch(desktop),
      isTrue,
    );
    expect(phoneDandanplay, contains('final DandanplayAccountViewModel data'));
    expect(phoneBangumi, contains('final BangumiAccountViewModel data'));
  });

  test('account activity has one state host and adaptive renderers', () {
    final account = File(
      'lib/themes/nipaplay/pages/account/material_account_page.dart',
    ).readAsStringSync();
    final host = File(
      'lib/widgets/user_activity/adaptive_user_activity.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/controllers/user_activity_controller.dart',
    ).readAsStringSync();
    final phone = File(
      'lib/widgets/user_activity/cupertino_user_activity.dart',
    ).readAsStringSync();
    final desktop = File(
      'lib/widgets/user_activity/desktop_user_activity.dart',
    ).readAsStringSync();

    expect(account, contains('final userActivity = AdaptiveUserActivity('));
    expect(account, contains('userActivity: userActivity'));
    expect(host, contains('with UserActivityController'));
    expect(host, contains('final data = UserActivityViewModel('));
    expect(host, contains('CupertinoUserActivity(data: data)'));
    expect(host, contains('DesktopUserActivity(data: data)'));
    expect(controller, isNot(contains('TabController')));
    expect(phone, contains('final UserActivityViewModel data'));
    expect(desktop, contains('final UserActivityViewModel data'));
    expect(desktop, isNot(contains('TabBar(')));
  });

  test('account model owns shared labels and action availability', () {
    var loginCount = 0;
    var syncCount = 0;
    final tokenController = TextEditingController();
    final dandanplay = DandanplayAccountViewModel(
      isLoggedIn: false,
      username: '未登录',
      avatarUrl: null,
      isLoading: false,
      onLogin: () => loginCount++,
      onRegister: () {},
      onLogout: () {},
      onDeleteAccount: () {},
    );
    final bangumi = BangumiAccountViewModel(
      isAuthorized: false,
      userInfo: null,
      isDandanplayLoggedIn: false,
      dandanLinkedInfo: null,
      dandanLinkedExpireTime: null,
      isRequestingDandanAuth: false,
      isRefreshingDandanStatus: false,
      isLoading: false,
      isSyncing: false,
      syncStatus: '',
      lastSyncTime: null,
      tokenController: tokenController,
      onRequestDandanAuth: () {},
      onOpenDandanManage: () {},
      onRefreshDandanStatus: () {},
      onSaveToken: () {},
      onClearToken: () {},
      onSync: () => syncCount++,
      onFullSync: () {},
      onTestConnection: () {},
      onClearCache: () {},
      onOpenDandanHelp: () {},
      onOpenNipaplayHelp: () {},
    );

    expect(dandanplay.actions.map((action) => action.label), [
      '立即登录',
      '注册新账号',
    ]);
    dandanplay.actions.first.onPressed!();
    expect(loginCount, 1);
    expect(bangumi.requestDandanAuthAction.onPressed, isNull);
    expect(bangumi.syncActions.first.label, '增量同步');
    bangumi.syncActions.first.onPressed!();
    expect(syncCount, 1);
    tokenController.dispose();
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

  test('desktop media subtabs share the main label-width indicator', () {
    final controls = File(
      'lib/media_library/adaptive_media_library_controls.dart',
    ).readAsStringSync();
    final mainTabs = File(
      'lib/themes/nipaplay/widgets/nipaplay_main_tab_bar.dart',
    ).readAsStringSync();

    expect(controls, contains('NipaplayLabelTabIndicator('));
    expect(controls, isNot(contains('width: selected ? 32 : 0')));
    expect(mainTabs, contains('selected ? painter.width : 0'));
    expect(mainTabs, contains('TabBarIndicatorSize.label'));
  });

  testWidgets('phone library management renders one item model in both views',
      (tester) async {
    const items = <UnifiedLibraryManagementItem>[
      UnifiedLibraryManagementItem(
        id: 'library-a',
        title: '动画目录',
        subtitle: '/media/anime',
        icon: LibraryManagementIcon.folder,
        onOpen: null,
      ),
    ];

    Future<void> pump(LibraryManagementViewMode viewMode) {
      return tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: CupertinoLibraryManagementOverview(
              items: items,
              viewMode: viewMode,
              emptyTitle: '没有目录',
              emptySubtitle: '请添加目录',
            ),
          ),
        ),
      );
    }

    await pump(LibraryManagementViewMode.icons);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('动画目录'), findsOneWidget);

    await pump(LibraryManagementViewMode.list);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('动画目录'), findsOneWidget);
  });

  testWidgets('desktop library management honors the shared view mode',
      (tester) async {
    Future<void> pump(LibraryManagementViewMode viewMode) {
      return tester.pumpWidget(
        MaterialApp(
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.desktopTablet,
            child: SizedBox(
              width: 900,
              height: 600,
              child: AdaptiveLibraryManagementOverview(
                items: const [
                  UnifiedLibraryManagementItem(
                    id: 'a',
                    title: '目录 A',
                    subtitle: '/media/a',
                    icon: LibraryManagementIcon.folder,
                    onOpen: null,
                  ),
                  UnifiedLibraryManagementItem(
                    id: 'b',
                    title: '目录 B',
                    subtitle: '/media/b',
                    icon: LibraryManagementIcon.folder,
                    onOpen: null,
                  ),
                ],
                viewMode: viewMode,
                emptyContent: const LibraryManagementEmptyContent(
                  title: '没有目录',
                  subtitle: '请添加目录',
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pump(LibraryManagementViewMode.icons);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('目录 A'), findsOneWidget);

    await pump(LibraryManagementViewMode.list);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('目录 B'), findsOneWidget);
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

  test('media collection empty content is shared by both renderers', () {
    final local = mediaCollectionEmptyContent(
      UnifiedMediaLibrarySource.local,
      sourceLabel: '本地媒体库',
    );
    final webdav = mediaCollectionEmptyContent(
      UnifiedMediaLibrarySource.webdav,
      sourceLabel: 'WebDAV媒体库',
    );
    final renderer = File(
      'lib/media_library/adaptive_media_collection_view.dart',
    ).readAsStringSync();

    expect(local.title, '本地媒体库为空');
    expect(local.subtitle, contains('观看或扫描识别'));
    expect(webdav.subtitle, contains('WebDAV 刮削'));
    expect(renderer, contains('_AdaptiveMediaCollectionEmptyState('));
    expect(renderer, isNot(contains('_phoneEmptyState')));
    expect(
      renderer,
      contains("ValueKey<String>('media-collection-empty-state')"),
    );
    expect(
      renderer,
      contains('mainAxisAlignment: material.MainAxisAlignment.center'),
    );
    expect(renderer, contains('cupertino.CupertinoIcons.rectangle_stack'));
    expect(renderer, isNot(contains('material.Icons.video_library_outlined')));
    expect(
      renderer,
      isNot(contains("material.Text(\n          '\$sourceLabel为空'")),
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

  test('torrent page has one model and surface-specific renderers', () {
    final page =
        File('lib/pages/torrent_download_page.dart').readAsStringSync();
    final phone = File(
      'lib/themes/cupertino/widgets/cupertino_torrent_download_controls.dart',
    ).readAsStringSync();
    final phonePage = phone.substring(
      0,
      phone.indexOf('class CupertinoAddTorrentView'),
    );
    final glassGroup = File(
      'lib/themes/cupertino/widgets/cupertino_glass_button_group.dart',
    ).readAsStringSync();
    final dialogs = File(
      'lib/downloads/adaptive_torrent_download_dialogs.dart',
    ).readAsStringSync();

    expect(page, contains('final data = _buildPageViewModel();'));
    expect(page, contains('CupertinoTorrentDownloadView(data: data)'));
    expect(page, contains('DesktopTorrentDownloadView(data: data)'));
    expect(page, contains('TelevisionTorrentDownloadView(data: data)'));
    expect(page, contains('surface == AppDisplaySurface.television'));
    expect(page, contains('final data = _buildViewModel();'));
    expect(page, contains('CupertinoAddTorrentView(data: data)'));
    expect(page, contains('DesktopAddTorrentView(data: data)'));
    expect(phone, contains('final UnifiedTorrentPageViewModel data'));
    expect(phone, contains('final AddTorrentDialogViewModel data'));
    expect(phone, isNot(contains('on _TorrentDownloadPageState')));
    expect(phone, isNot(contains('on _AddMagnetDialogState')));
    expect(phonePage, contains("CupertinoAppPageHeader(title: '下载器'"));
    expect(phonePage, contains("id: 'torrent-view-mode'"));
    expect(phonePage, contains('CupertinoPageActionsScope.maybeOf(context)'));
    expect(phonePage, contains('color: Colors.transparent'));
    expect(
      RegExp('AppAccentColors.current').allMatches(phonePage).length,
      1,
    );
    expect(glassGroup, contains("return 'list.bullet'"));
    expect(glassGroup, contains("return 'square.grid.2x2'"));
    expect(dialogs, contains('showAddTorrent('));
    expect(dialogs, contains('confirmDelete('));
    expect(dialogs, contains('selectPlayableFile('));
    expect(page, isNot(contains('showCupertinoDialog')));
  });

  test('torrent task and dialogs expose shared semantic data', () {
    const task = TorrentTask(
      id: 7,
      infoHash: 'hash-7',
      name: 'Example',
      outputFolder: '/downloads/example',
      state: 'completed',
      progressBytes: 100,
      uploadedBytes: 0,
      totalBytes: 100,
      finished: true,
      downloadSpeedBytesPerSecond: 0,
      uploadSpeedBytesPerSecond: 0,
      error: null,
    );
    var played = false;
    final item = UnifiedTorrentTaskItemViewModel(
      task: task,
      scanSummary: null,
      isAutoScanning: false,
      isAutoScanned: true,
      actions: [
        UnifiedTorrentTaskActionViewModel(
          action: UnifiedTorrentTaskAction.play,
          label: '播放',
          onPressed: () => played = true,
        ),
      ],
    );
    const deleteDialog = TorrentDeleteDialogViewModel(task: task);

    expect(item.primaryAction.label, '播放');
    item.primaryAction.onPressed();
    expect(played, isTrue);
    expect(item.scanStatusText, '已加入媒体库');
    expect(deleteDialog.title, '删除任务和文件');
    expect(deleteDialog.message, contains('Example'));
    expect(formatTorrentBytes(1024), '1.00 KB');
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

  test('playback entry host delegates controls to the adaptive renderer', () {
    final source = File(
      'lib/themes/nipaplay/widgets/video_upload_ui.dart',
    ).readAsStringSync();
    final renderer = File(
      'lib/playback/adaptive_playback_entry_view.dart',
    ).readAsStringSync();
    final selectFileStart = renderer.indexOf(
      'label: data.content.selectFileLabel',
    );
    final selectFileEnd = renderer.indexOf(
      'const material.SizedBox(height: 8)',
      selectFileStart,
    );
    final selectFileButton = renderer.substring(
      selectFileStart,
      selectFileEnd,
    );

    expect(source, contains('AdaptivePlaybackEntryView('));
    expect(source, isNot(contains('TextField(')));
    expect(source, isNot(contains('TextButton(')));
    expect(selectFileButton, isNot(contains('emphasis:')));
  });

  test('add media uses one model with adaptive renderers', () {
    final model = File(
      'lib/media_library/media_source_option.dart',
    ).readAsStringSync();
    final host = File(
      'lib/media_library/adaptive_media_library_controls.dart',
    ).readAsStringSync();
    final desktop = File(
      'lib/themes/nipaplay/widgets/media_server_selection_sheet.dart',
    ).readAsStringSync();
    final phone = File(
      'lib/themes/cupertino/widgets/cupertino_media_source_sheet.dart',
    ).readAsStringSync();

    expect(model, contains('const mediaSourceOptions'));
    for (final id in <String>[
      'local_folder',
      'nipaplay',
      'jellyfin',
      'dandanplay',
      'emby',
      'webdav',
      'smb',
    ]) {
      expect(model, contains("id: '$id'"));
      expect(desktop, isNot(contains("pop('$id')")));
      expect(phone, isNot(contains("value: '$id'")));
    }

    expect(desktop, contains('MediaSourceCategory.values'));
    expect(desktop, contains('option.iconKind'));
    expect(
      desktop,
      isNot(contains('color: accentColor.withValues(alpha: 0.18)')),
    );
    expect(phone, contains('MediaSourceCategory.values'));
    expect(phone, contains('CupertinoListTile('));
    expect(phone, contains('option.subtitle'));
    expect(phone, isNot(contains('color.withValues(alpha: 0.14)')));
    expect(phone, contains('size: 30'));
    expect(host, contains('MediaServerSelectionSheet.show('));
    expect(host, contains('CupertinoMediaSourceSheet.show('));
    expect(host, isNot(contains('CupertinoBottomSheetOption(')));
  });

  testWidgets('playback entry builds Cupertino controls on phone',
      (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: AdaptivePlaybackEntryView(
            content: unifiedPlaybackEntryContent,
            mascotScale: const AlwaysStoppedAnimation<double>(1),
            onMascotTap: () {},
            onSelectFile: () {},
            onOpenUrlInput: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoButton), findsWidgets);
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('playback URL popup builds one adaptive phone form',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final submitting = ValueNotifier<bool>(false);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(submitting.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: AdaptivePlaybackUrlDialogContent(
            content: unifiedPlaybackEntryContent,
            controller: controller,
            focusNode: focusNode,
            isSubmitting: submitting,
            onPaste: () {},
            onEditOneTimeUserAgent: () {},
            onPlay: () async => false,
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
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

  testWidgets('non-iOS 26 phones use liquid glass adaptive controls',
      (tester) async {
    PlatformInfo.setPlatformOverride(PlatformOverride.android);
    PlatformInfo.setPreferCupertinoControls(true);
    addTearDown(() {
      PlatformInfo.setPreferCupertinoControls(false);
      PlatformInfo.clearPlatformOverride();
    });

    await tester.pumpWidget(
      CupertinoApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: Column(
            children: [
              AdaptiveButton(
                label: 'Action',
                onPressed: () {},
              ),
              AdaptiveSwitch(value: true, onChanged: (_) {}),
              AdaptiveSlider(value: 0.5, onChanged: (_) {}),
              AdaptiveSegmentedControl(
                labels: const ['One', 'Two'],
                selectedIndex: 0,
                onValueChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(GlassButton), findsWidgets);
    expect(find.byType(GlassSwitch), findsOneWidget);
    expect(find.byType(GlassSlider), findsOneWidget);
    expect(find.byType(GlassSegmentedControl), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  test('iOS 26 native controls have one liquid-glass fallback layer', () {
    final bridge = File(
      'lib/themes/cupertino/cupertino_adaptive_platform_ui.dart',
    ).readAsStringSync();
    final mainPage = File(
      'lib/themes/cupertino/pages/cupertino_main_page.dart',
    ).readAsStringSync();
    final nativePage = File(
      'lib/themes/cupertino/widgets/cupertino_adaptive_native_page.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/settings/adaptive_settings_widgets.dart',
    ).readAsStringSync();
    final danmaku = File(
      'lib/settings/pages/danmaku_settings_content.dart',
    ).readAsStringSync();
    final remote = File(
      'lib/themes/cupertino/pages/settings/pages/'
      'cupertino_remote_controller_settings_page.dart',
    ).readAsStringSync();
    final dandanplayDialog = File(
      'lib/themes/cupertino/widgets/'
      'cupertino_dandanplay_connection_dialog.dart',
    ).readAsStringSync();
    final networkDialog = File(
      'lib/themes/cupertino/widgets/'
      'cupertino_network_server_connection_dialog.dart',
    ).readAsStringSync();

    for (final control in <String>[
      'GlassButton.custom(',
      'GlassSwitch(',
      'GlassSlider(',
      'GlassSegmentedControl(',
      'GlassDialog.show',
      'GlassTextField(',
    ]) {
      expect(bridge, contains(control));
    }
    expect(mainPage, contains('GlassTabBar.bottom('));
    expect(mainPage, contains('backgroundColor: const Color(0x00000000)'));
    expect(mainPage, contains('Positioned.fill(child: body)'));
    expect(mainPage, contains('bottom: glassTabBarBottom'));
    expect(mainPage, contains('verticalPadding: 0'));
    expect(mainPage, isNot(contains('Expanded(child: body)')));
    expect(nativePage, contains('GlassScaffold('));
    expect(nativePage, contains('GlassAppBar('));
    expect(settings, isNot(contains('fluent.Slider(')));
    expect(danmaku, isNot(contains('PlatformInfo.isIOS26OrHigher()')));
    expect(remote, isNot(contains('PlatformInfo.isIOS26OrHigher()')));
    expect(remote, isNot(contains('fluent.Slider(')));
    expect(dandanplayDialog, contains('AdaptiveAlertDialog.inputShow('));
    expect(networkDialog, contains('AdaptiveAlertDialog.inputShow('));
    expect(dandanplayDialog, isNot(contains('IOS26AlertDialog(')));
    expect(networkDialog, isNot(contains('IOS26AlertDialog(')));
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
    expect(
      find.byKey(
        const ValueKey<String>('cupertino-bottom-sheet-top-scrim'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('open-child')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sheet-child')), findsOneWidget);
    expect(find.text('Child settings'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.byType(AdaptiveScaffold), findsNothing);
    expect(find.byType(CupertinoBottomSheet), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('cupertino-bottom-sheet-top-scrim'),
      ),
      findsOneWidget,
    );

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
