import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/emby_detail_page.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/emby_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

class EmbyMediaLibraryView extends StatefulWidget {
  final void Function(WatchHistoryItem item)? onPlayEpisode;

  const EmbyMediaLibraryView({
    super.key,
    this.onPlayEpisode,
  });

  @override
  State<EmbyMediaLibraryView> createState() => _EmbyMediaLibraryViewState();
}

class _EmbyMediaLibraryViewState extends State<EmbyMediaLibraryView> with AutomaticKeepAliveClientMixin {
  List<EmbyMediaItem> _embyMediaItems = [];
  bool _isLoadingEmby = false;
  String? _embyError;
  Timer? _embyRefreshTimer;
  final ScrollController _gridScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
        embyProvider.addListener(_onEmbyProviderChanged);
        _loadEmbyData(); // Initial load based on current provider state
      }
    });
  }

  @override
  void dispose() {
    try {
      if (mounted) {
        final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
        embyProvider.removeListener(_onEmbyProviderChanged);
      }
    } catch (e) {
      // ignore: avoid_print
      print("Error removing EmbyProvider listener in EmbyMediaLibraryView: $e");
    }
    _embyRefreshTimer?.cancel();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _onEmbyProviderChanged() {
    if (mounted) {
      _loadEmbyData();
    }
  }

  Future<void> _loadEmbyData() async {
    if (!mounted) return;

    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    final embyService = EmbyService.instance;

    if (!embyProvider.isConnected || embyProvider.selectedLibraryIds.isEmpty) {
      if (mounted) {
        setState(() {
          _embyMediaItems = [];
          _isLoadingEmby = false;
          _embyError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingEmby = true;
        _embyError = null;
      });
    }

    try {
      // final mediaItems = await embyService.getLatestMediaItems(limit: 200); // 旧的调用方式
      final mediaItems = await embyService.getLatestMediaItems(totalLimit: 99999, limitPerLibrary: 99999); // 新的调用方式
      if (mounted) {
        setState(() {
          _embyMediaItems = mediaItems;
          _isLoadingEmby = false;
        });
      }
      _setupEmbyRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _embyError = e.toString();
          _isLoadingEmby = false;
        });
      }
    }
  }

  void _setupEmbyRefreshTimer() {
    _embyRefreshTimer?.cancel();
    _embyRefreshTimer = Timer.periodic(const Duration(minutes: 60), (timer) {
      _loadEmbyData();
    });
  }

  Future<void> _showEmbyServerDialog() async {
    final result = await EmbyServerDialog.show(context);
    if (result == true && mounted) {
        _loadEmbyData(); // Reload if dialog indicated changes
    }
  }

  void _navigateToEmbyDetail(String embyId) {
    EmbyDetailPage.show(context, embyId).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        widget.onPlayEpisode?.call(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // For AutomaticKeepAliveClientMixin

    final embyProvider = Provider.of<EmbyProvider>(context); // listen: true for build updates
    final embyService = EmbyService.instance;

    if (!embyProvider.isConnected || embyProvider.selectedLibraryIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Emby未连接或未选择媒体库。\n请检查Emby服务器设置。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showEmbyServerDialog,
                icon: const Icon(Icons.settings),
                label: const Text('设置Emby服务器'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingEmby) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_embyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载Emby媒体库失败: $_embyError', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadEmbyData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_embyMediaItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Emby媒体库为空。\n请确保已选择媒体库并且包含内容。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showEmbyServerDialog,
                icon: const Icon(Icons.settings),
                label: const Text('检查Emby设置'),
              ),
            ],
          ),
        ),
      );
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
                  itemCount: _embyMediaItems.length,
                  itemBuilder: (context, index) {
                    final mediaItem = _embyMediaItems[index];
                    final imageUrl = mediaItem.imagePrimaryTag != null
                        ? embyService.getImageUrl(mediaItem.id, width: 300)
                        : '';
                    return AnimeCard(
                      key: ValueKey('emby_${mediaItem.id}'),
                      name: mediaItem.name,
                      imageUrl: imageUrl,
                      onTap: () {
                        _navigateToEmbyDetail(mediaItem.id);
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
                    itemCount: _embyMediaItems.length,
                    itemBuilder: (context, index) {
                      final mediaItem = _embyMediaItems[index];
                      final imageUrl = mediaItem.imagePrimaryTag != null
                          ? embyService.getImageUrl(mediaItem.id, width: 300)
                          : '';
                      return AnimeCard(
                        key: ValueKey('emby_${mediaItem.id}'),
                        name: mediaItem.name,
                        imageUrl: imageUrl,
                        source: 'Emby',
                        onTap: () {
                          _navigateToEmbyDetail(mediaItem.id);
                        },
                      );
                    },
                  ),
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionGlassButton(
            iconData: Ionicons.settings_outline,
            onPressed: _showEmbyServerDialog,
            description: 'Emby服务器设置\n管理连接信息和媒体库\n配置播放偏好设置',
          ),
        ),
      ],
    );
  }
}
