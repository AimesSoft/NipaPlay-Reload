import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import '../utils/video_player_state.dart';
import '../widgets/loading_overlay.dart';
import '../utils/tab_change_notifier.dart';
import '../widgets/loading_placeholder.dart';
import '../providers/watch_history_provider.dart';
import '../providers/appearance_settings_provider.dart';
import '../pages/media_library_page.dart';
import '../widgets/library_management_tab.dart';
import 'package:nipaplay/services/scan_service.dart';
import '../widgets/blur_snackbar.dart';
import '../widgets/history_all_modal.dart';
import '../widgets/switchable_view.dart';
import 'package:nipaplay/main.dart';
import '../services/jellyfin_service.dart';
import '../services/emby_service.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/widgets/jellyfin_media_library_view.dart';
import 'package:nipaplay/widgets/emby_media_library_view.dart';

// Custom ScrollBehavior for NoScrollbarBehavior is removed as NestedScrollView handles scrolling differently.

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Using a Material widget to ensure proper theming and background.
    // Changed color to Colors.transparent to remove the black background.
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent, // Changed from Theme.of(context).scaffoldBackgroundColor
        elevation: overlapsContent ? 4.0 : 0.0, // Add elevation when content overlaps (sticks)
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}

class _AnimePageState extends State<AnimePage> with WidgetsBindingObserver {
  bool _loadingVideo = false;
  List<String> _loadingMessages = ['正在初始化播放器...'];
  VideoPlayerState? _videoPlayerState;
  final ScrollController _mainPageScrollController = ScrollController(); // Used for NestedScrollView
  final ScrollController _watchHistoryListScrollController = ScrollController();
  
  // 仅保留当前标签页索引用于初始化_MediaLibraryTabs
  final int _currentTabIndex = 0;

