import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/settings/unified_settings_entries.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dandanplay_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_smb_connection_dialog.dart'
    as cupertino_smb;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_webdav_connection_dialog.dart'
    as cupertino_webdav;
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/smb_connection_dialog.dart'
    as desktop_smb;
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart'
    as desktop_webdav;
import 'package:nipaplay/utils/tab_change_notifier.dart';

class AdaptiveMediaLibraryPage extends StatefulWidget {
  const AdaptiveMediaLibraryPage({super.key});

  @override
  State<AdaptiveMediaLibraryPage> createState() =>
      _AdaptiveMediaLibraryPageState();
}

class _AdaptiveMediaLibraryPageState extends State<AdaptiveMediaLibraryPage> {
  String _selectedSectionId = MediaLibrarySectionIds.local;
  LibraryManagementViewMode _managementViewMode =
      LibraryManagementViewMode.icons;
  TabChangeNotifier? _tabChangeNotifier;
  bool _connectionsInitialized = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      unawaited(_initializeConnections());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<TabChangeNotifier>();
    if (notifier == _tabChangeNotifier) return;
    _tabChangeNotifier?.removeListener(_handleRequestedSection);
    _tabChangeNotifier = notifier..addListener(_handleRequestedSection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleRequestedSection();
    });
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_handleRequestedSection);
    super.dispose();
  }

  Future<void> _initializeConnections() async {
    await Future.wait([
      WebDAVService.instance.initialize(),
      SMBService.instance.initialize(),
    ]);
    if (!mounted) return;
    setState(() => _connectionsInitialized = true);
  }

  void _handleRequestedSection() {
    final requested = _tabChangeNotifier?.targetMediaLibrarySectionId;
    if (requested == null) return;
    _tabChangeNotifier?.clearSubTabIndex();
    if (requested != _selectedSectionId && mounted) {
      setState(() => _selectedSectionId = requested);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer5<
        JellyfinProvider,
        EmbyProvider,
        SharedRemoteLibraryProvider,
        DandanplayRemoteProvider,
        WatchHistoryProvider>(
      builder: (
        context,
        jellyfinProvider,
        embyProvider,
        sharedProvider,
        dandanProvider,
        watchHistoryProvider,
        _,
      ) {
        if (!watchHistoryProvider.isLoaded && !watchHistoryProvider.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !watchHistoryProvider.isLoaded) {
              watchHistoryProvider.loadHistory();
            }
          });
        }

        final sections = buildUnifiedMediaLibrarySections(
          MediaLibraryAvailability(
            showLocal: !kIsWeb,
            showWebDAVLibrary: watchHistoryProvider.isLoaded &&
                mediaLibraryHasItemsForSource(
                  watchHistoryProvider.history,
                  UnifiedMediaLibrarySource.webdav,
                ),
            showWebDAVManagement: kIsWeb
                ? sharedProvider.webdavConnections.isNotEmpty
                : _connectionsInitialized &&
                    WebDAVService.instance.connections.isNotEmpty,
            showSMBLibrary: watchHistoryProvider.isLoaded &&
                mediaLibraryHasItemsForSource(
                  watchHistoryProvider.history,
                  UnifiedMediaLibrarySource.smb,
                ),
            showSMBManagement: kIsWeb
                ? sharedProvider.smbConnections.isNotEmpty
                : _connectionsInitialized &&
                    SMBService.instance.connections.isNotEmpty,
            showShared: sharedProvider.hasReachableActiveHost || kIsWeb,
            showDandanplay: dandanProvider.isConnected,
            showJellyfin: jellyfinProvider.isConnected,
            showEmby: embyProvider.isConnected,
          ),
        );

        if (sections.isEmpty) {
          return const SizedBox.shrink();
        }

        final selectedIndex = mediaLibrarySectionIndexById(
          sections,
          _selectedSectionId,
        );
        final selectedSection = sections[selectedIndex < 0 ? 0 : selectedIndex];
        if (selectedSection.id != _selectedSectionId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedSectionId = selectedSection.id);
            }
          });
        }

        return AdaptiveMediaLibraryScaffold(
          sections: sections,
          selectedSection: selectedSection,
          onSectionSelected: (id) {
            if (id != _selectedSectionId) {
              setState(() => _selectedSectionId = id);
            }
          },
          onRemoteAccess: _openRemoteAccessSettings,
          onAddMedia: _showAddMedia,
          child: AdaptiveMediaLibrarySectionContent(
            section: selectedSection,
            onPlayEpisode: _playHistoryItem,
            onSourcesUpdated: _refreshSources,
            managementViewMode: _managementViewMode,
            onManagementViewModeChanged: (viewMode) {
              if (viewMode != _managementViewMode) {
                setState(() => _managementViewMode = viewMode);
              }
            },
          ),
        );
      },
    );
  }

  void _refreshSources() {
    if (!mounted) return;
    setState(() {
      _connectionsInitialized = kIsWeb || _connectionsInitialized;
    });
  }

  Future<void> _openRemoteAccessSettings() async {
    await UnifiedAppViewPresenter.show<void>(
      context,
      viewId: AppPageIds.settings,
      initialSubpageId: UnifiedSettingEntryIds.remoteAccess,
    );
  }

  Future<void> _showAddMedia() async {
    final selection = await showAdaptiveMediaSourcePicker(context);
    if (!mounted || selection == null) return;

    switch (selection) {
      case 'local_folder':
        await _addLocalFolder();
        break;
      case 'webdav':
        await _addWebDAV();
        break;
      case 'smb':
        await _addSMB();
        break;
      case 'jellyfin':
        await _configureNetworkServer(MediaServerType.jellyfin);
        break;
      case 'emby':
        await _configureNetworkServer(MediaServerType.emby);
        break;
      case 'dandanplay':
        await _configureDandanplay();
        break;
      case 'nipaplay':
        await _addSharedHost();
        break;
    }
  }

  Future<void> _addLocalFolder() async {
    if (kIsWeb) return;
    final scanService = context.read<ScanService>();
    if (scanService.isScanning) {
      _showMessage('已有扫描任务在进行中，请稍后');
      return;
    }
    final directory = await FilePickerService().pickDirectory();
    if (directory == null || directory.trim().isEmpty) return;
    await scanService.startDirectoryScan(
      directory,
      skipPreviouslyMatchedUnwatched: false,
    );
    if (mounted) _showMessage('已开始扫描：${path.basename(directory)}');
  }

  Future<void> _addWebDAV() async {
    final isPhone =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final result = isPhone
        ? await cupertino_webdav.CupertinoWebDAVConnectionDialog.show(context)
        : await desktop_webdav.WebDAVConnectionDialog.show(context);
    if (result == true && mounted) {
      setState(() => _connectionsInitialized = true);
    }
  }

  Future<void> _addSMB() async {
    final isPhone =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final result = isPhone
        ? await cupertino_smb.CupertinoSmbConnectionDialog.show(context)
        : await desktop_smb.SMBConnectionDialog.show(context);
    if (result == true && mounted) {
      setState(() => _connectionsInitialized = true);
    }
  }

  Future<void> _configureNetworkServer(MediaServerType type) async {
    await NetworkMediaServerDialog.show(context, type);
  }

  Future<void> _configureDandanplay() async {
    final surface = AppDisplaySurfaceScope.of(context);
    final provider = context.read<DandanplayRemoteProvider>();
    if (!provider.isInitialized) await provider.initialize();
    if (!mounted) return;

    if (surface == AppDisplaySurface.phone) {
      final config = await showCupertinoDandanplayConnectionDialog(
        context: context,
        provider: provider,
      );
      if (config == null) return;
      await provider.connect(config.baseUrl, token: config.apiToken);
      return;
    }

    final result = await BlurLoginDialog.show(
      context,
      title: provider.isConnected ? '更新弹弹play远程连接' : '连接弹弹play远程服务',
      loginButtonText: provider.isConnected ? '保存' : '连接',
      fields: [
        LoginField(
          key: 'baseUrl',
          label: '远程服务地址',
          hint: '例如 http://192.168.1.2:23333',
          initialValue: provider.serverUrl ?? '',
        ),
        const LoginField(
          key: 'token',
          label: 'API密钥 (可选)',
          isPassword: true,
          required: false,
        ),
      ],
      onLogin: (values) async {
        try {
          await provider.connect(
            values['baseUrl'] ?? '',
            token: values['token'],
          );
          return const LoginResult(success: true, message: '连接成功');
        } catch (error) {
          return LoginResult(success: false, message: '$error');
        }
      },
    );
    if (result == true && mounted) setState(() {});
  }

  Future<void> _addSharedHost() async {
    await SharedRemoteHostSelectionSheet.show(context);
  }

  Future<void> _playHistoryItem(WatchHistoryItem item) async {
    var filePath = item.filePath;
    PlaybackSession? playbackSession;

    try {
      if (filePath.startsWith('jellyfin://')) {
        playbackSession = await JellyfinService.instance.createPlaybackSession(
          itemId: filePath.replaceFirst('jellyfin://', ''),
          startPositionMs: item.lastPosition > 0 ? item.lastPosition : null,
        );
      } else if (filePath.startsWith('emby://')) {
        final id = filePath.replaceFirst('emby://', '').split('/').last;
        playbackSession = await EmbyService.instance.createPlaybackSession(
          itemId: id,
          startPositionMs: item.lastPosition > 0 ? item.lastPosition : null,
        );
      } else if (!kIsWeb &&
          !filePath.startsWith('http://') &&
          !filePath.startsWith('https://') &&
          !filePath.startsWith('webdav://') &&
          !filePath.startsWith('smb://')) {
        var file = File(filePath);
        if (!file.existsSync() && Platform.isIOS) {
          final alternate = filePath.startsWith('/private')
              ? filePath.replaceFirst('/private', '')
              : '/private$filePath';
          file = File(alternate);
          if (file.existsSync()) filePath = alternate;
        }
        if (!file.existsSync()) throw '文件不存在或无法访问';
      }

      await PlaybackService().play(
        PlayableItem(
          videoPath: filePath,
          title: item.animeName,
          subtitle: item.episodeTitle,
          animeId: item.animeId,
          episodeId: item.episodeId,
          historyItem: item,
          playbackSession: playbackSession,
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('播放失败：$error', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      AdaptiveSnackBar.show(
        context,
        message: message,
        type: error ? AdaptiveSnackBarType.error : AdaptiveSnackBarType.info,
      );
    } else {
      BlurSnackBar.show(context, message);
    }
  }
}
