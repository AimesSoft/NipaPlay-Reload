import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/local_library_control_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/search_bar_action_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/floating_action_glass_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_library_sort_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/jellyfin_library_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/emby_library_card.dart';
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
  bool get isFolder;
  String? get progress; // 新增
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
  @override
  bool get isFolder => _item.isFolder;
  
  @override
  String? get progress {
    if (_item.userData?.played == true) return '已看完';
    // Jellyfin 列表接口可能不返回具体的播放进度集数，如果需要更详细的可以后续扩展
    return null;
  }
  
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
  @override
  bool get isFolder => _item.isFolder;

  @override
  String? get progress {
    if (_item.userData?.played == true) return '已看完';
    return null;
  }
  
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
  bool _isFolderNavigation = false;
  final List<_FolderNode> _folderStack = [];
  
  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  LocalLibrarySortType _currentSort = LocalLibrarySortType.dateAdded;
  bool _isSearching = false;
  bool _isSearchLoading = false;
  List<NetworkMediaItem> _searchResults = [];
  List<NetworkMediaItem> _filteredMediaItems = [];
  Timer? _searchDebounceTimer;

  void _applySortAndFilter() {
    if (!mounted) return;
    setState(() {
      String query = _searchController.text.toLowerCase().trim();
      
      // 基础过滤
      List<NetworkMediaItem> source = _mediaItems;
      if (query.isNotEmpty) {
        source = source.where((item) => item.title.toLowerCase().contains(query)).toList();
      }
      
      // 排序
      switch (_currentSort) {
        case LocalLibrarySortType.name:
          source.sort((a, b) => a.title.compareTo(b.title));
          break;
        case LocalLibrarySortType.dateAdded:
          // 远程服务目前没有统一的添加日期，这里暂不做变动或使用原始顺序
          break;
        case LocalLibrarySortType.rating:
          break;
      }
      _filteredMediaItems = source;
    });
  }

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
    _searchDebounceTimer?.cancel();
    _gridScrollController.dispose();
    _searchController.dispose();
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

  String? get _currentFolderId =>
      _folderStack.isNotEmpty ? _folderStack.last.id : null;

  bool get _isAtFolderRoot => _folderStack.length <= 1;

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
        Column(
          children: [
            // 主页面搜索栏
            _buildMainSearchBar(),
            // 媒体库网格或搜索结果
            Expanded(
              child: RepaintBoundary(
                child: Scrollbar(
                  controller: _gridScrollController,
                  thickness: 4,
                  radius: const Radius.circular(2),
                  child: _isSearching
                      ? GridView.builder(
                          controller: _gridScrollController,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 500,
                            mainAxisExtent: 140,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          padding: const EdgeInsets.all(16),
                          cacheExtent: 800,
                          clipBehavior: Clip.hardEdge,
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final item = _searchResults[index];
                            return _buildMediaCard(item);
                          },
                        )
                      : GridView.builder(
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
            ),
          ],
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
                    onTap: _retryCurrentView,
                  ),
                  const SizedBox(width: 16),
                  BlurButton(
                    icon: Icons.arrow_back,
                    text: '返回',
                    onTap: _handleBackNavigation,
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
              // 已整合返回按钮和标题的控制栏
              _buildSearchBar(),
              // 空内容提示
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isFolderNavigation ? '该文件夹为空。' : '该媒体库为空。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        BlurButton(
                          icon: Icons.arrow_back,
                          text: _isFolderNavigation && !_isAtFolderRoot
                              ? '返回上级文件夹'
                              : '返回媒体库列表',
                          onTap: _handleBackNavigation,
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
            // 搜索栏（在媒体库内容视图中显示，已整合返回按钮和标题）
            if (_isShowingLibraryContent) _buildSearchBar(),
            // 媒体内容网格/文件夹列表
            Expanded(
              child: RepaintBoundary(
                child: Scrollbar(
                  controller: _gridScrollController,
                  thickness: 4,
                  radius: const Radius.circular(2),
                  child: _isFolderNavigation
                      ? _buildFolderListView()
                                                                                                        : GridView.builder(
                                                                                                            controller: _gridScrollController,
                                                                                                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                                                                                              maxCrossAxisExtent: 500,
                                                                                                              mainAxisExtent: 140,
                                                                                                              crossAxisSpacing: 16,
                                                                                                              mainAxisSpacing: 16,
                                                                                                            ),
                                                                                                            padding: const EdgeInsets.all(16),
                                                                                                            cacheExtent: 800,
                                                                                                            clipBehavior: Clip.hardEdge,
                                                                                                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                                                                                            addAutomaticKeepAlives: false,
                                                                                                            addRepaintBoundaries: true,
                                                                                                            itemCount: _isSearching ? _searchResults.length : _filteredMediaItems.length,
                                                                                                            itemBuilder: (context, index) {
                                                                                                              final item = _isSearching ? _searchResults[index] : _filteredMediaItems[index];
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

  String _getCurrentViewTitle(dynamic provider) {
    if (_isFolderNavigation && _folderStack.isNotEmpty) {
      return _folderStack.last.name;
    }
    
    // 直接实现获取选中媒体库名称的逻辑
    try {
      final selectedLibraries = _getSelectedLibraries(provider);
      final currentLibrary = selectedLibraries.firstWhere(
        (l) => l.id == _selectedLibraryId,
        orElse: () => selectedLibraries.isNotEmpty ? selectedLibraries.first : selectedLibraries.first,
      );
      return currentLibrary.name;
    } catch (_) {
      return '媒体库';
    }
  }

  Widget _buildFloatingActionButtons() {
    final showSortButton =
        _isShowingLibraryContent && !_isSearching && !_isFolderNavigation;
    if (!showSortButton) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 排序按钮（仅在显示库内容且未在搜索时显示）
          FloatingActionGlassButton(
            iconData: Ionicons.swap_vertical_outline,
            onPressed: _showSortDialog,
            description: '排序选项\n按名称、日期或评分排序\n提升浏览体验',
          ),
        ],
      ),
    );
  }

  Widget _buildServerSettingsAction() {
    return SearchBarActionButton(
      icon: Ionicons.settings_outline,
      tooltip: '$_serverName服务器设置',
      onPressed: _showServerDialog,
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

    return HorizontalAnimeCard(
      key: ValueKey(uniqueId),
      title: item.title,
      imageUrl: imageUrl,
      source: _serverName,
      rating: item.userRating,
      onTap: () => _openMediaDetail(item),
      summary: item.overview,
      progress: item.progress,
    );
  }

  Widget _buildFolderListView() {
    final items = _isSearching ? _searchResults : _mediaItems;

    return ListView.separated(
      controller: _gridScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        color: Colors.white12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final icon = item.isFolder
            ? Ionicons.folder_outline
            : Ionicons.play_circle_outline;

        return ListTile(
          dense: true,
          leading: Icon(icon, color: Colors.white70, size: 20),
          title: Text(
            item.title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: item.isFolder
              ? null
              : const Text(
                  '点击查看详情',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
          onTap: () => _openMediaDetail(item),
        );
      },
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
          _isFolderNavigation = false;
          _folderStack.clear();
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
          _applySortAndFilter();
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

  // 构建搜索栏（单个媒体库视图）
  Widget _buildSearchBar() {
    String? title;
    if (_isShowingLibraryContent) {
      title = _getCurrentViewTitle(_provider);
    }

    return LocalLibraryControlBar(
      showBackButton: _isShowingLibraryContent,
      onBack: _handleBackNavigation,
      title: title,
      searchController: _searchController,
      currentSort: _currentSort,
      onSearchChanged: _onSearchChanged,
      onSortChanged: (type) {
        setState(() => _currentSort = type);
        _applySortAndFilter();
      },
      trailingActions: [
        _buildServerSettingsAction(),
      ],
    );
  }

  // 构建主页面搜索栏（媒体库列表视图）
  Widget _buildMainSearchBar() {
    return LocalLibraryControlBar(
      searchController: _searchController,
      currentSort: _currentSort,
      onSearchChanged: _onMainSearchChanged,
      onSortChanged: (type) {
        setState(() => _currentSort = type);
        _applySortAndFilter();
      },
      trailingActions: [
        _buildServerSettingsAction(),
      ],
    );
  }

  // 搜索输入变化处理（单个媒体库）
  void _onSearchChanged(String query) {
    // 取消之前的搜索定时器
    _searchDebounceTimer?.cancel();
    
    if (_isFolderNavigation) {
      if (query.isEmpty) {
        setState(() {
          _isSearching = false;
          _searchResults.clear();
          _isSearchLoading = false;
        });
        return;
      }

      final keyword = query.trim().toLowerCase();
      final results = _mediaItems
          .where((item) => item.title.toLowerCase().contains(keyword))
          .toList();

      setState(() {
        _isSearching = true;
        _searchResults = results;
        _isSearchLoading = false;
      });
      return;
    }

    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults.clear();
        _isSearchLoading = false;
      });
      return;
    }

    setState(() {
      _isSearchLoading = true;
    });

    // 设置新的搜索定时器（防抖动）
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  // 主页面搜索输入变化处理（跨媒体库）
  void _onMainSearchChanged(String query) {
    // 取消之前的搜索定时器
    _searchDebounceTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults.clear();
        _isSearchLoading = false;
      });
      return;
    }

    setState(() {
      _isSearchLoading = true;
    });

    // 设置新的搜索定时器（防抖动）
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performCrossLibrarySearch(query);
    });
  }

  // 执行搜索（单个媒体库）
  Future<void> _performSearch(String query) async {
    if (!mounted || query.trim().isEmpty) return;

    try {
      final service = _service;
      List<dynamic> searchResults = [];

      switch (widget.serverType) {
        case NetworkMediaServerType.jellyfin:
          if (_selectedLibraryId != null) {
            searchResults = await (service as JellyfinService).searchInLibrary(
              _selectedLibraryId!,
              query,
              limit: 50,
            );
          } else {
            searchResults = await (service as JellyfinService).searchMediaItems(
              query,
              limit: 50,
            );
          }
          break;
        case NetworkMediaServerType.emby:
          if (_selectedLibraryId != null) {
            searchResults = await (service as EmbyService).searchInLibrary(
              _selectedLibraryId!,
              query,
              limit: 50,
            );
          } else {
            searchResults = await (service as EmbyService).searchMediaItems(
              query,
              limit: 50,
            );
          }
          break;
      }

      if (mounted) {
        setState(() {
          _isSearching = true;
          _searchResults = _convertToNetworkMediaItems(searchResults);
          _isSearchLoading = false;
        });

        debugPrint('[$_serverName] 搜索 "$query" 找到 ${_searchResults.length} 个结果');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchLoading = false;
          _error = '搜索失败: $e';
        });
      }
      debugPrint('[$_serverName] 搜索失败: $e');
    }
  }

  // 执行跨媒体库搜索
  Future<void> _performCrossLibrarySearch(String query) async {
    if (!mounted || query.trim().isEmpty) return;

    try {
      final service = _service;
      final provider = _provider;
      final selectedLibraries = _getSelectedLibraries(provider);
      List<dynamic> allSearchResults = [];

      // 遍历所有选中的媒体库
      for (final library in selectedLibraries) {
        if (library.type.toLowerCase() == 'mixed') {
          continue;
        }
        try {
          List<dynamic> libraryResults = [];
          
          switch (widget.serverType) {
            case NetworkMediaServerType.jellyfin:
              libraryResults = await (service as JellyfinService).searchInLibrary(
                library.id,
                query,
                limit: 50,
              );
              break;
            case NetworkMediaServerType.emby:
              libraryResults = await (service as EmbyService).searchInLibrary(
                library.id,
                query,
                limit: 50,
              );
              break;
          }
          
          allSearchResults.addAll(libraryResults);
          debugPrint('[$_serverName] 在媒体库 "${library.name}" 中搜索 "$query" 找到 ${libraryResults.length} 个结果');
        } catch (e) {
          debugPrint('[$_serverName] 在媒体库 "${library.name}" 中搜索失败: $e');
          // 继续搜索其他媒体库
        }
      }

      if (mounted) {
        setState(() {
          _isSearching = true;
          _searchResults = _convertToNetworkMediaItems(allSearchResults);
          _isSearchLoading = false;
        });

        debugPrint('[$_serverName] 跨媒体库搜索 "$query" 共找到 ${_searchResults.length} 个结果');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchLoading = false;
          _error = '跨媒体库搜索失败: $e';
        });
      }
      debugPrint('[$_serverName] 跨媒体库搜索失败: $e');
    }
  }

  // 清空搜索
  void _clearSearch() {
    _searchController.clear();
    _searchDebounceTimer?.cancel();
    setState(() {
      _isSearching = false;
      _searchResults.clear();
      _isSearchLoading = false;
    });
  }

  void _handleBackNavigation() {
    if (_isFolderNavigation && !_isAtFolderRoot) {
      _navigateUpFolder();
      return;
    }
    _backToLibraries();
  }

  void _navigateUpFolder() {
    if (_folderStack.length <= 1) {
      _backToLibraries();
      return;
    }

    _clearSearch();

    if (mounted) {
      setState(() {
        _folderStack.removeLast();
        _isLoadingLibraryContent = true;
        _error = null;
      });
    }

    final parentId = _currentFolderId;
    if (parentId != null) {
      _loadFolderItems(parentId);
    }
  }

  void _retryCurrentView() {
    if (_isFolderNavigation) {
      final folderId = _currentFolderId;
      if (folderId != null) {
        setState(() {
          _isLoadingLibraryContent = true;
          _error = null;
        });
        _loadFolderItems(folderId);
      }
      return;
    }

    if (_selectedLibraryId != null) {
      _loadLibraryContent(_selectedLibraryId!);
    }
  }

  // 返回媒体库列表
  void _backToLibraries() {
    _clearSearch();
    
    if (mounted) {
      setState(() {
        _selectedLibraryId = null;
        _isShowingLibraryContent = false;
        _isFolderNavigation = false;
        _folderStack.clear();
        _mediaItems.clear(); // 清空当前媒体项
        _error = null;
      });
      
      // 重新加载数据以同步最新的媒体库状态
      _loadData();
    }
  }

  // 选择媒体库
  void _selectLibrary(NetworkMediaLibrary library) {
    _clearSearch();

    final isMixedLibrary = library.type.toLowerCase() == 'mixed';
    setState(() {
      _selectedLibraryId = library.id;
      _isShowingLibraryContent = true;
      _isLoadingLibraryContent = true;
      _isFolderNavigation = isMixedLibrary;
      _mediaItems.clear();
      _error = null;
      _folderStack
        ..clear();
      if (isMixedLibrary) {
        _folderStack.add(_FolderNode(id: library.id, name: library.name));
      }
    });

    if (isMixedLibrary) {
      _loadFolderItems(library.id);
    } else {
      _loadLibraryContent(library.id);
    }
  }

  // 加载媒体库内容
  Future<void> _loadLibraryContent(String libraryId) async {
    if (!mounted) return;

    if (_isFolderNavigation) {
      await _loadFolderItems(libraryId);
      return;
    }

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
          _applySortAndFilter();
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

  Future<void> _loadFolderItems(String parentId) async {
    if (!mounted) return;

    if (mounted) {
      setState(() {
        _isLoadingLibraryContent = true;
        _error = null;
      });
    }

    try {
      final service = _service;
      List<dynamic> items;

      switch (widget.serverType) {
        case NetworkMediaServerType.jellyfin:
          items = await (service as JellyfinService).getFolderItems(
            parentId,
            limit: 99999,
          );
          break;
        case NetworkMediaServerType.emby:
          items = await (service as EmbyService).getFolderItems(
            parentId,
            limit: 99999,
          );
          break;
      }

      if (mounted) {
        setState(() {
          _mediaItems = _convertToNetworkMediaItems(items);
          _applySortAndFilter();
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
      if (_isShowingLibraryContent) {
        if (_isFolderNavigation) {
          final folderId = _currentFolderId ?? _selectedLibraryId;
          if (folderId != null) {
            _loadFolderItems(folderId);
          }
        } else if (_selectedLibraryId != null) {
          _loadLibraryContent(_selectedLibraryId!);
        }
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
  Future<void> _openMediaDetail(NetworkMediaItem item) async {
    if (_isFolderNavigation && item.isFolder) {
      _enterFolder(item);
      return;
    }

    switch (widget.serverType) {
      case NetworkMediaServerType.jellyfin:
        final jellyfinItem = (item as JellyfinMediaItemAdapter).originalItem;
        final result =
            await MediaServerDetailPage.showJellyfin(context, jellyfinItem.id);
        if (result != null && result.filePath.isNotEmpty) {
          widget.onPlayEpisode?.call(result);
        }
        break;
      case NetworkMediaServerType.emby:
        final embyItem = (item as EmbyMediaItemAdapter).originalItem;
        final result =
            await MediaServerDetailPage.showEmby(context, embyItem.id);
        if (result != null && result.filePath.isNotEmpty) {
          widget.onPlayEpisode?.call(result);
        }
        break;
    }
  }

  void _enterFolder(NetworkMediaItem item) {
    _clearSearch();

    if (mounted) {
      setState(() {
        _isLoadingLibraryContent = true;
        _error = null;
        _folderStack.add(_FolderNode(id: item.id, name: item.title));
      });
    }

    _loadFolderItems(item.id);
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

class _FolderNode {
  final String id;
  final String name;

  const _FolderNode({
    required this.id,
    required this.name,
  });
}
