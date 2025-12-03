import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_anime_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_shared_anime_detail_page.dart';

class CupertinoDandanplayLibraryPage extends StatefulWidget {
  const CupertinoDandanplayLibraryPage({super.key});

  @override
  State<CupertinoDandanplayLibraryPage> createState() =>
      _CupertinoDandanplayLibraryPageState();
}

class _CupertinoDandanplayLibraryPageState
    extends State<CupertinoDandanplayLibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  final Map<int, String?> _coverCache = {};
  final Map<int, Future<String?>> _coverLoadingTasks = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeProvider());
  }

  Future<void> _initializeProvider() async {
    if (!mounted) return;
    final provider = context.read<DandanplayRemoteProvider>();
    await provider.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: '弹弹play 媒体库',
        useNativeToolbar: true,
        actions: [
          AdaptiveAppBarAction(
            iosSymbol: 'arrow.clockwise',
            icon: CupertinoIcons.refresh,
            onPressed: () => _handleManualRefresh(),
          ),
          AdaptiveAppBarAction(
            iosSymbol: 'slider.horizontal.3',
            icon: CupertinoIcons.slider_horizontal_3,
            onPressed: () => _manageConnection(),
          ),
        ],
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          child: Consumer<DandanplayRemoteProvider>(
            builder: (context, provider, _) {
              if (!provider.isInitialized && provider.isLoading) {
                return const Center(child: CupertinoActivityIndicator());
              }

              if (!provider.isConnected) {
                return _buildDisconnectedState(provider);
              }

              return _buildConnectedContent(provider);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleManualRefresh() async {
    final provider = context.read<DandanplayRemoteProvider>();
    await _refreshLibrary(provider, showToast: true);
  }

  Widget _buildConnectedContent(DandanplayRemoteProvider provider) {
    final List<DandanplayRemoteAnimeGroup> filtered =
        _filterGroups(provider.animeGroups);
    final bool hasError =
        (provider.errorMessage?.isNotEmpty ?? false) && !provider.isLoading;
    final bool showEmptyLibrary =
        provider.animeGroups.isEmpty && !provider.isLoading;
    final bool showEmptySearch =
        provider.animeGroups.isNotEmpty && filtered.isEmpty;

    final slivers = <Widget>[
      CupertinoSliverRefreshControl(
        onRefresh: () => _refreshLibrary(provider),
      ),
      const SliverToBoxAdapter(
        child: SizedBox(height: 60),
      ),
      SliverToBoxAdapter(child: _buildSearchField()),
    ];

    if (hasError) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _buildErrorBanner(provider.errorMessage!),
        ),
      ));
    }

    if (provider.isLoading && provider.animeGroups.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    } else if (showEmptyLibrary) {
      slivers.add(
        _buildPlaceholderSliver(
          icon: CupertinoIcons.tv,
          title: '远程媒体库为空',
          message: '请确认弹弹play 已同步媒体，稍候片刻即可自动更新列表。',
        ),
      );
    } else if (showEmptySearch) {
      slivers.add(
        _buildPlaceholderSliver(
          icon: CupertinoIcons.search,
          title: '没有找到匹配内容',
          message: '请尝试调整或清空搜索关键词。',
        ),
      );
    } else {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final group = filtered[index];
              return Padding(
                padding: EdgeInsets.fromLTRB(20, index == 0 ? 16 : 8, 20, 8),
                child: CupertinoAnimeCard(
                  title: group.title,
                  imageUrl: _resolveCoverUrlForGroup(group, provider),
                  episodeLabel: '共 ${group.episodeCount} 集',
                  lastWatchTime: group.latestPlayTime,
                  sourceLabel: '弹弹play',
                  summary: group.latestEpisode.episodeTitle,
                  onTap: () => _openAnimeDetail(group, provider),
                ),
              );
            },
            childCount: filtered.length,
          ),
        ),
      );
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: slivers,
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: CupertinoSearchTextField(
        controller: _searchController,
        placeholder: '搜索番剧或剧集',
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim();
          });
        },
        onSuffixTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    final Color borderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemRed,
      context,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: borderColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: borderColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: borderColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderSliver({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: CupertinoColors.inactiveGray),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel,
                    context,
                  ),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisconnectedState(DandanplayRemoteProvider provider) {
    final Color secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.cloud,
              size: 48,
              color: secondary,
            ),
            const SizedBox(height: 12),
            const Text(
              '尚未连接弹弹play 远程服务',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '请完成远程访问配置后即可在此浏览家中电脑或 NAS 上的番剧记录。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: secondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: () => _manageConnection(provider: provider),
              borderRadius: BorderRadius.circular(14),
              child: const Text('连接弹弹play'),
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
    final query = _searchQuery.toLowerCase();
    return source.where((group) {
      final titleMatch = group.title.toLowerCase().contains(query);
      final episodeMatch = group.episodes.any(
        (episode) => episode.episodeTitle.toLowerCase().contains(query),
      );
      return titleMatch || episodeMatch;
    }).toList();
  }

  Future<void> _refreshLibrary(
    DandanplayRemoteProvider provider, {
    bool showToast = false,
  }) async {
    try {
      await provider.refresh();
      if (showToast && mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '远程媒体库已刷新',
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '刷新失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String? _resolveCoverUrlForGroup(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider,
  ) {
    final String? fallback = provider.buildImageUrl(group.primaryHash ?? '');
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
    future.whenComplete(() => _coverLoadingTasks.remove(animeId));
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
      final future = _coverLoadingTasks[animeId];
      final newly = await future;
      if (newly != null && newly.isNotEmpty) {
        return newly;
      }
    }

    final fallback = provider.buildImageUrl(group.primaryHash ?? '');
    if (fallback != null && fallback.isNotEmpty) {
      _coverCache[animeId] = fallback;
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

  Future<void> _openAnimeDetail(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider provider,
  ) async {
    final animeId = group.animeId;
    if (animeId == null) {
      AdaptiveSnackBar.show(
        context,
        message: '该条目缺少 Bangumi ID，无法打开详情',
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }

    final coverUrl = await _getOrFetchCoverUrl(animeId, provider, group);
    if (!mounted) return;

    final summary = _buildSharedSummary(
      group,
      provider,
      coverUrl: coverUrl,
    );

    Future<List<SharedRemoteEpisode>> episodeLoader({bool force = false}) async {
      final episodes = group.episodes.reversed
          .map((episode) => _mapToSharedEpisode(episode, provider))
          .whereType<SharedRemoteEpisode>()
          .toList();
      if (episodes.isEmpty) {
        throw Exception('该番剧暂无可播放的剧集');
      }
      return episodes;
    }

    Future<PlayableItem> playableBuilder(
      BuildContext routeContext,
      SharedRemoteEpisode episode,
    ) async {
      return _buildPlayableFromShared(summary: summary, episode: episode);
    }

    await CupertinoBottomSheet.show(
      context: context,
      title: null,
      showCloseButton: true,
      child: CupertinoSharedAnimeDetailPage(
        anime: summary,
        hideBackButton: true,
        showCloseButton: true,
        customEpisodeLoader: ({bool force = false}) =>
            episodeLoader(force: force),
        customPlayableBuilder: playableBuilder,
        sourceLabelOverride: provider.serverUrl ?? '弹弹play',
      ),
    );
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
      lastWatchTime:
          group.latestPlayTime ?? DateTime.fromMillisecondsSinceEpoch(0),
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
      title: episode.episodeTitle.isNotEmpty
          ? episode.episodeTitle
          : episode.name,
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

  Future<void> _manageConnection({
    DandanplayRemoteProvider? provider,
  }) async {
    final target = provider ?? context.read<DandanplayRemoteProvider>();
    final bool hasExisting = target.serverUrl?.isNotEmpty == true;
    final config = await showCupertinoDandanplayConnectionDialog(
      context: context,
      provider: target,
    );
    if (config == null) {
      return;
    }

    try {
      await target.connect(
        config.baseUrl,
        token: config.apiToken,
      );
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: hasExisting
            ? '弹弹play 远程服务配置已更新'
            : '弹弹play 远程服务已连接',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '连接失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }
}
