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

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> with WidgetsBindingObserver {
  bool _loadingVideo = false;
  List<String> _loadingMessages = ['正在初始化播放器...'];
  TabController? _tabController;
  VideoPlayerState? _videoPlayerState;
  final DateTime _lastHistoryUpdateTime = DateTime(2000); // 初始设为很早的时间
  final DateTime _lastCacheClearTime = DateTime(2000); // 初始设为很早的时间
  final ScrollController _historyScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 在下一帧执行，确保上下文可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupTabController();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在didChangeDependencies中获取Provider，并保存引用
    _videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
    _setupThumbnailUpdateListener();
  }

  void _setupTabController() {
    // 获取 TabController
    _tabController = DefaultTabController.of(context);
    // 不再添加监听器和刷新逻辑
  }

  // 设置缩略图更新监听器
  void _setupThumbnailUpdateListener() {
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.addThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {
      //debugPrint('设置缩略图更新监听器时出错: $e');
    }
  }

  // 缩略图更新回调
  void _onThumbnailUpdated() {
    if (!mounted) return;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    // 不再自动刷新观看记录，由Provider负责
  }

  @override
  void dispose() {
    if (_tabController != null) {
      _tabController!.removeListener(() {}); // 移除无用监听
    }
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.removeThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {}
    _historyScrollController.dispose();
    super.dispose();
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) {
    // 使用保存的引用，而不是每次都从Provider获取
    if (_videoPlayerState == null) {
      // 如果没有引用，安全地获取
      try {
        _videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
      } catch (e) {
        //debugPrint('获取VideoPlayerState失败: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放器初始化失败，请重试')),
        );
        return;
      }
    }
    
    final videoState = _videoPlayerState!;
    
    // 显示加载中遮罩
    setState(() {
      _loadingVideo = true;
      _loadingMessages = ['正在初始化播放器...'];
    });
    
    // 声明一个监听器变量，但暂时不赋值
    late final VoidCallback statusListener;
    late final VoidCallback playbackFinishListener;
    
    // 定义并赋值状态监听器函数
    statusListener = () {
      // 确保页面仍然挂载
      if (!mounted) {
        videoState.removeListener(statusListener);
        return;
      }
      
      // 更新加载消息
      if (videoState.statusMessages.isNotEmpty && 
          videoState.statusMessages.last != _loadingMessages.last) {
        // 使用安全的方式更新状态，确保不在布局过程中调用setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _loadingMessages = List<String>.from(videoState.statusMessages);
            });
          }
        });
      }
      
      // 当视频状态变为ready或playing时，表示初始化完成，此时再跳转
      if (videoState.status == PlayerStatus.ready || 
          videoState.status == PlayerStatus.playing) {
        // 隐藏加载中遮罩，使用postFrameCallback确保安全
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _loadingVideo = false;
            });
            // 在跳转前移除监听器，避免在页面dispose后调用setState
            videoState.removeListener(statusListener);
            // 切换到视频播放页面
            final tabController = DefaultTabController.of(context);
            tabController.animateTo(0);
            // 新增：确保主Tab切换到播放页
            try {
              Provider.of<TabChangeNotifier>(context, listen: false).changeTab(0);
            } catch (e) {
              // 忽略异常，防止因Provider未找到导致崩溃
            }
          }
        });
      }
    };
    
    // 定义播放结束监听器，用于刷新观看历史
    playbackFinishListener = () {
      // 如果播放状态变为暂停并且视频进度接近结束，认为播放结束了
      if (!mounted) {
        videoState.removeListener(playbackFinishListener);
        return;
      }
      
      if (videoState.status == PlayerStatus.paused && 
          videoState.progress > 0.9) {
        //debugPrint('检测到视频播放接近结束，重新加载观看历史');
        // 移除监听器，避免重复触发
        videoState.removeListener(playbackFinishListener);
        // 直接刷新Provider
        final provider = context.read<WatchHistoryProvider>();
        provider.refresh();
      }
    };
    
    // 添加监听器
    videoState.addListener(statusListener);
    videoState.addListener(playbackFinishListener);
    
    // 加载选定的视频
    videoState.initializePlayer(item.filePath);
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
    final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context);
    if (!watchHistoryProvider.isLoaded && !watchHistoryProvider.isLoading) {
      // 兜底触发一次加载
      Future.microtask(() {
        watchHistoryProvider.loadHistory();
      });
    }
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        final isLoading = historyProvider.isLoading;
        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text("观看记录", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : history.isEmpty
                        ? _buildEmptyState()
                        : _buildWatchHistoryList(history),
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text("媒体库", style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Center(
                      child: Text(
                        "媒体库功能开发中...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loadingVideo)
              LoadingOverlay(
                messages: _loadingMessages,
                backgroundOpacity: 0.5,
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            color: Colors.white38,
            size: 48,
          ),
          SizedBox(height: 16),
          Text(
            "暂无观看记录",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchHistoryList(List<WatchHistoryItem> history) {
    // 确定哪个是最新更新的记录
    String? latestUpdatedPath;
    DateTime latestTime = DateTime(2000);
    for (var item in history) {
      if (item.lastWatchTime.isAfter(latestTime)) {
        latestTime = item.lastWatchTime;
        latestUpdatedPath = item.filePath;
      }
    }
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          // 鼠标滚轮上下滚动时，横向滚动
          final newOffset = _historyScrollController.offset + pointerSignal.scrollDelta.dy;
          if (newOffset < 0) {
            _historyScrollController.jumpTo(0);
          } else if (newOffset > _historyScrollController.position.maxScrollExtent) {
            _historyScrollController.jumpTo(_historyScrollController.position.maxScrollExtent);
          } else {
            _historyScrollController.jumpTo(newOffset);
          }
        }
      },
      child: Scrollbar(
        controller: _historyScrollController,
        child: ListView.builder(
          controller: _historyScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: history.length,
          itemBuilder: (context, index) {
            final item = history[index];
            final isLatestUpdated = item.filePath == latestUpdatedPath;
            return Padding(
              key: ValueKey('${item.filePath}_${item.lastWatchTime.millisecondsSinceEpoch}'),
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () => _onWatchHistoryItemTap(item),
                child: _buildHistoryCard(item, isLatestUpdated),
              ),
            );
          },
        ),
      ),
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
                      item.animeName.isEmpty ? path.basename(item.filePath) : item.animeName,
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
                          _formatDuration(Duration(milliseconds: item.lastPosition)),
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
              return const LoadingPlaceholder(width: double.infinity, height: 90, borderRadius: 10);
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return _buildDefaultThumbnail();
            }
            try {
              return Image.memory(
                snapshot.data!,
                key: isLatestUpdated ? UniqueKey() : ValueKey(item.thumbnailPath),
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
}