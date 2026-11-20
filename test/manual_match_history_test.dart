import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/manual_match_history.dart';

WatchHistoryItem _history({
  required double progress,
  required bool isFromScan,
}) {
  return WatchHistoryItem(
    filePath: '/anime/old.mkv',
    animeName: '旧标题',
    episodeTitle: '旧集名',
    episodeId: 1,
    animeId: 1,
    watchProgress: progress,
    lastPosition: 1200,
    duration: 1440000,
    lastWatchTime: DateTime(2026, 10, 1),
    thumbnailPath: '/thumbs/old.jpg',
    isFromScan: isFromScan,
    videoHash: 'hash',
  );
}

void main() {
  group('buildManualMatchHistoryItem（#1047）', () {
    test('扫描时没匹配上、没有记录的文件：手动匹配后仍是未播放的扫描项', () {
      final item = buildManualMatchHistoryItem(
        filePath: '/anime/[Group] Show - 03.mkv',
        fileName: '[Group] Show - 03.mkv',
        animeId: 18500,
        episodeId: 185000003,
        animeTitle: '番剧',
        episodeTitle: '第3话',
      );

      expect(item.isFromScan, isTrue);
      expect(item.watchProgress, 0.0);
      expect(item.animeName, '番剧');
      expect(item.episodeId, 185000003);
    });

    test('已有扫描记录：保留扫描标记', () {
      final item = buildManualMatchHistoryItem(
        filePath: '/anime/old.mkv',
        fileName: 'old.mkv',
        animeId: 2,
        episodeId: 20001,
        animeTitle: '新标题',
        episodeTitle: '',
        source: _history(progress: 0, isFromScan: true),
      );

      expect(item.isFromScan, isTrue);
      expect(item.episodeTitle, '旧集名');
    });

    test('播放过的记录：保留进度与非扫描标记', () {
      final item = buildManualMatchHistoryItem(
        filePath: '/anime/old.mkv',
        fileName: 'old.mkv',
        animeId: 2,
        episodeId: 20001,
        animeTitle: '',
        episodeTitle: '新集名',
        source: _history(progress: 0.4, isFromScan: false),
      );

      expect(item.isFromScan, isFalse);
      expect(item.watchProgress, 0.4);
      expect(item.lastPosition, 1200);
      expect(item.thumbnailPath, '/thumbs/old.jpg');
      expect(item.videoHash, 'hash');
      expect(item.animeName, '旧标题');
      expect(item.episodeTitle, '新集名');
    });

    test('没有标题时用文件名兜底', () {
      final item = buildManualMatchHistoryItem(
        filePath: '/anime/Show 05.mkv',
        fileName: 'Show 05.mkv',
        animeId: 3,
        episodeId: 30005,
        animeTitle: '',
        episodeTitle: '',
      );

      expect(item.animeName, 'Show 05');
    });
  });
}
