import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';
import 'package:nipaplay/models/watch_history_model.dart';
import '../utils/video_player_state.dart';
import '../widgets/loading_overlay.dart';
import '../utils/tab_change_notifier.dart';
import '../widgets/loading_placeholder.dart';
import '../providers/watch_history_provider.dart';
import '../providers/appearance_settings_provider.dart';
import 'package:flutter/gestures.dart';
import '../pages/media_library_page.dart';
import '../widgets/library_management_tab.dart';
import 'package:nipaplay/services/scan_service.dart';
import '../widgets/blur_snackbar.dart';
import '../widgets/history_all_modal.dart';
import '../widgets/switchable_view.dart';
import 'package:flutter/rendering.dart';
import 'package:nipaplay/main.dart';
import '../services/jellyfin_service.dart';

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
  int _currentTabIndex = 0;

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
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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

    // 检查是否为网络URL或Jellyfin协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;
    
    if (isNetworkUrl || isJellyfinProtocol) {
      // 对于网络URL和Jellyfin协议，跳过本地文件检查
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
        debugPrint('[AnimePage] statusListener: Player ready/playing AND tabChangeLogicExecuted is false.');
        tabChangeLogicExecuted = true; // Set flag immediately
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
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
            debugPrint('[AnimePage] statusListener (postFrame): Removing self (statusListener).');
            videoState.removeListener(statusListener);
          } else {
            debugPrint('[AnimePage] statusListener (postFrame): Not mounted, removing listener only.');
            videoState.removeListener(statusListener); // Also remove if not mounted here
          }
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
    
    // 根据是否是Jellyfin流媒体决定传递参数
    if (isJellyfinProtocol && actualPlayUrl != null) {
      debugPrint('[AnimePage] 使用Jellyfin流媒体URL播放: $actualPlayUrl');
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
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
    final cardWidth = 166.0; // 卡片宽度 + 右侧padding
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

    // 根据平台决定是否使用Scrollbar
    if (Platform.isAndroid || Platform.isIOS) {
      return historyListView; // 移动平台不显示滚动条
    } else {
      // 创建适用于桌面平台的Scrollbar
      return Scrollbar(
        controller: _watchHistoryListScrollController,
        radius: const Radius.circular(2),
        thickness: 4, 
        thumbVisibility: false,
        child: historyListView,
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
    Key? key,
    this.initialIndex = 0,
    required this.onPlayEpisode,
    required this.mediaLibraryVersion,
  }) : super(key: key);

  @override
  State<_MediaLibraryTabs> createState() => _MediaLibraryTabsState();
}

class _MediaLibraryTabsState extends State<_MediaLibraryTabs> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  // 添加一个固定的子组件数量常量
  static const int TAB_COUNT = 2; // 固定为2个标签页：媒体库和库管理

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // 使用固定的TAB_COUNT常量，避免后续变化
    _tabController = TabController(length: TAB_COUNT, vsync: this, initialIndex: _currentIndex);
    _tabController.addListener(_handleTabChange);
    
    // 添加调试信息
    print('_MediaLibraryTabs创建TabController：固定长度${_tabController.length}');
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
    // 获取外观设置，判断是否启用页面滑动动画
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final enableAnimation = appearanceSettings.enablePageAnimation;
    
    // 保存子组件为局部变量，确保长度一致性
    final List<Widget> pageChildren = [
      // 使用RepaintBoundary隔离绘制边界，减少重绘范围
      RepaintBoundary(
        child: MediaLibraryPage(
          key: ValueKey('mediaLibrary_${widget.mediaLibraryVersion}'),
          onPlayEpisode: widget.onPlayEpisode,
        ),
      ),
      // 使用RepaintBoundary隔离绘制边界，减少重绘范围
      RepaintBoundary(
        child: LibraryManagementTab(
          onPlayEpisode: widget.onPlayEpisode,
        ),
      ),
    ];
    
    // 验证子组件数量与TabController长度是否匹配
    if (pageChildren.length != TAB_COUNT) {
      print('警告：子组件数量(${pageChildren.length})与TabController长度(${TAB_COUNT})不匹配');
    }
    
    return Column(
      children: [
        // Tab控制器
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "媒体库"),
            Tab(text: "库管理"),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold),
          indicatorPadding: const EdgeInsets.only(
              top: 45, left: 0, right: 0),
          indicator: BoxDecoration(
            color: Colors.greenAccent,
            borderRadius: BorderRadius.circular(30),
          ),
          tabAlignment: TabAlignment.start,
          dividerColor: const Color.fromARGB(59, 255, 255, 255),
          dividerHeight: 3.0,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        // 内容区域 - 使用SwitchableView替代直接使用IndexedStack
        Expanded(
          child: SwitchableView(
            enableAnimation: enableAnimation,
            currentIndex: _currentIndex,
            controller: _tabController,
            // 使用更合适的物理滑动效果
            physics: enableAnimation 
                ? const PageScrollPhysics() // 开启动画时使用页面滑动物理效果
                : const NeverScrollableScrollPhysics(), // 关闭动画时禁止滑动
            onPageChanged: (index) {
              if (_currentIndex != index) {
                setState(() {
                  _currentIndex = index;
                });
                // 使用animateTo而不是直接设置index，这样可以保持动画效果
                _tabController.animateTo(index);
                
                // 额外的调试信息，帮助排查问题
                print('页面变更到: $index (启用动画: $enableAnimation)');
              }
            },
            children: pageChildren,
          ),
        ),
      ],
    );
  }
}
