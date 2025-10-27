import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_bottom_sheet.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_anime_card.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_glass_media_server_card.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_shared_anime_detail_page.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_network_media_management_sheet.dart';
import 'package:nipaplay/pages/cupertino/network_media/cupertino_network_server_libraries_page.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/local_media_share_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/utils/android_storage_helper.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_server_dialog.dart' show MediaServerType;

// ignore_for_file: prefer_const_constructors

class CupertinoMediaLibraryPage extends StatefulWidget {
  const CupertinoMediaLibraryPage({super.key});

  @override
  State<CupertinoMediaLibraryPage> createState() =>
      _CupertinoMediaLibraryPageState();
}

class _CupertinoMediaLibraryPageState extends State<CupertinoMediaLibraryPage> {
  final ScrollController _scrollController = ScrollController();
  final DateFormat _timeFormatter = DateFormat('MM-dd HH:mm');
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    const cardColor = CupertinoColors.secondarySystemBackground;

    final titleOpacity = (1.0 - (_scrollOffset / 10.0)).clamp(0.0, 1.0);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          Consumer3<SharedRemoteLibraryProvider, JellyfinProvider,
              EmbyProvider>(
            builder:
                (context, sharedProvider, jellyfinProvider, embyProvider, _) {
              return CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(top: statusBarHeight + 52),
                    sliver: CupertinoSliverRefreshControl(
                      onRefresh: () => _refreshActiveHost(sharedProvider),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSectionTitle('本地媒体库'),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: CupertinoLocalMediaLibraryCard(
                        onViewLibrary: _showLocalMediaLibraryBottomSheet,
                        onManageLibrary: _showLibraryManagementBottomSheet,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 12),
                  ),
                  ..._buildNetworkMediaSection(
                    context,
                    jellyfinProvider,
                    embyProvider,
                  ),
                  SliverToBoxAdapter(
                    child: _buildSectionTitle('NipaPlay 共享媒体库'),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildHostCard(context, sharedProvider, cardColor),
                    ),
                  ),
                  if (sharedProvider.errorMessage != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _buildErrorBanner(
                            context, sharedProvider, cardColor),
                      ),
                    ),
                  ..._buildLibrarySlivers(context, sharedProvider, cardColor),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                ],
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      backgroundColor,
                      backgroundColor.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    '媒体库',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNetworkMediaSection(
    BuildContext context,
    JellyfinProvider jellyfinProvider,
    EmbyProvider embyProvider,
  ) {
    final bool jellyfinConnected = jellyfinProvider.isConnected;
    final bool embyConnected = embyProvider.isConnected;
    final List<Widget> slivers = [];

    final List<Widget> cards = [];

    if (jellyfinConnected) {
      final List<String> selected =
          _resolveSelectedLibraryNames<JellyfinLibrary>(
        jellyfinProvider.availableLibraries,
        jellyfinProvider.selectedLibraryIds,
        (library) => library.id,
        (library) => library.name,
      );
      cards.add(
        CupertinoGlassMediaServerCard(
          title: 'Jellyfin 媒体库',
          subtitle: _formatServerSubtitle(
            jellyfinProvider.username,
            jellyfinProvider.serverUrl,
          ),
          icon: CupertinoIcons.tv,
          accentColor: CupertinoColors.systemBlue,
          libraryNames: selected,
          isLoading: jellyfinProvider.isLoading,
          onTap: () => _openNetworkServerLibrariesPage(
            MediaServerType.jellyfin,
          ),
          onManage: () => _showNetworkServerDialog(MediaServerType.jellyfin),
        ),
      );
    }

    if (embyConnected) {
      final List<String> selected = _resolveSelectedLibraryNames<EmbyLibrary>(
        embyProvider.availableLibraries,
        embyProvider.selectedLibraryIds,
        (library) => library.id,
        (library) => library.name,
      );
      cards.add(
        CupertinoGlassMediaServerCard(
          title: 'Emby 媒体库',
          subtitle: _formatServerSubtitle(
            embyProvider.username,
            embyProvider.serverUrl,
          ),
          icon: CupertinoIcons.play_rectangle,
          accentColor: const Color(0xFF52B54B),
          libraryNames: selected,
          isLoading: embyProvider.isLoading,
          onTap: () => _openNetworkServerLibrariesPage(
            MediaServerType.emby,
          ),
          onManage: () => _showNetworkServerDialog(MediaServerType.emby),
        ),
      );
    }

    if (cards.isEmpty) {
      return slivers;
    }

    slivers.add(
      SliverToBoxAdapter(
        child: _buildSectionTitle('网络媒体库'),
      ),
    );

    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: _withSpacing(cards),
          ),
        ),
      ),
    );

    slivers.add(
      const SliverToBoxAdapter(
        child: SizedBox(height: 12),
      ),
    );

    return slivers;
  }

  List<Widget> _withSpacing(List<Widget> items) {
    if (items.length <= 1) {
      return List<Widget>.from(items);
    }
    final List<Widget> spaced = [];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        spaced.add(const SizedBox(height: 16));
      }
      spaced.add(items[i]);
    }
    return spaced;
  }

  String? _formatServerSubtitle(String? username, String? serverUrl) {
    final List<String> segments = [];
    if (username != null && username.isNotEmpty) {
      segments.add(username);
    }
    if (serverUrl != null && serverUrl.isNotEmpty) {
      segments.add(_trimUrlScheme(serverUrl));
    }
    if (segments.isEmpty) {
      return null;
    }
    return segments.join(' · ');
  }

  String _trimUrlScheme(String url) {
    return url.replaceFirst(RegExp(r'^https?://'), '');
  }

  Future<void> _openNetworkServerLibrariesPage(MediaServerType type) async {
    final bool connected = switch (type) {
      MediaServerType.jellyfin => context.read<JellyfinProvider>().isConnected,
      MediaServerType.emby => context.read<EmbyProvider>().isConnected,
    };

    if (!connected) {
      AdaptiveSnackBar.show(
        context,
        message: type == MediaServerType.jellyfin
            ? '请先连接 Jellyfin 服务器'
            : '请先连接 Emby 服务器',
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }

    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CupertinoNetworkServerLibrariesPage(
          serverType: type,
          onOpenDetail: _openNetworkMediaDetail,
          onManageServer: _showNetworkServerDialog,
        ),
      ),
    );
  }

  Future<void> _refreshActiveHost(SharedRemoteLibraryProvider provider) async {
    if (!provider.hasActiveHost) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '请先添加共享客户端',
          type: AdaptiveSnackBarType.warning,
        );
      }
      return;
    }
    await provider.refreshLibrary(userInitiated: true);
  }

  Widget _buildHostCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    Color cardColor,
  ) {
    final hasHosts = provider.hosts.isNotEmpty;
    final activeHost = provider.activeHost;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Container(
      key: ValueKey<bool>(hasHosts),
      padding: const EdgeInsets.all(20),
      decoration: _hostCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.isLoading)
            const Row(
              children: [
                Expanded(child: SizedBox()),
                CupertinoActivityIndicator(radius: 10),
              ],
            ),
          if (!hasHosts)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '尚未添加任何共享客户端',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: labelColor),
                ),
                const SizedBox(height: 6),
                Text(
                  '点击下方按钮添加一台已开启远程访问的 NipaPlay 客户端。',
                  style: TextStyle(
                      fontSize: 14, color: secondaryLabelColor, height: 1.3),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoButton(
                    onPressed: () => _openAddHostDialog(provider),
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.activeBlue, context),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    borderRadius: BorderRadius.circular(14),
                    child: const Text(
                      '添加共享客户端',
                      style:
                          TextStyle(fontSize: 15, color: CupertinoColors.white),
                    ),
                  ),
                ),
              ],
            )
          else if (activeHost == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请先选择一个共享客户端',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: labelColor),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前未选定共享客户端，请点击下方按钮从已保存的列表中选择。',
                  style: TextStyle(
                      fontSize: 14, color: secondaryLabelColor, height: 1.3),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildActionButton(
                    context,
                    label: '选择客户端',
                    icon: CupertinoIcons.arrow_right_circle,
                    onPressed: provider.hosts.isNotEmpty
                        ? () => SharedRemoteHostSelectionSheet.show(context)
                        : null,
                    primary: true,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  context,
                  label: '当前客户端',
                  value: activeHost.displayName.isNotEmpty
                      ? activeHost.displayName
                      : activeHost.baseUrl,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '访问地址',
                  value: activeHost.baseUrl,
                  allowWrap: true,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(context, activeHost),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '最后同步',
                  value: _formatDateTime(activeHost.lastConnectedAt),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '番剧数量',
                  value: '${provider.animeSummaries.length}',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _buildActionButton(
                      context,
                      label: '查看媒体库',
                      icon: CupertinoIcons.collections,
                      onPressed: () => _showMediaLibraryBottomSheet(provider),
                      primary: true,
                    ),
                    _buildActionButton(
                      context,
                      label: '刷新媒体库',
                      icon: CupertinoIcons.refresh,
                      onPressed: () => _refreshActiveHost(provider),
                    ),
                    _buildActionButton(
                      context,
                      label: '切换客户端',
                      icon: CupertinoIcons.arrow_2_circlepath,
                      onPressed: provider.hosts.length > 1
                          ? () => SharedRemoteHostSelectionSheet.show(context)
                          : null,
                    ),
                    _buildActionButton(
                      context,
                      label: '添加客户端',
                      icon: CupertinoIcons.add,
                      onPressed: () => _openAddHostDialog(provider),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  BoxDecoration _hostCardDecoration(BuildContext context) {
    return BoxDecoration(
      color: CupertinoDynamicColor.resolve(
        CupertinoDynamicColor.withBrightness(
          color: CupertinoColors.white,
          darkColor: CupertinoColors.darkBackgroundGray,
        ),
        context,
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: CupertinoColors.black.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    bool allowWrap = false,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final valueColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    final valueWidget = allowWrap
        ? Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14, height: 1.3),
          )
        : Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          );

    return Row(
      crossAxisAlignment:
          allowWrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: valueWidget),
      ],
    );
  }

  Widget _buildStatusRow(BuildContext context, SharedRemoteHost host) {
    final statusColor = host.isOnline
        ? CupertinoDynamicColor.resolve(CupertinoColors.activeGreen, context)
        : CupertinoDynamicColor.resolve(CupertinoColors.systemOrange, context);
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            '连接状态',
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            host.isOnline ? '在线' : '等待连接',
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (host.lastError != null && host.lastError!.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              host.lastError!,
              style: TextStyle(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemRed, context),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final bool enabled = onPressed != null;
    final Color primaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    final Color secondaryBackground =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final Color textColor = primary
        ? CupertinoColors.white
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color backgroundColor = primary ? primaryColor : secondaryBackground;

    return CupertinoButton(
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: BorderRadius.circular(12),
      minimumSize: const Size.square(36),
      color: enabled ? backgroundColor : backgroundColor.withValues(alpha: 0.4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: enabled ? textColor : textColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? textColor : textColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    Color cardColor,
  ) {
    final resolvedCardColor = CupertinoDynamicColor.resolve(cardColor, context);
    final errorColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: resolvedCardColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: errorColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill,
              color: errorColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.errorMessage ?? '',
              style: TextStyle(color: errorColor, fontSize: 13, height: 1.35),
            ),
          ),
          CupertinoButton(
            onPressed: provider.clearError,
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(28),
            child: Icon(
              CupertinoIcons.clear_circled_solid,
              color: errorColor.withValues(alpha: 0.9),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLibrarySlivers(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    Color cardColor,
  ) {
    final hasHosts = provider.hosts.isNotEmpty;
    final hasActiveHost = provider.hasActiveHost;

    if (provider.isInitializing) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    if (!hasHosts) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyPlaceholder(
            context,
            icon: CupertinoIcons.cloud,
            title: '尚未添加共享客户端',
            subtitle: '请在上方按钮中添加一台已开启远程访问的 NipaPlay 客户端。',
          ),
        ),
      ];
    }

    if (!hasActiveHost) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyPlaceholder(
            context,
            icon: CupertinoIcons.tray,
            title: '尚未选择客户端',
            subtitle: '请选择一个可用的共享客户端以显示媒体库内容。',
          ),
        ),
      ];
    }

    // 如果有活跃主机，显示提示用户点击"查看媒体库"按钮
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: _buildEmptyPlaceholder(
            context,
            icon: CupertinoIcons.collections,
            title: '媒体库已连接',
            subtitle: '点击上方的"查看媒体库"按钮来浏览内容。',
          ),
        ),
      ),
    ];
  }

  Widget _buildEmptyPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final iconColor =
        CupertinoDynamicColor.resolve(CupertinoColors.inactiveGray, context);
    final titleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: subtitleColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final textStyle = CupertinoTheme.of(context).textTheme.navTitleTextStyle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: textStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }

  List<String> _resolveSelectedLibraryNames<T>(
    List<T> libraries,
    Iterable<String> selectedIds,
    String Function(T library) idSelector,
    String Function(T library) nameSelector,
  ) {
    if (selectedIds.isEmpty) {
      return const <String>[];
    }

    final Map<String, String> nameMap = {
      for (final library in libraries)
        idSelector(library): nameSelector(library),
    };

    final List<String> resolved = [];
    for (final id in selectedIds) {
      final name = nameMap[id];
      if (name != null && name.isNotEmpty) {
        resolved.add(name);
      }
    }
    return resolved;
  }

  Future<void> _showNetworkServerDialog(MediaServerType type) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => CupertinoNetworkMediaManagementSheet(
          serverType: type,
        ),
      ),
    );
    if (mounted) {
      final label = type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
      AdaptiveSnackBar.show(
        context,
        message: '$label 服务器设置已更新',
        type: AdaptiveSnackBarType.success,
      );
    }
  }

  Future<void> _openNetworkMediaDetail(
    MediaServerType type,
    String mediaId,
  ) async {
    WatchHistoryItem? result;
    if (type == MediaServerType.jellyfin) {
      result = await MediaServerDetailPage.showJellyfin(context, mediaId);
    } else {
      result = await MediaServerDetailPage.showEmby(context, mediaId);
    }

    if (result == null || !mounted) {
      return;
    }

    String? actualPlayUrl;
    try {
      if (result.filePath.startsWith('jellyfin://')) {
        final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
        final provider = context.read<JellyfinProvider>();
        if (!provider.isConnected) {
          AdaptiveSnackBar.show(
            context,
            message: '未连接到 Jellyfin 服务器',
            type: AdaptiveSnackBarType.warning,
          );
          return;
        }
        actualPlayUrl = provider.getStreamUrl(jellyfinId);
      } else if (result.filePath.startsWith('emby://')) {
        final embyId = result.filePath.replaceFirst('emby://', '');
        final provider = context.read<EmbyProvider>();
        if (!provider.isConnected) {
          AdaptiveSnackBar.show(
            context,
            message: '未连接到 Emby 服务器',
            type: AdaptiveSnackBarType.warning,
          );
          return;
        }
        actualPlayUrl = await provider.getStreamUrl(embyId);
      }
    } catch (e) {
      AdaptiveSnackBar.show(
        context,
        message: '获取播放地址失败：$e',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    final playable = PlayableItem(
      videoPath: result.filePath,
      title: result.animeName,
      subtitle: result.episodeTitle,
      animeId: result.animeId,
      episodeId: result.episodeId,
      historyItem: result,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playable);
    await context.read<WatchHistoryProvider>().refresh();
  }

  String _formatDateTime(DateTime? time) {
    if (time == null) {
      return '尚未同步';
    }
    return _timeFormatter.format(time.toLocal());
  }

  Future<void> _showLocalMediaLibraryBottomSheet() async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '本地媒体库',
      floatingTitle: true,
      child: const _LocalMediaLibrarySheet(),
    );
  }

  Future<void> _showLibraryManagementBottomSheet() async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '库管理',
      floatingTitle: true,
      child: const _CupertinoLibraryManagementSheet(),
    );
  }

  Future<void> _showMediaLibraryBottomSheet(
      SharedRemoteLibraryProvider provider) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '共享媒体库',
      floatingTitle: true, // 使用浮动标题
      child: _MediaLibraryContent(provider: provider),
    );
  }

  Future<void> _openAddHostDialog(SharedRemoteLibraryProvider provider) async {
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => IOS26AlertDialog(
        title: '添加NipaPlay共享客户端',
        input: const AdaptiveAlertDialogInput(
          placeholder: '例如：http://192.168.1.100:8080',
          initialValue: '',
          keyboardType: TextInputType.url,
        ),
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '添加',
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final baseUrl = result.trim();
      if (baseUrl.isEmpty) {
        if (mounted) {
          AdaptiveSnackBar.show(
            context,
            message: '请输入访问地址',
            type: AdaptiveSnackBarType.warning,
          );
        }
        return;
      }

      try {
        await provider.addHost(
          displayName: baseUrl,
          baseUrl: baseUrl,
        );
        if (mounted) {
          AdaptiveSnackBar.show(
            context,
            message: '已添加共享客户端',
            type: AdaptiveSnackBarType.success,
          );
        }
      } catch (e) {
        if (mounted) {
          AdaptiveSnackBar.show(
            context,
            message: '添加失败：$e',
            type: AdaptiveSnackBarType.error,
          );
        }
      }
    }
  }
}

