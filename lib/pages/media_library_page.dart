import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_model.dart'; // Needed for _fetchedAnimeDetails
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart'; // Needed for getAnimeDetails
import 'package:nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/widgets/transparent_page_route.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For image URL persistence
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/services/jellyfin_service.dart'; // 添加Jellyfin服务
import 'package:nipaplay/models/jellyfin_model.dart'; // 添加Jellyfin模型
import 'package:nipaplay/pages/jellyfin_detail_page.dart'; // 添加Jellyfin详情页面
import 'package:nipaplay/widgets/jellyfin_server_dialog.dart'; // 添加Jellyfin服务器设置对话框
import 'dart:io'; // 添加Platform导入
import 'dart:async'; // 添加异步支持
import 'package:nipaplay/providers/jellyfin_provider.dart'; // 确保此导入存在

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
  Map<int, String> _persistedImageUrls = {}; // Loaded from SharedPreferences
  final Map<int, BangumiAnime> _fetchedFullAnimeData = {}; // Freshly fetched in this session
  bool _isLoadingInitial = true; // For the initial list from history
  String? _error;
  // No longer a single _isLoading; initial load and background fetches are separate concerns.
  final ScrollController _gridScrollController = ScrollController();

  static const String _prefsKeyPrefix = 'media_library_image_url_';
  
  // Jellyfin相关状态
  List<JellyfinMediaItem> _jellyfinMediaItems = [];
  bool _isLoadingJellyfin = false;
  String? _jellyfinError;
  bool _isJellyfinConnected = false;
  Timer? _jellyfinRefreshTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialMediaLibraryData();
        _loadJellyfinData(); // 初始加载

        // 添加对JellyfinProvider的监听
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.addListener(_onJellyfinProviderChanged);
      }
    });
  }

  @override
  void dispose() {
    // 移除JellyfinProvider的监听器
    // 使用try-catch是一个好习惯，以防Provider在Widget之前被销毁
    try {
      if (mounted) { // 确保widget仍然挂载
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.removeListener(_onJellyfinProviderChanged);
      }
    } catch (e) {
      print("移除JellyfinProvider监听器时出错: $e");
    }

    _gridScrollController.dispose();
    _jellyfinRefreshTimer?.cancel();
    super.dispose();
  }

  // 当JellyfinProvider状态改变时调用
  void _onJellyfinProviderChanged() {
    if (mounted) {
      // 当JellyfinProvider通知更改时（例如连接状态、选择的库），
      // 重新加载Jellyfin数据。
      _loadJellyfinData();
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

    final Map<int, WatchHistoryItem> latestHistoryItemMap = {};
    for (var item in watchHistory) {
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
  
  // 加载Jellyfin数据
  Future<void> _loadJellyfinData() async {
    // 使用 Provider 的状态来决定是否加载，因为 Provider 是我们监听的源头
    // listen: false 因为我们是通过 addListener 手动监听，而不是在 build 方法中依赖它
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    final jellyfinService = JellyfinService.instance; // Service 仍然是获取媒体项的实际执行者

    // 根据Provider的状态来判断
    if (!jellyfinProvider.isConnected || jellyfinProvider.selectedLibraryIds.isEmpty) {
      if (mounted) {
        setState(() {
          _isJellyfinConnected = false; // 更新UI状态以反映Provider的状态
          _jellyfinMediaItems = [];
          _isLoadingJellyfin = false; // 确保停止加载指示器
          _jellyfinError = null; // 清除之前的错误
        });
      }
      return;
    }

    // 如果执行到这里，说明Provider已连接并且有选中的媒体库
    if (mounted) {
      setState(() {
        _isJellyfinConnected = true; // 确保UI状态与Provider一致
        _isLoadingJellyfin = true;
        _jellyfinError = null;
      });
    }

    try {
      // 使用Service获取数据。Service中的selectedLibraryIds应该已经被Provider更新过了。
      final mediaItems = await jellyfinService.getLatestMediaItems(limit: 200);

      if (mounted) {
        setState(() {
          _jellyfinMediaItems = mediaItems;
          _isLoadingJellyfin = false;
        });
      }

      _setupJellyfinRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _jellyfinError = e.toString();
          _isLoadingJellyfin = false;
          // 发生错误时，也可以考虑根据错误类型更新 _isJellyfinConnected 状态
        });
      }
    }
  }
  
  void _setupJellyfinRefreshTimer() {
    // 取消现有的定时器
    _jellyfinRefreshTimer?.cancel();
    
    // 每60分钟刷新一次
    _jellyfinRefreshTimer = Timer.periodic(const Duration(minutes: 60), (timer) {
      _loadJellyfinData();
    });
  }
  
  // 显示Jellyfin服务器设置对话框
  Future<void> _showJellyfinServerDialog() async {
    final result = await JellyfinServerDialog.show(context);
    
    if (result == true) {
      // 如果对话框返回true，表示已进行更改，需要刷新数据
      _loadJellyfinData();
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
    AnimeDetailPage.show(context, animeId).then((WatchHistoryItem? result) {
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
  
  // 导航到Jellyfin媒体详情页
  void _navigateToJellyfinDetail(String jellyfinId) {
    JellyfinDetailPage.show(context, jellyfinId).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        // 调用播放回调
        widget.onPlayEpisode?.call(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 需要调用super.build用于AutomaticKeepAliveClientMixin
    
    final List<Tab> tabs = [];
    final List<Widget> tabViews = [];

    // 始终包含本地媒体库
    tabs.add(const Tab(text: '媒体库'));
    tabViews.add(_buildLocalMediaLibrary());

    // 如果Jellyfin已连接，则添加Jellyfin标签页
    if (_isJellyfinConnected) {
      tabs.add(const Tab(text: 'Jellyfin'));
      tabViews.add(_buildJellyfinMediaLibrary());
    }
    
    return DefaultTabController(
      key: ValueKey<int>(tabs.length), // Add this key
      length: tabs.length, // 使用 tabs 列表的实际长度
      child: Column(
        children: [
          // 仅当有多个标签页时显示 TabBar，或者根据您的UI设计决定
          if (tabs.length > 1) 
            TabBar(
              tabs: tabs, // 使用构建好的 tabs 列表
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.blue,
            ),
          
          Expanded(
            child: TabBarView(
              children: tabViews, // 使用构建好的 tabViews 列表
            ),
          ),
        ],
      ),
    );
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
                  // 添加Jellyfin服务器按钮
                  if (!_isJellyfinConnected) // Only show if not connected
                    ElevatedButton.icon(
                      onPressed: _showJellyfinServerDialog,
                      icon: const Icon(Icons.cloud),
                      label: const Text('添加Jellyfin服务器'),
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
                    final useOptimizedRendering = index > 11;
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

                    return AnimeCard(
                      key: ValueKey(animeId ?? historyItem.filePath), 
                      name: nameToDisplay, 
                      imageUrl: imageUrlToDisplay,
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
                      final useOptimizedRendering = index > 11;
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

                      return AnimeCard(
                        key: ValueKey(animeId ?? historyItem.filePath), 
                        name: nameToDisplay, 
                        imageUrl: imageUrlToDisplay,
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
              child: FloatingActionButton(
                onPressed: _showJellyfinServerDialog,
                tooltip: '添加Jellyfin服务器',
                child: const Icon(Icons.cloud),
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildJellyfinMediaLibrary() {
    final jellyfinService = JellyfinService.instance;
    
    if (_isLoadingJellyfin) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_jellyfinError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载Jellyfin媒体库失败: $_jellyfinError', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadJellyfinData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_jellyfinMediaItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Jellyfin媒体库为空。\n请确保已选择媒体库并且包含内容。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showJellyfinServerDialog,
                icon: const Icon(Icons.settings),
                label: const Text('设置Jellyfin服务器'),
              ),
            ],
          ),
        ),
      );
    }
    
    // 显示Jellyfin媒体列表
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
              cacheExtent: 800,
              clipBehavior: Clip.hardEdge,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: _jellyfinMediaItems.length,
              itemBuilder: (context, index) {
                // 保留优化渲染逻辑，与本地媒体库一致
                final useOptimizedRendering = index > 11;
                final mediaItem = _jellyfinMediaItems[index];
                final imageUrl = mediaItem.imagePrimaryTag != null
                  ? jellyfinService.getImageUrl(mediaItem.id, width: 300)
                  : '';
                
                return AnimeCard(
                  key: ValueKey('jellyfin_${mediaItem.id}'), 
                  name: mediaItem.name, 
                  imageUrl: imageUrl,
                  onTap: () {
                    _navigateToJellyfinDetail(mediaItem.id);
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
                cacheExtent: 800,
                clipBehavior: Clip.hardEdge,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                itemCount: _jellyfinMediaItems.length,
                itemBuilder: (context, index) {
                  final mediaItem = _jellyfinMediaItems[index];
                  final imageUrl = mediaItem.imagePrimaryTag != null
                    ? jellyfinService.getImageUrl(mediaItem.id, width: 300)
                    : '';
                  
                  return AnimeCard(
                    key: ValueKey('jellyfin_${mediaItem.id}'), 
                    name: mediaItem.name, 
                    imageUrl: imageUrl,
                    onTap: () {
                      _navigateToJellyfinDetail(mediaItem.id);
                    },
                  );
                },
              ),
            ),
        ),
        
        // 右下角悬浮按钮，用于设置Jellyfin服务器
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _showJellyfinServerDialog,
            tooltip: '设置Jellyfin服务器',
            child: const Icon(Icons.settings),
          ),
        ),
      ],
    );
  }
}