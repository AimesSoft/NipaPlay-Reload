import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_model.dart'; // Needed for _fetchedAnimeDetails
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart'; // Needed for getAnimeDetails
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/themed_anime_detail.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For image URL persistence
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/jellyfin_server_dialog.dart'; 
import 'dart:io'; 
import 'dart:async';
import 'dart:ui'; 
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/emby_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/media_server_selection_sheet.dart';

// Define a callback type for when an episode is selected for playing
typedef OnPlayEpisodeCallback = void Function(WatchHistoryItem item);

class MediaLibraryPage extends StatefulWidget {
  final OnPlayEpisodeCallback? onPlayEpisode; // Add this callback
  final bool jellyfinMode; // 是否为Jellyfin媒体库模式

  const MediaLibraryPage({
    super.key, 
    this.onPlayEpisode,
    this.jellyfinMode = false,
  }); // Modify constructor

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> with AutomaticKeepAliveClientMixin {
  List<WatchHistoryItem> _uniqueLibraryItems = []; 
  Map<int, String> _persistedImageUrls = {}; 
  final Map<int, BangumiAnime> _fetchedFullAnimeData = {}; 
  bool _isLoadingInitial = true; 
  String? _error;
  
  final ScrollController _gridScrollController = ScrollController();

  static const String _prefsKeyPrefix = 'media_library_image_url_';
  
  // Jellyfin相关状态
  // List<JellyfinMediaItem> _jellyfinMediaItems = []; // MOVED to JellyfinMediaLibraryView
  // bool _isLoadingJellyfin = false; // MOVED to JellyfinMediaLibraryView
  // String? _jellyfinError; // MOVED to JellyfinMediaLibraryView
  bool _isJellyfinConnected = false; // KEEP - to control tab visibility
  // Timer? _jellyfinRefreshTimer; // MOVED to JellyfinMediaLibraryView

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialMediaLibraryData();
        // _loadJellyfinData(); // REMOVED - JellyfinMediaLibraryView handles its own loading

        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        _isJellyfinConnected = jellyfinProvider.isConnected; // Initialize
        jellyfinProvider.addListener(_onJellyfinProviderChanged);
      }
    });
  }

  @override
  void dispose() {
    try {
      if (mounted) { 
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.removeListener(_onJellyfinProviderChanged);
      }
    } catch (e) {
      // ignore: avoid_print
      print("移除JellyfinProvider监听器时出错: $e");
    }

    _gridScrollController.dispose();
    // _jellyfinRefreshTimer?.cancel(); // REMOVED
    super.dispose();
  }

  void _onJellyfinProviderChanged() {
    if (mounted) {
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (_isJellyfinConnected != jellyfinProvider.isConnected) {
        setState(() {
          _isJellyfinConnected = jellyfinProvider.isConnected;
        });
      }
      // _loadJellyfinData(); // REMOVED - JellyfinMediaLibraryView handles its own loading
    }
  }

  Future<void> _processAndSortHistory(List<WatchHistoryItem> watchHistory) async {
    if (!mounted) return;

    if (watchHistory.isEmpty) {
      setState(() {
        _uniqueLibraryItems = [];
        _isLoadingInitial = false; 
      });
      return;
    }

    // 过滤掉Jellyfin和Emby媒体项（使用jellyfin://和emby://协议的项目）
    // 让它们只出现在专门的流媒体库标签页中
    final filteredHistory = watchHistory.where((item) => 
      !item.filePath.startsWith('jellyfin://') &&
      !item.filePath.startsWith('emby://')
    ).toList();

    final Map<int, WatchHistoryItem> latestHistoryItemMap = {};
    for (var item in filteredHistory) {
      if (item.animeId != null) {
        if (latestHistoryItemMap.containsKey(item.animeId!)) {
          if (item.lastWatchTime.isAfter(latestHistoryItemMap[item.animeId!]!.lastWatchTime)) {
            latestHistoryItemMap[item.animeId!] = item;
          }
        } else {
          latestHistoryItemMap[item.animeId!] = item;
        }
      }
    }
    final uniqueAnimeItemsFromHistory = latestHistoryItemMap.values.toList();
    uniqueAnimeItemsFromHistory.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

    Map<int, String> loadedPersistedUrls = {};
    final prefs = await SharedPreferences.getInstance();
    for (var item in uniqueAnimeItemsFromHistory) {
      if (item.animeId != null) {
        String? persistedUrl = prefs.getString('$_prefsKeyPrefix${item.animeId}');
        if (persistedUrl != null && persistedUrl.isNotEmpty) {
          loadedPersistedUrls[item.animeId!] = persistedUrl;
        }
      }
    }

    setState(() {
      _uniqueLibraryItems = uniqueAnimeItemsFromHistory;
      _persistedImageUrls = loadedPersistedUrls;
      _isLoadingInitial = false; 
    });
    _fetchAndPersistFullDetailsInBackground(); 
  }

  Future<void> _loadInitialMediaLibraryData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitial = true;
      _error = null;
    });

    try {
      final historyProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!historyProvider.isLoaded && !historyProvider.isLoading) {
        await historyProvider.loadHistory(); 
      }
      
      if (historyProvider.isLoaded) { // If loaded, process immediately
          await _processAndSortHistory(historyProvider.history);
      }
      // If not loaded yet, the Consumer will pick it up once loaded.
      // However, to prevent showing loading indefinitely if historyProvider never loads or is empty,
      // we might need to adjust _isLoadingInitial in the Consumer as well.
      // For now, this relies on historyProvider becoming loaded.

    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingInitial = false;
        });
      }
    }
  }
  
  Future<void> _showJellyfinServerDialog() async {
    final result = await JellyfinServerDialog.show(context);
    if (result == true && mounted) {
      // 可以在这里添加刷新逻辑
    }
  }

  Future<void> _showServerSelectionDialog() async {
    final result = await MediaServerSelectionSheet.show(context);

    if (result != null && mounted) {
      if (result == 'jellyfin') {
        await _showJellyfinServerDialog();
      } else if (result == 'emby') {
        await _showEmbyServerDialog();
      }
    }
  }

  Future<void> _showEmbyServerDialog() async {
    final result = await EmbyServerDialog.show(context);
    if (result == true && mounted) {
      // 可以在这里添加刷新逻辑
    }
  }

  Future<void> _fetchAndPersistFullDetailsInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    // 一次只加载最多3个番剧的详情，避免过多并行请求
    List<Future> pendingRequests = [];
    int maxConcurrentRequests = 3;
    int batchSize = 0; // 已处理批次数，用于延迟处理
    
    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null) { 
        // 只有在以下情况才获取详情：
        // 1. 本次会话中未获取过
        // 2. 没有缓存的图片URL
        if (_fetchedFullAnimeData.containsKey(historyItem.animeId!) || 
            _persistedImageUrls.containsKey(historyItem.animeId!)) {
            continue;
        }
        
        // 每批次间隔200毫秒，避免频繁UI更新
        if (batchSize > 0 && batchSize % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
        batchSize++;
        
        // 创建获取详情的异步函数
        Future<void> fetchDetailForItem() async {
          try {
            final animeDetail = await BangumiService.instance.getAnimeDetails(historyItem.animeId!);
            if (mounted) {
              setState(() {
                _fetchedFullAnimeData[historyItem.animeId!] = animeDetail;
              });
              if (animeDetail.imageUrl.isNotEmpty) {
                await prefs.setString('$_prefsKeyPrefix${historyItem.animeId!}', animeDetail.imageUrl);
                if (mounted) {
                  setState(() {
                    _persistedImageUrls[historyItem.animeId!] = animeDetail.imageUrl;
                  });
                }
              } else {
                // If fetched URL is empty, remove potentially stale persisted URL
                await prefs.remove('$_prefsKeyPrefix${historyItem.animeId!}');
                // Also update UI state if it was relying on a persisted URL that's now invalid
                if(mounted && _persistedImageUrls.containsKey(historyItem.animeId!)){
                  setState(() {
                    _persistedImageUrls.remove(historyItem.animeId!);
                  });
                }
              }
            }
          } catch (e) {
            //debugPrint('[MediaLibraryPage] Background fetch error for animeId ${historyItem.animeId}: $e');
          }
        }
        
        // 限制并发请求数量
        if (pendingRequests.length >= maxConcurrentRequests) {
          // 等待其中一个请求完成
          await Future.any(pendingRequests);
          // 监控每个请求，移除已完成的
          // 由于无法直接检查Future是否完成，需要创建新的请求列表
          pendingRequests = [...pendingRequests];
          // 移除一个请求，确保有空间添加新请求
          pendingRequests.removeAt(0);
        }
        
        // 添加新请求
        final request = fetchDetailForItem();
        pendingRequests.add(request);
      }
    }
    
    // 等待所有剩余请求完成
    if (pendingRequests.isNotEmpty) {
      await Future.wait(pendingRequests);
    }
  }

  // 在用户点击番剧卡片时加载详情
  Future<void> _preloadAnimeDetail(int animeId) async {
    // 如果已经在本会话中加载过，就不再重复加载
    if (_fetchedFullAnimeData.containsKey(animeId)) {
      return;
    }
    
    try {
      final animeDetail = await BangumiService.instance.getAnimeDetails(animeId);
      if (mounted) {
        setState(() {
          _fetchedFullAnimeData[animeId] = animeDetail;
        });
      }
    } catch (e) {
      // 加载失败时不显示错误，让详情页处理错误
      //debugPrint('[MediaLibraryPage] Failed to preload anime detail: $e');
    }
  }

  void _navigateToAnimeDetail(int animeId) {
    // 直接显示详情页，不等待预加载完成
    ThemedAnimeDetail.show(context, animeId).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        // filePath is from WatchHistoryItem, which should be non-empty if an episode was chosen
        
        // Instead of initializing player here, call the callback
        widget.onPlayEpisode?.call(result);
      }
    });
    
    // 在后台尝试预加载详情数据，为下次查看做准备
    if (!_fetchedFullAnimeData.containsKey(animeId)) {
      _preloadAnimeDetail(animeId);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); 
    
    // 现在MediaLibraryPage只显示本地媒体库，移除Jellyfin标签页
    return _buildLocalMediaLibrary();
  }
  
  Widget _buildLocalMediaLibrary() {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        
        if (!historyProvider.isLoaded && _isLoadingInitial) {
            // Still relying on _loadInitialMediaLibraryData to kick off loading
            // and for _isLoadingInitial to be true initially.
            // This condition handles the very first load.
             return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
            );
        }

        // If provider is loaded or becomes loaded, process its history.
        // This ensures that updates from the provider trigger a re-sort.
        // This ensures that updates from the provider trigger a re-sort.
        if (historyProvider.isLoaded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                    // Check if the data is actually different or if _isLoadingInitial is true
                    // to avoid unnecessary processing if _processAndSortHistory is heavy.
                    // For simplicity, we call it; _processAndSortHistory's setState handles actual UI update.
                    _processAndSortHistory(historyProvider.history);
                }
            });
        }

        // UI rendering logic based on _isLoadingInitial, _error, _uniqueLibraryItems
        if (_isLoadingInitial) {
          // This will be true until _processAndSortHistory sets it to false.
          return const SizedBox(
            height: 200, 
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (_error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('加载媒体库失败: $_error', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadInitialMediaLibraryData,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        if (_uniqueLibraryItems.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '媒体库为空。\n观看过的动画将显示在这里。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  // 添加媒体服务器按钮 - 使用毛玻璃效果
                  if (!_isJellyfinConnected) // Only show if not connected
                    _buildGlassButton(
                      onPressed: _showServerSelectionDialog,
                      icon: Icons.cloud,
                      label: '添加媒体服务器',
                    ),
                ],
              ),
            ),
          );
        }

        // Using RepaintBoundary for the GridView
        return Stack(
          children: [
            RepaintBoundary(
              child: Platform.isAndroid || Platform.isIOS 
              ? GridView.builder(
                  controller: _gridScrollController,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 150, 
                    childAspectRatio: 7/12,   
                    crossAxisSpacing: 8,      
                    mainAxisSpacing: 8,       
                  ),
                  padding: const EdgeInsets.all(0),
                  // 增加cacheExtent以提升滚动流畅度
                  cacheExtent: 800, // 提高预缓存距离
                  // 优化GridView性能
                  clipBehavior: Clip.hardEdge,
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  // 添加更多GridView性能优化参数
                  addAutomaticKeepAlives: false, // 避免保持所有项目活动
                  addRepaintBoundaries: true, // 为每个项目添加绘制边界
                  // 只渲染两行之后的项目，控制同时显示的项目数量
                  // 通过key和index控制垂直方向的显示
                  itemCount: _uniqueLibraryItems.length,
                  itemBuilder: (context, index) {
                    // 判断是否超出当前屏幕过多，实现按需渲染
                    // 前12个项目(约前两行)使用完整渲染，后面的使用优化渲染
                    // final useOptimizedRendering = index > 11; // 暂未使用
                    final historyItem = _uniqueLibraryItems[index];
                    final animeId = historyItem.animeId;

                    String imageUrlToDisplay = historyItem.thumbnailPath ?? '';
                    String nameToDisplay = historyItem.animeName.isNotEmpty 
                        ? historyItem.animeName 
                        : (historyItem.episodeTitle ?? '未知动画');

                    if (animeId != null) {
                        if (_fetchedFullAnimeData.containsKey(animeId)) {
                            final fetchedData = _fetchedFullAnimeData[animeId]!;
                            if (fetchedData.imageUrl.isNotEmpty) {
                                imageUrlToDisplay = fetchedData.imageUrl;
                            }
                            if (fetchedData.nameCn.isNotEmpty) {
                                nameToDisplay = fetchedData.nameCn;
                            } else if (fetchedData.name.isNotEmpty) {
                                nameToDisplay = fetchedData.name;
                            }
                        } else if (_persistedImageUrls.containsKey(animeId)) {
                            imageUrlToDisplay = _persistedImageUrls[animeId]!;
                            // Name remains from historyItem until full details are fetched in this session
                        }
                    }

                    return _buildAnimeCard(
                      key: ValueKey(animeId ?? historyItem.filePath), 
                      name: nameToDisplay, 
                      imageUrl: imageUrlToDisplay,
                      source: AnimeCard.getSourceFromFilePath(historyItem.filePath),
                      rating: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                          ? _fetchedFullAnimeData[animeId]!.rating 
                          : null,
                      ratingDetails: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                          ? _fetchedFullAnimeData[animeId]!.ratingDetails 
                          : null,
                      onTap: () {
                        if (animeId != null) {
                          _navigateToAnimeDetail(animeId);
                        } else {
                          BlurSnackBar.show(context, '无法打开详情，动画ID未知');
                        }
                      },
                    );
                  },
                )
              : Scrollbar(
                  controller: _gridScrollController,
                  thickness: 4,
                  radius: const Radius.circular(2),
                  child: GridView.builder(
                    controller: _gridScrollController,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 150, 
                      childAspectRatio: 7/12,   
                      crossAxisSpacing: 8,      
                      mainAxisSpacing: 8,       
                    ),
                    padding: const EdgeInsets.all(0),
                    // 增加cacheExtent以提升滚动流畅度
                    cacheExtent: 800, // 提高预缓存距离
                    // 优化GridView性能
                    clipBehavior: Clip.hardEdge,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    // 添加更多GridView性能优化参数
                    addAutomaticKeepAlives: false, // 避免保持所有项目活动
                    addRepaintBoundaries: true, // 为每个项目添加绘制边界
                    // 只渲染两行之后的项目，控制同时显示的项目数量
                    // 通过key和index控制垂直方向的显示
                    itemCount: _uniqueLibraryItems.length,
                    itemBuilder: (context, index) {
                      // 判断是否超出当前屏幕过多，实现按需渲染
                      // 前12个项目(约前两行)使用完整渲染，后面的使用优化渲染
                      // final useOptimizedRendering = index > 11; // 暂未使用
                      final historyItem = _uniqueLibraryItems[index];
                      final animeId = historyItem.animeId;

                      String imageUrlToDisplay = historyItem.thumbnailPath ?? '';
                      String nameToDisplay = historyItem.animeName.isNotEmpty 
                          ? historyItem.animeName 
                          : (historyItem.episodeTitle ?? '未知动画');

                      if (animeId != null) {
                          if (_fetchedFullAnimeData.containsKey(animeId)) {
                              final fetchedData = _fetchedFullAnimeData[animeId]!;
                              if (fetchedData.imageUrl.isNotEmpty) {
                                  imageUrlToDisplay = fetchedData.imageUrl;
                              }
                              if (fetchedData.nameCn.isNotEmpty) {
                                  nameToDisplay = fetchedData.nameCn;
                              } else if (fetchedData.name.isNotEmpty) {
                                  nameToDisplay = fetchedData.name;
                              }
                          } else if (_persistedImageUrls.containsKey(animeId)) {
                              imageUrlToDisplay = _persistedImageUrls[animeId]!;
                              // Name remains from historyItem until full details are fetched in this session
                          }
                      }

                      return _buildAnimeCard(
                        key: ValueKey(animeId ?? historyItem.filePath), 
                        name: nameToDisplay, 
                        imageUrl: imageUrlToDisplay,
                        source: AnimeCard.getSourceFromFilePath(historyItem.filePath),
                        rating: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                            ? _fetchedFullAnimeData[animeId]!.rating 
                            : null,
                        ratingDetails: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                            ? _fetchedFullAnimeData[animeId]!.ratingDetails 
                            : null,
                        onTap: () {
                          if (animeId != null) {
                            _navigateToAnimeDetail(animeId);
                          } else {
                            BlurSnackBar.show(context, '无法打开详情，动画ID未知');
                          }
                        },
                      );
                    },
                  ),
                ),
            ),
            
            // 右下角悬浮按钮，用于添加Jellyfin服务器
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionGlassButton(
                iconData: Ionicons.cloud_outline,
                onPressed: _showServerSelectionDialog,
                description: '添加媒体服务器\n连接到Jellyfin或Emby服务器\n享受云端媒体库内容',
              ),
            ),
          ],
        );
      },
    );
  }

  // 根据主题选择合适的AnimeCard组件
  Widget _buildAnimeCard({
    required Key key,
    required String name,
    required String imageUrl,
    required String? source,
    required double? rating,
    required Map<String, dynamic>? ratingDetails,
    required VoidCallback onTap,
  }) {
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    if (uiThemeProvider.isFluentUITheme) {
      // 使用 FluentUI 版本
      return FluentAnimeCard(
        key: key,
        name: name,
        imageUrl: imageUrl,
        source: source,
        rating: rating,
        ratingDetails: ratingDetails,
        onTap: onTap,
      );
    } else {
      // 使用 Material 版本（保持原有逻辑）
      return AnimeCard(
        key: key,
        name: name,
        imageUrl: imageUrl,
        source: source,
        rating: rating,
        ratingDetails: ratingDetails,
        onTap: onTap,
      );
    }
  }

  Widget _buildGlassButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isHovered ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(isHovered ? 0.4 : 0.2),
                    width: 0.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}