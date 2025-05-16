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

// Define a callback type for when an episode is selected for playing
typedef OnPlayEpisodeCallback = void Function(WatchHistoryItem item);

class MediaLibraryPage extends StatefulWidget {
  final OnPlayEpisodeCallback? onPlayEpisode; // Add this callback

  const MediaLibraryPage({super.key, this.onPlayEpisode}); // Modify constructor

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  List<WatchHistoryItem> _uniqueLibraryItems = []; 
  Map<int, String> _persistedImageUrls = {}; // Loaded from SharedPreferences
  final Map<int, BangumiAnime> _fetchedFullAnimeData = {}; // Freshly fetched in this session
  bool _isLoadingInitial = true; // For the initial list from history
  String? _error;
  // No longer a single _isLoading; initial load and background fetches are separate concerns.

  static const String _prefsKeyPrefix = 'media_library_image_url_';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialMediaLibraryData();
      }
    });
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
      final watchHistory = historyProvider.history;

      if (watchHistory.isEmpty) {
        if (mounted) {
          setState(() {
            _uniqueLibraryItems = [];
            _isLoadingInitial = false;
          });
        }
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
      
      // Load persisted image URLs
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

      if (mounted) {
        setState(() {
          _uniqueLibraryItems = uniqueAnimeItemsFromHistory;
          _persistedImageUrls = loadedPersistedUrls; 
          _isLoadingInitial = false;
        });
        _fetchAndPersistFullDetailsInBackground();
      }
    } catch (e) {
      //debugPrint('[MediaLibraryPage] Error loading initial media library data: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingInitial = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitial) {
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
                onPressed: _loadInitialMediaLibraryData, // Changed to load initial data
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_uniqueLibraryItems.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '媒体库为空。\n观看过的动画将显示在这里。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    // 使用RepaintBoundary包装整个GridView，优化重绘
    return RepaintBoundary(
      child: GridView.builder(
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
    );
  }
} 