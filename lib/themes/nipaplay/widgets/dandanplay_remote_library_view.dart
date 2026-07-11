import 'dart:async';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';

class DandanplayRemoteLibraryView extends StatefulWidget {
  const DandanplayRemoteLibraryView({
    super.key,
    this.onPlayEpisode,
  });

  final ValueChanged<WatchHistoryItem>? onPlayEpisode;

  @override
  State<DandanplayRemoteLibraryView> createState() =>
      _DandanplayRemoteLibraryViewState();
}

class _DandanplayRemoteLibraryViewState
    extends State<DandanplayRemoteLibraryView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  final ScrollController _gridScrollController = ScrollController();
  Timer? _searchDebounce;
  final Map<int, String?> _coverCache = {}; // 复用本地缓存的番剧封面
  final Map<int, Future<String?>> _coverLoadingTasks = {};

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DandanplayRemoteProvider>(
      builder: (context, provider, child) {
        final isLargeScreen = NipaplayLargeScreenModeScope.isActiveOf(context);
        if (!provider.isInitialized && provider.isLoading) {
          return const Center(child: AdaptiveMediaActivityIndicator());
        }
        if (!provider.isConnected) {
          if (isLargeScreen) {
            return _buildLargeScreenDisconnectedState(provider);
          }
          return _buildDisconnectedState(provider);
        }

        final List<DandanplayRemoteAnimeGroup> groups =
            _filterGroups(provider.animeGroups);

        if (provider.animeGroups.isEmpty && !provider.isLoading) {
          if (isLargeScreen) {
            return _buildLargeScreenEmptyState(provider);
          }
          return _buildEmptyState(provider);
        }

        if (isLargeScreen) {
          return _buildLargeScreenRemoteLibrary(groups, provider);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(),
            if ((provider.errorMessage?.isNotEmpty ?? false) &&
                !provider.isLoading) ...[
              SizedBox(height: 12),
              _buildDandanErrorBanner(provider.errorMessage!),
            ],
            SizedBox(height: 12),
            Expanded(
              child: _buildMediaGrid(groups, provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLargeScreenRemoteLibrary(
    List<DandanplayRemoteAnimeGroup> groups,
    DandanplayRemoteProvider provider,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: NipaplayLargeScreenTextInput(
                controller: _searchController,
                hintText: '搜索弹弹play远程媒体',
                onChanged: _updateSearchQueryDebounced,
                onSubmitted: _commitSearchQuery,
                suffix: _searchQuery.isEmpty
                    ? null
                    : AdaptiveMediaIconButton(
                        tooltip: '清空搜索',
                        onPressed: _clearSearchQuery,
                        desktopIcon: Icons.close_rounded,
                        phoneIcon: cupertino.CupertinoIcons.clear,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            NipaplayLargeScreenActionButton(
              icon: Icons.refresh_rounded,
              label: provider.isLoading ? '刷新中' : '刷新',
              onPressed: provider.isLoading
                  ? null
                  : () async {
                      try {
                        await provider.refresh();
                      } catch (e) {
                        if (mounted) {
                          BlurSnackBar.show(context, '刷新失败: $e');
                        }
                      }
                    },
            ),
            const SizedBox(width: 10),
            NipaplayLargeScreenActionButton(
              icon: Ionicons.link_outline,
              label: '连接',
              onPressed: () => _showConnectDialog(context, provider),
            ),
          ],
        ),
        if ((provider.errorMessage?.isNotEmpty ?? false) &&
            !provider.isLoading) ...[
          const SizedBox(height: 14),
          _buildLargeScreenDandanErrorBanner(provider.errorMessage!),
        ],
        const SizedBox(height: 18),
        Expanded(
          child: provider.isLoading && groups.isEmpty
              ? const Center(child: AdaptiveMediaActivityIndicator())
              : groups.isEmpty
                  ? const NipaplayLargeScreenEmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有匹配结果',
                      subtitle: '换个关键词再试试',
                    )
                  : GridView.builder(
                      controller: _gridScrollController,
                      padding: const EdgeInsets.only(bottom: 96),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 244,
                        mainAxisExtent: 468,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                      ),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        return _buildLargeScreenAnimeCard(
                          groups[index],
                          provider,
                          autofocus: index == 0,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildLargeScreenAnimeCard(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider, {
    required bool autofocus,
  }) {
    final coverUrl = _resolveCoverUrlForGroup(group, provider);
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);

    return NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: () => _openAnimeDetail(group, provider),
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
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __) =>
                        _buildLargeScreenDandanFallbackPoster(textColor),
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
                    child: _buildLargeScreenDandanBadge('弹弹play'),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _buildLargeScreenDandanBadge(
                      '${group.episodeCount} 集',
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
                    group.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatLargeScreenDandanSubtitle(group),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.52),
                      fontSize: 12,
                      height: 1.26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeScreenDisconnectedState(
    DandanplayRemoteProvider provider,
  ) {
    return NipaplayLargeScreenEmptyState(
      icon: Ionicons.cloud_offline_outline,
      title: '尚未连接弹弹play远程服务',
      subtitle: '连接后可以在大屏模式中浏览家中弹弹play媒体库',
      action: NipaplayLargeScreenActionButton(
        icon: Ionicons.link_outline,
        label: '连接弹弹play',
        onPressed: () => _showConnectDialog(context, provider),
      ),
    );
  }

  Widget _buildLargeScreenEmptyState(DandanplayRemoteProvider provider) {
    return NipaplayLargeScreenEmptyState(
      icon: Ionicons.tv_outline,
      title: '远程媒体库为空',
      subtitle: '请确认弹弹play远程访问已同步媒体，稍候片刻后刷新列表',
      action: NipaplayLargeScreenActionButton(
        icon: Icons.refresh_rounded,
        label: '刷新',
        onPressed: provider.isLoading
            ? null
            : () async {
                try {
                  await provider.refresh();
                } catch (e) {
                  if (mounted) {
                    BlurSnackBar.show(context, '刷新失败: $e');
                  }
                }
              },
      ),
    );
  }

  Widget _buildLargeScreenDandanErrorBanner(String message) {
    return NipaplayLargeScreenPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Ionicons.warning_outline,
              color: Colors.redAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenDandanFallbackPoster(Color textColor) {
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

  Widget _buildLargeScreenDandanBadge(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  String _formatLargeScreenDandanSubtitle(DandanplayRemoteAnimeGroup group) {
    final latest = group.latestPlayTime;
    if (latest == null) {
      return '共 ${group.episodeCount} 集';
    }
    return '共 ${group.episodeCount} 集 · 最近播放 ${latest.year}-${latest.month.toString().padLeft(2, '0')}-${latest.day.toString().padLeft(2, '0')}';
  }

  void _updateSearchQueryDebounced(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.trim();
      });
    });
  }

  void _commitSearchQuery(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = value.trim();
    });
  }

  void _clearSearchQuery() {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildDandanErrorBanner(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.red.withValues(alpha: 0.1),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Ionicons.warning_outline, color: Colors.redAccent, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DandanplayRemoteAnimeGroup> _filterGroups(
    List<DandanplayRemoteAnimeGroup> source,
  ) {
    if (_searchQuery.isEmpty) {
      return List.unmodifiable(source);
    }
    return source.where((group) {
      final titleMatch = _matchesQuery(group.title, _searchQuery);
      final episodeMatch = group.episodes.any(
        (episode) => _matchesQuery(episode.episodeTitle, _searchQuery),
      );
      return titleMatch || episodeMatch;
    }).toList();
  }

  bool _matchesQuery(String source, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return true;

    final lowerSource = source.toLowerCase();
    final lowerQuery = trimmed.toLowerCase();
    if (lowerSource.contains(lowerQuery)) return true;

    final normalizedSource = _normalizeSearchText(lowerSource);
    final normalizedQuery = _normalizeSearchText(lowerQuery);
    if (normalizedSource.contains(normalizedQuery)) return true;

    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (tokens.length <= 1) return false;

    final tokenMatch = tokens.every(
      (token) => _normalizeSearchText(lowerSource)
          .contains(_normalizeSearchText(token.toLowerCase())),
    );
    return tokenMatch;
  }

  String _normalizeSearchText(String input) {
    return input.replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
  }

  Widget _buildMediaGrid(
    List<DandanplayRemoteAnimeGroup> groups,
    DandanplayRemoteProvider provider,
  ) {
    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;
    return RepaintBoundary(
      child: AdaptiveMediaScrollbar(
        controller: _gridScrollController,
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: showSummary
                ? HorizontalAnimeCard.detailedGridMaxCrossAxisExtent
                : HorizontalAnimeCard.compactGridMaxCrossAxisExtent,
            mainAxisExtent: showSummary
                ? HorizontalAnimeCard.detailedCardHeight
                : HorizontalAnimeCard.compactCardHeight,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return _buildAnimeCard(group, provider);
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return AdaptiveMediaSearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      placeholder: '搜索番剧或剧集…',
      onChanged: _updateSearchQueryDebounced,
      onSubmitted: _commitSearchQuery,
      onClear: () {
        _searchDebounce?.cancel();
        if (mounted) setState(() => _searchQuery = '');
      },
    );
  }

  Widget _buildAnimeCard(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider,
  ) {
    final coverUrl = _resolveCoverUrlForGroup(group, provider);

    if (group.animeId != null) {
      return FutureBuilder<BangumiAnime>(
        future: BangumiService.instance.getAnimeDetails(group.animeId!),
        builder: (context, snapshot) {
          String? summary;
          if (snapshot.hasData && snapshot.data!.summary != null) {
            summary = snapshot.data!.summary;
          }
          return HorizontalAnimeCard(
            key: ValueKey('dandan_${group.animeId ?? group.title}'),
            title: group.title,
            imageUrl: coverUrl,
            source: '弹弹play',
            rating: null,
            onTap: () => _openAnimeDetail(group, provider),
            summary: summary,
          );
        },
      );
    }

    return HorizontalAnimeCard(
      key: ValueKey('dandan_${group.animeId ?? group.title}'),
      title: group.title,
      imageUrl: coverUrl,
      source: '弹弹play',
      rating: null,
      onTap: () => _openAnimeDetail(group, provider),
      summary: null,
    );
  }

  String _resolveCoverUrlForGroup(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider,
  ) {
    final fallback = provider.buildImageUrl(group.primaryHash ?? '') ?? '';
    final animeId = group.animeId;
    if (animeId == null) {
      return fallback;
    }

    final cached = _coverCache[animeId];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    _coverCache.putIfAbsent(animeId, () => fallback);
    _ensureCoverLoad(animeId);
    return _coverCache[animeId] ?? fallback;
  }

  void _ensureCoverLoad(int animeId) {
    if (_coverLoadingTasks.containsKey(animeId)) {
      return;
    }

    final future = _loadCoverFromSources(animeId).then((url) {
      if ((url?.isNotEmpty ?? false) && mounted) {
        setState(() {
          _coverCache[animeId] = url;
        });
      } else if (url != null && url.isNotEmpty) {
        _coverCache[animeId] = url;
      }
      return url;
    }).catchError((error) {
      debugPrint('获取番剧封面失败($animeId): $error');
      return null;
    });

    _coverLoadingTasks[animeId] = future;
    future.whenComplete(() {
      _coverLoadingTasks.remove(animeId);
    });
  }

  Future<String?> _getOrFetchCoverUrl(
    int animeId,
    DandanplayRemoteProvider provider,
    DandanplayRemoteAnimeGroup group,
  ) async {
    final cached = _coverCache[animeId];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final pending = _coverLoadingTasks[animeId];
    if (pending != null) {
      final result = await pending;
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } else {
      _ensureCoverLoad(animeId);
      final newly = await _coverLoadingTasks[animeId];
      if (newly != null && newly.isNotEmpty) {
        return newly;
      }
    }

    final fallback = provider.buildImageUrl(group.primaryHash ?? '');
    if (fallback != null && fallback.isNotEmpty) {
      if (mounted) {
        setState(() {
          _coverCache[animeId] = fallback;
        });
      } else {
        _coverCache[animeId] = fallback;
      }
    }
    return fallback;
  }

  Future<String?> _loadCoverFromSources(int animeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'media_library_image_url_$animeId';
      final persisted = prefs.getString(key);
      if (persisted != null && persisted.isNotEmpty) {
        return persisted;
      }

      final detail = await BangumiService.instance.getAnimeDetails(animeId);
      final url = detail.imageUrl;
      if (url.isNotEmpty) {
        await prefs.setString(key, url);
        return url;
      }
    } catch (e) {
      debugPrint('加载番剧封面异常($animeId): $e');
    }
    return null;
  }

  SharedRemoteAnimeSummary _buildSharedSummary(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider, {
    String? coverUrl,
  }) {
    final resolvedCover = coverUrl ??
        (group.animeId != null ? _coverCache[group.animeId!] : null) ??
        provider.buildImageUrl(group.primaryHash ?? '');

    return SharedRemoteAnimeSummary(
      animeId: group.animeId!,
      name: group.title,
      nameCn: group.title,
      summary: null,
      imageUrl: resolvedCover,
      lastWatchTime: group.latestPlayTime ?? DateTime.now(),
      episodeCount: group.episodeCount,
      hasMissingFiles: false,
    );
  }

  SharedRemoteEpisode? _mapToSharedEpisode(
    DandanplayRemoteEpisode episode,
    DandanplayRemoteProvider provider,
  ) {
    final streamUrl = provider.buildStreamUrlForEpisode(episode);
    if (streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    final resolvedEpisodeId = episode.episodeId ??
        (episode.entryId.isNotEmpty
            ? episode.entryId.hashCode
            : (episode.hash.isNotEmpty
                ? episode.hash.hashCode
                : episode.name.hashCode));

    final shareKey = episode.entryId.isNotEmpty
        ? episode.entryId
        : (episode.hash.isNotEmpty ? episode.hash : episode.path);

    return SharedRemoteEpisode(
      shareId: 'dandan_$shareKey',
      title:
          episode.episodeTitle.isNotEmpty ? episode.episodeTitle : episode.name,
      fileName: episode.name,
      streamPath: streamUrl,
      fileExists: true,
      animeId: episode.animeId,
      episodeId: resolvedEpisodeId,
      duration: episode.duration,
      lastPosition: 0,
      progress: 0,
      fileSize: episode.size,
      lastWatchTime: episode.lastPlay ?? episode.created,
      videoHash: episode.hash.isNotEmpty ? episode.hash : null,
    );
  }

  PlayableItem _buildPlayableFromShared({
    required SharedRemoteAnimeSummary summary,
    required SharedRemoteEpisode episode,
  }) {
    final watchItem = _buildWatchHistoryItem(
      summary: summary,
      episode: episode,
    );
    return PlayableItem(
      videoPath: watchItem.filePath,
      title: watchItem.animeName,
      subtitle: watchItem.episodeTitle,
      animeId: watchItem.animeId,
      episodeId: watchItem.episodeId,
      historyItem: watchItem,
      actualPlayUrl: watchItem.filePath,
    );
  }

  WatchHistoryItem _buildWatchHistoryItem({
    required SharedRemoteAnimeSummary summary,
    required SharedRemoteEpisode episode,
  }) {
    final duration = episode.duration ?? 0;
    final lastPosition = episode.lastPosition ?? 0;
    double progress = episode.progress ?? 0;
    if (progress <= 0 && duration > 0 && lastPosition > 0) {
      progress = (lastPosition / duration).clamp(0.0, 1.0);
    }

    return WatchHistoryItem(
      filePath: episode.streamPath,
      animeName:
          summary.nameCn?.isNotEmpty == true ? summary.nameCn! : summary.name,
      episodeTitle: episode.title,
      episodeId: episode.episodeId,
      animeId: summary.animeId,
      watchProgress: progress,
      lastPosition: lastPosition,
      duration: duration,
      lastWatchTime: episode.lastWatchTime ?? summary.lastWatchTime,
      thumbnailPath: summary.imageUrl,
      isFromScan: false,
      videoHash: episode.videoHash,
    );
  }

  Future<void> _openAnimeDetail(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider,
  ) async {
    final animeId = group.animeId;
    if (animeId == null) {
      BlurSnackBar.show(context, '该条目缺少 Bangumi ID，无法打开详情');
      return;
    }

    final coverUrl = await _getOrFetchCoverUrl(animeId, provider, group);
    if (!mounted) return;

    final summary = _buildSharedSummary(
      group,
      provider,
      coverUrl: coverUrl,
    );
    Future<List<SharedRemoteEpisode>> episodeLoader() async {
      final episodes = group.episodes.reversed
          .map((episode) => _mapToSharedEpisode(episode, provider))
          .whereType<SharedRemoteEpisode>()
          .toList();
      if (episodes.isEmpty) {
        throw Exception('该番剧暂无可播放的剧集');
      }
      return episodes;
    }

    final sourceLabel = provider.serverUrl ?? '弹弹play';

    try {
      final result = await ThemedAnimeDetail.show(
        context,
        summary.animeId,
        sharedSummary: summary,
        sharedEpisodeLoader: episodeLoader,
        sharedEpisodeBuilder: (episode) => _buildPlayableFromShared(
          summary: summary,
          episode: episode,
        ),
        sharedSourceLabel: sourceLabel,
      );

      if (result != null) {
        widget.onPlayEpisode?.call(result);
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '打开详情失败：$e');
      }
    }
  }

  Widget _buildDisconnectedState(DandanplayRemoteProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final subTextColor = textColor.withOpacity(0.7);
    final mutedTextColor = textColor.withOpacity(0.5);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Ionicons.cloud_offline_outline,
                color: mutedTextColor, size: 48),
            SizedBox(height: 16),
            Text(
              '尚未连接弹弹play远程服务',
              style: TextStyle(color: textColor, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              '请先在下方完成远程访问配置，即可浏览家中弹弹play媒体库。',
              textAlign: TextAlign.center,
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
            SizedBox(height: 20),
            AdaptiveMediaActionButton(
              onPressed: () => _showConnectDialog(context, provider),
              desktopIcon: Ionicons.link_outline,
              phoneIcon: cupertino.CupertinoIcons.link,
              label: '连接弹弹play',
              emphasis: AdaptiveMediaActionEmphasis.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(DandanplayRemoteProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final subTextColor = textColor.withOpacity(0.7);
    final mutedTextColor = textColor.withOpacity(0.5);
    final title = '远程媒体库为空';
    final subtitle = '请确认弹弹play 远程访问已同步媒体，稍候片刻即可自动更新列表。';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Ionicons.tv_outline,
              color: mutedTextColor,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConnectDialog(
    BuildContext context,
    DandanplayRemoteProvider provider,
  ) async {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      final config = await showCupertinoDandanplayConnectionDialog(
        context: context,
        provider: provider,
      );
      if (config == null) return;
      await _connectProvider(provider, config.baseUrl, config.apiToken);
      return;
    }

    final connected = await BlurLoginDialog.show(
      context,
      title: '连接弹弹play远程服务',
      loginButtonText: '连接',
      fields: [
        LoginField(
          key: 'base',
          label: '服务地址',
          hint: '例如 http://192.168.1.10:23333',
          initialValue: provider.serverUrl ?? '',
        ),
        LoginField(
          key: 'token',
          label: provider.tokenRequired ? 'API密钥 (必填)' : 'API密钥 (可选)',
          isPassword: true,
          required: provider.tokenRequired,
        ),
      ],
      onLogin: (values) async {
        final baseUrl = values['base']?.trim() ?? '';
        if (baseUrl.isEmpty) {
          return const LoginResult(success: false, message: '请输入远程服务地址');
        }
        try {
          final token = values['token'];
          await provider.connect(
            baseUrl,
            token: token?.isNotEmpty == true ? token : null,
          );
          return const LoginResult(success: true, message: '连接成功');
        } catch (error) {
          return LoginResult(success: false, message: '连接失败: $error');
        }
      },
    );
    if (connected == true && mounted) {
      BlurSnackBar.show(context, '弹弹play远程服务已连接');
    }
  }

  Future<void> _connectProvider(
    DandanplayRemoteProvider provider,
    String baseUrl,
    String? token,
  ) async {
    final url = baseUrl.trim();
    if (url.isEmpty) {
      BlurSnackBar.show(context, '请输入远程服务地址');
      return;
    }

    try {
      await provider.connect(url,
          token: token?.isNotEmpty == true ? token : null);
      if (!mounted) return;
      BlurSnackBar.show(context, '弹弹play远程服务已连接');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '连接失败: $e');
    }
  }
}
