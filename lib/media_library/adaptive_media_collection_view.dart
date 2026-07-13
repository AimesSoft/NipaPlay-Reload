import 'dart:convert';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/media_library/media_collection_empty_content.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_anime_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_search_toolbar.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/local_library_control_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

enum MediaCollectionSort { recentlyAdded, name }

class AdaptiveMediaCollectionView extends material.StatefulWidget {
  const AdaptiveMediaCollectionView({
    super.key,
    required this.source,
    required this.onPlayEpisode,
  });

  final UnifiedMediaLibrarySource source;
  final material.ValueChanged<WatchHistoryItem> onPlayEpisode;

  @override
  material.State<AdaptiveMediaCollectionView> createState() =>
      _AdaptiveMediaCollectionViewState();
}

class _AdaptiveMediaCollectionViewState
    extends material.State<AdaptiveMediaCollectionView> {
  final material.TextEditingController _searchController =
      material.TextEditingController();
  final Map<int, BangumiAnime> _details = <int, BangumiAnime>{};
  final Map<int, Future<BangumiAnime>> _detailRequests =
      <int, Future<BangumiAnime>>{};
  String _query = '';
  MediaCollectionSort _sort = MediaCollectionSort.recentlyAdded;
  bool _isSyncing = false;
  bool _isLoadingWebCollection = false;
  List<WatchHistoryItem> _webCollectionItems = const <WatchHistoryItem>[];

  @override
  void initState() {
    super.initState();
    if (kIsWeb && widget.source == UnifiedMediaLibrarySource.local) {
      material.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadWebCollection();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _sourceLabel => switch (widget.source) {
        UnifiedMediaLibrarySource.local => '本地媒体库',
        UnifiedMediaLibrarySource.webdav => 'WebDAV媒体库',
        UnifiedMediaLibrarySource.smb => 'SMB媒体库',
      };

  @override
  material.Widget build(material.BuildContext context) {
    return Consumer<WatchHistoryProvider>(
      builder: (context, provider, _) {
        if (!provider.isLoaded && !provider.isLoading) {
          material.WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !provider.isLoaded) provider.loadHistory();
          });
        }

        final allItems =
            kIsWeb && widget.source == UnifiedMediaLibrarySource.local
                ? _webCollectionItems
                : mediaLibraryLatestItemsByAnime(
                    provider.history,
                    widget.source,
                  );
        final filteredItems = _filterAndSort(allItems);
        for (final item in filteredItems) {
          _ensureDetail(item.animeId!);
        }

        return material.Column(
          children: [
            AdaptiveMediaCollectionControlBar(
              sourceLabel: _sourceLabel,
              controller: _searchController,
              sort: _sort,
              isSyncing: _isSyncing,
              onSearchChanged: (value) => setState(() => _query = value),
              onSortChanged: (value) => setState(() => _sort = value),
              onSync: _isSyncing ? null : _sync,
            ),
            material.Expanded(
              child: AdaptiveMediaCollectionItems(
                source: widget.source,
                sourceLabel: _sourceLabel,
                isLoading: _isLoadingWebCollection ||
                    (provider.isLoading && !provider.isLoaded),
                items: filteredItems,
                allHistory: provider.history,
                details: _details,
                onRefresh: _sync,
                onTap: _openAnimeDetail,
              ),
            ),
          ],
        );
      },
    );
  }

  List<WatchHistoryItem> _filterAndSort(List<WatchHistoryItem> items) {
    final query = _query.trim().toLowerCase();
    final filtered = items.where((item) {
      if (query.isEmpty) return true;
      return item.animeName.toLowerCase().contains(query) ||
          (item.episodeTitle?.toLowerCase().contains(query) ?? false);
    }).toList();
    if (_sort == MediaCollectionSort.name) {
      filtered.sort((a, b) => a.animeName.compareTo(b.animeName));
    }
    return filtered;
  }

  void _ensureDetail(int animeId) {
    if (_details.containsKey(animeId) || _detailRequests.containsKey(animeId)) {
      return;
    }
    final cached = BangumiService.instance.getAnimeDetailsFromMemory(animeId);
    if (cached != null) {
      _details[animeId] = cached;
      return;
    }
    final request = BangumiService.instance.getAnimeDetails(animeId);
    _detailRequests[animeId] = request;
    request.then((detail) {
      if (!mounted) return;
      setState(() {
        _details[animeId] = detail;
        _detailRequests.remove(animeId);
      });
    }).catchError((_) {
      _detailRequests.remove(animeId);
    });
  }

  Future<void> _sync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final provider = context.read<WatchHistoryProvider>();
      provider.clearInvalidPathCache();
      await provider.refresh();
      if (kIsWeb && widget.source == UnifiedMediaLibrarySource.local) {
        await _loadWebCollection(showLoading: false);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _loadWebCollection({bool showLoading = true}) async {
    if (!kIsWeb || widget.source != UnifiedMediaLibrarySource.local) return;
    if (showLoading && mounted) {
      setState(() => _isLoadingWebCollection = true);
    }
    try {
      final uri = WebRemoteAccessService.apiUri('/api/media/local/items');
      if (uri == null) throw Exception('未配置远程访问地址');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('远程媒体库响应 ${response.statusCode}');
      }
      final rawItems = json.decode(utf8.decode(response.bodyBytes)) as List;
      final items = <WatchHistoryItem>[];
      for (final raw in rawItems.whereType<Map<String, dynamic>>()) {
        final anime = BangumiAnime.fromJson(raw);
        _details[anime.id] = anime;
        items.add(
          WatchHistoryItem(
            animeId: anime.id,
            animeName: anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
            episodeTitle: '',
            filePath: 'web_${anime.id}',
            lastWatchTime: raw['_localLastWatchTime'] != null
                ? DateTime.tryParse(raw['_localLastWatchTime'].toString()) ??
                    DateTime.now()
                : DateTime.now(),
            watchProgress: 0,
            lastPosition: 0,
            duration: 0,
            thumbnailPath: anime.imageUrl,
          ),
        );
      }
      items.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      if (mounted) setState(() => _webCollectionItems = items);
    } finally {
      if (mounted) setState(() => _isLoadingWebCollection = false);
    }
  }

  Future<void> _openAnimeDetail(WatchHistoryItem item) async {
    final provider = context.read<WatchHistoryProvider>();
    final episodes = provider.history
        .where((candidate) =>
            candidate.animeId == item.animeId &&
            mediaLibraryItemMatchesSource(candidate, widget.source))
        .toList()
      ..sort(
        (a, b) => (a.episodeId ?? 0).compareTo(b.episodeId ?? 0),
      );
    final episodeByPath = <String, WatchHistoryItem>{
      for (final episode in episodes) episode.filePath: episode,
    };
    final detail = _details[item.animeId];
    final summary = SharedRemoteAnimeSummary(
      animeId: item.animeId!,
      name: item.animeName,
      nameCn: detail?.nameCn,
      summary: detail?.summary,
      imageUrl: _imageUrl(item, detail),
      lastWatchTime: item.lastWatchTime,
      episodeCount: episodes.length,
      hasMissingFiles: false,
    );

    final result = await ThemedAnimeDetail.show(
      context,
      item.animeId!,
      sharedSummary: summary,
      sharedSourceLabel: _sourceLabel,
      sharedEpisodeLoader: () async => episodes
          .map(
            (episode) => SharedRemoteEpisode(
              shareId: episode.filePath,
              title: episode.episodeTitle ?? episode.animeName,
              fileName: path.basename(episode.filePath),
              streamPath: episode.filePath,
              fileExists: true,
              animeId: episode.animeId,
              episodeId: episode.episodeId,
              duration: episode.duration,
              lastPosition: episode.lastPosition,
              progress: episode.watchProgress,
              lastWatchTime: episode.lastWatchTime,
              videoHash: episode.videoHash,
            ),
          )
          .toList(),
      sharedEpisodeBuilder: (episode) {
        final historyItem = episodeByPath[episode.shareId]!;
        return PlayableItem(
          videoPath: historyItem.filePath,
          title: historyItem.animeName,
          subtitle: historyItem.episodeTitle,
          animeId: historyItem.animeId,
          episodeId: historyItem.episodeId,
          historyItem: historyItem,
        );
      },
    );
    if (result != null) widget.onPlayEpisode(result);
  }

  static String _title(WatchHistoryItem item, BangumiAnime? detail) {
    if (detail?.nameCn.isNotEmpty == true) return detail!.nameCn;
    if (detail?.name.isNotEmpty == true) return detail!.name;
    return item.animeName;
  }

  static String _imageUrl(WatchHistoryItem item, BangumiAnime? detail) {
    if (detail?.imageUrl.isNotEmpty == true) return detail!.imageUrl;
    return item.thumbnailPath ?? '';
  }
}

