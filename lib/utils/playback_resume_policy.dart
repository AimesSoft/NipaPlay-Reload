import 'package:nipaplay/models/watch_history_model.dart';

/// Resolve history before falling back to the device's position cache.
/// The database can contain a newer server refresh than the route's initial
/// snapshot. Completed episodes replay at zero; remote zero is authoritative.
int? historyResumePosition({
  required String path,
  WatchHistoryItem? canonicalHistory,
  WatchHistoryItem? initialHistory,
}) {
  final history = canonicalHistory ?? initialHistory;
  if (history?.isCompleted == true) return 0;
  if (canonicalHistory != null &&
      (path.startsWith('jellyfin://') || path.startsWith('emby://'))) {
    return canonicalHistory.resumePosition;
  }
  return null;
}
