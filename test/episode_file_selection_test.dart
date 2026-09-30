import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/episode_file_candidate.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DetailContext extends Fake implements PlaybackDetailContext {}

WatchHistoryItem _history(String path,
        {int animeId = 10, int episodeId = 100}) =>
    WatchHistoryItem(
      filePath: path,
      animeName: '测试番剧',
      episodeTitle: '第一集',
      animeId: animeId,
      episodeId: episodeId,
      watchProgress: 0.5,
      lastPosition: 600000,
      duration: 1200000,
      lastWatchTime: DateTime(2026, 9, 30),
      thumbnailPath: '/thumbnail.png',
      videoHash: 'hash',
      mediaKey: 'stored:$path',
      isFromScan: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('source descriptions', () {
    test('labels local, WebDAV, SMB and media servers', () {
      for (final entry in {
        '/media/episode.mkv': '本地媒体库',
        'webdav://dav-id/episode.mkv': 'WebDAV',
        'smb://smb-id/episode.mkv': 'SMB',
        'jellyfin://123': 'Jellyfin',
        'emby://456': 'Emby',
        'https://example.test/video.mkv': '网络媒体',
      }.entries) {
        expect(
            EpisodeFileCandidate(_history(entry.key)).sourceLabel, entry.value);
      }
    });

    test('decodes URI paths without changing the playback identity', () {
      const path = 'webdav://dav-id/%E7%AC%AC%E4%B8%80%E9%9B%86%20HD.mkv';
      final candidate = EpisodeFileCandidate(_history(path));
      expect(candidate.displayPath, 'webdav://dav-id/第一集 HD.mkv');
      expect(candidate.history.filePath, path);
      expect(
          EpisodeFileCandidate(_history('/media/literal%20name.mkv'))
              .displayPath,
          '/media/literal%20name.mkv');
    });

    test('SMB proxy query parameters are decoded exactly once', () {
      final path = Uri.http('127.0.0.1:3456', '/smb/stream', {
        'conn': 'server',
        'path': '/番剧/literal%20name.mkv',
      }).toString();
      final candidate = EpisodeFileCandidate(_history(path));
      expect(candidate.sourceLabel, 'SMB');
      expect(candidate.displayPath, 'smb://server/番剧/literal%20name.mkv');
    });

    test('omits credentials and tolerates invalid URL escapes', () {
      final candidate = EpisodeFileCandidate(_history(
          'https://user:secret@example.test/dav/%E7%AC%AC%E4%B8%80%E9%9B%86.mkv'));
      expect(candidate.displayPath, 'https://example.test/dav/第一集.mkv');
      expect(
          EpisodeFileCandidate(_history('webdav://id/bad%GG.mkv')).displayPath,
          'webdav://id/bad%GG.mkv');
    });
  });

  group('playback selection', () {
    late List<WatchHistoryItem> rows;
    late EpisodeFileSelectionService service;
    late PlayableItem requested;
    late PlaybackSession session;
    late PlaybackDetailContext detail;

    setUp(() {
      rows = [
        _history('/media/first.mkv'),
        _history('webdav://dav/first%20HD.mkv'),
        _history('smb://smb/first.mkv'),
      ];
      session = PlaybackSession(
          itemId: 'old',
          streamUrl: 'https://old.test/video',
          isTranscoding: false);
      detail = _DetailContext();
      requested = PlayableItem(
        videoPath: rows.first.filePath,
        historyItem: rows.first,
        actualPlayUrl: 'https://old.test/video',
        playbackSession: session,
        detailContext: detail,
        mediaKey: 'old-source',
      );
      service = EpisodeFileSelectionService(
        loadMatches: (animeId, episodeId) async => rows
            .where(
                (row) => row.animeId == animeId && row.episodeId == episodeId)
            .toList(),
        loadHistory: (path) async {
          for (final row in rows) {
            if (row.filePath == path) return row;
          }
          return null;
        },
        clearMatch: (expected) async {
          final index = rows.indexOf(expected);
          if (index < 0) return false;
          rows[index] = rows[index].withoutMatchInfo();
          return true;
        },
      );
    });

    test('chooses the specified file and discards the previous source session',
        () async {
      final result =
          await service.resolve(requested, choose: (candidates, _) async {
        expect(candidates.map((item) => item.sourceLabel),
            ['本地媒体库', 'WebDAV', 'SMB']);
        return candidates[1];
      });
      expect(result!.videoPath, 'webdav://dav/first%20HD.mkv');
      expect(result.historyItem!.lastPosition, 600000);
      expect(result.actualPlayUrl, isNull);
      expect(result.playbackSession, isNull);
      expect(result.detailContext, isNull);
      expect(result.mediaKey, rows[1].mediaKey);
    });

    test('keeps a resolved session when the original file is selected',
        () async {
      final result = await service.resolve(requested,
          choose: (candidates, _) async => candidates.first);
      expect(result!.actualPlayUrl, requested.actualPlayUrl);
      expect(result.playbackSession, same(session));
      expect(result.detailContext, same(detail));
    });

    test('a single file uses the existing request without opening the chooser',
        () async {
      rows = [rows.first];
      final result = await service.resolve(requested, choose: (_, __) async {
        fail('single-file playback must not open a chooser');
      });
      expect(result, same(requested));
    });

    test('cancel returns no playback request', () async {
      expect(await service.resolve(requested, choose: (_, __) async => null),
          isNull);
    });

    test('unmatching one file retains progress and the remaining choice plays',
        () async {
      final result =
          await service.resolve(requested, choose: (candidates, unmatch) async {
        expect(await unmatch(candidates.first), isTrue);
        return candidates.last;
      });
      expect(rows.first.animeName, isEmpty);
      expect(rows.first.episodeTitle, isNull);
      expect(rows.first.lastPosition, 600000);
      expect(rows.first.mediaKey, 'stored:/media/first.mkv');
      expect(result!.videoPath, rows.last.filePath);
    });

    test('a stale card uses the sole remaining matched file after unmatching',
        () async {
      rows = [rows.first.withoutMatchInfo(), rows[1]];
      final result = await service.resolve(requested, choose: (_, __) async {
        fail('only one active match remains');
      });
      expect(result!.videoPath, rows.last.filePath);
    });

    test('an unlinked selection cannot start playback', () async {
      final result =
          await service.resolve(requested, choose: (candidates, unmatch) async {
        await unmatch(candidates.first);
        return candidates.first;
      });
      expect(result, isNull);
    });

    test('a newer request cancels the old pending selection', () async {
      var cancelled = false;
      final result = await service.resolve(requested,
          isCancelled: () => cancelled,
          choose: (candidates, _) async {
            cancelled = true;
            return candidates.last;
          });
      expect(result, isNull);
    });

    test('aliases of the same file do not create a duplicate choice', () async {
      rows = [
        _history('smb://server/first.mkv'),
        _history(
            'http://127.0.0.1:3456/smb/stream?conn=server&path=%2Ffirst.mkv'),
      ];
      final result = await service.resolve(
          PlayableItem(videoPath: rows.first.filePath, historyItem: rows.first),
          choose: (_, __) async {
        fail('both aliases identify the same file');
      });
      expect(result!.videoPath, rows.first.filePath);
    });

    test('unknown files retain normal playback', () async {
      rows.clear();
      final unknown = PlayableItem(videoPath: '/media/unknown.mkv');
      expect(
          await service.resolve(unknown, choose: (_, __) async {
            fail('unidentified files must not open a chooser');
          }),
          same(unknown));
    });
  });
}
