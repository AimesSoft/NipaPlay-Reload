part of '../../../pages/dashboard_home_page.dart';

extension _DashboardHomePageTrending on _DashboardHomePageState {
  TrendingBangumiQuery get _currentTrendingQuery => TrendingBangumiQuery(
        kind: _trendingKind,
        period: _trendingPeriod,
        scope: _trendingScope,
      );

  TrendingBangumiResult? get _currentTrendingResult =>
      _trendingResults[_currentTrendingQuery.cacheKey];

  bool get _isCurrentTrendingLoading =>
      _trendingLoadingKeys.contains(_currentTrendingQuery.cacheKey);

  ScrollController _getTrendingScrollController() {
    _trendingScrollController ??= ScrollController();
    return _trendingScrollController!;
  }

  Future<void> _loadTrending({bool forceRefresh = false}) async {
    await _loadTrendingQuery(
      _currentTrendingQuery,
      forceRefresh: forceRefresh,
    );
  }

  Future<TrendingBangumiResult?> _loadTrendingQuery(
    TrendingBangumiQuery query, {
    bool forceRefresh = false,
  }) async {
    if (!mounted) return null;
    final key = query.cacheKey;
    if (_trendingLoadingKeys.contains(key)) return _trendingResults[key];
    if (!forceRefresh && _trendingResults.containsKey(key)) {
      return _trendingResults[key];
    }

    _updateTrendingState(() {
      _trendingLoadingKeys.add(key);
      if (_currentTrendingQuery.cacheKey == key) {
        _trendingError = null;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final filterAdultContent =
          prefs.getBool('global_filter_adult_content') ?? true;
      final result = await TrendingBangumiService.instance.fetch(
        query,
        forceRefresh: forceRefresh,
        filterAdultContent: filterAdultContent,
        limit: 50,
      );
      if (!mounted) return null;
      _updateTrendingState(() {
        _trendingResults[key] = result;
        _trendingLoadingKeys.remove(key);
        if (_currentTrendingQuery.cacheKey == key) {
          _trendingError = null;
        }
      });
      _resetTrendingScroll();
      return result;
    } catch (error) {
      if (!mounted) return null;
      _updateTrendingState(() {
        _trendingLoadingKeys.remove(key);
        if (_currentTrendingQuery.cacheKey == key) {
          _trendingError = '排行榜加载失败';
        }
      });
      debugPrint('加载排行榜失败: $error');
      return _trendingResults[key];
    }
  }

  Future<TrendingBangumiResult?> _applyTrendingQuery(
    TrendingBangumiQuery query,
  ) async {
    if (_currentTrendingQuery.cacheKey == query.cacheKey) {
      return _currentTrendingResult;
    }
    _updateTrendingState(() {
      _trendingKind = query.kind;
      _trendingPeriod = query.period;
      _trendingScope = query.scope;
      _trendingError = null;
    });
    _resetTrendingScroll();
    return _loadTrendingQuery(query);
  }

  void _resetTrendingScroll() {
    final controller = _trendingScrollController;
    if (controller == null || !controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String _trendingMetric(TrendingBangumiItem item) {
    return _formatTrendingMetric(item, _trendingKind);
  }

  String? _trendingDateLabel(TrendingSummary? summary) {
    return _formatTrendingDateLabel(summary);
  }

  String get _trendingSelectionLabel =>
      '${_trendingKind.label} · ${_currentTrendingQuery.dimensionLabel}';

  Widget _buildTrendingSection() {
    final result = _currentTrendingResult;
    final items = result?.items ?? const <TrendingBangumiItem>[];
    final previewItems = items.take(10).toList(growable: false);
    final loading = _isCurrentTrendingLoading;
    final controller = _getTrendingScrollController();
    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;
    final listHeight = showSummary
        ? HorizontalAnimeCard.detailedListHeight
        : HorizontalAnimeCard.compactListHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '排行榜',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 32),
              _buildScrollButton(
                icon: Icons.tune_rounded,
                onTap: () => _showTrendingFilter(cupertinoStyle: false),
                message: '设置排序方式',
              ),
              const SizedBox(width: 12),
              _buildScrollButton(
                icon: Icons.format_list_numbered_rounded,
                onTap: items.isEmpty
                    ? null
                    : () => _showFullTrendingList(cupertinoStyle: false),
                message: '查看完整榜单',
                enabled: items.isNotEmpty,
              ),
              const SizedBox(width: 12),
              _buildScrollButton(
                icon: Icons.refresh_rounded,
                onTap: loading ? null : () => _loadTrending(forceRefresh: true),
                message: '刷新排行榜',
                enabled: !loading,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_trendingError != null && items.isEmpty)
          _buildTrendingErrorState()
        else if (!loading && items.isEmpty)
          _buildTrendingEmptyState()
        else
          SizedBox(
            height: listHeight,
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: loading && items.isEmpty ? 5 : previewItems.length,
              itemBuilder: (context, index) {
                if (loading && items.isEmpty) {
                  return const HorizontalAnimeSkeleton();
                }
                final item = previewItems[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildTrendingCard(item),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _showTrendingFilter({required bool cupertinoStyle}) async {
    var selectedKind = _trendingKind;
    var selectedPeriod = _trendingPeriod;
    var selectedScope = _trendingScope;

    TrendingBangumiQuery selectedQuery() => TrendingBangumiQuery(
          kind: selectedKind,
          period: selectedPeriod,
          scope: selectedScope,
        );

    late final TrendingBangumiQuery? result;
    if (cupertinoStyle) {
      result = await CupertinoBottomSheet.show<TrendingBangumiQuery>(
        context: context,
        title: '排行榜设置',
        heightRatio: 0.76,
        child: StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Widget optionTile({
              required String label,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return cupertino.CupertinoListTile(
                title: Text(label),
                trailing: selected
                    ? Icon(
                        cupertino.CupertinoIcons.check_mark,
                        color: cupertino.CupertinoTheme.of(sheetContext)
                            .primaryColor,
                      )
                    : null,
                onTap: onTap,
              );
            }

            return SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                children: [
                  cupertino.CupertinoListSection.insetGrouped(
                    header: const Text('榜单类型'),
                    children: [
                      for (final kind in TrendingRankingKind.values)
                        optionTile(
                          label: kind.label,
                          selected: selectedKind == kind,
                          onTap: () => setModalState(() {
                            selectedKind = kind;
                          }),
                        ),
                    ],
                  ),
                  cupertino.CupertinoListSection.insetGrouped(
                    header: Text(
                      selectedKind == TrendingRankingKind.newAnimeHot
                          ? '季度范围'
                          : '统计周期',
                    ),
                    children: selectedKind == TrendingRankingKind.newAnimeHot
                        ? [
                            for (final scope in TrendingNewAnimeScope.values)
                              optionTile(
                                label: scope.label,
                                selected: selectedScope == scope,
                                onTap: () => setModalState(() {
                                  selectedScope = scope;
                                }),
                              ),
                          ]
                        : [
                            for (final period in TrendingPeriod.values)
                              optionTile(
                                label: period.label,
                                selected: selectedPeriod == period,
                                onTap: () => setModalState(() {
                                  selectedPeriod = period;
                                }),
                              ),
                          ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: cupertino.CupertinoButton.filled(
                      onPressed: () => Navigator.of(sheetContext).pop(
                        selectedQuery(),
                      ),
                      child: Text('应用 ${selectedQuery().kind.label} · '
                          '${selectedQuery().dimensionLabel}'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } else {
      result = await NipaplayWindow.show<TrendingBangumiQuery>(
        context: context,
        child: Builder(
          builder: (windowContext) {
            return NipaplayWindowScaffold(
              backgroundImageUrl: null,
              maxWidth: 520,
              maxHeightFactor: 0.58,
              onClose: () => Navigator.of(windowContext).pop(),
              child: StatefulBuilder(
                builder: (sheetContext, setModalState) {
                  final theme = Theme.of(sheetContext);
                  final secondaryColor = theme.colorScheme.onSurfaceVariant;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(52, 16, 44, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '排行榜设置',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '选择首页预览和完整榜单的统计方式',
                              style: TextStyle(
                                color: secondaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                        child: _NipaplayTrendingFilterControls(
                          query: selectedQuery(),
                          onKindChanged: (kind) => setModalState(() {
                            selectedKind = kind;
                          }),
                          onPeriodChanged: (period) => setModalState(() {
                            selectedPeriod = period;
                          }),
                          onScopeChanged: (scope) => setModalState(() {
                            selectedScope = scope;
                          }),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${selectedQuery().kind.label}  ·  '
                                '${selectedQuery().dimensionLabel}',
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            HoverScaleTextButton(
                              text: '取消',
                              onPressed: () =>
                                  Navigator.of(windowContext).pop(),
                            ),
                            const SizedBox(width: 12),
                            HoverScaleTextButton(
                              onPressed: () => Navigator.of(windowContext).pop(
                                selectedQuery(),
                              ),
                              idleColor: AppAccentColors.current,
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded, size: 17),
                                  SizedBox(width: 5),
                                  Text('应用'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      );
    }

    if (result != null && mounted) {
      await _applyTrendingQuery(result);
    }
  }

  Future<void> _showFullTrendingList({required bool cupertinoStyle}) async {
    final result = _currentTrendingResult;
    if (result == null || result.items.isEmpty || !mounted) return;
    final items = result.items;

    if (cupertinoStyle) {
      await CupertinoBottomSheet.show<void>(
        context: context,
        title: '完整排行榜',
        heightRatio: 0.92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCupertinoFullTrendingListSummary(result.summary),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 1),
                itemBuilder: (sheetContext, index) =>
                    _buildCupertinoFullTrendingRow(
                  sheetContext,
                  items[index],
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    await NipaplayWindow.show<void>(
      context: context,
      child: Builder(
        builder: (windowContext) {
          return NipaplayWindowScaffold(
            backgroundImageUrl: null,
            maxWidth: 1120,
            maxHeightFactor: 0.92,
            onClose: () => Navigator.of(windowContext).pop(),
            child: _NipaplayFullTrendingView(
              initialQuery: _currentTrendingQuery,
              initialResult: result,
              onQueryChanged: _applyTrendingQuery,
              onAnimeSelected: (anime) {
                Navigator.of(windowContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showAnimeDetail(anime);
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCupertinoFullTrendingListSummary(TrendingSummary summary) {
    final secondaryColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final labels = <String>[
      _trendingSelectionLabel,
      if (_trendingDateLabel(summary) case final date?) date,
      '共 ${_currentTrendingResult?.items.length ?? 0} 条',
      '数据来源：弹弹play开放弹幕网络',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Text(
        labels.join('  ·  '),
        style: TextStyle(fontSize: 12, color: secondaryColor),
      ),
    );
  }

  Widget _buildCupertinoFullTrendingRow(
    BuildContext sheetContext,
    TrendingBangumiItem item,
  ) {
    final anime = item.anime;
    final title = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
    final secondaryColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      sheetContext,
    );
    final rankColor = item.rank > 0 && item.rank <= 3
        ? AppAccentColors.current
        : secondaryColor;

    void openDetails() {
      Navigator.of(sheetContext).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAnimeDetail(anime);
      });
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              item.rank > 0 ? '#${item.rank}' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rankColor,
                fontSize: item.rank > 0 && item.rank <= 3 ? 17 : 14,
                fontWeight: item.rank > 0 && item.rank <= 3
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: CachedNetworkImageWidget(
              imageUrl: anime.imageUrl,
              width: 48,
              height: 68,
              fit: BoxFit.cover,
              memCacheWidth: 144,
              memCacheHeight: 204,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _trendingMetric(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: secondaryColor),
                ),
              ],
            ),
          ),
          if (anime.rating case final rating?) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                const SizedBox(width: 2),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: openDetails,
      child: content,
    );
  }

  Widget _buildTrendingErrorState() {
    return Container(
      height: 116,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : Colors.black.withValues(alpha: 0.04),
      ),
      child: Center(
        child: TextButton.icon(
          onPressed: () => _loadTrending(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(_trendingError!),
        ),
      ),
    );
  }

  Widget _buildTrendingEmptyState() {
    return Container(
      height: 116,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : Colors.black.withValues(alpha: 0.04),
      ),
      child: Center(
        child: Text(
          '暂无排行榜数据',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingCard(TrendingBangumiItem item) {
    final anime = item.anime;
    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;
    void onTap() => _showAnimeDetail(anime);

    Widget buildCard(String? summary) {
      final card = SizedBox(
        width: showSummary
            ? HorizontalAnimeCard.detailedCardWidth
            : HorizontalAnimeCard.compactCardWidth,
        height: showSummary
            ? HorizontalAnimeCard.detailedCardHeight
            : HorizontalAnimeCard.compactCardHeight,
        child: HorizontalAnimeCard(
          key: ValueKey(
            'trending_${_currentTrendingQuery.cacheKey}_${anime.id}',
          ),
          title: anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
          imageUrl: anime.imageUrl,
          onTap: onTap,
          rating: anime.rating,
          source: '弹弹play',
          progress: _trendingMetric(item),
          summary: summary,
          badgeText: item.rank > 0 ? '#${item.rank}' : null,
        ),
      );
      if (!_isLargeScreenModeActive) return card;
      return _wrapLargeScreenFocusable(
        child: card,
        onActivate: onTap,
        borderRadius: BorderRadius.circular(4),
      );
    }

    return FutureBuilder<BangumiAnime>(
      future: BangumiService.instance.getAnimeDetails(anime.id),
      builder: (context, snapshot) => buildCard(snapshot.data?.summary),
    );
  }

  Widget _buildCupertinoTrendingSection() {
    final result = _currentTrendingResult;
    final items = result?.items ?? const <TrendingBangumiItem>[];
    final previewItems = items.take(10).toList(growable: false);
    final loading = _isCurrentTrendingLoading;
    final secondaryColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCupertinoSectionHeader(
          '排行榜',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCupertinoHomeIconButton(
                label: '设置排序方式',
                icon: cupertino.CupertinoIcons.slider_horizontal_3,
                onPressed: () => _showTrendingFilter(cupertinoStyle: true),
              ),
              _buildCupertinoHomeIconButton(
                label: '查看完整榜单',
                icon: cupertino.CupertinoIcons.list_number,
                onPressed: items.isEmpty
                    ? null
                    : () => _showFullTrendingList(cupertinoStyle: true),
              ),
              _buildCupertinoHomeIconButton(
                label: '刷新排行榜',
                icon: cupertino.CupertinoIcons.refresh,
                onPressed:
                    loading ? null : () => _loadTrending(forceRefresh: true),
                loading: loading,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_trendingError != null && items.isEmpty)
          SizedBox(
            height: 116,
            child: Center(
              child: cupertino.CupertinoButton(
                onPressed: () => _loadTrending(forceRefresh: true),
                child: Text('${_trendingError!}，点击重试'),
              ),
            ),
          )
        else if (!loading && items.isEmpty)
          SizedBox(
            height: 116,
            child: Center(
              child: Text(
                '暂无排行榜数据',
                style: TextStyle(color: secondaryColor),
              ),
            ),
          )
        else
          SizedBox(
            height: 224,
            child: loading && items.isEmpty
                ? const Center(child: cupertino.CupertinoActivityIndicator())
                : ListView.separated(
                    controller: _getTrendingScrollController(),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: previewItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = previewItems[index];
                      final anime = item.anime;
                      return _buildCupertinoPosterCard(
                        imageUrl: anime.imageUrl,
                        title:
                            anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
                        subtitle: _trendingMetric(item),
                        rating: anime.rating,
                        badgeText: item.rank > 0 ? '#${item.rank}' : null,
                        onTap: () => _showAnimeDetail(anime),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}

String _formatTrendingMetric(
  TrendingBangumiItem item,
  TrendingRankingKind kind,
) {
  if (kind == TrendingRankingKind.allRising) {
    final rate = item.heatGrowthRate;
    if (rate != null && rate.isNotEmpty) return '增长 $rate';
    final delta = item.heatDelta;
    if (delta != null && delta.isNotEmpty) return '热度 +$delta';
  }
  final heat = item.heat;
  return heat == null || heat.isEmpty ? '热度统计中' : '热度 $heat';
}

String? _formatTrendingDateLabel(TrendingSummary? summary) {
  if (summary == null) return null;
  final from = summary.dateFrom;
  final to = summary.dateTo;
  if (from != null && to != null) return '$from — $to';
  final latest = summary.latestDataDate;
  return latest == null ? null : '数据截至 $latest';
}

class _NipaplayTrendingFilterControls extends StatefulWidget {
  const _NipaplayTrendingFilterControls({
    required this.query,
    required this.onKindChanged,
    required this.onPeriodChanged,
    required this.onScopeChanged,
    this.compact = false,
  });

  final TrendingBangumiQuery query;
  final ValueChanged<TrendingRankingKind> onKindChanged;
  final ValueChanged<TrendingPeriod> onPeriodChanged;
  final ValueChanged<TrendingNewAnimeScope> onScopeChanged;
  final bool compact;

  @override
  State<_NipaplayTrendingFilterControls> createState() =>
      _NipaplayTrendingFilterControlsState();
}

class _NipaplayTrendingFilterControlsState
    extends State<_NipaplayTrendingFilterControls> {
  final GlobalKey _kindDropdownKey = GlobalKey();
  final GlobalKey _dimensionDropdownKey = GlobalKey();

  Widget _buildField({
    required String label,
    required Widget control,
    bool horizontal = false,
  }) {
    if (horizontal) {
      return Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: control,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        control,
      ],
    );
  }

  Widget _buildKindDropdown() {
    return BlurDropdown<TrendingRankingKind>(
      dropdownKey: _kindDropdownKey,
      items: [
        for (final kind in TrendingRankingKind.values)
          DropdownMenuItemData<TrendingRankingKind>(
            title: kind.label,
            value: kind,
            isSelected: widget.query.kind == kind,
          ),
      ],
      onItemSelected: widget.onKindChanged,
    );
  }

  Widget _buildDimensionDropdown() {
    if (widget.query.kind == TrendingRankingKind.newAnimeHot) {
      return BlurDropdown<TrendingNewAnimeScope>(
        dropdownKey: _dimensionDropdownKey,
        items: [
          for (final scope in TrendingNewAnimeScope.values)
            DropdownMenuItemData<TrendingNewAnimeScope>(
              title: scope.label,
              value: scope,
              isSelected: widget.query.scope == scope,
            ),
        ],
        onItemSelected: widget.onScopeChanged,
      );
    }

    return BlurDropdown<TrendingPeriod>(
      dropdownKey: _dimensionDropdownKey,
      items: [
        for (final period in TrendingPeriod.values)
          DropdownMenuItemData<TrendingPeriod>(
            title: period.label,
            value: period,
            isSelected: widget.query.period == period,
          ),
      ],
      onItemSelected: widget.onPeriodChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField(label: '榜单类型', control: _buildKindDropdown()),
          const SizedBox(height: 20),
          _buildField(
            label: widget.query.kind == TrendingRankingKind.newAnimeHot
                ? '季度范围'
                : '统计周期',
            control: _buildDimensionDropdown(),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = [
          _buildField(
            label: '榜单类型',
            control: _buildKindDropdown(),
            horizontal: true,
          ),
          _buildField(
            label: widget.query.kind == TrendingRankingKind.newAnimeHot
                ? '季度范围'
                : '统计周期',
            control: _buildDimensionDropdown(),
            horizontal: true,
          ),
        ];
        if (constraints.maxWidth < 680) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              fields.first,
              const SizedBox(height: 10),
              fields.last,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: fields.first),
            const SizedBox(width: 30),
            Expanded(child: fields.last),
          ],
        );
      },
    );
  }
}

class _NipaplayFullTrendingView extends StatefulWidget {
  const _NipaplayFullTrendingView({
    required this.initialQuery,
    required this.initialResult,
    required this.onQueryChanged,
    required this.onAnimeSelected,
  });

  final TrendingBangumiQuery initialQuery;
  final TrendingBangumiResult initialResult;
  final Future<TrendingBangumiResult?> Function(TrendingBangumiQuery query)
      onQueryChanged;
  final ValueChanged<BangumiAnime> onAnimeSelected;

  @override
  State<_NipaplayFullTrendingView> createState() =>
      _NipaplayFullTrendingViewState();
}

class _NipaplayFullTrendingViewState extends State<_NipaplayFullTrendingView> {
  late TrendingBangumiQuery _query;
  late TrendingBangumiResult _result;
  bool _loading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _result = widget.initialResult;
  }

  Future<void> _changeQuery(TrendingBangumiQuery query) async {
    if (query.cacheKey == _query.cacheKey) return;
    final requestId = ++_requestId;
    setState(() {
      _query = query;
      _loading = true;
    });
    final result = await widget.onQueryChanged(query);
    if (!mounted || requestId != _requestId) return;
    setState(() {
      if (result != null) _result = result;
      _loading = false;
    });
  }

  void _changeKind(TrendingRankingKind kind) {
    _changeQuery(TrendingBangumiQuery(
      kind: kind,
      period: _query.period,
      scope: _query.scope,
    ));
  }

  void _changePeriod(TrendingPeriod period) {
    _changeQuery(TrendingBangumiQuery(
      kind: _query.kind,
      period: period,
      scope: _query.scope,
    ));
  }

  void _changeScope(TrendingNewAnimeScope scope) {
    _changeQuery(TrendingBangumiQuery(
      kind: _query.kind,
      period: _query.period,
      scope: scope,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryColor = theme.colorScheme.onSurfaceVariant;
    final items = _result.items;
    final dateLabel = _formatTrendingDateLabel(_result.summary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(52, 16, 44, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '完整排行榜',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_query.kind.label}  ·  ${_query.dimensionLabel}  ·  '
                '共 ${items.length} 部',
                style: TextStyle(color: secondaryColor, fontSize: 12),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 11),
          child: _NipaplayTrendingFilterControls(
            query: _query,
            compact: true,
            onKindChanged: _changeKind,
            onPeriodChanged: _changePeriod,
            onScopeChanged: _changeScope,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 7),
          child: Row(
            children: [
              if (dateLabel != null) ...[
                Text(
                  dateLabel,
                  style: TextStyle(color: secondaryColor, fontSize: 11),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  '数据来源：弹弹play开放弹幕网络',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondaryColor, fontSize: 11),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _loading ? 1 : 0,
                child: Text(
                  '正在更新榜单…',
                  style: TextStyle(
                    color: AppAccentColors.current,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: _loading ? 0.58 : 1,
            child: _buildRankingContent(items),
          ),
        ),
      ],
    );
  }

  Widget _buildRankingContent(List<TrendingBangumiItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('暂无排行榜数据'));
    }

    return CustomScrollView(
      key: ValueKey(_query.cacheKey),
      slivers: [
        SliverToBoxAdapter(child: _buildPodium(items.take(3).toList())),
        if (items.length > 3)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisExtent: 285,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index + 3];
                  return _NipaplayRankingCard(
                    item: item,
                    kind: _query.kind,
                    onTap: () => widget.onAnimeSelected(item.anime),
                  );
                },
                childCount: items.length - 3,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPodium(List<TrendingBangumiItem> items) {
    final byRank = <int, TrendingBangumiItem>{
      for (final item in items) item.rank: item,
    };
    final first = byRank[1] ?? (items.isNotEmpty ? items.first : null);
    final second = byRank[2] ?? (items.length > 1 ? items[1] : null);
    final third = byRank[3] ?? (items.length > 2 ? items[2] : null);

    Widget slot(
      TrendingBangumiItem? item, {
      required double width,
      required double height,
    }) {
      if (item == null) return SizedBox(width: width, height: height);
      return _NipaplayRankingCard(
        item: item,
        kind: _query.kind,
        featured: true,
        width: width,
        height: height,
        onTap: () => widget.onAnimeSelected(item.anime),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(300.0, constraints.maxWidth - 40);
        final scale = math.min(1.0, availableWidth / 650);
        final sideWidth = 178.0 * scale;
        final centerWidth = 210.0 * scale;
        final gap = 18.0 * scale;
        return SizedBox(
          height: 326,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              slot(second, width: sideWidth, height: 250 * scale),
              SizedBox(width: gap),
              slot(first, width: centerWidth, height: 304 * scale),
              SizedBox(width: gap),
              slot(third, width: sideWidth, height: 238 * scale),
            ],
          ),
        );
      },
    );
  }
}

class _NipaplayRankingCard extends StatefulWidget {
  const _NipaplayRankingCard({
    required this.item,
    required this.kind,
    required this.onTap,
    this.featured = false,
    this.width,
    this.height,
  });

  final TrendingBangumiItem item;
  final TrendingRankingKind kind;
  final VoidCallback onTap;
  final bool featured;
  final double? width;
  final double? height;

  @override
  State<_NipaplayRankingCard> createState() => _NipaplayRankingCardState();
}

class _NipaplayRankingCardState extends State<_NipaplayRankingCard> {
  bool _hovered = false;

  Color _rankColor(BuildContext context) {
    return switch (widget.item.rank) {
      1 => const Color(0xFFFFC400),
      2 => const Color(0xFF718099),
      3 => const Color(0xFFC56D38),
      _ => Theme.of(context).brightness == Brightness.dark
          ? const Color(0xCC1B1B1B)
          : const Color(0xCC26313A),
    };
  }

  Widget _buildRankBadge(BuildContext context) {
    final rank = widget.item.rank;
    final featuredRank = widget.featured && rank > 0 && rank <= 3;
    return Container(
      constraints: BoxConstraints(minWidth: featuredRank ? 39 : 31),
      padding: EdgeInsets.symmetric(
        horizontal: featuredRank ? 8 : 6,
        vertical: featuredRank ? 5 : 4,
      ),
      decoration: BoxDecoration(
        color: _rankColor(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Text(
        featuredRank ? 'TOP\n$rank' : (rank > 0 ? '#$rank' : '—'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          height: featuredRank ? 1.05 : 1,
          fontSize: featuredRank ? 12 : 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child =
        widget.featured ? _buildFeaturedCard(context) : _buildGridCard(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          scale: _hovered ? 1.025 : 1,
          child: child,
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(BuildContext context) {
    final anime = widget.item.anime;
    final title = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImageWidget(
              imageUrl: anime.imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: ((widget.width ?? 210) * 2).round(),
              memCacheHeight: ((widget.height ?? 304) * 2).round(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.42, 1],
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            Positioned(top: 0, left: 0, child: _buildRankBadge(context)),
            Positioned(
              left: 10,
              right: 9,
              bottom: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.16,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (anime.rating case final rating?) ...[
                        Text(
                          '评分 ${rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          _formatTrendingMetric(widget.item, widget.kind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFA726),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        anime.isFavorited == true
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context) {
    final anime = widget.item.anime;
    final title = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
    final secondaryColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImageWidget(
                  imageUrl: anime.imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  memCacheHeight: 440,
                ),
                Positioned(top: 0, left: 0, child: _buildRankBadge(context)),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xD91B1B1B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatTrendingMetric(widget.item, widget.kind),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFFFFA726),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              anime.rating == null
                  ? '暂无评分'
                  : '评分 ${anime.rating!.toStringAsFixed(1)}',
              style: TextStyle(color: secondaryColor, fontSize: 10),
            ),
            const Spacer(),
            Icon(
              anime.isFavorited == true
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: anime.isFavorited == true
                  ? AppAccentColors.current
                  : secondaryColor,
              size: 15,
            ),
          ],
        ),
      ],
    );
  }
}
