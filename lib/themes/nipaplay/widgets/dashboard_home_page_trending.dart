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
    if (!mounted) return;
    final query = _currentTrendingQuery;
    final key = query.cacheKey;
    if (_trendingLoadingKeys.contains(key)) return;
    if (!forceRefresh && _trendingResults.containsKey(key)) return;

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
      if (!mounted) return;
      _updateTrendingState(() {
        _trendingResults[key] = result;
        _trendingLoadingKeys.remove(key);
        if (_currentTrendingQuery.cacheKey == key) {
          _trendingError = null;
        }
      });
      _resetTrendingScroll();
    } catch (error) {
      if (!mounted) return;
      _updateTrendingState(() {
        _trendingLoadingKeys.remove(key);
        if (_currentTrendingQuery.cacheKey == key) {
          _trendingError = '排行榜加载失败';
        }
      });
      debugPrint('加载排行榜失败: $error');
    }
  }

  void _applyTrendingQuery(TrendingBangumiQuery query) {
    if (_currentTrendingQuery.cacheKey == query.cacheKey) return;
    _updateTrendingState(() {
      _trendingKind = query.kind;
      _trendingPeriod = query.period;
      _trendingScope = query.scope;
      _trendingError = null;
    });
    _resetTrendingScroll();
    unawaited(_loadTrending());
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
    if (_trendingKind == TrendingRankingKind.allRising) {
      final rate = item.heatGrowthRate;
      if (rate != null && rate.isNotEmpty) return '增长 $rate';
      final delta = item.heatDelta;
      if (delta != null && delta.isNotEmpty) return '热度 +$delta';
    }
    final heat = item.heat;
    return heat == null || heat.isEmpty ? '热度统计中' : '热度 $heat';
  }

  String? _trendingDateLabel(TrendingSummary? summary) {
    if (summary == null) return null;
    final from = summary.dateFrom;
    final to = summary.dateTo;
    if (from != null && to != null) return '$from — $to';
    final latest = summary.latestDataDate;
    return latest == null ? null : '数据截至 $latest';
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
              const Spacer(),
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
            final isDark =
                Theme.of(windowContext).brightness == Brightness.dark;
            return NipaplayWindowScaffold(
              backgroundImageUrl: null,
              backgroundColor: isDark
                  ? Colors.black.withValues(alpha: 0.56)
                  : const Color(0xFFF4F5F8).withValues(alpha: 0.68),
              backdropBlurSigma: 34,
              borderColor: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.78),
              maxWidth: 640,
              maxHeightFactor: 0.68,
              onClose: () => Navigator.of(windowContext).pop(),
              child: StatefulBuilder(
                builder: (sheetContext, setModalState) {
                  final theme = Theme.of(sheetContext);
                  final isDark = theme.brightness == Brightness.dark;
                  final secondaryColor = theme.colorScheme.onSurfaceVariant;
                  final groupColor = isDark
                      ? Colors.white.withValues(alpha: 0.065)
                      : Colors.white.withValues(alpha: 0.44);
                  final groupBorder = isDark
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.black.withValues(alpha: 0.055);

                  Widget optionButton({
                    required String label,
                    required bool selected,
                    required VoidCallback onTap,
                    IconData? icon,
                  }) {
                    final accent = AppAccentColors.current;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: onTap,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? accent.withValues(
                                          alpha: isDark ? 0.22 : 0.14,
                                        )
                                      : isDark
                                          ? Colors.white
                                              .withValues(alpha: 0.035)
                                          : Colors.white
                                              .withValues(alpha: 0.30),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: selected
                                        ? accent.withValues(alpha: 0.72)
                                        : groupBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (icon != null) ...[
                                      Icon(
                                        icon,
                                        size: 18,
                                        color:
                                            selected ? accent : secondaryColor,
                                      ),
                                      const SizedBox(width: 7),
                                    ],
                                    Flexible(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: selected
                                              ? accent
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (selected) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: accent,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )),
                      ),
                    );
                  }

                  Widget optionGroup({
                    required String title,
                    required String subtitle,
                    required List<Widget> options,
                  }) {
                    return Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      decoration: BoxDecoration(
                        color: groupColor,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: groupBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(children: options),
                        ],
                      ),
                    );
                  }

                  IconData iconForKind(TrendingRankingKind kind) =>
                      switch (kind) {
                        TrendingRankingKind.allHot =>
                          Icons.local_fire_department_rounded,
                        TrendingRankingKind.allRising =>
                          Icons.trending_up_rounded,
                        TrendingRankingKind.newAnimeHot =>
                          Icons.auto_awesome_rounded,
                      };

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(52, 14, 24, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppAccentColors.current
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                Icons.leaderboard_rounded,
                                size: 21,
                                color: AppAccentColors.current,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '排行榜设置',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
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
                          ],
                        ),
                      ),
                      Divider(height: 1, color: groupBorder),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                          children: [
                            optionGroup(
                              title: '榜单类型',
                              subtitle: '决定热度的统计维度',
                              options: [
                                for (final kind in TrendingRankingKind.values)
                                  optionButton(
                                    label: kind.label,
                                    icon: iconForKind(kind),
                                    selected: selectedKind == kind,
                                    onTap: () => setModalState(() {
                                      selectedKind = kind;
                                    }),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            optionGroup(
                              title: selectedKind ==
                                      TrendingRankingKind.newAnimeHot
                                  ? '季度范围'
                                  : '统计周期',
                              subtitle: selectedKind ==
                                      TrendingRankingKind.newAnimeHot
                                  ? '切换当前季度或上一季度'
                                  : '切换榜单覆盖的时间长度',
                              options: selectedKind ==
                                      TrendingRankingKind.newAnimeHot
                                  ? [
                                      for (final scope
                                          in TrendingNewAnimeScope.values)
                                        optionButton(
                                          label: scope.label,
                                          selected: selectedScope == scope,
                                          onTap: () => setModalState(() {
                                            selectedScope = scope;
                                          }),
                                        ),
                                    ]
                                  : [
                                      for (final period
                                          in TrendingPeriod.values)
                                        optionButton(
                                          label: period.label,
                                          selected: selectedPeriod == period,
                                          onTap: () => setModalState(() {
                                            selectedPeriod = period;
                                          }),
                                        ),
                                    ],
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: groupBorder),
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
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(windowContext).pop(),
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(windowContext).pop(
                                selectedQuery(),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('应用'),
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
      _applyTrendingQuery(result);
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
            _buildFullTrendingListSummary(
              result.summary,
              cupertinoStyle: true,
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 1),
                itemBuilder: (sheetContext, index) => _buildFullTrendingRow(
                  sheetContext,
                  items[index],
                  cupertinoStyle: true,
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
          final theme = Theme.of(windowContext);
          final isDark = theme.brightness == Brightness.dark;
          final dividerColor = isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.055);
          return NipaplayWindowScaffold(
            backgroundImageUrl: null,
            backgroundColor: isDark
                ? Colors.black.withValues(alpha: 0.56)
                : const Color(0xFFF4F5F8).withValues(alpha: 0.68),
            backdropBlurSigma: 34,
            borderColor: isDark
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.78),
            maxWidth: 820,
            maxHeightFactor: 0.88,
            onClose: () => Navigator.of(windowContext).pop(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, 14, 24, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              AppAccentColors.current.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.format_list_numbered_rounded,
                          size: 21,
                          color: AppAccentColors.current,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '完整排行榜',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_trendingSelectionLabel  ·  ${items.length} 部作品',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                _buildFullTrendingListSummary(
                  result.summary,
                  cupertinoStyle: false,
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: items.length,
                    itemBuilder: (sheetContext, index) => _buildFullTrendingRow(
                      sheetContext,
                      items[index],
                      cupertinoStyle: false,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullTrendingListSummary(
    TrendingSummary summary, {
    required bool cupertinoStyle,
  }) {
    final secondaryColor = cupertinoStyle
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.secondaryLabel,
            context,
          )
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final labels = <(IconData, String)>[
      (Icons.tune_rounded, _trendingSelectionLabel),
      if (_trendingDateLabel(summary) case final date?)
        (Icons.calendar_today_rounded, date),
      (
        Icons.movie_filter_outlined,
        '共 ${_currentTrendingResult?.items.length ?? 0} 条',
      ),
      (Icons.cloud_outlined, '数据来源：弹弹play开放弹幕网络'),
    ];
    if (cupertinoStyle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Text(
          labels.map((item) => item.$2).join('  ·  '),
          style: TextStyle(fontSize: 12, color: secondaryColor),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, label) in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.065)
                    : Colors.white.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: secondaryColor),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: secondaryColor),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullTrendingRow(
    BuildContext sheetContext,
    TrendingBangumiItem item, {
    required bool cupertinoStyle,
  }) {
    final anime = item.anime;
    final title = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
    final secondaryColor = cupertinoStyle
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.secondaryLabel,
            sheetContext,
          )
        : Theme.of(sheetContext).colorScheme.onSurfaceVariant;
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

    if (cupertinoStyle) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: openDetails,
        child: content,
      );
    }
    final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
    final highlighted = item.rank > 0 && item.rank <= 3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: highlighted
            ? AppAccentColors.current.withValues(alpha: isDark ? 0.09 : 0.055)
            : isDark
                ? Colors.white.withValues(alpha: 0.035)
                : Colors.white.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openDetails,
          hoverColor: AppAccentColors.current.withValues(alpha: 0.08),
          child: content,
        ),
      ),
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
