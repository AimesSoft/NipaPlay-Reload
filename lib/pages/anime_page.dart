import 'package:flutter/material.dart';
import 'dart:io';
import '../models/watch_history_model.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../widgets/loading_overlay.dart';
import '../utils/tab_change_notifier.dart';
import 'dart:typed_data';
import '../widgets/loading_placeholder.dart';
import '../providers/watch_history_provider.dart';
import 'package:flutter/gestures.dart';
import '../pages/media_library_page.dart';
import '../widgets/library_management_tab.dart';
import 'package:nipaplay/services/scan_service.dart';

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
    return Material(
      color: Colors.transparent, // Changed from Theme.of(context).scaffoldBackgroundColor
      elevation: overlapsContent ? 4.0 : 0.0, // Add elevation when content overlaps (sticks)
      child: tabBar,
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

  int _mediaLibraryVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {});
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

  void _onWatchHistoryItemTap(WatchHistoryItem item) {
    debugPrint('[AnimePage] _onWatchHistoryItemTap: Received item: $item');
    if (item != null) {
      debugPrint('[AnimePage] item.animeName: ${item.animeName}');
      debugPrint('[AnimePage] item.filePath: ${item.filePath}');
      debugPrint('[AnimePage] item.episodeTitle: ${item.episodeTitle}');
    }

    if (_videoPlayerState == null) {
      try {
        _videoPlayerState =
            Provider.of<VideoPlayerState>(context, listen: false);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放器初始化失败，请重试')),
        );
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
      if (!mounted) {
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
      if (videoState.status == PlayerStatus.ready ||
          videoState.status == PlayerStatus.playing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _loadingVideo = false;
            });
            videoState.removeListener(statusListener);
            final tabController = DefaultTabController.of(context);
            tabController.animateTo(0);
            try {
              Provider.of<TabChangeNotifier>(context, listen: false)
                  .changeTab(0);
            } catch (e) {}
          }
        });
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
    videoState.initializePlayer(item.filePath, historyItem: item);
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

            // DefaultTabController is moved to wrap NestedScrollView
            return DefaultTabController(
              length: 2,
              child: Stack(
                children: [
                  NestedScrollView(
                    controller: _mainPageScrollController,
                    headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                      return <Widget>[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(top: 24, left: 16.0, right: 16.0),
                            child: Text("观看记录",
                                style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 180,
                            child: isLoadingHistory && history.isEmpty
                                ? const Center(child: CircularProgressIndicator())
                                : history.isEmpty
                                    ? _buildEmptyState(
                                        message: "暂无观看记录，已扫描的视频可在媒体库查看")
                                    : _buildWatchHistoryList(history),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        SliverPersistentHeader(
                          delegate: _SliverTabBarDelegate(
                            TabBar(
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
                          ),
                          pinned: true, // This makes the TabBar stick
                          floating: false, // Keeps TabBar visible once pinned
                        ),
                      ];
                    },
                    body: TabBarView(
                      children: [
                        MediaLibraryPage(
                          key: ValueKey(_mediaLibraryVersion),
                          onPlayEpisode: _onWatchHistoryItemTap,
                          // Physics might need adjustment here, to be reviewed
                        ),
                        LibraryManagementTab(
                          onPlayEpisode: _onWatchHistoryItemTap,
                          // Physics might need adjustment here, to be reviewed
                        ),
                      ],
                    ),
                  ),
                  if (_loadingVideo)
                    Positioned.fill(
                      child: LoadingOverlay(messages: _loadingMessages),
                    ),
                ],
              ),
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
    // Filter out items with zero duration, as they are likely just scanned entries without playback
    final displayedHistory =
        history.where((item) => item.duration > 0).toList();
    // The history from provider is already sorted by lastWatchTime.

    if (displayedHistory.isEmpty) {
      return _buildEmptyState(message: "暂无观看记录，已扫描的视频可在媒体库查看");
    }

    // 确定哪个是最新更新的记录 (from the displayed list)
    String? latestUpdatedPath;
    DateTime latestTime = DateTime(2000);
    for (var item in displayedHistory) {
      if (item.lastWatchTime.isAfter(latestTime)) {
        latestTime = item.lastWatchTime;
        latestUpdatedPath = item.filePath;
      }
    }

    Widget actualListView = ListView.builder(
      controller: _watchHistoryListScrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: displayedHistory.length, // Use filtered list length
      itemBuilder: (context, index) {
        final item = displayedHistory[index]; // Use filtered list item
        final isLatestUpdated = item.filePath == latestUpdatedPath;
        return Padding(
          key: ValueKey(
              '${item.filePath}_${item.lastWatchTime.millisecondsSinceEpoch}'),
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            onTap: () => _onWatchHistoryItemTap(item),
            child: _buildHistoryCard(item, isLatestUpdated),
          ),
        );
      },
    );

    Widget listWidget;
    // Check if the platform is mobile
    if (Platform.isAndroid || Platform.isIOS) {
      // On mobile, do not use Scrollbar
      listWidget = actualListView;
    } else {
      // On non-mobile platforms (e.g., desktop), use Scrollbar
      listWidget = Scrollbar(
        controller: _watchHistoryListScrollController,
        child: actualListView,
      );
    }

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          // 鼠标滚轮上下滚动时，横向滚动
          final newOffset =
              _watchHistoryListScrollController.offset + pointerSignal.scrollDelta.dy;
          if (newOffset < 0) {
            _watchHistoryListScrollController.jumpTo(0);
          } else if (newOffset >
              _watchHistoryListScrollController.position.maxScrollExtent) {
            _watchHistoryListScrollController
                .jumpTo(_watchHistoryListScrollController.position.maxScrollExtent);
          } else {
            _watchHistoryListScrollController.jumpTo(newOffset);
          }
        }
      },
      child: listWidget, // Use the conditionally wrapped list
    );
  }

  Widget _buildHistoryCard(WatchHistoryItem item, bool isLatestUpdated) {
    return SizedBox(
      width: 150,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GlassmorphicContainer(
          width: 150,
          height: 170,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图部分 (如果有则显示，否则显示默认图片)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                child: Container(
                  height: 90,
                  width: double.infinity,
                  color: Colors.black38,
                  child: _getVideoThumbnail(item, isLatestUpdated),
                ),
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
                      item.animeName.isEmpty
                          ? path.basename(item.filePath)
                          : item.animeName,
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
      color: Colors.black54,
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
}
