import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_glass_library_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_management_sheet.dart';

import 'cupertino_network_library_items_page.dart';

/// 网路媒体库服务器库列表页。
class CupertinoNetworkServerLibrariesPage extends StatefulWidget {
  const CupertinoNetworkServerLibrariesPage({
    super.key,
    required this.serverType,
    required this.onOpenDetail,
    this.onManageServer,
  });

  final MediaServerType serverType;
  final Future<void> Function(MediaServerType type, String mediaId) onOpenDetail;
  final Future<void> Function(MediaServerType type)? onManageServer;

  @override
  State<CupertinoNetworkServerLibrariesPage> createState() =>
      _CupertinoNetworkServerLibrariesPageState();
}

class _CupertinoNetworkServerLibrariesPageState
    extends State<CupertinoNetworkServerLibrariesPage> {
  bool _ensureTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLibraries());
  }

  Future<void> _ensureLibraries() async {
    if (_ensureTriggered) return;
    _ensureTriggered = true;
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        final provider = context.read<JellyfinProvider>();
        if (provider.availableLibraries.isEmpty) {
          await provider.refreshAvailableLibraries();
        }
        break;
      case MediaServerType.emby:
        final provider = context.read<EmbyProvider>();
        if (provider.availableLibraries.isEmpty) {
          await provider.refreshAvailableLibraries();
        }
        break;
    }
  }

  Color get _accentColor => widget.serverType == MediaServerType.jellyfin
      ? CupertinoColors.systemBlue
      : const Color(0xFF52B54B);

  String get _serverLabel =>
      widget.serverType == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';

  Future<void> _showManagementSheet() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => CupertinoNetworkMediaManagementSheet(
          serverType: widget.serverType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        return Consumer<JellyfinProvider>(
          builder: (context, provider, _) => _buildPage(
            context,
            backgroundColor: backgroundColor,
            isConnected: provider.isConnected,
            username: provider.username,
            serverUrl: provider.serverUrl,
            isLoading: provider.isLoading && provider.availableLibraries.isEmpty,
            error: provider.hasError ? provider.errorMessage : null,
            libraries: _mapJellyfinLibraries(provider),
            onRefresh: provider.refreshAvailableLibraries,
          ),
        );
      case MediaServerType.emby:
        return Consumer<EmbyProvider>(
          builder: (context, provider, _) => _buildPage(
            context,
            backgroundColor: backgroundColor,
            isConnected: provider.isConnected,
            username: provider.username,
            serverUrl: provider.serverUrl,
            isLoading: provider.isLoading && provider.availableLibraries.isEmpty,
            error: provider.hasError ? provider.errorMessage : null,
            libraries: _mapEmbyLibraries(provider),
            onRefresh: provider.refreshAvailableLibraries,
          ),
        );
    }
  }

  List<_NetworkLibraryCardData> _mapJellyfinLibraries(
    JellyfinProvider provider,
  ) {
    final libraries = provider.availableLibraries;
    final selectedIds = provider.selectedLibraryIds;
    
    // 只显示已选中的库，未选中时返回空列表
    if (selectedIds.isEmpty) {
      return [];
    }
    
    final filtered = libraries
        .where((library) => selectedIds.contains(library.id))
        .toList();
    
    return filtered
        .map(
          (library) => _NetworkLibraryCardData(
            id: library.id,
            name: library.name,
            itemCount: library.totalItems,
            subtitle: _resolveCollectionTypeLabel(library.type),
            imageUrl: provider.getLibraryImageUrl(library.id),
          ),
        )
        .toList();
  }

  List<_NetworkLibraryCardData> _mapEmbyLibraries(
    EmbyProvider provider,
  ) {
    final libraries = provider.availableLibraries;
    final selectedIds = provider.selectedLibraryIds;
    
    // 只显示已选中的库，未选中时返回空列表
    if (selectedIds.isEmpty) {
      return [];
    }
    
    final filtered = libraries
        .where((library) => selectedIds.contains(library.id))
        .toList();
    
    return filtered
        .map(
          (library) => _NetworkLibraryCardData(
            id: library.id,
            name: library.name,
            itemCount: library.totalItems,
            subtitle: _resolveCollectionTypeLabel(library.type),
            imageUrl: provider.getLibraryImageUrl(library.id),
          ),
        )
        .toList();
  }

  Widget _buildPage(
    BuildContext context, {
    required Color backgroundColor,
    required bool isConnected,
    required bool isLoading,
    required String? error,
    required String? username,
    required String? serverUrl,
    required List<_NetworkLibraryCardData> libraries,
    required Future<void> Function() onRefresh,
  }) {
    final List<Widget> slivers = [
      CupertinoSliverRefreshControl(onRefresh: onRefresh),
      // 顶部空间
      const SliverToBoxAdapter(
        child: SizedBox(height: 150),
      ),
    ];

    if (!isConnected) {
      slivers.add(
        _buildPlaceholder(
          context,
          icon: CupertinoIcons.cloud,
          title: '尚未连接$_serverLabel',
          message: '请返回上一页并完成服务器连接。',
        ),
      );
    } else if (isLoading) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    } else if (error != null && error.isNotEmpty && libraries.isEmpty) {
      slivers.add(
        _buildPlaceholder(
          context,
          icon: CupertinoIcons.exclamationmark_triangle,
          title: '加载失败',
          message: error,
        ),
      );
    } else if (libraries.isEmpty) {
      slivers.add(
        _buildPlaceholder(
          context,
          icon: CupertinoIcons.collections,
          title: '暂无可用媒体库',
          message: '请在服务器设置中选择至少一个媒体库。',
        ),
      );
    } else {
      slivers.add(_buildLibraryGrid(context, libraries));
    }

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: '我的 $_serverLabel',
        useNativeToolbar: true,
        actions: widget.onManageServer == null
            ? null
            : [
                AdaptiveAppBarAction(
                  iosSymbol: 'slider.horizontal.3',
                  icon: CupertinoIcons.slider_horizontal_3,
                  onPressed: _showManagementSheet,
                ),
              ],
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

  Widget _buildLibraryGrid(
    BuildContext context,
    List<_NetworkLibraryCardData> libraries,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final library = libraries[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                height: 200,
                child: CupertinoGlassLibraryCard(
                  title: library.name,
                  subtitle: library.subtitle,
                  imageUrl: library.imageUrl,
                  itemCount: library.itemCount,
                  accentColor: _accentColor,
                  onTap: () => _openLibrary(library),
                  showOverlay: false,
                  serverBrand: widget.serverType == MediaServerType.jellyfin
                      ? MediaServerBrand.jellyfin
                      : MediaServerBrand.emby,
                ),
              ),
            );
          },
          childCount: libraries.length,
        ),
      ),
    );
  }

  Widget _buildPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 44,
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.inactiveGray,
                context,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
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
          ],
        ),
      ),
    );
  }

  void _openLibrary(_NetworkLibraryCardData library) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CupertinoNetworkLibraryItemsPage(
          serverType: widget.serverType,
          libraryId: library.id,
          libraryName: library.name,
          librarySubtitle: library.subtitle,
          accentColor: _accentColor,
          onOpenDetail: widget.onOpenDetail,
        ),
      ),
    );
  }

  String? _resolveCollectionTypeLabel(String? type) {
    switch (type) {
      case 'tvshows':
        return '剧集库';
      case 'movies':
        return '电影库';
      case 'boxsets':
        return '合集';
      default:
        return null;
    }
  }
}

class _NetworkLibraryCardData {
  const _NetworkLibraryCardData({
    required this.id,
    required this.name,
    this.subtitle,
    this.imageUrl,
    this.itemCount,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? imageUrl;
  final int? itemCount;
}
