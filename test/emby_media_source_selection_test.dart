import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_source_selection.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/widgets/emby_media_source_selector.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

PlaybackMediaSource _source(String id, String path) {
  return PlaybackMediaSource(
    id: id,
    path: path,
    container: path.split('.').last,
  );
}

PlaybackSession _session({
  required String selectedId,
  required List<PlaybackMediaSource> sources,
}) {
  return PlaybackSession(
    itemId: 'episode-1',
    streamUrl: 'https://media.test/$selectedId',
    isTranscoding: false,
    mediaSourceId: selectedId,
    mediaSources: sources,
    selectedSource: sources.firstWhere((source) => source.id == selectedId),
  );
}

void main() {
  group('selectAndPlayEmbySource', () {
    test('plays a single source without prompting or reloading', () async {
      final source = _source('only', '/media/only.mkv');
      final initial = _session(selectedId: source.id, sources: [source]);
      var prompted = false;
      var reloaded = false;
      final playedSessions = <PlaybackSession>[];

      final result = await selectAndPlayEmbySource(
        initialSession: initial,
        chooseSource: (sources, selectedId) async {
          prompted = true;
          return sources.single;
        },
        reloadSession: (mediaSourceId) async {
          reloaded = true;
          return initial;
        },
        startPlayback: (session) async => playedSessions.add(session),
      );

      expect(result, isTrue);
      expect(prompted, isFalse);
      expect(reloaded, isFalse);
      expect(playedSessions, [same(initial)]);
    });

    test('reloads the selected source before starting playback', () async {
      final first = _source('source-a', '/media/Version A.mkv');
      final second = _source('source-b', '/media/Version B.mp4');
      final initial = _session(selectedId: first.id, sources: [first, second]);
      final requestedSourceIds = <String>[];
      final playedSessions = <PlaybackSession>[];
      final sourceChanges = <(String?, String)>[];
      final events = <String>[];
      final selectedSession =
          _session(selectedId: second.id, sources: [first, second]);

      final result = await selectAndPlayEmbySource(
        initialSession: initial,
        chooseSource: (sources, selectedId) async {
          expect(sources, orderedEquals([first, second]));
          expect(selectedId, first.id);
          return second;
        },
        reloadSession: (mediaSourceId) async {
          requestedSourceIds.add(mediaSourceId);
          events.add('reload:$mediaSourceId');
          return selectedSession;
        },
        onSourceChanged: (previousId, selectedId) async {
          sourceChanges.add((previousId, selectedId));
          events.add('change:$previousId:$selectedId');
        },
        startPlayback: (session) async {
          playedSessions.add(session);
          events.add('play:${session.mediaSourceId}');
        },
      );

      expect(requestedSourceIds, [second.id]);
      expect(playedSessions, [same(selectedSession)]);
      expect(sourceChanges, [(first.id, second.id)]);
      expect(events,
          ['reload:source-b', 'change:source-a:source-b', 'play:source-b']);
      expect(result, isTrue);
    });

    test('does not reload or start playback when selection is cancelled',
        () async {
      final first = _source('source-a', '/media/Version A.mkv');
      final second = _source('source-b', '/media/Version B.mp4');
      final initial = _session(selectedId: first.id, sources: [first, second]);
      var reloaded = false;
      var playbackStarts = 0;
      var sourceChanges = 0;

      final result = await selectAndPlayEmbySource(
        initialSession: initial,
        chooseSource: (sources, selectedId) async => null,
        reloadSession: (mediaSourceId) async {
          reloaded = true;
          return initial;
        },
        onSourceChanged: (previousId, selectedId) async => sourceChanges++,
        startPlayback: (session) async => playbackStarts++,
      );

      expect(result, isFalse);
      expect(reloaded, isFalse);
      expect(playbackStarts, 0);
      expect(sourceChanges, 0);
    });

    test('propagates reload failures without starting playback', () async {
      final first = _source('source-a', '/media/Version A.mkv');
      final second = _source('source-b', '/media/Version B.mp4');
      final initial = _session(selectedId: first.id, sources: [first, second]);
      var playbackStarts = 0;
      var sourceChanges = 0;

      final future = selectAndPlayEmbySource(
        initialSession: initial,
        chooseSource: (sources, selectedId) async => second,
        reloadSession: (mediaSourceId) => Future.error(StateError('reload')),
        onSourceChanged: (previousId, selectedId) async => sourceChanges++,
        startPlayback: (session) async => playbackStarts++,
      );

      await expectLater(future, throwsStateError);
      expect(playbackStarts, 0);
      expect(sourceChanges, 0);
    });

    test(
        'plays the initial session without reload when current source is chosen',
        () async {
      final first = _source('source-a', '/media/Version A.mkv');
      final second = _source('source-b', '/media/Version B.mp4');
      final initial = _session(selectedId: first.id, sources: [first, second]);
      var reloads = 0;
      var sourceChanges = 0;
      final played = <PlaybackSession>[];

      final result = await selectAndPlayEmbySource(
        initialSession: initial,
        chooseSource: (sources, selectedId) async => first,
        reloadSession: (mediaSourceId) async {
          reloads++;
          return initial;
        },
        onSourceChanged: (previousId, selectedId) async => sourceChanges++,
        startPlayback: (session) async => played.add(session),
      );

      expect(result, isTrue);
      expect(reloads, 0);
      expect(sourceChanges, 0);
      expect(played, [same(initial)]);
    });
  });

  testWidgets('selector shows every source and returns the tapped source',
      (tester) async {
    final first = _source('source-a', '/media/Version A.mkv');
    final second = _source(
      'source-b',
      'https://media.test/%E5%89%A7%E5%9C%BA%E7%89%88.mp4',
    );
    PlaybackMediaSource? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmbyMediaSourceSelector(
            sources: [first, second],
            selectedSourceId: first.id,
            onSelected: (source) => selected = source,
          ),
        ),
      ),
    );

    expect(find.text('Version A.mkv'), findsOneWidget);
    expect(find.text('剧场版.mp4'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    await tester.tap(find.text('剧场版.mp4'));
    expect(selected, same(second));
  });

  test('source label falls back to container and ordinal without a path', () {
    const source = PlaybackMediaSource(id: 'source-b', container: 'mkv');

    expect(embyMediaSourceLabel(source, index: 1), '版本 2 · MKV');
  });

  test('source-change cleanup clears both preferences exactly once', () async {
    final clearedAudioItems = <String>[];
    final clearedSubtitleItems = <String>[];

    await clearEmbySelectionsForSourceChange(
      itemId: 'episode-1',
      clearAudio: clearedAudioItems.add,
      clearSubtitle: clearedSubtitleItems.add,
    );

    expect(clearedAudioItems, <String>['episode-1']);
    expect(clearedSubtitleItems, <String>['episode-1']);
  });

  test('nested Emby playback paths resolve to the episode item id', () {
    expect(
      embyItemIdFromVideoPath('emby://series/season/episode-1'),
      'episode-1',
    );
    expect(embyItemIdFromVideoPath('emby://episode-2'), 'episode-2');
  });

  test('subtitle download uses the selected Emby media source', () async {
    final previousPathProvider = PathProviderPlatform.instance;
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'nipaplay-selected-subtitle-source-test-',
    );
    PathProviderPlatform.instance =
        _TemporaryPathProvider(temporaryDirectory.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previousPathProvider;
      await temporaryDirectory.delete(recursive: true);
    });
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      if (request.uri.path.endsWith('/PlaybackInfo')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'MediaSources': [
              {'Id': 'source-a'},
              {'Id': 'source-b'},
            ],
          }));
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('1\n00:00:00,000 --> 00:00:01,000\nSubtitle');
      }
      await request.response.close();
    });
    final emby = EmbyService.instance;
    final previousServerUrl = emby.serverUrl;
    final previousAccessToken = emby.accessToken;
    final previousUserId = emby.userId;
    final previousProfile = emby.currentProfile;
    final previousIsConnected = emby.isConnected;
    emby
      ..serverUrl = 'http://${server.address.address}:${server.port}'
      ..accessToken = 'emby-token'
      ..userId = 'emby-user'
      ..currentProfile = null
      ..isConnected = true;
    addTearDown(() {
      emby
        ..isConnected = previousIsConnected
        ..serverUrl = previousServerUrl
        ..accessToken = previousAccessToken
        ..userId = previousUserId
        ..currentProfile = previousProfile;
    });

    final file = await HttpOverrides.runWithHttpOverrides(
      () => emby.downloadSubtitleFile(
        'episode-1',
        4,
        'srt',
        mediaSourceId: 'source-b',
      ),
      _RealHttpOverrides(),
    );

    expect(file, isNotNull);
    expect(
      requestedPaths,
      contains('/emby/Videos/episode-1/source-b/Subtitles/4/Stream.srt'),
    );
  });

  test('real Emby playback entries wire the shared source selection flow', () {
    String source(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final detailPage = source('lib/pages/media_server_detail_page.dart');
    final desktopMenu = File(
      'lib/themes/nipaplay/widgets/jellyfin_quality_menu.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final cupertinoMenu = source(
      'lib/themes/cupertino/widgets/player_menu/'
      'cupertino_jellyfin_quality_pane.dart',
    );
    final streaming = source(
      'lib/utils/video_player_state/video_player_state_streaming.dart',
    );
    final embyService = source('lib/services/emby_service.dart');

    expect(detailPage, contains('selectAndPlayEmbySource('));
    expect(detailPage, contains('_startSelectedEmbyEpisode('));
    expect(
      detailPage,
      contains(
        'Future<void> _startEpisodePlayback('
        '\n    WatchHistoryItem historyItem,'
        '\n    PlaybackSession? playbackSession,'
        '\n  ) async {'
        '\n    if (!mounted) return;',
      ),
    );
    expect(desktopMenu, contains('EmbyMediaSourceSelector('));
    expect(desktopMenu, contains('mediaSourceId: _selectedMediaSourceId'));
    expect(desktopMenu, contains('_selectMediaSource('));
    expect(
      desktopMenu,
      contains('getSubtitleTracks(itemId, mediaSourceId: source.id)'),
    );
    expect(
      desktopMenu,
      contains(
        '_selectedMediaSourceId = source.id;'
        '\n      _selectedServerSubtitleIndex = null;'
        '\n      _burnIn = false;',
      ),
    );
    expect(cupertinoMenu, contains('embyMediaSourceLabel('));
    expect(cupertinoMenu, contains('mediaSourceId: _selectedMediaSourceId'));
    expect(cupertinoMenu, contains('_selectMediaSource('));
    expect(
      cupertinoMenu,
      contains('getSubtitleTracks(itemId, mediaSourceId: source.id)'),
    );
    expect(
      cupertinoMenu,
      contains(
        '_selectedMediaSourceId = source.id;'
        '\n      _selectedServerSubtitle = null;'
        '\n      _burnIn = false;',
      ),
    );
    expect(streaming, contains('String? mediaSourceId'));
    expect(
      streaming,
      contains('mediaSourceId: mediaSourceId ??'),
    );
    final embyReload = streaming.substring(
      streaming.indexOf('extension EmbyQualitySwitch'),
    );
    expect(embyReload, contains('rethrow;'));
    expect(embyReload, contains('if (_error != null || !hasVideo)'));
    expect(
      embyReload.indexOf('await initializePlayer('),
      lessThan(embyReload.indexOf('_currentPlaybackSession = newSession;')),
    );
    expect(embyService, contains('{String? mediaSourceId}'));
    expect(embyService, contains("source['Id']?.toString() == mediaSourceId"));
    expect(detailPage, contains('clearEmbySelectionsForSourceChange('));
    final sourceChanged = detailPage.substring(
      detailPage.indexOf('onSourceChanged: (previousId, selectedId) async'),
      detailPage.indexOf(
        'startPlayback:',
        detailPage.indexOf('onSourceChanged:'),
      ),
    );
    expect(
      sourceChanged.indexOf('if (!mounted) return;'),
      lessThan(sourceChanged.indexOf('Provider.of<VideoPlayerState>')),
    );
    final compactStreaming = streaming.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      compactStreaming,
      contains('final itemId = embyItemIdFromVideoPath(videoPath);'),
    );
    expect(
      compactStreaming,
      contains('final mediaSourceId = _currentPlaybackSession?.mediaSourceId;'),
    );
    expect(
      compactStreaming,
      contains(
        'getSubtitleTracks(itemId, mediaSourceId: mediaSourceId)',
      ),
    );
    expect(
      compactStreaming,
      contains(
        'downloadSubtitleFile(itemId, subtitleIndex, subtitleCodec, '
        'mediaSourceId: mediaSourceId)',
      ),
    );
    final embySubtitleLoader = streaming.substring(
      streaming.indexOf('Future<void> _loadEmbyExternalSubtitles'),
      streaming.indexOf('Future<void> _loadStreamingExternalSubtitles'),
    );
    expect(
      RegExp(r'_currentPlaybackSession\?\.mediaSourceId')
          .allMatches(embySubtitleLoader),
      hasLength(1),
    );
  });
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

class _RealHttpOverrides extends HttpOverrides {}
