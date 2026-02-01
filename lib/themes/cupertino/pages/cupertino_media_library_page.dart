import 'dart:async';
import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_shared_remote_lan_scan_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_anime_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_glass_media_server_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_shared_anime_detail_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_management_sheet.dart';
import 'package:nipaplay/themes/cupertino/pages/network_media/cupertino_network_server_libraries_page.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/local_media_share_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/android_storage_helper.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_server_detail_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart'
    show MediaServerType;
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/pages/network_media/cupertino_dandanplay_library_page.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_smb_connection_dialog.dart';

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
          Consumer4<SharedRemoteLibraryProvider, JellyfinProvider,
              EmbyProvider, DandanplayRemoteProvider>(
            builder: (
              context,
              sharedProvider,
              jellyfinProvider,
              embyProvider,
              dandanProvider,
              _,
            ) {
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
                  if (!kIsWeb) ...[
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
                  ],
                  ..._buildNetworkMediaSection(
                    context,
                    jellyfinProvider,
                    embyProvider,
                    dandanProvider,
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
    DandanplayRemoteProvider dandanProvider,
  ) {
    final bool jellyfinConnected = jellyfinProvider.isConnected;
    final bool embyConnected = embyProvider.isConnected;
    final bool dandanConnected = dandanProvider.isConnected;
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

    if (dandanConnected) {
      cards.add(
        CupertinoGlassMediaServerCard(
          title: '弹弹play 媒体库',
          subtitle: _formatServerSubtitle(null, dandanProvider.serverUrl),
          icon: CupertinoIcons.chat_bubble_2_fill,
          accentColor: const Color(0xFFFFC857),
          summaryText: _buildDandanSummary(dandanProvider),
          isLoading: dandanProvider.isLoading,
          onTap: () => _openDandanplayLibraryPage(dandanProvider),
          onManage: () => _manageDandanplayConnection(dandanProvider),
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

  String _buildDandanSummary(DandanplayRemoteProvider provider) {
    final String syncedLabel = _formatDateTime(provider.lastSyncedAt);
    final int animeCount = provider.animeGroups.length;
    final int episodeCount = provider.episodes.length;
    return '番剧 $animeCount · 视频 $episodeCount · 最近同步：$syncedLabel';
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CupertinoButton(
                        onPressed: () => _openAddHostDialog(provider),
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.activeBlue, context),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        borderRadius: BorderRadius.circular(14),
                        child: const Text(
                          '添加共享客户端',
                          style: TextStyle(
                              fontSize: 15, color: CupertinoColors.white),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CupertinoButton(
                        onPressed: () => _openLanScanDialog(provider),
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemGrey5, context),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        borderRadius: BorderRadius.circular(14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.wifi,
                              size: 18,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '扫描局域网',
                              style: TextStyle(
                                fontSize: 15,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.label, context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                      label: '库管理',
                      icon: CupertinoIcons.folder,
                      onPressed: () => _showRemoteLibraryManagementBottomSheet(provider),
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
                    _buildActionButton(
                      context,
                      label: '扫描局域网',
                      icon: CupertinoIcons.wifi,
                      onPressed: () => _openLanScanDialog(provider),
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
      result =
          await CupertinoMediaServerDetailPage.showJellyfin(context, mediaId);
    } else {
      result = await CupertinoMediaServerDetailPage.showEmby(context, mediaId);
    }

    if (result == null || !mounted) {
      return;
    }

    PlaybackSession? playbackSession;
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
        playbackSession =
            await JellyfinService.instance.createPlaybackSession(
          itemId: jellyfinId,
          startPositionMs:
              result.lastPosition > 0 ? result.lastPosition : null,
        );
      } else if (result.filePath.startsWith('emby://')) {
        final embyPath = result.filePath.replaceFirst('emby://', '');
        final parts = embyPath.split('/');
        final embyId = parts.isNotEmpty ? parts.last : embyPath;
        final provider = context.read<EmbyProvider>();
        if (!provider.isConnected) {
          AdaptiveSnackBar.show(
            context,
            message: '未连接到 Emby 服务器',
            type: AdaptiveSnackBarType.warning,
          );
          return;
        }
        playbackSession = await EmbyService.instance.createPlaybackSession(
          itemId: embyId,
          startPositionMs:
              result.lastPosition > 0 ? result.lastPosition : null,
        );
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
      playbackSession: playbackSession,
    );

    await PlaybackService().play(playable);
    await context.read<WatchHistoryProvider>().refresh();
  }

  Future<void> _openDandanplayLibraryPage(
    DandanplayRemoteProvider provider,
  ) async {
    if (!provider.isConnected) {
      AdaptiveSnackBar.show(
        context,
        message: '请先连接弹弹play 远程服务',
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }

    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => const CupertinoDandanplayLibraryPage(),
      ),
    );
  }

  Future<void> _manageDandanplayConnection(
    DandanplayRemoteProvider provider,
  ) async {
    final bool hasExisting = provider.serverUrl?.isNotEmpty == true;
    final config = await showCupertinoDandanplayConnectionDialog(
      context: context,
      provider: provider,
    );
    if (config == null) {
      return;
    }

    try {
      await provider.connect(
        config.baseUrl,
        token: config.apiToken,
      );
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: hasExisting
            ? '弹弹play 远程服务配置已更新'
            : '弹弹play 远程服务已连接',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '连接失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
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

  Future<void> _showRemoteLibraryManagementBottomSheet(
      SharedRemoteLibraryProvider provider) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '共享库管理',
      floatingTitle: true,
      child: _SharedRemoteLibraryManagementContent(provider: provider),
    );
  }

  Future<void> _openAddHostDialog(SharedRemoteLibraryProvider provider) async {
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => IOS26AlertDialog(
        title: '添加NipaPlay共享客户端',
        input: const AdaptiveAlertDialogInput(
          placeholder: '例如：192.168.1.100（默认1180）或 192.168.1.100:2345',
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

  Future<void> _openLanScanDialog(SharedRemoteLibraryProvider provider) async {
    await CupertinoSharedRemoteLanScanDialog.show(
      context,
      provider: provider,
    );
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

enum _LibrarySource {
  local,
  webdav,
  smb,
}

class _RemoteScrapeCandidate {
  final String filePath;
  final String fileName;

  const _RemoteScrapeCandidate({
    required this.filePath,
    required this.fileName,
  });
}

class _RemoteScrapeResult {
  final int total;
  final int matched;
  final int failed;

  const _RemoteScrapeResult({
    required this.total,
    required this.matched,
    required this.failed,
  });
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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final LocalMediaShareService _localShareService =
      LocalMediaShareService.instance;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      onGenerateInitialRoutes: (_, __) => [
        CupertinoPageRoute<void>(
          builder: (routeContext) => _LocalMediaLibraryListPage(
            onAnimeTap: _openAnimeDetail,
          ),
        ),
      ],
    );
  }

  Future<void> _openAnimeDetail(_LocalMediaSummary summary) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    ThemeNotifier? themeNotifier;
    try {
      themeNotifier = context.read<ThemeNotifier>();
    } catch (_) {
      themeNotifier = null;
    }

    final sharedSummary = _toSharedSummary(summary);
    final displayMode = themeNotifier?.animeDetailDisplayMode;

    await navigator.push(
      CupertinoPageRoute<void>(
        builder: (routeContext) => CupertinoSharedAnimeDetailPage(
          anime: sharedSummary,
          hideBackButton: false,
          displayModeOverride: displayMode,
          showCloseButton: false,
          customEpisodeLoader: ({bool force = false}) =>
              _loadLocalEpisodes(summary.animeId, force: force),
          customPlayableBuilder: (routeContext, episode) =>
              _buildLocalPlayableItem(routeContext, summary, episode),
          sourceLabelOverride: '本地媒体库',
        ),
      ),
    );
  }

  SharedRemoteAnimeSummary _toSharedSummary(_LocalMediaSummary summary) {
    return SharedRemoteAnimeSummary(
      animeId: summary.animeId,
      name: summary.name,
      nameCn: summary.nameCn,
      summary: summary.summary,
      imageUrl: summary.imageUrl,
      lastWatchTime:
          summary.lastWatchTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      episodeCount: summary.episodeCount,
      hasMissingFiles: summary.hasMissingFiles,
    );
  }

  Future<List<SharedRemoteEpisode>> _loadLocalEpisodes(
    int animeId, {
    bool force = false,
  }) async {
    if (force) {
      // 预留参数：本地数据目前不区分强制刷新与否
    }
    final detail = await _localShareService.getAnimeDetail(animeId);
    if (detail == null) {
      return const [];
    }

    final rawEpisodes = detail['episodes'];
    if (rawEpisodes is! List) {
      return const [];
    }

    return rawEpisodes
        .whereType<Map<String, dynamic>>()
        .map(SharedRemoteEpisode.fromJson)
        .toList();
  }

  Future<PlayableItem> _buildLocalPlayableItem(
    BuildContext routeContext,
    _LocalMediaSummary summary,
    SharedRemoteEpisode episode,
  ) async {
    final sharedEpisode =
        _localShareService.getEpisodeByShareId(episode.shareId);
    if (sharedEpisode == null) {
      throw '找不到对应的本地媒体文件';
    }

    final historyItem = sharedEpisode.historyItem;
    var filePath = historyItem.filePath;
    PlaybackSession? playbackSession;

    bool fileExists = false;

    if (filePath.startsWith('jellyfin://')) {
      final jellyfinId = filePath.replaceFirst('jellyfin://', '');
      try {
        final jellyfinProvider = routeContext.read<JellyfinProvider>();
        if (!jellyfinProvider.isConnected) {
          throw '未连接到 Jellyfin 服务器';
        }
        playbackSession =
            await JellyfinService.instance.createPlaybackSession(
          itemId: jellyfinId,
          startPositionMs:
              historyItem.lastPosition > 0 ? historyItem.lastPosition : null,
        );
        fileExists = true;
      } catch (e) {
        throw '获取 Jellyfin 播放地址失败：$e';
      }
    } else if (filePath.startsWith('emby://')) {
      final embyPath = filePath.replaceFirst('emby://', '');
      final parts = embyPath.split('/');
      final embyId = parts.isNotEmpty ? parts.last : embyPath;
      try {
        final embyProvider = routeContext.read<EmbyProvider>();
        if (!embyProvider.isConnected) {
          throw '未连接到 Emby 服务器';
        }
        playbackSession = await EmbyService.instance.createPlaybackSession(
          itemId: embyId,
          startPositionMs:
              historyItem.lastPosition > 0 ? historyItem.lastPosition : null,
        );
        fileExists = true;
      } catch (e) {
        throw '获取 Emby 播放地址失败：$e';
      }
    } else {
      if (kIsWeb) {
        fileExists = true;
      } else {
        final file = File(filePath);
        fileExists = file.existsSync();

        if (!fileExists && Platform.isIOS) {
          final altPath = filePath.startsWith('/private')
              ? filePath.replaceFirst('/private', '')
              : '/private$filePath';
          final altFile = File(altPath);
          if (altFile.existsSync()) {
            filePath = altPath;
            historyItem.filePath = altPath;
            fileExists = true;
          }
        }

        if (!fileExists) {
          throw '文件不存在或无法访问：${p.basename(filePath)}';
        }
      }
    }

    if (!fileExists) {
      throw '无法读取媒体文件：${p.basename(filePath)}';
    }

    return PlayableItem(
      videoPath: filePath,
      title: historyItem.animeName.isNotEmpty
          ? historyItem.animeName
          : summary.displayTitle,
      subtitle: historyItem.episodeTitle ?? episode.title,
      animeId: historyItem.animeId ?? summary.animeId,
      playbackSession: playbackSession,
      episodeId:
          historyItem.episodeId ?? episode.episodeId ?? episode.shareId.hashCode,
      historyItem: historyItem,
    );
  }
}

class _LocalMediaLibraryListPage extends StatefulWidget {
  const _LocalMediaLibraryListPage({
    required this.onAnimeTap,
  });

  final Future<void> Function(_LocalMediaSummary) onAnimeTap;

  @override
  State<_LocalMediaLibraryListPage> createState() =>
      _LocalMediaLibraryListPageState();
}

class _LocalMediaLibraryListPageState
    extends State<_LocalMediaLibraryListPage> {
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

  Future<void> _openAnimeDetail(_LocalMediaSummary summary) {
    if (!mounted) {
      return Future.value();
    }
    return widget.onAnimeTap(summary);
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
  _LibrarySource _selectedSource = _LibrarySource.local;
  List<WebDAVConnection> _webdavConnections = [];
  final Map<String, List<WebDAVFile>> _webdavFolderContents = {};
  final Set<String> _expandedWebDAVConnections = {};
  final Set<String> _expandedWebDAVFolders = {};
  final Set<String> _loadingWebDAVFolders = {};
  bool _isLoadingWebDAV = false;
  bool _webdavInitialized = false;
  String? _webdavErrorMessage;
  List<SMBConnection> _smbConnections = [];
  final Map<String, List<SMBFileEntry>> _smbFolderContents = {};
  final Set<String> _expandedSMBConnections = {};
  final Set<String> _expandedSMBFolders = {};
  final Set<String> _loadingSMBFolders = {};
  bool _isLoadingSMB = false;
  bool _smbInitialized = false;
  String? _smbErrorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _initWebDAVService();
    _initSMBService();
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
          const SizedBox(height: 20),
          _buildLibrarySourceToggle(context),
        ];

        if (_selectedSource == _LibrarySource.local) {
          sections.addAll([
            const SizedBox(height: 16),
            _buildFolderSection(context, scanService),
          ]);

          if (scanService.detectedChanges.isNotEmpty) {
            sections.addAll([
              const SizedBox(height: 20),
              _buildDetectedChangesInfo(context, scanService),
            ]);
          }
        } else if (_selectedSource == _LibrarySource.webdav) {
          sections.addAll([
            const SizedBox(height: 16),
            _buildWebDAVSection(context),
          ]);
        } else {
          sections.addAll([
            const SizedBox(height: 16),
            _buildSMBSection(context),
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
        _buildActionButton(
          context,
          label: '添加 WebDAV 服务器',
          icon: CupertinoIcons.cloud_upload,
          onPressed: _showWebDAVConnectionDialog,
        ),
        _buildActionButton(
          context,
          label: '添加 SMB 服务器',
          icon: CupertinoIcons.folder_badge_plus,
          onPressed: () => _showSMBConnectionDialog(),
        ),
      ],
    );
  }

  Widget _buildLibrarySourceToggle(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '查看内容',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '在本地文件夹、WebDAV 服务器与 SMB 服务器之间切换。',
          style: TextStyle(fontSize: 13, color: subtitleColor),
        ),
        const SizedBox(height: 12),
        CupertinoSlidingSegmentedControl<_LibrarySource>(
          backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey5,
            context,
          ),
          thumbColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey3,
            context,
          ),
          groupValue: _selectedSource,
          children: const {
            _LibrarySource.local: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('本地媒体'),
            ),
            _LibrarySource.webdav: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('WebDAV'),
            ),
            _LibrarySource.smb: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('SMB'),
            ),
          },
          onValueChanged: (value) {
            if (value == null || value == _selectedSource) {
              return;
            }
            setState(() {
              _selectedSource = value;
            });
          },
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

  Widget _buildWebDAVSection(BuildContext context) {
    final children = <Widget>[
      _buildWebDAVHeader(context),
      const SizedBox(height: 12),
    ];

    if (_isLoadingWebDAV && !_webdavInitialized) {
      children.add(_buildWebDAVPlaceholder(
        context,
        title: '正在加载连接',
        subtitle: '正在读取已保存的 WebDAV 服务器配置…',
      ));
    } else if (_webdavErrorMessage != null) {
      children.add(_buildWebDAVPlaceholder(
        context,
        title: '加载失败',
        subtitle: _webdavErrorMessage!,
        isError: true,
      ));
    } else if (_webdavConnections.isEmpty) {
      children.add(_buildWebDAVPlaceholder(
        context,
        title: '尚未添加 WebDAV 服务器',
        subtitle: '点击上方按钮添加服务器，即可浏览远程媒体并挂载到本地媒体库。',
      ));
    } else {
      children.addAll(
        _webdavConnections
            .map((connection) =>
                _buildWebDAVConnectionCard(context, connection))
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildWebDAVHeader(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WebDAV 服务器',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '连接远程 WebDAV 服务器，浏览目录并选择需要挂载的媒体文件夹。',
          style: TextStyle(fontSize: 13, color: subtitleColor, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildWebDAVPlaceholder(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor = isError
        ? CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context)
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor = isError
        ? CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context)
            .withValues(alpha: 0.8)
        : CupertinoDynamicColor.resolve(
            CupertinoColors.secondaryLabel,
            context,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: subtitleColor, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildWebDAVConnectionCard(
    BuildContext context,
    WebDAVConnection connection,
  ) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final urlColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final dividerColor =
        CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final statusColor = connection.isConnected
        ? CupertinoColors.activeGreen
        : CupertinoColors.systemRed;
    final isExpanded =
        _expandedWebDAVConnections.contains(connection.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              CupertinoDynamicColor.resolve(statusColor, context).withValues(
            alpha: 0.25,
          ),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.cloud,
                  color:
                      CupertinoDynamicColor.resolve(statusColor, context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: connection.isConnected
                        ? () => _toggleWebDAVConnection(connection)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connection.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connection.url,
                          style: TextStyle(fontSize: 12, color: urlColor),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: CupertinoDynamicColor.resolve(
                                  statusColor,
                                  context,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                connection.isConnected ? '已连接' : '未连接',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoDynamicColor.resolve(
                                    statusColor,
                                    context,
                                  ),
                                ),
                              ),
                            ),
                            if (connection.isConnected)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  isExpanded
                                      ? CupertinoIcons.chevron_down
                                      : CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: urlColor,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWebDAVIconButton(
                      icon: CupertinoIcons.pencil,
                      onPressed: () =>
                          _showWebDAVConnectionDialog(editConnection: connection),
                    ),
                    _buildWebDAVIconButton(
                      icon: CupertinoIcons.delete,
                      onPressed: () => _removeWebDAVConnection(connection),
                    ),
                    _buildWebDAVIconButton(
                      icon: CupertinoIcons.refresh_thin,
                      onPressed: () => _testWebDAVConnection(connection),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!connection.isConnected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '点击右上角刷新图标测试连接，成功后即可展开并浏览目录。',
                  style:
                      TextStyle(fontSize: 12, color: urlColor, height: 1.4),
                ),
              ),
            ),
          if (connection.isConnected && isExpanded)
            Container(height: 1, color: dividerColor),
          if (connection.isConnected && isExpanded)
            _buildWebDAVFileList(connection, '/', depth: 0),
        ],
      ),
    );
  }

  Widget _buildWebDAVFileList(
    WebDAVConnection connection,
    String path, {
    required int depth,
  }) {
    final key = _webdavKey(connection, path);
    final files = _webdavFolderContents[key];
    final isLoading = _loadingWebDAVFolders.contains(key);

    final indentation = 16.0 + depth * 14;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indentation, 16, 16, 16),
        child: const CupertinoActivityIndicator(radius: 10),
      );
    }

    if (files == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indentation, 16, 16, 16),
        child: Text(
          '尚未加载内容',
          style: TextStyle(
            fontSize: 13,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              context,
            ),
          ),
        ),
      );
    }

    if (files.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indentation, 16, 16, 16),
        child: Text(
          '文件夹为空',
          style: TextStyle(
            fontSize: 13,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              context,
            ),
          ),
        ),
      );
    }

    return Column(
      children: files
          .map((file) => _buildWebDAVNode(connection, file, depth))
          .toList(),
    );
  }

  Widget _buildWebDAVNode(
    WebDAVConnection connection,
    WebDAVFile file,
    int depth,
  ) {
    final key = _webdavKey(connection, file.path);
    final isExpanded = _expandedWebDAVFolders.contains(key);
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.0 + depth * 14, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                file.isDirectory
                    ? CupertinoIcons.folder
                    : CupertinoIcons.play_arrow_solid,
                size: 18,
                color: file.isDirectory
                    ? CupertinoDynamicColor.resolve(
                        CupertinoColors.activeBlue,
                        context,
                      )
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey,
                        context,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: TextStyle(
                        fontSize: 14,
                        color: labelColor,
                        fontWeight:
                            file.isDirectory ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (!file.isDirectory && file.size != null && file.size! > 0)
                      Text(
                        '${(file.size! / 1024 / 1024).toStringAsFixed(1)} MB',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                  ],
                ),
              ),
              if (file.isDirectory)
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: () =>
                          _scanWebDAVFolder(connection, file.path, file.name),
                      child: const Text('刮削'),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: () => _toggleWebDAVFolder(connection, file.path),
                      child: Icon(
                        isExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 16,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                )
              else
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minSize: 28,
                  onPressed: () => _playWebDAVFile(connection, file),
                  child: const Text('播放'),
                ),
            ],
          ),
        ),
        if (file.isDirectory && isExpanded)
          _buildWebDAVFileList(connection, file.path, depth: depth + 1),
      ],
    );
  }

  CupertinoButton _buildWebDAVIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 30,
      onPressed: onPressed,
      child: Icon(icon, size: 18),
    );
  }

  Future<void> _initWebDAVService() async {
    setState(() {
      _isLoadingWebDAV = true;
      _webdavErrorMessage = null;
    });

    try {
      await WebDAVService.instance.initialize();
      if (!mounted) return;
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
        _webdavInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _webdavErrorMessage = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingWebDAV = false;
      });
    }
  }

  void _refreshWebDAVConnections() {
    if (!mounted) return;
    setState(() {
      _webdavConnections = WebDAVService.instance.connections;
    });
  }

  Future<void> _showWebDAVConnectionDialog({
    WebDAVConnection? editConnection,
  }) async {
    final result = await WebDAVConnectionDialog.show(
      context,
      editConnection: editConnection,
    );

    if (result == true) {
      _refreshWebDAVConnections();
      _showSnack(editConnection == null ? '已添加 WebDAV 连接' : 'WebDAV 连接已更新');
    }
  }

  Future<void> _removeWebDAVConnection(WebDAVConnection connection) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除 WebDAV 连接'),
        content: Text('确定要删除“${connection.name}”吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WebDAVService.instance.removeConnection(connection.name);
      if (!mounted) return;
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
        _expandedWebDAVConnections.remove(connection.name);
        _webdavFolderContents
            .removeWhere((key, value) => key.startsWith('${connection.name}:'));
        _expandedWebDAVFolders
            .removeWhere((key) => key.startsWith('${connection.name}:'));
      });
      _showSnack('已删除 ${connection.name}');
    }
  }

  Future<void> _testWebDAVConnection(WebDAVConnection connection) async {
    _showSnack('正在测试连接…');
    await WebDAVService.instance.updateConnectionStatus(connection.name);
    if (!mounted) return;
    _refreshWebDAVConnections();
    final updated = WebDAVService.instance.getConnection(connection.name);
    if (updated?.isConnected == true) {
      _showSnack('连接成功，可以展开浏览目录');
    } else {
      _showSnack('连接失败，请检查配置');
    }
  }

  void _toggleWebDAVConnection(WebDAVConnection connection) {
    if (!connection.isConnected) {
      _showSnack('请先测试并建立连接');
      return;
    }

    final alreadyExpanded =
        _expandedWebDAVConnections.contains(connection.name);
    setState(() {
      if (alreadyExpanded) {
        _expandedWebDAVConnections.remove(connection.name);
      } else {
        _expandedWebDAVConnections.add(connection.name);
      }
    });

    if (!alreadyExpanded) {
      _loadWebDAVFolderChildren(connection, '/');
    }
  }

  void _toggleWebDAVFolder(WebDAVConnection connection, String path) {
    final key = _webdavKey(connection, path);
    final alreadyExpanded = _expandedWebDAVFolders.contains(key);
    setState(() {
      if (alreadyExpanded) {
        _expandedWebDAVFolders.remove(key);
      } else {
        _expandedWebDAVFolders.add(key);
      }
    });

    if (!alreadyExpanded) {
      _loadWebDAVFolderChildren(connection, path);
    }
  }

  Future<void> _loadWebDAVFolderChildren(
    WebDAVConnection connection,
    String path,
  ) async {
    final normalizedPath = path.isEmpty ? '/' : path;
    final key = _webdavKey(connection, normalizedPath);

    if (_loadingWebDAVFolders.contains(key)) {
      return;
    }

    setState(() {
      _loadingWebDAVFolders.add(key);
    });

    try {
      final files =
          await WebDAVService.instance.listDirectory(connection, normalizedPath);
      if (!mounted) return;
      setState(() {
        _webdavFolderContents[key] = files;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('加载目录失败：$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingWebDAVFolders.remove(key);
      });
    }
  }

  int? _parseMatchId(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<_RemoteScrapeResult> _scrapeRemoteFiles({
    required String sourceLabel,
    required List<_RemoteScrapeCandidate> candidates,
  }) async {
    int matched = 0;
    int failed = 0;

    for (final candidate in candidates) {
      try {
        final videoInfo = await DandanplayService.getVideoInfo(candidate.filePath);
        final matches = videoInfo['matches'];
        if (videoInfo['isMatched'] != true ||
            matches is! List ||
            matches.isEmpty ||
            matches.first is! Map) {
          failed++;
          continue;
        }

        final match = Map<String, dynamic>.from(matches.first as Map);
        final animeId = _parseMatchId(match['animeId']);
        final episodeId = _parseMatchId(match['episodeId']);
        if (animeId == null || episodeId == null) {
          failed++;
          continue;
        }

        final existingHistory =
            await WatchHistoryManager.getHistoryItem(candidate.filePath);
        final rawAnimeTitle = videoInfo['animeTitle'] ?? match['animeTitle'];
        final rawEpisodeTitle =
            videoInfo['episodeTitle'] ?? match['episodeTitle'];
        final rawHash = videoInfo['fileHash'] ?? videoInfo['hash'];
        final animeTitle = rawAnimeTitle?.toString();
        final episodeTitle = rawEpisodeTitle?.toString();
        final hashString = rawHash?.toString();
        final durationFromMatch = (videoInfo['duration'] is int)
            ? videoInfo['duration'] as int
            : (existingHistory?.duration ?? 0);
        final preserveProgress = existingHistory != null &&
            existingHistory.watchProgress > 0.01 &&
            !existingHistory.isFromScan;

        final historyItem = WatchHistoryItem(
          filePath: candidate.filePath,
          animeName: animeTitle?.isNotEmpty == true
              ? animeTitle!
              : (existingHistory?.animeName ??
                  p.basenameWithoutExtension(candidate.fileName)),
          episodeTitle: episodeTitle?.isNotEmpty == true
              ? episodeTitle
              : existingHistory?.episodeTitle,
          episodeId: episodeId,
          animeId: animeId,
          watchProgress: preserveProgress
              ? existingHistory!.watchProgress
              : (existingHistory?.watchProgress ?? 0.0),
          lastPosition: preserveProgress
              ? existingHistory!.lastPosition
              : (existingHistory?.lastPosition ?? 0),
          duration: durationFromMatch,
          lastWatchTime: DateTime.now(),
          thumbnailPath: existingHistory?.thumbnailPath,
          isFromScan: !preserveProgress,
          videoHash: hashString?.isNotEmpty == true
              ? hashString
              : existingHistory?.videoHash,
        );
        await WatchHistoryManager.addOrUpdateHistory(historyItem);
        matched++;
      } catch (e) {
        failed++;
        debugPrint('$sourceLabel 刮削失败: ${candidate.fileName} -> $e');
      }
    }

    return _RemoteScrapeResult(
      total: candidates.length,
      matched: matched,
      failed: failed,
    );
  }

  Future<void> _scanWebDAVFolder(
    WebDAVConnection connection,
    String folderPath,
    String folderName,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('刮削 WebDAV 文件夹'),
        content: Text('确定要刮削“$folderName”吗？\n刮削后将把其中的视频文件匹配到 WebDAV 媒体库。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刮削'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      _showSnack('正在刮削 $folderName…');
      final files = await _getWebDAVVideoFiles(connection, folderPath);
      if (files.isEmpty) {
        _showSnack('未找到可刮削的视频文件');
        return;
      }

      final candidates = files
          .map((file) => _RemoteScrapeCandidate(
                filePath:
                    WebDAVService.instance.getFileUrl(connection, file.path),
                fileName: file.name,
              ))
          .toList();
      final result = await _scrapeRemoteFiles(
        sourceLabel: 'WebDAV',
        candidates: candidates,
      );

      if (!mounted) return;
      await context.read<WatchHistoryProvider>().refresh();
      if (result.matched == 0) {
        _showSnack('刮削完成，但未匹配到番剧信息');
      } else if (result.failed > 0) {
        _showSnack('刮削完成：成功 ${result.matched}/${result.total}，失败 ${result.failed}');
      } else {
        _showSnack('刮削完成：成功 ${result.matched}/${result.total}');
      }
    } catch (e) {
      _showSnack('刮削失败：$e');
    }
  }

  Future<List<WebDAVFile>> _getWebDAVVideoFiles(
    WebDAVConnection connection,
    String folderPath,
  ) async {
    final List<WebDAVFile> videoFiles = [];
    try {
      final files = await WebDAVService.instance.listDirectory(
        connection,
        folderPath,
      );
      for (final file in files) {
        if (file.isDirectory) {
          final subFiles = await _getWebDAVVideoFiles(connection, file.path);
          videoFiles.addAll(subFiles);
        } else if (WebDAVService.instance.isVideoFile(file.name)) {
          videoFiles.add(file);
        }
      }
    } catch (e) {
      debugPrint('获取WebDAV视频文件失败: $e');
    }
    return videoFiles;
  }

  Future<void> _playWebDAVFile(
    WebDAVConnection connection,
    WebDAVFile file,
  ) async {
    try {
      final fileUrl = WebDAVService.instance.getFileUrl(connection, file.path);
      final historyItem = WatchHistoryItem(
        filePath: fileUrl,
        animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        episodeTitle: '',
        duration: 0,
        lastPosition: 0,
        watchProgress: 0.0,
        lastWatchTime: DateTime.now(),
      );
      await WatchHistoryManager.addOrUpdateHistory(historyItem);

      final playable = PlayableItem(
        videoPath: fileUrl,
        title: historyItem.animeName,
        historyItem: historyItem,
      );
      await PlaybackService().play(playable);
    } catch (e) {
      _showSnack('播放失败：$e');
    }
  }

  String _webdavKey(WebDAVConnection connection, String path) {
    return '${connection.name}:$path';
  }

  Widget _buildSMBSection(BuildContext context) {
    final children = <Widget>[
      _buildSMBHeader(context),
      const SizedBox(height: 12),
    ];

    if (_isLoadingSMB && !_smbInitialized) {
      children.add(_buildSMBPlaceholder(
        context,
        title: '正在加载连接',
        subtitle: '正在读取已保存的 SMB 服务器配置…',
      ));
    } else if (_smbErrorMessage != null) {
      children.add(_buildSMBPlaceholder(
        context,
        title: '加载失败',
        subtitle: _smbErrorMessage!,
        isError: true,
      ));
    } else if (_smbConnections.isEmpty) {
      children.add(_buildSMBPlaceholder(
        context,
        title: '尚未添加 SMB 服务器',
        subtitle: '点击上方按钮添加服务器，即可浏览局域网共享并挂载到本地媒体库。',
      ));
    } else {
      children.addAll(
        _smbConnections
            .map((connection) => _buildSMBConnectionCard(context, connection))
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildSMBHeader(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SMB 服务器',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '连接局域网中的 SMB/NAS 共享，浏览目录并选择需要挂载的媒体文件夹。',
          style: TextStyle(fontSize: 13, color: subtitleColor, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildSMBPlaceholder(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor = isError
        ? CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context)
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor = isError
        ? CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context)
            .withValues(alpha: 0.8)
        : CupertinoDynamicColor.resolve(
            CupertinoColors.secondaryLabel,
            context,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: subtitleColor, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSMBConnectionCard(
    BuildContext context,
    SMBConnection connection,
  ) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final dividerColor =
        CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final statusColor = connection.isConnected
        ? CupertinoColors.activeGreen
        : CupertinoColors.systemRed;
    final isExpanded = _expandedSMBConnections.contains(connection.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(statusColor, context)
              .withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.desktopcomputer,
                  color: CupertinoDynamicColor.resolve(statusColor, context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: connection.isConnected
                        ? () => _toggleSMBConnection(connection)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connection.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connection.port != 445
                              ? '${connection.host}:${connection.port}'
                              : connection.host,
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                        if (connection.username.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              '用户：${connection.username}${connection.domain.isNotEmpty ? ' @${connection.domain}' : ''}',
                              style:
                                  TextStyle(fontSize: 12, color: subtitleColor),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: CupertinoDynamicColor.resolve(
                                  statusColor,
                                  context,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                connection.isConnected ? '已连接' : '未连接',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoDynamicColor.resolve(
                                    statusColor,
                                    context,
                                  ),
                                ),
                              ),
                            ),
                            if (connection.isConnected)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  isExpanded
                                      ? CupertinoIcons.chevron_down
                                      : CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: subtitleColor,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSMBIconButton(
                      icon: CupertinoIcons.pencil,
                      onPressed: () =>
                          _showSMBConnectionDialog(editConnection: connection),
                    ),
                    _buildSMBIconButton(
                      icon: CupertinoIcons.delete,
                      onPressed: () => _removeSMBConnection(connection),
                    ),
                    _buildSMBIconButton(
                      icon: CupertinoIcons.refresh_thin,
                      onPressed: () => _refreshSMBConnection(connection),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!connection.isConnected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '点击右上角刷新图标以连接并加载目录。',
                  style:
                      TextStyle(fontSize: 12, color: subtitleColor, height: 1.4),
                ),
              ),
            ),
          if (connection.isConnected && isExpanded)
            Container(height: 1, color: dividerColor),
          if (connection.isConnected && isExpanded)
            _buildSMBFileList(connection, '/', depth: 0),
        ],
      ),
    );
  }

  Widget _buildSMBFileList(
    SMBConnection connection,
    String path, {
    required int depth,
  }) {
    final key = _smbKey(connection, path);
    final files = _smbFolderContents[key];
    final isLoading = _loadingSMBFolders.contains(key);
    final indentation = 16.0 + depth * 14;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indentation, 16, 16, 16),
        child: const CupertinoActivityIndicator(radius: 10),
      );
    }

    if (files == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indentation, 16, 16, 16),
        child: Text(
          '尚未加载内容',
          style: TextStyle(
            fontSize: 13,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              context,
            ),
          ),
        ),
      );
    }

    if (files.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indentation, 16, 16, 16),
        child: Text(
          '文件夹为空',
          style: TextStyle(
            fontSize: 13,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              context,
            ),
          ),
        ),
      );
    }

    return Column(
      children:
          files.map((file) => _buildSMBNode(connection, file, depth)).toList(),
    );
  }

  Widget _buildSMBNode(
    SMBConnection connection,
    SMBFileEntry file,
    int depth,
  ) {
    final key = _smbKey(connection, file.path);
    final isExpanded = _expandedSMBFolders.contains(key);
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.0 + depth * 14, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                file.isDirectory
                    ? CupertinoIcons.folder
                    : CupertinoIcons.play_arrow_solid,
                size: 18,
                color: file.isDirectory
                    ? CupertinoDynamicColor.resolve(
                        CupertinoColors.activeBlue,
                        context,
                      )
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey,
                        context,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: TextStyle(
                        fontSize: 14,
                        color: labelColor,
                        fontWeight:
                            file.isDirectory ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (!file.isDirectory && file.size != null && file.size! > 0)
                      Text(
                        '${(file.size! / 1024 / 1024).toStringAsFixed(1)} MB',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                  ],
                ),
              ),
              if (file.isDirectory)
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: () =>
                          _scanSMBFolder(connection, file.path, file.name),
                      child: const Text('刮削'),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: () => _toggleSMBFolder(connection, file.path),
                      child: Icon(
                        isExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 16,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                )
              else
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minSize: 28,
                  onPressed: () => _playSMBFile(connection, file),
                  child: const Text('播放'),
                ),
            ],
          ),
        ),
        if (file.isDirectory && isExpanded)
          _buildSMBFileList(connection, file.path, depth: depth + 1),
      ],
    );
  }

  CupertinoButton _buildSMBIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 30,
      onPressed: onPressed,
      child: Icon(icon, size: 18),
    );
  }

  Future<void> _initSMBService() async {
    setState(() {
      _isLoadingSMB = true;
      _smbErrorMessage = null;
    });

    try {
      await SMBService.instance.initialize();
      if (!mounted) return;
      setState(() {
        _smbConnections = SMBService.instance.connections;
        _smbInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _smbErrorMessage = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingSMB = false;
      });
    }
  }

  void _refreshSMBConnections() {
    if (!mounted) return;
    setState(() {
      _smbConnections = SMBService.instance.connections;
    });
  }

  Future<void> _showSMBConnectionDialog({
    SMBConnection? editConnection,
  }) async {
    final result = await CupertinoSmbConnectionDialog.show(
      context,
      editConnection: editConnection,
    );

    if (result == true) {
      _refreshSMBConnections();
      _showSnack(editConnection == null ? '已添加 SMB 连接' : 'SMB 连接已更新');
    }
  }

  Future<void> _removeSMBConnection(SMBConnection connection) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除 SMB 连接'),
        content: Text('确定要删除“${connection.name}”吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SMBService.instance.removeConnection(connection.name);
      if (!mounted) return;
      setState(() {
        _smbConnections = SMBService.instance.connections;
        _expandedSMBConnections.remove(connection.name);
        _smbFolderContents
            .removeWhere((key, value) => key.startsWith('${connection.name}:'));
        _expandedSMBFolders
            .removeWhere((key) => key.startsWith('${connection.name}:'));
      });
      _showSnack('已删除 ${connection.name}');
    }
  }

  Future<void> _refreshSMBConnection(SMBConnection connection) async {
    _showSnack('正在刷新 SMB 连接…');

    await SMBService.instance.updateConnectionStatus(connection.name);
    if (!mounted) return;

    _refreshSMBConnections();
    final updated = SMBService.instance.getConnection(connection.name);
    if (updated?.isConnected != true) {
      _showSnack('连接失败，请检查配置');
      return;
    }

    setState(() {
      _smbFolderContents
          .removeWhere((key, _) => key.startsWith('${connection.name}:'));
      _loadingSMBFolders
          .removeWhere((key) => key.startsWith('${connection.name}:'));
    });

    final expandedFolderKeys = _expandedSMBFolders
        .where((key) => key.startsWith('${connection.name}:'))
        .toList();
    final pathsToReload = <String>{'/'};
    for (final key in expandedFolderKeys) {
      final path = key.substring(connection.name.length + 1);
      if (path.trim().isNotEmpty) {
        pathsToReload.add(path);
      }
    }

    for (final path in pathsToReload) {
      await _loadSMBFolderChildren(updated!, path);
    }

    _showSnack('已刷新 ${connection.name}');
  }

  void _toggleSMBConnection(SMBConnection connection) {
    if (!connection.isConnected) {
      _showSnack('请先刷新连接以加载目录');
      return;
    }

    final alreadyExpanded = _expandedSMBConnections.contains(connection.name);
    setState(() {
      if (alreadyExpanded) {
        _expandedSMBConnections.remove(connection.name);
      } else {
        _expandedSMBConnections.add(connection.name);
      }
    });

    if (!alreadyExpanded) {
      _loadSMBFolderChildren(connection, '/');
    }
  }

  void _toggleSMBFolder(SMBConnection connection, String path) {
    final key = _smbKey(connection, path);
    final alreadyExpanded = _expandedSMBFolders.contains(key);
    setState(() {
      if (alreadyExpanded) {
        _expandedSMBFolders.remove(key);
      } else {
        _expandedSMBFolders.add(key);
      }
    });

    if (!alreadyExpanded) {
      _loadSMBFolderChildren(connection, path);
    }
  }

  Future<void> _loadSMBFolderChildren(
    SMBConnection connection,
    String path,
  ) async {
    final normalizedPath = path.isEmpty ? '/' : path;
    final key = _smbKey(connection, normalizedPath);

    if (_loadingSMBFolders.contains(key)) {
      return;
    }

    setState(() {
      _loadingSMBFolders.add(key);
    });

    try {
      final files = await SMBService.instance.listDirectory(
        connection,
        normalizedPath,
      );
      if (!mounted) return;
      setState(() {
        _smbFolderContents[key] = files;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('加载目录失败：$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingSMBFolders.remove(key);
      });
    }
  }

  Future<void> _scanSMBFolder(
    SMBConnection connection,
    String folderPath,
    String folderName,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('刮削 SMB 文件夹'),
        content: Text('确定要刮削“$folderName”吗？\n刮削后将把其中的视频文件匹配到 SMB 媒体库。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刮削'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      _showSnack('正在刮削 $folderName…');
      final files = await _getSMBVideoFiles(connection, folderPath);
      if (files.isEmpty) {
        _showSnack('未找到可刮削的视频文件');
        return;
      }

      final candidates = files
          .map((file) => _RemoteScrapeCandidate(
                filePath:
                    SMBProxyService.instance.buildStreamUrl(connection, file.path),
                fileName: file.name,
              ))
          .toList();
      final result = await _scrapeRemoteFiles(
        sourceLabel: 'SMB',
        candidates: candidates,
      );

      if (!mounted) return;
      await context.read<WatchHistoryProvider>().refresh();
      if (result.matched == 0) {
        _showSnack('刮削完成，但未匹配到番剧信息');
      } else if (result.failed > 0) {
        _showSnack('刮削完成：成功 ${result.matched}/${result.total}，失败 ${result.failed}');
      } else {
        _showSnack('刮削完成：成功 ${result.matched}/${result.total}');
      }
    } catch (e) {
      _showSnack('刮削失败：$e');
    }
  }

  Future<List<SMBFileEntry>> _getSMBVideoFiles(
    SMBConnection connection,
    String folderPath,
  ) async {
    final List<SMBFileEntry> videoFiles = [];
    try {
      final files = await SMBService.instance.listDirectory(
        connection,
        folderPath,
      );
      for (final file in files) {
        if (file.isDirectory) {
          final subFiles = await _getSMBVideoFiles(connection, file.path);
          videoFiles.addAll(subFiles);
        } else if (SMBService.instance.isVideoFile(file.name)) {
          videoFiles.add(file);
        }
      }
    } catch (e) {
      debugPrint('获取SMB视频文件失败: $e');
    }
    return videoFiles;
  }

  Future<void> _playSMBFile(
    SMBConnection connection,
    SMBFileEntry file,
  ) async {
    try {
      final fileUrl = SMBProxyService.instance.buildStreamUrl(connection, file.path);
      final historyItem = WatchHistoryItem(
        filePath: fileUrl,
        animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        episodeTitle: '',
        duration: 0,
        lastPosition: 0,
        watchProgress: 0.0,
        lastWatchTime: DateTime.now(),
      );
      await WatchHistoryManager.addOrUpdateHistory(historyItem);

      final playable = PlayableItem(
        videoPath: fileUrl,
        title: historyItem.animeName,
        historyItem: historyItem,
      );
      await PlaybackService().play(playable);
    } catch (e) {
      _showSnack('播放失败：$e');
    }
  }

  String _smbKey(SMBConnection connection, String path) {
    return '${connection.name}:$path';
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

class _SharedRemoteLibraryManagementContent extends StatefulWidget {
  const _SharedRemoteLibraryManagementContent({required this.provider});

  final SharedRemoteLibraryProvider provider;

  @override
  State<_SharedRemoteLibraryManagementContent> createState() =>
      _SharedRemoteLibraryManagementContentState();
}

class _SharedRemoteLibraryManagementContentState
    extends State<_SharedRemoteLibraryManagementContent> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;
  Timer? _pollTimer;
  bool _pollRequestInFlight = false;
  final Map<String, List<SharedRemoteFileEntry>> _expandedRemoteDirectories = {};
  final Set<String> _loadingRemoteDirectories = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.provider.scannedFolders.isEmpty &&
          widget.provider.scanStatus == null) {
        widget.provider.refreshManagement(userInitiated: true).then((_) {
          if (!mounted) return;
          _maybeStartPolling(widget.provider);
        });
      } else {
        _maybeStartPolling(widget.provider);
      }
    });
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeStartPolling(SharedRemoteLibraryProvider provider) {
    if (provider.scanStatus?.isScanning == true) {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }

      final provider = widget.provider;
      if (provider.scanStatus?.isScanning != true) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }

      if (_pollRequestInFlight) {
        return;
      }
      _pollRequestInFlight = true;
      provider.refreshScanStatus(showLoading: false).whenComplete(() {
        _pollRequestInFlight = false;
      });
    });
  }

  Future<void> _toggleRemoteDirectory(
    SharedRemoteLibraryProvider provider,
    String directoryPath,
  ) async {
    final normalized = directoryPath.trim();
    if (normalized.isEmpty) {
      return;
    }

    if (_expandedRemoteDirectories.containsKey(normalized)) {
      setState(() {
        _expandedRemoteDirectories.remove(normalized);
      });
      return;
    }

    await _loadRemoteDirectory(provider, normalized);
  }

  Future<void> _loadRemoteDirectory(
    SharedRemoteLibraryProvider provider,
    String directoryPath,
  ) async {
    if (_loadingRemoteDirectories.contains(directoryPath)) {
      return;
    }

    setState(() {
      _loadingRemoteDirectories.add(directoryPath);
    });

    try {
      final entries = await provider.browseRemoteDirectory(directoryPath);
      if (!mounted) return;
      setState(() {
        _expandedRemoteDirectories[directoryPath] = entries;
        _loadingRemoteDirectories.remove(directoryPath);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRemoteDirectories.remove(directoryPath);
      });
      AdaptiveSnackBar.show(
        context,
        message: '加载文件夹失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  List<Widget> _buildRemoteDirectoryChildren(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String directoryPath,
    int depth,
  ) {
    final entries = _expandedRemoteDirectories[directoryPath] ?? const [];
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    if (entries.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(12.0 + depth * 16.0, 6, 0, 6),
          child: Text(
            '（空文件夹）',
            style: TextStyle(color: secondaryLabelColor, fontSize: 12),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final entry in entries) {
      final entryPath = entry.path;
      final entryName = entry.name.isNotEmpty ? entry.name : entryPath;
      final left = 12.0 + depth * 16.0;

      if (entry.isDirectory) {
        final expanded = _expandedRemoteDirectories.containsKey(entryPath);
        final loading = _loadingRemoteDirectories.contains(entryPath);
        widgets.add(
          GestureDetector(
            onTap: () => _toggleRemoteDirectory(provider, entryPath),
            child: Padding(
              padding: EdgeInsets.fromLTRB(left, 4, 8, 4),
              child: Row(
                children: [
                  Icon(CupertinoIcons.folder, size: 18, color: secondaryLabelColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CupertinoActivityIndicator(radius: 7),
                    )
                  else
                    Icon(
                      expanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_forward,
                      size: 16,
                      color: secondaryLabelColor,
                    ),
                ],
              ),
            ),
          ),
        );
        if (expanded) {
          widgets.addAll(_buildRemoteDirectoryChildren(context, provider, entryPath, depth + 1));
        }
        continue;
      }

      widgets.add(
        GestureDetector(
          onTap: () => _playRemoteFile(provider, entry),
          child: Padding(
            padding: EdgeInsets.fromLTRB(left, 4, 8, 4),
            child: Row(
              children: [
                Icon(CupertinoIcons.play_circle, size: 18, color: secondaryLabelColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: labelColor),
                      ),
                      if (_remoteEntrySubtitle(entry) != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _remoteEntrySubtitle(entry)!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: secondaryLabelColor),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Future<void> _playRemoteFile(
    SharedRemoteLibraryProvider provider,
    SharedRemoteFileEntry entry,
  ) async {
    try {
      final streamUrl = provider.buildRemoteFileStreamUri(entry.path).toString();
      final name = entry.name.isNotEmpty ? entry.name : entry.path;
      final title = p.basenameWithoutExtension(name);

      final history = WatchHistoryItem(
        filePath: streamUrl,
        animeName: (entry.animeName?.trim().isNotEmpty == true)
            ? entry.animeName!.trim()
            : (title.isNotEmpty ? title : p.basenameWithoutExtension(entry.path)),
        episodeTitle: entry.episodeTitle?.trim().isNotEmpty == true
            ? entry.episodeTitle!.trim()
            : null,
        animeId: entry.animeId,
        episodeId: entry.episodeId,
        watchProgress: 0.0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
      );

      final playable = PlayableItem(
        videoPath: history.filePath,
        title: history.animeName,
        subtitle: history.episodeTitle,
        animeId: history.animeId,
        episodeId: history.episodeId,
        historyItem: history,
      );

      await PlaybackService().play(playable);
      if (mounted) {
        await context.read<WatchHistoryProvider>().refresh();
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '播放失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String? _remoteEntrySubtitle(SharedRemoteFileEntry entry) {
    final hasIds = (entry.animeId ?? 0) > 0 && (entry.episodeId ?? 0) > 0;
    if (!hasIds) {
      return null;
    }

    final parts = <String>[];
    final animeName = entry.animeName?.trim();
    if (animeName != null && animeName.isNotEmpty) {
      parts.add(animeName);
    }
    final episodeTitle = entry.episodeTitle?.trim();
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      parts.add(episodeTitle);
    }

    if (parts.isEmpty) {
      return '已识别';
    }
    return parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final titleOpacity = (1.0 - (_scrollOffset / 12.0)).clamp(0.0, 1.0);

    return ChangeNotifierProvider<SharedRemoteLibraryProvider>.value(
      value: widget.provider,
      child: Consumer<SharedRemoteLibraryProvider>(
        builder: (context, provider, _) {
          final sections = <Widget>[
            _buildStatusCard(context, provider),
            const SizedBox(height: 16),
            _buildActionButtons(context, provider),
            const SizedBox(height: 16),
            if (provider.webdavConnections.isNotEmpty) ...[
              _buildWebDAVSection(context, provider),
              const SizedBox(height: 16),
            ],
            if (provider.smbConnections.isNotEmpty) ...[
              _buildSMBSection(context, provider),
              const SizedBox(height: 16),
            ],
            _buildFolderSection(context, provider),
            const SizedBox(height: 32),
          ];

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
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
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

    final status = provider.scanStatus;
    final isScanning = status?.isScanning == true;
    final message = status?.message ?? provider.managementErrorMessage ?? '';

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
                isScanning ? CupertinoIcons.arrow_2_circlepath : CupertinoIcons.folder,
                size: 20,
                color: labelColor,
              ),
              const SizedBox(width: 8),
              Text(
                isScanning ? '远程端正在扫描' : '共享库管理',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const Spacer(),
              if (provider.isManagementLoading)
                const CupertinoActivityIndicator(radius: 10),
            ],
          ),
          const SizedBox(height: 14),
          _buildStatusRow(
            context,
            label: '扫描文件夹',
            value: '${provider.scannedFolders.length}',
          ),
          if (status != null) ...[
            const SizedBox(height: 6),
            _buildStatusRow(
              context,
              label: '进度',
              value: '${(status.progress * 100).toStringAsFixed(0)}%',
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message,
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

  Widget _buildActionButtons(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final busy = provider.isManagementLoading || provider.scanStatus?.isScanning == true;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildActionButton(
          context,
          label: '添加文件夹',
          icon: CupertinoIcons.add_circled,
          primary: true,
          onPressed: busy ? null : () => _handleAddFolder(provider),
        ),
        _buildActionButton(
          context,
          label: '智能刷新',
          icon: CupertinoIcons.refresh,
          onPressed: busy ? null : () => _handleRescanAll(provider),
        ),
        _buildActionButton(
          context,
          label: '添加 WebDAV',
          icon: CupertinoIcons.cloud,
          onPressed: busy ? null : () => _handleAddWebDAV(provider),
        ),
        _buildActionButton(
          context,
          label: '添加 SMB',
          icon: CupertinoIcons.share,
          onPressed: busy ? null : () => _handleAddSMB(provider),
        ),
        _buildActionButton(
          context,
          label: '刷新状态',
          icon: CupertinoIcons.arrow_down_doc,
          onPressed: () => provider.refreshManagement(userInitiated: true),
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
    final color = primary
        ? CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context)
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final textColor = primary ? CupertinoColors.white : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return CupertinoButton(
      onPressed: onPressed,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      borderRadius: BorderRadius.circular(14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 14, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildFolderSection(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final folders = provider.scannedFolders;
    if (provider.isManagementLoading && folders.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (folders.isEmpty) {
      final subtitle = provider.managementErrorMessage?.isNotEmpty == true
          ? provider.managementErrorMessage!
          : '远程端尚未添加媒体文件夹。';
      return _buildEmptyPlaceholder(
        context,
        icon: CupertinoIcons.folder,
        title: '暂无文件夹',
        subtitle: subtitle,
      );
    }

    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '扫描文件夹列表',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 12),
        ...folders.map((folder) {
          final busy = provider.isManagementLoading || provider.scanStatus?.isScanning == true;
          final statusColor = folder.exists
              ? CupertinoDynamicColor.resolve(CupertinoColors.systemGreen, context)
              : CupertinoDynamicColor.resolve(CupertinoColors.systemOrange, context);
          final title = folder.name.isNotEmpty ? folder.name : folder.path;
          final folderPath = folder.path;
          final expanded = _expandedRemoteDirectories.containsKey(folderPath);
          final loading = _loadingRemoteDirectories.contains(folderPath);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _toggleRemoteDirectory(provider, folderPath),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.folder,
                            size: 18,
                            color: statusColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: labelColor,
                              ),
                            ),
                          ),
                          if (loading)
                            const CupertinoActivityIndicator(radius: 8)
                          else
                            Icon(
                              expanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_forward,
                              size: 16,
                              color: secondaryLabelColor,
                            ),
                          const SizedBox(width: 4),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 32,
                            onPressed: busy
                                ? null
                                : () => _handleScanFolder(provider, folderPath),
                            child: Icon(
                              CupertinoIcons.refresh,
                              size: 18,
                              color: busy ? secondaryLabelColor : labelColor,
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 32,
                            onPressed: busy
                                ? null
                                : () => _handleRemoveFolder(provider, folderPath),
                            child: Icon(
                              CupertinoIcons.delete,
                              size: 18,
                              color: busy
                                  ? secondaryLabelColor
                                  : CupertinoDynamicColor.resolve(
                                      CupertinoColors.systemRed,
                                      context,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        folderPath,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: secondaryLabelColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                ..._buildRemoteDirectoryChildren(context, provider, folderPath, 1),
              const SizedBox(height: 12),
            ],
          );
        }),
      ],
    );
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

  Widget _buildWebDAVSection(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WebDAV 连接',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
          ),
        ),
        const SizedBox(height: 12),
        ...provider.webdavConnections.map((connection) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemBackground, context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.cloud,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.activeBlue, context),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        connection.url,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 32,
                  onPressed: () => _handleRemoveWebDAV(provider, connection),
                  child: Icon(
                    CupertinoIcons.delete,
                    size: 18,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemRed, context),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSMBSection(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SMB 连接',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
          ),
        ),
        const SizedBox(height: 12),
        ...provider.smbConnections.map((connection) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemBackground, context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.share,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.systemIndigo, context),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${connection.host}:${connection.port}',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 32,
                  onPressed: () => _handleEditSMB(provider, connection),
                  child: Icon(
                    CupertinoIcons.pencil,
                    size: 18,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label, context),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 32,
                  onPressed: () => _handleRemoveSMB(provider, connection),
                  child: Icon(
                    CupertinoIcons.delete,
                    size: 18,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemRed, context),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _handleAddWebDAV(SharedRemoteLibraryProvider provider) async {
    await WebDAVConnectionDialog.show(
      context,
      onSave: (connection) async {
        await provider.addWebDAVConnection(connection);
        if (provider.managementErrorMessage != null) {
          throw provider.managementErrorMessage!;
        }
        return true;
      },
    );
  }

  Future<void> _handleRemoveWebDAV(
    SharedRemoteLibraryProvider provider,
    WebDAVConnection connection,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除 WebDAV 连接'),
        content: Text('确定要删除“${connection.name}”吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await provider.removeWebDAVConnection(connection.name);
      _checkError(provider, '已删除 WebDAV 连接');
    }
  }

  Future<void> _handleAddSMB(SharedRemoteLibraryProvider provider) async {
    await CupertinoSmbConnectionDialog.show(
      context,
      onSave: (connection) async {
        await provider.addSMBConnection(connection);
        if (provider.managementErrorMessage != null) {
          return false;
        }
        return true;
      },
    );
  }

  Future<void> _handleEditSMB(
    SharedRemoteLibraryProvider provider,
    SMBConnection connection,
  ) async {
    await CupertinoSmbConnectionDialog.show(
      context,
      editConnection: connection,
      onSave: (updated) async {
        await provider.addSMBConnection(updated);
        if (provider.managementErrorMessage != null) {
          return false;
        }
        return true;
      },
    );
  }

  Future<void> _handleRemoveSMB(
    SharedRemoteLibraryProvider provider,
    SMBConnection connection,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除 SMB 连接'),
        content: Text('确定要删除“${connection.name}”吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await provider.removeSMBConnection(connection.name);
      _checkError(provider, '已删除 SMB 连接');
    }
  }

  void _checkError(SharedRemoteLibraryProvider provider, String successMessage) {
    if (!mounted) return;
    if (provider.managementErrorMessage != null) {
      AdaptiveSnackBar.show(
        context,
        message: provider.managementErrorMessage!,
        type: AdaptiveSnackBarType.error,
      );
    } else {
      AdaptiveSnackBar.show(
        context,
        message: successMessage,
        type: AdaptiveSnackBarType.success,
      );
    }
  }

  Future<void> _handleAddFolder(SharedRemoteLibraryProvider provider) async {
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => IOS26AlertDialog(
        title: '添加媒体文件夹（远程）',
        input: const AdaptiveAlertDialogInput(
          placeholder: '例如：/Volumes/Media 或 D:\\Anime',
          initialValue: '',
          keyboardType: TextInputType.text,
        ),
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '添加并扫描',
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) {
      return;
    }

    await provider.addRemoteFolder(
      folderPath: result.trim(),
      scan: true,
      skipPreviouslyMatchedUnwatched: false,
    );

    final error = provider.managementErrorMessage;
    if (!mounted) return;
    if (error != null && error.isNotEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: error,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    AdaptiveSnackBar.show(
      context,
      message: '已请求远程端开始扫描',
      type: AdaptiveSnackBarType.success,
    );
    _maybeStartPolling(provider);
  }

  Future<void> _handleRescanAll(SharedRemoteLibraryProvider provider) async {
    await provider.rescanRemoteAll(skipPreviouslyMatchedUnwatched: true);
    final error = provider.managementErrorMessage;
    if (!mounted) return;
    if (error != null && error.isNotEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: error,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    AdaptiveSnackBar.show(
      context,
      message: '已请求远程端开始智能刷新',
      type: AdaptiveSnackBarType.success,
    );
    _maybeStartPolling(provider);
  }

  Future<void> _handleScanFolder(
    SharedRemoteLibraryProvider provider,
    String folderPath,
  ) async {
    await provider.addRemoteFolder(
      folderPath: folderPath,
      scan: true,
      skipPreviouslyMatchedUnwatched: false,
    );
    _maybeStartPolling(provider);
  }

  Future<void> _handleRemoveFolder(
    SharedRemoteLibraryProvider provider,
    String folderPath,
  ) async {
    await provider.removeRemoteFolder(folderPath);
    final error = provider.managementErrorMessage;
    if (!mounted) return;
    if (error != null && error.isNotEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: error,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    AdaptiveSnackBar.show(
      context,
      message: '已移除文件夹',
      type: AdaptiveSnackBarType.success,
    );
  }
}
