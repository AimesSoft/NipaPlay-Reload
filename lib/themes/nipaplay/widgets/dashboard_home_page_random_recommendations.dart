part of dashboard_home_page;

extension DashboardHomePageRandomRecommendations on _DashboardHomePageState {
  ScrollController _getRandomRecommendationsScrollController() {
    _randomRecommendationsScrollController ??= ScrollController();
    return _randomRecommendationsScrollController!;
  }

  Future<void> _loadRandomRecommendations({bool forceRefresh = false}) async {
    if (!mounted || _isLoadingRandomRecommendations) return;
    if (forceRefresh && _randomRecommendationGroups.isNotEmpty) {
      _showNextRandomRecommendationGroup();
      return;
    }
    if (!forceRefresh && _randomRecommendations.isNotEmpty) return;

    setState(() => _isLoadingRandomRecommendations = true);

    try {
      final daily = await RandomRecommendationService.instance
          .fetchDailyRecommendations();
      final groups =
          daily.groups.where((group) => group.items.isNotEmpty).toList();
      final groupIndex = _randomRecommendationGroupIndex % groups.length;

      if (mounted) {
        setState(() {
          _randomRecommendationGroups = groups;
          _randomRecommendationGroupIndex = groupIndex;
          _randomRecommendations = groups[groupIndex].items;
          _isLoadingRandomRecommendations = false;
        });
        _resetRandomRecommendationScroll();
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
          height:
              context.watch<AppearanceSettingsProvider>().showAnimeCardSummary
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

    final onTap = () => ThemedAnimeDetail.show(context, anime.animeId);
    final card = SizedBox(
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
        onTap: onTap,
        source: sourceLabel,
        rating: anime.rating > 0 ? anime.rating : null,
        summary: summary,
      ),
    );
    if (!_isLargeScreenModeActive) {
      return card;
    }
    return _wrapLargeScreenFocusable(
      child: card,
      onActivate: onTap,
      borderRadius: BorderRadius.circular(4),
    );
  }

  String _formatRandomTagLabel(String tag) {
    if (tag.isEmpty) return '随机';
    const maxLength = 8;
    if (tag.length <= maxLength) return '#$tag';
    return '#${tag.substring(0, maxLength)}...';
  }

  void _showNextRandomRecommendationGroup() {
    final groups = _randomRecommendationGroups
        .where((group) => group.items.isNotEmpty)
        .toList();
    if (groups.isEmpty) return;
    final nextIndex = (_randomRecommendationGroupIndex + 1) % groups.length;
    setState(() {
      _randomRecommendationGroupIndex = nextIndex;
      _randomRecommendations = groups[nextIndex].items;
    });
    _resetRandomRecommendationScroll();
  }

  void _resetRandomRecommendationScroll() {
    final controller = _randomRecommendationsScrollController;
    if (controller == null || !controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }
}
