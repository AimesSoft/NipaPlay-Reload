part of dashboard_home_page;

const _blockedRandomRecommendationKeywords = <String>[
  '我的英雄学院',
  '我的英雄學院',
  '僕のヒーローアカデミア',
  'ヒロアカ',
  'my hero academia',
  'boku no hero academia',
  'hero academia',
  'mha',
];

class RandomRecommendationItem {
  final String tag;
  final SearchResultAnime anime;

  const RandomRecommendationItem({
    required this.tag,
    required this.anime,
  });
}

class _RandomTagSearchResult {
  final String tag;
  final List<SearchResultAnime> animes;

  const _RandomTagSearchResult(this.tag, this.animes);
}

extension DashboardHomePageRandomRecommendations on _DashboardHomePageState {
  ScrollController _getRandomRecommendationsScrollController() {
    _randomRecommendationsScrollController ??= ScrollController();
    return _randomRecommendationsScrollController!;
  }

  Future<void> _loadRandomRecommendations({bool forceRefresh = false}) async {
    if (!mounted || _isLoadingRandomRecommendations) return;
    if (!forceRefresh && _randomRecommendations.isNotEmpty) return;

    setState(() => _isLoadingRandomRecommendations = true);

    try {
      final config = await SearchService.instance.getSearchConfig();
      final tags = config.tags
          .map((tag) => tag.value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      if (tags.isEmpty) {
        if (mounted) {
          setState(() {
            _randomRecommendations = [];
            _isLoadingRandomRecommendations = false;
          });
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final bool filterAdultContentGlobally =
          prefs.getBool('global_filter_adult_content') ?? true;

      final random = math.Random();
      tags.shuffle(random);

      final items = <RandomRecommendationItem>[];
      final usedAnimeIds = <int>{};

      for (int start = 0; start < tags.length && items.length < 5; start += 5) {
        final batch = tags.sublist(start, math.min(start + 5, tags.length));
        final futures = batch.map((tag) async {
          try {
            final result = await SearchService.instance.searchAnimeByTags([tag]);
            return _RandomTagSearchResult(tag, result.animes);
          } catch (e) {
            debugPrint('随机推荐标签搜索失败: $tag, error: $e');
            return null;
          }
        }).toList();

        final results = await Future.wait(futures, eagerError: false);
        for (final entry in results) {
          if (entry == null) continue;

          final cappedResults = entry.animes.take(100).toList();
          final candidates = cappedResults.where((anime) {
            if (anime.animeId <= 0 || anime.animeTitle.isEmpty) return false;
            if (anime.imageUrl == null || anime.imageUrl!.isEmpty) return false;
            if (filterAdultContentGlobally && anime.isRestricted == true) {
              return false;
            }
            if (_isMyHeroAcademiaRelated(anime)) return false;
            return true;
          }).toList();

          if (candidates.isEmpty) continue;

          candidates.shuffle(random);
          SearchResultAnime? selected;
          for (final anime in candidates) {
            if (!usedAnimeIds.contains(anime.animeId)) {
              selected = anime;
              break;
            }
          }

          if (selected != null) {
            usedAnimeIds.add(selected.animeId);
            items.add(RandomRecommendationItem(tag: entry.tag, anime: selected));
          }

          if (items.length >= 5) break;
        }
      }

      if (mounted) {
        setState(() {
          _randomRecommendations = items;
          _isLoadingRandomRecommendations = false;
        });
      }
    } catch (e) {
      debugPrint('加载随机推荐失败: $e');
      if (mounted) setState(() => _isLoadingRandomRecommendations = false);
    }
  }

  Widget _buildRandomRecommendationsSection() {
    if (_randomRecommendations.isEmpty && !_isLoadingRandomRecommendations) {
      return const SizedBox.shrink();
    }

    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final scrollController = _getRandomRecommendationsScrollController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '随机推荐',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              if (!isPhone &&
                  (_randomRecommendations.isNotEmpty ||
                      _isLoadingRandomRecommendations)) ...[
                _buildScrollButtons(scrollController, 162),
                const SizedBox(width: 12),
                _buildScrollButton(
                  icon: Icons.refresh_rounded,
                  onTap: _isLoadingRandomRecommendations
                      ? null
                      : () => _loadRandomRecommendations(forceRefresh: true),
                  message: '刷新',
                  enabled: !_isLoadingRandomRecommendations,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: context.watch<AppearanceSettingsProvider>().showAnimeCardSummary
              ? HorizontalAnimeCard.detailedListHeight
              : HorizontalAnimeCard.compactListHeight,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _isLoadingRandomRecommendations
                ? 5
                : _randomRecommendations.length,
            itemBuilder: (context, index) {
              if (_isLoadingRandomRecommendations) {
                return const HorizontalAnimeSkeleton();
              }
              final item = _randomRecommendations[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildRandomRecommendationCard(item),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRandomRecommendationCard(RandomRecommendationItem item) {
    final anime = item.anime;
    final summary = (anime.intro != null && anime.intro!.isNotEmpty)
        ? anime.intro!
        : anime.typeDescription;
    final sourceLabel = _formatRandomTagLabel(item.tag);

    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;

    return SizedBox(
      width: showSummary
          ? HorizontalAnimeCard.detailedCardWidth
          : HorizontalAnimeCard.compactCardWidth,
      height: showSummary
          ? HorizontalAnimeCard.detailedCardHeight
          : HorizontalAnimeCard.compactCardHeight,
      child: HorizontalAnimeCard(
        key: ValueKey('random_${anime.animeId}_${item.tag.hashCode}'),
        title: anime.animeTitle,
        imageUrl: anime.imageUrl ?? '',
        onTap: () => ThemedAnimeDetail.show(context, anime.animeId),
        source: sourceLabel,
        rating: anime.rating > 0 ? anime.rating : null,
        summary: summary,
      ),
    );
  }

  String _formatRandomTagLabel(String tag) {
    if (tag.isEmpty) return '随机';
    const maxLength = 8;
    if (tag.length <= maxLength) return '#$tag';
    return '#${tag.substring(0, maxLength)}...';
  }

  bool _isMyHeroAcademiaRelated(SearchResultAnime anime) {
    final title = anime.animeTitle.trim();
    if (title.isEmpty) return false;
    final normalizedTitle = title.toLowerCase();
    return _blockedRandomRecommendationKeywords
        .any((keyword) => normalizedTitle.contains(keyword));
  }
}
