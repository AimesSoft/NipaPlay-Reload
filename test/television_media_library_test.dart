import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/media_library/media_source_option.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_view_container.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sections = <UnifiedMediaLibrarySection>[
  UnifiedMediaLibrarySection(
    id: MediaLibrarySectionIds.local,
    label: '本地媒体库',
    phoneSymbol: 'rectangle.stack',
    contentType: UnifiedMediaLibraryContentType.mediaCollection,
    source: UnifiedMediaLibrarySource.local,
  ),
  UnifiedMediaLibrarySection(
    id: MediaLibrarySectionIds.localManagement,
    label: '本地库管理',
    phoneSymbol: 'folder',
    contentType: UnifiedMediaLibraryContentType.libraryManagement,
    source: UnifiedMediaLibrarySource.local,
  ),
];

Widget _testApp({required Widget home, ThemeData? theme}) {
  return ChangeNotifierProvider<LargeScreenUiSfxService>(
    create: (_) => LargeScreenUiSfxService(),
    child: MaterialApp(
      theme: theme,
      home: home,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('televisions exclude local library sections and local folders', () {
    expect(
      shouldExposeLocalMediaLibrary(isWeb: false, isTelevision: true),
      isFalse,
    );
    expect(
      shouldExposeLocalMediaLibrary(isWeb: false, isTelevision: false),
      isTrue,
    );
    final tvOSSections = buildUnifiedMediaLibrarySections(
      MediaLibraryAvailability(
        showLocal: shouldExposeLocalMediaLibrary(
          isWeb: false,
          isTelevision: true,
        ),
        showWebDAVLibrary: false,
        showWebDAVManagement: false,
        showSMBLibrary: false,
        showSMBManagement: false,
        showShared: false,
        showDandanplay: false,
        showJellyfin: true,
        showEmby: false,
      ),
    );
    expect(
      tvOSSections.map((section) => section.id),
      isNot(contains(MediaLibrarySectionIds.local)),
    );
    expect(
      tvOSSections.map((section) => section.id),
      isNot(contains(MediaLibrarySectionIds.localManagement)),
    );

    final televisionOptions = availableMediaSourceOptions(isTelevision: true);
    expect(
      televisionOptions.map((option) => option.id),
      isNot(contains('local_folder')),
    );
    expect(
      televisionOptions.map((option) => option.id),
      contains('nipaplay'),
    );
    expect(
      availableMediaSourceOptions(isTelevision: false)
          .map((option) => option.id),
      contains('local_folder'),
    );
  });
  testWidgets('television media library shows controls and selects sections',
      (tester) async {
    String? selectedId;

    await tester.pumpWidget(
      _testApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.television,
          child: AdaptiveMediaLibraryScaffold(
            sections: _sections,
            selectedSection: _sections.first,
            onSectionSelected: (value) => selectedId = value,
            onSectionOrderChanged: (_) {},
            onRemoteAccess: () {},
            onAddMedia: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('television-media-library')),
      findsOneWidget,
    );
    expect(find.text('调整顺序'), findsOneWidget);
    expect(
      find.byType(NipaplayLargeScreenFocusableAction),
      findsWidgets,
    );

    await tester.tap(find.text('本地库管理'));
    await tester.pump();
    expect(selectedId, MediaLibrarySectionIds.localManagement);
  });

  testWidgets('desktop large screen mode opts into television media layout',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.desktopTablet,
          child: NipaplayLargeScreenModeScope(
            isActive: true,
            child: AdaptiveMediaLibraryScaffold(
              sections: _sections,
              selectedSection: _sections.first,
              onSectionSelected: (_) {},
              onSectionOrderChanged: (_) {},
              onRemoteAccess: () {},
              onAddMedia: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('television-media-library')),
      findsOneWidget,
    );
  });

  testWidgets('large screen host selection preserves mode across its route',
      (tester) async {
    final provider = SharedRemoteLibraryProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SharedRemoteLibraryProvider>.value(
        value: provider,
        child: _testApp(
          home: NipaplayLargeScreenModeScope(
            isActive: true,
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    await SharedRemoteHostSelectionSheet.show(context);
                  },
                  child: const Text('打开共享客户端'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开共享客户端'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('large-screen-view-container')),
      findsOneWidget,
    );
    final scanAction = find.widgetWithText(
      NipaplayLargeScreenActionButton,
      '扫描局域网',
    );
    expect(scanAction, findsOneWidget);
    expect(
      tester.widget<NipaplayLargeScreenActionButton>(scanAction).autofocus,
      isTrue,
    );
  });
  testWidgets('desktop large-screen collection uses light theme card text',
      (tester) async {
    final lightTheme = ThemeData.light();
    final item = WatchHistoryItem(
      animeId: 42,
      animeName: '测试番剧',
      episodeTitle: '第一集',
      filePath: '/media/test.mkv',
      lastWatchTime: DateTime(2026),
      watchProgress: 0.5,
      lastPosition: 60,
      duration: 120,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceSettingsProvider>(
        create: (_) => AppearanceSettingsProvider(),
        child: _testApp(
          theme: lightTheme,
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.desktopTablet,
            child: NipaplayLargeScreenModeScope(
              isActive: true,
              child: SizedBox(
                width: 1280,
                height: 720,
                child: AdaptiveMediaCollectionItems(
                  source: UnifiedMediaLibrarySource.local,
                  sourceLabel: '本地媒体库',
                  isLoading: false,
                  items: <WatchHistoryItem>[item],
                  allHistory: <WatchHistoryItem>[item],
                  details: const {},
                  onRefresh: () async {},
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('television-media-collection-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('television-media-poster-42')),
      findsOneWidget,
    );
    expect(
      find.byType(NipaplayLargeScreenFocusableAction),
      findsOneWidget,
    );
    final title = tester.widget<Text>(find.text('测试番剧'));
    expect(
      title.style?.color,
      lightTheme.colorScheme.onSurface.withValues(alpha: 0.9),
    );
  });

  testWidgets('large screen secondary content has a dedicated container',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        home: NipaplayLargeScreenViewContainer(
          title: '设置',
          subtitle: '遥控器操作',
          child: const Center(child: Text('内容区域')),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('large-screen-view-container')),
      findsOneWidget,
    );
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('内容区域'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    final lightDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey<String>('large-screen-view-container')),
        )
        .decoration as BoxDecoration;
    expect(lightDecoration.color, const Color(0xFFF5F5F5));

    await tester.pumpWidget(
      _testApp(
        home: Theme(
          data: ThemeData.dark(),
          child: const NipaplayLargeScreenViewContainer(
            key: ValueKey<String>('dark-large-screen-container'),
            title: '设置',
            child: Center(child: Text('内容区域')),
          ),
        ),
      ),
    );

    final darkDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey<String>('large-screen-view-container')),
        )
        .decoration as BoxDecoration;
    expect(darkDecoration.color, const Color(0xFF181818));
  });
}