class _LocalMediaSummary {
  const _LocalMediaSummary({
    required this.animeId,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.imageUrl,
    required this.episodeCount,
    required this.totalEpisodes,
    required this.lastWatchTime,
    required this.source,
    required this.hasMissingFiles,
  });

  final int animeId;
  final String name;
  final String? nameCn;
  final String? summary;
  final String? imageUrl;
  final int episodeCount;
  final int? totalEpisodes;
  final DateTime? lastWatchTime;
  final String? source;
  final bool hasMissingFiles;

  String get displayTitle =>
      (nameCn != null && nameCn!.isNotEmpty) ? nameCn! : name;

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  factory _LocalMediaSummary.fromJson(Map<String, dynamic> json) {
    return _LocalMediaSummary(
      animeId: (json['animeId'] ?? 0) as int,
      name: (json['name'] ?? '') as String,
      nameCn: (json['nameCn'] as String?)?.trim(),
      summary: (json['summary'] as String?)?.trim(),
      imageUrl: (json['imageUrl'] as String?)?.trim(),
      episodeCount: (json['episodeCount'] ?? 0) as int,
      totalEpisodes: json['totalEpisodes'] == null
          ? null
          : (json['totalEpisodes'] as num).toInt(),
      lastWatchTime: _parseDateTime(json['lastWatchTime'] as String?),
      source: json['source'] as String?,
      hasMissingFiles: json['hasMissingFiles'] == true,
    );
  }
}

