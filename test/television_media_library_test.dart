import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_view_container.dart';
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('television media library uses remote-first navigation',
      (tester) async {
    String? selectedId;

    await tester.pumpWidget(
      MaterialApp(
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
    expect(selectedId, MediaLibrarySectionIds.localManagement);
  });

  testWidgets('desktop large screen mode opts into television media layout',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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

  testWidgets('television collection renders a focusable poster grid',
      (tester) async {
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
        child: MaterialApp(
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.television,
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
  });

  testWidgets('large screen secondary content has a dedicated container',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NipaplayLargeScreenViewContainer(
          title: '设置',
          subtitle: '遥控器操作',
          child: Center(child: Text('内容区域')),
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
  });
}
