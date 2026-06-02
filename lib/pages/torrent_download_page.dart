import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/folder_opener.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_layout.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class TorrentDownloadPage extends StatefulWidget {
  const TorrentDownloadPage({super.key});

  @override
  State<TorrentDownloadPage> createState() => _TorrentDownloadPageState();
}

class _TorrentDownloadPageState extends State<TorrentDownloadPage>
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
      unawaited(_handleAutoScanCompletedTasks(tasks, silent: silent));
    } catch (e) {
      if (!mounted || silent) return;
      BlurSnackBar.show(context, '刷新下载列表失败: $e');
    }
  }

  Future<void> _chooseDownloadDirectory() async {
    final selected = await FilePickerService().pickDirectory(
      initialDirectory: _downloadDirectory.isEmpty ? null : _downloadDirectory,
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
      BlurSnackBar.show(context, '默认下载位置已更新');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '更新下载位置失败: $e');
    }
  }

  Future<void> _addMagnet() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty) {
      BlurSnackBar.show(context, '请输入 magnet 链接');
      return;
    }
    if (!magnet.startsWith('magnet:')) {
      BlurSnackBar.show(context, '链接格式不是有效的 magnet 地址');
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
          child: _tasks.isEmpty
              ? const LibraryManagementEmptyState(
                  icon: Ionicons.cloud_download_outline,
                  title: '暂无下载任务',
                  subtitle: '添加 magnet 链接或 .torrent 文件后，任务会显示在这里。',
                )
              : _buildTaskList(),
        ),
      ],
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DownloadDirectoryRow(
                  directory: _downloadDirectory,
                  onChoose: _chooseDownloadDirectory,
                ),
              ),
              const SizedBox(width: 12),
              _TorrentHoverAction(
                icon: Ionicons.refresh_outline,
                label: '刷新',
                onPressed: () => _refreshTasks(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MagnetInput(
                  controller: _magnetController,
                  enabled: !_isBusy,
                  onSubmitted: (_) => _addMagnet(),
                ),
              ),
              const SizedBox(width: 10),
              _TorrentHoverAction(
                icon: Ionicons.add_circle_outline,
                label: '添加链接',
                onPressed: _isBusy ? null : _addMagnet,
              ),
              const SizedBox(width: 8),
              _TorrentHoverAction(
                icon: Ionicons.document_attach_outline,
                label: '选择种子',
                onPressed: _isBusy ? null : _pickTorrentFile,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return LibraryManagementList<TorrentTask>(
      items: _tasks,
      minItemWidth: 420,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, task) => _TorrentTaskCard(
        task: task,
        onPlay: () => _playTask(task),
        onToggle: () => _toggleTask(task),
        onOpenFolder: () => _openTaskFolder(task),
        onForget: () => _forgetTask(task),
        onDelete: () => _deleteTask(task),
      ),
    );
  }
}

class _DownloadDirectoryRow extends StatelessWidget {
  const _DownloadDirectoryRow({
    required this.directory,
    required this.onChoose,
  });

  final String directory;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor = colorScheme.onSurface;
    final secondaryColor = colorScheme.onSurface.withOpacity(0.7);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(
        children: [
          Icon(
            Ionicons.folder_open_outline,
            color: secondaryColor,
            size: 22,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '默认下载位置',
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  directory.isEmpty ? '使用应用下载目录' : directory,
                  locale: const Locale("zh-Hans", "zh"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondaryColor),
                ),
              ],
            ),
          ),
          _TorrentHoverAction(
            icon: Ionicons.chevron_forward_outline,
            onPressed: onChoose,
            tooltip: '更改默认下载位置',
            padding: const EdgeInsets.all(8),
            iconSize: 20,
            hoverScale: 1.16,
          ),
        ],
      ),
    );
  }
}

class _TorrentHoverAction extends StatefulWidget {
  const _TorrentHoverAction({
    required this.icon,
    required this.onPressed,
    this.label,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.iconSize = 16,
    this.hoverScale = 1.08,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final double hoverScale;

  @override
  State<_TorrentHoverAction> createState() => _TorrentHoverActionState();
}

class _TorrentHoverActionState extends State<_TorrentHoverAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.onSurface.withOpacity(enabled ? 0.72 : 0.36);
    final activeColor =
        enabled && _isHovered ? AppAccentColors.current : baseColor;

    Widget content = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (enabled) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: widget.padding,
          child: AnimatedScale(
            scale: enabled && _isHovered ? widget.hoverScale : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: activeColor,
                  size: widget.iconSize,
                ),
                if (widget.label != null) ...[
                  const SizedBox(width: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: activeColor,
                      fontSize: 14,
                      fontWeight:
                          enabled && _isHovered ? FontWeight.w500 : null,
                    ),
                    child: Text(
                      widget.label!,
                      locale: const Locale("zh-Hans", "zh"),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      content = Tooltip(message: widget.tooltip!, child: content);
    }

    return content;
  }
}

class _MagnetInput extends StatefulWidget {
  const _MagnetInput({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  State<_MagnetInput> createState() => _MagnetInputState();
}

class _MagnetInputState extends State<_MagnetInput> {
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
        enabled: widget.enabled,
        controller: widget.controller,
        focusNode: _focusNode,
        onSubmitted: widget.onSubmitted,
        style: TextStyle(color: textColor, fontSize: 14),
        cursorColor: activeColor,
        decoration: InputDecoration(
          hintText: 'magnet:?xt=urn:btih:...',
          hintStyle: TextStyle(color: hintColor, fontSize: 14),
          prefixIcon: Icon(
            Ionicons.magnet_outline,
            color: _focusNode.hasFocus ? activeColor : hintColor,
            size: 18,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

class _TorrentTaskCard extends StatelessWidget {
  const _TorrentTaskCard({
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