class CupertinoLocalMediaLibraryCard extends StatefulWidget {
  const CupertinoLocalMediaLibraryCard({
    super.key,
    required this.onViewLibrary,
    required this.onManageLibrary,
  });

  final VoidCallback onViewLibrary;
  final VoidCallback onManageLibrary;

  @override
  State<CupertinoLocalMediaLibraryCard> createState() =>
      _CupertinoLocalMediaLibraryCardState();
}

class _CupertinoLocalMediaLibraryCardState
    extends State<CupertinoLocalMediaLibraryCard> {
  final LocalMediaShareService _localShareService =
      LocalMediaShareService.instance;
  final DateFormat _timeFormatter = DateFormat('MM-dd HH:mm');

  bool _isLoading = true;
  String? _error;
  List<_LocalMediaSummary> _summaries = <_LocalMediaSummary>[];
  WatchHistoryProvider? _watchHistoryProvider;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final watchHistory = context.read<WatchHistoryProvider>();
      _watchHistoryProvider = watchHistory;
      watchHistory.addListener(_handleHistoryChanged);
      _ensureInitialized(watchHistory);
    });
  }

  Future<void> _ensureInitialized(WatchHistoryProvider provider) async {
    if (!provider.isLoaded && !provider.isLoading) {
      await provider.loadHistory();
    }
    await _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _summaries = const [];
        _isLoading = false;
        _error = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _localShareService.getAnimeSummaries();
      final summaries =
          data.map((entry) => _LocalMediaSummary.fromJson(entry)).toList()
            ..sort((a, b) {
              final aTime =
                  a.lastWatchTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.lastWatchTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

      if (!mounted) return;
      setState(() {
        _summaries = summaries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleHistoryChanged() {
    _loadSummaries();
  }

  @override
  void dispose() {
    _watchHistoryProvider?.removeListener(_handleHistoryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final containerColor = CupertinoDynamicColor.resolve(
      CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );

    return Consumer<ScanService>(
      builder: (context, scanService, _) {
        final bool hasItems = _summaries.isNotEmpty;
        final DateTime? lastWatchTime =
            hasItems ? _summaries.first.lastWatchTime : null;
        final String? latestTitle =
            hasItems ? _summaries.first.displayTitle : null;

        return Container(
          key: ValueKey<bool>(_isLoading),
          padding: const EdgeInsets.all(20),
          decoration: _localCardDecoration(context, containerColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Row(
                  children: [
                    CupertinoActivityIndicator(radius: 10),
                    SizedBox(width: 8),
                    Text(
                      '正在准备媒体库...',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                )
              else if (_error != null)
                _buildErrorBanner(context, _error!)
              else ...[
                _buildInfoRow(
                  context,
                  label: '番剧数量',
                  value: hasItems ? '${_summaries.length}' : '暂无记录',
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '扫描文件夹',
                  value: scanService.scannedFolders.isNotEmpty
                      ? '${scanService.scannedFolders.length}'
                      : '未配置',
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '最近观看',
                  value: lastWatchTime != null
                      ? _timeFormatter.format(lastWatchTime.toLocal())
                      : '尚无观看记录',
                ),
                if (latestTitle != null && latestTitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    context,
                    label: '最新番剧',
                    value: latestTitle,
                    allowWrap: true,
                  ),
                ],
                if (scanService.scanMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildScanStatus(
                    context,
                    scanService.scanMessage,
                    scanService.isScanning,
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _buildActionButton(
                      context,
                      label: '查看媒体库',
                      icon: CupertinoIcons.collections,
                      primary: true,
                      onPressed: widget.onViewLibrary,
                    ),
                    _buildActionButton(
                      context,
                      label: '库管理',
                      icon: CupertinoIcons.slider_horizontal_3,
                      onPressed: widget.onManageLibrary,
                    ),
                    _buildActionButton(
                      context,
                      label: scanService.isScanning ? '扫描中…' : '智能刷新',
                      icon: CupertinoIcons.refresh,
                      onPressed: scanService.isScanning
                          ? null
                          : () => _handleSmartRefresh(scanService),
                    ),
                    _buildImportButton(context),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _localCardDecoration(
    BuildContext context,
    Color containerColor,
  ) {
    return BoxDecoration(
      color: containerColor,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: CupertinoColors.black.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  void _handleSmartRefresh(ScanService scanService) {
    if (scanService.scannedFolders.isEmpty) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '请先在库管理中添加媒体文件夹',
          type: AdaptiveSnackBarType.info,
        );
      }
      return;
    }
    scanService.rescanAllFolders();
  }

  void _handleImportSelection(dynamic value) {
    if (_isImporting) return;
    if (value == 'album') {
      _startImport(_pickVideoFromAlbum);
    } else if (value == 'file') {
      _startImport(_pickVideoFromFileManager);
    }
  }

  Widget _buildImportButton(BuildContext context) {
    final bool enabled = !_isImporting;
    final Color primaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    final Color textColor = CupertinoColors.white;

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: enabled ? primaryColor : primaryColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.add_circled,
            size: 18,
            color: textColor.withValues(alpha: enabled ? 1.0 : 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            _isImporting ? '导入中…' : '导入视频',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor.withValues(alpha: enabled ? 1.0 : 0.5),
            ),
          ),
        ],
      ),
    );

    if (!enabled) return child;

    return AdaptivePopupMenuButton.widget(
      items: _buildImportMenuItems(),
      child: child,
      onSelected: (index, entry) {
        final value = (entry as AdaptivePopupMenuItem).value;
        _handleImportSelection(value);
      },
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final errorColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);
    final cardColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: errorColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill,
              color: errorColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: errorColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanStatus(
    BuildContext context,
    String message,
    bool isProcessing,
  ) {
    final infoColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemBlue, context);
    final background = infoColor.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isProcessing)
            const CupertinoActivityIndicator(radius: 8)
          else
            Icon(CupertinoIcons.info, color: infoColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: infoColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    bool allowWrap = false,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final valueColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Row(
      crossAxisAlignment:
          allowWrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: allowWrap
              ? Text(
                  value,
                  style:
                      TextStyle(color: valueColor, fontSize: 14, height: 1.3),
                )
              : Text(
                  value,
                  style: TextStyle(color: valueColor, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final bool enabled = onPressed != null;
    final Color primaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    final Color secondaryBackground =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final Color textColor = primary
        ? CupertinoColors.white
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color backgroundColor = primary ? primaryColor : secondaryBackground;

    final buttonChild = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:
            enabled ? backgroundColor : backgroundColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: enabled ? textColor : textColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? textColor : textColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );

    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: buttonChild,
    );
  }

  Future<void> _startImport(Future<void> Function() task) async {
    if (_isImporting) return;
    if (mounted) {
      setState(() {
        _isImporting = true;
      });
    } else {
      _isImporting = true;
    }
    try {
      await task();
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '导入视频失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      } else {
        _isImporting = false;
      }
    }
  }

  Future<void> _pickVideoFromAlbum() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        if (!photos.isGranted || !videos.isGranted) {
          if (mounted) {
            BlurSnackBar.show(context, '需要授予相册与视频权限');
          }
          return;
        }
      }

      final picker = ImagePicker();
      final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      await _playSelectedFile(picked.path);
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '选择相册视频失败: $e');
      }
    }
  }

  Future<void> _pickVideoFromFileManager() async {
    final filePickerService = FilePickerService();
    final filePath = await filePickerService.pickVideoFile();
    if (filePath == null) {
      return;
    }
    await _playSelectedFile(filePath);
  }

  Future<void> _playSelectedFile(String path) async {
    try {
      await WatchHistoryManager.initialize();
    } catch (_) {
      // ignore initialization errors
    }

    WatchHistoryItem? historyItem =
        await WatchHistoryManager.getHistoryItem(path);
    historyItem ??= WatchHistoryItem(
      filePath: path,
      animeName: p.basenameWithoutExtension(path),
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
    );

    final playable = PlayableItem(
      videoPath: path,
      title: historyItem.animeName,
      historyItem: historyItem,
    );

    await PlaybackService().play(playable);

    await _watchHistoryProvider?.loadHistory();
  }

  List<AdaptivePopupMenuEntry> _buildImportMenuItems() {
    return [
      AdaptivePopupMenuItem(
        label: '从相册导入',
        value: 'album',
        icon: PlatformInfo.isIOS26OrHigher()
            ? 'photo.on.rectangle'
            : CupertinoIcons.photo,
      ),
      const AdaptivePopupMenuDivider(),
      AdaptivePopupMenuItem(
        label: '从文件管理器导入',
        value: 'file',
        icon: PlatformInfo.isIOS26OrHigher() ? 'folder' : CupertinoIcons.folder,
      ),
    ];
  }
}

class _LocalMediaLibrarySheet extends StatefulWidget {
  const _LocalMediaLibrarySheet();

  @override
  State<_LocalMediaLibrarySheet> createState() =>
      _LocalMediaLibrarySheetState();
}

class _LocalMediaLibrarySheetState extends State<_LocalMediaLibrarySheet> {
  final LocalMediaShareService _localShareService =
      LocalMediaShareService.instance;
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  double _scrollOffset = 0.0;
  List<_LocalMediaSummary> _summaries = <_LocalMediaSummary>[];
  WatchHistoryProvider? _watchHistoryProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final watchHistory = context.read<WatchHistoryProvider>();
      _watchHistoryProvider = watchHistory;
      watchHistory.addListener(_handleHistoryChanged);
      _initialize(watchHistory);
    });
  }

  Future<void> _initialize(WatchHistoryProvider provider) async {
    if (!provider.isLoaded && !provider.isLoading) {
      await provider.loadHistory();
    }
    await _loadSummaries();
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  void _handleHistoryChanged() {
    _loadSummaries();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _watchHistoryProvider?.removeListener(_handleHistoryChanged);
    super.dispose();
  }

  Future<void> _loadSummaries() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _summaries = const [];
        _isLoading = false;
        _error = 'Web 端暂不支持本地媒体库';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _localShareService.getAnimeSummaries();
      final summaries =
          data.map((entry) => _LocalMediaSummary.fromJson(entry)).toList()
            ..sort((a, b) {
              final aTime =
                  a.lastWatchTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.lastWatchTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

      if (!mounted) return;
      setState(() {
        _summaries = summaries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRefresh() async {
    final watchHistory = context.read<WatchHistoryProvider>();
    await watchHistory.refresh();
    await _loadSummaries();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final titleOpacity = (1.0 - (_scrollOffset / 12.0)).clamp(0.0, 1.0);

    if (_isLoading) {
      return CupertinoBottomSheetContentLayout(
        controller: _scrollController,
        backgroundColor: backgroundColor,
        floatingTitleOpacity: titleOpacity,
        sliversBuilder: (context, topSpacing) => const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoActivityIndicator(),
                SizedBox(height: 16),
                Text(
                  '正在加载本地媒体库...',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return CupertinoBottomSheetContentLayout(
        controller: _scrollController,
        backgroundColor: backgroundColor,
        floatingTitleOpacity: titleOpacity,
        sliversBuilder: (context, topSpacing) => [
          SliverFillRemaining(
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
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  CupertinoButton(
                    onPressed: _loadSummaries,
                    child: const Text('重新尝试'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_summaries.isEmpty) {
      return CupertinoBottomSheetContentLayout(
        controller: _scrollController,
        backgroundColor: backgroundColor,
        floatingTitleOpacity: titleOpacity,
        sliversBuilder: (context, topSpacing) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.tray,
                  size: 52,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.inactiveGray,
                    context,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '尚未找到本地番剧',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '请在“库管理”中添加媒体文件夹并执行扫描。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),
                CupertinoButton(
                  onPressed: _handleRefresh,
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return CupertinoBottomSheetContentLayout(
      controller: _scrollController,
      backgroundColor: backgroundColor,
      floatingTitleOpacity: titleOpacity,
      sliversBuilder: (context, topSpacing) => [
        CupertinoSliverRefreshControl(onRefresh: _handleRefresh),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final summary = _summaries[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == _summaries.length - 1 ? 0 : 12,
                  ),
                  child: CupertinoAnimeCard(
                    title: summary.displayTitle,
                    imageUrl: summary.imageUrl,
                    episodeLabel: _buildEpisodeLabel(summary),
                    lastWatchTime: summary.lastWatchTime,
                    onTap: () => _openAnimeDetail(summary),
                    sourceLabel: '本地媒体库',
                    summary: summary.summary,
                    rating: null,
                  ),
                );
              },
              childCount: _summaries.length,
            ),
          ),
        ),
      ],
    );
  }

  String _buildEpisodeLabel(_LocalMediaSummary summary) {
    final buffer = StringBuffer('共${summary.episodeCount}集');
    if (summary.totalEpisodes != null && summary.totalEpisodes! > 0) {
      buffer.write(' · 预计${summary.totalEpisodes}集');
    }
    if (summary.hasMissingFiles) {
      buffer.write(' · 存在缺失');
    }
    return buffer.toString();
  }

  Future<void> _openAnimeDetail(_LocalMediaSummary summary) async {
    if (!mounted) return;
    await AnimeDetailPage.show(context, summary.animeId);
  }
}

class _CupertinoLibraryManagementSheet extends StatefulWidget {
  const _CupertinoLibraryManagementSheet();

  @override
  State<_CupertinoLibraryManagementSheet> createState() =>
      _CupertinoLibraryManagementSheetState();
}

class _CupertinoLibraryManagementSheetState
    extends State<_CupertinoLibraryManagementSheet> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final titleOpacity = (1.0 - (_scrollOffset / 12.0)).clamp(0.0, 1.0);

    return Consumer2<ScanService, WatchHistoryProvider>(
      builder: (context, scanService, watchHistory, _) {
        final sections = <Widget>[
          _buildStatusCard(context, scanService, watchHistory),
          const SizedBox(height: 20),
          _buildActionButtons(context, scanService),
          const SizedBox(height: 24),
          _buildFolderSection(context, scanService),
        ];

        if (scanService.detectedChanges.isNotEmpty) {
          sections.addAll([
            const SizedBox(height: 20),
            _buildDetectedChangesInfo(context, scanService),
          ]);
        }

        sections.add(const SizedBox(height: 32));

        return CupertinoBottomSheetContentLayout(
          controller: _scrollController,
          backgroundColor: backgroundColor,
          floatingTitleOpacity: titleOpacity,
          sliversBuilder: (context, topSpacing) => [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate(sections),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    ScanService scanService,
    WatchHistoryProvider watchHistory,
  ) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                scanService.isScanning
                    ? CupertinoIcons.arrow_2_circlepath
                    : CupertinoIcons.archivebox,
                size: 20,
                color: labelColor,
              ),
              const SizedBox(width: 8),
              Text(
                scanService.isScanning ? '正在扫描媒体库' : '本地媒体库就绪',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const Spacer(),
              if (scanService.isScanning)
                const CupertinoActivityIndicator(radius: 10),
            ],
          ),
          const SizedBox(height: 14),
          _buildStatusRow(
            context,
            label: '番剧记录',
            value: '${watchHistory.history.length}',
          ),
          const SizedBox(height: 6),
          _buildStatusRow(
            context,
            label: '扫描文件夹',
            value: '${scanService.scannedFolders.length}',
          ),
          if (scanService.scanMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              scanService.scanMessage,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: secondaryLabelColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final valueColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, ScanService scanService) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildActionButton(
          context,
          label: '添加媒体文件夹',
          icon: CupertinoIcons.add_circled,
          primary: true,
          onPressed: scanService.isScanning
              ? null
              : () => _handleAddFolder(scanService),
        ),
        _buildActionButton(
          context,
          label: '智能刷新',
          icon: CupertinoIcons.refresh,
          onPressed: scanService.isScanning
              ? null
              : () => _handleSmartRefresh(scanService),
        ),
        _buildActionButton(
          context,
          label: '重新加载媒体库',
          icon: CupertinoIcons.arrow_down_doc,
          onPressed: () => _handleReloadHistory(),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final bool enabled = onPressed != null;
    final Color primaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    final Color secondaryBackground =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final Color textColor = primary
        ? CupertinoColors.white
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color backgroundColor = primary ? primaryColor : secondaryBackground;

    return CupertinoButton(
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      minimumSize: const Size.square(40),
      borderRadius: BorderRadius.circular(14),
      color: enabled ? backgroundColor : backgroundColor.withValues(alpha: 0.4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled ? textColor : textColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? textColor : textColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSection(BuildContext context, ScanService scanService) {
    final folders = scanService.scannedFolders;
    if (folders.isEmpty) {
      final secondaryLabel = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel,
        context,
      );
      final cardColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondarySystemBackground,
        context,
      );
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '尚未添加媒体文件夹',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方“添加媒体文件夹”按钮开始扫描本地番剧。',
              style:
                  TextStyle(fontSize: 13, color: secondaryLabel, height: 1.4),
            ),
          ],
        ),
      );
    }

    return CupertinoListSection.insetGrouped(
      backgroundColor: CupertinoDynamicColor.resolve(
        CupertinoColors.systemGroupedBackground,
        context,
      ),
      header: const Text('已添加的媒体文件夹'),
      children: folders
          .map((folder) => _buildFolderTile(context, scanService, folder))
          .toList(),
    );
  }

  Widget _buildFolderTile(
    BuildContext context,
    ScanService scanService,
    String folderPath,
  ) {
    final subtitleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final accentColor = CupertinoDynamicColor.resolve(
      CupertinoColors.activeBlue,
      context,
    );
    final destructiveColor = CupertinoDynamicColor.resolve(
      CupertinoColors.destructiveRed,
      context,
    );

    return CupertinoListTile(
      title: Text(p.basename(folderPath)),
      subtitle: Text(
        folderPath,
        style: TextStyle(color: subtitleColor, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(32),
            onPressed: scanService.isScanning
                ? null
                : () => _handleRescanFolder(scanService, folderPath),
            child: Icon(
              CupertinoIcons.refresh_thin,
              size: 20,
              color: scanService.isScanning
                  ? accentColor.withValues(alpha: 0.4)
                  : accentColor,
            ),
          ),
          const SizedBox(width: 4),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(32),
            onPressed: scanService.isScanning
                ? null
                : () => _handleRemoveFolder(scanService, folderPath),
            child: Icon(
              CupertinoIcons.delete,
              size: 20,
              color: scanService.isScanning
                  ? destructiveColor.withValues(alpha: 0.4)
                  : destructiveColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedChangesInfo(
    BuildContext context,
    ScanService scanService,
  ) {
    final highlightColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemYellow,
      context,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlightColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '检测到文件夹变化',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: highlightColor,
            ),
          ),
          const SizedBox(height: 8),
          ...scanService.detectedChanges.take(3).map(
                (change) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${change.displayName}: ${change.changeDescription}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: highlightColor.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
          if (scanService.detectedChanges.length > 3)
            Text(
              '还有 ${scanService.detectedChanges.length - 3} 个文件夹有变化…',
              style: TextStyle(
                fontSize: 12,
                color: highlightColor.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleAddFolder(ScanService scanService) async {
    if (kIsWeb) {
      _showSnack('Web 端暂不支持扫描本地媒体库');
      return;
    }
    if (scanService.isScanning) {
      _showSnack('已有扫描任务在进行中，请稍后再试。');
      return;
    }

    try {
      if (Platform.isIOS) {
        final directory = await StorageService.getAppStorageDirectory();
        await scanService.startDirectoryScan(
          directory.path,
          skipPreviouslyMatchedUnwatched: false,
        );
        _showSnack('已提交扫描任务：${p.basename(directory.path)}');
        return;
      }

      if (Platform.isAndroid) {
        final sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
        if (sdkVersion >= 33) {
          await _handleScanAndroidMediaFolders(scanService);
          return;
        }
      }

      final filePicker = FilePickerService();
      final selectedDirectory = await filePicker.pickDirectory();
      if (selectedDirectory == null) {
        _showSnack('未选择文件夹');
        return;
      }

      // [修改] 自定义目录会影响安卓缓存，先注释
      //await StorageService.saveCustomStoragePath(selectedDirectory);
      await scanService.startDirectoryScan(
        selectedDirectory,
        skipPreviouslyMatchedUnwatched: false,
      );
      _showSnack('已提交扫描任务：${p.basename(selectedDirectory)}');
    } catch (e) {
      _showSnack('添加媒体文件夹失败：$e');
    }
  }

  Future<void> _handleScanAndroidMediaFolders(ScanService scanService) async {
    try {
      final directories =
          await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (directories == null || directories.isEmpty) {
        _showSnack('未找到系统的影片文件夹');
        return;
      }

      for (final dir in directories) {
        await scanService.startDirectoryScan(
          dir.path,
          skipPreviouslyMatchedUnwatched: false,
        );
      }
      _showSnack('已提交系统视频文件夹扫描任务');
    } catch (e) {
      _showSnack('扫描系统视频文件夹失败：$e');
    }
  }

  Future<void> _handleRescanFolder(
    ScanService scanService,
    String folderPath,
  ) async {
    if (kIsWeb) {
      _showSnack('Web 端暂不支持扫描本地媒体库');
      return;
    }
    if (scanService.isScanning) {
      _showSnack('已有扫描任务在进行中，请稍后再试。');
      return;
    }

    await scanService.startDirectoryScan(
      folderPath,
      skipPreviouslyMatchedUnwatched: false,
    );
    _showSnack('已提交刷新：${p.basename(folderPath)}');
  }

  Future<void> _handleRemoveFolder(
    ScanService scanService,
    String folderPath,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('移除媒体文件夹'),
        content: Text('确定要移除\n$folderPath\n吗？相关的缓存与记录也会被清理。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    await scanService.removeScannedFolder(folderPath);
    if (!mounted) return;
    _showSnack('已提交移除：${p.basename(folderPath)}');
  }

  Future<void> _handleSmartRefresh(ScanService scanService) async {
    if (kIsWeb) {
      _showSnack('Web 端暂不支持扫描本地媒体库');
      return;
    }

    if (scanService.scannedFolders.isEmpty) {
      _showSnack('请先添加媒体文件夹后再刷新');
      return;
    }
    if (scanService.isScanning) {
      _showSnack('已有扫描任务在进行中，请稍后再试。');
      return;
    }

    await scanService.rescanAllFolders();
  }

  Future<void> _handleReloadHistory() async {
    final watchHistory = context.read<WatchHistoryProvider>();
    await watchHistory.refresh();
    _showSnack('已请求刷新本地媒体库数据');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.info,
    );
  }
}

/// 媒体库内容组件
/// 只负责显示媒体库的内容，不包含上拉菜单容器
class _MediaLibraryContent extends StatefulWidget {
  final SharedRemoteLibraryProvider provider;

  const _MediaLibraryContent({required this.provider});

  @override
  State<_MediaLibraryContent> createState() => _MediaLibraryContentState();
}

class _MediaLibraryContentState extends State<_MediaLibraryContent> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.provider.animeSummaries.isEmpty) {
        widget.provider.refreshLibrary(userInitiated: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      onGenerateInitialRoutes: (_, __) {
        return [
          CupertinoPageRoute<void>(
            builder: (routeContext) =>
                ChangeNotifierProvider<SharedRemoteLibraryProvider>.value(
              value: widget.provider,
              child: _CupertinoMediaLibraryListPage(
                onAnimeTap: _handleAnimeTap,
              ),
            ),
          ),
        ];
      },
      onGenerateRoute: (_) => null,
    );
  }

  Future<void> _handleAnimeTap(SharedRemoteAnimeSummary anime) async {
    final detailMode = context.read<ThemeNotifier>().animeDetailDisplayMode;

    await _navigatorKey.currentState?.push(
      CupertinoPageRoute<void>(
        builder: (routeContext) =>
            ChangeNotifierProvider<SharedRemoteLibraryProvider>.value(
          value: widget.provider,
          child: CupertinoSharedAnimeDetailPage(
            anime: anime,
            hideBackButton: false,
            displayModeOverride: detailMode,
            showCloseButton: false,
          ),
        ),
      ),
    );
  }
}

class _CupertinoMediaLibraryListPage extends StatefulWidget {
  const _CupertinoMediaLibraryListPage({required this.onAnimeTap});

  final ValueChanged<SharedRemoteAnimeSummary> onAnimeTap;

  @override
  State<_CupertinoMediaLibraryListPage> createState() =>
      _CupertinoMediaLibraryListPageState();
}

class _CupertinoMediaLibraryListPageState
    extends State<_CupertinoMediaLibraryListPage> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) {
      return;
    }
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, _) {
        return _buildContent(context, provider);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final animeSummaries = provider.animeSummaries;
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final titleOpacity = (1.0 - (_scrollOffset / 10.0)).clamp(0.0, 1.0);

    if (provider.isLoading && animeSummaries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(height: 16),
            Text(
              '正在加载媒体库...',
              style: TextStyle(color: CupertinoColors.secondaryLabel),
            ),
          ],
        ),
      );
    }

    if (animeSummaries.isEmpty) {
      final subtitle = provider.hasReachableActiveHost
          ? '该客户端的媒体库为空，稍后再试试。'
          : '当前客户端离线或不可达，请确认远程设备在线后重试。';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.folder,
                size: 52,
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.inactiveGray,
                  context,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '尚未同步到番剧',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.label,
                    context,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel,
                    context,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: () => provider.refreshLibrary(userInitiated: true),
                child: const Text('重新刷新'),
              ),
            ],
          ),
        ),
      );
    }

    return CupertinoBottomSheetContentLayout(
      controller: _scrollController,
      backgroundColor: backgroundColor,
      floatingTitleOpacity: titleOpacity,
      sliversBuilder: (context, topSpacing) {
        final slivers = <Widget>[];
        if (provider.isLoading) {
          slivers.add(
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CupertinoActivityIndicator(radius: 8),
                    SizedBox(width: 8),
                    Text('正在刷新…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        }

        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index.isOdd) {
                    return const SizedBox(height: 12);
                  }
                  final animeIndex = index ~/ 2;
                  final anime = animeSummaries[animeIndex];
                  return _buildAnimeCard(context, provider, anime);
                },
                childCount: animeSummaries.length * 2 - 1,
              ),
            ),
          ),
        );

        return slivers;
      },
    );
  }

  Widget _buildAnimeCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime,
  ) {
    final imageUrl = _resolveImageUrl(provider, anime.imageUrl);
    final title = anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name;
    final episodeLabel = _buildEpisodeLabel(anime);
    final sourceLabel = provider.activeHost?.displayName;

    return CupertinoAnimeCard(
      title: title,
      imageUrl: imageUrl,
      episodeLabel: episodeLabel,
      lastWatchTime: anime.lastWatchTime,
      onTap: () => widget.onAnimeTap(anime),
      isLoading: provider.isLoading,
      sourceLabel: sourceLabel,
      rating: null,
      summary: anime.summary,
    );
  }

  String _buildEpisodeLabel(SharedRemoteAnimeSummary anime) {
    final buffer = StringBuffer('共${anime.episodeCount}集');
    if (anime.hasMissingFiles) {
      buffer.write(' · 缺失文件');
    }
    return buffer.toString();
  }

  String? _resolveImageUrl(
    SharedRemoteLibraryProvider provider,
    String? imageUrl,
  ) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    if (imageUrl.startsWith('http')) {
      return imageUrl;
    }
    final baseUrl = provider.activeHost?.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      return imageUrl;
    }
    if (imageUrl.startsWith('/')) {
      return '$baseUrl$imageUrl';
    }
    return '$baseUrl/$imageUrl';
  }
}
