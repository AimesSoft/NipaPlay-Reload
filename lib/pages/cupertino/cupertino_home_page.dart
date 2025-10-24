import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';

class CupertinoHomePage extends StatefulWidget {
  const CupertinoHomePage({super.key});

  @override
  State<CupertinoHomePage> createState() => _CupertinoHomePageState();
}

class _CupertinoHomePageState extends State<CupertinoHomePage> {
  final PageController _pageController = PageController();
  final DateFormat _dateFormat = DateFormat('MM-dd HH:mm');
  final ScrollController _scrollController = ScrollController();

  Timer? _autoScrollTimer;
  Timer? _reloadDebounce;

  int _currentIndex = 0;
  bool _isLoadingRecommended = false;
  bool _didScheduleInitialLoad = false;
  double _scrollOffset = 0.0;

  List<_CupertinoRecommendedItem> _recommendedItems = [];

  JellyfinProvider? _jellyfinProvider;
  EmbyProvider? _embyProvider;
  WatchHistoryProvider? _watchHistoryProvider;

  final Map<int, String> _localImageCache = {};
  static const String _localPrefsKeyPrefix = 'media_library_image_url_';

  static List<_CupertinoRecommendedItem> _cachedRecommendedItems = [];
  static DateTime? _lastRecommendedLoadTime;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final jellyfin = Provider.of<JellyfinProvider>(context);
    if (_jellyfinProvider != jellyfin) {
      _jellyfinProvider?.removeListener(_onSourceChanged);
      _jellyfinProvider = jellyfin;
      _jellyfinProvider?.addListener(_onSourceChanged);
    }

    final emby = Provider.of<EmbyProvider>(context);
    if (_embyProvider != emby) {
      _embyProvider?.removeListener(_onSourceChanged);
      _embyProvider = emby;
      _embyProvider?.addListener(_onSourceChanged);
    }

    final history = Provider.of<WatchHistoryProvider>(context);
    if (_watchHistoryProvider != history) {
      _watchHistoryProvider?.removeListener(_onHistoryChanged);
      _watchHistoryProvider = history;
      _watchHistoryProvider?.addListener(_onHistoryChanged);

      if (history.isLoaded) {
        _scheduleRecommendedReload();
      }
    }

    if (!_didScheduleInitialLoad) {
      _didScheduleInitialLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRecommendedContent();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _reloadDebounce?.cancel();
    _pageController.dispose();
    _scrollController.dispose();

    _jellyfinProvider?.removeListener(_onSourceChanged);
    _embyProvider?.removeListener(_onSourceChanged);
    _watchHistoryProvider?.removeListener(_onHistoryChanged);

    super.dispose();
  }

  void _onSourceChanged() {
    _scheduleRecommendedReload(force: true);
  }

  void _onHistoryChanged() {
    if (!mounted) return;
    if (_watchHistoryProvider?.isLoaded == true) {
      _scheduleRecommendedReload();
    }
  }

