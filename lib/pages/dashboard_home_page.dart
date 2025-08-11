import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:nipaplay/pages/jellyfin_detail_page.dart';
import 'package:nipaplay/pages/emby_detail_page.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardHomePage extends StatefulWidget {
  const DashboardHomePage({super.key});

  @override
  State<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<DashboardHomePage>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  // 推荐内容数据
  List<RecommendedItem> _recommendedItems = [];
  bool _isLoadingRecommended = false;
  
  // 待处理的刷新请求
  bool _pendingRefreshAfterLoad = false;
  String _pendingRefreshReason = '';

  // 图片缓存 - 存储下载好的图片对象
  final Map<String, Image> _cachedImages = {}; // imageUrl -> ui.Image

  // 最近添加数据 - 按媒体库分类
  Map<String, List<JellyfinMediaItem>> _recentJellyfinItemsByLibrary = {};
  Map<String, List<EmbyMediaItem>> _recentEmbyItemsByLibrary = {};
  
  // 本地媒体库数据 - 使用番组信息而不是观看历史
  List<LocalAnimeItem> _localAnimeItems = [];
  // 本地媒体库图片持久化缓存（与 MediaLibraryPage 复用同一前缀）
  final Map<int, String> _localImageCache = {};
  static const String _localPrefsKeyPrefix = 'media_library_image_url_';
  bool _isLoadingLocalImages = false;

  final PageController _heroBannerPageController = PageController();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _continueWatchingScrollController = ScrollController();
  final ScrollController _recentJellyfinScrollController = ScrollController();
  final ScrollController _recentEmbyScrollController = ScrollController();
  
  // 动态媒体库的ScrollController映射
  final Map<String, ScrollController> _jellyfinLibraryScrollControllers = {};
  final Map<String, ScrollController> _embyLibraryScrollControllers = {};
  ScrollController? _localLibraryScrollController;
  
  // 自动切换相关
  Timer? _autoSwitchTimer;
  bool _isAutoSwitching = true;
  int _currentHeroBannerIndex = 0;
  late final ValueNotifier<int> _heroBannerIndexNotifier;
  int? _hoveredIndicatorIndex;

  @override
  void initState() {
    super.initState();
    _heroBannerIndexNotifier = ValueNotifier(0);
    
    // 🔥 修复Flutter状态错误：将数据加载移到addPostFrameCallback中
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupProviderListeners();
      _startAutoSwitch();
      
      // 🔥 在build完成后安全地加载数据，避免setState during build错误
      if (mounted) {
        _loadData();
      }
      
      // 延迟检查WatchHistoryProvider状态，如果已经加载完成但数据为空则重新加载
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
          if (watchHistoryProvider.isLoaded && _localAnimeItems.isEmpty && _recommendedItems.length <= 7) {
            debugPrint('DashboardHomePage: 延迟检查发现WatchHistoryProvider已加载但数据为空，重新加载数据');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _loadData();
              }
            });
          }
        }
      });
    });
  }
  
  // 获取或创建Jellyfin媒体库的ScrollController
  ScrollController _getJellyfinLibraryScrollController(String libraryName) {
    if (!_jellyfinLibraryScrollControllers.containsKey(libraryName)) {
      _jellyfinLibraryScrollControllers[libraryName] = ScrollController();
    }
    return _jellyfinLibraryScrollControllers[libraryName]!;
  }
  
  // 获取或创建Emby媒体库的ScrollController
  ScrollController _getEmbyLibraryScrollController(String libraryName) {
    if (!_embyLibraryScrollControllers.containsKey(libraryName)) {
      _embyLibraryScrollControllers[libraryName] = ScrollController();
    }
    return _embyLibraryScrollControllers[libraryName]!;
  }
  
  // 获取或创建本地媒体库的ScrollController
  ScrollController _getLocalLibraryScrollController() {
    _localLibraryScrollController ??= ScrollController();
    return _localLibraryScrollController!;
  }
  
  void _startAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _autoSwitchTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAutoSwitching && _recommendedItems.length >= 5 && mounted) {
        _currentHeroBannerIndex = (_currentHeroBannerIndex + 1) % 5;
        _heroBannerIndexNotifier.value = _currentHeroBannerIndex;
        if (_heroBannerPageController.hasClients) {
          _heroBannerPageController.animateToPage(
            _currentHeroBannerIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }
  
  void _stopAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _isAutoSwitching = false;
  }
  
  void _resumeAutoSwitch() {
    _isAutoSwitching = true;
    _startAutoSwitch();
  }
  
  void _setupProviderListeners() {
    // 监听Jellyfin连接状态变化
    try {
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      jellyfinProvider.addListener(_onJellyfinStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加JellyfinProvider监听器失败: $e');
    }
    
    // 监听Emby连接状态变化
    try {
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      embyProvider.addListener(_onEmbyStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加EmbyProvider监听器失败: $e');
    }
    
    // 监听WatchHistoryProvider的加载状态变化
    try {
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      watchHistoryProvider.addListener(_onWatchHistoryStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加WatchHistoryProvider监听器失败: $e');
    }
    
    // 监听ScanService的扫描完成状态变化
    try {
      final scanService = Provider.of<ScanService>(context, listen: false);
      scanService.addListener(_onScanServiceStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加ScanService监听器失败: $e');
    }
  }
  
  void _onJellyfinStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过Jellyfin状态变化处理');
      return;
    }
    
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    debugPrint('DashboardHomePage: Jellyfin连接状态变化 - isConnected: ${jellyfinProvider.isConnected}, mounted: $mounted');
    
    if (jellyfinProvider.isConnected && mounted) {
      if (_isLoadingRecommended) {
        // 如果正在加载，记录待处理的刷新请求
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'Jellyfin连接完成';
        debugPrint('DashboardHomePage: 正在加载中，记录Jellyfin刷新请求待稍后处理');
      } else {
        // 🔥 修复Flutter状态错误：使用addPostFrameCallback确保不在build期间调用
        debugPrint('DashboardHomePage: Jellyfin连接完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
    }
  }
  
  void _onEmbyStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过Emby状态变化处理');
      return;
    }
    
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    debugPrint('DashboardHomePage: Emby连接状态变化 - isConnected: ${embyProvider.isConnected}, mounted: $mounted');
    
    if (embyProvider.isConnected && mounted) {
      if (_isLoadingRecommended) {
        // 如果正在加载，记录待处理的刷新请求
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'Emby连接完成';
        debugPrint('DashboardHomePage: 正在加载中，记录Emby刷新请求待稍后处理');
      } else {
        // 🔥 修复Flutter状态错误：使用addPostFrameCallback确保不在build期间调用
        debugPrint('DashboardHomePage: Emby连接完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
    }
  }
  
  void _onWatchHistoryStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过WatchHistory状态变化处理');
      return;
    }
    
    final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
    debugPrint('DashboardHomePage: WatchHistory加载状态变化 - isLoaded: ${watchHistoryProvider.isLoaded}, mounted: $mounted');
    
    if (watchHistoryProvider.isLoaded && mounted) {
      if (_isLoadingRecommended) {
        // 如果正在加载，记录待处理的刷新请求
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'WatchHistory加载完成';
        debugPrint('DashboardHomePage: 正在加载中，记录WatchHistory刷新请求待稍后处理');
      } else {
        // 🔥 修复Flutter状态错误：使用addPostFrameCallback确保不在build期间调用
        debugPrint('DashboardHomePage: WatchHistory加载完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
    }
  }
  
  void _onScanServiceStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过ScanService状态变化处理');
      return;
    }
    
    final scanService = Provider.of<ScanService>(context, listen: false);
    debugPrint('DashboardHomePage: ScanService状态变化 - scanJustCompleted: ${scanService.scanJustCompleted}, mounted: $mounted');
    
    if (scanService.scanJustCompleted && mounted) {
      debugPrint('DashboardHomePage: 扫描完成，刷新WatchHistoryProvider和本地媒体库数据');
      
      // 刷新WatchHistoryProvider以获取最新的扫描结果
      try {
        final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
        watchHistoryProvider.refresh();
      } catch (e) {
        debugPrint('DashboardHomePage: 刷新WatchHistoryProvider失败: $e');
      }
      
      // 🔥 修复Flutter状态错误：使用addPostFrameCallback确保不在build期间调用
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
      
      // 确认扫描完成事件已处理
      scanService.acknowledgeScanCompleted();
    }
  }



  @override
  void dispose() {
    debugPrint('DashboardHomePage: 开始销毁Widget');
    
    // 清理定时器和ValueNotifier
    _autoSwitchTimer?.cancel();
    _heroBannerIndexNotifier.dispose();
    
    // 移除监听器 - 使用更安全的方式
    try {
      if (mounted) {
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.removeListener(_onJellyfinStateChanged);
        debugPrint('DashboardHomePage: JellyfinProvider监听器已移除');
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 移除JellyfinProvider监听器失败: $e');
    }
    
    try {
      if (mounted) {
        final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
        embyProvider.removeListener(_onEmbyStateChanged);
        debugPrint('DashboardHomePage: EmbyProvider监听器已移除');
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 移除EmbyProvider监听器失败: $e');
    }
    
    try {
      if (mounted) {
        final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
        watchHistoryProvider.removeListener(_onWatchHistoryStateChanged);
        debugPrint('DashboardHomePage: WatchHistoryProvider监听器已移除');
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 移除WatchHistoryProvider监听器失败: $e');
    }
    
    try {
      if (mounted) {
        final scanService = Provider.of<ScanService>(context, listen: false);
        scanService.removeListener(_onScanServiceStateChanged);
        debugPrint('DashboardHomePage: ScanService监听器已移除');
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 移除ScanService监听器失败: $e');
    }
    
    // 销毁ScrollController
    try {
      _heroBannerPageController.dispose();
      _mainScrollController.dispose();
      _continueWatchingScrollController.dispose();
      _recentJellyfinScrollController.dispose();
      _recentEmbyScrollController.dispose();
      
      // 销毁动态创建的ScrollController
      for (final controller in _jellyfinLibraryScrollControllers.values) {
        controller.dispose();
      }
      _jellyfinLibraryScrollControllers.clear();
      
      for (final controller in _embyLibraryScrollControllers.values) {
        controller.dispose();
      }
      _embyLibraryScrollControllers.clear();
      
      _localLibraryScrollController?.dispose();
      _localLibraryScrollController = null;
      
      debugPrint('DashboardHomePage: ScrollController已销毁');
    } catch (e) {
      debugPrint('DashboardHomePage: 销毁ScrollController失败: $e');
    }
    
    debugPrint('DashboardHomePage: Widget销毁完成');
    super.dispose();
  }

  Future<void> _loadData() async {
    debugPrint('DashboardHomePage: _loadData 被调用 - _isLoadingRecommended: $_isLoadingRecommended, mounted: $mounted');
    
    // 检查Widget状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过数据加载');
      return;
    }
    
    // 如果正在加载，先检查是否需要强制重新加载
    if (_isLoadingRecommended) {
      debugPrint('DashboardHomePage: 已在加载中，跳过重复调用 - _isLoadingRecommended: $_isLoadingRecommended');
      return;
    }
    
    // 🔥 修复仪表盘启动问题：确保WatchHistoryProvider已加载
    try {
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!watchHistoryProvider.isLoaded && !watchHistoryProvider.isLoading) {
        debugPrint('DashboardHomePage: WatchHistoryProvider未加载，主动触发加载');
        await watchHistoryProvider.loadHistory();
      } else if (watchHistoryProvider.isLoaded) {
        debugPrint('DashboardHomePage: WatchHistoryProvider已加载完成，历史记录数量: ${watchHistoryProvider.history.length}');
      } else {
        debugPrint('DashboardHomePage: WatchHistoryProvider正在加载中...');
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 加载WatchHistoryProvider失败: $e');
    }
    
    debugPrint('DashboardHomePage: 开始加载数据');
    await Future.wait([
      _loadRecommendedContent(),
      _loadRecentContent(),
    ]);
    
    // 再次检查Widget状态
    if (mounted) {
      debugPrint('DashboardHomePage: 数据加载完成');
    }
  }

  // 检查并处理待处理的刷新请求
  void _checkPendingRefresh() {
    if (_pendingRefreshAfterLoad && mounted) {
      debugPrint('DashboardHomePage: 处理待处理的刷新请求 - ${_pendingRefreshReason}');
      _pendingRefreshAfterLoad = false;
      _pendingRefreshReason = '';
      // 使用短延迟避免连续调用
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isLoadingRecommended) {
          _loadData();
        }
      });
    }
  }

  Future<void> _loadRecommendedContent() async {
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过推荐内容加载');
      return;
    }
    
    debugPrint('DashboardHomePage: 开始加载推荐内容');
    setState(() {
      _isLoadingRecommended = true;
    });

    try {
      // 第一步：快速收集所有候选项目（只收集基本信息）
      List<dynamic> allCandidates = [];

      // 从Jellyfin收集候选项目
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            try {
              final libraryItems = await jellyfinService.getRandomMediaItemsByLibrary(library.id, limit: 50);
              allCandidates.addAll(libraryItems);
              debugPrint('从Jellyfin媒体库 ${library.name} 收集到 ${libraryItems.length} 个候选项目');
            } catch (e) {
              debugPrint('获取Jellyfin媒体库 ${library.name} 随机内容失败: $e');
            }
          }
        }
      }

      // 从Emby收集候选项目
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            try {
              final libraryItems = await embyService.getRandomMediaItemsByLibrary(library.id, limit: 50);
              allCandidates.addAll(libraryItems);
              debugPrint('从Emby媒体库 ${library.name} 收集到 ${libraryItems.length} 个候选项目');
            } catch (e) {
              debugPrint('获取Emby媒体库 ${library.name} 随机内容失败: $e');
            }
          }
        }
      }

      // 从本地媒体库收集候选项目
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();
          
          // 按animeId分组，获取每个动画的最新观看记录
          final Map<int, WatchHistoryItem> latestLocalItems = {};
          for (var item in localHistory) {
            if (item.animeId != null) {
              if (latestLocalItems.containsKey(item.animeId!)) {
                if (item.lastWatchTime.isAfter(latestLocalItems[item.animeId!]!.lastWatchTime)) {
                  latestLocalItems[item.animeId!] = item;
                }
              } else {
                latestLocalItems[item.animeId!] = item;
              }
            }
          }
          
          // 随机选择一些本地项目 - 直接使用WatchHistoryItem作为候选
          final localItems = latestLocalItems.values.toList();
          localItems.shuffle(math.Random());
          final selectedLocalItems = localItems.take(math.min(30, localItems.length)).toList();
          allCandidates.addAll(selectedLocalItems);
          debugPrint('从本地媒体库收集到 ${selectedLocalItems.length} 个候选项目');
        } catch (e) {
          debugPrint('获取本地媒体库随机内容失败: $e');
        }
      } else {
        debugPrint('WatchHistoryProvider未加载完成，跳过本地媒体库推荐内容收集');
      }

      // 第二步：从所有候选中随机选择7个
      List<dynamic> selectedCandidates = [];
      if (allCandidates.isNotEmpty) {
        allCandidates.shuffle(math.Random());
        selectedCandidates = allCandidates.take(7).toList();
        debugPrint('从${allCandidates.length}个候选项目中随机选择了${selectedCandidates.length}个');
      }

      // 第三步：并行处理选中的7个项目，获取详细信息
      List<RecommendedItem> finalItems = [];
      
      // 并行处理所有候选项目
      final itemFutures = selectedCandidates.map((item) async {
        try {
          if (item is JellyfinMediaItem) {
            // 处理Jellyfin项目 - 并行获取图片和详细信息
            final jellyfinService = JellyfinService.instance;
            
            // 并行获取背景图片、Logo图片和详细信息
            final results = await Future.wait([
              _tryGetJellyfinImage(jellyfinService, item.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
              _tryGetJellyfinImage(jellyfinService, item.id, ['Logo', 'Thumb']),
              _getJellyfinItemSubtitle(jellyfinService, item),
            ]);
            
            final backdropUrl = results[0];
            final logoUrl = results[1];
            final subtitle = results[2];
            
            return RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: subtitle ?? '暂无简介信息',
              backgroundImageUrl: backdropUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.jellyfin,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            );
            
          } else if (item is EmbyMediaItem) {
            // 处理Emby项目 - 并行获取图片和详细信息
            final embyService = EmbyService.instance;
            
            // 并行获取背景图片、Logo图片和详细信息
            final results = await Future.wait([
              _tryGetEmbyImage(embyService, item.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
              _tryGetEmbyImage(embyService, item.id, ['Logo', 'Thumb']),
              _getEmbyItemSubtitle(embyService, item),
            ]);
            
            final backdropUrl = results[0];
            final logoUrl = results[1];
            final subtitle = results[2];
            
            return RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: subtitle ?? '暂无简介信息',
              backgroundImageUrl: backdropUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.emby,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            );
            
          } else if (item is WatchHistoryItem) {
            // 处理本地媒体库项目
            String subtitle = '暂无简介信息';
            String? backgroundImageUrl;
            
            // 尝试获取高清图片和详细信息
            if (item.animeId != null) {
              try {
                // 首先从弹弹play获取详细信息和bangumi ID
                final bangumiService = BangumiService.instance;
                final animeDetail = await bangumiService.getAnimeDetails(item.animeId!);
                subtitle = animeDetail.summary?.isNotEmpty == true ? animeDetail.summary! : '暂无简介信息';
                
                // 恢复原始图片加载逻辑
                backgroundImageUrl = await _getHighQualityImage(item.animeId!, animeDetail);
              } catch (e) {
                debugPrint('获取本地媒体详细信息失败 (animeId: ${item.animeId}): $e');
              }
            }
            
            return RecommendedItem(
              id: item.animeId?.toString() ?? item.filePath,
              title: item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画'),
              subtitle: subtitle,
              backgroundImageUrl: backgroundImageUrl,
              logoImageUrl: null, // 本地媒体库通常没有logo
              source: RecommendedItemSource.local,
              rating: null, // 本地媒体库暂时不支持评分
            );
          }
        } catch (e) {
          debugPrint('处理推荐项目失败: $e');
          return null;
        }
        return null;
      });
      
      // 等待所有项目处理完成
      final processedItems = await Future.wait(itemFutures);
      finalItems = processedItems.where((item) => item != null).cast<RecommendedItem>().toList();

      // 如果还不够7个，添加占位符
      while (finalItems.length < 7) {
        finalItems.add(RecommendedItem(
          id: 'placeholder_${finalItems.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }

      if (mounted) {
        setState(() {
          _recommendedItems = finalItems;
          _isLoadingRecommended = false;
        });
        
        // 推荐内容加载完成后启动自动切换
        if (finalItems.length >= 5) {
          _startAutoSwitch();
        }
        
        // 立即开始预加载所有推荐图片
        _preloadAllRecommendedImages(finalItems);
        
        // 检查是否有待处理的刷新请求
        _checkPendingRefresh();
      }
      debugPrint('推荐内容加载完成，总共 ${finalItems.length} 个项目');
    } catch (e) {
      debugPrint('加载推荐内容失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecommended = false;
        });
        
        // 检查是否有待处理的刷新请求
        _checkPendingRefresh();
      }
    }
  }

  Future<void> _loadRecentContent() async {
    debugPrint('DashboardHomePage: 开始加载最近内容');
    try {
      // 从Jellyfin按媒体库获取最近添加
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        _recentJellyfinItemsByLibrary.clear();
        
        // 获取选中的媒体库
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            try {
              // 按特定媒体库获取内容
              final libraryItems = await jellyfinService.getLatestMediaItemsByLibrary(library.id, limit: 25);
              
              if (libraryItems.isNotEmpty) {
                _recentJellyfinItemsByLibrary[library.name] = libraryItems;
                debugPrint('Jellyfin媒体库 ${library.name} 获取到 ${libraryItems.length} 个项目');
              }
            } catch (e) {
              debugPrint('获取Jellyfin媒体库 ${library.name} 最近内容失败: $e');
            }
          }
        }
      }

      // 从Emby按媒体库获取最近添加
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        _recentEmbyItemsByLibrary.clear();
        
        // 获取选中的媒体库
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            try {
              // 按特定媒体库获取内容
              final libraryItems = await embyService.getLatestMediaItemsByLibrary(library.id, limit: 25);
              
              if (libraryItems.isNotEmpty) {
                _recentEmbyItemsByLibrary[library.name] = libraryItems;
                debugPrint('Emby媒体库 ${library.name} 获取到 ${libraryItems.length} 个项目');
              }
            } catch (e) {
              debugPrint('获取Emby媒体库 ${library.name} 最近内容失败: $e');
            }
          }
        }
      }

      // 从本地媒体库获取最近添加（优化：不做逐文件stat，按历史记录时间排序，图片懒加载+持久化）
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();

          // 按animeId分组，选取“添加时间”代表：
          // 优先使用 isFromScan 为 true 的记录的 lastWatchTime（扫描入库时间），否则用最近一次 lastWatchTime
          final Map<int, WatchHistoryItem> representativeItems = {};
          final Map<int, DateTime> addedTimeMap = {};

          for (final item in localHistory) {
            final animeId = item.animeId;
            if (animeId == null) continue;

            final candidateTime = item.isFromScan ? item.lastWatchTime : item.lastWatchTime;
            if (!representativeItems.containsKey(animeId)) {
              representativeItems[animeId] = item;
              addedTimeMap[animeId] = candidateTime;
            } else {
              // 对于同一番组，取时间更新的那条作为代表
              if (candidateTime.isAfter(addedTimeMap[animeId]!)) {
                representativeItems[animeId] = item;
                addedTimeMap[animeId] = candidateTime;
              }
            }
          }

          // 提前从本地持久化中加载图片URL缓存，避免首屏大量网络请求
          await _loadPersistedLocalImageUrls(addedTimeMap.keys.toSet());

          // 构建 LocalAnimeItem 列表（先用缓存命中图片，未命中先留空，稍后后台补齐）
          List<LocalAnimeItem> localAnimeItems = representativeItems.entries.map((entry) {
            final animeId = entry.key;
            final latestEpisode = entry.value;
            final addedTime = addedTimeMap[animeId]!;
            final cachedImg = _localImageCache[animeId];
            return LocalAnimeItem(
              animeId: animeId,
              animeName: latestEpisode.animeName.isNotEmpty ? latestEpisode.animeName : '未知动画',
              imageUrl: cachedImg,
              backdropImageUrl: cachedImg,
              addedTime: addedTime,
              latestEpisode: latestEpisode,
            );
          }).toList();

          // 排序（最新在前）并限制数量
          localAnimeItems.sort((a, b) => b.addedTime.compareTo(a.addedTime));
          if (localAnimeItems.length > 25) {
            localAnimeItems = localAnimeItems.take(25).toList();
          }

          _localAnimeItems = localAnimeItems;
          debugPrint('本地媒体库获取到 ${_localAnimeItems.length} 个项目（首屏使用缓存图片，后台补齐高清图）');
        } catch (e) {
          debugPrint('获取本地媒体库最近内容失败: $e');
        }
      } else {
        debugPrint('WatchHistoryProvider未加载完成，跳过本地媒体库最近内容加载');
        _localAnimeItems = []; // 清空本地项目列表
      }

      if (mounted) {
        setState(() {
          // 触发UI更新
        });

        // 首屏渲染后，后台限流补齐缺失图片与番组详情（避免阻塞UI）
        _fetchLocalAnimeImagesInBackground();
      }
    } catch (e) {
      debugPrint('加载最近内容失败: $e');
    }
  }

  // 加载持久化的本地番组图片URL（与媒体库页复用同一Key前缀）
  Future<void> _loadPersistedLocalImageUrls(Set<int> animeIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in animeIds) {
        if (_localImageCache.containsKey(id)) continue;
        final url = prefs.getString('$_localPrefsKeyPrefix$id');
        if (url != null && url.isNotEmpty) {
          _localImageCache[id] = url;
        }
      }
    } catch (e) {
      debugPrint('加载本地图片持久化缓存失败: $e');
    }
  }

  // 后台抓取缺失的番组图片，限流并写入持久化缓存
  Future<void> _fetchLocalAnimeImagesInBackground() async {
    if (_isLoadingLocalImages) return;
    _isLoadingLocalImages = true;
    const int maxConcurrent = 3;
  final inflight = <Future<void>>[];

    for (final item in _localAnimeItems) {
      final id = item.animeId;
      if (_localImageCache.containsKey(id)) continue;

      Future<void> task() async {
        try {
          final detail = await BangumiService.instance.getAnimeDetails(id);
          final img = detail.imageUrl;
          if (img.isNotEmpty) {
            _localImageCache[id] = img;
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('$_localPrefsKeyPrefix$id', img);
            } catch (_) {}
            if (mounted) {
              // 局部更新对应项的图片字段
              final idx = _localAnimeItems.indexWhere((e) => e.animeId == id);
              if (idx != -1) {
                _localAnimeItems[idx] = LocalAnimeItem(
                  animeId: _localAnimeItems[idx].animeId,
                  animeName: _localAnimeItems[idx].animeName,
                  imageUrl: img,
                  backdropImageUrl: img,
                  addedTime: _localAnimeItems[idx].addedTime,
                  latestEpisode: _localAnimeItems[idx].latestEpisode,
                );
              }
            }
          }
        } catch (e) {
          // 静默失败，避免刷屏
        }
      }

      final fut = task();
      inflight.add(fut);
      fut.whenComplete(() {
        inflight.remove(fut);
      });
      if (inflight.length >= maxConcurrent) {
        try { await Future.any(inflight); } catch (_) {}
      }
    }

    try { await Future.wait(inflight); } catch (_) {}
    if (mounted) setState(() {});
    _isLoadingLocalImages = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer2<JellyfinProvider, EmbyProvider>(
        builder: (context, jellyfinProvider, embyProvider, child) {
          return SingleChildScrollView(
            controller: _mainScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // 大海报推荐区域
                  _buildHeroBanner(),
                  
                  const SizedBox(height: 32),
                  
                  // 继续播放区域
                  _buildContinueWatching(),
                  
                  const SizedBox(height: 32),
                  
                  // Jellyfin按媒体库显示最近添加
                  ..._recentJellyfinItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Jellyfin - 新增${entry.key}',
                      items: entry.value,
                      scrollController: _getJellyfinLibraryScrollController(entry.key),
                      onItemTap: (item) => _onJellyfinItemTap(item as JellyfinMediaItem),
                    ),
                    const SizedBox(height: 32),
                  ]).expand((x) => x),
                  
                  // Emby按媒体库显示最近添加
                  ..._recentEmbyItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Emby - 新增${entry.key}',
                      items: entry.value,
                      scrollController: _getEmbyLibraryScrollController(entry.key),
                      onItemTap: (item) => _onEmbyItemTap(item as EmbyMediaItem),
                    ),
                    const SizedBox(height: 32),
                  ]).expand((x) => x),
                  
                  // 本地媒体库显示最近添加
                  if (_localAnimeItems.isNotEmpty) ...[
                    _buildRecentSection(
                      title: '本地媒体库 - 最近添加',
                      items: _localAnimeItems,
                      scrollController: _getLocalLibraryScrollController(),
                      onItemTap: (item) => _onLocalAnimeItemTap(item as LocalAnimeItem),
                    ),
                    const SizedBox(height: 32),
                  ],
                  
                  // 空状态提示（当没有任何内容时）
                  if (_recentJellyfinItemsByLibrary.isEmpty && 
                      _recentEmbyItemsByLibrary.isEmpty && 
                      _localAnimeItems.isEmpty && 
                      !_isLoadingRecommended) ...[
                    Container(
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white10,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.video_library_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              jellyfinProvider.isConnected || embyProvider.isConnected
                                  ? '正在加载内容...'
                                  : '连接媒体服务器或观看本地视频以查看内容',
                              style: const TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                  
                  // 底部间距
                  const SizedBox(height: 50),
                ],
              ),
            );
        },
      ),
      floatingActionButton: _isLoadingRecommended 
          ? FloatingActionGlassButton(
              iconData: Icons.refresh_rounded,
              onPressed: () {}, // 加载中时禁用
              description: '正在刷新...',
            )
          : FloatingActionGlassButton(
              iconData: Icons.refresh_rounded,
              onPressed: _loadData,
              description: ' 刷新主页',
            ),
    );
  }

  Widget _buildHeroBanner() {
    if (_isLoadingRecommended) {
      return Container(
        height: 400,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white10,
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_recommendedItems.isEmpty) {
      return Container(
        height: 400,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white10,
        ),
        child: const Center(
          child: Text(
            '暂无推荐内容',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
      );
    }

    // 确保至少有7个项目用于布局
    final items = _recommendedItems.length >= 7 ? _recommendedItems.take(7).toList() : _recommendedItems;
    if (items.length < 7) {
      // 如果不足7个，填充占位符
      while (items.length < 7) {
        items.add(RecommendedItem(
          id: 'placeholder_${items.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }
    }

    return Container(
      height: 400,
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Row(
            children: [
              // 左侧主推荐横幅 - 占据大部分宽度，支持滑动（前5个）
              Expanded(
                flex: 2,
                child: PageView.builder(
                  controller: _heroBannerPageController,
                  itemCount: 5, // 固定显示5个
                  onPageChanged: (index) {
                    // 只更新当前索引和ValueNotifier，避免重新构建整个UI
                    _currentHeroBannerIndex = index;
                    _heroBannerIndexNotifier.value = index;
                    // 用户手动切换时停止自动切换3秒
                    _stopAutoSwitch();
                    Timer(const Duration(seconds: 3), () {
                      _resumeAutoSwitch();
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = items[index]; // 使用前5个
                    return _buildMainHeroBannerItem(item);
                  },
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 右侧小卡片区域 - 上下两个（第6和第7个）
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    // 上方小卡片（第6个）
                    Expanded(
                      child: _buildSmallRecommendationCard(items[5], 5),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // 下方小卡片（第7个）
                    Expanded(
                      child: _buildSmallRecommendationCard(items[6], 6),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // 页面指示器
          _buildPageIndicator(),
        ],
      ),
    );
  }

  Widget _buildMainHeroBannerItem(RecommendedItem item) {
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        key: ValueKey('hero_banner_${item.id}_${item.source.name}'), // 添加唯一key
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图 - 优先使用缓存的图片
            if (_cachedImages.containsKey(item.backgroundImageUrl))
              _cachedImages[item.backgroundImageUrl]!
            else if (item.backgroundImageUrl != null)
              Image.network(
                item.backgroundImageUrl!,
                key: ValueKey('hero_img_${item.id}_${item.backgroundImageUrl}'),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.white10,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.white10,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.white30),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.3),
                      Colors.purple.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 左上角服务商标识
            Positioned(
              top: 16,
              left: 16,
              child: _buildServiceIcon(item.source),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(1.0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左下角Logo - 优先使用缓存的图片
            if (_cachedImages.containsKey(item.logoImageUrl))
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 80,
                    ),
                    child: _cachedImages[item.logoImageUrl]!,
                  ),
                ),
              )
            else if (item.logoImageUrl != null)
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 80,
                    ),
                    child: Image.network(
                      item.logoImageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 200,
                          height: 80,
                          color: Colors.transparent,
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 200,
                        height: 80,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左侧中间位置的标题和简介
            Positioned(
              left: 16,
              right: MediaQuery.of(context).size.width * 0.3, // 留出右侧空间
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft, // 左对齐而不是居中
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 媒体名字（加粗显示）
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 剧情简介（只显示2行）
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle.replaceAll('<br>', ' ').replaceAll('<br/>', ' ').replaceAll('<br />', ' '),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallRecommendationCard(RecommendedItem item, int index) {
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        key: ValueKey('small_card_${item.id}_${item.source.name}_$index'), // 添加唯一key包含索引
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图 - 优先使用缓存的图片
            if (_cachedImages.containsKey(item.backgroundImageUrl))
              _cachedImages[item.backgroundImageUrl]!
            else if (item.backgroundImageUrl != null)
              Image.network(
                item.backgroundImageUrl!,
                key: ValueKey('small_img_${item.id}_${item.backgroundImageUrl}_$index'),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.white10,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.white10,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.white30, size: 16),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.3),
                      Colors.purple.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 左上角服务商标识
            Positioned(
              top: 8,
              left: 8,
              child: _buildServiceIcon(item.source),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 8,
                right: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(1.0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左下角小Logo（如果有的话）
            // Logo图片 - 优先使用缓存
            if (_cachedImages.containsKey(item.logoImageUrl))
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                    maxHeight: 45,
                  ),
                  child: _cachedImages[item.logoImageUrl]!,
                ),
              )
            else if (item.logoImageUrl != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                    maxHeight: 45,
                  ),
                  child: Image.network(
                    item.logoImageUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 120,
                        height: 45,
                        color: Colors.transparent,
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 120,
                      height: 45,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            
            // 右下角标题（总是显示，不论是否有Logo）
            Positioned(
              right: 8,
              bottom: 8,
              left: item.logoImageUrl != null ? 136 : 8, // 如果有Logo就避开它
              child: Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 8,
                      offset: Offset(1, 1),
                    ),
                    Shadow(
                      color: Colors.black,
                      blurRadius: 4,
                      offset: Offset(0, 0),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcon(RecommendedItemSource source) {
    Widget iconWidget;
    
    switch (source) {
      case RecommendedItemSource.jellyfin:
        iconWidget = SvgPicture.asset(
          'assets/jellyfin.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.emby:
        iconWidget = SvgPicture.asset(
          'assets/emby.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.local:
        // 本地文件用一个文件夹图标
        iconWidget = const Icon(
          Icons.folder,
          color: Colors.white,
          size: 20,
        );
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(1.0),
              width: 1,
            ),
          ),
          child: iconWidget,
        ),
      ),
    );
  }

  Widget _buildContinueWatching() {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        final validHistory = history.where((item) => item.duration > 0).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '继续播放',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (validHistory.isNotEmpty)
                  _buildScrollButtons(_continueWatchingScrollController, 292), // 卡片宽度280 + 12边距
              ],
            ),
            const SizedBox(height: 16),
            if (validHistory.isEmpty)
              Container(
                height: 180,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white10,
                ),
                child: const Center(
                  child: Text(
                    '暂无播放记录',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ),
              )
            else
              SizedBox(
                height: 280, // 增加高度以适应更大的卡片样式
                child: ListView.builder(
                  controller: _continueWatchingScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: math.min(validHistory.length, 10),
                  itemBuilder: (context, index) {
                    final item = validHistory[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildContinueWatchingCard(item),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildContinueWatchingCard(WatchHistoryItem item) {
    return GestureDetector(
      onTap: () => _onWatchHistoryItemTap(item),
      child: SizedBox(
        key: ValueKey('continue_${item.animeId ?? 0}_${item.filePath.hashCode}'), // 添加唯一key
        width: 280, // 增加宽度使卡片更大
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片容器
            Container(
              height: 158, // 16:9比例，280*0.5625=157.5
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景缩略图
                  _getVideoThumbnail(item),
                  
                  // 播放进度条（底部）
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: item.watchProgress,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.secondary,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 媒体名称
            Text(
              item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16, // 增加字体大小
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2, // 增加显示行数
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 4),
            
            // 集数信息
            if (item.episodeTitle != null)
              Text(
                item.episodeTitle!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14, // 增加字体大小
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection({
    required String title,
    required List<dynamic> items,
    required ScrollController scrollController,
    required Function(dynamic) onItemTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (items.isNotEmpty)
              _buildScrollButtons(scrollController, 162), // 卡片宽度150 + 12边距
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildMediaCard(item, onItemTap),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCard(dynamic item, Function(dynamic) onItemTap) {
    String name = '';
    String imageUrl = '';
    String uniqueId = '';
    
    if (item is JellyfinMediaItem) {
      name = item.name;
      uniqueId = 'jellyfin_${item.id}';
      try {
        imageUrl = JellyfinService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is EmbyMediaItem) {
      name = item.name;
      uniqueId = 'emby_${item.id}';
      try {
        imageUrl = EmbyService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is WatchHistoryItem) {
      name = item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画');
      uniqueId = 'history_${item.animeId ?? 0}_${item.filePath.hashCode}';
      imageUrl = item.thumbnailPath ?? '';
    } else if (item is LocalAnimeItem) {
      name = item.animeName;
      uniqueId = 'local_${item.animeId}_${item.animeName}';
      imageUrl = item.imageUrl ?? '';
    }

    return SizedBox(
      width: 150,
      height: 280,
      child: AnimeCard(
        key: ValueKey(uniqueId), // 添加唯一key防止widget复用导致的缓存混乱
        name: name,
        imageUrl: imageUrl,
        onTap: () => onItemTap(item),
        isOnAir: false,
      ),
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item) {
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        return FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(color: Colors.white10);
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
      }
    }
    return _buildDefaultThumbnail();
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Icon(Icons.video_library, color: Colors.white30, size: 32),
      ),
    );
  }

  void _onRecommendedItemTap(RecommendedItem item) {
    if (item.source == RecommendedItemSource.placeholder) return;
    
    if (item.source == RecommendedItemSource.jellyfin) {
      _navigateToJellyfinDetail(item.id);
    } else if (item.source == RecommendedItemSource.emby) {
      _navigateToEmbyDetail(item.id);
    } else if (item.source == RecommendedItemSource.local) {
      // 对于本地媒体库项目，使用animeId直接打开详情页
      if (item.id.contains(RegExp(r'^\d+$'))) {
        final animeId = int.tryParse(item.id);
        if (animeId != null) {
          AnimeDetailPage.show(context, animeId).then((result) {
            if (result != null) {
              // 刷新观看历史
              Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
              // 🔥 修复Flutter状态错误：使用addPostFrameCallback
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _loadData();
                }
              });
            }
          });
        }
      }
    }
  }

  void _onJellyfinItemTap(JellyfinMediaItem item) {
    _navigateToJellyfinDetail(item.id);
  }

  void _onEmbyItemTap(EmbyMediaItem item) {
    _navigateToEmbyDetail(item.id);
  }

  void _onLocalAnimeItemTap(LocalAnimeItem item) {
    // 打开动画详情页
    AnimeDetailPage.show(context, item.animeId).then((result) {
      if (result != null) {
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
        // 🔥 修复Flutter状态错误：使用addPostFrameCallback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
    });
  }

  // 已移除旧的创建本地动画项目的重量级方法，改为快速路径+后台补齐。

  void _navigateToJellyfinDetail(String jellyfinId) {
    JellyfinDetailPage.show(context, jellyfinId).then((result) {
      if (result != null) {
        // 检查是否需要获取实际播放URL
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
            final jellyfinService = JellyfinService.instance;
            if (jellyfinService.isConnected) {
              actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
            } else {
              BlurSnackBar.show(context, '未连接到Jellyfin服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
            return;
          }
        } else if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
            final embyService = EmbyService.instance;
            if (embyService.isConnected) {
              actualPlayUrl = embyService.getStreamUrl(embyId);
            } else {
              BlurSnackBar.show(context, '未连接到Emby服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
            return;
          }
        }
        
        // 创建PlayableItem并播放
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _navigateToEmbyDetail(String embyId) {
    EmbyDetailPage.show(context, embyId).then((result) {
      if (result != null) {
        // 检查是否需要获取实际播放URL
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
            final jellyfinService = JellyfinService.instance;
            if (jellyfinService.isConnected) {
              actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
            } else {
              BlurSnackBar.show(context, '未连接到Jellyfin服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
            return;
          }
        } else if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
            final embyService = EmbyService.instance;
            if (embyService.isConnected) {
              actualPlayUrl = embyService.getStreamUrl(embyId);
            } else {
              BlurSnackBar.show(context, '未连接到Emby服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
            return;
          }
        }
        
        // 创建PlayableItem并播放
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
          return;
        }
      }
      
      if (isEmbyProtocol) {
        try {
          final embyId = item.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = embyService.getStreamUrl(embyId);
          } else {
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
          return;
        }
      }
    } else {
      final videoFile = File(item.filePath);
      fileExists = videoFile.existsSync();
      
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          item = item.copyWith(filePath: filePath);
          fileExists = true;
        }
      }
    }
    
    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: item.filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }
  
  // 构建页面指示器（分离出来避免不必要的重建），支持点击和悬浮效果
  Widget _buildPageIndicator() {
    return Positioned(
      bottom: 16,
      left: 0,
      // 页面指示器只在左侧PageView区域显示：总宽度的2/3减去间距
      right: (MediaQuery.of(context).size.width - 32) / 3 + 12,
      child: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: _heroBannerIndexNotifier,
          builder: (context, currentIndex, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final bool isHovered = _hoveredIndicatorIndex == index;
                final bool isSelected = currentIndex == index;
                double size;
                if (isSelected && isHovered) {
                  size = 16.0; // 选中且悬浮时最大
                } else if (isHovered) {
                  size = 12.0; // 仅悬浮时变大
                } else {
                  size = 8.0; // 默认大小
                }

                return MouseRegion(
                  onEnter: (event) => setState(() => _hoveredIndicatorIndex = index),
                  onExit: (event) => setState(() => _hoveredIndicatorIndex = null),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      // 点击圆点时切换到对应页面
                      _stopAutoSwitch();
                      _currentHeroBannerIndex = index;
                      _heroBannerIndexNotifier.value = index;
                      _heroBannerPageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      Timer(const Duration(seconds: 3), () {
                        _resumeAutoSwitch();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: size,
                      height: size,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white
                            : (isHovered
                                ? Colors.white.withOpacity(0.8)
                                : Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  
  // 获取高清图片的方法
  Future<String?> _getHighQualityImage(int animeId, BangumiAnime animeDetail) async {
    try {
      // 首先尝试从弹弹play获取bangumi ID
      String? bangumiId = await _getBangumiIdFromDandanplay(animeId);
      
      if (bangumiId != null && bangumiId.isNotEmpty) {
        // 如果获取到bangumi ID，尝试从Bangumi API获取高清图片
        final bangumiImageUrl = await _getBangumiHighQualityImage(bangumiId);
        if (bangumiImageUrl != null && bangumiImageUrl.isNotEmpty) {
          debugPrint('从Bangumi API获取到高清图片: $bangumiImageUrl');
          return bangumiImageUrl;
        }
      }
      
      // 如果Bangumi API失败，回退到弹弹play的图片
      if (animeDetail.imageUrl.isNotEmpty) {
        debugPrint('回退到弹弹play图片: ${animeDetail.imageUrl}');
        return animeDetail.imageUrl;
      }
      
      debugPrint('未能获取到任何图片 (animeId: $animeId)');
      return null;
    } catch (e) {
      debugPrint('获取高清图片失败 (animeId: $animeId): $e');
      // 出错时回退到弹弹play的图片
      return animeDetail.imageUrl;
    }
  }
  
  // 从弹弹play API获取bangumi ID
  Future<String?> _getBangumiIdFromDandanplay(int animeId) async {
    try {
      // 使用弹弹play的番剧详情API获取bangumi ID
      final Map<String, dynamic> result = await DandanplayService.getBangumiDetails(animeId);
      
      if (result['success'] == true && result['bangumi'] != null) {
        final bangumi = result['bangumi'] as Map<String, dynamic>;
        
        // 检查是否有bangumiUrl，从中提取ID
        final String? bangumiUrl = bangumi['bangumiUrl'] as String?;
        if (bangumiUrl != null && bangumiUrl.contains('bangumi.tv/subject/')) {
          // 从URL中提取bangumi ID: https://bangumi.tv/subject/123456
          final RegExp regex = RegExp(r'bangumi\.tv/subject/(\d+)');
          final match = regex.firstMatch(bangumiUrl);
          if (match != null) {
            final bangumiId = match.group(1);
            debugPrint('从弹弹play获取到bangumi ID: $bangumiId');
            return bangumiId;
          }
        }
        
        // 也检查是否直接有bangumiId字段
        final dynamic directBangumiId = bangumi['bangumiId'];
        if (directBangumiId != null) {
          final String bangumiIdStr = directBangumiId.toString();
          if (bangumiIdStr.isNotEmpty && bangumiIdStr != '0') {
            debugPrint('从弹弹play直接获取到bangumi ID: $bangumiIdStr');
            return bangumiIdStr;
          }
        }
      }
      
      debugPrint('弹弹play未返回有效的bangumi ID (animeId: $animeId)');
      return null;
    } catch (e) {
      debugPrint('从弹弹play获取bangumi ID失败 (animeId: $animeId): $e');
      return null;
    }
  }
  
  // 从Bangumi API获取高清图片
  Future<String?> _getBangumiHighQualityImage(String bangumiId) async {
    try {
      // 使用Bangumi API的图片接口获取large尺寸的图片
      // GET /v0/subjects/{subject_id}/image?type=large
      final String imageApiUrl = 'https://api.bgm.tv/v0/subjects/$bangumiId/image?type=large';
      
      debugPrint('请求Bangumi图片API: $imageApiUrl');
      
      final response = await http.head(
        Uri.parse(imageApiUrl),
        headers: {
          'User-Agent': 'NipaPlay/1.0',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 302) {
        // Bangumi API返回302重定向到实际图片URL
        final String? location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          debugPrint('Bangumi API重定向到: $location');
          return location;
        }
      } else if (response.statusCode == 200) {
        // 有些情况下可能直接返回200
        return imageApiUrl;
      }
      
      debugPrint('Bangumi图片API响应异常: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('从Bangumi API获取图片失败 (bangumiId: $bangumiId): $e');
      return null;
    }
  }

  // 预加载所有推荐图片（下载图片对象而不是依赖URL）
  Future<void> _preloadAllRecommendedImages(List<RecommendedItem> items) async {
    debugPrint('开始预加载推荐图片...');
    
    if (items.length < 7) {
      debugPrint('推荐项目不足7个，跳过预加载');
      return;
    }
    
    // 优先加载用户当前能看到的图片：
    // 1. Hero Banner 当前页的背景图和 Logo
    // 2. 右侧两个小卡片的图片
    final currentItem = items[_currentHeroBannerIndex]; // 当前显示的 Hero Banner
    final rightCard1 = items[5]; // 右上小卡片
    final rightCard2 = items[6]; // 右下小卡片
    
    // 立即加载当前屏幕可见的图片
    final priorityFutures = <Future<void>>[];
    
    // 当前 Hero Banner 的背景图和 Logo
    if (currentItem.backgroundImageUrl != null && 
        currentItem.backgroundImageUrl!.isNotEmpty &&
        !currentItem.backgroundImageUrl!.contains('assets/') &&
        !_cachedImages.containsKey(currentItem.backgroundImageUrl!)) {
      priorityFutures.add(_downloadAndCacheImage(currentItem.backgroundImageUrl!, 'background_${currentItem.id}'));
    }
    
    if (currentItem.logoImageUrl != null && 
        currentItem.logoImageUrl!.isNotEmpty &&
        !currentItem.logoImageUrl!.contains('assets/') &&
        !_cachedImages.containsKey(currentItem.logoImageUrl!)) {
      priorityFutures.add(_downloadAndCacheImage(currentItem.logoImageUrl!, 'logo_${currentItem.id}'));
    }
    
    // 右侧两个小卡片的图片
    for (final card in [rightCard1, rightCard2]) {
      if (card.backgroundImageUrl != null && 
          card.backgroundImageUrl!.isNotEmpty &&
          !card.backgroundImageUrl!.contains('assets/') &&
          !_cachedImages.containsKey(card.backgroundImageUrl!)) {
        priorityFutures.add(_downloadAndCacheImage(card.backgroundImageUrl!, 'background_${card.id}'));
      }
      
      if (card.logoImageUrl != null && 
          card.logoImageUrl!.isNotEmpty &&
          !card.logoImageUrl!.contains('assets/') &&
          !_cachedImages.containsKey(card.logoImageUrl!)) {
        priorityFutures.add(_downloadAndCacheImage(card.logoImageUrl!, 'logo_${card.id}'));
      }
    }
    
    // 等待优先图片加载完成
    if (priorityFutures.isNotEmpty) {
      try {
        await Future.wait(priorityFutures, eagerError: false);
        debugPrint('优先图片加载完成，共加载了 ${priorityFutures.length} 张可见图片');
        if (mounted) setState(() {}); // 立即更新可见图片
      } catch (e) {
        debugPrint('加载优先图片时发生错误: $e');
      }
    }
    
    // 然后异步加载其他 Hero Banner 页面的图片
    final backgroundFutures = <Future<void>>[];
    
    for (int i = 0; i < 5; i++) { // Hero Banner 只有前5个
      final item = items[i];
      
      // 跳过已经加载的当前项目和右侧卡片项目
      if (i == _currentHeroBannerIndex || i == 5 || i == 6) continue;
      
      // 背景图片
      if (item.backgroundImageUrl != null && 
          item.backgroundImageUrl!.isNotEmpty &&
          !item.backgroundImageUrl!.contains('assets/') &&
          !_cachedImages.containsKey(item.backgroundImageUrl!)) {
        backgroundFutures.add(_downloadAndCacheImage(item.backgroundImageUrl!, 'background_${item.id}'));
      }
      
      // Logo图片
      if (item.logoImageUrl != null && 
          item.logoImageUrl!.isNotEmpty &&
          !item.logoImageUrl!.contains('assets/') &&
          !_cachedImages.containsKey(item.logoImageUrl!)) {
        backgroundFutures.add(_downloadAndCacheImage(item.logoImageUrl!, 'logo_${item.id}'));
      }
    }
    
    // 异步加载其他图片，不阻塞UI
    if (backgroundFutures.isNotEmpty) {
      Future.wait(backgroundFutures, eagerError: false).then((_) {
        debugPrint('其他推荐图片预加载完成，共预加载了 ${backgroundFutures.length} 张图片');
        if (mounted) setState(() {}); // 更新其他图片
      }).catchError((e) {
        debugPrint('预加载其他图片时发生错误: $e');
      });
    }
  }

  // 下载并缓存单个图片
  Future<void> _downloadAndCacheImage(String imageUrl, String cacheKey) async {
    try {
      debugPrint('下载图片: $imageUrl');
      
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        // 解码图片数据
        final codec = await instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        
        // 缓存图片对象
        _cachedImages[imageUrl] = Image.memory(
          response.bodyBytes,
          key: ValueKey(cacheKey),
          fit: BoxFit.cover,
        );
        
        debugPrint('图片下载并缓存成功: $imageUrl (${image.width}x${image.height})');
      } else {
        debugPrint('图片下载失败: $imageUrl, 状态码: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('下载图片时发生错误: $imageUrl, 错误: $e');
    }
  }

  // 辅助方法：尝试获取Jellyfin图片 - 并行验证版本
  Future<String?> _tryGetJellyfinImage(JellyfinService service, String itemId, List<String> imageTypes) async {
    // 构建所有可能的图片URL
    List<MapEntry<String, String>> imageUrlCandidates = [];
    
    for (String imageType in imageTypes) {
      try {
        String imageUrl;
        if (imageType == 'Backdrop') {
          imageUrl = service.getImageUrl(itemId, type: imageType, width: 1920, height: 1080, quality: 95);
        } else {
          imageUrl = service.getImageUrl(itemId, type: imageType);
        }
        
        if (imageUrl.isNotEmpty) {
          imageUrlCandidates.add(MapEntry(imageType, imageUrl));
        }
      } catch (e) {
        debugPrint('Jellyfin构建${imageType}图片URL失败: $e');
      }
    }
    
    if (imageUrlCandidates.isEmpty) {
      debugPrint('Jellyfin无法构建任何图片URL');
      return null;
    }
    
    // 并行验证所有URL
    final validationFutures = imageUrlCandidates.map((entry) async {
      try {
        final isValid = await _validateImageUrl(entry.value);
        return isValid ? entry : null;
      } catch (e) {
        debugPrint('Jellyfin验证${entry.key}图片失败: $e');
        return null;
      }
    });
    
    final validationResults = await Future.wait(validationFutures);
    
    // 按优先级顺序返回第一个有效的URL
    for (String imageType in imageTypes) {
      for (var result in validationResults) {
        if (result != null && result.key == imageType) {
          debugPrint('Jellyfin获取到${imageType}图片: ${result.value}');
          return result.value;
        }
      }
    }
    
    debugPrint('Jellyfin未找到任何可用图片，尝试类型: ${imageTypes.join(", ")}');
    return null;
  }

  // 辅助方法：尝试获取Emby图片 - 并行验证版本
  Future<String?> _tryGetEmbyImage(EmbyService service, String itemId, List<String> imageTypes) async {
    // 构建所有可能的图片URL
    List<MapEntry<String, String>> imageUrlCandidates = [];
    
    for (String imageType in imageTypes) {
      try {
        String imageUrl;
        if (imageType == 'Backdrop') {
          imageUrl = service.getImageUrl(itemId, type: imageType, width: 1920, height: 1080, quality: 95);
        } else {
          imageUrl = service.getImageUrl(itemId, type: imageType);
        }
        
        if (imageUrl.isNotEmpty) {
          imageUrlCandidates.add(MapEntry(imageType, imageUrl));
        }
      } catch (e) {
        debugPrint('Emby构建${imageType}图片URL失败: $e');
      }
    }
    
    if (imageUrlCandidates.isEmpty) {
      debugPrint('Emby无法构建任何图片URL');
      return null;
    }
    
    // 并行验证所有URL
    final validationFutures = imageUrlCandidates.map((entry) async {
      try {
        final isValid = await _validateImageUrl(entry.value);
        return isValid ? entry : null;
      } catch (e) {
        debugPrint('Emby验证${entry.key}图片失败: $e');
        return null;
      }
    });
    
    final validationResults = await Future.wait(validationFutures);
    
    // 按优先级顺序返回第一个有效的URL
    for (String imageType in imageTypes) {
      for (var result in validationResults) {
        if (result != null && result.key == imageType) {
          debugPrint('Emby获取到${imageType}图片: ${result.value}');
          return result.value;
        }
      }
    }
    
    debugPrint('Emby未找到任何可用图片，尝试类型: ${imageTypes.join(", ")}');
    return null;
  }

  // 辅助方法：获取Jellyfin项目简介
  Future<String> _getJellyfinItemSubtitle(JellyfinService service, JellyfinMediaItem item) async {
    try {
      final detail = await service.getMediaItemDetails(item.id);
      return detail.overview?.isNotEmpty == true ? detail.overview! : '暂无简介信息';
    } catch (e) {
      debugPrint('获取Jellyfin详细信息失败: $e');
      return item.overview?.isNotEmpty == true ? item.overview! : '暂无简介信息';
    }
  }

  // 辅助方法：获取Emby项目简介
  Future<String> _getEmbyItemSubtitle(EmbyService service, EmbyMediaItem item) async {
    try {
      final detail = await service.getMediaItemDetails(item.id);
      return detail.overview?.isNotEmpty == true ? detail.overview! : '暂无简介信息';
    } catch (e) {
      debugPrint('获取Emby详细信息失败: $e');
      return item.overview?.isNotEmpty == true ? item.overview! : '暂无简介信息';
    }
  }

  // 辅助方法：验证图片URL是否有效 - 优化版本
  Future<bool> _validateImageUrl(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(
        const Duration(seconds: 2), // 减少超时时间到2秒
        onTimeout: () => throw TimeoutException('图片验证超时', const Duration(seconds: 2)),
      );
      
      // 检查HTTP状态码是否成功
      if (response.statusCode != 200) {
        return false;
      }
      
      // 检查Content-Type是否为图片类型
      final contentType = response.headers['content-type'];
      if (contentType == null || !contentType.startsWith('image/')) {
        return false;
      }
      
      // 检查Content-Length，如果太小可能不是有效图片
      final contentLength = response.headers['content-length'];
      if (contentLength != null) {
        final length = int.tryParse(contentLength);
        if (length != null && length < 100) {
          return false;
        }
      }
      
      return true;
    } catch (e) {
      // 不打印验证失败日志，减少控制台输出
      return false;
    }
  }
  
  // 构建滚动按钮
  Widget _buildScrollButtons(ScrollController controller, double itemWidth) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final canScrollLeft = controller.hasClients && controller.offset > 0;
              return _buildScrollButton(
                icon: Icons.chevron_left,
                onTap: canScrollLeft ? () => _scrollToPrevious(controller, itemWidth) : null,
                enabled: canScrollLeft,
              );
            },
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final canScrollRight = controller.hasClients && 
                  controller.offset < controller.position.maxScrollExtent;
              return _buildScrollButton(
                icon: Icons.chevron_right,
                onTap: canScrollRight ? () => _scrollToNext(controller, itemWidth) : null,
                enabled: canScrollRight,
              );
            },
          ),
        ],
      ),
    );
  }
  
  // 构建单个滚动按钮
  Widget _buildScrollButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled 
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? Colors.white.withOpacity(0.3)
                  : Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: enabled ? onTap : null,
              child: Center(
                child: Icon(
                  icon,
                  color: enabled 
                      ? Colors.white
                      : Colors.white.withOpacity(0.5),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // 滚动到上一页
  void _scrollToPrevious(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = math.max(0.0, controller.offset - scrollDistance);
    
    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  // 滚动到下一页
  void _scrollToNext(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = controller.offset + scrollDistance;
    final maxScrollExtent = controller.position.maxScrollExtent;
    
    // 如果目标位置超过了最大滚动范围，就滚动到最大位置
    final finalTargetOffset = targetOffset > maxScrollExtent ? maxScrollExtent : targetOffset;
    
    controller.animateTo(
      finalTargetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

// 推荐内容数据模型
class RecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? backgroundImageUrl;
  final String? logoImageUrl;
  final RecommendedItemSource source;
  final double? rating;

  RecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.backgroundImageUrl,
    this.logoImageUrl,
    required this.source,
    this.rating,
  });
}

enum RecommendedItemSource {
  jellyfin,
  emby,
  local,
  placeholder,
}

// 本地动画项目数据模型
class LocalAnimeItem {
  final int animeId;
  final String animeName;
  final String? imageUrl;
  final String? backdropImageUrl;
  final DateTime addedTime; // 改为添加时间
  final WatchHistoryItem latestEpisode;

  LocalAnimeItem({
    required this.animeId,
    required this.animeName,
    this.imageUrl,
    this.backdropImageUrl,
    required this.addedTime, // 改为添加时间
    required this.latestEpisode,
  });
}
