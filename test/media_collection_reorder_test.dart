import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final testCase in <({
    String name,
    AppDisplaySurface surface,
    bool largeScreen,
  })>[
    (
      name: 'desktop grid',
      surface: AppDisplaySurface.desktopTablet,
      largeScreen: false,
    ),
    (
      name: 'phone list',
      surface: AppDisplaySurface.phone,
      largeScreen: false,
    ),
    (
      name: 'television grid',
      surface: AppDisplaySurface.television,
      largeScreen: true,
    ),
  ]) {
    testWidgets('${testCase.name} preserves poster element when items reorder',
        (tester) async {
      final harnessKey = GlobalKey<_MediaCollectionReorderHarnessState>();
      const movedKey = ValueKey<String>('media-collection-local-3');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppearanceSettingsProvider>(
          create: (_) => AppearanceSettingsProvider(),
          child: MaterialApp(
            home: AppDisplaySurfaceScope(
              surface: testCase.surface,
              child: NipaplayLargeScreenModeScope(
                isActive: testCase.largeScreen,
                child: SizedBox(
                  width: 1280,
                  height: 720,
                  child: _MediaCollectionReorderHarness(key: harnessKey),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final elementBefore = tester.element(find.byKey(movedKey));
      harnessKey.currentState!.moveLastToFront();
      await tester.pump();
      final elementAfter = tester.element(find.byKey(movedKey));

      expect(identical(elementAfter, elementBefore), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      ImageCacheManager.instance.clear();
    });
    testWidgets('${testCase.name} updates NEW badge visibility immediately',
        (tester) async {
      final appearance = AppearanceSettingsProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppearanceSettingsProvider>.value(
          value: appearance,
          child: MaterialApp(
            home: AppDisplaySurfaceScope(
              surface: testCase.surface,
              child: NipaplayLargeScreenModeScope(
                isActive: testCase.largeScreen,
                child: const SizedBox(
                  width: 1280,
                  height: 720,
                  child: _MediaCollectionReorderHarness(
                    newAnimeIds: <int>{1},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('NEW'), findsOneWidget);

      await appearance.setShowMediaLibraryNewBadge(false);
      await tester.pump();
      expect(find.text('NEW'), findsNothing);

      await appearance.setShowMediaLibraryNewBadge(true);
      await tester.pump();
      expect(find.text('NEW'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      ImageCacheManager.instance.clear();
    });
  }
}

class _MediaCollectionReorderHarness extends StatefulWidget {
  const _MediaCollectionReorderHarness({
    super.key,
    this.newAnimeIds = const <int>{},
  });

  final Set<int> newAnimeIds;

  @override
  State<_MediaCollectionReorderHarness> createState() =>
      _MediaCollectionReorderHarnessState();
}

class _MediaCollectionReorderHarnessState
    extends State<_MediaCollectionReorderHarness> {
  late List<WatchHistoryItem> _items = <WatchHistoryItem>[
    _item(1),
    _item(2),
    _item(3),
  ];

  void moveLastToFront() {
    setState(() {
      _items = <WatchHistoryItem>[_items.last, ..._items.take(2)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveMediaCollectionItems(
      source: UnifiedMediaLibrarySource.local,
      sourceLabel: '本地媒体库',
      isLoading: false,
      items: _items,
      allHistory: _items,
      details: const {},
      newAnimeIds: widget.newAnimeIds,
      onRefresh: () async {},
      onTap: (_) {},
    );
  }

  static WatchHistoryItem _item(int animeId) {
    return WatchHistoryItem(
      animeId: animeId,
      animeName: '番剧 $animeId',
      episodeTitle: '第1集',
      filePath: '/media/$animeId.mkv',
      lastWatchTime: DateTime(2026, 9, animeId),
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
    );
  }
}
