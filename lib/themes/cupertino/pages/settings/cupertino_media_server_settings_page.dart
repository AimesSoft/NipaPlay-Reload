import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_server_detail_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_remote_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_server_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_library_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_media_management_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_network_server_connection_dialog.dart';
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
    final label = type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
    final confirm = await showCupertinoDialog<bool>(
      context: context,
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

    try {
      if (type == MediaServerType.jellyfin) {
        await context.read<JellyfinProvider>().disconnectFromServer();
      } else {
        await context.read<EmbyProvider>().disconnectFromServer();
      }
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '$label 已断开连接',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
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

  Future<void> _showDandanplayConnectSheet(
    DandanplayRemoteProvider provider,
  ) async {
    final bool hasExisting = provider.serverUrl?.isNotEmpty == true;
    final TextEditingController urlController =
        TextEditingController(text: provider.serverUrl ?? '');
    final TextEditingController tokenController = TextEditingController();
    bool isSubmitting = false;
    String? errorText;

    try {
      final bool? result = await CupertinoBottomSheet.show<bool>(
        context: context,
        title: hasExisting ? '管理弹弹play远程访问' : '连接弹弹play远程访问',
        floatingTitle: true,
        child: StatefulBuilder(
          builder: (sheetContext, setState) {
            Future<void> handleSubmit() async {
              final String baseUrl = urlController.text.trim();
              final String token = tokenController.text.trim();
              if (baseUrl.isEmpty) {
                setState(() {
                  errorText = '请输入远程服务地址';
                });
                return;
              }

              FocusScope.of(sheetContext).unfocus();
              setState(() {
                isSubmitting = true;
                errorText = null;
              });

              try {
                await provider.connect(
                  baseUrl,
                  token: token.isEmpty ? null : token,
                );
                Navigator.of(sheetContext).pop(true);
              } catch (e) {
                setState(() {
                  errorText = e.toString();
                  isSubmitting = false;
                });
              }
            }

            final Color secondaryLabel = CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              sheetContext,
            );

            final String tokenPlaceholder =
                provider.tokenRequired ? '服务器已启用 API 验证' : '如启用 API 验证请填写';

            return CupertinoBottomSheetContentLayout(
              sliversBuilder: (context, topSpacing) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      topSpacing + 12,
                      20,
                      32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '请输入桌面端显示的远程服务地址以及可选的 API 密钥。',
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '远程服务地址',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label,
                              sheetContext,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: urlController,
                          keyboardType: TextInputType.url,
                          placeholder: '例如 http://192.168.1.2:23333',
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'API 密钥（可选）',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label,
                              sheetContext,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: tokenController,
                          placeholder: tokenPlaceholder,
                          obscureText: true,
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorText!,
                            style: TextStyle(
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemRed,
                                sheetContext,
                              ),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        CupertinoButton.filled(
                          onPressed: isSubmitting ? null : handleSubmit,
                          borderRadius: BorderRadius.circular(14),
                          child: isSubmitting
                              ? const CupertinoActivityIndicator()
                              : Text(hasExisting ? '保存' : '连接'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      if (result == true && mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '弹弹play 远程服务配置已更新',
          type: AdaptiveSnackBarType.success,
        );
      }
    } finally {
      urlController.dispose();
      tokenController.dispose();
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
                    onManage: () => _showDandanplayConnectSheet(
                      dandanProvider,
                    ),
                    onRefresh: dandanProvider.isConnected
                        ? () => _refreshDandanLibrary(dandanProvider)
                        : null,
                    onDisconnect: dandanProvider.isConnected
                        ? () => _disconnectDandanplay(dandanProvider)
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