class AdaptiveMediaCollectionControlBar extends material.StatelessWidget {
  const AdaptiveMediaCollectionControlBar({
    super.key,
    required this.sourceLabel,
    required this.controller,
    required this.sort,
    required this.isSyncing,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onSync,
  });

  final String sourceLabel;
  final material.TextEditingController controller;
  final MediaCollectionSort sort;
  final bool isSyncing;
  final material.ValueChanged<String> onSearchChanged;
  final material.ValueChanged<MediaCollectionSort> onSortChanged;
  final material.VoidCallback? onSync;

  @override
  material.Widget build(material.BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoMediaSearchToolbar(
        controller: controller,
        placeholder: '搜索$sourceLabel',
        onChanged: onSearchChanged,
        actions: [
          CupertinoMediaSearchToolbarAction(
            label: '媒体库排序',
            icon: cupertino.CupertinoIcons.sort_down,
            onPressed: () => _showPhoneSort(context),
          ),
          CupertinoMediaSearchToolbarAction(
            label: isSyncing ? '同步中' : '同步$sourceLabel',
            icon: cupertino.CupertinoIcons.refresh,
            onPressed: onSync,
            loading: isSyncing,
          ),
        ],
      );
    }

    return LocalLibraryControlBar(
      title: sourceLabel,
      searchController: controller,
      currentSort: sort == MediaCollectionSort.name
          ? LocalLibrarySortType.name
          : LocalLibrarySortType.dateAdded,
      onSearchChanged: onSearchChanged,
      onSortChanged: (value) => onSortChanged(
        value == LocalLibrarySortType.name
            ? MediaCollectionSort.name
            : MediaCollectionSort.recentlyAdded,
      ),
      trailingActions: [
        LocalLibraryActionControl(
          label: isSyncing ? '同步中' : '同步$sourceLabel',
          desktopIcon: material.Icons.sync,
          phoneIcon: cupertino.CupertinoIcons.refresh,
          onPressed: onSync,
        ),
      ],
    );
  }

  Future<void> _showPhoneSort(material.BuildContext context) async {
    final selected =
        await CupertinoBottomSheet.showSelection<MediaCollectionSort>(
      context: context,
      title: '媒体库排序',
      options: [
        CupertinoBottomSheetOption(
          label: '最近添加',
          value: MediaCollectionSort.recentlyAdded,
          selected: sort == MediaCollectionSort.recentlyAdded,
        ),
        CupertinoBottomSheetOption(
          label: '名称',
          value: MediaCollectionSort.name,
          selected: sort == MediaCollectionSort.name,
        ),
      ],
    );
    if (selected != null) onSortChanged(selected);
  }
}

