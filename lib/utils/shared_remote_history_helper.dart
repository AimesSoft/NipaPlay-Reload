import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';

class SharedRemoteHistoryHelper {
  const SharedRemoteHistoryHelper._();

  static String? firstNonEmptyString(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate == null) continue;
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  static String? normalizeHistoryName(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    if (lower == 'stream' || lower == 'unknown') {
      return null;
    }
    return trimmed;
  }

  static bool isSharedRemoteStreamPath(String path) {
    if (path.isEmpty) {
      return false;
    }
    final lowerPath = path.toLowerCase();
    if (!lowerPath.startsWith('http://') && !lowerPath.startsWith('https://')) {
      return false;
    }
    return lowerPath.contains('/api/media/local/share/episodes/') ||
        lowerPath.contains('/api/media/local/share/animes/') ||
        lowerPath.contains('/api/media/local/share/stream');
  }

  static String? extractSharedEpisodeId(String path) {
    final episodesMatch = RegExp(r'/episodes/([^/?]+)/').firstMatch(path);
    if (episodesMatch != null) {
      return episodesMatch.group(1);
    }

    final sharedRemoteMatch = RegExp(r'^sharedremote://[^/]+/([A-Za-z0-9]+)/')
        .firstMatch(path);
    if (sharedRemoteMatch != null) {
      return sharedRemoteMatch.group(1);
    }

    final eidQueryMatch = RegExp(r'[?&]eid=([^&]+)').firstMatch(path);
    if (eidQueryMatch != null) {
      return eidQueryMatch.group(1);
    }

    return null;
  }

  static Future<List<WatchHistoryItem>> loadHistoriesBySharedEpisodeId(
      String? shareEpisodeId) async {
    if (shareEpisodeId == null || shareEpisodeId.isEmpty) {
      return [];
    }
    return WatchHistoryDatabase.instance
        .getHistoriesBySharedEpisodeId(shareEpisodeId);
  }
}
