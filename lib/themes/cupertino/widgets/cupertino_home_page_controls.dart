part of dashboard_home_page;

extension _CupertinoHomePageControls on _DashboardHomePageState {
  Future<void> _refreshCupertinoHome() async {
    await Future.wait([
      _refreshContinueWatchingData(
        '手机主页手动刷新',
        syncRemote: true,
      ),
      _loadData(
        forceRefreshRecommended: true,
        forceRefreshRandom: true,
        forceRefreshToday: true,
      ),
    ]);
  }

  Widget _buildCupertinoHomePage() {
    final sectionsProvider = context.watch<HomeSectionsSettingsProvider>();

    return ColoredBox(
      color: Colors.transparent,
      child: CustomScrollView(
        controller: _mainScrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          cupertino.CupertinoSliverRefreshControl(
            onRefresh: _refreshCupertinoHome,
          ),
          const SliverToBoxAdapter(
            child: CupertinoAppPageHeader(title: '主页'),
          ),
          SliverToBoxAdapter(child: _buildCupertinoHero()),
          ..._buildCupertinoConfiguredSections(sectionsProvider),
          const SliverPadding(padding: EdgeInsets.only(bottom: 84)),
        ],
      ),
    );
  }

  List<Widget> _buildCupertinoConfiguredSections(
    HomeSectionsSettingsProvider sectionsProvider,
  ) {
    final slivers = <Widget>[];

    void addSection(Widget section) {
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 22)));
      slivers.add(SliverToBoxAdapter(child: section));
    }

    for (final component in _buildHomeComponents(sectionsProvider)) {
      switch (component.type) {
        case UnifiedHomeComponentType.hero:
          break;
        case UnifiedHomeComponentType.todaySeries:
          addSection(_buildCupertinoTodaySection());
          break;
        case UnifiedHomeComponentType.randomRecommendations:
          addSection(_buildCupertinoRandomSection());
          break;
        case UnifiedHomeComponentType.continueWatching:
          addSection(_buildCupertinoContinueWatching());
          break;
        case UnifiedHomeComponentType.remoteLibraries:
          for (final entry in _recentJellyfinItemsByLibrary.entries) {
            addSection(
              _buildCupertinoMediaSection<JellyfinMediaItem>(
                title: 'Jellyfin - 新增${entry.key}',
                items: entry.value,
                imageUrl: (item) {
                  try {
                    return JellyfinService.instance.getImageUrl(item.id);
                  } catch (_) {
                    return '';
                  }
                },
                itemTitle: (item) => item.name,
                subtitle: (item) => item.productionYear?.toString(),
                rating: (item) => double.tryParse(item.communityRating ?? ''),
                onTap: _onJellyfinItemTap,
              ),
            );
          }
          for (final entry in _recentEmbyItemsByLibrary.entries) {
            addSection(
              _buildCupertinoMediaSection<EmbyMediaItem>(
                title: 'Emby - 新增${entry.key}',
                items: entry.value,
                imageUrl: (item) {
                  try {
                    return EmbyService.instance.getImageUrl(item.id);
                  } catch (_) {
                    return '';
                  }
                },
                itemTitle: (item) => item.name,
                subtitle: (item) => item.productionYear?.toString(),
                rating: (item) => double.tryParse(item.communityRating ?? ''),
                onTap: _onEmbyItemTap,
              ),
            );
          }
          if (_recentDandanplayGroups.isNotEmpty) {
            addSection(
              _buildCupertinoMediaSection<DandanplayRemoteAnimeGroup>(
                title: '弹弹play - 最近添加',
                items: _recentDandanplayGroups,
                imageUrl: _getDandanGroupImage,
                itemTitle: (item) => item.title,
                subtitle: (item) => '${item.episodeCount} 集',
                onTap: _onDandanplayGroupTap,
              ),
            );
          }
          break;
        case UnifiedHomeComponentType.localLibrary:
          addSection(
            _buildCupertinoMediaSection<LocalAnimeItem>(
              title: '本地媒体库 - 最近添加',
              items: _localAnimeItems,
              imageUrl: (item) =>
                  item.imageUrl ?? _localImageCache[item.animeId] ?? '',
              itemTitle: (item) => item.animeName,
              subtitle: (item) => item.latestEpisode.episodeTitle,
              onTap: _onLocalAnimeItemTap,
            ),
          );
          break;
      }
    }
    return slivers;
  }

  Widget _buildCupertinoHero() {
    if (_isLoadingRecommended && _recommendedItems.isEmpty) {
      return const SizedBox(
        height: 236,
        child: Center(child: cupertino.CupertinoActivityIndicator()),
      );
    }
    if (_recommendedItems.isEmpty) {
      return _buildCupertinoEmptySection('暂无推荐内容');
    }

    final items = _recommendedItems.take(5).toList(growable: false);
    return SizedBox(
      height: 250,
      child: PageView.builder(
        controller: _heroBannerPageController,
        itemCount: items.length,
        onPageChanged: (index) {
          _currentHeroBannerIndex = index;
          _heroBannerIndexNotifier.value = index;
          _stopAutoSwitch();
          Timer(const Duration(seconds: 3), _resumeAutoSwitch);
        },
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onRecommendedItemTap(item),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildCupertinoImage(
                      item.backgroundImageUrl,
                      fit: BoxFit.cover,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.78),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.rating != null)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _buildCupertinoRating(item.rating!),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCupertinoTodaySection() {
    return _buildCupertinoMediaSection<BangumiAnime>(
      title: '今日新番',
      items: _todayAnimes,
      loading: _isLoadingTodayAnimes,
      imageUrl: (item) => item.imageUrl,
      itemTitle: (item) => item.nameCn.isNotEmpty ? item.nameCn : item.name,
      subtitle: (item) => item.airDate,
      rating: (item) => item.rating,
      onTap: _showAnimeDetail,
      action: cupertino.CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        onPressed: _showTagSearchModal,
        child: const Icon(cupertino.CupertinoIcons.search, size: 19),
      ),
    );
  }

  Widget _buildCupertinoRandomSection() {
    return _buildCupertinoMediaSection<RandomRecommendationItem>(
      title: '随机推荐',
      items: _randomRecommendations,
      loading: _isLoadingRandomRecommendations,
      imageUrl: (item) => item.anime.imageUrl ?? '',
      itemTitle: (item) => item.anime.animeTitle,
      subtitle: (item) => _formatRandomTagLabel(item.tag),
      rating: (item) => item.anime.rating > 0 ? item.anime.rating : null,
      onTap: (item) => ThemedAnimeDetail.show(
        context,
        item.anime.animeId,
      ),
      action: cupertino.CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        onPressed: _isLoadingRandomRecommendations
            ? null
            : () => _loadRandomRecommendations(forceRefresh: true),
        child: const Icon(cupertino.CupertinoIcons.refresh, size: 19),
      ),
    );
  }

  Widget _buildCupertinoContinueWatching() {
    return Consumer<WatchHistoryProvider>(
      builder: (context, history, _) {
        final items = history.continueWatchingItems.take(10).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCupertinoSectionHeader(
              '继续播放',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  cupertino.CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(36),
                    onPressed: () => unawaited(_showWatchHistoryDialog()),
                    child: const Icon(
                      cupertino.CupertinoIcons.time,
                      size: 19,
                    ),
                  ),
                  cupertino.CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(36),
                    onPressed: _isContinueWatchingRefreshInProgress
                        ? null
                        : _onContinueWatchingRefreshPressed,
                    child: _isContinueWatchingRefreshInProgress
                        ? const cupertino.CupertinoActivityIndicator(radius: 8)
                        : const Icon(
                            cupertino.CupertinoIcons.refresh,
                            size: 19,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              _buildCupertinoEmptySection('暂无播放记录')
            else
              SizedBox(
                height: 196,
                child: ListView.separated(
                  controller: _continueWatchingScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _isHistoryAutoMatching
                          ? null
                          : () => _onWatchHistoryItemTap(item),
                      child: SizedBox(
                        width: 224,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 124,
                                width: 224,
                                child: _getVideoThumbnail(item),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              item.animeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            _buildCupertinoProgress(item.watchProgress),
                            const SizedBox(height: 3),
                            Text(
                              '${(item.watchProgress * 100).round()}%'
                              '${item.episodeTitle == null ? '' : ' · ${item.episodeTitle}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cupertino.CupertinoDynamicColor.resolve(
                                  cupertino.CupertinoColors.secondaryLabel,
                                  context,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCupertinoMediaSection<T>({
    required String title,
    required List<T> items,
    required String Function(T item) imageUrl,
    required String Function(T item) itemTitle,
    required void Function(T item) onTap,
    String? Function(T item)? subtitle,
    double? Function(T item)? rating,
    bool loading = false,
    Widget? action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCupertinoSectionHeader(title, action: action),
        const SizedBox(height: 10),
        SizedBox(
          height: 224,
          child: loading && items.isEmpty
              ? const Center(child: cupertino.CupertinoActivityIndicator())
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildCupertinoPosterCard(
                      imageUrl: imageUrl(item),
                      title: itemTitle(item),
                      subtitle: subtitle?.call(item),
                      rating: rating?.call(item),
                      onTap: () => onTap(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCupertinoSectionHeader(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _buildCupertinoPosterCard({
    required String imageUrl,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    double? rating,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 126,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  SizedBox(
                    width: 126,
                    height: 172,
                    child: _buildCupertinoImage(imageUrl, fit: BoxFit.cover),
                  ),
                  if (rating != null)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: _buildCupertinoRating(rating),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: cupertino.CupertinoDynamicColor.resolve(
                    cupertino.CupertinoColors.secondaryLabel,
                    context,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoImage(String? imageUrl, {required BoxFit fit}) {
    final url = imageUrl?.trim() ?? '';
    final placeholderColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGrey5,
      context,
    );
    if (url.isEmpty) {
      return ColoredBox(
        color: placeholderColor,
        child: const Center(
          child: Icon(
            cupertino.CupertinoIcons.photo,
            color: cupertino.CupertinoColors.systemGrey,
          ),
        ),
      );
    }
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: fit,
        errorBuilder: (_, __, ___) => ColoredBox(color: placeholderColor),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) => ColoredBox(color: placeholderColor),
      errorWidget: (_, __, ___) => ColoredBox(color: placeholderColor),
    );
  }

  Widget _buildCupertinoRating(double rating) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoProgress(double value) {
    final progress = value.clamp(0.0, 1.0);
    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGrey4,
      context,
    );
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: ColoredBox(
          color: background,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: ColoredBox(
                color: cupertino.CupertinoTheme.of(context).primaryColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoEmptySection(String message) {
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(message, style: TextStyle(color: secondary)),
      ),
    );
  }
}
