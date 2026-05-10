import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class CupertinoTorrentDownloadPage extends StatefulWidget {
  const CupertinoTorrentDownloadPage({super.key});

  @override
  State<CupertinoTorrentDownloadPage> createState() =>
      _CupertinoTorrentDownloadPageState();
}

class _CupertinoTorrentDownloadPageState
    extends State<CupertinoTorrentDownloadPage>
    with WidgetsBindingObserver {
  final TorrentDownloadService _service = TorrentDownloadService.instance;
  final TextEditingController _magnetController = TextEditingController();
  Timer? _refreshTimer;
  List<TorrentTask> _tasks = const <TorrentTask>[];
  final Set<String> _autoScannedCompletedTaskKeys = <String>{};
  final Set<String> _autoScanningTaskKeys = <String>{};
  Future<void> _autoScanChain = Future<void>.value();
  String _downloadDirectory = '';
  bool _isLoading = true;
  bool _isBusy = false;
  bool _autoScanRegistryLoaded = false;

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
    _magnetController.dispose();
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
      unawaited(_handleAutoScanCompletedTasks(tasks, silent: silent));
    } catch (e) {
      if (!mounted || silent) return;
      _showToast('刷新下载列表失败: $e');
    }
  }

  Future<void> _chooseDownloadDirectory() async {
    final selected = await FilePickerService().pickDirectory(
      initialDirectory:
          _downloadDirectory.isEmpty ? null : _downloadDirectory,
    );
    if (selected == null || selected.trim().isEmpty) return;

    try {
      await _service.setDownloadDirectory(selected);
      final tasks = await _service.listTasks();
      if (!mounted) return;
      setState(() {
        _downloadDirectory = selected;
        _tasks = tasks;
      });
      _showToast('默认下载位置已更新');
    } catch (e) {
      if (!mounted) return;
      _showToast('更新下载位置失败: $e');
    }
  }

  Future<void> _addMagnet() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty) {
      _showToast('请输入 magnet 链接');
      return;
    }
    if (!magnet.startsWith('magnet:')) {
      _showToast('链接格式不是有效的 magnet 地址');
      return;
    }

    await _runBusyAction(
      action: () => _service.addMagnet(magnet),
      successMessage: '已添加下载任务',
      afterSuccess: () {
        _magnetController.clear();
      },
    );
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

    await _runBusyAction(
      action: () => _service.addTorrentFile(file.path),
      successMessage: '已添加 ${p.basename(file.path)}',
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

  Future<void> _loadAutoScanRegistry() async {
    if (_autoScanRegistryLoaded) return;
    final keys = await _service.loadAutoScannedCompletedTaskKeys();
    _autoScannedCompletedTaskKeys
      ..clear()
      ..addAll(keys);
    _autoScanRegistryLoaded = true;
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
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: isZh ? '下载器' : 'Downloader',
        useNativeToolbar: true,
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
                    child: _tasks.isEmpty
                        ? _buildEmptyState()
                        : _buildTaskList(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
            '暂无下载任务',
            style: TextStyle(
              fontSize: 17,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加 magnet 链接或 .torrent 文件后，任务会显示在这里。',
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
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDirectoryRow(),
              ),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                onPressed: () => _refreshTasks(),
                child: const Icon(CupertinoIcons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: _magnetController,
                  enabled: !_isBusy,
                  onSubmitted: (_) => _addMagnet(),
                  placeholder: 'magnet:?xt=urn:btih:...',
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      CupertinoIcons.link,
                      size: 18,
                      color: CupertinoColors.systemGrey3.resolveFrom(context),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemFill
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: AppAccentColors.current,
                borderRadius: BorderRadius.circular(8),
                onPressed: _isBusy ? null : _addMagnet,
                child: const Text('添加', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 4),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: _isBusy ? null : _pickTorrentFile,
                child:
                    const Text('种子', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryRow() {
    return GestureDetector(
      onTap: _chooseDownloadDirectory,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.folder,
              size: 20,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '默认下载位置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  Text(
                    _downloadDirectory.isEmpty
                        ? '使用应用下载目录'
                        : _downloadDirectory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          CupertinoColors.systemGrey.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: CupertinoColors.systemGrey2.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length,
      itemBuilder: (context, index) =>
          _CupertinoTorrentTaskCard(
        task: _tasks[index],
        onPlay: () => _playTask(_tasks[index]),
        onToggle: () => _toggleTask(_tasks[index]),
        onOpenFolder: () => _openTaskFolder(_tasks[index]),
        onForget: () => _forgetTask(_tasks[index]),
        onDelete: () => _deleteTask(_tasks[index]),
      ),
    );
  }

  Future<void> _openTaskFolder(TorrentTask task) async {
    // On mobile, open folder is limited; just show the path
    _showToast('文件夹: ${task.outputFolder}');
  }
}

class _CupertinoTorrentTaskCard extends StatelessWidget {
  const _CupertinoTorrentTaskCard({
    required this.task,
    required this.onPlay,
    required this.onToggle,
    required this.onOpenFolder,
    required this.onForget,
    required this.onDelete,
  });

  final TorrentTask task;
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
              backgroundColor:
                  CupertinoColors.systemGrey5.resolveFrom(context),
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
          const SizedBox(height: 12),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final actions = <Widget>[];
    if (task.finished) {
      actions.add(_actionButton(context, CupertinoIcons.play_circle, '播放', onPlay));
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
    final secondaryColor =
        CupertinoColors.secondaryLabel.resolveFrom(context);
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
