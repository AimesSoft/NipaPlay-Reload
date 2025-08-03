import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/jellyfin_detail_page.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/jellyfin_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/jellyfin_sort_dialog.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

class JellyfinMediaLibraryView extends StatefulWidget {
  final void Function(WatchHistoryItem item)? onPlayEpisode;

  const JellyfinMediaLibraryView({
    super.key,
    this.onPlayEpisode,
  });

  @override
  State<JellyfinMediaLibraryView> createState() => _JellyfinMediaLibraryViewState();
}

class _JellyfinMediaLibraryViewState extends State<JellyfinMediaLibraryView> with AutomaticKeepAliveClientMixin {
  List<JellyfinMediaItem> _jellyfinMediaItems = [];
  bool _isLoadingJellyfin = false;
  String? _jellyfinError;
  Timer? _jellyfinRefreshTimer;
  final ScrollController _gridScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.addListener(_onJellyfinProviderChanged);
        _loadJellyfinData(); // Initial load based on current provider state
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
      print("Error removing JellyfinProvider listener in JellyfinMediaLibraryView: $e");
    }
    _jellyfinRefreshTimer?.cancel();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _onJellyfinProviderChanged() {
    if (mounted) {
      _loadJellyfinData();
    }
  }

  Future<void> _loadJellyfinData() async {
    if (!mounted) return;

    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    final jellyfinService = JellyfinService.instance;

    if (!jellyfinProvider.isConnected || jellyfinProvider.selectedLibraryIds.isEmpty) {
      if (mounted) {
        setState(() {
          _jellyfinMediaItems = [];
          _isLoadingJellyfin = false;
          _jellyfinError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingJellyfin = true;
        _jellyfinError = null;
      });
    }

    try {
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      final mediaItems = await jellyfinService.getLatestMediaItems(
        limit: 99999,
        sortBy: jellyfinProvider.currentSortBy,
        sortOrder: jellyfinProvider.currentSortOrder,
      );
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
        });
      }
    }
  }

  void _setupJellyfinRefreshTimer() {
    _jellyfinRefreshTimer?.cancel();
    _jellyfinRefreshTimer = Timer.periodic(const Duration(minutes: 60), (timer) {
      _loadJellyfinData();
    });
  }

  Future<void> _showJellyfinServerDialog() async {
    final result = await JellyfinServerDialog.show(context);
    if (result == true && mounted) {
        _loadJellyfinData(); // Reload if dialog indicated changes
    }
  }

  void _navigateToJellyfinDetail(String jellyfinId) {
    JellyfinDetailPage.show(context, jellyfinId).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        widget.onPlayEpisode?.call(result);
      }
    });
  }

  Future<void> _showSortDialog() async {
    print('JellyfinMediaLibraryView: 显示排序对话框');
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    print('JellyfinMediaLibraryView: 当前排序设置 - sortBy: ${jellyfinProvider.currentSortBy}, sortOrder: ${jellyfinProvider.currentSortOrder}');
    
    final result = await JellyfinSortDialog.show(
      context,
      currentSortBy: jellyfinProvider.currentSortBy,
      currentSortOrder: jellyfinProvider.currentSortOrder,
    );
    
    if (result != null && mounted) {
      print('JellyfinMediaLibraryView: 用户选择了新的排序设置 - sortBy: ${result['sortBy']}, sortOrder: ${result['sortOrder']}');
      await jellyfinProvider.updateSortSettings(
        result['sortBy']!,
        result['sortOrder']!,
      );
    } else {
      print('JellyfinMediaLibraryView: 用户取消了排序设置');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // For AutomaticKeepAliveClientMixin

    final jellyfinProvider = Provider.of<JellyfinProvider>(context); // listen: true for build updates
    final jellyfinService = JellyfinService.instance;

    if (!jellyfinProvider.isConnected || jellyfinProvider.selectedLibraryIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Jellyfin未连接或未选择媒体库。\n请检查Jellyfin服务器设置。',
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

    if (_isLoadingJellyfin) {
      return const Center(child: CircularProgressIndicator());
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
                label: const Text('检查Jellyfin设置'),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer<JellyfinProvider>(
      builder: (context, jellyfinProvider, child) {
        // 当JellyfinProvider的媒体项更新时，同步更新本地状态
        if (_jellyfinMediaItems != jellyfinProvider.mediaItems) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _jellyfinMediaItems = jellyfinProvider.mediaItems;
              });
            }
          });
        }
        
        return Stack(
          children: [
            RepaintBoundary(
              child: Platform.isAndroid || Platform.isIOS
              ? GridView.builder(
                  controller: _gridScrollController,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 150,
                    childAspectRatio: 7 / 12,
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
                )
              : Scrollbar(
                  controller: _gridScrollController,
                  thickness: 4,
                  radius: const Radius.circular(2),
                  child: GridView.builder(
                    controller: _gridScrollController,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 150,
                      childAspectRatio: 7 / 12,
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
                        source: 'Jellyfin',
                        onTap: () {
                          _navigateToJellyfinDetail(mediaItem.id);
                        },
                      );
                    },
                  ),
                ),
        ),
        // 排序按钮
        Positioned(
          right: 16,
          bottom: 80,
          child: FloatingActionGlassButton(
            iconData: Ionicons.funnel_outline,
            onPressed: _showSortDialog,
            description: 'Jellyfin排序设置\n选择排序方式和顺序\n支持多种排序选项',
          ),
        ),
        // 设置按钮
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionGlassButton(
            iconData: Ionicons.settings_outline,
            onPressed: _showJellyfinServerDialog,
            description: 'Jellyfin服务器设置\n管理连接信息和媒体库\n配置播放偏好设置',
          ),
        ),
      ],
    );
      },
    );
  }
}