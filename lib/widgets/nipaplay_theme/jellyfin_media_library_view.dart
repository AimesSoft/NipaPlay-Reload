import 'dart:async';
import 'dart:io';
import 'dart:ui';
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
import 'package:nipaplay/widgets/nipaplay_theme/jellyfin_library_card.dart';
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
  String? _jellyfinError;
  Timer? _jellyfinRefreshTimer;
  final ScrollController _gridScrollController = ScrollController();
  
  // 新增状态变量
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
          _jellyfinError = null;
          _selectedLibraryId = null;
          _isShowingLibraryContent = false;
        });
      }
      return;
    }

    // 如果当前正在显示单个媒体库内容，不要重新加载全局内容
    if (_isShowingLibraryContent && _selectedLibraryId != null) {
      print('JellyfinMediaLibraryView: 当前正在显示单个媒体库内容，跳过全局加载');
      return;
    }

    if (mounted) {
      setState(() {
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
      if (mounted && !_isShowingLibraryContent) {
        setState(() {
          _jellyfinMediaItems = mediaItems;
        });
      }
      _setupJellyfinRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _jellyfinError = e.toString();
        });
      }
    }
  }

  // 新增方法：加载特定媒体库的内容
  Future<void> _loadLibraryContent(String libraryId) async {
    if (!mounted) return;

    final jellyfinService = JellyfinService.instance;
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    
    if (mounted) {
      setState(() {
        _isLoadingLibraryContent = true;
        _jellyfinError = null;
      });
    }

    try {
      // 获取该媒体库的排序设置
      final sortSettings = jellyfinProvider.getLibrarySortSettings(libraryId);
      
      final mediaItems = await jellyfinService.getLatestMediaItemsByLibrary(
        libraryId,
        limit: 99999,
        sortBy: sortSettings['sortBy']!,
        sortOrder: sortSettings['sortOrder']!,
      );
      
      if (mounted) {
        setState(() {
          _jellyfinMediaItems = mediaItems;
          _selectedLibraryId = libraryId;
          _isShowingLibraryContent = true;
          _isLoadingLibraryContent = false;
        });
      }
      _setupJellyfinRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _jellyfinError = e.toString();
          _isLoadingLibraryContent = false;
        });
      }
    }
  }

  // 新增方法：返回媒体库列表
  void _backToLibraries() {
    if (mounted) {
      setState(() {
        _selectedLibraryId = null;
        _isShowingLibraryContent = false;
        _jellyfinMediaItems = []; // 清空当前媒体项，强制重新同步
      });
      
      // 强制同步Provider的媒体项到本地状态
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isShowingLibraryContent) {
          setState(() {
            _jellyfinMediaItems = jellyfinProvider.mediaItems;
          });
        }
      });
    }
  }

  // 新增方法：选择媒体库
  void _selectLibrary(JellyfinLibrary library) {
    _loadLibraryContent(library.id);
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
    
    // 获取当前媒体库的排序设置，如果没有则使用全局设置
    Map<String, String> currentSortSettings;
    if (_isShowingLibraryContent && _selectedLibraryId != null) {
      currentSortSettings = jellyfinProvider.getLibrarySortSettings(_selectedLibraryId!);
      print('JellyfinMediaLibraryView: 当前媒体库 $_selectedLibraryId 的排序设置 - sortBy: ${currentSortSettings['sortBy']}, sortOrder: ${currentSortSettings['sortOrder']}');
    } else {
      currentSortSettings = {
        'sortBy': jellyfinProvider.currentSortBy,
        'sortOrder': jellyfinProvider.currentSortOrder,
      };
      print('JellyfinMediaLibraryView: 使用全局排序设置 - sortBy: ${currentSortSettings['sortBy']}, sortOrder: ${currentSortSettings['sortOrder']}');
    }
    
    final result = await JellyfinSortDialog.show(
      context,
      currentSortBy: currentSortSettings['sortBy']!,
      currentSortOrder: currentSortSettings['sortOrder']!,
    );
    
    if (result != null && mounted) {
      print('JellyfinMediaLibraryView: 用户选择了新的排序设置 - sortBy: ${result['sortBy']}, sortOrder: ${result['sortOrder']}');
      
      if (_isShowingLibraryContent && _selectedLibraryId != null) {
        // 保存当前媒体库的排序设置
        jellyfinProvider.setLibrarySortSettings(
          _selectedLibraryId!,
          result['sortBy']!,
          result['sortOrder']!,
        );
        
        // 重新加载当前媒体库内容
        _loadLibraryContent(_selectedLibraryId!);
      } else {
        // 更新全局排序设置
        jellyfinProvider.updateSortSettingsOnly(
          result['sortBy']!,
          result['sortOrder']!,
        );
      }
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

    // 根据当前状态决定显示内容
    if (_isShowingLibraryContent) {
      return _buildLibraryContentView(jellyfinProvider, jellyfinService);
    } else {
      return _buildLibrariesView(jellyfinProvider, jellyfinService);
    }
  }

  // 显示媒体库列表
  Widget _buildLibrariesView(JellyfinProvider jellyfinProvider, JellyfinService jellyfinService) {
    // 只显示用户选中的媒体库
    final selectedLibraries = jellyfinProvider.availableLibraries
        .where((library) => jellyfinProvider.selectedLibraryIds.contains(library.id))
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
                onPressed: _showJellyfinServerDialog,
                icon: const Icon(Icons.settings),
                label: const Text('设置Jellyfin服务器'),
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
                    maxCrossAxisExtent: 400, // 增大媒体库卡片
                    childAspectRatio: 16 / 9, // 长方形比例
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  itemCount: selectedLibraries.length,
                  itemBuilder: (context, index) {
                    final library = selectedLibraries[index];
                    return JellyfinLibraryCard(
                      key: ValueKey('library_${library.id}'),
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
                      maxCrossAxisExtent: 400, // 增大媒体库卡片
                      childAspectRatio: 16 / 9, // 长方形比例
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    itemCount: selectedLibraries.length,
                    itemBuilder: (context, index) {
                      final library = selectedLibraries[index];
                      return JellyfinLibraryCard(
                        key: ValueKey('library_${library.id}'),
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
            onPressed: _showJellyfinServerDialog,
            description: 'Jellyfin服务器设置\n管理连接信息和媒体库\n配置播放偏好设置',
          ),
        ),
      ],
    );
  }

  // 显示媒体库内容
  Widget _buildLibraryContentView(JellyfinProvider jellyfinProvider, JellyfinService jellyfinService) {
    if (_isLoadingLibraryContent) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_jellyfinError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载媒体库内容失败: $_jellyfinError', style: const TextStyle(color: Colors.white70)),
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

    if (_jellyfinMediaItems.isEmpty) {
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

    return Consumer<JellyfinProvider>(
      builder: (context, jellyfinProvider, child) {
        // 强化筛选：只有在显示媒体库列表时才同步Provider的媒体项
        // 当显示单个媒体库内容时，完全忽略Provider的全局媒体项，只使用本地的_jellyfinMediaItems
        if (!_isShowingLibraryContent && 
            _selectedLibraryId == null && 
            _jellyfinMediaItems != jellyfinProvider.mediaItems) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isShowingLibraryContent && _selectedLibraryId == null) {
              setState(() {
                _jellyfinMediaItems = jellyfinProvider.mediaItems;
              });
            }
          });
        }
        
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
                        borderRadius: BorderRadius.circular(24), // 圆形
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(24), // 圆形
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24), // 圆形
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
                          _getSelectedLibraryName(jellyfinProvider),
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
                // 媒体内容网格
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
                              padding: const EdgeInsets.all(16),
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
                ),
              ],
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

  // 获取选中媒体库的名称
  String _getSelectedLibraryName(JellyfinProvider jellyfinProvider) {
    if (_selectedLibraryId == null) return '媒体库';
    
    final libraries = jellyfinProvider.availableLibraries
        .where((lib) => lib.id == _selectedLibraryId);
    
    if (libraries.isEmpty) return '媒体库';
    
    return libraries.first.name;
  }
}