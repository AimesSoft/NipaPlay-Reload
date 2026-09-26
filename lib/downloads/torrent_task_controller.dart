import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/torrent_task.dart';

/// Serializes snapshots and locks individual tasks until their changed state has
/// been read back. A slow add or another task never blocks list polling.
class TorrentTaskController extends ChangeNotifier {
  TorrentTaskController({required this.loadTasks});

  final Future<List<TorrentTask>> Function() loadTasks;
  List<TorrentTask> _tasks = const [];
  List<TorrentTask> get tasks => _tasks;
  final Set<int> _busyIds = {};
  bool isBusy(int id) => _busyIds.contains(id);
  Future<void>? _refresh;
  bool _refreshAgain = false;
  bool _disposed = false;

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    _refreshAgain = true;
    return _refresh ??= _drainRefresh().whenComplete(() => _refresh = null);
  }

  Future<void> _drainRefresh() async {
    do {
      _refreshAgain = false;
      final tasks = await loadTasks();
      if (_disposed) return;
      _tasks = List.unmodifiable(tasks);
      notifyListeners();
    } while (_refreshAgain);
  }

  Future<bool> run(int id, Future<void> Function() action) async {
    if (_disposed || !_busyIds.add(id)) return false;
    notifyListeners();
    try {
      await action();
      // If a pre-action poll was already in flight, refresh() schedules another
      // read before releasing this task's controls.
      await refresh();
      return true;
    } finally {
      _busyIds.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