class AdaptiveMediaCollectionItems extends material.StatelessWidget {
  const AdaptiveMediaCollectionItems({
    super.key,
    required this.source,
    required this.sourceLabel,
    required this.isLoading,
    required this.items,
    required this.allHistory,
    required this.details,
    required this.onRefresh,
    required this.onTap,
  });

  final UnifiedMediaLibrarySource source;
  final String sourceLabel;
  final bool isLoading;
  final List<WatchHistoryItem> items;
  final List<WatchHistoryItem> allHistory;
  final Map<int, BangumiAnime> details;
  final Future<void> Function() onRefresh;
  final material.ValueChanged<WatchHistoryItem> onTap;

  @override
  material.Widget build(material.BuildContext context) {
    final emptyContent = mediaCollectionEmptyContent(
      source,
      sourceLabel: sourceLabel,
    );
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return _buildPhone(context, emptyContent);
    }
    return _buildDesktop(context, emptyContent);
  }

  material.Widget _buildPhone(
    material.BuildContext context,
    MediaCollectionEmptyContent emptyContent,
  ) {
    final slivers = <material.Widget>[
      cupertino.CupertinoSliverRefreshControl(onRefresh: onRefresh),
    ];
    if (isLoading) {
      slivers.add(
        const material.SliverFillRemaining(
          hasScrollBody: false,
          child: material.Center(
            child: cupertino.CupertinoActivityIndicator(),
          ),
        ),
      );
    } else if (items.isEmpty) {
      slivers.add(
        material.SliverFillRemaining(
          hasScrollBody: false,
          child: _AdaptiveMediaCollectionEmptyState(content: emptyContent),
        ),
      );
    } else {
      slivers.add(
        material.SliverPadding(
          padding: const material.EdgeInsets.fromLTRB(20, 12, 20, 112),
          sliver: material.SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const material.SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final detail = details[item.animeId];
              return CupertinoAnimeCard(
                title: _AdaptiveMediaCollectionViewState._title(item, detail),
                imageUrl:
                    _AdaptiveMediaCollectionViewState._imageUrl(item, detail),
                episodeLabel: _episodeLabel(item.animeId!),
                lastWatchTime: item.lastWatchTime,
                sourceLabel: sourceLabel,
                rating: detail?.rating,
                summary: detail?.summary,
                onTap: () => onTap(item),
              );
            },
          ),
        ),
      );
    }
    return material.CustomScrollView(
      physics: const material.BouncingScrollPhysics(
        parent: material.AlwaysScrollableScrollPhysics(),
      ),
      slivers: slivers,
    );
  }

  material.Widget _buildDesktop(
    material.BuildContext context,
    MediaCollectionEmptyContent emptyContent,
  ) {
    if (isLoading) {
      return material.Center(
        child: AdaptiveMediaActivityIndicator(color: AppAccentColors.current),
      );
    }
    if (items.isEmpty) {
      return material.Center(
        child: _AdaptiveMediaCollectionEmptyState(content: emptyContent),
      );
    }

    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;
    return material.GridView.builder(
      gridDelegate: material.SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: showSummary
            ? HorizontalAnimeCard.detailedGridMaxCrossAxisExtent
            : HorizontalAnimeCard.compactGridMaxCrossAxisExtent,
        mainAxisExtent: showSummary
            ? HorizontalAnimeCard.detailedCardHeight
            : HorizontalAnimeCard.compactCardHeight,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      padding: const material.EdgeInsets.fromLTRB(16, 0, 16, 80),
      physics: const material.BouncingScrollPhysics(
        parent: material.AlwaysScrollableScrollPhysics(),
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final detail = details[item.animeId];
        return HorizontalAnimeCard(
          imageUrl: _AdaptiveMediaCollectionViewState._imageUrl(item, detail),
          title: _AdaptiveMediaCollectionViewState._title(item, detail),
          rating: detail?.rating,
          source: AnimeCard.getSourceFromFilePath(item.filePath),
          summary: detail?.summary,
          progress: _watchProgress(item.animeId!, detail),
          onTap: () => onTap(item),
        );
      },
    );
  }

  String _episodeLabel(int animeId) {
    final count = allHistory
        .where((item) =>
            item.animeId == animeId &&
            mediaLibraryItemMatchesSource(item, source))
        .length;
    return '共$count集';
  }

  String _watchProgress(int animeId, BangumiAnime? detail) {
    final episodes = allHistory
        .where((item) =>
            item.animeId == animeId &&
            mediaLibraryItemMatchesSource(item, source))
        .toList();
    final watchedIds = episodes
        .where((item) => item.watchProgress > 0.01 || item.lastPosition > 0)
        .map((item) => item.episodeId)
        .whereType<int>()
        .toSet();
    final watchedCount = watchedIds.isEmpty
        ? episodes
            .where((item) => item.watchProgress > 0.01 || item.lastPosition > 0)
            .length
        : watchedIds.length;
    if (watchedCount == 0) return '未观看';
    final total = detail?.totalEpisodes;
    if (total != null && total > 0) {
      return watchedCount >= total ? '已看完' : '已看 $watchedCount / $total 集';
    }
    return '已看 $watchedCount 集';
  }
}

