import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/models/torrent_magnet_preview.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/torrent_task_scan_summary.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/folder_opener.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_layout.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

enum _TorrentTaskViewMode { cards, list }

enum _TorrentTaskSort { latest, name, progress, status }

const Map<_TorrentTaskSort, String> _torrentTaskSortLabels = {
  _TorrentTaskSort.latest: '最近添加',
  _TorrentTaskSort.name: '名称排序',
  _TorrentTaskSort.progress: '进度排序',
  _TorrentTaskSort.status: '状态排序',
};

class TorrentDownloadPage extends StatefulWidget {
  const TorrentDownloadPage({super.key});

  @override
  State<TorrentDownloadPage> createState() => _TorrentDownloadPageState();
}

class _TorrentDownloadPageState extends State<TorrentDownloadPage>
    with WidgetsBindingObserver {
  final TorrentDownloadService _service = TorrentDownloadService.instance;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _sortDropdownKey = GlobalKey();
  Timer? _refreshTimer;
  List<TorrentTask> _tasks = const <TorrentTask>[];
  final Set<String> _autoScannedCompletedTaskKeys = <String>{};
  final Set<String> _autoScanningTaskKeys = <String>{};
  Future<void> _autoScanChain = Future<void>.value();
  final Map<String, TorrentTaskScanSummary> _scanSummaries =
      <String, TorrentTaskScanSummary>{};
  final Set<String> _scanSummaryCheckedKeys = <String>{};
  bool _isLoadingScanSummaries = false;
  List<TorrentTask>? _pendingScanSummaryTasks;
  bool _pendingScanSummaryForce = false;
  String _downloadDirectory = '';
  bool _isLoading = true;
  bool _isBusy = false;
  bool _autoScanRegistryLoaded = false;
  _TorrentTaskViewMode _viewMode = _TorrentTaskViewMode.cards;
  _TorrentTaskSort _sort = _TorrentTaskSort.latest;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop refreshing when app is backgrounded, resume when foregrounded.
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshTasks(silent: true),
    );
  }

  Future<void> _initialize() async {
    try {
      final directory = await _service.getDownloadDirectory();
      await _service.initialize();
      final tasks = await _service.listTasks();
      if (!mounted) return;
      setState(() {
        _downloadDirectory = directory;
        _tasks = tasks;
        _isLoading = false;
      });
      unawaited(_loadScanSummariesForTasks(tasks));
      unawaited(_handleAutoScanCompletedTasks(tasks, silent: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      BlurSnackBar.show(context, '初始化种子下载失败: $e');
    }
  }

  Future<void> _refreshTasks({bool silent = false}) async {
    if (_isBusy && silent) return;
    try {
      final tasks = await _service.listTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
      });
      unawaited(_loadScanSummariesForTasks(tasks));
      unawaited(_handleAutoScanCompletedTasks(tasks, silent: silent));
    } catch (e) {
      if (!mounted || silent) return;
      BlurSnackBar.show(context, '刷新下载列表失败: $e');
    }
  }

  Future<void> _showAddMagnetDialog() async {
    final downloaderSettings = context.read<DownloaderSettingsProvider>();
    final initialDirectory = _downloadDirectory.isEmpty
        ? await _service.getDownloadDirectory()
        : _downloadDirectory;
    final recentDirectories = await _service.loadRecentDownloadDirectories();
    if (!mounted) return;
    final result = await NipaplayWindow.show<_AddMagnetDialogResult>(
      context: context,
      barrierDismissible: false,
      child: _AddMagnetDialog(
        service: _service,
        initialDirectory: initialDirectory,
        initialRecentDirectories: recentDirectories,
        initialCreateFolderForTask: downloaderSettings.createFolderForTask,
      ),
    );
    if (result == null) return;

    await _runBusyAction(
      action: () async {
        await _service.setDownloadDirectory(result.downloadDirectory);
        if (downloaderSettings.createFolderForTask !=
            result.createFolderForTask) {
          await downloaderSettings.setCreateFolderForTask(
            result.createFolderForTask,
          );
        }
        await _service.addMagnet(
          result.magnetUri,
          downloadDirectory: result.downloadDirectory,
          createFolderForTask: result.createFolderForTask,
        );
      },
      successMessage: '已添加下载任务',
      afterSuccess: () {
        if (mounted) {
          setState(() {
            _downloadDirectory = result.downloadDirectory;
          });
        }
      },
    );
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value.trim();
    });
  }

  void _applySort(_TorrentTaskSort sort) {
    if (_sort == sort) return;
    setState(() {
      _sort = sort;
    });
  }

  List<TorrentTask> get _visibleTasks {
    final query = _searchQuery.toLowerCase();
    final filtered = query.isEmpty
        ? List<TorrentTask>.from(_tasks)
        : _tasks.where((task) {
            final scanText =
                _scanSummaries[task.autoScanKey]?.displayText ?? '';
            final haystack = [
              task.name,
              task.outputFolder,
              task.displayState,
              scanText,
            ].join('\n').toLowerCase();
            return haystack.contains(query);
          }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case _TorrentTaskSort.latest:
          return b.id.compareTo(a.id);
        case _TorrentTaskSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _TorrentTaskSort.progress:
          return b.progress.compareTo(a.progress);
        case _TorrentTaskSort.status:
          return a.displayState.compareTo(b.displayState);
      }
    });
    return filtered;
  }

  Future<void> _pickTorrentFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Torrent',
          extensions: ['torrent'],
        ),
      ],
      confirmButtonText: '选择种子文件',
    );
    if (file == null) return;

    final initialDirectory = _downloadDirectory.trim().isEmpty
        ? await _service.getDownloadDirectory()
        : _downloadDirectory;
    if (!mounted) return;
    final selectedDirectory = await FilePickerService().pickDirectory(
      initialDirectory: initialDirectory,
    );
    if (selectedDirectory == null || selectedDirectory.trim().isEmpty) return;
    if (!mounted) return;

    final downloadDirectory = selectedDirectory.trim();
    final downloaderSettings = context.read<DownloaderSettingsProvider>();
    await _runBusyAction(
      action: () async {
        await _service.setDownloadDirectory(downloadDirectory);
        await _service.addTorrentFile(
          file.path,
          downloadDirectory: downloadDirectory,
          createFolderForTask: downloaderSettings.createFolderForTask,
        );
      },
      successMessage: '已添加 ${p.basename(file.path)}',
      afterSuccess: () {
        if (!mounted) return;
        setState(() {
          _downloadDirectory = downloadDirectory;
        });
      },
    );
  }

  Future<void> _runBusyAction({
    required Future<void> Function() action,
    required String successMessage,
    VoidCallback? afterSuccess,
  }) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
    });
    try {
      await action();
      afterSuccess?.call();
      await _refreshTasks(silent: true);
      if (!mounted) return;
      BlurSnackBar.show(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '操作失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _toggleTask(TorrentTask task) async {
    await _runBusyAction(
      action: () =>
          task.isPaused ? _service.resume(task.id) : _service.pause(task.id),
      successMessage: task.isPaused ? '已继续下载' : '已暂停下载',
    );
  }

  Future<void> _forgetTask(TorrentTask task) async {
    await _runBusyAction(
      action: () => _service.forget(task.id),
      successMessage: '已移除下载任务',
    );
  }

  Future<void> _deleteTask(TorrentTask task) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '删除任务和文件',
      content: '将从列表移除“${task.name}”，并删除已下载文件。此操作不可撤销。',
      actions: [
        HoverScaleTextButton(
          child: Text(
            '取消',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: const Text('删除'),
          idleColor: colorScheme.error,
          hoverColor: colorScheme.error,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (confirm != true) return;
    await _runBusyAction(
      action: () => _service.delete(task.id),
      successMessage: '已删除任务和文件',
    );
  }

  Future<void> _openTaskFolder(TorrentTask task) async {
    final ok = await FolderOpener.open(task.outputFolder);
    if (!mounted) return;
    if (!ok) {
      BlurSnackBar.show(context, '打开文件夹失败');
    }
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == _TorrentTaskViewMode.cards
          ? _TorrentTaskViewMode.list
          : _TorrentTaskViewMode.cards;
    });
  }

  Future<void> _loadAutoScanRegistry() async {
    if (_autoScanRegistryLoaded) return;
    final keys = await _service.loadAutoScannedCompletedTaskKeys();
    _autoScannedCompletedTaskKeys
      ..clear()
      ..addAll(keys);
    for (final key in keys) {
      _scanSummaryCheckedKeys.remove(key);
    }
    _autoScanRegistryLoaded = true;
  }

  Future<void> _loadScanSummariesForTasks(
    List<TorrentTask> tasks, {
    bool force = false,
  }) async {
    if (_isLoadingScanSummaries) {
      _pendingScanSummaryTasks = tasks;
      _pendingScanSummaryForce = _pendingScanSummaryForce || force;
      return;
    }

    _isLoadingScanSummaries = true;
    var currentTasks = tasks;
    var currentForce = force;
    try {
      while (true) {
        await _loadScanSummariesForTasksBatch(
          currentTasks,
          force: currentForce,
        );

        final pendingTasks = _pendingScanSummaryTasks;
        if (pendingTasks == null) break;
        currentTasks = pendingTasks;
        currentForce = _pendingScanSummaryForce;
        _pendingScanSummaryTasks = null;
        _pendingScanSummaryForce = false;
      }
    } finally {
      _isLoadingScanSummaries = false;
    }
  }

  Future<void> _loadScanSummariesForTasksBatch(
    List<TorrentTask> tasks, {
    required bool force,
  }) async {
    final targets = tasks.where((task) {
      if (!task.finished || task.outputFolder.trim().isEmpty) return false;
      return force || !_scanSummaryCheckedKeys.contains(task.autoScanKey);
    }).toList(growable: false);
    if (targets.isEmpty) return;

    final summaries = <String, TorrentTaskScanSummary>{};
    for (final task in targets) {
      final summary = await _loadScanSummary(task);
      if (summary != null) {
        summaries[task.autoScanKey] = summary;
      }
    }
    if (!mounted) return;

    final activeKeys = tasks.map((task) => task.autoScanKey).toSet();
    final checkedKeys = targets.map((task) => task.autoScanKey);
    setState(() {
      _scanSummaries
        ..removeWhere((key, _) => !activeKeys.contains(key))
        ..addAll(summaries);
      _scanSummaryCheckedKeys
        ..removeWhere((key) => !activeKeys.contains(key))
        ..addAll(checkedKeys);
    });
  }

  Future<TorrentTaskScanSummary?> _loadScanSummary(TorrentTask task) async {
    final items = await _service.listCompletedFileScanHistoryItems(task);
    final summary = TorrentTaskScanSummary.fromHistoryItems(items);
    if (summary.hasItems ||
        _autoScannedCompletedTaskKeys.contains(task.autoScanKey)) {
      return summary;
    }
    return null;
  }

  Future<void> _handleAutoScanCompletedTasks(
    List<TorrentTask> tasks, {
    required bool silent,
  }) async {
    if (!mounted) return;
    final settings =
        Provider.of<DownloaderSettingsProvider>(context, listen: false);
    if (!settings.isLoaded || !settings.autoScanCompletedTasks) return;

    await _loadAutoScanRegistry();
    if (!mounted) return;
    unawaited(_loadScanSummariesForTasks(tasks));

    for (final task in tasks) {
      if (!task.finished || task.outputFolder.trim().isEmpty) continue;
      final key = task.autoScanKey;
      if (_autoScannedCompletedTaskKeys.contains(key) ||
          _autoScanningTaskKeys.contains(key)) {
        continue;
      }

      _autoScanningTaskKeys.add(key);
      _autoScanChain = _autoScanChain.then(
        (_) => _autoScanCompletedTask(task, key, silent: silent),
      );
      unawaited(_autoScanChain);
    }
  }

  Future<void> _autoScanCompletedTask(
    TorrentTask task,
    String key, {
    required bool silent,
  }) async {
    try {
      final scanService = ServiceProvider.scanService;
      await scanService.addScannedFolder(task.outputFolder);
      while (mounted && scanService.isScanning) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;

      await scanService.startDirectoryScan(
        task.outputFolder,
        skipPreviouslyMatchedUnwatched: true,
      );
      await ServiceProvider.watchHistoryProvider.refresh();
      await _service.markAutoScannedCompletedTask(key);
      _autoScannedCompletedTaskKeys.add(key);
      final summary = await _loadScanSummary(task);
      if (mounted && summary != null) {
        setState(() {
          _scanSummaries[key] = summary;
          _scanSummaryCheckedKeys.add(key);
        });
      }

      if (!mounted || silent) return;
      BlurSnackBar.show(context, '已自动扫描并加入媒体库: ${task.name}');
    } catch (e) {
      if (!mounted || silent) return;
      BlurSnackBar.show(context, '自动扫描下载任务失败: $e');
    } finally {
      _autoScanningTaskKeys.remove(key);
    }
  }

  Future<void> _playTask(TorrentTask task) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
    });

    try {
      final files = await _service.listPlayableFiles(task);
      if (!mounted) return;
      if (files.isEmpty) {
        BlurSnackBar.show(context, '尚未获取到可播放的视频文件，请稍后再试');
        return;
      }

      final selected = files.length == 1
          ? files.first
          : await _showPlayableFilesDialog(files);
      if (selected == null || !mounted) return;

      final source = await _service.getPlaybackSource(task, selected);
      if (!mounted) return;
      await PlaybackService().play(
        PlayableItem(
          videoPath: source.videoPath,
          title: source.historyItem?.animeName ?? selected.fileName,
          subtitle: source.historyItem?.episodeTitle ?? task.name,
          historyItem: source.historyItem,
          actualPlayUrl: source.actualPlayUrl,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '播放下载任务失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<TorrentTaskFile?> _showPlayableFilesDialog(
    List<TorrentTaskFile> files,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlurDialog.show<TorrentTaskFile>(
      context: context,
      title: '选择要播放的文件',
      contentWidget: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: files.length,
          separatorBuilder: (_, __) => Divider(
            color: colorScheme.onSurface.withOpacity(0.08),
            height: 1,
          ),
          itemBuilder: (dialogContext, index) {
            final file = files[index];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Ionicons.play_circle_outline,
                color: AppAccentColors.current,
              ),
              title: Text(
                file.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                _TorrentTaskCard.formatBytes(file.length),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
              ),
              onTap: () => Navigator.of(dialogContext).pop(file),
            );
          },
        ),
      ),
      actions: [
        HoverScaleTextButton(
          child: Text(
            '取消',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleTasks = _visibleTasks;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppAccentColors.current),
      );
    }

    return Column(
      children: [
        _buildTopBar(colorScheme),
        Divider(color: colorScheme.onSurface.withOpacity(0.10), height: 1),
        Expanded(
          child: visibleTasks.isEmpty
              ? LibraryManagementEmptyState(
                  icon: Ionicons.cloud_download_outline,
                  title: _tasks.isEmpty ? '暂无下载任务' : '没有匹配的下载任务',
                  subtitle: _tasks.isEmpty
                      ? '添加 magnet 链接或 .torrent 文件后，任务会显示在这里。'
                      : '换一个关键词或清空搜索后再查看。',
                )
              : _buildTaskList(visibleTasks),
        ),
      ],
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final search = _SearchInput(
            controller: _searchController,
            onChanged: _updateSearchQuery,
            onClear: () => _updateSearchQuery(''),
          );
          final sort = SizedBox(
            width: 142,
            child: BlurDropdown<_TorrentTaskSort>(
              dropdownKey: _sortDropdownKey,
              onItemSelected: _applySort,
              items: _torrentTaskSortLabels.entries
                  .map(
                    (entry) => DropdownMenuItemData<_TorrentTaskSort>(
                      title: entry.value,
                      value: entry.key,
                      isSelected: entry.key == _sort,
                    ),
                  )
                  .toList(),
            ),
          );
          final actions = <Widget>[
            _TorrentHoverAction(
              icon: Ionicons.refresh_outline,
              label: '刷新',
              onPressed: () => _refreshTasks(),
            ),
            const SizedBox(width: 8),
            _TorrentHoverAction(
              icon: _viewMode == _TorrentTaskViewMode.cards
                  ? Ionicons.list_outline
                  : Ionicons.grid_outline,
              tooltip: _viewMode == _TorrentTaskViewMode.cards
                  ? '切换为列表显示'
                  : '切换为三列显示',
              onPressed: _toggleViewMode,
              padding: const EdgeInsets.all(8),
              iconSize: 20,
            ),
            const SizedBox(width: 8),
            _TorrentHoverAction(
              icon: Ionicons.add_circle_outline,
              label: '添加链接',
              onPressed: _isBusy ? null : _showAddMagnetDialog,
            ),
            const SizedBox(width: 8),
            _TorrentHoverAction(
              icon: Ionicons.document_attach_outline,
              label: '选择种子',
              onPressed: _isBusy ? null : _pickTorrentFile,
            ),
          ];

          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 10),
                    sort,
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: actions),
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              sort,
              const SizedBox(width: 10),
              ...actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildTaskList(List<TorrentTask> tasks) {
    if (_viewMode == _TorrentTaskViewMode.list) {
      return _buildCompactTaskList(tasks);
    }

    return LibraryManagementList<TorrentTask>(
      items: tasks,
      minItemWidth: 420,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, task) => _TorrentTaskCard(
        task: task,
        scanSummary: _scanSummaries[task.autoScanKey],
        isAutoScanning: _autoScanningTaskKeys.contains(task.autoScanKey),
        isAutoScanned: _autoScannedCompletedTaskKeys.contains(task.autoScanKey),
        onPlay: () => _playTask(task),
        onToggle: () => _toggleTask(task),
        onOpenFolder: () => _openTaskFolder(task),
        onForget: () => _forgetTask(task),
        onDelete: () => _deleteTask(task),
      ),
    );
  }

  Widget _buildCompactTaskList(List<TorrentTask> tasks) {
    return Scrollbar(
      radius: const Radius.circular(2),
      thickness: 4,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _TorrentTaskListItem(
            task: task,
            scanSummary: _scanSummaries[task.autoScanKey],
            isAutoScanning: _autoScanningTaskKeys.contains(task.autoScanKey),
            isAutoScanned:
                _autoScannedCompletedTaskKeys.contains(task.autoScanKey),
            onPlay: () => _playTask(task),
            onToggle: () => _toggleTask(task),
            onOpenFolder: () => _openTaskFolder(task),
            onForget: () => _forgetTask(task),
            onDelete: () => _deleteTask(task),
          );
        },
      ),
    );
  }
}

