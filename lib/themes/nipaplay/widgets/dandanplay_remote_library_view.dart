import 'dart:async';
import 'dart:ui';
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
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';

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
        if (!provider.isInitialized && provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!provider.isConnected) {
          return _buildDisconnectedState(provider);
        }

        final List<DandanplayRemoteAnimeGroup> groups =
            _filterGroups(provider.animeGroups);

        if (provider.animeGroups.isEmpty && !provider.isLoading) {
          return _buildEmptyState(provider);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(),
            if ((provider.errorMessage?.isNotEmpty ?? false) &&
                !provider.isLoading) ...[
              const SizedBox(height: 12),
              _buildDandanErrorBanner(provider.errorMessage!),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _buildMediaGrid(groups, provider),
            ),
          ],
        );
      },
    );
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
            const Icon(Ionicons.warning_outline, color: Colors.redAccent, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
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
    return RepaintBoundary(
      child: Scrollbar(
        controller: _gridScrollController,
        radius: const Radius.circular(2),
        thickness: 4,
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 500,
            mainAxisExtent: 140,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    const activeColor = Color(0xFFFF2E55);
    final idleBorderColor = isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
            border: Border.all(
              color: _searchFocusNode.hasFocus ? activeColor : idleBorderColor,
              width: _searchFocusNode.hasFocus ? 1.5 : 1,
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: activeColor.withValues(alpha: 0.3),
                selectionHandleColor: activeColor,
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: TextStyle(color: primaryTextColor, fontSize: 16),
              cursorColor: activeColor,
              decoration: InputDecoration(
                prefixIcon:
                    Icon(Icons.search, color: _searchFocusNode.hasFocus ? activeColor : secondaryTextColor, size: 20),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.clear, color: secondaryTextColor),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      ),
                hintText: '搜索番剧或剧集…',
                hintStyle:
                    TextStyle(color: secondaryTextColor.withValues(alpha: 0.6)),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (!mounted) return;
                  setState(() {
                    _searchQuery = value.trim();
                  });
                });
              },
              onSubmitted: (value) {
                _searchDebounce?.cancel();
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
          ),
        ),
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Ionicons.cloud_offline_outline,
                color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            const Text(
              '尚未连接弹弹play远程服务',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '请先在下方完成远程访问配置，即可浏览家中弹弹play媒体库。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            BlurButton(
              icon: Ionicons.link_outline,
              text: '连接弹弹play',
              onTap: () => _showConnectDialog(context, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(DandanplayRemoteProvider provider) {
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
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
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
    final result = await showDialog<Map<String, String?>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final baseController =
            TextEditingController(text: provider.serverUrl ?? '');
        final tokenController = TextEditingController();
        return AlertDialog(
          backgroundColor: Colors.black.withValues(alpha: 0.8),
          title: const Text(
            '连接弹弹play远程服务',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseController,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '服务地址',
                  hintText: '例如 http://192.168.1.10:23333',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText:
                      provider.tokenRequired ? 'API密钥 (必填)' : 'API密钥 (可选)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop({
                  'base': baseController.text.trim(),
                  'token': tokenController.text.trim(),
                });
              },
              child: const Text('连接'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    await _connectProvider(
      provider,
      result['base'] ?? '',
      result['token'],
    );
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
      await provider.connect(url, token: token?.isNotEmpty == true ? token : null);
      if (!mounted) return;
      BlurSnackBar.show(context, '弹弹play远程服务已连接');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '连接失败: $e');
    }
  }

}
