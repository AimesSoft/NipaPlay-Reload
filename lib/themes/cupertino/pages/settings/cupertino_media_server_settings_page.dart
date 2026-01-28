import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/services/media_server_device_id_service.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_server_detail_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_remote_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_server_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_library_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_management_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_server_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart'
    show MediaServerType;

class CupertinoMediaServerSettingsPage extends StatefulWidget {
  const CupertinoMediaServerSettingsPage({super.key});

  static const String routeName = 'cupertino-network-media-settings';

  @override
  State<CupertinoMediaServerSettingsPage> createState() =>
      _CupertinoMediaServerSettingsPageState();
}

class _CupertinoMediaServerSettingsPageState
    extends State<CupertinoMediaServerSettingsPage> {
  Future<_MediaServerDeviceIdInfo>? _deviceIdInfoFuture;

  @override
  void initState() {
    super.initState();
    _deviceIdInfoFuture = _loadDeviceIdInfo();
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
    final generatedDeviceId =
        await MediaServerDeviceIdService.instance.getOrCreateGeneratedDeviceId();
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

  Widget _buildDeviceIdSection(BuildContext context) {
    return FutureBuilder<_MediaServerDeviceIdInfo>(
      future: _deviceIdInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CupertinoSettingsGroupCard(
            margin: EdgeInsets.zero,
            children: [
              CupertinoSettingsTile(
                title: Text('设备标识 (DeviceId)'),
                subtitle: Text('正在加载...'),
                trailing: CupertinoActivityIndicator(radius: 10),
              ),
            ],
          );
        }

        final info = snapshot.data;
        if (info == null) {
          return CupertinoSettingsGroupCard(
            margin: EdgeInsets.zero,
            children: [
              CupertinoSettingsTile(
                title: const Text('设备标识 (DeviceId)'),
                subtitle: Text(
                  snapshot.hasError ? '加载失败：${snapshot.error}' : '加载失败',
                ),
                trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _refreshDeviceIdInfo,
                  child: const Text('重试'),
                ),
              ),
            ],
          );
        }

        final bool hasCustom = info.customDeviceId != null;
        final String customSubtitle = hasCustom
            ? '已设置：${info.customDeviceId}'
            : '未设置（使用自动生成）';

        return CupertinoSettingsGroupCard(
          margin: EdgeInsets.zero,
          addDividers: true,
          children: [
            CupertinoSettingsTile(
              title: const Text('设备标识 (DeviceId)'),
              subtitle: const Text('用于 Jellyfin / Emby 区分不同设备，避免互踢登出。'),
              showChevron: true,
              onTap: () => _showCustomDeviceIdDialog(info),
            ),
            CupertinoSettingsTile(
              title: const Text('当前 DeviceId'),
              subtitle: Text(info.effectiveDeviceId),
            ),
            CupertinoSettingsTile(
              title: const Text('自动生成标识'),
              subtitle: Text(info.generatedDeviceId),
            ),
            CupertinoSettingsTile(
              title: const Text('自定义 DeviceId'),
              subtitle: Text(customSubtitle),
              showChevron: true,
              onTap: () => _showCustomDeviceIdDialog(info),
            ),
            CupertinoSettingsTile(
              title: const Text('恢复自动生成'),
              subtitle: const Text('清除自定义 DeviceId'),
              onTap: hasCustom
                  ? () async {
                      try {
                        await MediaServerDeviceIdService.instance
                            .setCustomDeviceId(null);
                        if (!context.mounted) return;
                        _refreshDeviceIdInfo();
                        AdaptiveSnackBar.show(
                          context,
                          message: '已恢复自动生成的设备ID',
                          type: AdaptiveSnackBarType.success,
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: '操作失败：$e',
                          type: AdaptiveSnackBarType.error,
                        );
                      }
                    }
                  : null,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCustomDeviceIdDialog(_MediaServerDeviceIdInfo info) async {
    final controller = TextEditingController(text: info.customDeviceId ?? '');

    final String? input = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义 DeviceId'),
        content: Column(
          children: [
            const SizedBox(height: 12),
            const Text('留空表示使用自动生成的设备标识。'),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: '例如: My-iPhone-01',
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            const Text('不要包含双引号/换行，长度不超过128。'),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            isDefaultAction: true,
            child: const Text('保存'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (input == null) return;

    try {
      await MediaServerDeviceIdService.instance.setCustomDeviceId(input);
      if (!mounted) return;
      _refreshDeviceIdInfo();
      AdaptiveSnackBar.show(
        context,
        message: '设备ID已更新，建议断开并重新连接服务器',
        type: AdaptiveSnackBarType.success,
      );
    } on FormatException {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: 'DeviceId 无效：请避免双引号/换行，且长度 ≤ 128',
        type: AdaptiveSnackBarType.error,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '保存失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showNetworkServerDialog(MediaServerType type) async {
    // 检查是否已连接
    bool isConnected;
    if (type == MediaServerType.jellyfin) {
      isConnected = context.read<JellyfinProvider>().isConnected;
    } else {
      isConnected = context.read<EmbyProvider>().isConnected;
    }

    if (!isConnected) {
      // 未连接，显示连接弹窗
      final result =
          await CupertinoNetworkServerConnectionDialog.show(context, type);
      if (result == true && mounted) {
        final label = type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
        AdaptiveSnackBar.show(
          context,
          message: '$label 服务器已连接',
          type: AdaptiveSnackBarType.success,
        );
      }
    } else {
      // 已连接，显示管理界面
      await Navigator.of(context).push(
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (context) => CupertinoNetworkMediaManagementSheet(
            serverType: type,
          ),
        ),
      );
      if (!mounted) return;

      final label = type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
      AdaptiveSnackBar.show(
        context,
        message: '$label 服务器设置已更新',
        type: AdaptiveSnackBarType.success,
      );
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

  Future<void> _disconnectNetworkServer(MediaServerType type) async {
    final buildContext = context;
    final label = type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
    final jellyfinProvider = buildContext.read<JellyfinProvider>();
    final embyProvider = buildContext.read<EmbyProvider>();

    final confirm = await showCupertinoDialog<bool>(
      context: buildContext,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('断开连接'),
        content: Text('确定要断开与 $label 服务器的连接吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('断开连接'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!buildContext.mounted) return;

    try {
      if (type == MediaServerType.jellyfin) {
        await jellyfinProvider.disconnectFromServer();
      } else {
        await embyProvider.disconnectFromServer();
      }
      if (!buildContext.mounted) return;
      AdaptiveSnackBar.show(
        buildContext,
        message: '$label 已断开连接',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!buildContext.mounted) return;
      AdaptiveSnackBar.show(
        buildContext,
        message: '断开 $label 失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _refreshNetworkMedia(MediaServerType type) async {
    final label = type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
    if (type == MediaServerType.jellyfin) {
      final provider = context.read<JellyfinProvider>();
      if (!provider.isConnected) {
        AdaptiveSnackBar.show(
          context,
          message: '尚未连接到 $label 服务器',
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
          message: '尚未连接到 $label 服务器',
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
      message: '$label 媒体库已刷新',
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _showNetworkMediaLibraryBottomSheet({
    MediaServerType? initialServer,
  }) async {
    final jellyfinProvider = context.read<JellyfinProvider>();
    final embyProvider = context.read<EmbyProvider>();

    if (!jellyfinProvider.isConnected && !embyProvider.isConnected) {
      AdaptiveSnackBar.show(
        context,
        message: '请先连接 Jellyfin 或 Emby 服务器',
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }

    await CupertinoBottomSheet.show(
      context: context,
      title: '网络媒体库',
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

  Future<void> _showDandanplayConnectionDialog(
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

  Future<void> _refreshDandanLibrary(
    DandanplayRemoteProvider provider,
  ) async {
    try {
      await provider.refresh();
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '远程媒体库已刷新',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '刷新失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _disconnectDandanplay(
    DandanplayRemoteProvider provider,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('断开弹弹play远程服务'),
        content: const Text(
          '确定要断开与弹弹play远程服务的连接吗？\n\n这将清除保存的服务器地址与 API 密钥。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('断开连接'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await provider.disconnect();
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '已断开与弹弹play远程服务的连接',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '断开失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '网络媒体库',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Consumer3<JellyfinProvider, EmbyProvider,
              DandanplayRemoteProvider>(
            builder: (
              context,
              jellyfinProvider,
              embyProvider,
              dandanProvider,
              _,
            ) {
              final TextStyle descriptionStyle =
                  CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 14,
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel,
                          context,
                        ),
                        height: 1.4,
                      );
              final bool isDandanLoading =
                  !dandanProvider.isInitialized || dandanProvider.isLoading;
              final List<DandanplayRemoteAnimeGroup> dandanPreview =
                  dandanProvider.animeGroups.take(3).toList();

              return ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                children: [
                  Text(
                    '在此管理 Jellyfin / Emby 服务器连接，并设置弹弹play 远程媒体库。',
                    style: descriptionStyle,
                  ),
                  const SizedBox(height: 16),
                  CupertinoMediaServerCard(
                    title: 'Jellyfin 媒体服务器',
                    icon: CupertinoIcons.tv,
                    accentColor: CupertinoColors.systemBlue,
                    isConnected: jellyfinProvider.isConnected,
                    isLoading: !jellyfinProvider.isInitialized ||
                        jellyfinProvider.isLoading,
                    hasError: jellyfinProvider.hasError,
                    errorMessage: jellyfinProvider.errorMessage,
                    serverUrl: jellyfinProvider.serverUrl,
                    username: jellyfinProvider.username,
                    mediaItemCount: jellyfinProvider.mediaItems.length +
                        jellyfinProvider.movieItems.length,
                    selectedLibraries:
                        _resolveSelectedLibraryNames<JellyfinLibrary>(
                      jellyfinProvider.availableLibraries,
                      jellyfinProvider.selectedLibraryIds,
                      (library) => library.id,
                      (library) => library.name,
                    ),
                    onManage: () =>
                        _showNetworkServerDialog(MediaServerType.jellyfin),
                    onViewLibrary: jellyfinProvider.isConnected
                        ? () => _showNetworkMediaLibraryBottomSheet(
                              initialServer: MediaServerType.jellyfin,
                            )
                        : null,
                    onDisconnect: jellyfinProvider.isConnected
                        ? () => _disconnectNetworkServer(
                              MediaServerType.jellyfin,
                            )
                        : null,
                    onRefresh: jellyfinProvider.isConnected
                        ? () => _refreshNetworkMedia(
                              MediaServerType.jellyfin,
                            )
                        : null,
                    disconnectedDescription: '连接 Jellyfin 服务器以同步远程媒体库与播放记录。',
                    serverBrand: ServerBrand.jellyfin,
                  ),
                  const SizedBox(height: 16),
                  CupertinoMediaServerCard(
                    title: 'Emby 媒体服务器',
                    icon: CupertinoIcons.play_rectangle,
                    accentColor: const Color(0xFF52B54B),
                    isConnected: embyProvider.isConnected,
                    isLoading:
                        !embyProvider.isInitialized || embyProvider.isLoading,
                    hasError: embyProvider.hasError,
                    errorMessage: embyProvider.errorMessage,
                    serverUrl: embyProvider.serverUrl,
                    username: embyProvider.username,
                    mediaItemCount: embyProvider.mediaItems.length +
                        embyProvider.movieItems.length,
                    selectedLibraries:
                        _resolveSelectedLibraryNames<EmbyLibrary>(
                      embyProvider.availableLibraries,
                      embyProvider.selectedLibraryIds,
                      (library) => library.id,
                      (library) => library.name,
                    ),
                    onManage: () =>
                        _showNetworkServerDialog(MediaServerType.emby),
                    onViewLibrary: embyProvider.isConnected
                        ? () => _showNetworkMediaLibraryBottomSheet(
                              initialServer: MediaServerType.emby,
                            )
                        : null,
                    onDisconnect: embyProvider.isConnected
                        ? () => _disconnectNetworkServer(MediaServerType.emby)
                        : null,
                    onRefresh: embyProvider.isConnected
                        ? () => _refreshNetworkMedia(MediaServerType.emby)
                        : null,
                    disconnectedDescription: '连接 Emby 服务器后可浏览个人媒体库并远程播放。',
                    serverBrand: ServerBrand.emby,
                  ),
                  const SizedBox(height: 16),
                  CupertinoDandanplayRemoteCard(
                    isConnected: dandanProvider.isConnected,
                    isLoading: isDandanLoading,
                    errorMessage: dandanProvider.errorMessage,
                    serverUrl: dandanProvider.serverUrl,
                    lastSyncedAt: dandanProvider.lastSyncedAt,
                    animeGroupCount: dandanProvider.animeGroups.length,
                    episodeCount: dandanProvider.episodes.length,
                    previewGroups: dandanPreview,
                    onManage: () => _showDandanplayConnectionDialog(
                      dandanProvider,
                    ),
                    onRefresh: dandanProvider.isConnected
                        ? () => _refreshDandanLibrary(dandanProvider)
                        : null,
                    onDisconnect: dandanProvider.isConnected
                        ? () => _disconnectDandanplay(dandanProvider)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildDeviceIdSection(context),
                ],
              );
            },
          ),
        ),
      ),
    );
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
