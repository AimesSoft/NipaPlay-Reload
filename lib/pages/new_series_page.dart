import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/loading_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/floating_action_glass_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/main.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tag_search_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/services/external_player_service.dart';
import 'package:nipaplay/l10n/l10n.dart';

class NewSeriesPage extends StatefulWidget {
  const NewSeriesPage({super.key});

  @override
  State<NewSeriesPage> createState() => _NewSeriesPageState();
}

class _NewSeriesPageState extends State<NewSeriesPage>
    with AutomaticKeepAliveClientMixin<NewSeriesPage> {
  final BangumiService _bangumiService = BangumiService.instance;
  List<BangumiAnime> _animes = [];
  bool _isLoading = true;
  String? _error;
  bool _isReversed = false;

  // States for loading video from detail page
  bool _isLoadingVideoFromDetail = false;
  String _loadingMessageForDetail = '';

  // Override wantKeepAlive for AutomaticKeepAliveClientMixin
  @override
  bool get wantKeepAlive => true;

  // 切换排序方向
  void _toggleSort() {
    setState(() {
      _isReversed = !_isReversed;
    });
  }

  // 显示搜索模态框
  void _showSearchModal() {
    TagSearchModal.show(context);
  }

  String _weekdayText(int weekday) {
    switch (weekday) {
      case 0:
        return context.l10n.weekdaySunday;
      case 1:
        return context.l10n.weekdayMonday;
      case 2:
        return context.l10n.weekdayTuesday;
      case 3:
        return context.l10n.weekdayWednesday;
      case 4:
        return context.l10n.weekdayThursday;
      case 5:
        return context.l10n.weekdayFriday;
      case 6:
        return context.l10n.weekdaySaturday;
      default:
        return context.l10n.unknown;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAnimes();
  }

  @override
  void dispose() {
    // 释放所有图片资源
    for (var anime in _animes) {
      ImageCacheManager.instance.releaseImage(anime.imageUrl);
    }
    super.dispose();
  }

  Future<void> _loadAnimes({bool forceRefresh = false}) async {
    final l10n = context.l10n;
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = true;
        _error = null;
      });

      List<BangumiAnime> animes;

      if (kIsWeb) {
        // Web environment: fetch from the local API
        try {
          final apiUri = WebRemoteAccessService.apiUri('/api/bangumi/calendar');
          if (apiUri == null) {
            throw Exception(l10n.newSeriesRemoteAddressNotConfigured);
          }
          final response = await http.get(apiUri);
          if (response.statusCode == 200) {
            final List<dynamic> data =
                json.decode(utf8.decode(response.bodyBytes));
            animes = data
                .map((d) => BangumiAnime.fromJson(d as Map<String, dynamic>))
                .toList();
          } else {
            throw Exception('Failed to load from API: ${response.statusCode}');
          }
        } catch (e) {
          throw Exception('Failed to connect to the local API: $e');
        }
      } else {
        // Mobile/Desktop environment: fetch from the service
        final prefs = await SharedPreferences.getInstance();
        final bool filterAdultContentGlobally =
            prefs.getBool('global_filter_adult_content') ?? true;
        animes = await _bangumiService.getCalendar(
            forceRefresh: forceRefresh,
            filterAdultContent: filterAdultContentGlobally);
      }

      if (mounted) {
        setState(() {
          _animes = animes;
          _isLoading = false;
        });
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (e is TimeoutException) {
        errorMsg = l10n.newSeriesNetworkTimeout;
      } else if (errorMsg.contains('SocketException')) {
        errorMsg = l10n.newSeriesNetworkConnectionFailed;
      } else if (errorMsg.contains('HttpException')) {
        errorMsg = l10n.newSeriesServerUnavailableRetryLater;
      } else if (errorMsg.contains('FormatException')) {
        errorMsg = l10n.newSeriesServerDataFormatError;
      }

      if (mounted) {
        setState(() {
          _error = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  // 按星期几分组番剧
  Map<int, List<BangumiAnime>> _groupAnimesByWeekday() {
    final grouped = <int, List<BangumiAnime>>{};
    // Restore original filter
    final validAnimes = _animes
        .where((anime) =>
                anime.imageUrl.isNotEmpty &&
                anime.imageUrl != 'assets/backempty.png'
            // && anime.nameCn.isNotEmpty && // Temporarily removed to allow display even if names are empty
            // && anime.name.isNotEmpty       // Temporarily removed
            )
        .toList();
    // final validAnimes = _animes.toList(); // Test: Show all animes from cache (Reverted)

    final unknownAnimes = validAnimes
        .where((anime) =>
                anime.airWeekday == null ||
                anime.airWeekday == -1 ||
                anime.airWeekday! < 0 ||
                anime.airWeekday! > 6 // Dandanplay airDay is 0-6
            )
        .toList();

    if (unknownAnimes.isNotEmpty) {
      grouped[-1] = unknownAnimes;
    }

    for (var anime in validAnimes) {
      if (anime.airWeekday != null &&
          anime.airWeekday! >= 0 &&
          anime.airWeekday! <= 6) {
        // Dandanplay airDay is 0-6
        grouped.putIfAbsent(anime.airWeekday!, () => []).add(anime);
      }
    }
    return grouped;
  }

  SliverPadding _buildAnimeGridSliver(
      List<BangumiAnime> animes, int weekdayKey) {
    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      sliver: SliverGrid(
        key: ValueKey<String>('sliver_grid_for_weekday_$weekdayKey'),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: showSummary
              ? HorizontalAnimeCard.detailedGridMaxCrossAxisExtent
              : HorizontalAnimeCard.compactGridMaxCrossAxisExtent,
          mainAxisExtent: showSummary
              ? HorizontalAnimeCard.detailedCardHeight
              : HorizontalAnimeCard.compactCardHeight,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final anime = animes[index];
            return FutureBuilder<BangumiAnime>(
              future: _bangumiService.getAnimeDetails(anime.id),
              builder: (context, snapshot) {
                String? summary;
                if (snapshot.hasData && snapshot.data!.summary != null) {
                  summary = snapshot.data!.summary;
                }
                return HorizontalAnimeCard(
                  imageUrl: anime.imageUrl,
                  title: anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
                  rating: anime.rating,
                  onTap: () => _showAnimeDetail(anime),
                  summary: summary,
                );
              },
            );
          },
          childCount: animes.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }

  SliverPadding _buildWeekdayHeaderSliver(
    BuildContext context, {
    required String title,
    required int weekdayKey,
    required int count,
    required bool isToday,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      sliver: SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildWeekdayHeader(
            context,
            title: title,
            weekdayKey: weekdayKey,
            count: count,
            isToday: isToday,
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildEmptyDaySliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
        child: Center(
          child: Text(
            context.l10n.newSeriesNoTodayAnime,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Added for AutomaticKeepAliveClientMixin

    //debugPrint('[NewSeriesPage build] START - isLoading: $_isLoading, error: $_error, animes.length: ${_animes.length}');

    // Outer Stack to handle the new LoadingOverlay for video loading
    return Stack(
      children: [
        // Original content based on _isLoading for anime list
        _buildMainContent(
            context), // Extracted original content to a new method
        if (_isLoadingVideoFromDetail)
          LoadingOverlay(
            messages: [
              _loadingMessageForDetail
            ], // LoadingOverlay expects a list of messages
            backgroundOpacity: 0.7, // Optional: customize opacity
            animeTitle: null,
            episodeTitle: null,
            fileName: null,
          ),
      ],
    );
  }

  // Extracted original build content into a new method
  Widget _buildLargeScreenMainContent(BuildContext context) {
    if (_isLoading && _animes.isEmpty) {
      return const NipaplayLargeScreenPageScaffold(
        title: '新番时间表',
        subtitle: '正在加载番剧日历',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _animes.isEmpty) {
      return NipaplayLargeScreenPageScaffold(
        title: '新番时间表',
        subtitle: '加载失败',
        actions: [
          NipaplayLargeScreenActionButton(
            icon: Icons.refresh_rounded,
            label: context.l10n.retry,
            onPressed: () => _loadAnimes(),
          ),
        ],
        child: NipaplayLargeScreenEmptyState(
          icon: Icons.error_outline_rounded,
          title: context.l10n.loadFailedWithError(_error!),
          subtitle: '请检查网络连接后重试',
          action: NipaplayLargeScreenActionButton(
            icon: Icons.refresh_rounded,
            label: context.l10n.retry,
            onPressed: () => _loadAnimes(),
          ),
        ),
      );
    }

    final groupedAnimes = _groupAnimesByWeekday();
    final knownWeekdays = groupedAnimes.keys.where((day) => day != -1).toList();
    final today = DateTime.now().weekday % 7;
    knownWeekdays.sort((a, b) {
      if (a == today) return -1;
      if (b == today) return 1;
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return _isReversed ? distB.compareTo(distA) : distA.compareTo(distB);
    });
    final unknownAnimes = groupedAnimes[-1] ?? const <BangumiAnime>[];
    final totalCount =
        groupedAnimes.values.fold<int>(0, (sum, items) => sum + items.length);

    return NipaplayLargeScreenPageScaffold(
      title: '新番时间表',
      subtitle: '共 $totalCount 部 / 今日 ${groupedAnimes[today]?.length ?? 0} 部',
      actions: [
        NipaplayLargeScreenActionButton(
          icon: Ionicons.search_outline,
          label: '搜索',
          onPressed: _showSearchModal,
        ),
        NipaplayLargeScreenActionButton(
          icon: _isReversed
              ? Ionicons.chevron_up_outline
              : Ionicons.chevron_down_outline,
          label: _isReversed ? '远日期优先' : '近日期优先',
          onPressed: _toggleSort,
        ),
        NipaplayLargeScreenActionButton(
          icon: Icons.refresh_rounded,
          label: _isLoading ? '刷新中' : '刷新',
          onPressed: _isLoading ? null : () => _loadAnimes(forceRefresh: true),
        ),
      ],
      child: totalCount == 0
          ? NipaplayLargeScreenEmptyState(
              icon: Icons.calendar_month_outlined,
              title: context.l10n.newSeriesNoTodayAnime,
              subtitle: '暂无可显示的新番条目',
            )
          : CustomScrollView(
              key: const PageStorageKey<String>(
                'new_series_large_screen_scroll_view',
              ),
              slivers: [
                for (final weekday in knownWeekdays) ...[
                  _buildLargeScreenWeekdayHeaderSliver(
                    context,
                    title: _weekdayText(weekday),
                    count: groupedAnimes[weekday]?.length ?? 0,
                    isToday: weekday == today,
                  ),
                  if ((groupedAnimes[weekday]?.isNotEmpty ?? false))
                    _buildLargeScreenAnimeGridSliver(
                      groupedAnimes[weekday]!,
                      weekday,
                    ),
                ],
                if (unknownAnimes.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),
                  _buildLargeScreenWeekdayHeaderSliver(
                    context,
                    title: context.l10n.newSeriesUpdateTimeTbd,
                    count: unknownAnimes.length,
                    isToday: false,
                  ),
                  _buildLargeScreenAnimeGridSliver(unknownAnimes, -1),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
    );
  }

  SliverPadding _buildLargeScreenWeekdayHeaderSliver(
    BuildContext context, {
    required String title,
    required int count,
    required bool isToday,
  }) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isToday ? textColor : textColor.withValues(alpha: 0.82),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              context.l10n.newSeriesAnimeCount(count),
              style: TextStyle(
                color: textColor.withValues(alpha: 0.52),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverPadding _buildLargeScreenAnimeGridSliver(
    List<BangumiAnime> animes,
    int weekdayKey,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 22),
      sliver: SliverGrid(
        key: ValueKey<String>('large_screen_grid_for_weekday_$weekdayKey'),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 458,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return _buildLargeScreenAnimeCard(
              context,
              animes[index],
              autofocus: weekdayKey == DateTime.now().weekday % 7 && index == 0,
            );
          },
          childCount: animes.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
        ),
      ),
    );
  }

  Widget _buildLargeScreenAnimeCard(
    BuildContext context,
    BangumiAnime anime, {
    required bool autofocus,
  }) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
    final title = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
    return NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: () => _showAnimeDetail(anime),
      borderRadius: BorderRadius.circular(8),
      padding: EdgeInsets.zero,
      focusScale: 1.035,
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: Colors.white.withValues(alpha: 0.07),
        idleBackgroundLight: Colors.white.withValues(alpha: 0.82),
        focusStrokeWidth: 2.4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImageWidget(
                    imageUrl: anime.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __) =>
                        _buildLargeScreenNewSeriesFallbackPoster(textColor),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.74),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _buildLargeScreenNewSeriesBadge('Bangumi'),
                  ),
                  if (anime.rating != null && anime.rating! > 0)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _buildLargeScreenNewSeriesBadge(
                        anime.rating!.toStringAsFixed(1),
                        icon: Icons.star_rounded,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  if (anime.airDate != null && anime.airDate!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      anime.airDate!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.52),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeScreenNewSeriesFallbackPoster(Color textColor) {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: textColor.withValues(alpha: 0.46),
          size: 52,
        ),
      ),
    );
  }

  Widget _buildLargeScreenNewSeriesBadge(String label, {IconData? icon}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return _buildLargeScreenMainContent(context);
    }

    if (_isLoading && _animes.isEmpty) {
      //debugPrint('[NewSeriesPage build] Showing loading indicator.');
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _animes.isEmpty) {
      //debugPrint('[NewSeriesPage build] Showing error message: $_error');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(context.l10n.loadFailedWithError(_error!)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadAnimes(),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }

    final groupedAnimes = _groupAnimesByWeekday();
    final knownWeekdays = groupedAnimes.keys.where((day) => day != -1).toList();

    knownWeekdays.sort((a, b) {
      final today = DateTime.now().weekday % 7;
      if (a == today) return -1;
      if (b == today) return 1;
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return _isReversed ? distB.compareTo(distA) : distA.compareTo(distB);
    });

    final today = DateTime.now().weekday % 7;
    final unknownAnimes = groupedAnimes[-1] ?? const <BangumiAnime>[];

    return Stack(
      children: [
        CustomScrollView(
          key: const PageStorageKey<String>('new_series_scroll_view'),
          slivers: [
            for (final weekday in knownWeekdays) ...[
              _buildWeekdayHeaderSliver(
                context,
                title: _weekdayText(weekday),
                weekdayKey: weekday,
                count: groupedAnimes[weekday]?.length ?? 0,
                isToday: weekday == today,
              ),
              if ((groupedAnimes[weekday]?.isNotEmpty ?? false))
                _buildAnimeGridSliver(groupedAnimes[weekday]!, weekday)
              else
                _buildEmptyDaySliver(),
            ],
            if (unknownAnimes.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              const SliverToBoxAdapter(
                child:
                    Divider(color: Colors.white24, indent: 16, endIndent: 16),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              _buildWeekdayHeaderSliver(
                context,
                title: context.l10n.newSeriesUpdateTimeTbd,
                weekdayKey: -1,
                count: unknownAnimes.length,
                isToday: false,
              ),
              _buildAnimeGridSliver(unknownAnimes, -1),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 搜索按钮
              FloatingActionGlassButton(
                iconData: Ionicons.search_outline,
                onPressed: _showSearchModal,
                description: context.l10n.newSeriesSearchDescription,
              ),
              const SizedBox(height: 16), // 按钮之间的间距
              // 排序按钮
              FloatingActionGlassButton(
                iconData: _isReversed
                    ? Ionicons.chevron_up_outline
                    : Ionicons.chevron_down_outline,
                onPressed: _toggleSort,
                description: _isReversed
                    ? context.l10n.newSeriesSortDescriptionAscending
                    : context.l10n.newSeriesSortDescriptionDescending,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAnimeDetail(BangumiAnime animeFromList) async {
    // 使用主题适配的显示方法
    final result = await ThemedAnimeDetail.show(context, animeFromList.id);

    if (result is WatchHistoryItem) {
      // If a WatchHistoryItem is returned, handle playing the episode
      if (mounted) {
        // Ensure widget is still mounted
        _handlePlayEpisode(result);
      }
    }
  }

  Future<void> _handlePlayEpisode(WatchHistoryItem historyItem) async {
    if (!mounted) return;

    setState(() {
      _isLoadingVideoFromDetail = true;
      _loadingMessageForDetail = context.l10n.newSeriesInitializingPlayer;
    });

    final playableItem = PlayableItem(
      videoPath: historyItem.filePath,
      title: historyItem.animeName,
      subtitle: historyItem.episodeTitle,
      animeId: historyItem.animeId,
      episodeId: historyItem.episodeId,
      historyItem: historyItem,
    );

    if (await ExternalPlayerService.tryHandlePlayback(context, playableItem)) {
      if (mounted) {
        setState(() {
          _isLoadingVideoFromDetail = false;
        });
      }
      return;
    }

    bool tabChangeLogicExecutedInDetail = false;

    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);

      late VoidCallback statusListener;
      statusListener = () {
        if (!mounted) {
          videoState.removeListener(statusListener);
          return;
        }

        if ((videoState.status == PlayerStatus.ready ||
                videoState.status == PlayerStatus.playing) &&
            !tabChangeLogicExecutedInDetail) {
          tabChangeLogicExecutedInDetail = true;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isLoadingVideoFromDetail = false;
              });

              debugPrint(
                  '[NewSeriesPage _handlePlayEpisode] Player ready/playing. Attempting to switch tab.');
              try {
                MainPageState? mainPageState = MainPageState.of(context);
                if (mainPageState != null &&
                    mainPageState.globalTabController != null) {
                  if (mainPageState.globalTabController!.index != 1) {
                    mainPageState.globalTabController!.animateTo(1);
                    debugPrint(
                        '[NewSeriesPage _handlePlayEpisode] Directly called mainPageState.globalTabController.animateTo(1)');
                  } else {
                    debugPrint(
                        '[NewSeriesPage _handlePlayEpisode] mainPageState.globalTabController is already at index 1.');
                  }
                } else {
                  debugPrint(
                      '[NewSeriesPage _handlePlayEpisode] Could not find MainPageState or globalTabController.');
                }
              } catch (e) {
                debugPrint(
                    "[NewSeriesPage _handlePlayEpisode] Error directly changing tab: $e");
              }
              videoState.removeListener(statusListener);
            } else {
              videoState.removeListener(statusListener);
            }
          });
        } else if (videoState.status == PlayerStatus.error) {
          videoState.removeListener(statusListener);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isLoadingVideoFromDetail = false;
              });
              BlurSnackBar.show(
                context,
                context.l10n.newSeriesPlayerLoadFailedWithError(
                  videoState.error ?? context.l10n.unknownErrorOccurred,
                ),
              );
            }
          });
        } else if (tabChangeLogicExecutedInDetail &&
            (videoState.status == PlayerStatus.ready ||
                videoState.status == PlayerStatus.playing)) {
          debugPrint(
              '[NewSeriesPage _handlePlayEpisode] Tab logic executed, player still ready/playing. Ensuring listener removed.');
          videoState.removeListener(statusListener);
        }
      };

      videoState.addListener(statusListener);
      await videoState.initializePlayer(historyItem.filePath,
          historyItem: historyItem);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingVideoFromDetail = false;
          _loadingMessageForDetail =
              context.l10n.newSeriesErrorOccurredWithError('$e');
        });
        BlurSnackBar.show(
          context,
          context.l10n.newSeriesHandlePlayRequestFailedWithError('$e'),
        );
      }
    }
  }

  Widget _buildWeekdayHeader(
    BuildContext context, {
    required String title,
    required int weekdayKey,
    required int count,
    required bool isToday,
  }) {
    final String countText = context.l10n.newSeriesAnimeCount(count);

    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color:
                  isToday ? Colors.white : Colors.white.withValues(alpha: 0.9),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            countText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isToday
                  ? Colors.white.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
