import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/floating_action_glass_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';

enum _SharedRemoteViewMode { mediaLibrary, libraryManagement }

class SharedRemoteLibraryView extends StatefulWidget {
  const SharedRemoteLibraryView({super.key, this.onPlayEpisode});

  final OnPlayEpisodeCallback? onPlayEpisode;

  @override
  State<SharedRemoteLibraryView> createState() => _SharedRemoteLibraryViewState();
}

class _SharedRemoteLibraryViewState extends State<SharedRemoteLibraryView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _managementScrollController = ScrollController();
  _SharedRemoteViewMode _mode = _SharedRemoteViewMode.mediaLibrary;
  String? _managementLoadedHostId;
  Timer? _scanStatusTimer;
  bool _scanStatusRequestInFlight = false;
  final Map<String, List<SharedRemoteFileEntry>> _expandedRemoteDirectories = {};
  final Set<String> _loadingRemoteDirectories = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scanStatusTimer?.cancel();
    _gridScrollController.dispose();
    _managementScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        final animeSummaries = provider.animeSummaries;
        final hasHosts = provider.hosts.isNotEmpty;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeToggle(context, provider),
                if (_mode == _SharedRemoteViewMode.mediaLibrary &&
                    provider.errorMessage != null)
                  _buildErrorChip(
                    provider.errorMessage!,
                    onClose: provider.clearError,
                  ),
                if (_mode == _SharedRemoteViewMode.libraryManagement &&
                    provider.managementErrorMessage != null)
                  _buildErrorChip(
                    provider.managementErrorMessage!,
                    onClose: provider.clearManagementError,
                  ),
                Expanded(
                  child: _mode == _SharedRemoteViewMode.mediaLibrary
                      ? _buildMediaBody(
                          context,
                          provider,
                          animeSummaries,
                          hasHosts,
                        )
                      : _buildManagementBody(context, provider, hasHosts),
                ),
              ],
            ),
            _buildFloatingButtons(context, provider),
          ],
        );
      },
    );
  }

  Widget _buildMediaBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteAnimeSummary> animeSummaries,
    bool hasHosts,
  ) {
    if (provider.isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isLoading && animeSummaries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (animeSummaries.isEmpty) {
      return _buildEmptyLibraryPlaceholder(context, provider.activeHost);
    }

    return RepaintBoundary(
      child: Scrollbar(
        controller: _gridScrollController,
        radius: const Radius.circular(4),
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 500,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: 140,
          ),
          itemCount: animeSummaries.length,
          itemBuilder: (context, index) {
            final anime = animeSummaries[index];
            return HorizontalAnimeCard(
              key: ValueKey('shared_${anime.animeId}'),
              title: anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
              imageUrl: anime.imageUrl ?? '',
              source: provider.activeHost?.displayName,
              rating: null,
              isOnAir: false,
              onTap: () => _openEpisodeSheet(context, provider, anime),
            );
          },
        ),
      ),
    );
  }

  Widget _buildModeToggle(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final bool isManagement = _mode == _SharedRemoteViewMode.libraryManagement;
    final bool isMedia = _mode == _SharedRemoteViewMode.mediaLibrary;
    final bool hasActiveHost = provider.hasActiveHost;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildModeToggleItem(
                label: '媒体库',
                selected: isMedia,
                onTap: () => _setMode(_SharedRemoteViewMode.mediaLibrary),
              ),
            ),
            Expanded(
              child: _buildModeToggleItem(
                label: '库管理',
                selected: isManagement,
                onTap: () {
                  _setMode(_SharedRemoteViewMode.libraryManagement);
                  if (hasActiveHost) {
                    _ensureManagementLoaded();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggleItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: selected ? Colors.white.withOpacity(0.18) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              locale: const Locale('zh', 'CN'),
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setMode(_SharedRemoteViewMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
    });
    if (mode == _SharedRemoteViewMode.libraryManagement) {
      _ensureManagementLoaded();
    } else {
      _scanStatusTimer?.cancel();
      _scanStatusTimer = null;
    }
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
        if (context.read<SharedRemoteLibraryProvider>().scanStatus?.isScanning ==
            true) {
          _startScanStatusPolling();
        }
      });
      return;
    }

    if (provider.scannedFolders.isEmpty &&
        provider.scanStatus == null &&
        !provider.isManagementLoading &&
        provider.managementErrorMessage == null) {
      provider.refreshManagement(userInitiated: true).then((_) {
        if (!mounted) return;
        if (context.read<SharedRemoteLibraryProvider>().scanStatus?.isScanning ==
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
      if (_mode != _SharedRemoteViewMode.libraryManagement ||
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
    final entries = _expandedRemoteDirectories[directoryPath] ?? const [];
    final indent = EdgeInsets.only(left: 12.0 + depth * 16.0);

    if (entries.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(indent.left, 6, 0, 6),
          child: const Text(
            '（空文件夹）',
            locale: Locale('zh', 'CN'),
            style: TextStyle(color: Colors.white54, fontSize: 12),
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.fromLTRB(indent.left, 0, 8, 0),
              leading: const Icon(Ionicons.folder_outline, color: Colors.white70, size: 18),
              title: Text(
                entryName,
                locale: const Locale('zh', 'CN'),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      expanded ? Ionicons.chevron_down_outline : Ionicons.chevron_forward,
                      color: Colors.white54,
                      size: 16,
                    ),
              onTap: () => _toggleRemoteDirectory(provider, entryPath),
            ),
          ),
        );
        if (expanded) {
          widgets.addAll(_buildRemoteDirectoryChildren(context, provider, entryPath, depth + 1));
        }
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.fromLTRB(indent.left, 0, 8, 0),
            leading: const Icon(Icons.videocam_outlined, color: Colors.white70, size: 18),
            title: Text(
              entryName,
              locale: const Locale('zh', 'CN'),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _buildRemoteFileSubtitle(entry),
            onTap: () => _playRemoteFile(provider, entry),
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

    try {
      final streamUrl = provider.buildRemoteFileStreamUri(entry.path).toString();
      final fallbackTitle = entry.name.isNotEmpty
          ? p.basenameWithoutExtension(entry.name)
          : p.basenameWithoutExtension(entry.path);
      final resolvedAnimeName = (entry.animeName?.trim().isNotEmpty == true)
          ? entry.animeName!.trim()
          : (fallbackTitle.isNotEmpty ? fallbackTitle : p.basenameWithoutExtension(entry.path));
      final resolvedEpisodeTitle = entry.episodeTitle?.trim();

      final item = WatchHistoryItem(
        filePath: streamUrl,
        animeName: resolvedAnimeName,
        episodeTitle: resolvedEpisodeTitle?.isNotEmpty == true ? resolvedEpisodeTitle : null,
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

  Widget? _buildRemoteFileSubtitle(SharedRemoteFileEntry entry) {
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
      return const Text(
        '已识别',
        locale: Locale('zh', 'CN'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return Text(
      parts.join(' - '),
      locale: const Locale('zh', 'CN'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white54, fontSize: 12),
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
            const Icon(Ionicons.warning_outline, color: Colors.orangeAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                locale: const Locale('zh', 'CN'),
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Ionicons.close_outline, color: Colors.orangeAccent, size: 16),
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
  ) {
    if (provider.isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isManagementLoading &&
        provider.scannedFolders.isEmpty &&
        provider.scanStatus == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!provider.hasActiveHost) {
      return _buildEmptyManagementPlaceholder(
        context,
        title: '请选择一个共享客户端',
        subtitle: '先在右下角切换共享客户端，然后再进入库管理。',
      );
    }

    if (provider.managementErrorMessage != null &&
        provider.scannedFolders.isEmpty &&
        provider.scanStatus == null) {
      return _buildEmptyManagementPlaceholder(
        context,
        title: '库管理不可用',
        subtitle: provider.managementErrorMessage!,
      );
    }

    final folders = provider.scannedFolders;
    return ListView(
      controller: _managementScrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _buildScanStatusCard(context, provider),
        const SizedBox(height: 12),
        if (folders.isEmpty)
          _buildEmptyManagementPlaceholder(
            context,
            title: '远程端未添加媒体文件夹',
            subtitle: '可点击右下角按钮添加文件夹并触发扫描。',
          )
        else
          ...folders.map((folder) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildRemoteFolderCard(context, provider, folder),
              )),
      ],
    );
  }

  Widget _buildScanStatusCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final status = provider.scanStatus;
    final isScanning = status?.isScanning == true;
    final title = isScanning ? '远程端正在扫描' : '远程端库管理就绪';
    final message = status?.message ?? '尚未获取扫描状态';
    final progress = (status?.progress ?? 0.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isScanning ? Ionicons.refresh_outline : Ionicons.folder_open_outline,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  locale: const Locale('zh', 'CN'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (provider.isManagementLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (isScanning)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.lightBlueAccent,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            message,
            locale: const Locale('zh', 'CN'),
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            '扫描文件夹：${provider.scannedFolders.length}',
            locale: const Locale('zh', 'CN'),
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteFolderCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteScannedFolder folder,
  ) {
    final busy = provider.isManagementLoading || provider.scanStatus?.isScanning == true;
    final statusColor = folder.exists ? Colors.greenAccent : Colors.orangeAccent;
    final title = folder.name.isNotEmpty ? folder.name : folder.path;
    final folderPath = folder.path;
    final expanded = _expandedRemoteDirectories.containsKey(folderPath);
    final loading = _loadingRemoteDirectories.contains(folderPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _toggleRemoteDirectory(provider, folderPath),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        folder.exists
                            ? Ionicons.folder_outline
                            : Ionicons.warning_outline,
                        color: statusColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          locale: const Locale('zh', 'CN'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (loading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          expanded
                              ? Ionicons.chevron_down_outline
                              : Ionicons.chevron_forward,
                          color: Colors.white54,
                          size: 16,
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: '扫描',
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
                        icon: const Icon(
                          Ionicons.refresh_outline,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: '移除',
                        onPressed:
                            busy ? null : () => provider.removeRemoteFolder(folderPath),
                        icon: const Icon(
                          Ionicons.trash_outline,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    folderPath,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded) ..._buildRemoteDirectoryChildren(context, provider, folderPath, 1),
      ],
    );
  }

  Widget _buildEmptyManagementPlaceholder(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Ionicons.folder_open_outline, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              locale: const Locale('zh', 'CN'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              locale: const Locale('zh', 'CN'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHostsPlaceholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Ionicons.cloud_outline, color: Colors.white38, size: 48),
          SizedBox(height: 12),
          Text(
            '尚未添加共享客户端\n请前往设置 > 远程媒体库 添加',
            locale: Locale('zh', 'CN'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLibraryPlaceholder(BuildContext context, SharedRemoteHost? host) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Ionicons.folder_open_outline, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            host == null
                ? '请选择一个共享客户端'
                : '该客户端尚未扫描任何番剧',
            locale: const Locale('zh', 'CN'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButtons(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    final isManagement = _mode == _SharedRemoteViewMode.libraryManagement;
    final managementBusy =
        provider.isManagementLoading || provider.scanStatus?.isScanning == true;

    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionGlassButton(
            iconData: Ionicons.refresh_outline,
            description: isManagement
                ? '刷新库管理\n同步扫描文件夹与状态'
                : '刷新共享媒体\n重新同步番剧清单',
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
            const SizedBox(height: 16),
            FloatingActionGlassButton(
              iconData: Ionicons.add_circle,
              description: '添加文件夹\n输入远程端路径',
              onPressed: () {
                if (managementBusy) {
                  BlurSnackBar.show(context, '扫描进行中，请稍后操作');
                  return;
                }
                _openAddFolderDialog(context, provider);
              },
            ),
            const SizedBox(height: 16),
            FloatingActionGlassButton(
              iconData: Ionicons.refresh_outline,
              description: '智能刷新\n扫描变化的文件夹',
              onPressed: () async {
                if (managementBusy) {
                  BlurSnackBar.show(context, '扫描进行中，请稍后操作');
                  return;
                }
                await provider.rescanRemoteAll(
                  skipPreviouslyMatchedUnwatched: true,
                );
                _startScanStatusPolling();
              },
            ),
          ],
          const SizedBox(height: 16),
          FloatingActionGlassButton(
            iconData: Ionicons.link_outline,
            description: '切换共享客户端\n从列表中选择远程主机',
            onPressed: () => SharedRemoteHostSelectionSheet.show(context),
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
          hint: '例如：/Volumes/Media 或 D:\\Anime',
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
        sharedEpisodeLoader: () => provider.loadAnimeEpisodes(anime.animeId,
            force: true),
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
