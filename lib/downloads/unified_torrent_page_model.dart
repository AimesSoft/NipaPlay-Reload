import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/torrent_task_scan_summary.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/models/torrent_magnet_preview.dart';

enum UnifiedTorrentTaskViewMode { cards, list }

enum UnifiedTorrentTaskSort { latest, name, progress, status }

enum UnifiedTorrentTaskAction { play, toggle, openFolder, forget, delete }

class UnifiedTorrentTaskActionViewModel {
  const UnifiedTorrentTaskActionViewModel({
    required this.action,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final UnifiedTorrentTaskAction action;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

class UnifiedTorrentTaskItemViewModel {
  const UnifiedTorrentTaskItemViewModel({
    required this.task,
    required this.scanSummary,
    required this.isAutoScanning,
    required this.isAutoScanned,
    required this.actions,
  });

  final TorrentTask task;
  final TorrentTaskScanSummary? scanSummary;
  final bool isAutoScanning;
  final bool isAutoScanned;
  final List<UnifiedTorrentTaskActionViewModel> actions;

  UnifiedTorrentTaskActionViewModel? action(
    UnifiedTorrentTaskAction action,
  ) {
    for (final candidate in actions) {
      if (candidate.action == action) return candidate;
    }
    return null;
  }

  UnifiedTorrentTaskActionViewModel get primaryAction => task.finished
      ? action(UnifiedTorrentTaskAction.play)!
      : action(UnifiedTorrentTaskAction.toggle)!;

  String? get scanStatusText {
    if (isAutoScanning) return '正在加入媒体库...';
    if (scanSummary?.displayText.isNotEmpty == true) {
      return scanSummary!.displayText;
    }
    if (isAutoScanned) return '已加入媒体库';
    return null;
  }
}

class UnifiedTorrentPageViewModel {
  const UnifiedTorrentPageViewModel({
    required this.isLoading,
    required this.isBusy,
    required this.tasks,
    required this.visibleTasks,
    required this.searchController,
    required this.sort,
    required this.viewMode,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onToggleViewMode,
    required this.onRefresh,
    required this.onAddMagnet,
    required this.onPickTorrent,
  });

  static const String title = '下载';
  static const String searchPlaceholder = '搜索任务、路径、状态或扫描结果';

  final bool isLoading;
  final bool isBusy;
  final List<TorrentTask> tasks;
  final List<UnifiedTorrentTaskItemViewModel> visibleTasks;
  final TextEditingController searchController;
  final UnifiedTorrentTaskSort sort;
  final UnifiedTorrentTaskViewMode viewMode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<UnifiedTorrentTaskSort> onSortChanged;
  final VoidCallback onToggleViewMode;
  final VoidCallback onRefresh;
  final VoidCallback onAddMagnet;
  final VoidCallback onPickTorrent;

  bool get isFiltered => tasks.isNotEmpty && visibleTasks.isEmpty;
  int get activeTaskCount => tasks.where((task) => task.isActive).length;
  int get finishedTaskCount => tasks.where((task) => task.finished).length;
  int get downloadSpeedBytesPerSecond => tasks.fold<int>(
        0,
        (sum, task) => sum + task.downloadSpeedBytesPerSecond,
      );

  String get emptyTitle => isFiltered ? '没有匹配的下载任务' : '暂无下载任务';
  String get emptyDescription =>
      isFiltered ? '换一个关键词或清空搜索后再查看。' : '添加 magnet 链接或 .torrent 文件后，任务会显示在这里。';
}

class TorrentDeleteDialogViewModel {
  const TorrentDeleteDialogViewModel({required this.task});

  final TorrentTask task;

  String get title => '删除任务和文件';
  String get message => '将从列表移除“${task.name}”，并删除已下载文件。此操作不可撤销。';
  String get cancelLabel => '取消';
  String get confirmLabel => '删除';
}

class TorrentPlayableFilesDialogViewModel {
  const TorrentPlayableFilesDialogViewModel({required this.files});

  final List<TorrentTaskFile> files;
  String get title => '选择要播放的文件';
  String get cancelLabel => '取消';
}

class AddTorrentDialogResult {
  const AddTorrentDialogResult({
    required this.magnetUri,
    required this.downloadDirectory,
    required this.createFolderForTask,
  });

  final String magnetUri;
  final String downloadDirectory;
  final bool createFolderForTask;
}

class AddTorrentDialogViewModel {
  const AddTorrentDialogViewModel({
    required this.magnetController,
    required this.downloadDirectory,
    required this.createFolderForTask,
    required this.recentDirectories,
    required this.preview,
    required this.error,
    required this.isPreviewing,
    required this.onMagnetChanged,
    required this.onChooseDirectory,
    required this.onSelectDirectory,
    required this.onRemoveRecentDirectory,
    required this.onCreateFolderChanged,
    required this.onPreview,
    required this.onConfirm,
    required this.onCancel,
  });

  static const String title = '添加磁力链接';
  static const String magnetLabel = '磁力链接';
  static const String magnetPlaceholder = 'magnet:?xt=urn:btih:...';
  static const String directoryLabel = '下载目录';
  static const String createFolderLabel = '为任务创建独立文件夹';

  final TextEditingController magnetController;
  final String downloadDirectory;
  final bool createFolderForTask;
  final List<String> recentDirectories;
  final TorrentMagnetPreview? preview;
  final String? error;
  final bool isPreviewing;
  final ValueChanged<String> onMagnetChanged;
  final VoidCallback onChooseDirectory;
  final ValueChanged<String> onSelectDirectory;
  final ValueChanged<String> onRemoveRecentDirectory;
  final ValueChanged<bool> onCreateFolderChanged;
  final VoidCallback onPreview;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  bool get canConfirm => preview != null && !isPreviewing;
  String get previewLabel => preview == null ? '预览' : '重新预览';
}

const Map<UnifiedTorrentTaskSort, String> unifiedTorrentTaskSortLabels = {
  UnifiedTorrentTaskSort.latest: '最近添加',
  UnifiedTorrentTaskSort.name: '名称排序',
  UnifiedTorrentTaskSort.progress: '进度排序',
  UnifiedTorrentTaskSort.status: '状态排序',
};

String formatTorrentBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100
      ? 0
      : value >= 10
          ? 1
          : 2;
  return '${value.toStringAsFixed(unit == 0 ? 0 : digits)} ${units[unit]}';
}

List<TorrentTask> buildUnifiedTorrentVisibleTasks({
  required Iterable<TorrentTask> tasks,
  required Map<String, TorrentTaskScanSummary> scanSummaries,
  required String query,
  required UnifiedTorrentTaskSort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = normalizedQuery.isEmpty
      ? List<TorrentTask>.from(tasks)
      : tasks.where((task) {
          final scanText = scanSummaries[task.autoScanKey]?.displayText ?? '';
          final haystack = [
            task.name,
            task.outputFolder,
            task.displayState,
            scanText,
          ].join('\n').toLowerCase();
          return haystack.contains(normalizedQuery);
        }).toList();

  filtered.sort((a, b) {
    return switch (sort) {
      UnifiedTorrentTaskSort.latest => b.id.compareTo(a.id),
      UnifiedTorrentTaskSort.name =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      UnifiedTorrentTaskSort.progress => b.progress.compareTo(a.progress),
      UnifiedTorrentTaskSort.status => a.displayState.compareTo(b.displayState),
    };
  });
  return filtered;
}
