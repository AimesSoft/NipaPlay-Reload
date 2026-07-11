import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/torrent_task_scan_summary.dart';

enum UnifiedTorrentTaskViewMode { cards, list }

enum UnifiedTorrentTaskSort { latest, name, progress, status }

const Map<UnifiedTorrentTaskSort, String> unifiedTorrentTaskSortLabels = {
  UnifiedTorrentTaskSort.latest: '最近添加',
  UnifiedTorrentTaskSort.name: '名称排序',
  UnifiedTorrentTaskSort.progress: '进度排序',
  UnifiedTorrentTaskSort.status: '状态排序',
};

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
