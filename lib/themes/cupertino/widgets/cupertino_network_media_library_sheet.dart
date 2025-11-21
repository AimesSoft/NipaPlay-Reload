import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_anime_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';

class CupertinoNetworkMediaLibrarySheet extends StatefulWidget {
  const CupertinoNetworkMediaLibrarySheet({
    super.key,
    required this.jellyfinProvider,
    required this.embyProvider,
    required this.onOpenDetail,
    this.initialServer,
  });

  final JellyfinProvider jellyfinProvider;
  final EmbyProvider embyProvider;
  final MediaServerType? initialServer;
  final Future<void> Function(MediaServerType type, String id) onOpenDetail;

  @override
  State<CupertinoNetworkMediaLibrarySheet> createState() =>
      _CupertinoNetworkMediaLibrarySheetState();
}

class _CupertinoNetworkMediaLibrarySheetState
    extends State<CupertinoNetworkMediaLibrarySheet> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  late MediaServerType _activeServer;
  final DateFormat _dateFormatter = DateFormat('MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _activeServer = _resolveInitialServer();
    widget.jellyfinProvider.addListener(_handleProviderChanged);
    widget.embyProvider.addListener(_handleProviderChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    widget.jellyfinProvider.removeListener(_handleProviderChanged);
    widget.embyProvider.removeListener(_handleProviderChanged);
    super.dispose();
  }

  MediaServerType _resolveInitialServer() {
    final initial = widget.initialServer;
    if (initial != null) {
      if (initial == MediaServerType.jellyfin &&
          widget.jellyfinProvider.isConnected) {
        return initial;
      }
      if (initial == MediaServerType.emby &&
          widget.embyProvider.isConnected) {
        return initial;
      }
    }
    if (widget.jellyfinProvider.isConnected) {
      return MediaServerType.jellyfin;
    }
    return MediaServerType.emby;
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  void _handleProviderChanged() {
    if (!mounted) return;
    setState(_ensureActiveServer);
  }

  void _ensureActiveServer() {
    if (_activeServer == MediaServerType.jellyfin &&
        !widget.jellyfinProvider.isConnected &&
        widget.embyProvider.isConnected) {
      _activeServer = MediaServerType.emby;
    } else if (_activeServer == MediaServerType.emby &&
        !widget.embyProvider.isConnected &&
        widget.jellyfinProvider.isConnected) {
      _activeServer = MediaServerType.jellyfin;
    }
  }

  Future<void> _handleRefresh() async {
    if (_activeServer == MediaServerType.jellyfin) {
      if (widget.jellyfinProvider.isConnected) {
        await widget.jellyfinProvider.loadMediaItems();
        await widget.jellyfinProvider.loadMovieItems();
      }
    } else {
      if (widget.embyProvider.isConnected) {
        await widget.embyProvider.loadMediaItems();
        await widget.embyProvider.loadMovieItems();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureActiveServer();

    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double titleOpacity = (1.0 - (_scrollOffset / 12.0)).clamp(0.0, 1.0);

    final bool jellyfinConnected = widget.jellyfinProvider.isConnected;
    final bool embyConnected = widget.embyProvider.isConnected;
    final bool showSegmented = jellyfinConnected && embyConnected;

    final bool isJellyfinActive =
        _activeServer == MediaServerType.jellyfin;
    final bool connected = isJellyfinActive
        ? jellyfinConnected
        : embyConnected;
    final bool isLoading = isJellyfinActive
        ? widget.jellyfinProvider.isLoading
        : widget.embyProvider.isLoading;
    final bool hasError = isJellyfinActive
        ? widget.jellyfinProvider.hasError &&
            widget.jellyfinProvider.errorMessage != null
        : widget.embyProvider.hasError &&
            widget.embyProvider.errorMessage != null;
    final String? errorMessage = isJellyfinActive
        ? widget.jellyfinProvider.errorMessage
        : widget.embyProvider.errorMessage;

    final List<dynamic> mediaItems = (isJellyfinActive
            ? widget.jellyfinProvider.mediaItems
            : widget.embyProvider.mediaItems)
        .take(60)
        .toList();

    return CupertinoBottomSheetContentLayout(
      controller: _scrollController,
      backgroundColor: backgroundColor,
      floatingTitleOpacity: titleOpacity,
      sliversBuilder: (context, topSpacing) {
        if (!connected) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '当前服务器未连接，请返回重新选择。',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel,
                      context,
                    ),
                  ),
                ),
              ),
            ),
          ];
        }

        if (isLoading && mediaItems.isEmpty) {
          return [
            CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CupertinoActivityIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载远程媒体库...'),
                ],
              ),
            ),
          ];
        }

        if (hasError && mediaItems.isEmpty) {
          return [
            CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      size: 42,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemOrange,
                        context,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      errorMessage ?? '加载失败',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    CupertinoButton(
                      onPressed: _handleRefresh,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ];
        }

        if (mediaItems.isEmpty) {
          return [
            CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.collections,
                    size: 48,
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.inactiveGray,
                      context,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('暂未获取到远程媒体条目'),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    onPressed: _handleRefresh,
                    child: const Text('刷新'),
                  ),
                ],
              ),
            ),
          ];
        }

        final List<Widget> slivers = [
          CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
        ];

        if (showSegmented) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
                child: CupertinoSlidingSegmentedControl<MediaServerType>(
                  groupValue: _activeServer,
                  children: const {
                    MediaServerType.jellyfin: Text('Jellyfin'),
                    MediaServerType.emby: Text('Emby'),
                  },
                  onValueChanged: (value) {
                    if (value == null || value == _activeServer) return;
                    setState(() {
                      _activeServer = value;
                    });
                  },
                ),
              ),
            ),
          );
        }

        if (isLoading) {
          slivers.add(
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: CupertinoActivityIndicator(radius: 9),
                ),
              ),
            ),
          );
        }

        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, showSegmented ? 0 : topSpacing, 20, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = mediaItems[index];
                  if (_activeServer == MediaServerType.jellyfin) {
                    return _buildJellyfinCard(item as JellyfinMediaItem);
                  }
                  return _buildEmbyCard(item as EmbyMediaItem);
                },
                childCount: mediaItems.length,
              ),
            ),
          ),
        );

        return slivers;
      },
    );
  }

  Widget _buildJellyfinCard(JellyfinMediaItem item) {
    final imageUrl = widget.jellyfinProvider.getImageUrl(
      item.id,
      type: 'Primary',
      width: 360,
      quality: 90,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoAnimeCard(
        title: item.name,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        episodeLabel: '收录于 ${_dateFormatter.format(item.dateAdded.toLocal())}',
        lastWatchTime: item.dateAdded,
        sourceLabel: 'Jellyfin',
        rating: double.tryParse(item.communityRating ?? ''),
        summary: item.overview,
        onTap: () => widget.onOpenDetail(MediaServerType.jellyfin, item.id),
      ),
    );
  }

  Widget _buildEmbyCard(EmbyMediaItem item) {
    final imageUrl = widget.embyProvider.getImageUrl(
      item.id,
      type: 'Primary',
      width: 360,
      quality: 90,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoAnimeCard(
        title: item.name,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        episodeLabel: '收录于 ${_dateFormatter.format(item.dateAdded.toLocal())}',
        lastWatchTime: item.dateAdded,
        sourceLabel: 'Emby',
        rating: double.tryParse(item.communityRating ?? ''),
        summary: item.overview,
        onTap: () => widget.onOpenDetail(MediaServerType.emby, item.id),
      ),
    );
  }
}
