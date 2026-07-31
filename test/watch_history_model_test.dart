import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_model.dart';

void main() {
  test('accepts integer-backed numeric values from persisted history', () {
    final item = WatchHistoryItem.fromJson({
      'filePath': '/video.mp4',
      'animeName': 'Anime',
      'episodeId': 1001,
      'animeId': 10,
      'watchProgress': 0,
      'lastPosition': 12.0,
      'duration': 24.0,
      'lastWatchTime': '2026-07-29T00:00:00.000',
    });

    expect(item.watchProgress, 0.0);
    expect(item.lastPosition, 12);
    expect(item.duration, 24);
  });
}
