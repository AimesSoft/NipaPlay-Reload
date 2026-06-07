import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/torrent_magnet_preview.dart';
import 'package:nipaplay/models/torrent_task_scan_summary.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

enum _CupertinoTorrentTaskViewMode { cards, list }

enum _CupertinoTorrentTaskAction { play, toggle, openFolder, forget, delete }

enum _CupertinoTorrentTaskSort { latest, name, progress, status }

const Map<_CupertinoTorrentTaskSort, String> _cupertinoTorrentTaskSortLabels = {
  _CupertinoTorrentTaskSort.latest: '最近添加',
  _CupertinoTorrentTaskSort.name: '名称排序',
  _CupertinoTorrentTaskSort.progress: '进度排序',
  _CupertinoTorrentTaskSort.status: '状态排序',
};

class CupertinoTorrentDownloadPage extends StatefulWidget {
  const CupertinoTorrentDownloadPage({super.key});

  @override
  State<CupertinoTorrentDownloadPage> createState() =>
      _CupertinoTorrentDownloadPageState();
}

class _CupertinoTorrentDownloadPageState
    extends State<CupertinoTorrentDownloadPage> with WidgetsBindingObserver {
  final TorrentDownloadService _service = TorrentDownloadService.instance;
  final TextEditingController _searchController = TextEditingController();
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
  _CupertinoTorrentTaskViewMode _viewMode = _CupertinoTorrentTaskViewMode.cards;
  _CupertinoTorrentTaskSort _sort = _CupertinoTorrentTaskSort.latest;
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
      _showToast('初始化种子下载失败: $e');
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
      _showToast('刷新下载列表失败: $e');
    }
  }

  Future<void> _showAddMagnetDialog() async {
    final downloaderSettings = context.read<DownloaderSettingsProvider>();
    final initialDirectory = _downloadDirectory.isEmpty
        ? await _service.getDownloadDirectory()
        : _downloadDirectory;
    final recentDirectories = await _service.loadRecentDownloadDirectories();
    if (!mounted) return;
    final result =
        await showCupertinoModalPopupWithBottomBar<_CupertinoAddMagnetResult>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => _CupertinoAddMagnetSheet(
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

  void _applySort(_CupertinoTorrentTaskSort sort) {
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
        case _CupertinoTorrentTaskSort.latest:
          return b.id.compareTo(a.id);
        case _CupertinoTorrentTaskSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _CupertinoTorrentTaskSort.progress:
          return b.progress.compareTo(a.progress);
        case _CupertinoTorrentTaskSort.status:
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
      _showToast(successMessage);
    } catch (e) {
      if (!mounted) return;
      _showToast('操作失败: $e');
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
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除任务和文件'),
        content: Text('将从列表移除"${task.name}"，并删除已下载文件。此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _runBusyAction(
      action: () => _service.delete(task.id),
      successMessage: '已删除任务和文件',
    );
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == _CupertinoTorrentTaskViewMode.cards
          ? _CupertinoTorrentTaskViewMode.list
          : _CupertinoTorrentTaskViewMode.cards;
    });
  }

  Future<void> _showSortSheet() async {
    final selected =
        await showCupertinoModalPopupWithBottomBar<_CupertinoTorrentTaskSort>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('排序方式'),
        actions: _cupertinoTorrentTaskSortLabels.entries
            .map(
              (entry) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(sheetContext).pop(entry.key),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (entry.key == _sort) ...[
                      const Icon(CupertinoIcons.check_mark, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(entry.value),
                  ],
                ),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null) {
      _applySort(selected);
    }
  }

  bool _usesMobileTaskActions(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  Future<void> _showTaskActions(TorrentTask task) async {
    final result =
        await showCupertinoModalPopupWithBottomBar<_CupertinoTorrentTaskAction>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(
          task.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (task.finished)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext)
                  .pop(_CupertinoTorrentTaskAction.play),
              child: const Text('播放'),
            ),
          if (!task.finished)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext)
                  .pop(_CupertinoTorrentTaskAction.toggle),
              child: Text(task.isPaused ? '继续下载' : '暂停下载'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext)
                .pop(_CupertinoTorrentTaskAction.openFolder),
            child: const Text('查看文件夹'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext)
                .pop(_CupertinoTorrentTaskAction.forget),
            child: const Text('移除任务'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext)
                .pop(_CupertinoTorrentTaskAction.delete),
            child: const Text('删除任务和文件'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );

    if (!mounted || result == null) return;
    switch (result) {
      case _CupertinoTorrentTaskAction.play:
        await _playTask(task);
        break;
      case _CupertinoTorrentTaskAction.toggle:
        await _toggleTask(task);
        break;
      case _CupertinoTorrentTaskAction.openFolder:
        await _openTaskFolder(task);
        break;
      case _CupertinoTorrentTaskAction.forget:
        await _forgetTask(task);
        break;
      case _CupertinoTorrentTaskAction.delete:
        await _deleteTask(task);
        break;
    }
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
      _showToast('已自动扫描并加入媒体库: ${task.name}');
    } catch (e) {
      if (!mounted || silent) return;
      _showToast('自动扫描下载任务失败: $e');
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
        _showToast('尚未获取到可播放的视频文件，请稍后再试');
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
      _showToast('播放下载任务失败: $e');
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
    return showCupertinoDialog<TorrentTaskFile>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('选择要播放的文件'),
        content: SizedBox(
          height: 200,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                onPressed: () => Navigator.of(ctx).pop(file),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      _CupertinoTorrentTaskCard._formatBytes(file.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showToast(String message) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final visibleTasks = _visibleTasks;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: isZh ? '下载器' : 'Downloader',
        useNativeToolbar: true,
        actions: [
          AdaptiveAppBarAction(
            iosSymbol: _viewMode == _CupertinoTorrentTaskViewMode.cards
                ? 'list.bullet'
                : 'square.grid.2x2',
            icon: _viewMode == _CupertinoTorrentTaskViewMode.cards
                ? CupertinoIcons.list_bullet
                : CupertinoIcons.square_grid_2x2,
            onPressed: _toggleViewMode,
          ),
        ],
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  _buildTopBar(),
                  Container(
                    height: 0.5,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  Expanded(
                    child: visibleTasks.isEmpty
                        ? _buildEmptyState(isFiltered: _tasks.isNotEmpty)
                        : _buildTaskList(visibleTasks),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState({bool isFiltered = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.cloud_download,
            size: 64,
            color: CupertinoColors.systemGrey.resolveFrom(context),
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? '没有匹配的下载任务' : '暂无下载任务',
            style: TextStyle(
              fontSize: 17,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? '换一个关键词或清空搜索后再查看。'
                : '添加 magnet 链接或 .torrent 文件后，任务会显示在这里。',
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.systemGrey2.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final search = CupertinoSearchTextField(
            controller: _searchController,
            onChanged: _updateSearchQuery,
            onSuffixTap: () {
              _searchController.clear();
              _updateSearchQuery('');
            },
            placeholder: '搜索下载任务',
          );
          final sortButton = CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            minimumSize: Size.zero,
            onPressed: _showSortSheet,
            child: Text(
              _cupertinoTorrentTaskSortLabels[_sort] ?? '排序',
              style: const TextStyle(fontSize: 14),
            ),
          );
          final actions = <Widget>[
            CupertinoButton(
              padding: const EdgeInsets.all(7),
              minimumSize: Size.zero,
              onPressed: () => _refreshTasks(),
              child: const Icon(CupertinoIcons.refresh, size: 20),
            ),
            const SizedBox(width: 4),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              color: AppAccentColors.current,
              borderRadius: BorderRadius.circular(8),
              minimumSize: Size.zero,
              onPressed: _isBusy ? null : _showAddMagnetDialog,
              child: const Text('添加', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 4),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              minimumSize: Size.zero,
              onPressed: _isBusy ? null : _pickTorrentFile,
              child: const Text('种子', style: TextStyle(fontSize: 14)),
            ),
          ];

          if (compact) {
            return Column(
              children: [
                search,
                const SizedBox(height: 8),
                Row(
                  children: [
                    sortButton,
                    const SizedBox(width: 4),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: actions),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              sortButton,
              const SizedBox(width: 4),
              ...actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildTaskList(List<TorrentTask> tasks) {
    final useActionSheet = _usesMobileTaskActions(context);
    if (_viewMode == _CupertinoTorrentTaskViewMode.list) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _CupertinoTorrentTaskListItem(
            task: task,
            scanSummary: _scanSummaries[task.autoScanKey],
            isAutoScanning: _autoScanningTaskKeys.contains(task.autoScanKey),
            isAutoScanned:
                _autoScannedCompletedTaskKeys.contains(task.autoScanKey),
            onShowActions: () => _showTaskActions(task),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _CupertinoTorrentTaskCard(
          task: task,
          scanSummary: _scanSummaries[task.autoScanKey],
          isAutoScanning: _autoScanningTaskKeys.contains(task.autoScanKey),
          isAutoScanned:
              _autoScannedCompletedTaskKeys.contains(task.autoScanKey),
          useActionSheet: useActionSheet,
          onShowActions: () => _showTaskActions(task),
          onPlay: () => _playTask(task),
          onToggle: () => _toggleTask(task),
          onOpenFolder: () => _openTaskFolder(task),
          onForget: () => _forgetTask(task),
          onDelete: () => _deleteTask(task),
        );
      },
    );
  }

  Future<void> _openTaskFolder(TorrentTask task) async {
    // On mobile, open folder is limited; just show the path
    _showToast('文件夹: ${task.outputFolder}');
  }
}

class _CupertinoAddMagnetResult {
  const _CupertinoAddMagnetResult({
    required this.magnetUri,
    required this.downloadDirectory,
    required this.createFolderForTask,
  });

  final String magnetUri;
  final String downloadDirectory;
  final bool createFolderForTask;
}

class _CupertinoAddMagnetSheet extends StatefulWidget {
  const _CupertinoAddMagnetSheet({
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
  State<_CupertinoAddMagnetSheet> createState() =>
      _CupertinoAddMagnetSheetState();
}

class _CupertinoAddMagnetSheetState extends State<_CupertinoAddMagnetSheet> {
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
      _preview = null;
      _error = null;
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
      _CupertinoAddMagnetResult(
        magnetUri: magnet,
        downloadDirectory: downloadDirectory,
        createFolderForTask: _createFolderForTask,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    final sheetWidth = math.min(mediaSize.width - 16, 980.0);
    final sheetHeight = mediaSize.width < 600
        ? mediaSize.height * 0.88
        : math.min(mediaSize.height - 80, 680.0);
    final backgroundColor =
        CupertinoColors.secondarySystemBackground.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: CupertinoPopupSurface(
            isSurfacePainted: true,
            child: Container(
              width: sheetWidth,
              height: sheetHeight,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '添加磁力链接',
                          style: TextStyle(
                            color: labelColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(
                          CupertinoIcons.xmark_circle,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final useColumns = constraints.maxWidth >= 760;
                        final settings = _buildSettingsPane();
                        final preview = _buildPreviewPane();
                        if (!useColumns) {
                          return ListView(
                            children: [
                              settings,
                              const SizedBox(height: 16),
                              SizedBox(height: 330, child: preview),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 360, child: settings),
                            const SizedBox(width: 18),
                            Container(width: 0.5, color: separatorColor),
                            const SizedBox(width: 18),
                            Expanded(child: preview),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_error != null)
                        Expanded(
                          child: Text(
                            _error!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CupertinoColors.destructiveRed.resolveFrom(
                                context,
                              ),
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: 10),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        onPressed: _isPreviewing
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 6),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        onPressed: _isPreviewing ? null : _previewMagnet,
                        child: _isPreviewing
                            ? const CupertinoActivityIndicator()
                            : Text(_preview == null ? '预览' : '重新预览'),
                      ),
                      const SizedBox(width: 6),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        color: _preview == null || _isPreviewing
                            ? CupertinoColors.systemGrey4.resolveFrom(context)
                            : AppAccentColors.current,
                        onPressed:
                            _preview == null || _isPreviewing ? null : _confirm,
                        child: const Text('添加任务'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPane() {
    final fillColor = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);

    return ListView(
      children: [
        const _CupertinoDialogLabel('磁力链接'),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: _magnetController,
          minLines: 3,
          maxLines: 5,
          placeholder: 'magnet:?xt=urn:btih:...',
          padding: const EdgeInsets.all(12),
          onChanged: (_) {
            if (_preview != null || _error != null) {
              setState(() {
                _preview = null;
                _error = null;
              });
            }
          },
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 18),
        const _CupertinoDialogLabel('保存到'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(8),
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
                        : labelColor,
                    fontSize: 13,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: _chooseDirectory,
                child: const Icon(CupertinoIcons.folder, size: 20),
              ),
            ],
          ),
        ),
        if (_recentDirectories.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildQuickSelect(),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                '为任务创建独立文件夹',
                style: TextStyle(color: labelColor, fontSize: 14),
              ),
            ),
            CupertinoSwitch(
              value: _createFolderForTask,
              onChanged: (value) {
                setState(() {
                  _createFolderForTask = value;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_preview != null) _buildPreviewSummary(_preview!),
      ],
    );
  }

  Widget _buildQuickSelect() {
    final fillColor = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CupertinoDialogLabel('快速选择'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (var index = 0; index < _recentDirectories.length; index++)
                Column(
                  children: [
                    if (index > 0)
                      Container(height: 0.5, color: separatorColor),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                            minimumSize: Size.zero,
                            alignment: Alignment.centerLeft,
                            onPressed: () =>
                                _selectDirectory(_recentDirectories[index]),
                            child: Row(
                              children: [
                                Icon(
                                  _downloadDirectory ==
                                          _recentDirectories[index]
                                      ? CupertinoIcons.check_mark_circled
                                      : CupertinoIcons.folder,
                                  size: 17,
                                  color: _downloadDirectory ==
                                          _recentDirectories[index]
                                      ? AppAccentColors.current
                                      : secondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _recentDirectories[index],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _downloadDirectory ==
                                              _recentDirectories[index]
                                          ? AppAccentColors.current
                                          : labelColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          minimumSize: Size.zero,
                          onPressed: () => _removeRecentDirectory(
                            _recentDirectories[index],
                          ),
                          child: Icon(
                            CupertinoIcons.xmark_circle,
                            size: 18,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSummary(TorrentMagnetPreview preview) {
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CupertinoColors.label.resolveFrom(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${preview.files.length} 个文件，${_CupertinoTorrentTaskCard._formatBytes(preview.totalSize)}',
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

  Widget _buildPreviewPane() {
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);
    final preview = _preview;

    if (_isPreviewing) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (preview == null) {
      return Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '输入 magnet 链接后预览文件',
            style: TextStyle(color: secondaryColor, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '名称',
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  child: Text(
                    '大小',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: secondaryColor,
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
              separatorBuilder: (_, __) =>
                  Container(height: 0.5, color: separatorColor),
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
                            style: TextStyle(color: labelColor, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 88,
                        child: Text(
                          _CupertinoTorrentTaskCard._formatBytes(file.length),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: secondaryColor,
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

class _CupertinoDialogLabel extends StatelessWidget {
  const _CupertinoDialogLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CupertinoTorrentTaskCard extends StatelessWidget {
  const _CupertinoTorrentTaskCard({
    required this.task,
    required this.scanSummary,
    required this.isAutoScanning,
    required this.isAutoScanned,
    required this.useActionSheet,
    required this.onShowActions,
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
  final bool useActionSheet;
  final VoidCallback onShowActions;
  final VoidCallback onPlay;
  final VoidCallback onToggle;
  final VoidCallback onOpenFolder;
  final VoidCallback onForget;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppAccentColors.current;
    final progress = task.progress;
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.cloud_download,
                color: accentColor,
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
                        color: labelColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.outputFolder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CupertinoStateBadge(task: task),
              if (useActionSheet) ...[
                const SizedBox(width: 4),
                _CupertinoTaskMoreButton(onPressed: onShowActions),
              ],
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: task.hasError
                  ? CupertinoColors.destructiveRed.resolveFrom(context)
                  : AppAccentColors.current,
              backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _metricText(context, '进度', _formatPercent(progress)),
              _metricText(context, '已下载',
                  '${_formatBytes(task.progressBytes)} / ${_formatBytes(task.totalBytes)}'),
              _metricText(context, '下载',
                  '${_formatBytes(task.downloadSpeedBytesPerSecond)}/s'),
              _metricText(context, '上传',
                  '${_formatBytes(task.uploadSpeedBytesPerSecond)}/s'),
              if (isAutoScanning || scanSummary != null || isAutoScanned)
                _CupertinoTaskScanText(
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
              style: TextStyle(
                color: CupertinoColors.destructiveRed.resolveFrom(context),
                fontSize: 12,
              ),
            ),
          ],
          if (!useActionSheet) ...[
            const SizedBox(height: 12),
            _buildActionButtons(context),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final actions = <Widget>[];
    if (task.finished) {
      actions.add(
          _actionButton(context, CupertinoIcons.play_circle, '播放', onPlay));
    } else {
      actions.add(_actionButton(
        context,
        task.isPaused ? CupertinoIcons.play_fill : CupertinoIcons.pause,
        task.isPaused ? '继续' : '暂停',
        onToggle,
      ));
    }
    actions.addAll([
      _actionButton(context, CupertinoIcons.folder, '文件夹', onOpenFolder),
      _actionButton(context, CupertinoIcons.minus_circle, '移除', onForget),
      _actionButton(context, CupertinoIcons.trash, '删除', onDelete),
    ]);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: actions,
    );
  }

  Widget _actionButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _metricText(BuildContext context, String label, String value) {
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: secondaryColor),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    );
  }

  static String _formatPercent(double value) {
    return '${(value * 100).clamp(0, 100).toStringAsFixed(1)}%';
  }

  static String _formatBytes(int bytes) {
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

class _CupertinoTorrentTaskListItem extends StatelessWidget {
  const _CupertinoTorrentTaskListItem({
    required this.task,
    required this.scanSummary,
    required this.isAutoScanning,
    required this.isAutoScanned,
    required this.onShowActions,
  });

  final TorrentTask task;
  final TorrentTaskScanSummary? scanSummary;
  final bool isAutoScanning;
  final bool isAutoScanned;
  final VoidCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppAccentColors.current;
    final progress = task.progress;
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.cloud_download,
                color: accentColor,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.outputFolder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CupertinoStateBadge(task: task),
              const SizedBox(width: 4),
              _CupertinoTaskMoreButton(onPressed: onShowActions),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: task.hasError
                  ? CupertinoColors.destructiveRed.resolveFrom(context)
                  : AppAccentColors.current,
              backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _metricText(context, '进度',
                  _CupertinoTorrentTaskCard._formatPercent(progress)),
              _metricText(context, '已下载',
                  '${_CupertinoTorrentTaskCard._formatBytes(task.progressBytes)} / ${_CupertinoTorrentTaskCard._formatBytes(task.totalBytes)}'),
              _metricText(context, '下载',
                  '${_CupertinoTorrentTaskCard._formatBytes(task.downloadSpeedBytesPerSecond)}/s'),
              _metricText(context, '上传',
                  '${_CupertinoTorrentTaskCard._formatBytes(task.uploadSpeedBytesPerSecond)}/s'),
              if (isAutoScanning || scanSummary != null || isAutoScanned)
                _CupertinoTaskScanText(
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
              style: TextStyle(
                color: CupertinoColors.destructiveRed.resolveFrom(context),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricText(BuildContext context, String label, String value) {
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: secondaryColor),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    );
  }
}

class _CupertinoTaskMoreButton extends StatelessWidget {
  const _CupertinoTaskMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(6),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
    );
  }
}

class _CupertinoTaskScanText extends StatelessWidget {
  const _CupertinoTaskScanText({
    required this.summary,
    required this.isScanning,
    required this.isScanned,
  });

  final TorrentTaskScanSummary? summary;
  final bool isScanning;
  final bool isScanned;

  @override
  Widget build(BuildContext context) {
    final String text = isScanning
        ? '正在扫描入库...'
        : summary?.displayText ?? (isScanned ? '已扫描，正在读取结果...' : '');
    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
        fontSize: 12,
      ),
    );
  }
}

class _CupertinoStateBadge extends StatelessWidget {
  const _CupertinoStateBadge({required this.task});

  final TorrentTask task;

  @override
  Widget build(BuildContext context) {
    final color = task.hasError
        ? CupertinoColors.destructiveRed
        : task.finished
            ? CupertinoColors.activeGreen
            : task.isPaused
                ? CupertinoColors.systemGrey
                : AppAccentColors.current;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
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
