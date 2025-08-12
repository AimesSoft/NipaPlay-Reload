import 'dart:async';
import 'dart:io';
import 'dart:ui';
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
import 'package:nipaplay/widgets/emby_sort_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/emby_library_card.dart';
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
  String? _embyError;
  Timer? _embyRefreshTimer;
  final ScrollController _gridScrollController = ScrollController();
  
  // 新增：库视图状态
  String? _selectedLibraryId; // 当前选中的媒体库ID
  bool _isShowingLibraryContent = false; // 是否正在显示媒体库内容
  bool _isLoadingLibraryContent = false; // 是否正在加载媒体库内容

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
    if (!mounted) return;
    // 如果正在显示单个媒体库内容，不要打断
    if (_isShowingLibraryContent && _selectedLibraryId != null) return;
    _loadEmbyData();
  }

  Future<void> _loadEmbyData() async {
    if (!mounted) return;

    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    final embyService = EmbyService.instance;

    if (!embyProvider.isConnected || embyProvider.selectedLibraryIds.isEmpty) {
      if (mounted) {
        setState(() {
          _embyMediaItems = [];
          _embyError = null;
          _selectedLibraryId = null;
          _isShowingLibraryContent = false;
        });
      }
      return;
    }

    // 如果当前正在显示单个媒体库内容，不要重新加载全局内容
    if (_isShowingLibraryContent && _selectedLibraryId != null) {
      return;
    }

    try {
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      final mediaItems = await embyService.getLatestMediaItems(
        totalLimit: 99999, 
        limitPerLibrary: 99999,
        sortBy: embyProvider.currentSortBy,
        sortOrder: embyProvider.currentSortOrder,
      );
      if (mounted && !_isShowingLibraryContent) {
        setState(() {
          _embyMediaItems = mediaItems;
        });
      }
      _setupEmbyRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _embyError = e.toString();
        });
      }
    }
  }

  // 加载特定媒体库内容
  Future<void> _loadLibraryContent(String libraryId) async {
    if (!mounted) return;

    final embyService = EmbyService.instance;
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);

    if (mounted) {
      setState(() {
        _isLoadingLibraryContent = true;
        _embyError = null;
      });
    }

    try {
      final sortSettings = embyProvider.getLibrarySortSettings(libraryId);
      final mediaItems = await embyService.getLatestMediaItemsByLibrary(
        libraryId,
        limit: 99999,
        sortBy: sortSettings['sortBy']!,
        sortOrder: sortSettings['sortOrder']!,
      );
      if (mounted) {
        setState(() {
          _embyMediaItems = mediaItems;
          _selectedLibraryId = libraryId;
          _isShowingLibraryContent = true;
          _isLoadingLibraryContent = false;
        });
      }
      _setupEmbyRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _embyError = e.toString();
          _isLoadingLibraryContent = false;
        });
      }
    }
  }

  // 返回库列表
  void _backToLibraries() {
    if (!mounted) return;
    setState(() {
      _selectedLibraryId = null;
      _isShowingLibraryContent = false;
      _embyMediaItems = [];
    });
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isShowingLibraryContent) {
        setState(() {
          _embyMediaItems = embyProvider.mediaItems;
        });
      }
    });
  }

  // 选择媒体库
  void _selectLibrary(EmbyLibrary library) {
    _loadLibraryContent(library.id);
  }

  void _setupEmbyRefreshTimer() {
    _embyRefreshTimer?.cancel();
    _embyRefreshTimer = Timer.periodic(const Duration(minutes: 60), (timer) {
      _loadEmbyData();
    });
  }

  Future<void> _showSortDialog() async {
    print('EmbyMediaLibraryView: 显示排序对话框');
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    // 获取当前上下文排序（库内容页用每库设置，否则用全局）
    Map<String, String> currentSortSettings;
    if (_isShowingLibraryContent && _selectedLibraryId != null) {
      currentSortSettings = embyProvider.getLibrarySortSettings(_selectedLibraryId!);
    } else {
      currentSortSettings = {
        'sortBy': embyProvider.currentSortBy,
        'sortOrder': embyProvider.currentSortOrder,
      };
    }
    
    final result = await EmbySortDialog.show(
      context,
      currentSortBy: currentSortSettings['sortBy']!,
      currentSortOrder: currentSortSettings['sortOrder']!,
    );
    
    if (result != null && mounted) {
      if (_isShowingLibraryContent && _selectedLibraryId != null) {
        // 保存当前媒体库的排序设置并重新加载
        embyProvider.setLibrarySortSettings(
          _selectedLibraryId!,
          result['sortBy']!,
          result['sortOrder']!,
        );
        _loadLibraryContent(_selectedLibraryId!);
      } else {
        // 更新全局排序设置但不立刻刷新局部（交由Provider触发）
        embyProvider.updateSortSettingsOnly(
          result['sortBy']!,
          result['sortOrder']!,
        );
      }
    } else {
      print('EmbyMediaLibraryView: 用户取消了排序设置');
    }
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

    // 根据状态选择展示：库列表或库内容
    if (_isShowingLibraryContent) {
      return _buildLibraryContentView(embyProvider, embyService);
    } else {
      return _buildLibrariesView(embyProvider, embyService);
    }
  }
}

