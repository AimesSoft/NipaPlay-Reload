import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/jellyfin_detail_page.dart';
import 'package:nipaplay/pages/emby_detail_page.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/media_library_sort_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/jellyfin_library_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/emby_library_card.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

enum NetworkMediaServerType { jellyfin, emby }

// 通用媒体项接口
abstract class NetworkMediaItem {
  String get id;
  String get title;
  String? get imagePath;
  String? get overview;
  int? get episodeCount;
  int? get watchedEpisodeCount;
  double? get userRating;
}

// 通用媒体库接口
abstract class NetworkMediaLibrary {
  String get id;
  String get name;
  String get type;
}

// Jellyfin适配器
class JellyfinMediaItemAdapter implements NetworkMediaItem {
  final JellyfinMediaItem _item;
  JellyfinMediaItemAdapter(this._item);
  
  @override
  String get id => _item.id;
  @override
  String get title => _item.name;
  @override
  String? get imagePath => _item.imagePrimaryTag;
  @override
  String? get overview => _item.overview;
  @override
  int? get episodeCount => null; // Jellyfin doesn't have this field directly
  @override
  int? get watchedEpisodeCount => null; // Jellyfin doesn't have this field directly
  @override
  double? get userRating => null; // Convert from string if needed
  
  JellyfinMediaItem get originalItem => _item;
}

class JellyfinLibraryAdapter implements NetworkMediaLibrary {
  final JellyfinLibrary _library;
  JellyfinLibraryAdapter(this._library);
  
  @override
  String get id => _library.id;
  @override
  String get name => _library.name;
  @override
  String get type => _library.type ?? 'unknown';
  
  JellyfinLibrary get originalLibrary => _library;
}

// Emby适配器
class EmbyMediaItemAdapter implements NetworkMediaItem {
  final EmbyMediaItem _item;
  EmbyMediaItemAdapter(this._item);
  
  @override
  String get id => _item.id;
  @override
  String get title => _item.name;
  @override
  String? get imagePath => _item.imagePrimaryTag;
  @override
  String? get overview => _item.overview;
  @override
  int? get episodeCount => null; // Emby doesn't have this field directly
  @override
  int? get watchedEpisodeCount => null; // Emby doesn't have this field directly
  @override
  double? get userRating => null; // Convert from string if needed
  
  EmbyMediaItem get originalItem => _item;
}

class EmbyLibraryAdapter implements NetworkMediaLibrary {
  final EmbyLibrary _library;
  EmbyLibraryAdapter(this._library);
  
  @override
  String get id => _library.id;
  @override
  String get name => _library.name;
  @override
  String get type => _library.type ?? 'unknown';
  
  EmbyLibrary get originalLibrary => _library;
}

class NetworkMediaLibraryView extends StatefulWidget {
  final NetworkMediaServerType serverType;
  final void Function(WatchHistoryItem item)? onPlayEpisode;

  const NetworkMediaLibraryView({
    super.key,
    required this.serverType,
    this.onPlayEpisode,
  });

  @override
  State<NetworkMediaLibraryView> createState() => _NetworkMediaLibraryViewState();
}

