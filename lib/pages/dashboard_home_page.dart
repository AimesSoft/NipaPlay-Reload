library dashboard_home_page;

import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
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
import 'package:nipaplay/services/search_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_skeleton.dart';
import 'package:nipaplay/themes/nipaplay/widgets/loading_placeholder.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tag_search_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/floating_action_glass_button.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/watch_history_page.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/main.dart'; // 用于MainPageState
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/server_history_sync_service.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/utils/watch_history_auto_match_helper.dart';

part '../themes/nipaplay/widgets/dashboard_home_page_data_loading.dart';
part '../themes/nipaplay/widgets/dashboard_home_page_build_hero.dart';
part '../themes/nipaplay/widgets/dashboard_home_page_build_sections.dart';
part '../themes/nipaplay/widgets/dashboard_home_page_actions.dart';
part '../themes/nipaplay/widgets/dashboard_home_page_image_helpers.dart';
part '../themes/nipaplay/widgets/dashboard_home_page_models.dart';
part '../themes/nipaplay/widgets/dashboard_home_page_random_recommendations.dart';

class DashboardHomePage extends StatefulWidget {
  const DashboardHomePage({super.key});

  @override
  State<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<DashboardHomePage>
    with AutomaticKeepAliveClientMixin {
  // 持有Provider实例引用，确保在dispose中能正确移除监听器
  JellyfinProvider? _jellyfinProviderRef;
  EmbyProvider? _embyProviderRef;
  WatchHistoryProvider? _watchHistoryProviderRef;
  ScanService? _scanServiceRef;
  VideoPlayerState? _videoPlayerStateRef;
  // Provider ready 回调引用，便于移除
  VoidCallback? _jellyfinProviderReadyListener;
  VoidCallback? _embyProviderReadyListener;
  // 按服务粒度的监听开关
  bool _jellyfinLiveListening = false;
  bool _embyLiveListening = false;
  // Provider 通知后的轻量防抖（覆盖库选择等状态变化）
  Timer? _jfDebounceTimer;
  Timer? _emDebounceTimer;
  Timer? _watchHistoryDebounceTimer;

  bool _isHistoryAutoMatching = false;
  bool _historyAutoMatchDialogVisible = false;
  
  
  @override
  bool get wantKeepAlive => true;

  // 推荐内容数据
  List<RecommendedItem> _recommendedItems = [];
  bool _isLoadingRecommended = false;
  bool _isLoadingRecentContent = false;
  
  // 待处理的刷新请求
  bool _pendingRefreshAfterLoad = false;
  String _pendingRefreshReason = '';

  // 播放器状态追踪，用于检测退出播放器时触发刷新
  bool _wasPlayerActive = false;
  Timer? _playerStateCheckTimer;
  
  // 播放器状态缓存，减少频繁的Provider查询
  bool _cachedPlayerActiveState = false;
  DateTime _lastPlayerStateCheck = DateTime.now();

  // 移除老的图片缓存系统，现在使用 CachedNetworkImageWidget

  // 最近添加数据 - 按媒体库分类
  Map<String, List<JellyfinMediaItem>> _recentJellyfinItemsByLibrary = {};
  Map<String, List<EmbyMediaItem>> _recentEmbyItemsByLibrary = {};
  List<DandanplayRemoteAnimeGroup> _recentDandanplayGroups = [];
  ScrollController? _dandanplayScrollController;
  Map<String, DandanplayRemoteAnimeGroup> _recommendedDandanLookup = {};

  bool _isValidAnimeId(int? value) => value != null && value > 0;
  
  // 本地媒体库数据 - 使用番组信息而不是观看历史
  List<LocalAnimeItem> _localAnimeItems = [];
  
  // 今日新番数据
  List<BangumiAnime> _todayAnimes = [];
  bool _isLoadingTodayAnimes = false;
  ScrollController? _todayAnimesScrollController;

  // 随机推荐数据
  List<RandomRecommendationItem> _randomRecommendations = [];
  bool _isLoadingRandomRecommendations = false;
  ScrollController? _randomRecommendationsScrollController;

  // 本地媒体库图片持久化缓存（与 MediaLibraryPage 复用同一前缀）
  final Map<int, String> _localImageCache = {};
  static const String _localPrefsKeyPrefix = 'media_library_image_url_';
  bool _isLoadingLocalImages = false;
  bool _isLoadingDandanImages = false;

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

  // 缓存映射，用于存储已绘制的缩略图和最后绘制时间
  final Map<String, Map<String, dynamic>> _thumbnailCache = {};

  // 追踪已绘制的文件路径
  // ignore: unused_field
  final Set<String> _renderedThumbnailPaths = {};

  // 静态变量，用于缓存推荐内容
  static List<RecommendedItem> _cachedRecommendedItems = [];
  static DateTime? _lastRecommendedLoadTime;
  static Map<String, DandanplayRemoteAnimeGroup> _cachedDandanLookup = {};
  // 最近一次数据加载时间，用于合并短时间内的重复触发
  DateTime? _lastLoadTime;

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
        _loadData(
          forceRefreshRecommended: true,
          forceRefreshRandom: true,
          forceRefreshToday: true,
        );
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

  ScrollController _getDandanplayLibraryScrollController() {
    _dandanplayScrollController ??= ScrollController();
    return _dandanplayScrollController!;
  }

  ScrollController _getTodayAnimesScrollController() {
    _todayAnimesScrollController ??= ScrollController();
    return _todayAnimesScrollController!;
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
    // 订阅 Provider 级 ready；ready 之前不监听 Provider 的即时变化
    try {
      _jellyfinProviderRef = Provider.of<JellyfinProvider>(context, listen: false);
      _jellyfinProviderReadyListener = () {
        if (!mounted) return;
        debugPrint('DashboardHomePage: 收到 Jellyfin Provider ready 信号');
        // ready 后立即清理待处理请求，避免重复刷新
        _pendingRefreshAfterLoad = false;
        _pendingRefreshReason = '';
        // 先触发首次加载，避免激活监听后立即触发状态变化导致重复刷新
        _triggerLoadIfIdle('Jellyfin Provider ready');
        // 等待首次加载完成后再激活监听，避免加载期间的状态变化被捕获
        _scheduleJellyfinListeningActivation();
      };
      _jellyfinProviderRef!.addReadyListener(_jellyfinProviderReadyListener!);
      // 若进入页面时已 provider-ready，则立即激活监听并首刷
      if (_jellyfinProviderRef!.isReady) {
        _activateJellyfinLiveListening();
        // 不在进入页面时立即刷新，首刷由 initState 的 _loadData 负责，避免重复刷新
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 安装 Jellyfin Provider ready 监听失败: $e');
    }
    try {
      _embyProviderRef = Provider.of<EmbyProvider>(context, listen: false);
      _embyProviderReadyListener = () {
        if (!mounted) return;
        debugPrint('DashboardHomePage: 收到 Emby Provider ready 信号');
        // ready 后立即清理待处理请求，避免重复刷新
        _pendingRefreshAfterLoad = false;
        _pendingRefreshReason = '';
        // 先触发首次加载，避免激活监听后立即触发状态变化导致重复刷新
        _triggerLoadIfIdle('Emby Provider ready');
        // 等待首次加载完成后再激活监听，避免加载期间的状态变化被捕获
        _scheduleEmbyListeningActivation();
      };
      _embyProviderRef!.addReadyListener(_embyProviderReadyListener!);
      if (_embyProviderRef!.isReady) {
        _activateEmbyLiveListening();
        // 不在进入页面时立即刷新，首刷由 initState 的 _loadData 负责，避免重复刷新
      }
    } catch (e) {
      debugPrint('DashboardHomePage: 安装 Emby Provider ready 监听失败: $e');
    }
    
    // 监听WatchHistoryProvider的加载状态变化
    try {
  _watchHistoryProviderRef = Provider.of<WatchHistoryProvider>(context, listen: false);
  _watchHistoryProviderRef!.addListener(_onWatchHistoryStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加WatchHistoryProvider监听器失败: $e');
    }
    
    // 监听ScanService的扫描完成状态变化
    try {
  _scanServiceRef = Provider.of<ScanService>(context, listen: false);
  _scanServiceRef!.addListener(_onScanServiceStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加ScanService监听器失败: $e');
    }
    
    // 监听VideoPlayerState的状态变化，用于检测播放器状态
    try {
  _videoPlayerStateRef = Provider.of<VideoPlayerState>(context, listen: false);
  _videoPlayerStateRef!.addListener(_onVideoPlayerStateChanged);
    } catch (e) {
      debugPrint('DashboardHomePage: 添加VideoPlayerState监听器失败: $e');
    }
  }

  void _activateJellyfinLiveListening() {
    if (_jellyfinLiveListening || _jellyfinProviderRef == null) return;
    try {
      _jellyfinProviderRef!.addListener(_onJellyfinStateChanged);
      _jellyfinLiveListening = true;
      debugPrint('DashboardHomePage: 已激活 Jellyfin Provider 即时监听');
    } catch (e) {
      debugPrint('DashboardHomePage: 激活 Jellyfin 监听失败: $e');
    }
  }

  void _scheduleJellyfinListeningActivation() {
    // 等待当前数据加载完成后再激活监听，避免加载期间的状态变化被误捕获
    void checkAndActivate() {
      if (!mounted) return;
      if (_isLoadingRecommended) {
        // 如果还在加载，继续等待
        Future.delayed(const Duration(milliseconds: 100), checkAndActivate);
      } else {
        // 加载完成，可以安全激活监听
        _activateJellyfinLiveListening();
      }
    }
    checkAndActivate();
  }

  void _deactivateJellyfinLiveListening() {
    if (!_jellyfinLiveListening) return;
    try {
      _jellyfinProviderRef?.removeListener(_onJellyfinStateChanged);
    } catch (_) {}
    _jellyfinLiveListening = false;
    debugPrint('DashboardHomePage: 已暂停 Jellyfin Provider 即时监听');
  }

  void _activateEmbyLiveListening() {
    if (_embyLiveListening || _embyProviderRef == null) return;
    try {
      _embyProviderRef!.addListener(_onEmbyStateChanged);
      _embyLiveListening = true;
      debugPrint('DashboardHomePage: 已激活 Emby Provider 即时监听');
    } catch (e) {
      debugPrint('DashboardHomePage: 激活 Emby 监听失败: $e');
    }
  }

  void _scheduleEmbyListeningActivation() {
    // 等待当前数据加载完成后再激活监听，避免加载期间的状态变化被误捕获
    void checkAndActivate() {
      if (!mounted) return;
      if (_isLoadingRecommended) {
        // 如果还在加载，继续等待
        Future.delayed(const Duration(milliseconds: 100), checkAndActivate);
      } else {
        // 加载完成，可以安全激活监听
        _activateEmbyLiveListening();
      }
    }
    checkAndActivate();
  }

  void _deactivateEmbyLiveListening() {
    if (!_embyLiveListening) return;
    try {
      _embyProviderRef?.removeListener(_onEmbyStateChanged);
    } catch (_) {}
    _embyLiveListening = false;
    debugPrint('DashboardHomePage: 已暂停 Emby Provider 即时监听');
  }

  // ready 或进入页面即已 ready 时，若空闲则立即刷新一次
  void _triggerLoadIfIdle(String reason) {
    if (!mounted) return;
    debugPrint('DashboardHomePage: 检测到$reason，准备执行首次刷新');
    if (_isVideoPlayerActive()) return;
    // 合并短时间内的重复触发：注意，后端 ready 不参与合并，必须执行；仅合并后续触发
    final now = DateTime.now();
    final bool isBackendReady = reason.contains('后端 ready');
    if (!isBackendReady && _lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < 500) {
      debugPrint('DashboardHomePage: 距上次加载过近(${now.difference(_lastLoadTime!).inMilliseconds}ms)，跳过这次($reason)');
      return;
    }
    if (_isLoadingRecommended) {
      _pendingRefreshAfterLoad = true;
      _pendingRefreshReason = reason;
      return;
    }
    _loadData();
  }
  
  // 检查播放器是否处于活跃状态（播放中、暂停或准备好播放）
  bool _isVideoPlayerActive() {
    try {
      // 使用缓存机制，避免频繁的Provider查询
      final now = DateTime.now();
      const cacheValidDuration = Duration(milliseconds: 100); // 100ms缓存
      
      if (now.difference(_lastPlayerStateCheck) < cacheValidDuration) {
        return _cachedPlayerActiveState;
      }
      
      final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
      final isActive = videoPlayerState.status == PlayerStatus.playing || 
             videoPlayerState.status == PlayerStatus.paused ||
             videoPlayerState.hasVideo ||
             videoPlayerState.currentVideoPath != null;
      
      // 更新缓存
      _cachedPlayerActiveState = isActive;
      _lastPlayerStateCheck = now;
      
      // 只在状态发生变化时打印调试信息，减少日志噪音
      if (isActive != _wasPlayerActive) {
        debugPrint('DashboardHomePage: 播放器活跃状态变化 - $isActive '
                   '(status: ${videoPlayerState.status}, hasVideo: ${videoPlayerState.hasVideo})');
      }
      
      return isActive;
    } catch (e) {
      debugPrint('DashboardHomePage: _isVideoPlayerActive() 出错: $e');
      return false;
    }
  }

  // 判断是否应该延迟图片加载（避免与HEAD验证竞争）
  bool _shouldDelayImageLoad() {
    // 检查推荐内容中是否包含本地媒体
    final hasLocalContent = _recommendedItems.any((item) => 
      item.source == RecommendedItemSource.local
    );
    
    // 如果有本地媒体，就立即加载以保持最佳性能；没有本地媒体才延迟避免与HEAD验证竞争
    return !hasLocalContent;
  }

  void _onVideoPlayerStateChanged() {
    if (!mounted) return;
    
    final isCurrentlyActive = _isVideoPlayerActive();
    
    // 检测播放器从活跃状态变为非活跃状态（退出播放器）
    if (_wasPlayerActive && !isCurrentlyActive) {
      debugPrint('DashboardHomePage: 检测到播放器状态变为非活跃，启动延迟检查');
      
      // 取消之前的检查Timer
      _playerStateCheckTimer?.cancel();
      
      // 延迟检查，避免快速状态切换时的误触发
      _playerStateCheckTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && !_isVideoPlayerActive()) {
          debugPrint('DashboardHomePage: 确认播放器已退出，刷新最近观看');
          _scheduleWatchHistoryRefresh('播放器退出');
        } else {
          debugPrint('DashboardHomePage: 播放器状态已恢复活跃，取消更新');
        }
      });
    }
    
    // 如果播放器重新变为活跃状态，取消待处理的更新
    if (!_wasPlayerActive && isCurrentlyActive) {
      debugPrint('DashboardHomePage: 播放器重新激活，取消待处理的更新检查');
      _playerStateCheckTimer?.cancel();
    }
    
    // 更新播放器活跃状态记录
    _wasPlayerActive = isCurrentlyActive;
  }

  void _scheduleWatchHistoryRefresh(String reason) {
    if (!mounted) return;
    try {
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!watchHistoryProvider.isLoaded) {
        return;
      }
    } catch (_) {
      return;
    }
    _watchHistoryDebounceTimer?.cancel();
    _watchHistoryDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      debugPrint('DashboardHomePage: 触发最近观看刷新 - $reason');
      unawaited(_loadRecentContent(includeRemote: false));
    });
  }
  
  void _onJellyfinStateChanged() {
  if (!_jellyfinLiveListening) return; // ready 前不处理
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过Jellyfin状态变化处理');
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过Jellyfin状态变化处理');
      return;
    }
    
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    final connected = jellyfinProvider.isConnected;
    debugPrint('DashboardHomePage: Jellyfin provider 状态变化 - isConnected: $connected, mounted: $mounted');

    // 断开连接时，立即清空“最近添加”并刷新一次UI，避免残留
    if (!connected && mounted) {
      if (_recentJellyfinItemsByLibrary.isNotEmpty) {
        _recentJellyfinItemsByLibrary.clear();
        setState(() {});
      }
      // 继续走防抖以触发后续常规刷新（如空态）
    }

    // 已连接时的即时刷新（保持原有有效逻辑）：
    if (connected && mounted) {
      // 合并短时间内的重复触发（避免与刚刚的 ready/首刷重叠）
      final now = DateTime.now();
      if (_lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < 500) {
        debugPrint('DashboardHomePage: Jellyfin连接完成，但距上次加载过近(${now.difference(_lastLoadTime!).inMilliseconds}ms)，跳过立即刷新');
        return;
      }
      if (_isLoadingRecommended) {
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'Jellyfin连接完成';
        debugPrint('DashboardHomePage: 正在加载中，记录Jellyfin刷新请求待稍后处理');
      } else {
        debugPrint('DashboardHomePage: Jellyfin连接完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
      return; // 避免与防抖重复触发
    }

  // 统一处理 provider 状态变化（连接/断开/库选择等）：轻量防抖刷新
    _jfDebounceTimer?.cancel();
    _jfDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _isVideoPlayerActive() || _isLoadingRecommended) return;
      debugPrint('DashboardHomePage: Jellyfin provider 状态变化（防抖触发）刷新');
      _loadData();
    });
  }
  
  void _onEmbyStateChanged() {
  if (!_embyLiveListening) return; // ready 前不处理
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过Emby状态变化处理');
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过Emby状态变化处理');
      return;
    }
    
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    final connected = embyProvider.isConnected;
    debugPrint('DashboardHomePage: Emby provider 状态变化 - isConnected: $connected, mounted: $mounted');

    // 断开连接时，立即清空“最近添加”并刷新一次UI，避免残留
    if (!connected && mounted) {
      if (_recentEmbyItemsByLibrary.isNotEmpty) {
        _recentEmbyItemsByLibrary.clear();
        setState(() {});
      }
      // 继续走防抖以触发后续常规刷新（如空态）
    }

    // 已连接时的即时刷新（保持原有有效逻辑）：
    if (connected && mounted) {
      // 合并短时间内的重复触发（避免与刚刚的 ready/首刷重叠）
      final now = DateTime.now();
      if (_lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < 500) {
        debugPrint('DashboardHomePage: Emby连接完成，但距上次加载过近(${now.difference(_lastLoadTime!).inMilliseconds}ms)，跳过立即刷新');
        return;
      }
      if (_isLoadingRecommended) {
        _pendingRefreshAfterLoad = true;
        _pendingRefreshReason = 'Emby连接完成';
        debugPrint('DashboardHomePage: 正在加载中，记录Emby刷新请求待稍后处理');
      } else {
        debugPrint('DashboardHomePage: Emby连接完成，立即刷新数据');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
      return; // 避免与防抖重复触发
    }

  // 统一处理 provider 状态变化（连接/断开/库选择等）：轻量防抖刷新
    _emDebounceTimer?.cancel();
    _emDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _isVideoPlayerActive() || _isLoadingRecommended) return;
      debugPrint('DashboardHomePage: Emby provider 状态变化（防抖触发）刷新');
      _loadData();
    });
  }
  
  void _onWatchHistoryStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      return;
    }

    final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
    debugPrint('DashboardHomePage: WatchHistory加载状态变化 - isLoaded: ${watchHistoryProvider.isLoaded}, mounted: $mounted');
    
    if (watchHistoryProvider.isLoaded && mounted) {
      _scheduleWatchHistoryRefresh('WatchHistory变化');
    }
  }
  
  void _onScanServiceStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      debugPrint('DashboardHomePage: Widget已销毁，跳过ScanService状态变化处理');
      return;
    }
    
    // 如果播放器处于活跃状态（播放或暂停），跳过主页更新
    if (_isVideoPlayerActive()) {
      debugPrint('DashboardHomePage: 播放器活跃中，跳过ScanService状态变化处理');
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
    _playerStateCheckTimer?.cancel();
    _watchHistoryDebounceTimer?.cancel();
    _playerStateCheckTimer = null;
    
    // 重置播放器状态缓存，防止内存泄漏
    _cachedPlayerActiveState = false;
    _wasPlayerActive = false;
    
    _heroBannerIndexNotifier.dispose();
    
    // 移除监听器 - 使用初始化时保存的实例引用，避免在dispose中再次查找context
    try {
      _jfDebounceTimer?.cancel();
      _deactivateJellyfinLiveListening();
      if (_jellyfinProviderReadyListener != null) {
        try { _jellyfinProviderRef?.removeReadyListener(_jellyfinProviderReadyListener!); } catch (_) {}
        _jellyfinProviderReadyListener = null;
      }
      debugPrint('DashboardHomePage: JellyfinProvider监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除JellyfinProvider监听器失败: $e');
    }
    
    try {
      _emDebounceTimer?.cancel();
      _deactivateEmbyLiveListening();
      if (_embyProviderReadyListener != null) {
        try { _embyProviderRef?.removeReadyListener(_embyProviderReadyListener!); } catch (_) {}
        _embyProviderReadyListener = null;
      }
      debugPrint('DashboardHomePage: EmbyProvider监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除EmbyProvider监听器失败: $e');
    }
    
    try {
      _watchHistoryProviderRef?.removeListener(_onWatchHistoryStateChanged);
      debugPrint('DashboardHomePage: WatchHistoryProvider监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除WatchHistoryProvider监听器失败: $e');
    }
    
    try {
      _scanServiceRef?.removeListener(_onScanServiceStateChanged);
      debugPrint('DashboardHomePage: ScanService监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除ScanService监听器失败: $e');
    }
    
    try {
      _videoPlayerStateRef?.removeListener(_onVideoPlayerStateChanged);
      debugPrint('DashboardHomePage: VideoPlayerState监听器已移除');
    } catch (e) {
      debugPrint('DashboardHomePage: 移除VideoPlayerState监听器失败: $e');
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
      _dandanplayScrollController?.dispose();
      _dandanplayScrollController = null;
      _randomRecommendationsScrollController?.dispose();
      _randomRecommendationsScrollController = null;
      
      debugPrint('DashboardHomePage: ScrollController已销毁');
    } catch (e) {
      debugPrint('DashboardHomePage: 销毁ScrollController失败: $e');
    }
    
    debugPrint('DashboardHomePage: Widget销毁完成');
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final bool isIOS = Platform.isIOS;
    final homeSections = context.watch<HomeSectionsSettingsProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer2<JellyfinProvider, EmbyProvider>(
        builder: (context, jellyfinProvider, embyProvider, child) {
          final configuredSections = _buildConfiguredSections(
            isPhone: isPhone,
            isIOS: isIOS,
            sectionsProvider: homeSections,
          );
          return SingleChildScrollView(
            controller: _mainScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // 大海报推荐区域
                  _buildHeroBanner(isPhone: isPhone),
                  
                  SizedBox(height: isPhone ? 16 : 32),
                  ...configuredSections,

                  
                  // 底部间距
                  SizedBox(height: isPhone ? 30 : 50),
                ],
              ),
            );
        },
      ),
    );
}
}
