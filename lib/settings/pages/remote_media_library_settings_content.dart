import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/media_server_device_id_service.dart';
import 'package:nipaplay/services/remote_access_qr_service.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_server_detail_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_library_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_management_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_server_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart'
    show MediaServerType, NetworkMediaServerDialog;
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_view.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class RemoteMediaLibrarySettingsContent extends StatefulWidget {
  const RemoteMediaLibrarySettingsContent({super.key});

  @override
  State<RemoteMediaLibrarySettingsContent> createState() =>
      _RemoteMediaLibrarySettingsContentState();
}

class _RemoteMediaLibrarySettingsContentState
    extends State<RemoteMediaLibrarySettingsContent> {
  Future<_MediaServerDeviceIdInfo>? _deviceIdInfoFuture;

  @override
  void initState() {
    super.initState();
    _deviceIdInfoFuture = _loadDeviceIdInfo();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Consumer3<JellyfinProvider, EmbyProvider, DandanplayRemoteProvider>(
      builder: (
        context,
        jellyfinProvider,
        embyProvider,
        dandanProvider,
        child,
      ) {
        final isInitializing = !jellyfinProvider.isInitialized &&
            !embyProvider.isInitialized &&
            !dandanProvider.isInitialized;

        if (isInitializing) {
          return AdaptiveSettingsPage(
            title: l10n.networkMediaLibrary,
            children: [
              AdaptiveSettingsSection(
                children: [
                  AdaptiveSettingsTile<void>.card(
                    title: l10n.networkMediaLibrary,
                    subtitle: _text(
                      context,
                      '正在初始化远程媒体库服务...',
                      '正在初始化遠端媒體庫服務...',
                      'Initializing network media services...',
                    ),
                    icon: Ionicons.cloud_outline,
                    phoneIcon: cupertino.CupertinoIcons.cloud,
                    enabled: false,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          );
        }

        return AdaptiveSettingsPage(
          title: l10n.networkMediaLibrary,
          children: [
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile<void>.card(
                  title: l10n.networkMediaLibrary,
                  subtitle: l10n.networkMediaLibraryIntro,
                  icon: Ionicons.cloud_outline,
                  phoneIcon: cupertino.CupertinoIcons.cloud,
                  enabled: false,
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildNetworkServerSection(
              context,
              type: MediaServerType.jellyfin,
              title: l10n.jellyfinMediaServerTitle,
              isConnected: jellyfinProvider.isConnected,
              isLoading:
                  !jellyfinProvider.isInitialized || jellyfinProvider.isLoading,
              hasError: jellyfinProvider.hasError,
              errorMessage: jellyfinProvider.errorMessage,
              serverUrl: jellyfinProvider.serverUrl,
              username: jellyfinProvider.username,
              mediaItemCount: jellyfinProvider.mediaItems.length +
                  jellyfinProvider.movieItems.length,
              selectedLibraries: _resolveSelectedLibraryNames<JellyfinLibrary>(
                jellyfinProvider.availableLibraries,
                jellyfinProvider.selectedLibraryIds,
                (library) => library.id,
                (library) => library.name,
              ),
              disconnectedDescription: l10n.jellyfinDisconnectedDescription,
              icon: Ionicons.tv_outline,
            ),
            const SizedBox(height: 16),
            _buildNetworkServerSection(
              context,
              type: MediaServerType.emby,
              title: l10n.embyMediaServerTitle,
              isConnected: embyProvider.isConnected,
              isLoading: !embyProvider.isInitialized || embyProvider.isLoading,
              hasError: embyProvider.hasError,
              errorMessage: embyProvider.errorMessage,
              serverUrl: embyProvider.serverUrl,
              username: embyProvider.username,
              mediaItemCount: embyProvider.mediaItems.length +
                  embyProvider.movieItems.length,
              selectedLibraries: _resolveSelectedLibraryNames<EmbyLibrary>(
                embyProvider.availableLibraries,
                embyProvider.selectedLibraryIds,
                (library) => library.id,
                (library) => library.name,
              ),
              disconnectedDescription: l10n.embyDisconnectedDescription,
              icon: Ionicons.play_circle_outline,
            ),
            const SizedBox(height: 16),
            _buildDandanplaySection(context, dandanProvider),
            const SizedBox(height: 16),
            _buildSharedRemoteSection(context),
            const SizedBox(height: 16),
            _buildDeviceIdSection(context),
            const SizedBox(height: 16),
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile<void>.card(
                  title: _text(
                      context, '其他媒体服务', '其他媒體服務', 'Other Media Services'),
                  subtitle: _text(
                    context,
                    'DLNA/UPnP 等更多远程媒体服务支持正在开发中',
                    'DLNA/UPnP 等更多遠端媒體服務支援正在開發中',
                    'DLNA/UPnP and more remote media services are planned.',
                  ),
                  icon: Ionicons.wifi_outline,
                  phoneIcon: cupertino.CupertinoIcons.wifi,
                  enabled: false,
                  onTap: () {},
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildNetworkServerSection(
    BuildContext context, {
    required MediaServerType type,
    required String title,
    required bool isConnected,
    required bool isLoading,
    required bool hasError,
    required String? errorMessage,
    required String? serverUrl,
    required String? username,
    required int mediaItemCount,
    required List<String> selectedLibraries,
    required String disconnectedDescription,
    required IconData icon,
  }) {
    final l10n = context.l10n;
    final status = isLoading
        ? l10n.loading
        : (isConnected
            ? l10n.mediaServerStatusConnected
            : l10n.mediaServerStatusDisconnected);
    final summary = isConnected
        ? _connectedServerSummary(
            context,
            serverUrl: serverUrl,
            username: username,
            mediaItemCount: mediaItemCount,
            selectedLibraries: selectedLibraries,
          )
        : disconnectedDescription;

    return AdaptiveSettingsCanvas(
      child: _buildServerPanel(
        context,
        title: title,
        status: status,
        summary: summary,
        icon: icon,
        active: isConnected,
        loading: isLoading,
        hasError: hasError,
        errorMessage: errorMessage,
        selectedLibraries: selectedLibraries,
        actions: [
          _buildServerPanelButton(
            context,
            label: isConnected
                ? l10n.mediaServerManageServer
                : l10n.mediaServerConnectServer,
            icon: isConnected
                ? Ionicons.settings_outline
                : Ionicons.log_in_outline,
            primary: true,
            onPressed: isLoading ? null : () => _showNetworkServerDialog(type),
          ),
          if (isConnected)
            _buildServerPanelButton(
              context,
              label: l10n.mediaServerViewLibrary,
              icon: Ionicons.library_outline,
              onPressed: () => _showNetworkMediaLibrary(type),
            ),
          if (isConnected)
            _buildServerPanelButton(
              context,
              label: l10n.mediaServerRefresh,
              icon: Ionicons.refresh_outline,
              onPressed: () => _refreshNetworkMedia(type),
            ),
          if (isConnected)
            _buildServerPanelButton(
              context,
              label: l10n.disconnect,
              icon: Ionicons.log_out_outline,
              destructive: true,
              onPressed: () => _disconnectNetworkServer(type),
            ),
        ],
      ),
    );
  }

  Widget _buildDandanplaySection(
    BuildContext context,
    DandanplayRemoteProvider provider,
  ) {
    final l10n = context.l10n;
    final isLoading = !provider.isInitialized || provider.isLoading;
    final isConnected = provider.isConnected;
    final hasError = provider.errorMessage?.isNotEmpty == true && !isLoading;
    final status = isLoading
        ? l10n.loading
        : isConnected
            ? l10n.dandanRemoteStatusSynced
            : (provider.serverUrl?.isNotEmpty == true
                ? l10n.dandanRemoteStatusConnectFailed
                : l10n.dandanRemoteStatusNotConfigured);
    final summary = isConnected
        ? '${l10n.dandanRemoteServerAddressLabel}: ${provider.serverUrl ?? l10n.mediaServerUnknown}\n'
            '${l10n.dandanRemoteAnimeEntries}: ${provider.animeGroups.length} · '
            '${l10n.dandanRemoteVideoFiles}: ${provider.episodes.length}\n'
            '${l10n.dandanRemoteLastSyncedLabel}: ${_formatDandanTimestamp(context, provider.lastSyncedAt)}'
        : l10n.dandanRemoteDisconnectedHintLong;

    return AdaptiveSettingsCanvas(
      child: _buildServerPanel(
        context,
        title: l10n.dandanRemoteCardTitle,
        status: status,
        summary: summary,
        icon: Ionicons.chatbubbles_outline,
        active: isConnected,
        loading: isLoading,
        hasError: hasError,
        errorMessage: provider.errorMessage,
        actions: [
          _buildServerPanelButton(
            context,
            label: isConnected
                ? l10n.dandanRemoteManageConnection
                : l10n.dandanRemoteConnectAccessTitle,
            icon: isConnected
                ? Ionicons.settings_outline
                : Ionicons.log_in_outline,
            primary: true,
            onPressed: isLoading
                ? null
                : () => _showDandanplayConnectionDialog(provider),
          ),
          if (isConnected)
            _buildServerPanelButton(
              context,
              label: l10n.dandanRemoteRefreshLibrary,
              icon: Ionicons.refresh_outline,
              onPressed:
                  isLoading ? null : () => _refreshDandanLibrary(provider),
            ),
          if (isConnected)
            _buildServerPanelButton(
              context,
              label: l10n.disconnect,
              icon: Ionicons.log_out_outline,
              destructive: true,
              onPressed:
                  isLoading ? null : () => _disconnectDandanplay(provider),
            ),
        ],
      ),
    );
  }

  Widget _buildServerPanel(
    BuildContext context, {
    required String title,
    required String status,
    required String summary,
    required IconData icon,
    required bool active,
    required bool loading,
    required bool hasError,
    String? errorMessage,
    List<String> selectedLibraries = const <String>[],
    required List<Widget> actions,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _serverStatusColor(
      context,
      active: active,
      loading: loading,
      hasError: hasError,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active
                        ? _text(
                            context,
                            '服务器已经连接，可以浏览或刷新远程媒体库。',
                            '伺服器已連接，可以瀏覽或重新整理遠端媒體庫。',
                            'The server is connected. You can browse or refresh the remote library.',
                          )
                        : _text(
                            context,
                            '连接后会在本地显示远程媒体库内容。',
                            '連接後會在本地顯示遠端媒體庫內容。',
                            'After connecting, the remote media library appears locally.',
                          ),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildServerStatusChip(
              context,
              status,
              active: active,
              loading: loading,
              hasError: hasError,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (hasError && errorMessage?.isNotEmpty == true) ...[
          _buildServerMessageBox(
            context,
            '${_text(context, '错误', '錯誤', 'Error')}: $errorMessage',
            destructive: true,
          ),
          const SizedBox(height: 10),
        ],
        _buildServerMessageBox(context, summary),
        if (selectedLibraries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.mediaServerInfoSelectedLibraries,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final library in selectedLibraries)
                Chip(
                  label: Text(library),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actions,
        ),
      ],
    );
  }

  Widget _buildServerStatusChip(
    BuildContext context,
    String label, {
    required bool active,
    required bool loading,
    required bool hasError,
  }) {
    final color = _serverStatusColor(
      context,
      active: active,
      loading: loading,
      hasError: hasError,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _serverStatusColor(
    BuildContext context, {
    required bool active,
    required bool loading,
    required bool hasError,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    if (hasError) return colorScheme.error;
    if (loading) return colorScheme.tertiary;
    if (active) return colorScheme.primary;
    return colorScheme.onSurfaceVariant;
  }

  Widget _buildServerMessageBox(
    BuildContext context,
    String message, {
    bool destructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        destructive ? colorScheme.error : colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: destructive ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildServerPanelButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
    bool destructive = false,
  }) {
    return AdaptiveSettingsActionButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      primary: primary,
      destructive: destructive,
    );
  }

  Widget _buildSharedRemoteSection(BuildContext context) {
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        if (provider.isInitializing) {
          return AdaptiveSettingsSection(
            children: [
              AdaptiveSettingsTile<void>.card(
                title: _sharedRemoteTitle(context),
                subtitle: context.l10n.loading,
                icon: Ionicons.laptop_outline,
                phoneIcon: cupertino.CupertinoIcons.device_laptop,
                enabled: false,
                onTap: () {},
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile<void>.card(
                  title: _sharedRemoteTitle(context),
                  subtitle: _sharedRemoteSubtitle(context, provider),
                  icon: Ionicons.laptop_outline,
                  phoneIcon: cupertino.CupertinoIcons.device_laptop,
                  enabled: provider.hasActiveHost,
                  onTap: () => _openSharedRemoteLibrary(context),
                ),
                if (RemoteAccessQrCameraScanner.isSupported)
                  AdaptiveSettingsTile<void>.card(
                    title: _text(context, '扫码连接共享客户端', '掃碼連接共享客戶端',
                        'Scan to Connect Shared Client'),
                    subtitle: _text(
                      context,
                      '扫描另一台设备远程访问二维码',
                      '掃描另一台裝置遠端存取 QR Code',
                      'Scan another device remote access QR code.',
                    ),
                    icon: Ionicons.qr_code_outline,
                    phoneIcon: cupertino.CupertinoIcons.qrcode_viewfinder,
                    onTap: () => _connectSharedRemoteByQr(context, provider),
                  ),
                AdaptiveSettingsTile<void>.card(
                  title:
                      _text(context, '新增共享客户端', '新增共享客戶端', 'Add Shared Client'),
                  subtitle: _text(
                    context,
                    '填写另一台设备的局域网访问地址',
                    '填寫另一台裝置的區域網路存取地址',
                    'Enter another device LAN access URL.',
                  ),
                  icon: Ionicons.add_circle_outline,
                  phoneIcon: cupertino.CupertinoIcons.add_circled,
                  onTap: () => _showAddSharedHostDialog(context, provider),
                ),
              ],
            ),
            for (final host in provider.hosts) ...[
              const SizedBox(height: 12),
              AdaptiveSettingsSection(
                children: _buildSharedRemoteHostTiles(
                  context,
                  provider,
                  host,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildSharedRemoteHostTiles(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteHost host,
  ) {
    return [
      AdaptiveSettingsTile<void>.card(
        title: host.displayName.isNotEmpty ? host.displayName : host.baseUrl,
        subtitle: [
          host.baseUrl,
          provider.activeHostId == host.id
              ? _text(context, '当前使用', '目前使用', 'Active')
              : _text(context, '点击设为当前', '點擊設為目前使用', 'Tap to make active'),
          if (host.lastError?.isNotEmpty == true) host.lastError!,
        ].join('\n'),
        icon: host.isOnline
            ? Ionicons.checkmark_circle_outline
            : Ionicons.alert_circle_outline,
        phoneIcon: host.isOnline
            ? cupertino.CupertinoIcons.check_mark_circled
            : cupertino.CupertinoIcons.exclamationmark_circle,
        onTap: () => provider.setActiveHost(host.id),
      ),
      AdaptiveSettingsTile<void>.card(
        title: _text(context, '刷新共享媒体库', '重新整理共享媒體庫', 'Refresh Shared Library'),
        subtitle: host.baseUrl,
        icon: Ionicons.refresh_outline,
        phoneIcon: cupertino.CupertinoIcons.refresh,
        enabled: provider.activeHostId == host.id,
        onTap: () => provider.refreshLibrary(userInitiated: true),
      ),
      AdaptiveSettingsTile<void>.card(
        title: _text(context, '编辑共享客户端', '編輯共享客戶端', 'Edit Shared Client'),
        subtitle: _text(context, '重命名或修改访问地址', '重新命名或修改存取地址',
            'Rename or change the access URL.'),
        icon: Ionicons.create_outline,
        phoneIcon: cupertino.CupertinoIcons.pencil,
        onTap: () => _showEditSharedHostDialog(context, provider, host),
      ),
      AdaptiveSettingsTile<void>.card(
        title: _text(context, '删除共享客户端', '刪除共享客戶端', 'Delete Shared Client'),
        subtitle: host.baseUrl,
        icon: Ionicons.trash_outline,
        phoneIcon: cupertino.CupertinoIcons.trash,
        isDestructive: true,
        onTap: () => _confirmRemoveSharedHost(context, provider, host.id),
      ),
    ];
  }

  Widget _buildDeviceIdSection(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<_MediaServerDeviceIdInfo>(
      future: _deviceIdInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AdaptiveSettingsSection(
            children: [
              AdaptiveSettingsTile<void>.card(
                title: l10n.deviceIdTitle,
                subtitle: l10n.loading,
                icon: Ionicons.finger_print_outline,
                phoneIcon: cupertino.CupertinoIcons.device_phone_portrait,
                enabled: false,
                onTap: () {},
              ),
            ],
          );
        }

        final info = snapshot.data;
        if (info == null) {
          return AdaptiveSettingsSection(
            children: [
              AdaptiveSettingsTile<void>.card(
                title: l10n.deviceIdTitle,
                subtitle: snapshot.hasError
                    ? l10n.loadFailedWithError('${snapshot.error}')
                    : l10n.loadFailed,
                icon: Ionicons.alert_circle_outline,
                phoneIcon: cupertino.CupertinoIcons.exclamationmark_circle,
                onTap: _refreshDeviceIdInfo,
              ),
            ],
          );
        }

        final hasCustom = info.customDeviceId != null;
        return AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: l10n.deviceIdTitle,
              subtitle: l10n.deviceIdDescription,
              icon: Ionicons.finger_print_outline,
              phoneIcon: cupertino.CupertinoIcons.device_phone_portrait,
              onTap: () => _showCustomDeviceIdDialog(info),
            ),
            AdaptiveSettingsTile<void>.card(
              title: l10n.deviceIdCurrent,
              subtitle: info.effectiveDeviceId,
              icon: Ionicons.information_circle_outline,
              phoneIcon: cupertino.CupertinoIcons.info_circle,
              onTap: () => _showCustomDeviceIdDialog(info),
            ),
            AdaptiveSettingsTile<void>.card(
              title: hasCustom ? l10n.deviceIdCustom : l10n.deviceIdGenerated,
              subtitle: hasCustom
                  ? l10n.deviceIdCustomSet(info.customDeviceId!)
                  : info.generatedDeviceId,
              icon: Ionicons.create_outline,
              phoneIcon: cupertino.CupertinoIcons.pencil,
              onTap: () => _showCustomDeviceIdDialog(info),
            ),
            AdaptiveSettingsTile<void>.card(
              title: l10n.deviceIdRestoreAuto,
              subtitle: l10n.deviceIdRestoreAutoSubtitle,
              icon: Ionicons.refresh_outline,
              phoneIcon: cupertino.CupertinoIcons.refresh,
              enabled: hasCustom,
              onTap: () => _restoreGeneratedDeviceId(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showNetworkServerDialog(MediaServerType type) async {
    final isPhoneLayout = AdaptiveSettingsScope.isPhoneLayout(context);
    final l10n = context.l10n;
    final label = _serverLabel(type);

    if (isPhoneLayout) {
      final isConnected = type == MediaServerType.jellyfin
          ? context.read<JellyfinProvider>().isConnected
          : context.read<EmbyProvider>().isConnected;
      if (!isConnected) {
        final result =
            await CupertinoNetworkServerConnectionDialog.show(context, type);
        if (result == true && mounted) {
          AdaptiveSnackBar.show(
            context,
            message: l10n.networkServerConnected(label),
            type: AdaptiveSnackBarType.success,
          );
        }
        return;
      }

      await Navigator.of(context).push(
        cupertino.CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (context) => CupertinoNetworkMediaManagementSheet(
            serverType: type,
          ),
        ),
      );
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.networkServerSettingsUpdated(label),
        type: AdaptiveSnackBarType.success,
      );
      return;
    }

    final result = await NetworkMediaServerDialog.show(context, type);
    if (result == true && mounted) {
      AdaptiveSnackBar.show(
        context,
        message: l10n.networkServerSettingsUpdated(label),
        type: AdaptiveSnackBarType.success,
      );
    }
  }

  Future<void> _showNetworkMediaLibrary(MediaServerType type) async {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      await _showNetworkMediaLibraryBottomSheet(initialServer: type);
      return;
    }

    final viewType = type == MediaServerType.jellyfin
        ? NetworkMediaServerType.jellyfin
        : NetworkMediaServerType.emby;
    await _openNipaplayWindow(
      context,
      title: context.l10n.networkMediaLibrary,
      child: NetworkMediaLibraryView(serverType: viewType),
    );
  }

  Future<void> _showNetworkMediaLibraryBottomSheet({
    MediaServerType? initialServer,
  }) async {
    final l10n = context.l10n;
    final jellyfinProvider = context.read<JellyfinProvider>();
    final embyProvider = context.read<EmbyProvider>();

    if (!jellyfinProvider.isConnected && !embyProvider.isConnected) {
      AdaptiveSnackBar.show(
        context,
        message: l10n.connectJellyfinOrEmbyFirst,
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }

    await CupertinoBottomSheet.show(
      context: context,
      title: l10n.networkMediaLibrary,
      floatingTitle: true,
      child: CupertinoNetworkMediaLibrarySheet(
        jellyfinProvider: jellyfinProvider,
        embyProvider: embyProvider,
        initialServer: initialServer,
        onOpenDetail: (type, id) async {
          await Navigator.of(context).maybePop();
          if (!mounted) return;
          await _openMediaDetail(type, id);
        },
      ),
    );
  }

  Future<void> _openMediaDetail(MediaServerType type, String mediaId) async {
    if (type == MediaServerType.jellyfin) {
      await CupertinoMediaServerDetailPage.showJellyfin(context, mediaId);
    } else {
      await CupertinoMediaServerDetailPage.showEmby(context, mediaId);
    }
  }

  Future<void> _refreshNetworkMedia(MediaServerType type) async {
    final l10n = context.l10n;
    final label = _serverLabel(type);
    if (type == MediaServerType.jellyfin) {
      final provider = context.read<JellyfinProvider>();
      if (!provider.isConnected) {
        AdaptiveSnackBar.show(
          context,
          message: l10n.networkServerNotConnected(label),
          type: AdaptiveSnackBarType.warning,
        );
        return;
      }
      await provider.loadMediaItems();
      await provider.loadMovieItems();
    } else {
      final provider = context.read<EmbyProvider>();
      if (!provider.isConnected) {
        AdaptiveSnackBar.show(
          context,
          message: l10n.networkServerNotConnected(label),
          type: AdaptiveSnackBarType.warning,
        );
        return;
      }
      await provider.loadMediaItems();
      await provider.loadMovieItems();
    }

    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: l10n.networkLibraryRefreshed(label),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _disconnectNetworkServer(MediaServerType type) async {
    final l10n = context.l10n;
    final label = _serverLabel(type);
    final confirmed = AdaptiveSettingsScope.isPhoneLayout(context)
        ? await _confirmCupertino(
            title: l10n.disconnect,
            content: l10n.disconnectServerConfirm(label),
            destructiveText: l10n.disconnect,
          )
        : await _confirmMaterial(
            title: l10n.disconnect,
            content: l10n.disconnectServerConfirm(label),
            destructiveText: l10n.disconnect,
          );
    if (confirmed != true || !mounted) return;

    try {
      if (type == MediaServerType.jellyfin) {
        await context.read<JellyfinProvider>().disconnectFromServer();
      } else {
        await context.read<EmbyProvider>().disconnectFromServer();
      }
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.networkServerDisconnected(label),
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.disconnectServerFailed(label, '$e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showDandanplayConnectionDialog(
    DandanplayRemoteProvider provider,
  ) async {
    final l10n = context.l10n;
    final hasExisting = provider.serverUrl?.isNotEmpty == true;
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      final config = await showCupertinoDandanplayConnectionDialog(
        context: context,
        provider: provider,
      );
      if (config == null) return;

      try {
        await provider.connect(config.baseUrl, token: config.apiToken);
        if (!mounted) return;
        AdaptiveSnackBar.show(
          context,
          message: hasExisting
              ? l10n.dandanRemoteConfigUpdated
              : l10n.dandanRemoteConnected,
          type: AdaptiveSnackBarType.success,
        );
      } catch (e) {
        if (!mounted) return;
        AdaptiveSnackBar.show(
          context,
          message: l10n.connectFailedWithError('$e'),
          type: AdaptiveSnackBarType.error,
        );
      }
      return;
    }

    final connectLabel = _text(context, '连接', '連接', 'Connect');
    final result = await BlurLoginDialog.show(
      context,
      title: hasExisting
          ? l10n.dandanRemoteManageAccessTitle
          : l10n.dandanRemoteConnectAccessTitle,
      loginButtonText: hasExisting ? l10n.save : connectLabel,
      fields: [
        LoginField(
          key: 'baseUrl',
          label: l10n.dandanRemoteServerAddressLabel,
          hint: l10n.dandanRemoteAddressPlaceholder,
          initialValue: provider.serverUrl ?? '',
        ),
        LoginField(
          key: 'token',
          label: l10n.dandanRemoteApiTokenOptionalTitle,
          hint: l10n.dandanRemoteApiTokenPrompt(
            hasExisting ? l10n.save : connectLabel,
          ),
          isPassword: true,
          required: false,
        ),
      ],
      onLogin: (values) async {
        final baseUrl = values['baseUrl'] ?? '';
        final token = values['token'];
        if (baseUrl.isEmpty) {
          return LoginResult(success: false, message: l10n.enterServerAddress);
        }
        try {
          await provider.connect(baseUrl, token: token);
          return LoginResult(
              success: true, message: l10n.dandanRemoteConnected);
        } catch (e) {
          return LoginResult(success: false, message: e.toString());
        }
      },
    );

    if (result == true && mounted) {
      AdaptiveSnackBar.show(
        context,
        message: l10n.dandanRemoteConfigUpdated,
        type: AdaptiveSnackBarType.success,
      );
    }
  }

  Future<void> _refreshDandanLibrary(DandanplayRemoteProvider provider) async {
    final l10n = context.l10n;
    try {
      await provider.refresh();
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.remoteLibraryRefreshed,
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.refreshFailedWithError('$e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _disconnectDandanplay(
    DandanplayRemoteProvider provider,
  ) async {
    final l10n = context.l10n;
    final confirmed = AdaptiveSettingsScope.isPhoneLayout(context)
        ? await _confirmCupertino(
            title: l10n.disconnectDandanRemoteTitle,
            content: l10n.disconnectDandanRemoteContent,
            destructiveText: l10n.disconnect,
          )
        : await _confirmMaterial(
            title: l10n.disconnectDandanRemoteTitle,
            content: l10n.disconnectDandanRemoteContent,
            destructiveText: l10n.disconnect,
          );
    if (confirmed != true) return;

    try {
      await provider.disconnect();
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.dandanRemoteDisconnected,
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.disconnectFailedWithError('$e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _openSharedRemoteLibrary(BuildContext context) async {
    await _openNipaplayWindow(
      context,
      title: _sharedRemoteTitle(context),
      child: const SharedRemoteLibraryView(),
    );
  }

  Future<void> _connectSharedRemoteByQr(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    try {
      final payload = await RemoteAccessQrCameraScanner.scan(context);
      if (payload == null) return;

      final candidates = payload.allCandidateBaseUrls;
      RemoteAccessServerInfo? info;
      for (final candidate in candidates) {
        info = await RemoteAccessQrService.fetchServerInfo(candidate);
        if (info != null) break;
      }

      if (info == null) {
        if (!context.mounted) return;
        AdaptiveSnackBar.show(
          context,
          message: _text(
            context,
            '未识别到可访问的 NipaPlay 远程访问服务',
            '未識別到可存取的 NipaPlay 遠端存取服務',
            'No reachable NipaPlay remote access service found.',
          ),
          type: AdaptiveSnackBarType.error,
        );
        return;
      }

      final displayName = payload.displayName?.trim().isNotEmpty == true
          ? payload.displayName!.trim()
          : info.displayName;
      await provider.connectOrActivateHost(
        displayName: displayName,
        baseUrl: info.baseUrl,
      );

      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _text(
          context,
          '已连接共享媒体库与遥控器',
          '已連接共享媒體庫與遙控器',
          'Shared media library and remote control connected.',
        ),
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _text(
            context, '扫码连接失败：$e', '掃碼連接失敗：$e', 'QR connection failed: $e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showAddSharedHostDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    final result = await _showSharedHostEditDialog(context);
    if (result == null) return;
    try {
      await provider.addHost(
        displayName: result.displayName.trim().isEmpty
            ? result.baseUrl.trim()
            : result.displayName.trim(),
        baseUrl: result.baseUrl.trim(),
      );
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _text(context, '已添加共享客户端', '已新增共享客戶端', 'Shared client added.'),
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _text(context, '添加失败：$e', '新增失敗：$e', 'Add failed: $e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showEditSharedHostDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    dynamic host,
  ) async {
    final result = await _showSharedHostEditDialog(
      context,
      displayName: host.displayName,
      baseUrl: host.baseUrl,
    );
    if (result == null) return;
    await provider.renameHost(host.id, result.displayName.trim());
    await provider.updateHostUrl(host.id, result.baseUrl.trim());
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: _text(context, '共享客户端已更新', '共享客戶端已更新', 'Shared client updated.'),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<_SharedHostEditResult?> _showSharedHostEditDialog(
    BuildContext context, {
    String displayName = '',
    String baseUrl = '',
  }) async {
    final nameController = TextEditingController(text: displayName);
    final urlController = TextEditingController(text: baseUrl);
    try {
      if (AdaptiveSettingsScope.isPhoneLayout(context)) {
        return cupertino.showCupertinoDialog<_SharedHostEditResult>(
          context: context,
          builder: (dialogContext) => cupertino.CupertinoAlertDialog(
            title: Text(_text(context, '共享客户端', '共享客戶端', 'Shared Client')),
            content: Column(
              children: [
                const SizedBox(height: 12),
                cupertino.CupertinoTextField(
                  controller: nameController,
                  placeholder: _text(context, '备注名称', '備註名稱', 'Display name'),
                ),
                const SizedBox(height: 8),
                cupertino.CupertinoTextField(
                  controller: urlController,
                  placeholder: _text(
                    context,
                    '例如：192.168.1.100:1180',
                    '例如：192.168.1.100:1180',
                    'e.g. 192.168.1.100:1180',
                  ),
                ),
              ],
            ),
            actions: [
              cupertino.CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.cancel),
              ),
              cupertino.CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    _SharedHostEditResult(
                      displayName: nameController.text,
                      baseUrl: urlController.text,
                    ),
                  );
                },
                child: Text(context.l10n.save),
              ),
            ],
          ),
        );
      }

      return BlurDialog.show<_SharedHostEditResult>(
        context: context,
        title: _text(context, '共享客户端', '共享客戶端', 'Shared Client'),
        contentWidget: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: _text(context, '备注名称', '備註名稱', 'Display name'),
              ),
            ),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: _text(context, '访问地址', '存取地址', 'Access URL'),
                hintText: '192.168.1.100:1180',
              ),
            ),
          ],
        ),
        actions: [
          HoverScaleTextButton(
            text: context.l10n.cancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
          HoverScaleTextButton(
            text: context.l10n.save,
            onPressed: () {
              Navigator.of(context).pop(
                _SharedHostEditResult(
                  displayName: nameController.text,
                  baseUrl: urlController.text,
                ),
              );
            },
          ),
        ],
      );
    } finally {
      nameController.dispose();
      urlController.dispose();
    }
  }

  Future<void> _confirmRemoveSharedHost(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
  ) async {
    final confirmed = AdaptiveSettingsScope.isPhoneLayout(context)
        ? await _confirmCupertino(
            title: _text(context, '删除共享客户端', '刪除共享客戶端', 'Delete Shared Client'),
            content: _text(context, '确定要删除该客户端吗？', '確定要刪除此客戶端嗎？',
                'Delete this shared client?'),
            destructiveText: _text(context, '删除', '刪除', 'Delete'),
          )
        : await _confirmMaterial(
            title: _text(context, '删除共享客户端', '刪除共享客戶端', 'Delete Shared Client'),
            content: _text(context, '确定要删除该客户端吗？', '確定要刪除此客戶端嗎？',
                'Delete this shared client?'),
            destructiveText: _text(context, '删除', '刪除', 'Delete'),
          );
    if (confirmed != true) return;
    await provider.removeHost(hostId);
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: _text(context, '已删除共享客户端', '已刪除共享客戶端', 'Shared client deleted.'),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _showCustomDeviceIdDialog(_MediaServerDeviceIdInfo info) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: info.customDeviceId ?? '');
    final String? input;
    try {
      if (AdaptiveSettingsScope.isPhoneLayout(context)) {
        input = await cupertino.showCupertinoDialog<String>(
          context: context,
          builder: (dialogContext) => cupertino.CupertinoAlertDialog(
            title: Text(l10n.deviceIdDialogTitle),
            content: Column(
              children: [
                const SizedBox(height: 12),
                Text(l10n.deviceIdDialogHint),
                const SizedBox(height: 12),
                cupertino.CupertinoTextField(
                  controller: controller,
                  placeholder: l10n.deviceIdDialogPlaceholder,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Text(l10n.deviceIdDialogValidationHint),
              ],
            ),
            actions: [
              cupertino.CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
              cupertino.CupertinoDialogAction(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                isDefaultAction: true,
                child: Text(l10n.save),
              ),
            ],
          ),
        );
      } else {
        input = await BlurDialog.show<String>(
          context: context,
          title: l10n.deviceIdDialogTitle,
          contentWidget: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.deviceIdDialogHint),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 128,
                decoration: InputDecoration(
                  hintText: l10n.deviceIdDialogPlaceholder,
                ),
              ),
              Text(l10n.deviceIdDialogValidationHint),
            ],
          ),
          actions: [
            HoverScaleTextButton(
              text: l10n.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
            HoverScaleTextButton(
              text: l10n.save,
              onPressed: () => Navigator.of(context).pop(controller.text),
            ),
          ],
        );
      }
    } finally {
      controller.dispose();
    }

    if (input == null) return;

    try {
      await MediaServerDeviceIdService.instance.setCustomDeviceId(input);
      if (!mounted) return;
      _refreshDeviceIdInfo();
      AdaptiveSnackBar.show(
        context,
        message: l10n.deviceIdUpdatedHint,
        type: AdaptiveSnackBarType.success,
      );
    } on FormatException {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.deviceIdInvalid,
        type: AdaptiveSnackBarType.error,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.saveFailedWithError('$e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _restoreGeneratedDeviceId(BuildContext context) async {
    try {
      await MediaServerDeviceIdService.instance.setCustomDeviceId(null);
      if (!context.mounted) return;
      _refreshDeviceIdInfo();
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.deviceIdRestoreSuccess,
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.operationFailed('$e'),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<bool?> _confirmMaterial({
    required String title,
    required String content,
    required String destructiveText,
  }) {
    return BlurDialog.show<bool>(
      context: context,
      title: title,
      content: content,
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            destructiveText,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmCupertino({
    required String title,
    required String content,
    required String destructiveText,
  }) {
    return cupertino.showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => cupertino.CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          cupertino.CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          cupertino.CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(destructiveText),
          ),
        ],
      ),
    );
  }

  Future<void> _openNipaplayWindow(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      child: Builder(
        builder: (dialogContext) {
          final colorScheme = Theme.of(dialogContext).colorScheme;
          final screenSize = MediaQuery.of(dialogContext).size;
          final maxWidth = (screenSize.width * 0.95).clamp(360.0, 1280.0);
          return NipaplayWindowScaffold(
            maxWidth: maxWidth,
            maxHeightFactor: 0.88,
            onClose: () => Navigator.of(dialogContext).maybePop(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                ),
                Expanded(child: child),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<_MediaServerDeviceIdInfo> _loadDeviceIdInfo() async {
    String appName = 'NipaPlay';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.appName.isNotEmpty) {
        appName = packageInfo.appName;
      }
    } catch (_) {}

    final platform = _clientPlatformLabel();
    final customDeviceId =
        await MediaServerDeviceIdService.instance.getCustomDeviceId();
    final generatedDeviceId = await MediaServerDeviceIdService.instance
        .getOrCreateGeneratedDeviceId();
    final effectiveDeviceId =
        await MediaServerDeviceIdService.instance.getEffectiveDeviceId(
      appName: appName,
      platform: platform,
    );

    return _MediaServerDeviceIdInfo(
      appName: appName,
      platform: platform,
      effectiveDeviceId: effectiveDeviceId,
      generatedDeviceId: generatedDeviceId,
      customDeviceId: customDeviceId,
    );
  }

  void _refreshDeviceIdInfo() {
    setState(() {
      _deviceIdInfoFuture = _loadDeviceIdInfo();
    });
  }

  static String _clientPlatformLabel() {
    if (kIsWeb || kDebugMode) {
      return 'Flutter';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'Ios';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'Macos';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
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

    final nameMap = {
      for (final library in libraries)
        idSelector(library): nameSelector(library),
    };
    return [
      for (final id in selectedIds)
        if (nameMap[id]?.isNotEmpty == true) nameMap[id]!,
    ];
  }

  String _connectedServerSummary(
    BuildContext context, {
    required String? serverUrl,
    required String? username,
    required int mediaItemCount,
    required List<String> selectedLibraries,
  }) {
    final l10n = context.l10n;
    return [
      '${l10n.mediaServerInfoServerUrl}: ${serverUrl ?? l10n.mediaServerUnknown}',
      '${l10n.mediaServerInfoUsername}: ${username ?? l10n.mediaServerAnonymous}',
      '${l10n.mediaServerInfoItemCount}: $mediaItemCount',
      if (selectedLibraries.isNotEmpty)
        '${l10n.mediaServerInfoSelectedLibraries}: ${selectedLibraries.join(', ')}',
    ].join('\n');
  }

  String _sharedRemoteSubtitle(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final active = provider.activeHost;
    if (active == null) {
      return _text(
        context,
        '尚未添加任何共享客户端',
        '尚未新增任何共享客戶端',
        'No shared clients added yet.',
      );
    }
    return [
      active.displayName.isNotEmpty ? active.displayName : active.baseUrl,
      active.baseUrl,
      _text(
          context,
          '媒体条目: ${provider.animeSummaries.length}',
          '媒體條目: ${provider.animeSummaries.length}',
          'Media items: ${provider.animeSummaries.length}'),
      if (provider.errorMessage?.isNotEmpty == true) provider.errorMessage!,
    ].join('\n');
  }

  String _sharedRemoteTitle(BuildContext context) => _text(
        context,
        'NipaPlay 局域网媒体共享',
        'NipaPlay 區域網路媒體共享',
        'NipaPlay LAN Media Sharing',
      );

  String _serverLabel(MediaServerType type) {
    return type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
  }

  String _formatDandanTimestamp(BuildContext context, DateTime? timestamp) {
    if (timestamp == null) {
      return _text(context, '暂无记录', '暫無記錄', 'No records');
    }
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) {
      return _text(context, '刚刚', '剛剛', 'Just now');
    }
    if (diff.inHours < 1) {
      return _text(context, '${diff.inMinutes} 分钟前', '${diff.inMinutes} 分鐘前',
          '${diff.inMinutes} minutes ago');
    }
    if (diff.inDays < 1) {
      return _text(context, '${diff.inHours} 小时前', '${diff.inHours} 小時前',
          '${diff.inHours} hours ago');
    }
    if (diff.inDays < 7) {
      return _text(context, '${diff.inDays} 天前', '${diff.inDays} 天前',
          '${diff.inDays} days ago');
    }
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${timestamp.year}-${twoDigits(timestamp.month)}-${twoDigits(timestamp.day)} '
        '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}';
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') return english;
    if (locale == 'zh_Hant') return traditional;
    return simplified;
  }
}

class _MediaServerDeviceIdInfo {
  const _MediaServerDeviceIdInfo({
    required this.appName,
    required this.platform,
    required this.effectiveDeviceId,
    required this.generatedDeviceId,
    required this.customDeviceId,
  });

  final String appName;
  final String platform;
  final String effectiveDeviceId;
  final String generatedDeviceId;
  final String? customDeviceId;
}

class _SharedHostEditResult {
  const _SharedHostEditResult({
    required this.displayName,
    required this.baseUrl,
  });

  final String displayName;
  final String baseUrl;
}
