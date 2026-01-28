import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_library_sort_sheet.dart';

class CupertinoNetworkLibraryItemsPage extends StatefulWidget {
  const CupertinoNetworkLibraryItemsPage({
    super.key,
    required this.serverType,
    required this.libraryId,
    required this.libraryName,
    this.librarySubtitle,
    required this.accentColor,
    required this.onOpenDetail,
  });

  final MediaServerType serverType;
  final String libraryId;
  final String libraryName;
  final String? librarySubtitle;
  final Color accentColor;
  final Future<void> Function(MediaServerType type, String mediaId) onOpenDetail;

  @override
  State<CupertinoNetworkLibraryItemsPage> createState() =>
      _CupertinoNetworkLibraryItemsPageState();
}

enum _LibrarySort { recentlyAdded, nameAsc }

class _SortOption {
  const _SortOption({
    required this.sortBy,
    required this.sortOrder,
    required this.label,
  });

  final String sortBy;
  final String sortOrder;
  final String label;
}

class _CupertinoNetworkLibraryItemsPageState
    extends State<CupertinoNetworkLibraryItemsPage> {
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  bool _isLoading = true;
  String? _error;
  List<_NetworkMediaGridItem> _items = const [];
  _LibrarySort _currentSort = _LibrarySort.recentlyAdded;
  bool _isFolderNavigation = false;
  final List<_FolderNode> _folderStack = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItems());
  }

  String? get _currentFolderId =>
      _folderStack.isNotEmpty ? _folderStack.last.id : null;

  bool get _isAtFolderRoot => _folderStack.length <= 1;

  String get _currentTitle =>
      _isFolderNavigation && _folderStack.isNotEmpty
          ? _folderStack.last.name
          : widget.libraryName;

  _SortOption _resolveSortOption(_LibrarySort sort) {
    switch (sort) {
      case _LibrarySort.nameAsc:
        return const _SortOption(
          sortBy: 'SortName',
          sortOrder: 'Ascending',
          label: '名称 ↑',
        );
      case _LibrarySort.recentlyAdded:
        return const _SortOption(
          sortBy: 'DateCreated',
          sortOrder: 'Descending',
          label: '最新 ↓',
        );
    }
  }

  bool _isMixedLibrary() {
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        final provider = context.read<JellyfinProvider>();
        final library = provider.findLibrary(widget.libraryId);
        return library?.type?.toLowerCase() == 'mixed';
      case MediaServerType.emby:
        final provider = context.read<EmbyProvider>();
        final library = provider.findLibrary(widget.libraryId);
        return library?.type?.toLowerCase() == 'mixed';
    }
  }

  Future<void> _loadItems({_LibrarySort? nextSort}) async {
    if (_isMixedLibrary()) {
      if (!_isFolderNavigation) {
        _folderStack.clear();
      }
      _isFolderNavigation = true;
      if (_folderStack.isEmpty) {
        _folderStack.add(
          _FolderNode(id: widget.libraryId, name: widget.libraryName),
        );
      }
      await _loadFolderItems(_currentFolderId ?? widget.libraryId);
      return;
    }

    if (_isFolderNavigation) {
      _isFolderNavigation = false;
      _folderStack.clear();
    }

    final _LibrarySort targetSort = nextSort ?? _currentSort;
    final _SortOption option = _resolveSortOption(targetSort);

    setState(() {
      _isLoading = true;
      _error = null;
      _currentSort = targetSort;
    });

    try {
      switch (widget.serverType) {
        case MediaServerType.jellyfin:
          final provider = context.read<JellyfinProvider>();
          if (!provider.isConnected) {
            throw Exception('尚未连接 Jellyfin 服务器');
          }
          final mediaItems = await provider.fetchMediaItemsForLibrary(
            widget.libraryId,
            limit: 120,
            sortBy: option.sortBy,
            sortOrder: option.sortOrder,
          );
          final mapped = mediaItems
              .map(
                (item) => _NetworkMediaGridItem(
                  id: item.id,
                  title: item.name,
                  subtitle: _buildSubtitle(
                    communityRating: item.communityRating,
                    productionYear: item.productionYear,
                    dateAdded: item.dateAdded,
                  ),
                  imageUrl: (item.imagePrimaryTag?.isNotEmpty ?? false)
                      ? provider.getImageUrl(
                          item.id,
                          type: 'Primary',
                          width: 600,
                          quality: 90,
                        )
                      : null,
                  isFolder: item.isFolder,
                  type: item.type,
                ),
              )
              .toList();
          if (mounted) {
            setState(() {
              _items = mapped;
            });
          }
          break;
        case MediaServerType.emby:
          final provider = context.read<EmbyProvider>();
          if (!provider.isConnected) {
            throw Exception('尚未连接 Emby 服务器');
          }
          final mediaItems = await provider.fetchMediaItemsForLibrary(
            widget.libraryId,
            limit: 120,
            sortBy: option.sortBy,
            sortOrder: option.sortOrder,
          );
          final mapped = mediaItems
              .map(
                (item) => _NetworkMediaGridItem(
                  id: item.id,
                  title: item.name,
                  subtitle: _buildSubtitle(
                    communityRating: item.communityRating,
                    productionYear: item.productionYear,
                    dateAdded: item.dateAdded,
                  ),
                  imageUrl: (item.imagePrimaryTag?.isNotEmpty ?? false)
                      ? provider.getImageUrl(
                          item.id,
                          type: 'Primary',
                          width: 600,
                          quality: 90,
                        )
                      : null,
                  isFolder: item.isFolder,
                  type: item.type,
                ),
              )
              .toList();
          if (mounted) {
            setState(() {
              _items = mapped;
            });
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFolderItems(String parentId) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      switch (widget.serverType) {
        case MediaServerType.jellyfin:
          final provider = context.read<JellyfinProvider>();
          if (!provider.isConnected) {
            throw Exception('尚未连接 Jellyfin 服务器');
          }
          final items = await provider.fetchFolderItems(
            parentId,
            limit: 99999,
          );
          final mapped = items
              .map(
                (item) => _NetworkMediaGridItem(
                  id: item.id,
                  title: item.name,
                  subtitle: item.isFolder ? '文件夹' : '点击查看详情',
                  imageUrl: null,
                  isFolder: item.isFolder,
                  type: item.type,
                ),
              )
              .toList();
          if (mounted) {
            setState(() {
              _items = mapped;
            });
          }
          break;
        case MediaServerType.emby:
          final provider = context.read<EmbyProvider>();
          if (!provider.isConnected) {
            throw Exception('尚未连接 Emby 服务器');
          }
          final items = await provider.fetchFolderItems(
            parentId,
            limit: 99999,
          );
          final mapped = items
              .map(
                (item) => _NetworkMediaGridItem(
                  id: item.id,
                  title: item.name,
                  subtitle: item.isFolder ? '文件夹' : '点击查看详情',
                  imageUrl: null,
                  isFolder: item.isFolder,
                  type: item.type,
                ),
              )
              .toList();
          if (mounted) {
            setState(() {
              _items = mapped;
            });
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildSubtitle({
    String? communityRating,
    int? productionYear,
    DateTime? dateAdded,
  }) {
    final segments = <String>[];
    if (productionYear != null && productionYear > 0) {
      segments.add('$productionYear');
    }
    if (communityRating != null && communityRating.isNotEmpty) {
      segments.add('评分 ${communityRating}');
    }
    if (dateAdded != null) {
      segments.add('收录 ${_dateFormatter.format(dateAdded.toLocal())}');
    }
    return segments.isEmpty ? '点击查看详情' : segments.join(' · ');
  }

  Future<void> _handleRefresh() => _loadItems();

  Future<void> _showSortDialog() async {
    if (_isFolderNavigation) {
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => CupertinoMediaLibrarySortSheet(
          currentSortBy: _resolveSortOption(_currentSort).sortBy,
          currentSortOrder: _resolveSortOption(_currentSort).sortOrder,
          serverType: widget.serverType == MediaServerType.jellyfin
              ? 'jellyfin'
              : 'emby',
          onSortChanged: (sortBy, sortOrder) {
            // 根据选择更新排序
            if (sortBy == 'SortName' && sortOrder == 'Ascending') {
              _loadItems(nextSort: _LibrarySort.nameAsc);
            } else {
              _loadItems(nextSort: _LibrarySort.recentlyAdded);
            }
          },
        ),
      ),
    );
  }

  void _enterFolder(_NetworkMediaGridItem item) {
    if (!item.isFolder) return;
    setState(() {
      _folderStack.add(_FolderNode(id: item.id, name: item.title));
    });
    _loadFolderItems(item.id);
  }

  void _navigateUpFolder() {
    if (_folderStack.length <= 1) return;
    setState(() {
      _folderStack.removeLast();
    });
    final parentId = _currentFolderId ?? widget.libraryId;
    _loadFolderItems(parentId);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    final slivers = <Widget>[
      CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
      // 顶部空间
      const SliverToBoxAdapter(
        child: SizedBox(height: 160),
      ),
    ];

    if (_isLoading) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    } else if (_error != null) {
      slivers.add(_buildErrorPlaceholder(context, _error!));
    } else if (_items.isEmpty) {
      slivers.add(_buildEmptyPlaceholder(context));
    } else if (_isFolderNavigation) {
      slivers.add(_buildFolderList());
    } else {
      slivers.add(_buildGrid());
    }

    final actions = <AdaptiveAppBarAction>[];
    if (_isFolderNavigation) {
      if (!_isAtFolderRoot) {
        actions.add(
          AdaptiveAppBarAction(
            iosSymbol: 'chevron.up',
            icon: CupertinoIcons.chevron_up,
            onPressed: _navigateUpFolder,
          ),
        );
      }
    } else {
      actions.add(
        AdaptiveAppBarAction(
          iosSymbol: 'line.horizontal.3.decrease',
          icon: CupertinoIcons.line_horizontal_3_decrease,
          onPressed: _showSortDialog,
        ),
      );
    }

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: _currentTitle,
        useNativeToolbar: true,
        actions: actions.isEmpty ? null : actions,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: slivers,
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.6,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = _items[index];
            return _NetworkMediaPoster(
              title: item.title,
              subtitle: item.subtitle,
              imageUrl: item.imageUrl,
              accentColor: widget.accentColor,
              onTap: () => widget.onOpenDetail(widget.serverType, item.id),
            );
          },
          childCount: _items.length,
        ),
      ),
    );
  }

  Widget _buildFolderList() {
    final hasParent = !_isAtFolderRoot;
    final totalCount = _items.length + (hasParent ? 1 : 0);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (hasParent && index == 0) {
              return _buildFolderUpTile(context);
            }
            final itemIndex = hasParent ? index - 1 : index;
            final item = _items[itemIndex];
            return _buildFolderItemTile(context, item);
          },
          childCount: totalCount,
        ),
      ),
    );
  }

  Widget _buildFolderUpTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdaptiveListTile(
        leading: const Icon(CupertinoIcons.chevron_up, size: 20),
        title: const Text('返回上级文件夹'),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
        onTap: _navigateUpFolder,
      ),
    );
  }

  Widget _buildFolderItemTile(
    BuildContext context,
    _NetworkMediaGridItem item,
  ) {
    final isFolder = item.isFolder;
    final IconData icon = isFolder
        ? CupertinoIcons.folder
        : CupertinoIcons.play_circle;
    final IconData? trailingIcon =
        isFolder ? CupertinoIcons.chevron_forward : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdaptiveListTile(
        leading: Icon(icon, size: 20),
        title: Text(item.title),
        subtitle: isFolder ? const Text('文件夹') : const Text('点击查看详情'),
        trailing:
            trailingIcon == null ? null : Icon(trailingIcon, size: 16),
        onTap: () {
          if (isFolder) {
            _enterFolder(item);
            return;
          }
          widget.onOpenDetail(widget.serverType, item.id);
        },
      ),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context, String message) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 44,
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemOrange,
                context,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 20),
            CupertinoButton(
              onPressed: _loadItems,
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(BuildContext context) {
    final bool canNavigateUp = _isFolderNavigation && !_isAtFolderRoot;
    final String title = _isFolderNavigation ? '当前文件夹暂无内容' : '当前媒体库暂无内容';
    final String message = _isFolderNavigation
        ? '可以返回上级文件夹继续浏览。'
        : '请登录 Jellyfin/Emby 管理后台确认该媒体库是否包含内容。';

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.collections,
              size: 44,
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.inactiveGray,
                context,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.35),
            ),
            if (canNavigateUp) ...[
              const SizedBox(height: 16),
              CupertinoButton(
                onPressed: _navigateUpFolder,
                child: const Text('返回上级文件夹'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NetworkMediaGridItem {
  const _NetworkMediaGridItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.isFolder = false,
    this.type,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isFolder;
  final String? type;
}

class _NetworkMediaPoster extends StatelessWidget {
  const _NetworkMediaPoster({
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: imageUrl?.isNotEmpty == true
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  accentColor.withValues(alpha: 0.35),
                                  accentColor.withValues(alpha: 0.1),
                                ],
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0x00111111),
                            CupertinoColors.black.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondaryLabel,
                context,
              ),
            ),
          ),
        ],
      ),
    );
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