  int _mediaLibraryVersion = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
    _setupThumbnailUpdateListener();
  }

  void _setupThumbnailUpdateListener() {
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.addThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {
      //debugPrint('设置缩略图更新监听器时出错: $e');
    }
  }

  void _onThumbnailUpdated() {
    if (!mounted) return;
    // 不再清理所有图片缓存，避免影响番剧卡片的封面显示
    // 只触发UI重建来显示新的缩略图
    setState(() {
      // 触发UI重建，让新的缩略图能够显示
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.removeThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {}
    _mainPageScrollController.dispose();
    _watchHistoryListScrollController.dispose();
    super.dispose();
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    debugPrint('[AnimePage] _onWatchHistoryItemTap: Received item: $item');
    debugPrint('[AnimePage] item.animeName: ${item.animeName}');
    debugPrint('[AnimePage] item.filePath: ${item.filePath}');
    debugPrint('[AnimePage] item.episodeTitle: ${item.episodeTitle}');
  
    bool tabChangeLogicExecuted = false; // Flag to ensure one-shot execution

    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;
    
    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      // 对于网络URL和流媒体协议，跳过本地文件检查
      fileExists = true;
      debugPrint('[AnimePage] 检测到流媒体URL，跳过文件存在性检查: ${item.filePath}');
      
      // 如果是Jellyfin协议，需要获取实际的HTTP流媒体URL
      if (isJellyfinProtocol) {
        try {
          // 从jellyfin://协议URL中提取itemId
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          debugPrint('[AnimePage] 解析Jellyfin ID: $jellyfinId');
          
          // 使用JellyfinService获取实际的HTTP流媒体URL
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
            debugPrint('[AnimePage] 获取到Jellyfin流媒体URL: $actualPlayUrl');
          } else {
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          debugPrint('[AnimePage] 获取Jellyfin流媒体URL失败: $e');
          BlurSnackBar.show(context, '获取流媒体URL失败: $e');
          return;
        }
      }
      
      // 如果是Emby协议，需要获取实际的HTTP流媒体URL
      if (isEmbyProtocol) {
        try {
          // 从emby://协议URL中提取itemId
          final embyId = item.filePath.replaceFirst('emby://', '');
          debugPrint('[AnimePage] 解析Emby ID: $embyId');
          
          // 使用EmbyService获取实际的HTTP流媒体URL
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = embyService.getStreamUrl(embyId);
            debugPrint('[AnimePage] 获取到Emby流媒体URL: $actualPlayUrl');
          } else {
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          debugPrint('[AnimePage] 获取Emby流媒体URL失败: $e');
          BlurSnackBar.show(context, '获取流媒体URL失败: $e');
          return;
        }
      }
    } else {
      // 对于本地文件进行存在性检查
      final videoFile = File(item.filePath);
      fileExists = videoFile.existsSync();
      
      // 在iOS系统上，有时文件路径可能会有/private前缀，或者没有这个前缀，尝试两种路径
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath;
        if (filePath.startsWith('/private')) {
          // 尝试去掉/private前缀
          altPath = filePath.replaceFirst('/private', '');
        } else {
          // 尝试添加/private前缀
          altPath = '/private$filePath';
        }
        
        final File altFile = File(altPath);
        fileExists = altFile.existsSync();
        if (fileExists) {
          // 如果找到了文件，更新路径
          filePath = altPath;
          // 创建新的项目以便传递更新后的路径
          item = WatchHistoryItem(
            filePath: filePath,
            animeName: item.animeName,
            episodeTitle: item.episodeTitle,
            episodeId: item.episodeId,
            animeId: item.animeId,
            watchProgress: item.watchProgress,
            lastPosition: item.lastPosition,
            duration: item.duration,
            lastWatchTime: item.lastWatchTime,
            thumbnailPath: item.thumbnailPath,
            isFromScan: item.isFromScan,
          );
        }
      }
    }
    
    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    if (_videoPlayerState == null) {
      try {
        _videoPlayerState =
            Provider.of<VideoPlayerState>(context, listen: false);
      } catch (e) {
        BlurSnackBar.show(context, '播放器初始化失败，请重试');
        return;
      }
    }

    final videoState = _videoPlayerState!;
    setState(() {
      _loadingVideo = true;
      _loadingMessages = ['正在初始化播放器...'];
    });

    late final VoidCallback statusListener;
    late final VoidCallback playbackFinishListener;

    statusListener = () {
      debugPrint('[AnimePage] statusListener triggered. Player status: ${videoState.status}, mounted: $mounted, tabChangeLogicExecuted: $tabChangeLogicExecuted');
      if (!mounted) {
        debugPrint('[AnimePage] statusListener: Not mounted, removing listener.');
        videoState.removeListener(statusListener);
        return;
      }
      if (videoState.statusMessages.isNotEmpty &&
          videoState.statusMessages.last != _loadingMessages.last) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _loadingMessages = List<String>.from(videoState.statusMessages);
            });
          }
        });
      }
      if ((videoState.status == PlayerStatus.ready ||
          videoState.status == PlayerStatus.playing) && !tabChangeLogicExecuted) {
        tabChangeLogicExecuted = true; // Set flag immediately
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          debugPrint('[AnimePage] statusListener (postFrame): Executing tab change and UI update.');
          if (mounted) {
            setState(() {
              _loadingVideo = false;
            });
            debugPrint('[AnimePage] statusListener (postFrame): Calling changeTab(0).');
            try {
              MainPageState? mainPageState = MainPageState.of(context);
              if (mainPageState != null && mainPageState.globalTabController != null) {
                if (mainPageState.globalTabController!.index != 0) {
                  mainPageState.globalTabController!.animateTo(0);
                  debugPrint('[AnimePage] statusListener (postFrame): Directly called mainPageState.globalTabController.animateTo(0)');
                } else {
                  debugPrint('[AnimePage] statusListener (postFrame): mainPageState.globalTabController is already at index 0.');
                }
              } else {
                debugPrint('[AnimePage] statusListener (postFrame): Could not find MainPageState or globalTabController. Falling back to TabChangeNotifier.');
                // Fallback if direct access fails for some reason
                Provider.of<TabChangeNotifier>(context, listen: false).changeTab(0);
              }
            } catch (e) {
              debugPrint("[AnimePage] statusListener (postFrame): Error directly changing tab or using fallback: $e");
            }
          }
          debugPrint('[AnimePage] statusListener (postFrame): Removing self (statusListener).');
          videoState.removeListener(statusListener);
        });
      } else if (tabChangeLogicExecuted && (videoState.status == PlayerStatus.ready || videoState.status == PlayerStatus.playing)) {
        debugPrint('[AnimePage] statusListener: Player ready/playing BUT tabChangeLogicExecuted is true. Ensuring listener is removed.');
        videoState.removeListener(statusListener);
      }
    };

    playbackFinishListener = () {
      if (!mounted) {
        videoState.removeListener(playbackFinishListener);
        return;
      }
      if (videoState.status == PlayerStatus.paused &&
          videoState.progress > 0.9) {
        videoState.removeListener(playbackFinishListener);
        final provider = context.read<WatchHistoryProvider>();
        provider.refresh();
      }
    };

    videoState.addListener(statusListener);
    videoState.addListener(playbackFinishListener);
    debugPrint('[AnimePage] _onWatchHistoryItemTap: Added statusListener and playbackFinishListener. Calling initializePlayer.');
    
    // 根据是否是流媒体协议决定传递参数
    if ((isJellyfinProtocol || isEmbyProtocol) && actualPlayUrl != null) {
      debugPrint('[AnimePage] 使用流媒体URL播放: $actualPlayUrl');
      videoState.initializePlayer(item.filePath, historyItem: item, actualPlayUrl: actualPlayUrl);
    } else {
      videoState.initializePlayer(item.filePath, historyItem: item);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        final isLoadingHistory = historyProvider.isLoading;

        return Builder(
          builder: (context) {
            final scanService = Provider.of<ScanService>(context);
            if (scanService.scanJustCompleted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  incrementMediaLibraryVersion();
                  try {
                    Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
                    debugPrint("WatchHistoryProvider refreshed from AnimePage due to scan or folder event.");
                  } catch (e) {
                    debugPrint("Error refreshing WatchHistoryProvider from AnimePage: $e");
                  }
                  scanService.acknowledgeScanCompleted();
                }
              });
            }

            // 移除DefaultTabController，直接使用Stack
            return Stack(
              children: [
                NestedScrollView(
                  controller: _mainPageScrollController,
                  headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 24, left: 16.0, right: 16.0),
                          child: RepaintBoundary(
                            child: Text("观看记录",
                                style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 180,
                          child: RepaintBoundary(
                            child: isLoadingHistory && history.isEmpty
                                ? const Center(child: CircularProgressIndicator())
                                : history.isEmpty
                                    ? _buildEmptyState(
                                        message: "暂无观看记录，已扫描的视频可在媒体库查看")
                                    : _buildWatchHistoryList(history),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text("媒体内容",
                              style: TextStyle(
                                  fontSize: 28,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    ];
                  },
                  body: _MediaLibraryTabs(
                    initialIndex: _currentTabIndex,
                    onPlayEpisode: _onWatchHistoryItemTap,
                    mediaLibraryVersion: _mediaLibraryVersion,
                  ),
                ),
                if (_loadingVideo)
                  Positioned.fill(
                    child: LoadingOverlay(messages: _loadingMessages),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState({String message = "暂无观看记录"}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.history,
            color: Colors.white38,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            message, // Use the message parameter
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchHistoryList(List<WatchHistoryItem> history) {
    // 过滤出有效的观看记录（持续时间大于0）
    final validHistoryItems = history.where((item) => item.duration > 0).toList();
    
    if (validHistoryItems.isEmpty) {
      return _buildEmptyState(message: "暂无观看记录，已扫描的视频可在媒体库查看");
    }

    // 确定哪个是最新更新的记录
    String? latestUpdatedPath;
    DateTime latestTime = DateTime(2000);
    for (var item in validHistoryItems) {
      if (item.lastWatchTime.isAfter(latestTime)) {
        latestTime = item.lastWatchTime;
        latestUpdatedPath = item.filePath;
      }
    }
    
    // 计算屏幕能显示的卡片数量（每个卡片宽度为150+16=166像素）
    final screenWidth = MediaQuery.of(context).size.width;
    const cardWidth = 166.0; // 卡片宽度 + 右侧padding
    // 现在最多显示计算得到的卡片数量，不再保留一个位置给"查看更多"按钮
    final visibleCards = (screenWidth / cardWidth).floor();
    
    // 决定是否需要"查看更多"按钮（现在使用固定宽度）
    final showViewMoreButton = validHistoryItems.length > visibleCards + 2;
    
    // The number of items shown in the list
    final displayItemCount = showViewMoreButton 
        ? visibleCards + 2  // 如果显示"查看更多"按钮，则显示比屏幕可容纳多两张卡片
        : validHistoryItems.length;  // 否则显示所有历史记录
    
    // 创建ListView
    ListView historyListView = ListView.builder(
      key: const PageStorageKey<String>('watch_history_list'),
      controller: _watchHistoryListScrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: showViewMoreButton 
          ? displayItemCount + 1  // 实际显示的卡片数量 + 1个"查看更多"按钮
          : validHistoryItems.length, // 如果历史记录较少，显示全部
      itemBuilder: (context, index) {
        // 检查是否是"查看更多"按钮的位置（现在应该始终是最后一个位置）
        if (showViewMoreButton && index == displayItemCount) {
          // 使用固定宽度的"查看更多"按钮，与卡片相同宽度
          const moreButtonWidth = 150.0; // 与卡片相同宽度
          
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: moreButtonWidth,
              child: GestureDetector(
                onTap: () => _showAllHistory(validHistoryItems),
                child: GlassmorphicContainer(
                  width: moreButtonWidth,
                  height: 180,
                  borderRadius: 10,
                  blur: 20,
                  border: 1.5,
                  linearGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.1),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                  borderGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.5),
                      Colors.white.withOpacity(0.5),
                    ],
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.more_horiz, color: Colors.white, size: 32),
                        SizedBox(height: 8),
                        Text(
                          "查看更多",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // 正常的历史记录项
        // 确保索引在有效范围内
        if (index < validHistoryItems.length) {
          final item = validHistoryItems[index];
          final isLatestUpdated = item.filePath == latestUpdatedPath;
          
          return Padding(
            key: ValueKey('${item.filePath}_${item.lastWatchTime.millisecondsSinceEpoch}'),
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => _onWatchHistoryItemTap(item),
              child: _buildHistoryCard(item, isLatestUpdated),
            ),
          );
        }
        
        // 如果索引无效，返回一个空的容器（实际上不应该发生）
        return const SizedBox.shrink();
      },
    );

    // 添加鼠标拖动功能的包装器
    Widget draggableHistoryList = _MouseDragScrollWrapper(
      scrollController: _watchHistoryListScrollController,
      child: historyListView,
    );

    // 根据平台决定是否使用Scrollbar
    if (Platform.isAndroid || Platform.isIOS) {
      return draggableHistoryList; // 移动平台不显示滚动条
    } else {
      // 创建适用于桌面平台的Scrollbar
      return Scrollbar(
        controller: _watchHistoryListScrollController,
        radius: const Radius.circular(2),
        thickness: 4, 
        thumbVisibility: false,
        child: draggableHistoryList,
      );
    }
  }

  Widget _buildHistoryCard(WatchHistoryItem item, bool isLatestUpdated) {
    return RepaintBoundary(
      child: SizedBox(
        width: 150,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 150,
            height: 170,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // 底层：模糊的缩略图背景
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 20,
                      sigmaY: 20,
                    ),
                    child: _getVideoThumbnail(item, isLatestUpdated),
                  ),
                ),
                
                // 中间层：半透明遮罩，提高可读性
                Positioned.fill(
                  child: Container(
                    color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                  ),
                ),
                
                // 顶层：内容
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 清晰的缩略图部分
                    SizedBox(
                      height: 90,
                      width: double.infinity,
                      child: _getVideoThumbnail(item, isLatestUpdated),
                    ),
                    
                    // 进度条
                    LinearProgressIndicator(
                      value: item.watchProgress,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.secondary,
                      ),
                      minHeight: 2,
                    ),
                    
                    // 标题和信息部分
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 显示动画名称，如果没有则显示文件名
                          Text(
                            item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // 显示集数标题，如果没有则显示文件名
                          Text(
                            item.episodeTitle ?? '未知集数',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                color: Theme.of(context).colorScheme.secondary,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(
                                    Duration(milliseconds: item.lastPosition)),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.secondary,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                " / ${_formatDuration(Duration(milliseconds: item.duration))}",
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item, bool isLatestUpdated) {
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        // 异步读取缩略图文件
        return FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // 加载中动画，和新番图片一致
              return const LoadingPlaceholder(
                  width: double.infinity, height: 90, borderRadius: 10);
            }
            if (snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.data == null) {
              return _buildDefaultThumbnail();
            }
            try {
              return Image.memory(
                snapshot.data!,
                key: isLatestUpdated
                    ? UniqueKey()
                    : ValueKey(item.thumbnailPath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultThumbnail();
                },
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

  // 默认缩略图
  Widget _buildDefaultThumbnail() {
    return Container(
      color: const Color.fromARGB(255, 77, 77, 77),
      child: const Center(
        child: Icon(Icons.video_library, color: Colors.white30, size: 32),
      ),
    );
  }

  void incrementMediaLibraryVersion() {
    if (mounted) {
      setState(() {
        _mediaLibraryVersion++;
      });
    }
  }
  
  // 显示所有历史记录的对话框
  void _showAllHistory(List<WatchHistoryItem> allHistory) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => HistoryAllModal(
        history: allHistory,
        onItemTap: _onWatchHistoryItemTap,
      ),
    );
  }
}

// 在文件末尾添加新的类用于管理媒体库标签页
class _MediaLibraryTabs extends StatefulWidget {
  final int initialIndex;
  final ValueChanged<WatchHistoryItem> onPlayEpisode;
  final int mediaLibraryVersion;

  const _MediaLibraryTabs({
    this.initialIndex = 0,
    required this.onPlayEpisode,
    required this.mediaLibraryVersion,
  });

  @override
  State<_MediaLibraryTabs> createState() => _MediaLibraryTabsState();
}

class _MediaLibraryTabsState extends State<_MediaLibraryTabs> with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  bool _isJellyfinConnected = false;
  bool _isEmbyConnected = false;
  
  // 动态计算标签页数量
  int get _tabCount {
    int count = 2; // 基础标签: 媒体库, 库管理
    if (_isJellyfinConnected) count++;
    if (_isEmbyConnected) count++;
    return count;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _checkConnectionStates();
    _tabController = TabController(
      length: _tabCount, 
      vsync: this, 
      initialIndex: _currentIndex
    );
    _tabController.addListener(_handleTabChange);
    
    print('_MediaLibraryTabs创建TabController：动态长度${_tabController.length}');
  }

  void _checkConnectionStates() {
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    _isJellyfinConnected = jellyfinProvider.isConnected;
    _isEmbyConnected = embyProvider.isConnected;
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) return;
    
    if (_currentIndex != _tabController.index) {
      setState(() {
        _currentIndex = _tabController.index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final enableAnimation = appearanceSettings.enablePageAnimation;
    
    return Consumer2<JellyfinProvider, EmbyProvider>(
      builder: (context, jellyfinProvider, embyProvider, child) {
        final currentJellyfinConnectionState = jellyfinProvider.isConnected;
        final currentEmbyConnectionState = embyProvider.isConnected;
        
        // 检查连接状态是否改变
        if (_isJellyfinConnected != currentJellyfinConnectionState || 
            _isEmbyConnected != currentEmbyConnectionState) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _updateTabController(currentJellyfinConnectionState, currentEmbyConnectionState);
            }
          });
        }
        
        // 动态生成标签页内容
        final List<Widget> pageChildren = [
          RepaintBoundary(
            child: MediaLibraryPage(
              key: ValueKey('mediaLibrary_${widget.mediaLibraryVersion}'),
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
          RepaintBoundary(
            child: LibraryManagementTab(
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
        ];
        
        if (_isJellyfinConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: JellyfinMediaLibraryView(
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }
        
        if (_isEmbyConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: EmbyMediaLibraryView(
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }
        
        // 动态生成标签
        final List<Tab> tabs = [
          const Tab(text: "媒体库"),
          const Tab(text: "库管理"),
        ];
        
        if (_isJellyfinConnected) {
          tabs.add(const Tab(text: "Jellyfin"));
        }
        
        if (_isEmbyConnected) {
          tabs.add(const Tab(text: "Emby"));
        }
        
        // 验证标签数量与内容数量是否匹配
        if (tabs.length != pageChildren.length || tabs.length != _tabCount) {
          print('警告：标签数量(${tabs.length})、内容数量(${pageChildren.length})与预期数量($_tabCount)不匹配');
        }
        
        return LayoutBuilder(
          builder: (context, constraints) {
            // 检查可用高度，如果太小则使用最小安全布局
            final availableHeight = constraints.maxHeight;
            final isHeightConstrained = availableHeight < 100; // 小于100像素视为高度受限
            
            if (isHeightConstrained) {
              // 高度受限时，使用简化布局避免溢出
              return SizedBox(
                height: availableHeight,
                child: const Center(
                  child: Text(
                    '布局空间不足',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              );
            }
            
            return Column(
              children: [
                // TabBar - 使用Flexible包装以防溢出
                Flexible(
                  flex: 0,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: tabs,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold
                    ),
                    indicatorPadding: const EdgeInsets.only(
                      top: 45, 
                      left: 0, 
                      right: 0
                    ),
                    indicator: BoxDecoration(
                      color: Colors.greenAccent,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    tabAlignment: TabAlignment.start,
                    dividerColor: const Color.fromARGB(59, 255, 255, 255),
                    dividerHeight: 3.0,
                    indicatorSize: TabBarIndicatorSize.tab,
                  ),
                ),
                // 内容区域 - 确保占用剩余所有空间
                Expanded(
                  child: SwitchableView(
                    enableAnimation: enableAnimation,
                    currentIndex: _currentIndex,
                    controller: _tabController,
                    physics: enableAnimation 
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) {
                      if (_currentIndex != index) {
                        setState(() {
                          _currentIndex = index;
                        });
                        _tabController.animateTo(index);
                        print('页面变更到: $index (启用动画: $enableAnimation)');
                      }
                    },
                    children: pageChildren,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _updateTabController(bool isJellyfinConnected, bool isEmbyConnected) {
    if (_isJellyfinConnected == isJellyfinConnected && _isEmbyConnected == isEmbyConnected) return;
    
    final oldIndex = _currentIndex;
    _isJellyfinConnected = isJellyfinConnected;
    _isEmbyConnected = isEmbyConnected;
    
    // 创建新的TabController
    final newController = TabController(
      length: _tabCount, 
      vsync: this, 
      initialIndex: oldIndex >= _tabCount ? 0 : oldIndex
    );
    
    // 移除旧监听器并释放资源
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    
    // 更新到新的控制器
    _tabController = newController;
    _tabController.addListener(_handleTabChange);
    
    // 调整当前索引
    if (_currentIndex >= _tabCount) {
      _currentIndex = 0;
    }
    
    setState(() {
      // 触发重建以使用新的TabController
    });
    
    print('TabController已更新：新长度=$_tabCount, 当前索引=$_currentIndex');
  }
}

// 鼠标拖动滚动包装器
class _MouseDragScrollWrapper extends StatefulWidget {
  final ScrollController scrollController;
  final Widget child;

  const _MouseDragScrollWrapper({
    required this.scrollController,
    required this.child,
  });

  @override
  State<_MouseDragScrollWrapper> createState() => _MouseDragScrollWrapperState();
}

class _MouseDragScrollWrapperState extends State<_MouseDragScrollWrapper> {
  bool _isDragging = false;
  double _lastPanPosition = 0.0;
  
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // 只响应鼠标左键
        if (event.buttons == 1) {
          _isDragging = true;
          _lastPanPosition = event.position.dx;
        }
      },
      onPointerMove: (PointerMoveEvent event) {
        if (_isDragging && widget.scrollController.hasClients) {
          final double delta = _lastPanPosition - event.position.dx;
          _lastPanPosition = event.position.dx;
          
          // 计算新的滚动位置
          final double newScrollOffset = widget.scrollController.offset + delta;
          
          // 限制滚动范围
          final double maxScrollExtent = widget.scrollController.position.maxScrollExtent;
          final double minScrollExtent = widget.scrollController.position.minScrollExtent;
          
          final double clampedOffset = newScrollOffset.clamp(minScrollExtent, maxScrollExtent);
          
          // 应用滚动
          widget.scrollController.jumpTo(clampedOffset);
        }
      },
      onPointerUp: (PointerUpEvent event) {
        _isDragging = false;
      },
      onPointerCancel: (PointerCancelEvent event) {
        _isDragging = false;
      },
      child: MouseRegion(
        cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: widget.child,
      ),
    );
  }
}
