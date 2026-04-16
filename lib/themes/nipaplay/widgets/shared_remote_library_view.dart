import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/themes/nipaplay/widgets/local_library_control_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_layout.dart';
import 'package:nipaplay/themes/nipaplay/widgets/search_bar_action_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';

enum SharedRemoteViewMode { mediaLibrary, libraryManagement }

class SharedRemoteLibraryView extends StatefulWidget {
  const SharedRemoteLibraryView({
    super.key,
    this.onPlayEpisode,
    this.mode = SharedRemoteViewMode.mediaLibrary,
  });

  final OnPlayEpisodeCallback? onPlayEpisode;
  final SharedRemoteViewMode mode;

  @override
  State<SharedRemoteLibraryView> createState() =>
      _SharedRemoteLibraryViewState();
}

class _SharedRemoteLibraryViewState extends State<SharedRemoteLibraryView>
    with AutomaticKeepAliveClientMixin {
  static const Color _accentColor = Color(0xFFFF2E55);
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _managementScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  LocalLibrarySortType _currentSort = LocalLibrarySortType.dateAdded;
  String? _managementLoadedHostId;
  Timer? _scanStatusTimer;
  bool _scanStatusRequestInFlight = false;
  final Map<String, List<SharedRemoteFileEntry>> _expandedRemoteDirectories =
      {};
  final Set<String> _loadingRemoteDirectories = {};

  @override
  bool get wantKeepAlive => true;

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

  Widget _buildScanningIndicator(SharedRemoteLibraryProvider provider) {
    final status = provider.scanStatus;
    final progress = (status?.progress ?? 0.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status?.message ?? '正在扫描...',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation<Color>(_accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SearchBarActionButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  Widget _buildMediaBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteAnimeSummary> animeSummaries,
    bool hasHosts,
  ) {
    if (provider.isInitializing) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isLoading && animeSummaries.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }

    if (animeSummaries.isEmpty) {
      return _buildEmptyLibraryPlaceholder(context, provider.activeHost);
    }

    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;

    return RepaintBoundary(
      child: Scrollbar(
        controller: _gridScrollController,
        radius: const Radius.circular(4),
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
          child: ListTile(
            dense: true,
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
            const Icon(Ionicons.warning_outline,
                color: Colors.orangeAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                locale: const Locale('zh', 'CN'),
                style:
                    const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Ionicons.close_outline,
                  color: Colors.orangeAccent, size: 16),
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
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isManagementLoading &&
        folders.isEmpty &&
        provider.scanStatus == null) {
      return const Center(
          child: CircularProgressIndicator(color: _accentColor));
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

    return LibraryManagementList<SharedRemoteScannedFolder>(
      scrollController: _managementScrollController,
      items: folders,
      itemBuilder: (context, folder) =>
          _buildRemoteFolderCard(context, provider, folder),
    );
  }

  Widget _buildRemoteFolderCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteScannedFolder folder,
  ) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final Color iconColor = isDark ? Colors.white70 : Colors.black54;

    final busy =
        provider.isManagementLoading || provider.scanStatus?.isScanning == true;
    final statusColor = folder.exists ? iconColor : Colors.orangeAccent;
    final title = folder.name.isNotEmpty ? folder.name : folder.path;
    final folderPath = folder.path;
    final expanded = _expandedRemoteDirectories.containsKey(folderPath);
    final loading = _loadingRemoteDirectories.contains(folderPath);

    return LibraryManagementCard(
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>(folderPath),
          leading: Icon(
            folder.exists
                ? Icons.folder_open_outlined
                : Ionicons.warning_outline,
            color: statusColor,
          ),
          iconColor: iconColor,
          collapsedIconColor: iconColor,
          onExpansionChanged: (isExpanded) {
            if (isExpanded != expanded) {
              // Avoid setState during build when ExpansionTile restores its state.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _toggleRemoteDirectory(provider, folderPath);
              });
            }
          },
          initiallyExpanded: expanded,
          title: Text(
            title,
            style: TextStyle(color: textColor, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              folderPath,
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(color: secondaryTextColor, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '移除',
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                constraints: const BoxConstraints(),
                onPressed:
                    busy ? null : () => provider.removeRemoteFolder(folderPath),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: '扫描',
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                constraints: const BoxConstraints(),
                onPressed: busy
                    ? null
                    : () async {
                        await provider.addRemoteFolder(
                          folderPath: folderPath,
                          scan: true,
                          skipPreviouslyMatchedUnwatched: false,
                        );
                        _startScanStatusPolling();
                      },
                icon: Icon(
                  Icons.refresh_rounded,
                  color: iconColor,
                  size: 22,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _accentColor),
                  ),
                ),
            ],
          ),
          children: expanded
              ? _buildRemoteDirectoryChildren(context, provider, folderPath, 1)
              : [],
        ),
      ),
    );
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
      BuildContext context, SharedRemoteHost? host) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Ionicons.folder_open_outline,
              color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            host == null ? '请选择一个共享客户端' : '该客户端尚未扫描任何番剧',
            locale: const Locale('zh', 'CN'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
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
