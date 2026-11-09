import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/media_library_scope.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/models/episode_file_candidate.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchHistoryItem history(String path, {int episode = 100}) => WatchHistoryItem(
      filePath: path,
      animeId: 10,
      episodeId: episode,
      animeName: 'Anime',
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const webdav = MediaLibraryScope(MediaLibraryScopeKind.webdav);
  const local = MediaLibraryScope(MediaLibraryScopeKind.local);

  test(
      'source classes aggregate DAV connections but exclude unrelated protocols',
      () {
    for (final path in [
      'webdav://a/01.mkv',
      'webdav://b/01.mkv',
      'http://127.0.0.1:33222/webdav/stream?conn=a&path=%2F01.mkv'
    ]) {
      expect(webdav.containsPath(path), isTrue);
    }
    for (final path in [
      'smb://a/01.mkv',
      '/01.mkv',
      'jellyfin://a',
      'emby://a',
      'http://nas/api/media/local/share/episodes/a/stream',
      'http://nas/api/media/local/manage/stream?path=/dav/a',
      'http://nas/api/v1/stream/a'
    ]) {
      expect(webdav.containsPath(path), isFalse, reason: path);
    }
    for (final path in [
      '/media/01.mkv',
      r'C:\Anime\01.mkv',
      'file:///media/01.mkv',
      'content://com.android.providers.media.documents/document/video%3A42'
    ]) {
      expect(local.containsPath(path), isTrue);
    }
    expect(local.containsPath('http://nas/video.mkv'), isFalse);
    expect(local.containsPath('dandanplay://a'), isFalse);
    const shared = MediaLibraryScope(MediaLibraryScopeKind.sharedRemote,
        hostOrigin: 'http://nas:7768');
    expect(
        shared.containsPath(
            'http://nas:7768/api/media/local/share/episodes/a/stream'),
        isTrue);
    expect(
        shared.containsPath(
            'http://other:7768/api/media/local/share/episodes/a/stream'),
        isFalse);
    expect(
        shared.containsPath(
            'http://nas:7769/api/media/local/share/episodes/a/stream'),
        isFalse);
  });

  test(
      'chooser contains only DAV versions across connections and keeps scope after switching',
      () async {
    final rows = [
      history('/local.mkv'),
      history('webdav://a/01.mkv'),
      history('webdav://b/01.mkv'),
      history('smb://c/01.mkv')
    ];
    final service = EpisodeFileSelectionService(
      loadHistory: (_) async => rows[1],
      loadMatches: (_, __) async => rows,
    );
    final item = PlayableItem(
        videoPath: rows[1].filePath,
        historyItem: rows[1],
        mediaLibraryScope: webdav,
        actualPlayUrl: 'http://old');
    final result = await service.resolve(item, choose: (candidates, _) async {
      expect(candidates.map((c) => c.history.filePath),
          [rows[1].filePath, rows[2].filePath]);
      return candidates.last;
    });
    expect(result!.videoPath, rows[2].filePath);
    expect(result.mediaLibraryScope, same(webdav));
    expect(result.actualPlayUrl, isNull);
    final next = PlayableItem(
        videoPath: 'smb://c/02.mkv',
        animeId: 10,
        episodeId: 100,
        mediaLibraryScope: result.mediaLibraryScope);
    final nextResult = await service.resolve(next,
        choose: (candidates, _) async => candidates.first);
    expect(nextResult!.videoPath, rows[1].filePath);
  });

  test(
      'one in-scope version plays directly; unrestricted entry still lists every source',
      () async {
    final rows = [
      history('/local.mkv'),
      history('webdav://a/01.mkv'),
      history('smb://c/01.mkv')
    ];
    final service = EpisodeFileSelectionService(
        loadHistory: (_) async => rows.first,
        loadMatches: (_, __) async => rows);
    final request =
        PlayableItem(videoPath: rows.first.filePath, historyItem: rows.first);
    final scoped = await service.resolve(request.withMediaLibraryScope(webdav),
        choose: (_, __) async => throw StateError('must not show chooser'));
    expect(scoped!.videoPath, rows[1].filePath);
    await service.resolve(request, choose: (candidates, _) async {
      expect(candidates, hasLength(3));
      return null;
    });
  });

  test('missing or cleared scoped episode never falls back to another library',
      () async {
    final smb = history('smb://a/01.mkv');
    var unavailable = false;
    final service = EpisodeFileSelectionService(
        loadHistory: (_) async => smb, loadMatches: (_, __) async => [smb]);
    final result = await service.resolve(
        PlayableItem(
            videoPath: smb.filePath,
            historyItem: smb,
            mediaLibraryScope: webdav),
        onUnavailable: () => unavailable = true,
        choose: (_, __) async => throw StateError('no in-scope file'));
    expect(result, isNull);
    expect(unavailable, isTrue);
    final cleared = history('webdav://a/01.mkv').withoutMatchInfo();
    final stale = EpisodeFileSelectionService(
        loadHistory: (_) async => cleared, loadMatches: (_, __) async => [smb]);
    expect(
        await stale.resolve(
            PlayableItem(
                videoPath: cleared.filePath,
                historyItem: history(cleared.filePath),
                mediaLibraryScope: webdav),
            choose: (_, __) async => null),
        isNull);
  });

  test(
      'revalidation rejects a selected candidate moved out of the scoped library',
      () async {
    final rows = [history('webdav://a/01.mkv'), history('webdav://b/01.mkv')];
    final service = EpisodeFileSelectionService(
        loadHistory: (_) async => rows.first,
        loadMatches: (_, __) async => rows);
    final result = await service.resolve(
        PlayableItem(
            videoPath: rows.first.filePath,
            historyItem: rows.first,
            mediaLibraryScope: webdav), choose: (candidates, _) async {
      final selected = candidates.last;
      rows.removeLast();
      rows.add(history('smb://c/01.mkv'));
      return selected;
    });
    expect(result, isNull);
  });

  test(
      'remote supplied file can play without local history, despite matches in other libraries',
      () async {
    const scope = MediaLibraryScope(MediaLibraryScopeKind.sharedRemote,
        hostOrigin: 'http://nas:7768');
    final remote =
        history('http://nas:7768/api/media/local/share/episodes/a/stream');
    final service = EpisodeFileSelectionService(
        loadHistory: (_) async => null,
        loadMatches: (_, __) async => [history('webdav://a/01.mkv')]);
    final requested = PlayableItem(
        videoPath: remote.filePath,
        historyItem: remote,
        mediaLibraryScope: scope);
    expect(await service.resolve(requested, choose: (_, __) async => null),
        same(requested));
  });

  test('scope survives detail reconstruction, matching and candidate changes',
      () {
    final context = PlaybackDetailContext(
        sourceKind: PlaybackSourceKind.webDav,
        sourceLabel: 'DAV',
        sourceKey: 'dav',
        title: 'Anime',
        isIdentified: false,
        episodeLoader: () async => [],
        mediaLibraryScope: webdav);
    final matched = context.withAnimeMatch(animeId: 10);
    expect(matched.mediaLibraryScope, same(webdav));
    const episode = PlaybackDetailEpisode(
        id: '2',
        videoPath: 'webdav://a/02.mkv',
        title: '2',
        animeId: 10,
        episodeId: 101);
    final playable =
        PlayableItem.fromDetailEpisode(episode, detailContext: context);
    expect(playable.detailContext, isNull);
    expect(playable.mediaLibraryScope, same(webdav));
    expect(
        EpisodeFileCandidate(history('webdav://b/02.mkv', episode: 101))
            .toPlayable(playable)
            .mediaLibraryScope,
        same(webdav));
  });

  test(
      'a scoped remote request stays selectable alongside remembered host versions',
      () async {
    const scope = MediaLibraryScope(MediaLibraryScopeKind.sharedRemote,
        hostOrigin: 'http://nas:7768');
    final supplied =
        history('http://nas:7768/api/media/local/share/episodes/new/stream');
    final saved =
        history('http://nas:7768/api/media/local/share/episodes/old/stream');
    final other =
        history('http://other:7768/api/media/local/share/episodes/old/stream');
    final service = EpisodeFileSelectionService(
      loadHistory: (path) async => path == saved.filePath ? saved : null,
      loadMatches: (_, __) async => [saved, other, history('/local.mkv')],
    );
    final requested = PlayableItem(
        videoPath: supplied.filePath,
        historyItem: supplied,
        mediaLibraryScope: scope);
    final selected =
        await service.resolve(requested, choose: (candidates, _) async {
      expect(candidates.map((c) => c.history.filePath),
          [saved.filePath, supplied.filePath]);
      return candidates.last;
    });
    expect(selected!.videoPath, supplied.filePath);
    expect(selected.mediaLibraryScope, same(scope));
  });

  test('SMB and local requests filter the same mixed matches independently',
      () async {
    final rows = [
      history('/local.mkv'),
      history('webdav://a/01.mkv'),
      history('smb://a/01.mkv')
    ];
    final service = EpisodeFileSelectionService(
        loadHistory: (_) async => rows.first,
        loadMatches: (_, __) async => rows);
    for (final entry in {
      MediaLibraryScopeKind.local: rows[0].filePath,
      MediaLibraryScopeKind.smb: rows[2].filePath,
    }.entries) {
      final result = await service.resolve(
          PlayableItem(
              videoPath: rows.first.filePath,
              historyItem: rows.first,
              mediaLibraryScope: MediaLibraryScope(entry.key)),
          choose: (_, __) async => throw StateError('only one scoped version'));
      expect(result!.videoPath, entry.value);
    }
  });
}
