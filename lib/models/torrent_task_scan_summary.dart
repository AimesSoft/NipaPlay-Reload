import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;

class TorrentTaskScanSummary {
  const TorrentTaskScanSummary({
    required this.itemCount,
    required this.labels,
  });

  final int itemCount;
  final List<String> labels;

  bool get hasItems => itemCount > 0;

  String get displayText {
    if (!hasItems) return '未匹配到番剧信息';
    if (labels.isEmpty) return '';
    final suffix = itemCount > labels.length ? ' 等' : '';
    return '${labels.join('、')}$suffix';
  }

  factory TorrentTaskScanSummary.fromHistoryItems(
    Iterable<WatchHistoryItem> items,
  ) {
    final matchedItems = items
        .where(
          _hasScanInfo,
        )
        .toList(growable: false);
    final labels = <String>[];
    final seen = <String>{};

    for (final item in matchedItems) {
      final label = _formatLabel(item);
      if (label.isEmpty || !seen.add(label)) continue;
      labels.add(label);
      if (labels.length >= 3) break;
    }

    return TorrentTaskScanSummary(
      itemCount: matchedItems.length,
      labels: labels,
    );
  }

  static String _formatLabel(WatchHistoryItem item) {
    final animeName = item.animeName.trim();
    final episodeTitle = item.episodeTitle?.trim() ?? '';
    if (animeName.isEmpty) return episodeTitle;
    if (episodeTitle.isEmpty) return animeName;
    return '$animeName - $episodeTitle';
  }

  static bool _hasScanInfo(WatchHistoryItem item) {
    final animeName = item.animeName.trim();
    final fileName = p.basename(item.filePath).trim();
    final baseName = p.basenameWithoutExtension(item.filePath).trim();
    return item.animeId != null ||
        item.episodeId != null ||
        (animeName.isNotEmpty &&
            animeName != fileName &&
            animeName != baseName);
  }
}