  void _scheduleRecommendedReload({bool force = false}) {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _loadRecommendedContent(forceRefresh: force);
    });
  }

  Future<void> _loadRecommendedContent({bool forceRefresh = false}) async {
    if (!mounted || _isLoadingRecommended) return;

    // 使用缓存避免频繁加载
    final cacheValid = _cachedRecommendedItems.isNotEmpty &&
        _lastRecommendedLoadTime != null &&
        DateTime.now().difference(_lastRecommendedLoadTime!).inHours < 12;

    if (!forceRefresh && cacheValid) {
      setState(() {
        _recommendedItems = _cachedRecommendedItems;
        _isLoadingRecommended = false;
      });
      _startAutoScroll();
      return;
    }

    setState(() {
      _isLoadingRecommended = true;
    });

    try {
      final List<dynamic> allCandidates = [];

      final jellyfinProvider = _jellyfinProvider;
      if (jellyfinProvider != null && jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        final futures = <Future<List<JellyfinMediaItem>>>[];
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            futures.add(jellyfinService.getRandomMediaItemsByLibrary(library.id,
                limit: 30));
          }
        }
        if (futures.isNotEmpty) {
          final results = await Future.wait(futures, eagerError: false);
          for (final list in results) {
            allCandidates.addAll(list);
          }
        }
      }

      final embyProvider = _embyProvider;
      if (embyProvider != null && embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        final futures = <Future<List<EmbyMediaItem>>>[];
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            futures.add(embyService.getRandomMediaItemsByLibrary(library.id,
                limit: 30));
          }
        }
        if (futures.isNotEmpty) {
          final results = await Future.wait(futures, eagerError: false);
          for (final list in results) {
            allCandidates.addAll(list);
          }
        }
      }

      final historyProvider = _watchHistoryProvider;
      if (historyProvider != null && historyProvider.isLoaded) {
        final localHistory = historyProvider.history.where((item) {
          return !item.filePath.startsWith('jellyfin://') &&
              !item.filePath.startsWith('emby://');
        }).toList();

        final Map<int, WatchHistoryItem> latestLocalItems = {};
        for (final item in localHistory) {
          if (item.animeId == null) continue;
          final existing = latestLocalItems[item.animeId!];
          if (existing == null ||
              item.lastWatchTime.isAfter(existing.lastWatchTime)) {
            latestLocalItems[item.animeId!] = item;
          }
        }

        allCandidates.addAll(latestLocalItems.values.take(20));
      }

      if (allCandidates.isEmpty) {
        _setRecommendedPlaceholders();
        return;
      }

      allCandidates.shuffle(math.Random());
      final selected = allCandidates.take(5).toList();
      final List<_CupertinoRecommendedItem> builtItems = [];
      final Set<String> seenIds = {};

      for (final candidate in selected) {
        _CupertinoRecommendedItem? built;
        if (candidate is JellyfinMediaItem) {
          final jellyfinService = JellyfinService.instance;
          String? backdropUrl;
          try {
            backdropUrl =
                jellyfinService.getImageUrl(candidate.id, type: 'Backdrop');
          } catch (_) {
            try {
              backdropUrl =
                  jellyfinService.getImageUrl(candidate.id, type: 'Primary');
            } catch (_) {}
          }

          built = _CupertinoRecommendedItem(
            id: 'jellyfin_${candidate.id}',
            title: candidate.name,
            subtitle: _sanitizeOverview(candidate.overview),
            imageUrl: backdropUrl,
            source: _CupertinoRecommendedSource.jellyfin,
            rating: candidate.communityRating != null
                ? double.tryParse(candidate.communityRating!)
                : null,
          );
        } else if (candidate is EmbyMediaItem) {
          final embyService = EmbyService.instance;
          String? backdropUrl;
          try {
            backdropUrl =
                embyService.getImageUrl(candidate.id, type: 'Backdrop');
          } catch (_) {
            try {
              backdropUrl =
                  embyService.getImageUrl(candidate.id, type: 'Primary');
            } catch (_) {}
          }

          built = _CupertinoRecommendedItem(
            id: 'emby_${candidate.id}',
            title: candidate.name,
            subtitle: _sanitizeOverview(candidate.overview),
            imageUrl: backdropUrl,
            source: _CupertinoRecommendedSource.emby,
            rating: candidate.communityRating != null
                ? double.tryParse(candidate.communityRating!)
                : null,
          );
        } else if (candidate is WatchHistoryItem) {
          String? imagePath = candidate.thumbnailPath;
          if (imagePath == null && candidate.animeId != null) {
            imagePath = await _loadPersistedImage(candidate.animeId!);
          }

          built = _CupertinoRecommendedItem(
            id: 'local_${candidate.animeId ?? candidate.filePath}',
            title: candidate.animeName.isNotEmpty
                ? candidate.animeName
                : (candidate.episodeTitle ?? '本地媒体'),
            subtitle: candidate.episodeTitle ?? '继续观看',
            imageUrl: imagePath,
            source: _CupertinoRecommendedSource.local,
            rating: null,
          );
        }

        if (built != null && seenIds.add(built.id)) {
          builtItems.add(built);
        }
      }

      if (builtItems.isEmpty) {
        _setRecommendedPlaceholders();
        return;
      }

      while (builtItems.length < 5) {
        builtItems.add(
          _CupertinoRecommendedItem(
            id: 'placeholder_${builtItems.length}',
            title: '暂无推荐内容',
            subtitle: '连接媒体库以获取更多推荐',
            imageUrl: null,
            source: _CupertinoRecommendedSource.placeholder,
            rating: null,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _recommendedItems = builtItems;
        _isLoadingRecommended = false;
        _currentIndex = 0;
      });

      _cachedRecommendedItems = builtItems;
      _lastRecommendedLoadTime = DateTime.now();
      _startAutoScroll();

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('CupertinoHomePage: 加载推荐内容失败: $e');
      _setRecommendedPlaceholders();
    }
  }

  Future<String?> _loadPersistedImage(int animeId) async {
    final cached = _localImageCache[animeId];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString('$_localPrefsKeyPrefix$animeId');
      if (persisted != null && persisted.isNotEmpty) {
        _localImageCache[animeId] = persisted;
        return persisted;
      }

      final key = 'bangumi_detail_$animeId';
      final raw = prefs.getString(key);
      if (raw != null) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        final detail = decoded['animeDetail'] as Map<String, dynamic>?;
        final imageUrl = detail?['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          _localImageCache[animeId] = imageUrl;
          await prefs.setString('$_localPrefsKeyPrefix$animeId', imageUrl);
          return imageUrl;
        }
      }
    } catch (_) {}

    try {
      final bangumiDetail =
          await BangumiService.instance.getAnimeDetails(animeId);
      final imageUrl = bangumiDetail.imageUrl;
      if (imageUrl.isNotEmpty) {
        _localImageCache[animeId] = imageUrl;
        try {
          prefs ??= await SharedPreferences.getInstance();
          await prefs.setString('$_localPrefsKeyPrefix$animeId', imageUrl);
        } catch (_) {}
        return imageUrl;
      }
    } catch (e) {
      debugPrint('CupertinoHomePage: 获取番剧封面失败: $e');
    }

    return null;
  }

  void _setRecommendedPlaceholders() {
    if (!mounted) return;
    setState(() {
      _recommendedItems = List.generate(5, (index) {
        return _CupertinoRecommendedItem(
          id: 'placeholder_$index',
          title: '暂无推荐内容',
          subtitle: '稍后再试或连接媒体库获取推荐',
          imageUrl: null,
          source: _CupertinoRecommendedSource.placeholder,
          rating: null,
        );
      });
      _isLoadingRecommended = false;
      _currentIndex = 0;
    });
    _cachedRecommendedItems = _recommendedItems;
    _lastRecommendedLoadTime = DateTime.now();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_recommendedItems.length <= 1) return;

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pageController.hasClients || !mounted) return;
      final next = (_currentIndex + 1) % _recommendedItems.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentIndex = next;
      });
    });
  }

  Future<void> _handleRefresh() async {
    await _loadRecommendedContent(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    // 计算标题透明度 (滚动0-10px时快速消失)
    final titleOpacity = (1.0 - (_scrollOffset / 10.0)).clamp(0.0, 1.0);

    // 获取状态栏高度
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // 顶部留空，为大标题和状态栏预留空间
              SliverPadding(
                padding: EdgeInsets.only(
                    top: statusBarHeight + 52), // 状态栏 + 大标题高度 + 间距
                sliver:
                    CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
              ),
              SliverToBoxAdapter(child: _buildSectionTitle('精选推荐')),
              SliverToBoxAdapter(child: _buildHeroSection()),
              SliverToBoxAdapter(child: _buildSectionTitle('最近观看')),
              SliverToBoxAdapter(
                child: Consumer<WatchHistoryProvider>(
                  builder: (context, provider, _) {
                    final recentItems = _buildRecentItems(provider.history);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: recentItems.isEmpty
                          ? _buildEmptyRecentPlaceholder()
                          : Column(
                              children: recentItems
                                  .map((item) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _buildRecentCard(item),
                                      ))
                                  .toList(),
                            ),
                    );
                  },
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          ),
          // 顶部白色渐变遮罩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      backgroundColor,
                      backgroundColor.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 自定义大标题 - 使用 Stack 叠加
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    '主页',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    if (_isLoadingRecommended && _recommendedItems.isEmpty) {
      return const SizedBox(
        height: 240,
        child: Center(
          child: CupertinoActivityIndicator(),
        ),
      );
    }

    const horizontalMargin = 20.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - horizontalMargin * 2;
    final cardHeight = cardWidth / (3 / 2); // 整个卡片 3:2 横图比例

    return SizedBox(
      height: cardHeight,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _recommendedItems.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final item = _recommendedItems[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
            child: _buildPosterCard(item, cardHeight),
          );
        },
      ),
    );
  }

  Widget _buildPosterCard(
    _CupertinoRecommendedItem item,
    double cardHeight,
  ) {
    final cardColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );
    CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    // ignore: prefer_const_constructors
    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // 背景图片铺满整个卡片
          if (item.imageUrl != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _buildPosterBackground(item.imageUrl!),
              ),
            ),
          // 底部渐变遮罩覆盖整个卡片底部
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: cardHeight * 0.5, // 遮罩覆盖卡片底部60%高度
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
          // 文字信息叠加在最上层
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCardMetaRow(item),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                  if (item.rating != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(CupertinoIcons.star_fill,
                            color: Color(0xFFFFD166), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          item.rating!.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildPageIndicator(item),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMetaRow(_CupertinoRecommendedItem item) {
    final label = _sourceLabel(item.source);
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _sourceIcon(item.source),
          size: 16,
          color: CupertinoColors.activeBlue,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: CupertinoColors.activeBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPosterBackground(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) =>
            Container(color: CupertinoColors.systemGrey),
      );
    }

    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) =>
            Container(color: CupertinoColors.systemGrey),
      );
    }

    return Container(color: CupertinoColors.systemGrey);
  }

  Widget _buildPageIndicator(_CupertinoRecommendedItem _) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_recommendedItems.length, (index) {
        final isActive = index == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 6),
          width: isActive ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? CupertinoColors.activeBlue
                : CupertinoColors.systemGrey3,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title) {
    final textStyle = CupertinoTheme.of(context).textTheme.navTitleTextStyle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: textStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildEmptyRecentPlaceholder() {
    final resolvedBackground = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );
    // ignore: prefer_const_constructors
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Text(
          '暂无观看记录',
          style: TextStyle(color: CupertinoColors.inactiveGray),
        ),
      ),
    );
  }

  Widget _buildRecentCard(WatchHistoryItem item) {
    final resolvedBackground = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );
    final progress =
        item.duration > 0 ? item.watchProgress.clamp(0.0, 1.0) : 0.0;

    // ignore: prefer_const_constructors
    return Container(
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.animeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (item.episodeTitle != null && item.episodeTitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.episodeTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, color: CupertinoColors.systemGrey),
            ),
          ],
          const SizedBox(height: 12),
          _buildProgressBar(progress),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).round()}% • ${_dateFormat.format(item.lastWatchTime)}',
            style: const TextStyle(
                fontSize: 13, color: CupertinoColors.systemGrey2),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double progress) {
    final resolvedTrack =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey4, context);
    return SizedBox(
      height: 6,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: resolvedTrack.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<WatchHistoryItem> _buildRecentItems(List<WatchHistoryItem> history) {
    final sorted = List<WatchHistoryItem>.from(history)
      ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

    final List<WatchHistoryItem> result = [];
    final Set<String> keys = {};
    for (final item in sorted) {
      final key =
          item.animeId != null ? 'anime_${item.animeId}' : item.filePath;
      if (keys.add(key)) {
        result.add(item);
      }
      if (result.length >= 8) {
        break;
      }
    }
    return result;
  }

  String _sourceLabel(_CupertinoRecommendedSource source) {
    switch (source) {
      case _CupertinoRecommendedSource.jellyfin:
        return 'Jellyfin';
      case _CupertinoRecommendedSource.emby:
        return 'Emby';
      case _CupertinoRecommendedSource.local:
        return '本地媒体';
      case _CupertinoRecommendedSource.placeholder:
        return '';
    }
  }

  IconData _sourceIcon(_CupertinoRecommendedSource source) {
    switch (source) {
      case _CupertinoRecommendedSource.jellyfin:
        return CupertinoIcons.tv;
      case _CupertinoRecommendedSource.emby:
        return CupertinoIcons.tv_music_note;
      case _CupertinoRecommendedSource.local:
        return CupertinoIcons.tray_full;
      case _CupertinoRecommendedSource.placeholder:
        return CupertinoIcons.sparkles;
    }
  }

  String _sanitizeOverview(String? value) {
    if (value == null || value.isEmpty) {
      return '暂无简介信息';
    }
    return value
        .replaceAll('<br>', ' ')
        .replaceAll('<br/>', ' ')
        .replaceAll('<br />', ' ')
        .trim();
  }
}

class _CupertinoRecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final _CupertinoRecommendedSource source;
  final double? rating;

  _CupertinoRecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.source,
    this.rating,
  });
}

enum _CupertinoRecommendedSource {
  jellyfin,
  emby,
  local,
  placeholder,
}