// 库列表视图
extension _EmbyLibrariesView on _EmbyMediaLibraryViewState {
  Widget _buildLibrariesView(EmbyProvider embyProvider, EmbyService embyService) {
    final selectedLibraries = embyProvider.availableLibraries
        .where((library) => embyProvider.selectedLibraryIds.contains(library.id))
        .toList();

    if (selectedLibraries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '没有选中的媒体库。\n请在设置中选择要显示的媒体库。',
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

    return Stack(
      children: [
        RepaintBoundary(
          child: Platform.isAndroid || Platform.isIOS
              ? GridView.builder(
                  controller: _gridScrollController,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    childAspectRatio: 16 / 9,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  itemCount: selectedLibraries.length,
                  itemBuilder: (context, index) {
                    final library = selectedLibraries[index];
                    return EmbyLibraryCard(
                      key: ValueKey('library_${library.id}')
                      ,
                      library: library,
                      onTap: () => _selectLibrary(library),
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
                      maxCrossAxisExtent: 400,
                      childAspectRatio: 16 / 9,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    itemCount: selectedLibraries.length,
                    itemBuilder: (context, index) {
                      final library = selectedLibraries[index];
                      return EmbyLibraryCard(
                        key: ValueKey('library_${library.id}')
                        ,
                        library: library,
                        onTap: () => _selectLibrary(library),
                      );
                    },
                  ),
                ),
        ),
        // 设置按钮
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

// 库内容视图
extension _EmbyLibraryContentView on _EmbyMediaLibraryViewState {
  Widget _buildLibraryContentView(EmbyProvider embyProvider, EmbyService embyService) {
    if (_isLoadingLibraryContent) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_embyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载媒体库内容失败: $_embyError', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => _loadLibraryContent(_selectedLibraryId!),
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _backToLibraries,
                    child: const Text('返回'),
                  ),
                ],
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
                '该媒体库为空。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _backToLibraries,
                child: const Text('返回媒体库列表'),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer<EmbyProvider>(
      builder: (context, embyProvider, child) {
        return Stack(
          children: [
            Column(
              children: [
                // 顶部导航栏
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: _backToLibraries,
                                child: const Center(
                                  child: Icon(
                                    Icons.chevron_left,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _getSelectedLibraryName(embyProvider),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // 内容网格
                Expanded(
                  child: RepaintBoundary(
                    child: Platform.isAndroid || Platform.isIOS
                        ? GridView.builder(
                            controller: _gridScrollController,
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 150,
                              childAspectRatio: 7 / 12,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            padding: const EdgeInsets.all(16),
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
                              padding: const EdgeInsets.all(16),
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
                ),
              ],
            ),
            // 排序按钮（库内容页显示）
            Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionGlassButton(
                iconData: Ionicons.funnel_outline,
                onPressed: _showSortDialog,
                description: 'Emby排序设置\n选择排序方式和顺序\n支持多种排序选项',
              ),
            ),
            // 设置按钮
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
      },
    );
  }

  String _getSelectedLibraryName(EmbyProvider embyProvider) {
    if (_selectedLibraryId == null) return '媒体库';
    final libs = embyProvider.availableLibraries.where((l) => l.id == _selectedLibraryId);
    if (libs.isEmpty) return '媒体库';
    return libs.first.name;
  }
}
