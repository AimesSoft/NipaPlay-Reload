import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/models/watch_history_model.dart';

bool eligibleClassicHistory(Map<String, Object?> row) {
  final item = WatchHistoryItem.fromJson(row);
  return UnifiedMediaLibrarySource.values
      .any((source) => mediaLibraryItemMatchesSource(item, source));
}