class _TorrentHoverAction extends StatelessWidget {
  const _TorrentHoverAction({
    required this.icon,
    required this.onPressed,
    this.label,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.iconSize = 16,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.onSurface.withOpacity(enabled ? 0.72 : 0.36);

    Widget content = HoverScaleTextButton(
      onPressed: onPressed,
      padding: padding,
      hoverScale: 1.08,
      idleColor: baseColor,
      hoverColor: AppAccentColors.current,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label!,
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                fontSize: 14,
                fontFamilyFallback: AppTheme.platformFontFamilyFallback,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
          ],
        ],
      ),
    );

    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }

    return content;
  }
}

class _SearchInput extends StatefulWidget {
  const _SearchInput({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppAccentColors.current;
    final idleBorderColor =
        isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
    final bgColor = isDark ? Colors.white.withOpacity(0.12) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = textColor.withOpacity(0.45);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focusNode.hasFocus ? activeColor : idleBorderColor,
          width: _focusNode.hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: (value) {
          widget.onChanged(value);
          if (mounted) setState(() {});
        },
        style: TextStyle(color: textColor, fontSize: 14),
        cursorColor: activeColor,
        decoration: InputDecoration(
          hintText: '搜索下载任务...',
          hintStyle: TextStyle(color: hintColor, fontSize: 14),
          prefixIcon: Icon(
            Ionicons.search_outline,
            color: _focusNode.hasFocus ? activeColor : hintColor,
            size: 18,
          ),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : Tooltip(
                  message: '清空搜索',
                  child: HoverScaleTextButton(
                    onPressed: () {
                      widget.controller.clear();
                      widget.onClear();
                      setState(() {});
                    },
                    padding: const EdgeInsets.all(8),
                    idleColor: hintColor,
                    child: const Icon(
                      Ionicons.close_circle_outline,
                      size: 18,
                    ),
                  ),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

class _AddMagnetDialogResult {
  const _AddMagnetDialogResult({
    required this.magnetUri,
    required this.downloadDirectory,
    required this.createFolderForTask,
  });

  final String magnetUri;
  final String downloadDirectory;
  final bool createFolderForTask;
}

class _AddMagnetDialog extends StatefulWidget {
  const _AddMagnetDialog({
    required this.service,
    required this.initialDirectory,
    required this.initialRecentDirectories,
    required this.initialCreateFolderForTask,
  });

  final TorrentDownloadService service;
  final String initialDirectory;
  final List<String> initialRecentDirectories;
  final bool initialCreateFolderForTask;

  @override
  State<_AddMagnetDialog> createState() => _AddMagnetDialogState();
}

class _AddMagnetDialogState extends State<_AddMagnetDialog> {
  late final TextEditingController _magnetController;
  late String _downloadDirectory;
  late bool _createFolderForTask;
  late List<String> _recentDirectories;
  TorrentMagnetPreview? _preview;
  String? _error;
  bool _isPreviewing = false;
  int _previewRequestId = 0;

  @override
  void initState() {
    super.initState();
    _magnetController = TextEditingController();
    _downloadDirectory = widget.initialDirectory;
    _createFolderForTask = widget.initialCreateFolderForTask;
    _recentDirectories = List<String>.from(widget.initialRecentDirectories);
  }

  @override
  void dispose() {
    _magnetController.dispose();
    super.dispose();
  }

  Future<void> _chooseDirectory() async {
    final selected = await FilePickerService().pickDirectory(
      initialDirectory:
          _downloadDirectory.trim().isEmpty ? null : _downloadDirectory,
    );
    if (selected == null || selected.trim().isEmpty) return;
    await widget.service.rememberRecentDownloadDirectory(selected.trim());
    _selectDirectory(selected.trim());
  }

  void _selectDirectory(String directory) {
    setState(() {
      _downloadDirectory = directory;
      _recentDirectories = [
        directory,
        ..._recentDirectories.where((value) => value != directory),
      ].take(8).toList(growable: false);
      _preview = null;
      _error = null;
    });
  }

  Future<void> _removeRecentDirectory(String directory) async {
    await widget.service.removeRecentDownloadDirectory(directory);
    if (!mounted) return;
    setState(() {
      _recentDirectories.remove(directory);
    });
  }

  Future<void> _previewMagnet() async {
    final magnet = _magnetController.text.trim();
    final downloadDirectory = _downloadDirectory.trim();
    if (magnet.isEmpty) {
      setState(() => _error = '请输入 magnet 链接');
      return;
    }
    if (!magnet.startsWith('magnet:')) {
      setState(() => _error = '链接格式不是有效的 magnet 地址');
      return;
    }
    if (downloadDirectory.isEmpty) {
      setState(() => _error = '请选择下载位置');
      return;
    }

    final requestId = ++_previewRequestId;
    setState(() {
      _isPreviewing = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await widget.service.previewMagnet(
        magnet,
        downloadDirectory: downloadDirectory,
      );
      if (!mounted) return;
      if (!_isCurrentPreviewRequest(requestId, magnet, downloadDirectory)) {
        return;
      }
      setState(() {
        _preview = preview;
      });
    } catch (error) {
      if (!mounted) return;
      if (!_isCurrentPreviewRequest(requestId, magnet, downloadDirectory)) {
        return;
      }
      setState(() {
        _error = '解析失败: $error';
      });
    } finally {
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _isPreviewing = false;
        });
      }
    }
  }

  bool _isCurrentPreviewRequest(
    int requestId,
    String magnet,
    String downloadDirectory,
  ) {
    return requestId == _previewRequestId &&
        _magnetController.text.trim() == magnet &&
        _downloadDirectory.trim() == downloadDirectory;
  }

  void _confirm() {
    final magnet = _magnetController.text.trim();
    final downloadDirectory = _downloadDirectory.trim();
    if (_preview == null || magnet.isEmpty || downloadDirectory.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      _AddMagnetDialogResult(
        magnetUri: magnet,
        downloadDirectory: downloadDirectory,
        createFolderForTask: _createFolderForTask,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return NipaplayWindowScaffold(
      maxWidth: 980,
      maxHeightFactor: 0.88,
      onClose: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '添加磁力链接',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useColumns = constraints.maxWidth >= 760;
                  final settings = _buildDialogSettings(colorScheme);
                  final files = _buildPreviewPane(colorScheme);
                  if (!useColumns) {
                    return ListView(
                      children: [
                        settings,
                        const SizedBox(height: 16),
                        SizedBox(height: 360, child: files),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 360, child: settings),
                      const SizedBox(width: 18),
                      VerticalDivider(
                        color: colorScheme.onSurface.withValues(alpha: 0.10),
                        width: 1,
                      ),
                      const SizedBox(width: 18),
                      Expanded(child: files),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_error != null)
                  Expanded(
                    child: Text(
                      _error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 12),
                HoverScaleTextButton(
                  text: '取消',
                  onPressed:
                      _isPreviewing ? null : () => Navigator.of(context).pop(),
                  idleColor: colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 8),
                HoverScaleTextButton(
                  onPressed: _isPreviewing ? null : _previewMagnet,
                  idleColor: colorScheme.onSurface.withValues(alpha: 0.78),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPreviewing)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Ionicons.search_outline, size: 16),
                      const SizedBox(width: 5),
                      Text(_preview == null ? '预览' : '重新预览'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                HoverScaleTextButton(
                  onPressed:
                      _preview == null || _isPreviewing ? null : _confirm,
                  idleColor: colorScheme.onSurface.withValues(alpha: 0.88),
                  hoverColor: AppAccentColors.current,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Ionicons.add_circle_outline, size: 16),
                      SizedBox(width: 5),
                      Text('添加任务'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogSettings(ColorScheme colorScheme) {
    final secondaryColor = colorScheme.onSurface.withOpacity(0.55);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DialogFieldLabel('磁力链接'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: colorScheme.onSurface.withOpacity(0.12)),
            ),
            child: TextField(
              controller: _magnetController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) {
                if (_preview != null || _error != null) {
                  setState(() {
                    _preview = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _previewMagnet(),
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
              cursorColor: AppAccentColors.current,
              decoration: InputDecoration(
                hintText: 'magnet:?xt=urn:btih:...',
                hintStyle: TextStyle(color: secondaryColor),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _DialogFieldLabel('保存到'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: colorScheme.onSurface.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _downloadDirectory.isEmpty ? '请选择下载位置' : _downloadDirectory,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _downloadDirectory.isEmpty
                          ? secondaryColor
                          : colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: '选择下载位置',
                  child: HoverScaleTextButton(
                    onPressed: _chooseDirectory,
                    padding: const EdgeInsets.all(6),
                    child: const Icon(Ionicons.folder_open_outline, size: 20),
                  ),
                ),
              ],
            ),
          ),
          if (_recentDirectories.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildQuickSelect(colorScheme),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '为任务创建独立文件夹',
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ),
              FluentSettingsSwitch(
                value: _createFolderForTask,
                onChanged: (value) {
                  setState(() {
                    _createFolderForTask = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_preview != null) _buildPreviewSummary(colorScheme, _preview!),
        ],
      ),
    );
  }

  Widget _buildQuickSelect(ColorScheme colorScheme) {
    final secondaryColor = colorScheme.onSurface.withOpacity(0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DialogFieldLabel('快速选择'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.onSurface.withOpacity(0.10)),
          ),
          child: Column(
            children: [
              for (var index = 0; index < _recentDirectories.length; index++)
                Column(
                  children: [
                    if (index > 0)
                      Divider(
                        height: 1,
                        color: colorScheme.onSurface.withOpacity(0.08),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: HoverScaleTextButton(
                              onPressed: () =>
                                  _selectDirectory(_recentDirectories[index]),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              hoverScale: 1.0,
                              idleColor: _downloadDirectory ==
                                      _recentDirectories[index]
                                  ? AppAccentColors.current
                                  : colorScheme.onSurface.withOpacity(0.72),
                              child: Row(
                                children: [
                                  Icon(
                                    _downloadDirectory ==
                                            _recentDirectories[index]
                                        ? Ionicons.checkmark_circle_outline
                                        : Ionicons.folder_open_outline,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _recentDirectories[index],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Tooltip(
                            message: '从快速选择移除',
                            child: HoverScaleTextButton(
                              onPressed: () => _removeRecentDirectory(
                                _recentDirectories[index],
                              ),
                              padding: const EdgeInsets.all(7),
                              idleColor: secondaryColor,
                              child: const Icon(
                                Ionicons.close_circle_outline,
                                size: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSummary(
    ColorScheme colorScheme,
    TorrentMagnetPreview preview,
  ) {
    final secondaryColor = colorScheme.onSurface.withOpacity(0.55);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.onSurface.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${preview.files.length} 个文件，${_TorrentTaskCard.formatBytes(preview.totalSize)}',
            style: TextStyle(color: secondaryColor, fontSize: 12),
          ),
          if (preview.suggestedFolderName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '文件夹：${preview.suggestedFolderName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondaryColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewPane(ColorScheme colorScheme) {
    final preview = _preview;
    if (_isPreviewing) {
      return Center(
        child: CircularProgressIndicator(color: AppAccentColors.current),
      );
    }
    if (preview == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.onSurface.withOpacity(0.10)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '输入 magnet 链接后预览文件',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.55),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.onSurface.withOpacity(0.10)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '名称',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: Text(
                    '大小',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: preview.files.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: colorScheme.onSurface.withOpacity(0.08),
              ),
              itemBuilder: (context, index) {
                final file = preview.files[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            file.path,
                            softWrap: false,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: Text(
                          _TorrentTaskCard.formatBytes(file.length),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.55),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogFieldLabel extends StatelessWidget {
  const _DialogFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      locale: const Locale("zh-Hans", "zh"),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _TorrentTaskCard extends StatelessWidget {
  const _TorrentTaskCard({
    required this.task,
    required this.scanSummary,
    required this.isAutoScanning,
    required this.isAutoScanned,
    required this.onPlay,
    required this.onToggle,
    required this.onOpenFolder,
    required this.onForget,
    required this.onDelete,
  });

  final TorrentTask task;
  final TorrentTaskScanSummary? scanSummary;
  final bool isAutoScanning;
  final bool isAutoScanned;
  final VoidCallback onPlay;
  final VoidCallback onToggle;
  final VoidCallback onOpenFolder;
  final VoidCallback onForget;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    final progress = task.progress;

    return LibraryManagementCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Ionicons.cloud_download_outline,
                  color: AppAccentColors.current,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.outputFolder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StateBadge(task: task),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color:
                    task.hasError ? colorScheme.error : AppAccentColors.current,
                backgroundColor: onSurface.withOpacity(0.10),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _MetricText(label: '进度', value: _formatPercent(progress)),
                _MetricText(
                  label: '已下载',
                  value:
                      '${formatBytes(task.progressBytes)} / ${formatBytes(task.totalBytes)}',
                ),
                _MetricText(
                  label: '下载',
                  value: '${formatBytes(task.downloadSpeedBytesPerSecond)}/s',
                ),
                _MetricText(
                  label: '上传',
                  value: '${formatBytes(task.uploadSpeedBytesPerSecond)}/s',
                ),
                if (isAutoScanning || scanSummary != null || isAutoScanned)
                  _TorrentTaskScanText(
                    summary: scanSummary,
                    isScanning: isAutoScanning,
                    isScanned: isAutoScanned,
                  ),
              ],
            ),
            if (task.error?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                task.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (task.finished)
                  _TorrentHoverAction(
                    icon: Ionicons.play_circle_outline,
                    label: '播放',
                    onPressed: onPlay,
                  ),
                if (!task.finished) ...[
                  _TorrentHoverAction(
                    icon: task.isPaused
                        ? Ionicons.play_outline
                        : Ionicons.pause_outline,
                    label: task.isPaused ? '继续' : '暂停',
                    onPressed: onToggle,
                  ),
                ],
                _TorrentHoverAction(
                  icon: Ionicons.folder_open_outline,
                  label: '打开文件夹',
                  onPressed: onOpenFolder,
                ),
                _TorrentHoverAction(
                  icon: Ionicons.remove_circle_outline,
                  label: '移除',
                  onPressed: onForget,
                ),
                _TorrentHoverAction(
                  icon: Ionicons.trash_outline,
                  label: '删文件',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPercent(double value) {
    return '${(value * 100).clamp(0, 100).toStringAsFixed(1)}%';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0
        ? 0
        : value >= 10
            ? 1
            : 2;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

class _TorrentTaskListItem extends StatelessWidget {
  const _TorrentTaskListItem({
    required this.task,
    required this.scanSummary,
    required this.isAutoScanning,
    required this.isAutoScanned,
    required this.onPlay,
    required this.onToggle,
    required this.onOpenFolder,
    required this.onForget,
    required this.onDelete,
  });

  final TorrentTask task;
  final TorrentTaskScanSummary? scanSummary;
  final bool isAutoScanning;
  final bool isAutoScanned;
  final VoidCallback onPlay;
  final VoidCallback onToggle;
  final VoidCallback onOpenFolder;
  final VoidCallback onForget;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    final progress = task.progress;

    return LibraryManagementCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final actions = _buildActions();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Ionicons.cloud_download_outline,
                      color: AppAccentColors.current,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.name,
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            task.outputFolder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onSurface.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StateBadge(task: task),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: task.hasError
                        ? colorScheme.error
                        : AppAccentColors.current,
                    backgroundColor: onSurface.withValues(alpha: 0.10),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _MetricText(
                      label: '进度',
                      value: _TorrentTaskCard._formatPercent(progress),
                    ),
                    _MetricText(
                      label: '已下载',
                      value:
                          '${_TorrentTaskCard.formatBytes(task.progressBytes)} / ${_TorrentTaskCard.formatBytes(task.totalBytes)}',
                    ),
                    _MetricText(
                      label: '下载',
                      value:
                          '${_TorrentTaskCard.formatBytes(task.downloadSpeedBytesPerSecond)}/s',
                    ),
                    _MetricText(
                      label: '上传',
                      value:
                          '${_TorrentTaskCard.formatBytes(task.uploadSpeedBytesPerSecond)}/s',
                    ),
                    if (isAutoScanning || scanSummary != null || isAutoScanned)
                      _TorrentTaskScanText(
                        summary: scanSummary,
                        isScanning: isAutoScanning,
                        isScanned: isAutoScanned,
                      ),
                  ],
                ),
                if (task.error?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.error, fontSize: 12),
                  ),
                ],
                if (compact) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: actions,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    return [
      if (task.finished)
        _TorrentHoverAction(
          icon: Ionicons.play_circle_outline,
          tooltip: '播放',
          onPressed: onPlay,
          padding: const EdgeInsets.all(8),
          iconSize: 18,
        ),
      if (!task.finished)
        _TorrentHoverAction(
          icon: task.isPaused ? Ionicons.play_outline : Ionicons.pause_outline,
          tooltip: task.isPaused ? '继续' : '暂停',
          onPressed: onToggle,
          padding: const EdgeInsets.all(8),
          iconSize: 18,
        ),
      _TorrentHoverAction(
        icon: Ionicons.folder_open_outline,
        tooltip: '打开文件夹',
        onPressed: onOpenFolder,
        padding: const EdgeInsets.all(8),
        iconSize: 18,
      ),
      _TorrentHoverAction(
        icon: Ionicons.remove_circle_outline,
        tooltip: '移除',
        onPressed: onForget,
        padding: const EdgeInsets.all(8),
        iconSize: 18,
      ),
      _TorrentHoverAction(
        icon: Ionicons.trash_outline,
        tooltip: '删除任务和文件',
        onPressed: onDelete,
        padding: const EdgeInsets.all(8),
        iconSize: 18,
      ),
    ];
  }
}

class _TorrentTaskScanText extends StatelessWidget {
  const _TorrentTaskScanText({
    required this.summary,
    required this.isScanning,
    required this.isScanned,
  });

  final TorrentTaskScanSummary? summary;
  final bool isScanning;
  final bool isScanned;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String text = isScanning
        ? '正在扫描入库...'
        : summary?.displayText ?? (isScanned ? '已扫描，正在读取结果...' : '');
    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colorScheme.onSurface.withValues(alpha: 0.55),
        fontSize: 12,
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.task});

  final TorrentTask task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = task.hasError
        ? colorScheme.error
        : task.finished
            ? Colors.green
            : task.isPaused
                ? colorScheme.onSurface.withOpacity(0.55)
                : AppAccentColors.current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35), width: 0.5),
      ),
      child: Text(
        task.displayState,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeTextStyle = Theme.of(context).textTheme.bodySmall;
    final baseStyle = (themeTextStyle ?? const TextStyle()).copyWith(
      fontSize: 12,
      fontFamilyFallback: AppTheme.platformFontFamilyFallback,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: '$label ',
            style: baseStyle.copyWith(
              color: colorScheme.onSurface.withOpacity(0.50),
            ),
          ),
          TextSpan(
            text: value,
            style: baseStyle.copyWith(
              color: colorScheme.onSurface.withOpacity(0.82),
            ),
          ),
        ],
      ),
      style: baseStyle,
    );
  }
}
