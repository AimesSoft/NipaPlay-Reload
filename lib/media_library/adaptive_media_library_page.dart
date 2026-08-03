import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/media_library/adaptive_add_media_flow.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/media_library/media_library_section_order_store.dart';
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
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/settings/unified_settings_entries.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_page_actions_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';

class AdaptiveMediaLibraryPage extends StatefulWidget {
  const AdaptiveMediaLibraryPage({
    super.key,
    this.sectionOrderStore,
  });

  final MediaLibrarySectionOrderStore? sectionOrderStore;

  @override
  State<AdaptiveMediaLibraryPage> createState() =>
      _AdaptiveMediaLibraryPageState();
}

class _AdaptiveMediaLibraryPageState extends State<AdaptiveMediaLibraryPage> {
  String _selectedSectionId = MediaLibrarySectionIds.local;
  LibraryManagementViewMode _managementViewMode =
      LibraryManagementViewMode.icons;
  TabChangeNotifier? _tabChangeNotifier;
  CupertinoPageActionsController? _pageActionsController;
  bool _connectionsInitialized = false;
  int _selectionRevision = 0;
  late final MediaLibrarySectionOrderStore _sectionOrderStore;

  @override
  void initState() {
    super.initState();
    _sectionOrderStore =
        widget.sectionOrderStore ?? MediaLibrarySectionOrderStore();
    unawaited(_restoreSelectedSection());
    unawaited(_restoreSectionOrder());
    if (!kIsWeb) {
      unawaited(_initializeConnections());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pageActionsController = CupertinoPageActionsScope.maybeOf(context);
    if (pageActionsController != _pageActionsController) {
      _pageActionsController?.clear(this);
      _pageActionsController = pageActionsController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pageActionsController != pageActionsController) {
          return;
        }
        pageActionsController?.setActions(
          this,
          [
            CupertinoPageAction(
              id: 'media-library-more',
              label: '媒体库操作',
              icon: CupertinoIcons.ellipsis,
              onPressed: _showPhonePageActions,
            ),
          ],
        );
      });
    }
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
    _pageActionsController?.clear(this);
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

  Future<void> _restoreSelectedSection() async {
    final revisionAtStart = _selectionRevision;
    final saved = await SettingsStorage.loadString(
      SettingsKeys.mediaLibrarySelectedSection,
    );
    if (!mounted || saved.trim().isEmpty) return;
    if (_selectionRevision != revisionAtStart) return;
    setState(() => _selectedSectionId = saved.trim());
  }

  void _selectSection(String sectionId) {
    final normalized = sectionId.trim();
    if (normalized.isEmpty) return;
    _selectionRevision++;
    if (normalized != _selectedSectionId) {
      setState(() => _selectedSectionId = normalized);
    }
    unawaited(_persistSelectedSection(normalized));
  }

  Future<void> _persistSelectedSection(String sectionId) async {
    try {
      await SettingsStorage.saveString(
        SettingsKeys.mediaLibrarySelectedSection,
        sectionId,
      );
    } catch (error) {
      debugPrint('保存媒体库分区失败: $error');
    }
  }

  Future<void> _restoreSectionOrder() async {
    try {
      final restored = await _sectionOrderStore.restore();
      if (mounted && restored) setState(() {});
    } catch (error) {
      debugPrint('恢复媒体库排序失败: $error');
    }
  }

  void _setSectionOrder(List<String> sectionIds) {
    unawaited(_persistSectionOrder(sectionIds));
  }

  Future<void> _persistSectionOrder(List<String> sectionIds) async {
    try {
      await _sectionOrderStore.updateVisible(sectionIds);
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('保存媒体库排序失败: $error');
    }
  }

  void _selectMountedMediaLibrarySection(String sectionId) {
    if (!mounted ||
        AppDisplaySurfaceScope.of(context) != AppDisplaySurface.phone) {
      return;
    }
    _selectSection(sectionId);
  }

  void _handleRequestedSection() {
    final requested = _tabChangeNotifier?.targetMediaLibrarySectionId;
    if (requested == null) return;
    _tabChangeNotifier?.clearSubTabIndex();
    if (requested != _selectedSectionId && mounted) {
      _selectSection(requested);
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

        final sections = applyMediaLibrarySectionOrder(
          buildUnifiedMediaLibrarySections(
            MediaLibraryAvailability(
              showLocal: shouldExposeLocalMediaLibrary(
                isWeb: kIsWeb,
                isTvOS: globals.isTvOS,
              ),
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
          ),
          _sectionOrderStore.sectionIds,
        );

        if (sections.isEmpty) {
          return const SizedBox.shrink();
        }

        final selectedIndex = mediaLibrarySectionIndexById(
          sections,
          _selectedSectionId,
        );
        final selectedSection = sections[selectedIndex < 0 ? 0 : selectedIndex];

        return AdaptiveMediaLibraryScaffold(
          sections: sections,
          selectedSection: selectedSection,
          onSectionSelected: _selectSection,
          onSectionOrderChanged: _setSectionOrder,
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
    final result = await showAdaptiveAddMediaFlow(context);
    if (!mounted || result == null) return;
    if (result.connectionsChanged) {
      setState(() => _connectionsInitialized = true);
    } else {
      setState(() {});
    }
    final sectionId = result.sectionId;
    if (sectionId != null) _selectMountedMediaLibrarySection(sectionId);
  }

  Future<void> _showPhonePageActions() async {
    final selected = await CupertinoBottomSheet.show<String>(
      context: context,
      title: '媒体库操作',
      heightRatio: 0.94,
      child: Builder(
        builder: (sheetContext) {
          final label = CupertinoDynamicColor.resolve(
            CupertinoColors.label,
            sheetContext,
          );
          final separator = CupertinoDynamicColor.resolve(
            CupertinoColors.separator,
            sheetContext,
          );

          Widget action({
            required String id,
            required String title,
            required IconData icon,
          }) {
            return CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              onPressed: () => Navigator.of(sheetContext).pop(id),
              child: Row(
                children: [
                  Icon(icon, size: 21, color: label),
                  const SizedBox(width: 14),
                  Text(title, style: TextStyle(fontSize: 16, color: label)),
                  const Spacer(),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 15,
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiaryLabel,
                      sheetContext,
                    ),
                  ),
                ],
              ),
            );
          }

          return SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                action(
                  id: 'add',
                  title: '添加媒体',
                  icon: CupertinoIcons.add_circled,
                ),
                Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 55),
                    color: separator),
                action(
                  id: 'remote',
                  title: '远程访问',
                  icon: CupertinoIcons.link,
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    switch (selected) {
      case 'add':
        await _showAddMedia();
      case 'remote':
        await _openRemoteAccessSettings();
    }
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
