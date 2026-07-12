import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:nipaplay/search/tag_search_controller.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_tag_search_view.dart';

void main() {
  test('tag search controller owns shared text search and pagination state',
      () async {
    final dataSource = _FakeTagSearchDataSource(
      textResults: List.generate(45, _anime),
    );
    final controller = TagSearchController(dataSource: dataSource);

    expect(controller.addTextTag('科幻'), isNull);
    await controller.performSmartSearch();

    expect(dataSource.lastTags, ['科幻']);
    expect(controller.mode, TagSearchMode.text);
    expect(controller.totalResults, 45);
    expect(controller.visibleResults, hasLength(20));

    await controller.loadMoreTextResults();
    expect(controller.visibleResults, hasLength(40));
    await controller.loadMoreTextResults();
    expect(controller.visibleResults, hasLength(45));
    expect(controller.hasMoreText, isFalse);
  });

  test('tag search controller routes shared filters to advanced search',
      () async {
    final dataSource = _FakeTagSearchDataSource(
      advancedResults: [_anime(1)],
    );
    final controller = TagSearchController(dataSource: dataSource)
      ..setKeyword('机器人')
      ..setSelectedYear(2024)
      ..setMinRating(7)
      ..setMaxRating(9);

    await controller.performSmartSearch();

    expect(controller.mode, TagSearchMode.advanced);
    expect(dataSource.advancedKeyword, '机器人');
    expect(dataSource.advancedYear, 2024);
    expect(dataSource.advancedMinRate, 7);
    expect(dataSource.advancedMaxRate, 9);
    expect(controller.visibleResults.single.animeId, 1);
  });

  test('tag validation is shared by every renderer', () {
    final controller = TagSearchController(
      dataSource: _FakeTagSearchDataSource(),
    );

    for (var index = 0; index < 10; index++) {
      expect(controller.addTextTag('tag-$index'), isNull);
    }
    expect(controller.addTextTag('tag-10'), '最多只能添加10个标签');
  });

  testWidgets('Cupertino tag search renderer fits a narrow phone viewport',
      (tester) async {
    PlatformInfo.setPlatformOverride(PlatformOverride.ios, iosVersion: 26);
    addTearDown(PlatformInfo.clearPlatformOverride);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TagSearchController(
      dataSource: _FakeTagSearchDataSource(),
      suggestedTags: const ['科幻', '日常', '冒险'],
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: CupertinoTagSearchView(
            controller: controller,
            onOpenAnimeDetail: (_) {},
            onMessage: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    expect(find.byType(AdaptiveSlider), findsNWidgets(2));
    expect(find.byType(IOS26Slider), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

SearchResultAnime _anime(int index) {
  return SearchResultAnime(
    animeId: index,
    animeTitle: 'Anime $index',
    type: 'tvseries',
    episodeCount: 12,
    rating: 8,
    isFavorited: false,
  );
}

class _FakeTagSearchDataSource implements TagSearchDataSource {
  _FakeTagSearchDataSource({
    this.textResults = const [],
    this.advancedResults = const [],
  });

  final List<SearchResultAnime> textResults;
  final List<SearchResultAnime> advancedResults;
  List<String>? lastTags;
  String? advancedKeyword;
  int? advancedYear;
  int? advancedMinRate;
  int? advancedMaxRate;

  @override
  Future<SearchConfig> loadConfig() async {
    return SearchConfig(
      types: const [],
      tags: const [],
      sorts: const [],
      minYear: 2000,
      maxYear: 2026,
    );
  }

  @override
  Future<SearchResult> searchByTags(List<String> tags) async {
    lastTags = List.of(tags);
    return SearchResult(animes: textResults);
  }

  @override
  Future<SearchResult> searchAdvanced({
    String? keyword,
    int? type,
    List<int>? tagIds,
    int? year,
    required int minRate,
    required int maxRate,
    required int sort,
  }) async {
    advancedKeyword = keyword;
    advancedYear = year;
    advancedMinRate = minRate;
    advancedMaxRate = maxRate;
    return SearchResult(animes: advancedResults);
  }
}