class _AdaptiveMediaCollectionEmptyState extends material.StatelessWidget {
  const _AdaptiveMediaCollectionEmptyState({required this.content});

  final MediaCollectionEmptyContent content;

  @override
  material.Widget build(material.BuildContext context) {
    final phone = AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final secondary = phone
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.secondaryLabel,
            context,
          )
        : material.Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.58);

    return material.Center(
      key: const material.ValueKey<String>('media-collection-empty-state'),
      child: material.Padding(
        padding: const material.EdgeInsets.symmetric(horizontal: 32),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          mainAxisAlignment: material.MainAxisAlignment.center,
          children: [
            material.Icon(
              _icon(),
              size: 50,
              color: secondary,
            ),
            const material.SizedBox(height: 14),
            material.Text(
              content.title,
              textAlign: material.TextAlign.center,
              style: const material.TextStyle(
                fontSize: 18,
                fontWeight: material.FontWeight.w600,
              ),
            ),
            const material.SizedBox(height: 8),
            material.Text(
              content.subtitle,
              textAlign: material.TextAlign.center,
              style: material.TextStyle(color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  material.IconData _icon() {
    return switch (content.icon) {
      MediaCollectionEmptyIcon.library =>
        cupertino.CupertinoIcons.rectangle_stack,
    };
  }
}
