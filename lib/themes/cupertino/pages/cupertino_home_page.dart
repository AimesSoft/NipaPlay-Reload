import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_shared_anime_detail_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_server_detail_page.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:path/path.dart' as p;

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
  bool _isLoadingLatest = false;
  bool _didScheduleInitialLoad = false;
  double _scrollOffset = 0.0;

  List<_CupertinoRecommendedItem> _recommendedItems = [];
  
  // 最近添加数据
  Map<String, List<dynamic>> _recentJellyfinItemsByLibrary = {};
  Map<String, List<dynamic>> _recentEmbyItemsByLibrary = {};
  List<WatchHistoryItem> _recentLocalItems = [];

  JellyfinProvider? _jellyfinProvider;
  EmbyProvider? _embyProvider;
  WatchHistoryProvider? _watchHistoryProvider;

  final Map<int, String> _localImageCache = {};
  final Map<String, Map<String, dynamic>> _thumbnailCache = {};
  static const String _localPrefsKeyPrefix = 'media_library_image_url_';

  static List<_CupertinoRecommendedItem> _cachedRecommendedItems = [];
  static DateTime? _lastRecommendedLoadTime;
  
  // 最近添加缓存（static以跨页面保持）
  static Map<String, List<dynamic>> _cachedJellyfinItemsByLibrary = {};
  static Map<String, List<dynamic>> _cachedEmbyItemsByLibrary = {};
  static List<WatchHistoryItem> _cachedLocalItems = [];
  static DateTime? _lastLatestLoadTime;

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
          _loadLatestContent();
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
    _loadLatestContent(forceRefresh: true); // 媒体源改变时也刷新最近添加
  }

  void _onHistoryChanged() {
    if (!mounted) return;
    if (_watchHistoryProvider?.isLoaded == true) {
      _scheduleRecommendedReload();
      _loadLatestContent(forceRefresh: true); // 历史记录改变时也刷新最近添加
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
            animeId: null,
            episodeCount: null,
            mediaServerItemId: candidate.id,
            mediaServerType: MediaServerType.jellyfin,
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
            animeId: null,
            episodeCount: null,
            mediaServerItemId: candidate.id,
            mediaServerType: MediaServerType.emby,
          );
        } else if (candidate is WatchHistoryItem) {
          String? imagePath;
          if (candidate.animeId != null) {
            imagePath = await _loadPersistedImage(candidate.animeId!);
          }

          imagePath ??= candidate.thumbnailPath;
          debugPrint(
            '[CupertinoHome] 推荐封面选择: animeId=${candidate.animeId} path=$imagePath',
          );

          built = _CupertinoRecommendedItem(
            id: 'local_${candidate.animeId ?? candidate.filePath}',
            title: candidate.animeName.isNotEmpty
                ? candidate.animeName
                : (candidate.episodeTitle ?? '本地媒体'),
            subtitle: candidate.episodeTitle ?? '继续观看',
            imageUrl: imagePath,
            source: _CupertinoRecommendedSource.local,
            rating: null,
            animeId: candidate.animeId,
            episodeCount: null,
            mediaServerItemId: null,
            mediaServerType: null,
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
            animeId: null,
            episodeCount: null,
            mediaServerItemId: null,
            mediaServerType: null,
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

  // 加载最近添加的媒体内容（Jellyfin/Emby/本地/NipaPlay共享）
  Future<void> _loadLatestContent({bool forceRefresh = false}) async {
    if (!mounted || _isLoadingLatest) return;

    // 使用缓存避免频繁加载（缓存12小时）
    final cacheValid = (_cachedJellyfinItemsByLibrary.isNotEmpty ||
            _cachedEmbyItemsByLibrary.isNotEmpty ||
            _cachedLocalItems.isNotEmpty) &&
        _lastLatestLoadTime != null &&
        DateTime.now().difference(_lastLatestLoadTime!).inHours < 12;

    if (!forceRefresh && cacheValid) {
      setState(() {
        _recentJellyfinItemsByLibrary = _cachedJellyfinItemsByLibrary;
        _recentEmbyItemsByLibrary = _cachedEmbyItemsByLibrary;
        _recentLocalItems = _cachedLocalItems;
        _isLoadingLatest = false;
      });
      return;
    }

    setState(() {
      _isLoadingLatest = true;
    });

    try {
      // 从Jellyfin按媒体库获取最近添加
      final jellyfinProvider = _jellyfinProvider;
      if (jellyfinProvider != null && jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        _recentJellyfinItemsByLibrary.clear();
        final jfFutures = <Future<void>>[];
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            jfFutures.add(() async {
              try {
                final libraryItems = await jellyfinService
                    .getLatestMediaItemsByLibrary(library.id, limit: 20);
                if (libraryItems.isNotEmpty) {
                  _recentJellyfinItemsByLibrary[library.name] = libraryItems;
                }
              } catch (e) {
                debugPrint('获取Jellyfin媒体库 ${library.name} 最近内容失败: $e');
              }
            }());
          }
        }
        if (jfFutures.isNotEmpty) {
          await Future.wait(jfFutures, eagerError: false);
        }
      } else {
        _recentJellyfinItemsByLibrary.clear();
      }

      // 从Emby按媒体库获取最近添加
      final embyProvider = _embyProvider;
      if (embyProvider != null && embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        _recentEmbyItemsByLibrary.clear();
        final emFutures = <Future<void>>[];
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            emFutures.add(() async {
              try {
                final libraryItems = await embyService
                    .getLatestMediaItemsByLibrary(library.id, limit: 20);
                if (libraryItems.isNotEmpty) {
                  _recentEmbyItemsByLibrary[library.name] = libraryItems;
                }
              } catch (e) {
                debugPrint('获取Emby媒体库 ${library.name} 最近内容失败: $e');
              }
            }());
          }
        }
        if (emFutures.isNotEmpty) {
          await Future.wait(emFutures, eagerError: false);
        }
      } else {
        _recentEmbyItemsByLibrary.clear();
      }

      // 从本地历史记录获取最近添加
      final historyProvider = _watchHistoryProvider;
      if (historyProvider != null && historyProvider.isLoaded) {
        try {
          final localHistory = historyProvider.history.where((item) {
            return !item.filePath.startsWith('jellyfin://') &&
                !item.filePath.startsWith('emby://');
          }).toList();

          final Map<int, WatchHistoryItem> latestByAnimeId = {};
          for (final item in localHistory) {
            final animeId = item.animeId;
            if (animeId == null) continue;

            final existing = latestByAnimeId[animeId];
            if (existing == null ||
                item.lastWatchTime.isAfter(existing.lastWatchTime)) {
              latestByAnimeId[animeId] = item;
            }
          }

          _recentLocalItems = latestByAnimeId.values.toList()
            ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
          if (_recentLocalItems.length > 20) {
            _recentLocalItems = _recentLocalItems.take(20).toList();
          }
        } catch (e) {
          debugPrint('获取本地最近内容失败: $e');
          _recentLocalItems = [];
        }
      } else {
        _recentLocalItems = [];
      }

      // 保存到缓存
      _cachedJellyfinItemsByLibrary = _recentJellyfinItemsByLibrary;
      _cachedEmbyItemsByLibrary = _recentEmbyItemsByLibrary;
      _cachedLocalItems = _recentLocalItems;
      _lastLatestLoadTime = DateTime.now();

      if (mounted) {
        setState(() {
          _isLoadingLatest = false;
        });
      }
    } catch (e) {
      debugPrint('加载最近添加内容失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingLatest = false;
        });
      }
    }
  }

  Future<String?> _loadPersistedImage(int animeId) async {
    final cached = _localImageCache[animeId];
    if (cached != null && cached.isNotEmpty) {
      if (_looksHighQualityUrl(cached)) {
        return cached;
      }
    }

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString('$_localPrefsKeyPrefix$animeId');
      if (persisted != null && persisted.isNotEmpty) {
        if (_looksHighQualityUrl(persisted)) {
          _localImageCache[animeId] = persisted;
          return persisted;
        }
      }

      final key = 'bangumi_detail_$animeId';
      final raw = prefs.getString(key);
      if (raw != null) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        final detail = decoded['animeDetail'] as Map<String, dynamic>?;
        final imageUrl = detail?['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          final resolvedUrl = await _maybeUpgradeBangumiImage(
            imageUrl,
            bangumiId: _extractBangumiIdFromDetailMap(detail),
          );
          _localImageCache[animeId] = resolvedUrl;
          await prefs.setString('$_localPrefsKeyPrefix$animeId', resolvedUrl);
          return resolvedUrl;
        }
      }
    } catch (_) {}

    try {
      final bangumiDetail =
          await BangumiService.instance.getAnimeDetails(animeId);
      var imageUrl = bangumiDetail.imageUrl;
      if (imageUrl.isNotEmpty) {
        imageUrl = await _maybeUpgradeBangumiImage(
          imageUrl,
          bangumiId: _extractBangumiIdFromAnime(bangumiDetail),
        );
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

  bool _looksHighQualityUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('bgm.tv') ||
        lower.contains('type=large') ||
        lower.contains('original')) {
      return true;
    }
    if (lower.contains('medium') || lower.contains('small')) {
      return false;
    }
    final widthMatch = RegExp(r'[?&]width=(\d+)').firstMatch(lower);
    if (widthMatch != null) {
      final width = int.tryParse(widthMatch.group(1)!);
      if (width != null && width >= 1000) {
        return true;
      }
    }
    return false;
  }

  Future<String> _maybeUpgradeBangumiImage(String imageUrl,
      {String? bangumiId}) async {
    if (_looksHighQualityUrl(imageUrl)) {
      return imageUrl;
    }
    if (bangumiId == null || bangumiId.isEmpty) {
      return imageUrl;
    }
    final hqUrl = await _fetchBangumiHighQualityCover(bangumiId);
    if (hqUrl != null && hqUrl.isNotEmpty) {
      return hqUrl;
    }
    return imageUrl;
  }

  String? _extractBangumiIdFromDetailMap(Map<String, dynamic>? detail) {
    if (detail == null) return null;
    final bangumiUrl = detail['bangumiUrl'] as String?;
    final fromUrl = _extractBangumiIdFromUrl(bangumiUrl);
    if (fromUrl != null) {
      return fromUrl;
    }
    final metadata = detail['metadata'];
    if (metadata is List) {
      for (final entry in metadata) {
        final fromMeta = _extractBangumiIdFromUrl(entry?.toString());
        if (fromMeta != null) {
          return fromMeta;
        }
      }
    }
    return null;
  }

  String? _extractBangumiIdFromAnime(BangumiAnime anime) {
    final fromUrl = _extractBangumiIdFromUrl(anime.bangumiUrl);
    if (fromUrl != null) {
      return fromUrl;
    }
    final metadata = anime.metadata;
    if (metadata != null) {
      for (final entry in metadata) {
        final id = _extractBangumiIdFromUrl(entry);
        if (id != null) {
          return id;
        }
      }
    }
    return null;
  }

  String? _extractBangumiIdFromUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    final match = RegExp(r'(?:bangumi|bgm)\.tv/subject/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  Future<String?> _fetchBangumiHighQualityCover(String bangumiId) async {
    try {
      final uri = Uri.parse(
          'https://api.bgm.tv/v0/subjects/$bangumiId/image?type=large');
      final response = await http.head(
        uri,
        headers: const {'User-Agent': 'NipaPlay/1.0'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 302) {
        final redirected = response.headers['location'];
        if (redirected != null && redirected.isNotEmpty) {
          return redirected;
        }
      } else if (response.statusCode == 200) {
        return uri.toString();
      }
    } catch (e) {
      debugPrint('CupertinoHomePage: 获取Bangumi高清封面失败: $e');
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
    await Future.wait([
      _loadRecommendedContent(forceRefresh: true),
      _loadLatestContent(),
    ]);
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
                child:
                    Consumer2<WatchHistoryProvider, AppearanceSettingsProvider>(
                  builder: (context, historyProvider, appearanceProvider, _) {
                    final recentItems = _buildRecentItems(
                        historyProvider.continueWatchingItems);
                    final style = appearanceProvider.recentWatchingStyle;

                    if (recentItems.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: _buildEmptyRecentPlaceholder(),
                      );
                    }

                    if (style == RecentWatchingStyle.detailed) {
                      return SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: recentItems.length,
                          itemBuilder: (context, index) {
                            final item = recentItems[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _buildDetailedRecentCard(item),
                            );
                          },
                        ),
                      );
                    } else {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Column(
                          children: recentItems
                              .map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildRecentCard(item),
                                  ))
                              .toList(),
                        ),
                      );
                    }
                  },
                ),
              ),
              // 最近添加部分（无标题，直接显示媒体库内容）
              SliverToBoxAdapter(child: _buildLatestSection()),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
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
    final cardHeight = cardWidth / (16 / 10); // 整个卡片 16:10 横图比例

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

  // 构建最近添加部分（包含Jellyfin/Emby/本地媒体库）
  Widget _buildLatestSection() {
    if (_isLoadingLatest) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    final hasJellyfin = _recentJellyfinItemsByLibrary.isNotEmpty;
    final hasEmby = _recentEmbyItemsByLibrary.isNotEmpty;
    final hasLocal = _recentLocalItems.isNotEmpty;

    if (!hasJellyfin && !hasEmby && !hasLocal) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Center(
          child: Text(
            '暂无最近添加的内容',
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondaryLabel,
                context,
              ),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Jellyfin媒体库
        if (hasJellyfin) ..._buildJellyfinLatestSections(),
        // Emby媒体库
        if (hasEmby) ..._buildEmbyLatestSections(),
        // 本地媒体库
        if (hasLocal) _buildLocalLatestSection(),
      ],
    );
  }

  List<Widget> _buildJellyfinLatestSections() {
    final List<Widget> sections = [];
    _recentJellyfinItemsByLibrary.forEach((libraryName, items) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 12, bottom: 8),
          child: Text(
            'Jellyfin - 新增$libraryName',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      sections.add(
        SizedBox(
          height: 210, // 增加高度以容纳封面和文字
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildLatestMediaCard(
                  item,
                  MediaServerType.jellyfin,
                ),
              );
            },
          ),
        ),
      );
    });
    return sections;
  }

  List<Widget> _buildEmbyLatestSections() {
    final List<Widget> sections = [];
    _recentEmbyItemsByLibrary.forEach((libraryName, items) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 12, bottom: 8),
          child: Text(
            'Emby - 新增$libraryName',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      sections.add(
        SizedBox(
          height: 210, // 增加高度以容纳封面和文字
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildLatestMediaCard(
                  item,
                  MediaServerType.emby,
                ),
              );
            },
          ),
        ),
      );
    });
    return sections;
  }

  Widget _buildLocalLatestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 20, top: 12, bottom: 8),
          child: Text(
            '本地媒体库 - 最近添加',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 210, // 增加高度以容纳封面和文字
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _recentLocalItems.length,
            itemBuilder: (context, index) {
              final item = _recentLocalItems[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildLocalLatestCard(item),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLatestMediaCard(dynamic item, MediaServerType serverType) {
    String? imageUrl;
    String title = '';

    if (serverType == MediaServerType.jellyfin && item is JellyfinMediaItem) {
      final jellyfinService = JellyfinService.instance;
      try {
        imageUrl = jellyfinService.getImageUrl(item.id, type: 'Primary');
      } catch (_) {}
      title = item.name;
    } else if (serverType == MediaServerType.emby && item is EmbyMediaItem) {
      final embyService = EmbyService.instance;
      try {
        imageUrl = embyService.getImageUrl(item.id, type: 'Primary');
      } catch (_) {}
      title = item.name;
    }

    return GestureDetector(
      onTap: () => _openMediaServerDetailFromItem(item, serverType),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 180, // 固定封面高度
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey5,
                              context,
                            ),
                            child: const Center(
                              child: Icon(
                                CupertinoIcons.photo,
                                size: 32,
                                color: CupertinoColors.systemGrey,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemGrey5,
                          context,
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.photo,
                            size: 32,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalLatestCard(WatchHistoryItem item) {
    return GestureDetector(
      onTap: () => _handleRecentTap(item),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 180, // 固定封面高度
                child: item.thumbnailPath != null
                    ? Image.network(
                        item.thumbnailPath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey5,
                              context,
                            ),
                            child: const Center(
                              child: Icon(
                                CupertinoIcons.play_rectangle,
                                size: 32,
                                color: CupertinoColors.systemGrey,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemGrey5,
                          context,
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.play_rectangle,
                            size: 32,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.animeName.isNotEmpty ? item.animeName : '本地媒体',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMediaServerDetailFromItem(
      dynamic item, MediaServerType serverType) async {
    if (!mounted) return;

    String itemId = '';
    if (item is JellyfinMediaItem) {
      itemId = item.id;
    } else if (item is EmbyMediaItem) {
      itemId = item.id;
    }

    if (itemId.isEmpty) return;

    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => CupertinoMediaServerDetailPage(
          mediaId: itemId,
          serverType: serverType,
        ),
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

    final bool hasAnimeId = item.animeId != null;
    final bool hasRemoteMedia =
        item.mediaServerItemId != null && item.mediaServerType != null;
    final bool canOpenDetail = (hasAnimeId || hasRemoteMedia) &&
        item.source != _CupertinoRecommendedSource.placeholder;

    // ignore: prefer_const_constructors
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canOpenDetail ? () => _openHeroDetail(item) : null,
      child: Semantics(
        button: canOpenDetail,
        enabled: canOpenDetail,
        label: item.title,
        child: Container(
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
                height: cardHeight * 1, // 遮罩覆盖卡片底部60%高度
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.75),
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
                        maxLines: 1,
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
        ),
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

    final cardContent = Container(
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleRecentTap(item),
      child: cardContent,
    );
  }

  Widget _buildDetailedRecentCard(WatchHistoryItem item) {
    final progress =
        item.duration > 0 ? item.watchProgress.clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () => _handleRecentTap(item),
      child: SizedBox(
        key: ValueKey(
            'detailed_recent_${item.animeId ?? 0}_${item.filePath.hashCode}'),
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 135,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _getVideoThumbnail(item),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: CupertinoColors.systemGrey4,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          CupertinoColors.activeBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.animeName.isNotEmpty
                  ? item.animeName
                  : p.basename(item.filePath),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.episodeTitle != null && item.episodeTitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.episodeTitle!,
                style: const TextStyle(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item) {
    final now = DateTime.now();

    // iOS平台特殊处理：检查截图文件的修改时间
    if (Platform.isIOS && item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        try {
          final fileModified = thumbnailFile.lastModifiedSync();
          final cacheKey =
              '${item.filePath}_${fileModified.millisecondsSinceEpoch}';

          if (_thumbnailCache.containsKey(cacheKey)) {
            final cachedData = _thumbnailCache[cacheKey]!;
            final lastRenderTime = cachedData['time'] as DateTime;

            if (now.difference(lastRenderTime).inSeconds < 60) {
              return cachedData['widget'] as Widget;
            }
          }

          _thumbnailCache
              .removeWhere((key, value) => key.startsWith('${item.filePath}_'));

          final thumbnailWidget = FutureBuilder<Uint8List>(
            future: thumbnailFile.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey6,
                    context,
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _buildDefaultThumbnail();
              }
              try {
                return Image.memory(
                  snapshot.data!,
                  key: ValueKey(
                      '${item.filePath}_${fileModified.millisecondsSinceEpoch}'),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              } catch (e) {
                return _buildDefaultThumbnail();
              }
            },
          );

          _thumbnailCache[cacheKey] = {'widget': thumbnailWidget, 'time': now};

          return thumbnailWidget;
        } catch (e) {
          debugPrint('获取截图文件修改时间失败: $e');
        }
      }
    }

    // 非iOS平台或获取修改时间失败时的逻辑
    if (_thumbnailCache.containsKey(item.filePath)) {
      final cachedData = _thumbnailCache[item.filePath]!;
      final lastRenderTime = cachedData['time'] as DateTime;

      if (now.difference(lastRenderTime).inSeconds < 60) {
        return cachedData['widget'] as Widget;
      }
    }

    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        final thumbnailWidget = FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.systemGrey6,
                  context,
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildDefaultThumbnail();
            }
            try {
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              );
            } catch (e) {
              return _buildDefaultThumbnail();
            }
          },
        );

        _thumbnailCache[item.filePath] = {
          'widget': thumbnailWidget,
          'time': now
        };

        return thumbnailWidget;
      }
    }

    final defaultThumbnail = _buildDefaultThumbnail();

    _thumbnailCache[item.filePath] = {'widget': defaultThumbnail, 'time': now};

    return defaultThumbnail;
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: CupertinoDynamicColor.resolve(
        CupertinoColors.systemGrey6,
        context,
      ),
      child: const Center(
        child: Icon(
          CupertinoIcons.video_camera,
          color: CupertinoColors.systemGrey3,
          size: 32,
        ),
      ),
    );
  }

  Future<void> _handleRecentTap(WatchHistoryItem item) async {
    if (item.filePath.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: '无法播放：缺少文件路径',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    try {
      final playable = await _buildPlayableItem(item);
      if (playable == null) {
        return;
      }
      await PlaybackService().play(playable);
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '播放失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<PlayableItem?> _buildPlayableItem(WatchHistoryItem item) async {
    String filePath = item.filePath;
    String? actualPlayUrl;
    bool fileExists = false;

    final bool isNetworkUrl = filePath.startsWith('http');
    final bool isJellyfinProtocol = filePath.startsWith('jellyfin://');
    final bool isEmbyProtocol = filePath.startsWith('emby://');

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;

      if (isJellyfinProtocol) {
        try {
          final jellyfinId = filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            AdaptiveSnackBar.show(
              context,
              message: '未连接到Jellyfin服务器',
              type: AdaptiveSnackBarType.error,
            );
            return null;
          }
        } catch (e) {
          AdaptiveSnackBar.show(
            context,
            message: '获取Jellyfin流地址失败：$e',
            type: AdaptiveSnackBarType.error,
          );
          return null;
        }
      }

      if (isEmbyProtocol) {
        try {
          final embyId = filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = await embyService.getStreamUrl(embyId);
          } else {
            AdaptiveSnackBar.show(
              context,
              message: '未连接到Emby服务器',
              type: AdaptiveSnackBarType.error,
            );
            return null;
          }
        } catch (e) {
          AdaptiveSnackBar.show(
            context,
            message: '获取Emby流地址失败：$e',
            type: AdaptiveSnackBarType.error,
          );
          return null;
        }
      }
    } else {
      final file = File(filePath);
      fileExists = file.existsSync();

      if (!fileExists && Platform.isIOS) {
        final altPath = filePath.startsWith('/private')
            ? filePath.replaceFirst('/private', '')
            : '/private$filePath';
        final altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          fileExists = true;
        }
      }
    }

    if (!fileExists) {
      AdaptiveSnackBar.show(
        context,
        message: '文件不存在或无法访问：${p.basename(item.filePath)}',
        type: AdaptiveSnackBarType.error,
      );
      return null;
    }

    return PlayableItem(
      videoPath: filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      actualPlayUrl: actualPlayUrl,
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

  Future<void> _openHeroDetail(_CupertinoRecommendedItem item) async {
    if (!mounted) return;

    if (item.mediaServerItemId != null && item.mediaServerType != null) {
      await _openMediaServerDetail(item);
      return;
    }

    if (item.animeId == null) {
      return;
    }

    SharedRemoteLibraryProvider? sharedProvider;
    try {
      sharedProvider = context.read<SharedRemoteLibraryProvider>();
    } on ProviderNotFoundException {
      sharedProvider = null;
    } catch (_) {
      sharedProvider = null;
    }

    ThemeNotifier? themeNotifier;
    try {
      themeNotifier = context.read<ThemeNotifier>();
    } on ProviderNotFoundException {
      themeNotifier = null;
    } catch (_) {
      themeNotifier = null;
    }

    final detailMode = themeNotifier?.animeDetailDisplayMode;

    if (sharedProvider == null) {
      ThemedAnimeDetail.show(context, item.animeId!);
      return;
    }

    SharedRemoteAnimeSummary? summary;
    for (final entry in sharedProvider.animeSummaries) {
      if (entry.animeId == item.animeId) {
        summary = entry;
        break;
      }
    }

    summary = summary != null
        ? SharedRemoteAnimeSummary(
            animeId: summary.animeId,
            name: summary.name,
            nameCn: summary.nameCn ?? summary.name,
            summary: summary.summary ?? item.subtitle,
            imageUrl: summary.imageUrl ?? item.imageUrl,
            lastWatchTime: summary.lastWatchTime,
            episodeCount: summary.episodeCount,
            hasMissingFiles: summary.hasMissingFiles,
          )
        : SharedRemoteAnimeSummary(
            animeId: item.animeId!,
            name: item.title,
            nameCn: item.title,
            summary: item.subtitle,
            imageUrl: item.imageUrl,
            lastWatchTime: DateTime.now(),
            episodeCount: item.episodeCount ?? 0,
            hasMissingFiles: false,
          );

    await CupertinoBottomSheet.show(
      context: context,
      title: null,
      showCloseButton: false,
      child: ChangeNotifierProvider<SharedRemoteLibraryProvider>.value(
        value: sharedProvider,
        child: CupertinoSharedAnimeDetailPage(
          anime: summary,
          hideBackButton: true,
          displayModeOverride: detailMode,
          showCloseButton: true,
        ),
      ),
    );
  }

  Future<void> _openMediaServerDetail(_CupertinoRecommendedItem item) async {
    if (!mounted ||
        item.mediaServerItemId == null ||
        item.mediaServerType == null) {
      return;
    }

    final serverType = item.mediaServerType!;
    final mediaId = item.mediaServerItemId!;

    switch (serverType) {
      case MediaServerType.jellyfin:
        var provider = _jellyfinProvider;
        if (provider == null || !provider.isConnected) {
          await NetworkMediaServerDialog.show(
              context, MediaServerType.jellyfin);
          provider = _jellyfinProvider;
          if (provider == null || !provider.isConnected) {
            return;
          }
        }
        await CupertinoMediaServerDetailPage.showJellyfin(context, mediaId);
        return;
      case MediaServerType.emby:
        var provider = _embyProvider;
        if (provider == null || !provider.isConnected) {
          await NetworkMediaServerDialog.show(context, MediaServerType.emby);
          provider = _embyProvider;
          if (provider == null || !provider.isConnected) {
            return;
          }
        }
        await CupertinoMediaServerDetailPage.showEmby(context, mediaId);
        return;
    }
  }
}

class _CupertinoRecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final _CupertinoRecommendedSource source;
  final double? rating;
  final int? animeId;
  final int? episodeCount;
  final String? mediaServerItemId;
  final MediaServerType? mediaServerType;

  _CupertinoRecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.source,
    this.rating,
    this.animeId,
    this.episodeCount,
    this.mediaServerItemId,
    this.mediaServerType,
  });
}

enum _CupertinoRecommendedSource {
  jellyfin,
  emby,
  local,
  placeholder,
}
