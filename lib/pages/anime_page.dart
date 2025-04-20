import 'package:flutter/material.dart';
import 'dart:io';
import '../models/watch_history_model.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../widgets/loading_overlay.dart';
import '../utils/tab_change_notifier.dart';

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> with WidgetsBindingObserver {
  List<WatchHistoryItem> _watchHistory = [];
  bool _isLoading = true;
  bool _loadingVideo = false;
  List<String> _loadingMessages = ['正在初始化播放器...'];
  TabController? _tabController;
  VideoPlayerState? _videoPlayerState;
  DateTime _lastHistoryUpdateTime = DateTime(2000); // 初始设为很早的时间
  DateTime _lastCacheClearTime = DateTime(2000); // 初始设为很早的时间

  @override
  void initState() {
    super.initState();
    _loadWatchHistory();
    // 添加观察者
    WidgetsBinding.instance.addObserver(this);
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
    if (_tabController != null) {
      // 添加监听器
      _tabController!.addListener(_handleTabChange);
    }
  }

  void _handleTabChange() {
    // 如果 TabController 可用且选中了动画页面（索引为1）
    if (_tabController != null && _tabController!.index == 1 && mounted) {
      // 使用局部变量保存上次更新时间
      final now = DateTime.now();
      final lastUpdateDiff = now.difference(_lastHistoryUpdateTime).inSeconds;
      
      // 只有当距离上次更新超过5秒或首次加载时才刷新
      if (lastUpdateDiff > 5 || _watchHistory.isEmpty) {
        //debugPrint('切换到观看记录页面，距离上次更新${lastUpdateDiff}秒，触发刷新');
        _loadWatchHistory();
      } else {
        //debugPrint('切换到观看记录页面，但刚刚更新过（${lastUpdateDiff}秒前），跳过刷新');
      }
    }
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
    //debugPrint('收到缩略图更新通知，刷新观看历史');
    // 确保组件挂载时才进行操作
    if (!mounted) return;
    
    // 立即清理图片缓存，确保缩略图能够更新
    //debugPrint('强制清理图片缓存');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    
    // 避免多层嵌套异步操作，减少状态访问不一致的风险
    // 增加延迟，给缓存清理和文件系统更新留出时间
    _safeReloadWatchHistory(delay: 500);
  }

  // 安全地重新加载观看历史
  void _safeReloadWatchHistory({int delay = 0}) {
    if (!mounted) return;
    
    // 如果已经有一个重载正在进行，不要启动另一个
    if (_isReloadingHistory) {
      //debugPrint('已有重载历史记录任务正在进行，跳过此次请求');
      return;
    }
    
    if (delay > 0) {
      // 如果需要延迟，使用postFrameCallback和Future.delayed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(Duration(milliseconds: delay), () {
          if (mounted) _loadWatchHistory();
        });
      });
    } else {
      // 直接加载
      _loadWatchHistory();
    }
  }

  // 加载时使用的锁，防止并发加载
  bool _isReloadingHistory = false;

  @override
  void dispose() {
    // 移除 TabController 监听器
    if (_tabController != null) {
      _tabController!.removeListener(_handleTabChange);
    }
    // 移除观察者
    WidgetsBinding.instance.removeObserver(this);
    
    // 移除缩略图更新监听器
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.removeThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {
      //debugPrint('移除缩略图更新监听器时出错: $e');
    }
    
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用恢复活动状态时刷新观看历史
    if (state == AppLifecycleState.resumed) {
      _loadWatchHistory();
    }
  }

  Future<void> _loadWatchHistory() async {
    // 如果已经在加载，直接返回
    if (_isReloadingHistory) {
      //debugPrint('已经在加载观看历史，跳过重复请求');
      return;
    }
    
    //debugPrint('开始重新加载观看历史...');
    // 先检查组件是否挂载
    if (!mounted) return;
    
    _isReloadingHistory = true;
    
    // 使用局部变量记录初始加载状态
    final bool initialLoadingState = _watchHistory.isEmpty;
    
    // 只有在初始加载时才显示加载状态
    if (initialLoadingState) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final history = await WatchHistoryManager.getAllHistory();
      
      // 如果不是首次加载且有历史记录，清理图片缓存以确保最新缩略图更新
      // 但是减少这种清理的频率，只有在上次清理超过30秒后才清理
      if (!initialLoadingState && history.isNotEmpty) {
        final now = DateTime.now();
        if (now.difference(_lastCacheClearTime).inSeconds > 30) {
          // 彻底清理图片缓存，确保缩略图能够刷新
          //debugPrint('清理图片缓存确保最新缩略图更新');
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          _lastCacheClearTime = now;
        } else {
          //debugPrint('距上次清理缓存时间不足30秒，跳过此次清理');
        }
      }
      
      // 在异步操作完成后再次检查组件是否挂载
      if (!mounted) return;
      
      // 仅在有数据变化或初始加载时更新UI
      bool needsUpdate = initialLoadingState;
      
      if (history.length != _watchHistory.length) {
        needsUpdate = true;
      } else if (history.isNotEmpty) {
        // 检查第一项是否有变化
        final firstNew = history.first;
        final firstOld = _watchHistory.isNotEmpty ? _watchHistory.first : null;
        
        if (firstOld == null || 
            firstNew.filePath != firstOld.filePath || 
            firstNew.lastWatchTime != firstOld.lastWatchTime ||
            firstNew.thumbnailPath != firstOld.thumbnailPath) {
          needsUpdate = true;
        }
      }
      
      if (needsUpdate) {
        setState(() {
          _watchHistory = history;
          _isLoading = false;
          _lastHistoryUpdateTime = DateTime.now();
        });
        //debugPrint('观看历史已更新，共${history.length}条记录');
      } else {
        //debugPrint('观看历史无变化，跳过UI更新');
        if (initialLoadingState) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      //debugPrint('加载观看历史失败: $e');
      // 确保组件仍然挂载
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载观看记录失败: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      _isReloadingHistory = false;
    }
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
        // 延迟一点时间再刷新，确保观看记录已保存
        _safeReloadWatchHistory(delay: 500);
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
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.only(top: 24),  // 添加上方间距，避免置顶
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text("观看记录", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              
              // 观看记录部分
              SizedBox(
                height: 180,
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : _watchHistory.isEmpty
                    ? _buildEmptyState()
                    : _buildWatchHistoryList(),
              ),
              
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text("媒体库", style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              
              // 媒体库部分 - 这部分保持原样
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
        
        // 加载中遮罩
        if (_loadingVideo)
          LoadingOverlay(
            messages: _loadingMessages,
            backgroundOpacity: 0.5,
          ),
      ],
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

  Widget _buildWatchHistoryList() {
    // 确定哪个是最新更新的记录
    String? latestUpdatedPath;
    DateTime latestTime = DateTime(2000); // 初始设为很早的时间
    
    for (var item in _watchHistory) {
      if (item.lastWatchTime.isAfter(latestTime)) {
        latestTime = item.lastWatchTime;
        latestUpdatedPath = item.filePath;
      }
    }
    
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _watchHistory.length,
      itemBuilder: (context, index) {
        final item = _watchHistory[index];
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
        if (isLatestUpdated) {
          // 对最新记录使用更激进的刷新策略
          //debugPrint('使用特殊刷新策略加载最新缩略图: ${item.thumbnailPath}');
          
          // 读取文件字节数据，跳过图片缓存
          try {
            final bytes = thumbnailFile.readAsBytesSync();
            return Image.memory(
              bytes,
              key: UniqueKey(), // 每次都使用新Key
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                //debugPrint('加载缩略图字节数据出错: $error');
                return _buildDefaultThumbnail();
              },
            );
          } catch (e) {
            //debugPrint('读取缩略图文件失败: $e');
            return _buildDefaultThumbnail();
          }
        } else {
          // 非最新记录使用常规方式加载
          return Image.file(
            thumbnailFile,
            key: ValueKey(item.thumbnailPath),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 300,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              //debugPrint('加载缩略图出错: $error');
              return _buildDefaultThumbnail();
            },
          );
        }
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