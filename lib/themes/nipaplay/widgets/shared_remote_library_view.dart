import 'dart:async';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/local_library_control_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_layout.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/media_library/adaptive_library_management_overview.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';

enum SharedRemoteViewMode { mediaLibrary, libraryManagement }

class SharedRemoteLibraryView extends StatefulWidget {
  const SharedRemoteLibraryView({
    super.key,
    this.onPlayEpisode,
    this.mode = SharedRemoteViewMode.mediaLibrary,
  });

  final ValueChanged<WatchHistoryItem>? onPlayEpisode;
  final SharedRemoteViewMode mode;

  @override
  State<SharedRemoteLibraryView> createState() =>
      _SharedRemoteLibraryViewState();
}

class _SharedRemoteLibraryViewState extends State<SharedRemoteLibraryView>
    with AutomaticKeepAliveClientMixin {
  static Color get _accentColor => AppAccentColors.current;

  // “只看未观看”状态的持久化 Key
  static const String _unwatchedFilterPrefsKey =
      'shared_library_unwatched_only';

  // 从本地存储恢复“只看未观看”开关状态（重开应用后保持上一次的状态）
  Future<void> _restoreUnwatchedFilterState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_unwatchedFilterPrefsKey);
      if (saved == null || !mounted) return;
      setState(() {
        _showOnlyUnwatched = saved;
      });
    } catch (e) {
      debugPrint('[共享媒体库] 恢复未观看过滤状态失败: $e');
    }
  }

  // 将“只看未观看”开关状态写入本地存储
  Future<void> _persistUnwatchedFilterState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_unwatchedFilterPrefsKey, _showOnlyUnwatched);
    } catch (e) {
      debugPrint('[共享媒体库] 保存未观看过滤状态失败: $e');
    }
  }

  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _managementScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  LocalLibrarySortType _currentSort = LocalLibrarySortType.dateAdded;
  bool _showOnlyUnwatched = false;
  LibraryManagementViewMode _managementViewMode =
      LibraryManagementViewMode.icons;
  String? _managementLoadedHostId;
  Timer? _scanStatusTimer;
  bool _scanStatusRequestInFlight = false;
  final Map<String, List<SharedRemoteFileEntry>> _expandedRemoteDirectories =
      {};
  final Set<String> _loadingRemoteDirectories = {};
  String? _largeScreenSelectedRemoteFolderPath;

  @override
  bool get wantKeepAlive => true;

  // 本地观看历史中已看过的番剧 ID（用于“只看未观看”过滤）
  Set<int> _watchedAnimeIds() {
    try {
      final provider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (provider.isLoaded) {
        return provider.history
            .where((item) => item.animeId != null)
            .map((item) => item.animeId!)
            .toSet();
      }
    } catch (_) {
      // Provider 不可用时退回到静态缓存
    }
    return WatchHistoryManager.getAllCachedHistory()
        .where((item) => item.animeId != null)
        .map((item) => item.animeId!)
        .toSet();
  }

  @override
  void initState() {
    super.initState();
    // 如果是管理模式，确保在第一帧后触发加载
    if (widget.mode == SharedRemoteViewMode.libraryManagement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ensureManagementLoaded();
        }
      });
    }
    // 恢复“只看未观看”开关状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _restoreUnwatchedFilterState();
      }
    });
  }

  @override
  void dispose() {
    _scanStatusTimer?.cancel();
    _gridScrollController.dispose();
    _managementScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        final query = _searchController.text.toLowerCase().trim();
        List<SharedRemoteAnimeSummary> animeSummaries;
        List<SharedRemoteScannedFolder> scannedFolders;

        if (query.isEmpty) {
          animeSummaries = List.from(provider.animeSummaries);
          scannedFolders = List.from(provider.scannedFolders);
        } else {
          animeSummaries = provider.animeSummaries.where((anime) {
            return (anime.nameCn ?? '').toLowerCase().contains(query) ||
                anime.name.toLowerCase().contains(query);
          }).toList();

          scannedFolders = provider.scannedFolders.where((folder) {
            return folder.name.toLowerCase().contains(query) ||
                folder.path.toLowerCase().contains(query);
          }).toList();
        }

        // 只看未观看过滤（基于本地观看历史，看过即视为已观看）
        if (widget.mode == SharedRemoteViewMode.mediaLibrary &&
            _showOnlyUnwatched) {
          final watchedIds = _watchedAnimeIds();
          animeSummaries = animeSummaries
              .where((anime) => !watchedIds.contains(anime.animeId))
              .toList();
        }

        // 排序逻辑
        if (widget.mode == SharedRemoteViewMode.mediaLibrary) {
          if (_currentSort == LocalLibrarySortType.name) {
            animeSummaries.sort((a, b) => (a.nameCn ?? a.name)
                .toLowerCase()
                .compareTo((b.nameCn ?? b.name).toLowerCase()));
          } else if (_currentSort == LocalLibrarySortType.dateAdded) {
            animeSummaries
                .sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
          }
        } else {
          // 管理模式下按名称或路径(作为dateAdded的降级)排序
          if (_currentSort == LocalLibrarySortType.name) {
            scannedFolders.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else {
            scannedFolders.sort(
                (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
          }
        }

        final hasHosts = provider.hosts.isNotEmpty;
        final isManagement =
            widget.mode == SharedRemoteViewMode.libraryManagement;
        final managementBusy = provider.isManagementLoading ||
            provider.scanStatus?.isScanning == true;

        if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
          return _buildLargeScreenSharedRemoteView(
            context: context,
            provider: provider,
            animeSummaries: animeSummaries,
            scannedFolders: scannedFolders,
            hasHosts: hasHosts,
            isManagement: isManagement,
            managementBusy: managementBusy,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalLibraryControlBar(
              searchController: _searchController,
              onSearchChanged: (val) => setState(() {}),
              currentSort: _currentSort,
              onSortChanged: (type) {
                setState(() {
                  _currentSort = type;
                });
              },
              showSort: true,
              showUnwatchedOnly: isManagement ? null : _showOnlyUnwatched,
              onToggleUnwatchedOnly: isManagement
                  ? null
                  : () {
                      setState(() {
                        _showOnlyUnwatched = !_showOnlyUnwatched;
                      });
                      _persistUnwatchedFilterState();
                    },
              viewMode: isManagement ? _managementViewMode : null,
              onToggleViewMode: isManagement
                  ? () {
                      setState(() {
                        _managementViewMode = _managementViewMode ==
                                LibraryManagementViewMode.icons
                            ? LibraryManagementViewMode.list
                            : LibraryManagementViewMode.icons;
                      });
                    }
                  : null,
              trailingActions: [
                _buildActionIcon(
                  icon: Ionicons.refresh_outline,
                  tooltip: isManagement ? '刷新库管理' : '刷新共享媒体',
                  onPressed: () {
                    if (!provider.hasActiveHost) {
                      BlurSnackBar.show(context, '请先添加并选择共享客户端');
                      return;
                    }
                    if (isManagement) {
                      provider.refreshManagement(userInitiated: true);
                    } else {
                      provider.refreshLibrary(userInitiated: true);
                    }
                  },
                ),
                if (isManagement) ...[
                  _buildActionIcon(
                    icon: Ionicons.trash_outline,
                    tooltip: '清理不存在文件夹',
                    onPressed: managementBusy
                        ? null
                        : () async {
                            final removedCount =
                                await provider.cleanupMissingRemoteFolders();
                            if (!mounted) return;
                            final error = provider.managementErrorMessage;
                            if (error != null && error.isNotEmpty) {
                              BlurSnackBar.show(context, error);
                              return;
                            }
                            if (removedCount > 0) {
                              BlurSnackBar.show(
                                context,
                                '已清理 $removedCount 个不存在的文件夹',
                              );
                            } else {
                              BlurSnackBar.show(context, '没有需要清理的不存在文件夹');
                            }
                          },
                  ),
                  _buildActionIcon(
                    icon: Ionicons.add_circle_outline,
                    tooltip: '添加文件夹',
                    onPressed: managementBusy
                        ? null
                        : () => _openAddFolderDialog(context, provider),
                  ),
                  _buildActionIcon(
                    icon: Ionicons.flash_outline,
                    tooltip: '智能刷新',
                    onPressed: managementBusy
                        ? null
                        : () async {
                            await provider.rescanRemoteAll(
                                skipPreviouslyMatchedUnwatched: true);
                            _startScanStatusPolling();
                          },
                  ),
                ],
                _buildActionIcon(
                  icon: Ionicons.link_outline,
                  tooltip: '切换共享客户端',
                  onPressed: () => SharedRemoteHostSelectionSheet.show(context),
                ),
              ],
            ),
            if (isManagement && provider.scanStatus?.isScanning == true)
              _buildScanningIndicator(provider),
            if (isManagement && provider.managementErrorMessage != null)
              _buildErrorChip(
                provider.managementErrorMessage!,
                onClose: provider.clearManagementError,
              ),
            if (!isManagement && provider.errorMessage != null)
              _buildErrorChip(
                provider.errorMessage!,
                onClose: provider.clearError,
              ),
            Expanded(
              child: isManagement
                  ? _buildManagementBody(
                      context, provider, hasHosts, scannedFolders)
                  : _buildMediaBody(
                      context,
                      provider,
                      animeSummaries,
                      hasHosts,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLargeScreenSharedRemoteView({
    required BuildContext context,
    required SharedRemoteLibraryProvider provider,
    required List<SharedRemoteAnimeSummary> animeSummaries,
    required List<SharedRemoteScannedFolder> scannedFolders,
    required bool hasHosts,
    required bool isManagement,
    required bool managementBusy,
  }) {
    return Column(
      children: [
        _buildLargeScreenTopBar(
          provider: provider,
          isManagement: isManagement,
          managementBusy: managementBusy,
        ),
        const SizedBox(height: 14),
        _buildLargeScreenSortRow(isManagement: isManagement),
        if (isManagement && provider.scanStatus?.isScanning == true) ...[
          const SizedBox(height: 14),
          _buildLargeScreenScanningIndicator(provider),
        ],
        if (isManagement && provider.managementErrorMessage != null) ...[
          const SizedBox(height: 14),
          _buildLargeScreenNotice(
            message: provider.managementErrorMessage!,
            onClose: provider.clearManagementError,
          ),
        ],
        if (!isManagement && provider.errorMessage != null) ...[
          const SizedBox(height: 14),
          _buildLargeScreenNotice(
            message: provider.errorMessage!,
            onClose: provider.clearError,
          ),
        ],
        const SizedBox(height: 18),
        Expanded(
          child: isManagement
              ? _buildLargeScreenManagementBody(
                  context,
                  provider,
                  hasHosts,
                  scannedFolders,
                )
              : _buildLargeScreenMediaBody(
                  context,
                  provider,
                  animeSummaries,
                  hasHosts,
                ),
        ),
      ],
    );
  }

  Widget _buildLargeScreenTopBar({
    required SharedRemoteLibraryProvider provider,
    required bool isManagement,
    required bool managementBusy,
  }) {
    final title = isManagement ? '共享库管理' : '共享媒体库';
    return Row(
      children: [
        Expanded(
          child: NipaplayLargeScreenTextInput(
            controller: _searchController,
            hintText: '搜索 $title',
            onChanged: (_) => setState(() {}),
            suffix: _searchController.text.isEmpty
                ? null
                : AdaptiveMediaIconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    desktopIcon: Icons.close_rounded,
                    phoneIcon: cupertino.CupertinoIcons.clear,
                  ),
          ),
        ),
        const SizedBox(width: 14),
        NipaplayLargeScreenActionButton(
          icon: Ionicons.refresh_outline,
          label: '刷新',
          onPressed: () {
            if (!provider.hasActiveHost) {
              BlurSnackBar.show(context, '请先添加并选择共享客户端');
              return;
            }
            if (isManagement) {
              provider.refreshManagement(userInitiated: true);
            } else {
              provider.refreshLibrary(userInitiated: true);
            }
          },
        ),
        if (isManagement) ...[
          const SizedBox(width: 10),
          NipaplayLargeScreenActionButton(
            icon: Ionicons.add_circle_outline,
            label: '添加',
            onPressed: managementBusy
                ? null
                : () => _openAddFolderDialog(context, provider),
          ),
          const SizedBox(width: 10),
          NipaplayLargeScreenActionButton(
            icon: Ionicons.flash_outline,
            label: '智能刷新',
            onPressed: managementBusy
                ? null
                : () async {
                    await provider.rescanRemoteAll(
                      skipPreviouslyMatchedUnwatched: true,
                    );
                    _startScanStatusPolling();
                  },
          ),
          const SizedBox(width: 10),
          NipaplayLargeScreenActionButton(
            icon: Ionicons.trash_outline,
            label: '清理',
            onPressed: managementBusy
                ? null
                : () => _cleanupLargeScreenSharedRemote(provider),
          ),
        ],
        const SizedBox(width: 10),
        NipaplayLargeScreenActionButton(
          icon: Ionicons.link_outline,
          label: '客户端',
          onPressed: () => SharedRemoteHostSelectionSheet.show(context),
        ),
      ],
    );
  }

  Widget _buildLargeScreenSortRow({required bool isManagement}) {
    return Row(
      children: [
        _buildLargeScreenSortChip(
          label: isManagement ? '路径' : '最近观看',
          icon: Icons.schedule_rounded,
          type: LocalLibrarySortType.dateAdded,
        ),
        const SizedBox(width: 10),
        _buildLargeScreenSortChip(
          label: '名称',
          icon: Icons.sort_by_alpha_rounded,
          type: LocalLibrarySortType.name,
        ),
        if (!isManagement) ...[
          const SizedBox(width: 10),
          _buildLargeScreenSortChip(
            label: '评分',
            icon: Icons.star_rounded,
            type: LocalLibrarySortType.rating,
          ),
          const SizedBox(width: 10),
          _buildLargeScreenUnwatchedChip(),
        ],
      ],
    );
  }

  Widget _buildLargeScreenUnwatchedChip() {
    final selected = _showOnlyUnwatched;
    return NipaplayLargeScreenFocusableAction(
      onActivate: () {
        setState(() {
          _showOnlyUnwatched = !_showOnlyUnwatched;
        });
        _persistUnwatchedFilterState();
      },
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      focusScale: 1.04,
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: selected
            ? _accentColor.withValues(alpha: 0.26)
            : Colors.white.withValues(alpha: 0.09),
        idleBackgroundLight: selected
            ? _accentColor.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.82),
        focusStrokeColor: selected ? _accentColor : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Ionicons.eye_off_outline : Ionicons.eye_outline,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            '只看未观看',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenSortChip({
    required String label,
    required IconData icon,
    required LocalLibrarySortType type,
  }) {
    final selected = _currentSort == type;
    return NipaplayLargeScreenFocusableAction(
      onActivate: () {
        if (_currentSort == type) return;
        setState(() {
          _currentSort = type;
        });
      },
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      focusScale: 1.04,
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: selected
            ? _accentColor.withValues(alpha: 0.26)
            : Colors.white.withValues(alpha: 0.09),
        idleBackgroundLight: selected
            ? _accentColor.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.82),
        focusStrokeColor: selected ? _accentColor : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenScanningIndicator(
    SharedRemoteLibraryProvider provider,
  ) {
    final status = provider.scanStatus;
    final progress = (status?.progress ?? 0.0).clamp(0.0, 1.0);
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
    return NipaplayLargeScreenPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status?.message ?? '正在扫描...',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AdaptiveMediaProgressBar(
            value: progress,
            backgroundColor: Colors.white10,
            color: _accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenNotice({
    required String message,
    required VoidCallback onClose,
  }) {
    return NipaplayLargeScreenPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Ionicons.warning_outline,
              color: Colors.orangeAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          NipaplayLargeScreenIconButton(
            icon: Ionicons.close_outline,
            tooltip: '关闭',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenMediaBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteAnimeSummary> animeSummaries,
    bool hasHosts,
  ) {
    if (provider.isInitializing ||
        (provider.isLoading && animeSummaries.isEmpty && hasHosts)) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }

    if (!hasHosts) {
      return NipaplayLargeScreenEmptyState(
        icon: Ionicons.cloud_outline,
        title: '尚未添加共享客户端',
        subtitle: '添加客户端后可以从大屏模式浏览远程媒体库',
        action: NipaplayLargeScreenActionButton(
          icon: Ionicons.link_outline,
          label: '添加客户端',
          onPressed: () => SharedRemoteHostSelectionSheet.show(context),
        ),
      );
    }

    if (animeSummaries.isEmpty) {
      final filteredEmpty =
          _showOnlyUnwatched && _searchController.text.trim().isEmpty;
      return NipaplayLargeScreenEmptyState(
        icon: filteredEmpty
            ? Ionicons.eye_off_outline
            : Ionicons.folder_open_outline,
        title: filteredEmpty
            ? '没有未观看的番剧'
            : (provider.activeHost == null ? '请选择共享客户端' : '该客户端尚未扫描番剧'),
        subtitle: filteredEmpty
            ? '关闭“只看未观看”后可查看全部内容'
            : '切换客户端或进入库管理添加远程文件夹',
      );
    }

    return GridView.builder(
      controller: _gridScrollController,
      padding: const EdgeInsets.only(bottom: 96),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 244,
        mainAxisExtent: 468,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
      ),
      itemCount: animeSummaries.length,
      itemBuilder: (context, index) {
        return _buildLargeScreenSharedAnimeCard(
          context,
          provider,
          animeSummaries[index],
          autofocus: index == 0,
        );
      },
    );
  }

  Widget _buildLargeScreenSharedAnimeCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime, {
    required bool autofocus,
  }) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
    final title = anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name;

    return NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: () => _openEpisodeSheet(context, provider, anime),
      borderRadius: BorderRadius.circular(8),
      padding: EdgeInsets.zero,
      focusScale: 1,
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: Colors.white.withValues(alpha: 0.07),
        idleBackgroundLight: Colors.white.withValues(alpha: 0.82),
        focusStrokeWidth: 2.4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImageWidget(
                    imageUrl: anime.imageUrl ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __) =>
                        _buildLargeScreenSharedFallbackPoster(textColor),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.74),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _buildLargeScreenSharedBadge(
                      provider.activeHost?.displayName ?? '共享',
                    ),
                  ),
                  if (anime.episodeCount > 0)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _buildLargeScreenSharedBadge(
                        '${anime.episodeCount} 集',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  if (anime.summary?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      anime.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.52),
                        fontSize: 12,
                        height: 1.26,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeScreenManagementBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    bool hasHosts,
    List<SharedRemoteScannedFolder> folders,
  ) {
    if (provider.isInitializing ||
        (provider.isManagementLoading &&
            folders.isEmpty &&
            provider.scanStatus == null)) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }

    if (!hasHosts) {
      return NipaplayLargeScreenEmptyState(
        icon: Ionicons.cloud_outline,
        title: '尚未添加共享客户端',
        subtitle: '请先添加客户端，再管理远程媒体文件夹',
        action: NipaplayLargeScreenActionButton(
          icon: Ionicons.link_outline,
          label: '添加客户端',
          onPressed: () => SharedRemoteHostSelectionSheet.show(context),
        ),
      );
    }

    if (!provider.hasActiveHost) {
      return const NipaplayLargeScreenEmptyState(
        icon: Ionicons.folder_open_outline,
        title: '请选择一个共享客户端',
        subtitle: '切换客户端后再进入库管理',
      );
    }

    if (provider.managementErrorMessage != null &&
        folders.isEmpty &&
        provider.scanStatus == null) {
      return NipaplayLargeScreenEmptyState(
        icon: Ionicons.warning_outline,
        title: '库管理不可用',
        subtitle: provider.managementErrorMessage!,
      );
    }

    if (folders.isEmpty) {
      return NipaplayLargeScreenEmptyState(
        icon: Ionicons.folder_open_outline,
        title: '远程端未添加媒体文件夹',
        subtitle: '添加文件夹后可以在这里扫描、浏览和播放远程视频',
        action: NipaplayLargeScreenActionButton(
          icon: Ionicons.add_circle_outline,
          label: '添加文件夹',
          onPressed: () => _openAddFolderDialog(context, provider),
        ),
      );
    }

    final selectedPath = folders.any(
            (folder) => folder.path == _largeScreenSelectedRemoteFolderPath)
        ? _largeScreenSelectedRemoteFolderPath
        : folders.first.path;
    final selectedFolder =
        folders.firstWhere((folder) => folder.path == selectedPath);

    return Row(
      children: [
        SizedBox(
          width: 390,
          child: ListView.separated(
            controller: _managementScrollController,
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: folders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return _buildLargeScreenRemoteFolderCard(
                provider,
                folder,
                selected: folder.path == selectedPath,
                autofocus: index == 0,
              );
            },
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _buildLargeScreenRemoteFolderDetail(
            context,
            provider,
            selectedFolder,
          ),
        ),
      ],
    );
  }

  Widget _buildLargeScreenRemoteFolderCard(
    SharedRemoteLibraryProvider provider,
    SharedRemoteScannedFolder folder, {
    required bool selected,
    required bool autofocus,
  }) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
    final busy =
        provider.isManagementLoading || provider.scanStatus?.isScanning == true;
    final title = folder.name.isNotEmpty ? folder.name : folder.path;
    final statusColor = folder.exists ? _accentColor : Colors.orangeAccent;

    return NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: () => _selectLargeScreenRemoteFolder(provider, folder.path),
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.all(14),
      focusScale: 1.025,
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: selected
            ? _accentColor.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.075),
        idleBackgroundLight: selected
            ? _accentColor.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.82),
        focusStrokeColor: selected ? _accentColor : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                folder.exists
                    ? Icons.folder_open_outlined
                    : Ionicons.warning_outline,
                color: statusColor,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            folder.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.58),
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              NipaplayLargeScreenIconButton(
                icon: Icons.refresh_rounded,
                tooltip: '扫描',
                onPressed: busy
                    ? null
                    : () async {
                        await provider.addRemoteFolder(
                          folderPath: folder.path,
                          scan: true,
                          skipPreviouslyMatchedUnwatched: false,
                        );
                        _startScanStatusPolling();
                      },
              ),
              const SizedBox(width: 8),
              NipaplayLargeScreenIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: '移除',
                onPressed: busy
                    ? null
                    : () => provider.removeRemoteFolder(folder.path),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenRemoteFolderDetail(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteScannedFolder folder,
  ) {
    final folderPath = folder.path;
    final loading = _loadingRemoteDirectories.contains(folderPath);
    final expanded = _expandedRemoteDirectories.containsKey(folderPath);
    if (!loading && !expanded) {
      Future.microtask(() => _loadRemoteDirectory(provider, folderPath));
    }

    return NipaplayLargeScreenPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NipaplayLargeScreenSectionHeader(
            title: folder.name.isNotEmpty ? folder.name : folder.path,
            subtitle: folder.path,
            trailing: NipaplayLargeScreenActionButton(
              icon: Icons.refresh_rounded,
              label: '扫描',
              compact: true,
              onPressed: provider.scanStatus?.isScanning == true
                  ? null
                  : () async {
                      await provider.addRemoteFolder(
                        folderPath: folder.path,
                        scan: true,
                        skipPreviouslyMatchedUnwatched: false,
                      );
                      _startScanStatusPolling();
                    },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: loading
                ? const Center(child: AdaptiveMediaActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 80),
                    children: _buildRemoteDirectoryChildren(
                      context,
                      provider,
                      folderPath,
                      1,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenSharedFallbackPoster(Color textColor) {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: textColor.withValues(alpha: 0.46),
          size: 52,
        ),
      ),
    );
  }

  Widget _buildLargeScreenSharedBadge(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _selectLargeScreenRemoteFolder(
    SharedRemoteLibraryProvider provider,
    String folderPath,
  ) {
    setState(() {
      _largeScreenSelectedRemoteFolderPath = folderPath;
    });
    if (!_expandedRemoteDirectories.containsKey(folderPath) &&
        !_loadingRemoteDirectories.contains(folderPath)) {
      _loadRemoteDirectory(provider, folderPath);
    }
  }

  Future<void> _cleanupLargeScreenSharedRemote(
    SharedRemoteLibraryProvider provider,
  ) async {
    final removedCount = await provider.cleanupMissingRemoteFolders();
    if (!mounted) return;
    final error = provider.managementErrorMessage;
    if (error != null && error.isNotEmpty) {
      BlurSnackBar.show(context, error);
      return;
    }
    BlurSnackBar.show(
      context,
      removedCount > 0 ? '已清理 $removedCount 个不存在的文件夹' : '没有需要清理的不存在文件夹',
    );
  }

  Widget _buildScanningIndicator(SharedRemoteLibraryProvider provider) {
    final status = provider.scanStatus;
    final progress = (status?.progress ?? 0.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status?.message ?? '正在扫描...',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          SizedBox(height: 4),
          AdaptiveMediaProgressBar(
            value: progress,
            backgroundColor: Colors.white10,
            color: _accentColor,
          ),
        ],
      ),
    );
  }

  LocalLibraryActionControl _buildActionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return LocalLibraryActionControl(
      label: tooltip,
      desktopIcon: icon,
      phoneIcon: switch (icon) {
        Ionicons.refresh_outline => cupertino.CupertinoIcons.refresh,
        Ionicons.trash_outline => cupertino.CupertinoIcons.delete,
        Ionicons.add_circle_outline => cupertino.CupertinoIcons.add_circled,
        Ionicons.flash_outline => cupertino.CupertinoIcons.bolt,
        Ionicons.link_outline => cupertino.CupertinoIcons.link,
        _ => cupertino.CupertinoIcons.ellipsis,
      },
      onPressed: onPressed,
      isDestructive: icon == Ionicons.trash_outline,
    );
  }

  Widget _buildMediaBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteAnimeSummary> animeSummaries,
    bool hasHosts,
  ) {
    if (provider.isInitializing) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isLoading && animeSummaries.isEmpty) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }

    if (animeSummaries.isEmpty) {
      return _buildEmptyLibraryPlaceholder(
        context,
        provider.activeHost,
        filteredEmpty:
            _showOnlyUnwatched && _searchController.text.trim().isEmpty,
      );
    }

    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;

    return RepaintBoundary(
      child: AdaptiveMediaScrollbar(
        controller: _gridScrollController,
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: showSummary
                ? HorizontalAnimeCard.detailedGridMaxCrossAxisExtent
                : HorizontalAnimeCard.compactGridMaxCrossAxisExtent,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: showSummary
                ? HorizontalAnimeCard.detailedCardHeight
                : HorizontalAnimeCard.compactCardHeight,
          ),
          itemCount: animeSummaries.length,
          itemBuilder: (context, index) {
            final anime = animeSummaries[index];
            return HorizontalAnimeCard(
              key: ValueKey('shared_${anime.animeId}'),
              title:
                  anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
              imageUrl: anime.imageUrl ?? '',
              source: provider.activeHost?.displayName,
              rating: null,
              onTap: () => _openEpisodeSheet(context, provider, anime),
            );
          },
        ),
      ),
    );
  }

  void _ensureManagementLoaded() {
    final provider = context.read<SharedRemoteLibraryProvider>();
    if (!provider.hasActiveHost) {
      return;
    }

    final hostId = provider.activeHostId;
    if (hostId == null) {
      return;
    }

    if (_managementLoadedHostId != hostId) {
      if (mounted) {
        setState(() {
          _expandedRemoteDirectories.clear();
          _loadingRemoteDirectories.clear();
        });
      }
      _managementLoadedHostId = hostId;
      provider.refreshManagement(userInitiated: true).then((_) {
        if (!mounted) return;
        if (context
                .read<SharedRemoteLibraryProvider>()
                .scanStatus
                ?.isScanning ==
            true) {
          _startScanStatusPolling();
        }
      });
      return;
    }

    if (provider.scannedFolders.isEmpty &&
        !provider.isManagementLoading &&
        provider.managementErrorMessage == null) {
      provider.refreshManagement(userInitiated: true).then((_) {
        if (!mounted) return;
        if (context
                .read<SharedRemoteLibraryProvider>()
                .scanStatus
                ?.isScanning ==
            true) {
          _startScanStatusPolling();
        }
      });
    }
  }

  void _startScanStatusPolling() {
    _scanStatusTimer?.cancel();
    _scanStatusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _scanStatusTimer?.cancel();
        _scanStatusTimer = null;
        return;
      }

      final provider = context.read<SharedRemoteLibraryProvider>();
      if (widget.mode != SharedRemoteViewMode.libraryManagement ||
          !provider.hasActiveHost) {
        _scanStatusTimer?.cancel();
        _scanStatusTimer = null;
        return;
      }

      final scanning = provider.scanStatus?.isScanning == true;
      if (!scanning) {
        _scanStatusTimer?.cancel();
        _scanStatusTimer = null;
        return;
      }

      if (_scanStatusRequestInFlight) {
        return;
      }
      _scanStatusRequestInFlight = true;
      provider.refreshScanStatus(showLoading: false).whenComplete(() {
        _scanStatusRequestInFlight = false;
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
      BlurSnackBar.show(context, '加载文件夹失败: $e');
    }
  }

  List<Widget> _buildRemoteDirectoryChildren(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String directoryPath,
    int depth,
  ) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final Color iconColor = isDark ? Colors.white70 : Colors.black54;

    final entries = List<SharedRemoteFileEntry>.from(
        _expandedRemoteDirectories[directoryPath] ?? const []);

    // 对子条目进行排序
    entries.sort((a, b) {
      // 文件夹永远在前面
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      if (_currentSort == LocalLibrarySortType.name) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else {
        // 最近修改 (降序)
        final timeA = a.modifiedTime ?? DateTime(1970);
        final timeB = b.modifiedTime ?? DateTime(1970);
        return timeB.compareTo(timeA);
      }
    });

    final indent = libraryManagementTreeIndent(depth);

    if (entries.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(indent, 6, 0, 6),
          child: Text(
            '（空文件夹）',
            locale: const Locale('zh', 'CN'),
            style: TextStyle(color: secondaryTextColor, fontSize: 12),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final entry in entries) {
      final entryPath = entry.path;
      final entryName = entry.name.isNotEmpty ? entry.name : entryPath;
      if (entry.isDirectory) {
        final expanded = _expandedRemoteDirectories.containsKey(entryPath);
        final loading = _loadingRemoteDirectories.contains(entryPath);
        widgets.add(
          LibraryManagementFolderRow(
            title: entryName,
            locale: const Locale('zh', 'CN'),
            indent: indent,
            expanded: expanded,
            loading: loading,
            iconColor: iconColor,
            textColor: textColor,
            secondaryTextColor: secondaryTextColor,
            onTap: () => _toggleRemoteDirectory(provider, entryPath),
          ),
        );
        if (expanded) {
          widgets.addAll(_buildRemoteDirectoryChildren(
              context, provider, entryPath, depth + 1));
        }
        continue;
      }

      final canPlay = provider.isRemoteFilePlayable(entry);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AdaptiveMediaListTile(
            contentPadding: EdgeInsets.fromLTRB(indent, 0, 8, 0),
            leading: Icon(
              canPlay ? Icons.videocam_outlined : Icons.description_outlined,
              color: iconColor,
              size: 18,
            ),
            title: Text(
              entryName,
              locale: const Locale('zh', 'CN'),
              style: TextStyle(color: textColor, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _buildRemoteFileSubtitle(context, entry),
            onTap: canPlay ? () => _playRemoteFile(provider, entry) : null,
          ),
        ),
      );
    }
    return widgets;
  }

  void _playRemoteFile(
    SharedRemoteLibraryProvider provider,
    SharedRemoteFileEntry entry,
  ) {
    final callback = widget.onPlayEpisode;
    if (callback == null) {
      BlurSnackBar.show(context, '当前页面不支持播放');
      return;
    }
    if (!provider.isRemoteFilePlayable(entry)) {
      BlurSnackBar.show(context, '该文件不是可播放媒体');
      return;
    }

    try {
      final streamUrl =
          provider.buildRemoteFileStreamUri(entry.path).toString();
      final fallbackTitle = entry.name.isNotEmpty
          ? p.basenameWithoutExtension(entry.name)
          : p.basenameWithoutExtension(entry.path);
      final resolvedAnimeName = (entry.animeName?.trim().isNotEmpty == true)
          ? entry.animeName!.trim()
          : (fallbackTitle.isNotEmpty
              ? fallbackTitle
              : p.basenameWithoutExtension(entry.path));
      final resolvedEpisodeTitle = entry.episodeTitle?.trim();

      final item = WatchHistoryItem(
        filePath: streamUrl,
        animeName: resolvedAnimeName,
        episodeTitle: resolvedEpisodeTitle?.isNotEmpty == true
            ? resolvedEpisodeTitle
            : null,
        animeId: entry.animeId,
        episodeId: entry.episodeId,
        watchProgress: 0.0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
      );
      callback(item);
    } catch (e) {
      BlurSnackBar.show(context, '播放失败: $e');
    }
  }

  Widget? _buildRemoteFileSubtitle(
      BuildContext context, SharedRemoteFileEntry entry) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color secondaryTextColor = isDark ? Colors.white54 : Colors.black54;

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
      return Text(
        '已识别',
        locale: const Locale('zh', 'CN'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: secondaryTextColor, fontSize: 12),
      );
    }

    return Text(
      parts.join(' - '),
      locale: const Locale('zh', 'CN'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: secondaryTextColor, fontSize: 12),
    );
  }

  Widget _buildErrorChip(String message, {required VoidCallback onClose}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.orange.withOpacity(0.12),
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Ionicons.warning_outline,
                color: Colors.orangeAccent, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                locale: const Locale('zh', 'CN'),
                style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
            AdaptiveMediaIconButton(
              onPressed: onClose,
              desktopIcon: Ionicons.close_outline,
              phoneIcon: cupertino.CupertinoIcons.clear,
              tooltip: '关闭',
              color: Colors.orangeAccent,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagementBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    bool hasHosts,
    List<SharedRemoteScannedFolder> folders,
  ) {
    if (provider.isInitializing) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isManagementLoading &&
        folders.isEmpty &&
        provider.scanStatus == null) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }

    if (!provider.hasActiveHost) {
      return _buildEmptyManagementPlaceholder(
        context,
        title: '请选择一个共享客户端',
        subtitle: '先在右侧切换共享客户端，然后再进入库管理。',
      );
    }

    if (provider.managementErrorMessage != null &&
        folders.isEmpty &&
        provider.scanStatus == null) {
      return _buildEmptyManagementPlaceholder(
        context,
        title: '库管理不可用',
        subtitle: provider.managementErrorMessage!,
      );
    }

    if (folders.isEmpty) {
      return _buildEmptyManagementPlaceholder(
        context,
        title: '远程端未添加媒体文件夹',
        subtitle: '可点击右侧按钮添加文件夹并触发扫描。',
      );
    }

    return AdaptiveLibraryManagementOverview(
      items: _buildUnifiedRemoteManagementItems(provider, folders),
      viewMode: _managementViewMode,
      emptyContent: const LibraryManagementEmptyContent(
        title: '远程端未添加媒体文件夹',
        subtitle: '使用顶部添加按钮选择文件夹并扫描。',
      ),
    );
  }

  List<UnifiedLibraryManagementItem> _buildUnifiedRemoteManagementItems(
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteScannedFolder> folders,
  ) {
    final busy =
        provider.isManagementLoading || provider.scanStatus?.isScanning == true;
    final items = <UnifiedLibraryManagementItem>[];

    for (final folder in folders) {
      final path = folder.path;
      final expanded = _expandedRemoteDirectories.containsKey(path);
      items.add(
        UnifiedLibraryManagementItem(
          id: 'remote-root:$path',
          title: folder.name.isNotEmpty ? folder.name : path,
          subtitle: path,
          status: folder.exists
              ? (_loadingRemoteDirectories.contains(path) ? '加载中' : null)
              : '不存在',
          icon: LibraryManagementIcon.folder,
          onOpen: () => _toggleRemoteDirectory(provider, path),
          actions: [
            UnifiedLibraryManagementAction(
              label: expanded ? '收起文件夹' : '浏览文件',
              icon: LibraryManagementIcon.browse,
              onPressed: () => _toggleRemoteDirectory(provider, path),
            ),
            UnifiedLibraryManagementAction(
              label: '重新扫描',
              icon: LibraryManagementIcon.refresh,
              onPressed: busy
                  ? null
                  : () async {
                      await provider.addRemoteFolder(
                        folderPath: path,
                        scan: true,
                        skipPreviouslyMatchedUnwatched: false,
                      );
                      _startScanStatusPolling();
                    },
            ),
            UnifiedLibraryManagementAction(
              label: '移除文件夹',
              icon: LibraryManagementIcon.delete,
              destructive: true,
              onPressed: busy ? null : () => provider.removeRemoteFolder(path),
            ),
          ],
        ),
      );
      if (expanded) {
        _appendUnifiedRemoteEntries(
          items,
          provider,
          parentPath: path,
          depth: 1,
        );
      }
    }
    return items;
  }

  void _appendUnifiedRemoteEntries(
    List<UnifiedLibraryManagementItem> output,
    SharedRemoteLibraryProvider provider, {
    required String parentPath,
    required int depth,
  }) {
    final entries = List<SharedRemoteFileEntry>.from(
      _expandedRemoteDirectories[parentPath] ?? const [],
    )..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    for (final entry in entries) {
      final path = entry.path;
      final title = entry.name.isNotEmpty ? entry.name : path;
      final canPlay = provider.isRemoteFilePlayable(entry);
      output.add(
        UnifiedLibraryManagementItem(
          id: 'remote-entry:$path',
          title: title,
          subtitle: entry.isDirectory
              ? '子文件夹 · ${p.dirname(path)}'
              : (entry.episodeTitle?.trim().isNotEmpty == true
                  ? entry.episodeTitle!.trim()
                  : p.dirname(path)),
          status: _loadingRemoteDirectories.contains(path) ? '加载中' : null,
          icon: entry.isDirectory
              ? LibraryManagementIcon.folder
              : canPlay
                  ? LibraryManagementIcon.video
                  : LibraryManagementIcon.file,
          onOpen: entry.isDirectory
              ? () => _toggleRemoteDirectory(provider, path)
              : canPlay
                  ? () => _playRemoteFile(provider, entry)
                  : null,
          actions: [
            if (entry.isDirectory)
              UnifiedLibraryManagementAction(
                label: '打开文件夹',
                icon: LibraryManagementIcon.browse,
                onPressed: () => _toggleRemoteDirectory(provider, path),
              ),
            if (!entry.isDirectory && canPlay)
              UnifiedLibraryManagementAction(
                label: '播放',
                icon: LibraryManagementIcon.video,
                onPressed: () => _playRemoteFile(provider, entry),
              ),
          ],
        ),
      );
      if (entry.isDirectory && _expandedRemoteDirectories.containsKey(path)) {
        _appendUnifiedRemoteEntries(
          output,
          provider,
          parentPath: path,
          depth: depth + 1,
        );
      }
    }
  }

  Widget _buildEmptyManagementPlaceholder(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return LibraryManagementEmptyState(
      icon: Ionicons.folder_open_outline,
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _buildEmptyHostsPlaceholder(BuildContext context) {
    return const LibraryManagementEmptyState(
      icon: Ionicons.cloud_outline,
      title: '尚未添加共享客户端',
      subtitle: '请前往设置 > 远程媒体库 添加',
    );
  }

  Widget _buildEmptyLibraryPlaceholder(
    BuildContext context,
    SharedRemoteHost? host, {
    bool filteredEmpty = false,
  }) {
    final String message;
    if (host == null) {
      message = '请选择一个共享客户端';
    } else if (filteredEmpty) {
      message = '没有未观看的番剧';
    } else {
      message = '该客户端尚未扫描任何番剧';
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filteredEmpty ? Ionicons.eye_off_outline : Ionicons.folder_open_outline,
            color: Colors.white38,
            size: 48,
          ),
          SizedBox(height: 12),
          Text(
            message,
            locale: const Locale('zh', 'CN'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddFolderDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    if (!provider.hasActiveHost) {
      BlurSnackBar.show(context, '请先添加并选择共享客户端');
      return;
    }

    final confirmed = await BlurLoginDialog.show(
      context,
      title: '添加媒体文件夹（远程）',
      fields: const [
        LoginField(
          key: 'path',
          label: '文件夹路径',
          hint: '例如：/Volumes/Anime 或 D:\\Anime',
        ),
      ],
      loginButtonText: '添加并扫描',
      onLogin: (values) async {
        await provider.addRemoteFolder(
          folderPath: values['path'] ?? '',
          scan: true,
          skipPreviouslyMatchedUnwatched: false,
        );
        final error = provider.managementErrorMessage;
        if (error != null && error.isNotEmpty) {
          return LoginResult(success: false, message: error);
        }
        return const LoginResult(success: true, message: '已请求远程端开始扫描');
      },
    );

    if (confirmed == true && mounted) {
      _startScanStatusPolling();
    }
  }

  Future<void> _openEpisodeSheet(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime,
  ) async {
    try {
      final provider =
          Provider.of<SharedRemoteLibraryProvider>(context, listen: false);
      await ThemedAnimeDetail.show(
        context,
        anime.animeId,
        sharedSummary: anime,
        sharedEpisodeLoader: () =>
            provider.loadAnimeEpisodes(anime.animeId, force: true),
        sharedEpisodeBuilder: (episode) => provider.buildPlayableItem(
          anime: anime,
          episode: episode,
        ),
        sharedSourceLabel: provider.activeHost?.displayName,
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '打开详情失败: $e');
    }
  }
}