class _NetworkMediaLibraryViewState extends State<NetworkMediaLibraryView> 
    with AutomaticKeepAliveClientMixin {
  
  List<NetworkMediaItem> _mediaItems = [];
  String? _error;
  Timer? _refreshTimer;
  final ScrollController _gridScrollController = ScrollController();
  
  // 库视图状态
  String? _selectedLibraryId;
  bool _isShowingLibraryContent = false;
  bool _isLoadingLibraryContent = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = _provider;
        provider.addListener(_onProviderChanged);
        _loadData(); // Initial load based on current provider state
      }
    });
  }

  @override
  void dispose() {
    try {
      if (mounted) {
        final provider = _provider;
        provider.removeListener(_onProviderChanged);
      }
    } catch (e) {
      // ignore: avoid_print
      print("Error removing Provider listener in NetworkMediaLibraryView: $e");
    }
    _refreshTimer?.cancel();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) {
      _loadData();
    }
  }

  // 获取对应的provider和service
  dynamic get _provider {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        return Provider.of<JellyfinProvider>(context, listen: false);
      case NetworkMediaServerType.emby:
        return Provider.of<EmbyProvider>(context, listen: false);
    }
  }

  dynamic get _service {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        return JellyfinService.instance;
      case NetworkMediaServerType.emby:
        return EmbyService.instance;
    }
  }

  String get _serverName {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        return 'Jellyfin';
      case NetworkMediaServerType.emby:
        return 'Emby';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final provider = _provider;
    final service = _service;

    if (!provider.isConnected || provider.selectedLibraryIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '媒体库为空。\n观看过的动画将显示在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              BlurButton(
                icon: Icons.cloud,
                text: '添加媒体服务器',
                onTap: _showServerDialog,
              ),
            ],
          ),
        ),
      );
    }

    // 根据当前状态决定显示内容
    if (_isShowingLibraryContent) {
      return _buildLibraryContentView(provider, service);
    } else {
      return _buildLibrariesView(provider, service);
    }
  }

  Widget _buildLibrariesView(dynamic provider, dynamic service) {
    final selectedLibraries = _getSelectedLibraries(provider);
    
    if (selectedLibraries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '没有可用的媒体库',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              BlurButton(
                icon: Icons.refresh,
                text: '刷新媒体库',
                onTap: () => _loadData(),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RepaintBoundary(
          child: Scrollbar(
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
              cacheExtent: 800,
              clipBehavior: Clip.hardEdge,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: selectedLibraries.length,
              itemBuilder: (context, index) {
                final library = selectedLibraries[index];
                return _buildLibraryCard(library);
              },
            ),
          ),
        ),
        // 右下角按钮组
        _buildFloatingActionButtons(),
      ],
    );
  }

  Widget _buildLibraryContentView(dynamic provider, dynamic service) {
    if (_isLoadingLibraryContent) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载媒体库内容失败: $_error', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BlurButton(
                    icon: Icons.refresh,
                    text: '重试',
                    onTap: () => _loadLibraryContent(_selectedLibraryId!),
                  ),
                  const SizedBox(width: 16),
                  BlurButton(
                    icon: Icons.arrow_back,
                    text: '返回',
                    onTap: _backToLibraries,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_mediaItems.isEmpty) {
      return Stack(
        children: [
          Column(
            children: [
              // 顶部导航栏
              _buildTopNavigationBar(provider),
              // 空内容提示
              Expanded(
                child: Center(
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
                        BlurButton(
                          icon: Icons.arrow_back,
                          text: '返回媒体库列表',
                          onTap: _backToLibraries,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _buildFloatingActionButtons(),
        ],
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // 顶部导航栏
            _buildTopNavigationBar(provider),
            // 媒体内容网格
            Expanded(
              child: RepaintBoundary(
                child: Scrollbar(
                  controller: _gridScrollController,
                  thickness: 4,
                  radius: const Radius.circular(2),
                  child: GridView.builder(
                    controller: _gridScrollController,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 150,
                      childAspectRatio: 7/12,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    padding: const EdgeInsets.all(16),
                    cacheExtent: 800,
                    clipBehavior: Clip.hardEdge,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemCount: _mediaItems.length,
                    itemBuilder: (context, index) {
                      final item = _mediaItems[index];
                      return _buildMediaCard(item);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        _buildFloatingActionButtons(),
      ],
    );
  }

  Widget _buildTopNavigationBar(dynamic provider) {
    return Container(
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(24), // 圆形
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
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
              _getSelectedLibraryName(provider),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 获取选中媒体库的名称
  String _getSelectedLibraryName(dynamic provider) {
    if (_selectedLibraryId == null) return '媒体库';
    
    final selectedLibraries = _getSelectedLibraries(provider);
    final library = selectedLibraries.where((lib) => lib.id == _selectedLibraryId);
    
    if (library.isEmpty) return '媒体库';
    
    return library.first.name;
  }

  Widget _buildFloatingActionButtons() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 排序按钮（仅在显示库内容时显示）
          if (_isShowingLibraryContent) ...[
            FloatingActionGlassButton(
              iconData: Ionicons.swap_vertical_outline,
              onPressed: _showSortDialog,
              description: '排序选项\n按名称、日期或评分排序\n提升浏览体验',
            ),
            const SizedBox(height: 16), // 按钮之间的间距
          ],
          // 设置按钮
          FloatingActionGlassButton(
            iconData: Ionicons.settings_outline,
            onPressed: _showServerDialog,
            description: '$_serverName服务器设置\n管理连接信息和媒体库\n配置播放偏好设置',
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryCard(NetworkMediaLibrary library) {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        final jellyfinLibrary = (library as JellyfinLibraryAdapter).originalLibrary;
        return JellyfinLibraryCard(
          key: ValueKey('library_${library.id}'),
          library: jellyfinLibrary,
          onTap: () => _selectLibrary(library),
        );
      case NetworkMediaServerType.emby:
        final embyLibrary = (library as EmbyLibraryAdapter).originalLibrary;
        return EmbyLibraryCard(
          key: ValueKey('library_${library.id}'),
          library: embyLibrary,
          onTap: () => _selectLibrary(library),
        );
    }
  }

  Widget _buildMediaCard(NetworkMediaItem item) {
    String imageUrl = '';
    String uniqueId = '';
    
    // 根据服务器类型获取正确的图片URL和唯一ID
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        final jellyfinItem = (item as JellyfinMediaItemAdapter).originalItem;
        uniqueId = 'jellyfin_${jellyfinItem.id}';
        imageUrl = jellyfinItem.imagePrimaryTag != null
            ? JellyfinService.instance.getImageUrl(jellyfinItem.id, width: 300)
            : '';
        break;
      case NetworkMediaServerType.emby:
        final embyItem = (item as EmbyMediaItemAdapter).originalItem;
        uniqueId = 'emby_${embyItem.id}';
        imageUrl = embyItem.imagePrimaryTag != null
            ? EmbyService.instance.getImageUrl(embyItem.id, width: 300)
            : '';
        break;
    }

    return AnimeCard(
      key: ValueKey(uniqueId),
      name: item.title,
      imageUrl: imageUrl,
      source: _serverName,
      useLegacyImageLoadMode: true, // 恢复旧版图片加载方式，减少并发请求
      // 在网格中使用轻微毛玻璃，实际是否启用由全局设置控制
      enableBackgroundBlur: true,
      backgroundBlurSigma: 6.0,
      enableShadow: false, // 网格中禁用阴影以降低绘制成本
      onTap: () => _openMediaDetail(item),
    );
  }

  // 获取选中的媒体库列表
  List<NetworkMediaLibrary> _getSelectedLibraries(dynamic provider) {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        final jellyfinProvider = provider as JellyfinProvider;
        return jellyfinProvider.availableLibraries
            .where((library) => jellyfinProvider.selectedLibraryIds.contains(library.id))
            .map((lib) => JellyfinLibraryAdapter(lib))
            .toList();
      case NetworkMediaServerType.emby:
        final embyProvider = provider as EmbyProvider;
        return embyProvider.availableLibraries
            .where((library) => embyProvider.selectedLibraryIds.contains(library.id))
            .map((lib) => EmbyLibraryAdapter(lib))
            .toList();
    }
  }

  // 加载数据
  Future<void> _loadData() async {
    if (!mounted) return;
    
    final provider = _provider;
    
    if (!provider.isConnected || provider.selectedLibraryIds.isEmpty) {
      if (mounted) {
        setState(() {
          _mediaItems.clear();
          _error = null;
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

    if (mounted) {
      setState(() {
        _error = null;
      });
    }

    try {
      final service = _service;
      List<dynamic> items;
      
      switch (widget.serverType) {
        case NetworkMediaServerType.jellyfin:
          items = await (service as JellyfinService).getLatestMediaItems(
            limit: 99999,
            sortBy: provider.currentSortBy,
            sortOrder: provider.currentSortOrder,
          );
          break;
        case NetworkMediaServerType.emby:
          items = await (service as EmbyService).getLatestMediaItems(
            limitPerLibrary: 99999,
            totalLimit: 99999,
            sortBy: provider.currentSortBy,
            sortOrder: provider.currentSortOrder,
          );
          break;
      }
      
      if (mounted && !_isShowingLibraryContent) {
        setState(() {
          _mediaItems = _convertToNetworkMediaItems(items);
        });
      }
      _setupRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  // 返回媒体库列表
  void _backToLibraries() {
    if (mounted) {
      setState(() {
        _selectedLibraryId = null;
        _isShowingLibraryContent = false;
        _mediaItems.clear(); // 清空当前媒体项
        _error = null;
      });
      
      // 重新加载数据以同步最新的媒体库状态
      _loadData();
    }
  }

  // 选择媒体库
  void _selectLibrary(NetworkMediaLibrary library) {
    setState(() {
      _selectedLibraryId = library.id;
      _isShowingLibraryContent = true;
      _isLoadingLibraryContent = true;
      _mediaItems.clear();
      _error = null;
    });
    
    _loadLibraryContent(library.id);
  }

  // 加载媒体库内容
  Future<void> _loadLibraryContent(String libraryId) async {
    if (!mounted) return;
    
    try {
      final service = _service;
      final provider = _provider;
      List<dynamic> items;
      
      // 获取该媒体库的排序设置
      final sortSettings = provider.getLibrarySortSettings(libraryId);
      
      switch (widget.serverType) {
        case NetworkMediaServerType.jellyfin:
          items = await (service as JellyfinService).getLatestMediaItemsByLibrary(
            libraryId,
            limit: 99999,
            sortBy: sortSettings['sortBy']!,
            sortOrder: sortSettings['sortOrder']!,
          );
          break;
        case NetworkMediaServerType.emby:
          items = await (service as EmbyService).getLatestMediaItemsByLibrary(
            libraryId,
            limit: 99999,
            sortBy: sortSettings['sortBy']!,
            sortOrder: sortSettings['sortOrder']!,
          );
          break;
      }
      
      if (mounted) {
        setState(() {
          _mediaItems = _convertToNetworkMediaItems(items);
          _isLoadingLibraryContent = false;
          _error = null;
        });
      }
      _setupRefreshTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingLibraryContent = false;
        });
      }
    }
  }

  // 设置刷新定时器
  void _setupRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 60), (timer) {
      if (_isShowingLibraryContent && _selectedLibraryId != null) {
        _loadLibraryContent(_selectedLibraryId!);
      } else {
        _loadData();
      }
    });
  }

  // 转换为通用媒体项
  List<NetworkMediaItem> _convertToNetworkMediaItems(List<dynamic> items) {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        return items.cast<JellyfinMediaItem>()
            .map((item) => JellyfinMediaItemAdapter(item))
            .toList();
      case NetworkMediaServerType.emby:
        return items.cast<EmbyMediaItem>()
            .map((item) => EmbyMediaItemAdapter(item))
            .toList();
    }
  }

  // 打开媒体详情
  void _openMediaDetail(NetworkMediaItem item) {
    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        final jellyfinItem = (item as JellyfinMediaItemAdapter).originalItem;
        JellyfinDetailPage.show(context, jellyfinItem.id).then((WatchHistoryItem? result) {
          if (result != null && result.filePath.isNotEmpty) {
            widget.onPlayEpisode?.call(result);
          }
        });
        break;
      case NetworkMediaServerType.emby:
        final embyItem = (item as EmbyMediaItemAdapter).originalItem;
        EmbyDetailPage.show(context, embyItem.id).then((WatchHistoryItem? result) {
          if (result != null && result.filePath.isNotEmpty) {
            widget.onPlayEpisode?.call(result);
          }
        });
        break;
    }
  }

  // 显示服务器设置对话框
  Future<void> _showServerDialog() async {
    final result = await NetworkMediaServerDialog.show(
      context, 
      widget.serverType == NetworkMediaServerType.jellyfin 
          ? MediaServerType.jellyfin 
          : MediaServerType.emby
    );
    if (result == true && mounted) {
      _loadData();
    }
  }

  // 显示排序对话框
  Future<void> _showSortDialog() async {
    final MediaLibraryType libraryType = widget.serverType == NetworkMediaServerType.jellyfin 
        ? MediaLibraryType.jellyfin 
        : MediaLibraryType.emby;
    
    final provider = _provider;
    
    // 获取当前媒体库的排序设置，如果没有则使用全局设置
    Map<String, String> currentSortSettings;
    if (_isShowingLibraryContent && _selectedLibraryId != null) {
      currentSortSettings = provider.getLibrarySortSettings(_selectedLibraryId!);
    } else {
      currentSortSettings = {
        'sortBy': provider.currentSortBy,
        'sortOrder': provider.currentSortOrder,
      };
    }
    
    final result = await MediaLibrarySortDialog.show(
      context, 
      currentSortBy: currentSortSettings['sortBy']!,
      currentSortOrder: currentSortSettings['sortOrder']!,
      libraryType: libraryType,
    );
    
    if (result != null && mounted) {
      if (_isShowingLibraryContent && _selectedLibraryId != null) {
        // 保存当前媒体库的排序设置
        provider.setLibrarySortSettings(
          _selectedLibraryId!,
          result['sortBy']!,
          result['sortOrder']!,
        );
        
        // 重新加载当前媒体库内容
        _loadLibraryContent(_selectedLibraryId!);
      } else {
        // 更新全局排序设置
        provider.updateSortSettingsOnly(
          result['sortBy']!,
          result['sortOrder']!,
        );
      }
    }
  }


}
