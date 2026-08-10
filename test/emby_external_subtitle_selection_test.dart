import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/services/emby_track_application.dart';

void main() {
  group('resolveExternalSubtitleAction', () {
    test('selects the requested external stream and normalizes its codec', () {
      const track = EmbyResolvedTrackSelection.track(
        sourceIndex: 4,
        fingerprint: EmbyTrackFingerprint(
          language: 'zho',
          normalizedTitle: 'simplified chinese',
          codec: 'ASS',
          isExternal: true,
        ),
      );

      final action = resolveExternalSubtitleAction(track);

      expect(action.kind, EmbyExternalSubtitleActionKind.select);
      expect(action.streamIndex, 4);
      expect(action.codec, 'ass');
      expect(action.fingerprint, same(track.fingerprint));
    });

    test('uses srt when the selected external subtitle omits its codec', () {
      const track = EmbyResolvedTrackSelection.track(
        sourceIndex: 5,
        fingerprint: EmbyTrackFingerprint(
          language: 'zho',
          normalizedTitle: 'traditional chinese',
          isExternal: true,
        ),
      );

      final action = resolveExternalSubtitleAction(track);

      expect(action.kind, EmbyExternalSubtitleActionKind.select);
      expect(action.streamIndex, 5);
      expect(action.codec, 'srt');
    });
  });

  group('applyEmbyExternalSubtitleAction', () {
    test('downloads and activates only the selected current-source subtitle',
        () async {
      const action = EmbyExternalSubtitleAction.select(
        streamIndex: 4,
        codec: 'ass',
        fingerprint: EmbyTrackFingerprint(
          language: 'zho',
          normalizedTitle: 'simplified chinese',
          codec: 'ass',
          isExternal: true,
        ),
      );
      final harness = _ExternalSubtitleHarness();

      await harness.applyBundle(
        _bundleWithSubtitle(action),
        mediaSourceId: 'source-b',
      );

      expect(harness.downloads, <String>['episode-1|source-b|4|ass']);
      expect(harness.cachedIndexes, <int>[4]);
      expect(harness.activatedServerIndexes, <int>[4]);
      expect(harness.activeExternalSubtitlePath, 'C:/cache/4.ass');
      expect(harness.clears, 1);
      expect(harness.followDefaultLoads, 0);
      final downloadPosition = harness.events.indexOf('download:4');
      expect(
          harness.events.indexOf('set-subtitle:'), lessThan(downloadPosition));
      expect(
          harness.events.indexOf('clear-external'), lessThan(downloadPosition));
    });

    test('disabled clears embedded and external subtitles without downloading',
        () async {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.followDefault(),
        subtitle: EmbyResolvedTrackSelection.disabled(),
      );
      final harness = _ExternalSubtitleHarness()
        ..activeSubtitleTracks = <int>[1]
        ..activeExternalSubtitlePath = 'C:/cache/old.ass';

      await harness.applyBundle(selection);

      expect(harness.activeSubtitleTracks, isEmpty);
      expect(harness.activeExternalSubtitlePath, isNull);
      expect(harness.downloads, isEmpty);
      expect(harness.cachedIndexes, isEmpty);
      expect(harness.activatedServerIndexes, isEmpty);
      expect(harness.clears, 1);
      expect(harness.followDefaultLoads, 0);
    });

    test('follow default preserves the existing external subtitle behavior',
        () async {
      final harness = _ExternalSubtitleHarness()
        ..activeExternalSubtitlePath = 'C:/cache/current.ass';

      await harness.applyBundle(
        const EmbyResolvedTrackBundle(
          audio: EmbyResolvedTrackSelection.followDefault(),
          subtitle: EmbyResolvedTrackSelection.followDefault(),
        ),
      );

      expect(harness.followDefaultLoads, 1);
      expect(harness.clears, 0);
      expect(harness.downloads, isEmpty);
      expect(harness.activeExternalSubtitlePath, 'C:/cache/current.ass');
    });

    test(
        'follow default stops after tracks load when playback generation changes',
        () async {
      final harness = _DefaultSubtitleHarness();

      await harness.run(
        getTracks: () async {
          harness.generation++;
          return _defaultTracks();
        },
      );

      expect(harness.downloadedIndexes, isEmpty);
      expect(harness.cacheCalls, 0);
      expect(harness.activatedIndexes, isEmpty);
    });

    test('follow default checks identity after every subtitle download',
        () async {
      final harness = _DefaultSubtitleHarness();

      await harness.run(
        getTracks: () async => _defaultTracks(count: 3),
        download: (streamIndex, codec) async {
          harness.downloadedIndexes.add(streamIndex);
          if (streamIndex == 2) {
            harness.currentPath = 'emby://episode-2';
          }
          return 'C:/cache/$streamIndex.$codec';
        },
      );

      expect(harness.downloadedIndexes, <int>[1, 2]);
      expect(harness.cacheCalls, 0);
      expect(harness.activatedIndexes, isEmpty);
    });

    test('follow default checks identity again immediately before activation',
        () async {
      final harness = _DefaultSubtitleHarness();

      await harness.run(
        getTracks: () async => _defaultTracks(),
        cache: (downloaded, activePath) async {
          harness.cacheCalls++;
          harness.generation++;
          return true;
        },
      );

      expect(harness.downloadedIndexes, <int>[1, 2]);
      expect(harness.cacheCalls, 1);
      expect(harness.activatedIndexes, isEmpty);
    });

    test('a missing download fails without caching or activating', () async {
      final harness = _ExternalSubtitleHarness()
        ..activeSubtitleTracks = <int>[2]
        ..activeExternalSubtitlePath = 'C:/cache/old.ass'
        ..downloadResult = null;
      const action = EmbyExternalSubtitleAction.select(
        streamIndex: 6,
        codec: 'srt',
        fingerprint: EmbyTrackFingerprint(
          language: 'eng',
          codec: 'srt',
          isExternal: true,
        ),
      );

      await expectLater(
        harness.applyBundle(_bundleWithSubtitle(action)),
        throwsA(isA<StateError>()),
      );

      expect(harness.activeSubtitleTracks, isEmpty);
      expect(harness.activeExternalSubtitlePath, isNull);
      expect(harness.clears, 1);
      expect(harness.downloads, <String>['episode-1|source-a|6|srt']);
      expect(harness.cachedIndexes, isEmpty);
      expect(harness.activatedServerIndexes, isEmpty);
    });

    test('download errors are preserved and never activate stale subtitles',
        () async {
      final failure = StateError('download failed');
      final harness = _ExternalSubtitleHarness()
        ..activeSubtitleTracks = <int>[2]
        ..activeExternalSubtitlePath = 'C:/cache/old.ass'
        ..downloadError = failure;
      const action = EmbyExternalSubtitleAction.select(
        streamIndex: 7,
        codec: 'ass',
        fingerprint: EmbyTrackFingerprint(
          language: 'zho',
          codec: 'ass',
          isExternal: true,
        ),
      );

      await expectLater(
        harness.applyBundle(_bundleWithSubtitle(action)),
        throwsA(same(failure)),
      );

      expect(harness.activeSubtitleTracks, isEmpty);
      expect(harness.activeExternalSubtitlePath, isNull);
      expect(harness.clears, 1);
      expect(harness.cachedIndexes, isEmpty);
      expect(harness.activatedServerIndexes, isEmpty);
    });

    test('activation errors are reported after the exact subtitle is cached',
        () async {
      final failure = StateError('activation failed');
      final harness = _ExternalSubtitleHarness()
        ..activeSubtitleTracks = <int>[2]
        ..activeExternalSubtitlePath = 'C:/cache/old.ass'
        ..activationError = failure;
      const action = EmbyExternalSubtitleAction.select(
        streamIndex: 8,
        codec: 'ass',
        fingerprint: EmbyTrackFingerprint(
          language: 'zho',
          codec: 'ass',
          isExternal: true,
        ),
      );

      await expectLater(
        harness.applyBundle(_bundleWithSubtitle(action)),
        throwsA(same(failure)),
      );

      expect(harness.activeSubtitleTracks, isEmpty);
      expect(harness.activeExternalSubtitlePath, isNull);
      expect(harness.clears, 1);
      expect(harness.downloads, <String>['episode-1|source-a|8|ass']);
      expect(harness.cachedIndexes, <int>[8]);
      expect(harness.activatedServerIndexes, <int>[8]);
    });

    test('video-path guard invokes Emby application only for emby paths',
        () async {
      var embyApplications = 0;

      await applyEmbyTracksForVideoPath(
        videoPath: 'emby://episode-1',
        isTranscoding: false,
        applyEmby: () async {
          embyApplications++;
        },
      );

      expect(embyApplications, 1);
    });

    test('video-path guard skips all Emby track application for transcoding',
        () async {
      var embyApplications = 0;

      await applyEmbyTracksForVideoPath(
        videoPath: 'emby://episode-1',
        isTranscoding: true,
        applyEmby: () async {
          embyApplications++;
        },
      );

      expect(embyApplications, 0);
    });

    test('video-path guard leaves Jellyfin and unrelated paths untouched',
        () async {
      for (final path in <String>[
        'jellyfin://episode-1',
        'https://media.test/video.mkv',
        r'C:\Anime\Episode 01.mkv',
      ]) {
        var embyApplications = 0;

        await applyEmbyTracksForVideoPath(
          videoPath: path,
          isTranscoding: false,
          applyEmby: () async {
            embyApplications++;
          },
        );

        expect(embyApplications, 0, reason: path);
      }
    });
  });

  group('activateEmbyExternalSubtitle', () {
    test('awaits the asynchronous player setter before completing', () async {
      final setterCompleter = Completer<void>();
      final player = _AsyncSubtitlePlayer(
        onSet: (path) => setterCompleter.future,
      );
      var completed = false;

      final activation = activateEmbyExternalSubtitle(
        player: player,
        subtitlePath: 'C:/cache/selected.ass',
      );
      activation.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(player.paths, <String>['C:/cache/selected.ass']);
      expect(completed, isFalse);

      setterCompleter.complete();
      await activation;

      expect(completed, isTrue);
    });

    test('preserves the exact asynchronous setter error', () async {
      final failure = StateError('async player rejected subtitle');
      final player = _AsyncSubtitlePlayer(
        onSet: (path) async => throw failure,
      );

      await expectLater(
        activateEmbyExternalSubtitle(
          player: player,
          subtitlePath: 'C:/cache/selected.ass',
        ),
        throwsA(same(failure)),
      );

      expect(player.paths, <String>['C:/cache/selected.ass']);
    });
  });
}

class _ExternalSubtitleHarness {
  List<int> activeAudioTracks = <int>[];
  List<int> activeSubtitleTracks = <int>[];
  String? activeExternalSubtitlePath;
  String? downloadResult = 'generated';
  Object? downloadError;
  Object? activationError;
  final List<String> downloads = <String>[];
  final List<int> cachedIndexes = <int>[];
  final List<int> activatedServerIndexes = <int>[];
  final List<String> events = <String>[];
  int clears = 0;
  int followDefaultLoads = 0;

  Future<void> applyBundle(
    EmbyResolvedTrackBundle bundle, {
    String mediaSourceId = 'source-a',
  }) {
    return applyEmbyResolvedTracksAfterOpen(
      mediaInfo: PlayerMediaInfo(
        duration: 1000,
        audio: <PlayerAudioStreamInfo>[],
        subtitle: <PlayerSubtitleStreamInfo>[
          PlayerSubtitleStreamInfo(
            title: 'Old embedded subtitle',
            language: 'eng',
            rawRepresentation: 'Old embedded subtitle',
          ),
        ],
      ),
      bundle: bundle,
      setActiveAudio: (indexes) {
        events.add('set-audio:${indexes.join(',')}');
        activeAudioTracks = List<int>.of(indexes);
      },
      setActiveSubtitle: (indexes) {
        events.add('set-subtitle:${indexes.join(',')}');
        activeSubtitleTracks = List<int>.of(indexes);
      },
      clearExternal: () async {
        events.add('clear-external');
        clears++;
        activeExternalSubtitlePath = null;
      },
      loadExternal: (action) => _loadExternalAction(
        action,
        mediaSourceId: mediaSourceId,
      ),
    );
  }

  Future<void> _loadExternalAction(
    EmbyExternalSubtitleAction action, {
    required String mediaSourceId,
  }) {
    return applyEmbyExternalSubtitleAction(
      action: action,
      videoPath: 'emby://episode-1',
      itemId: 'episode-1',
      mediaSourceId: mediaSourceId,
      download: (itemId, selectedMediaSourceId, streamIndex, codec) async {
        events.add('download:$streamIndex');
        downloads.add(
          '$itemId|$selectedMediaSourceId|$streamIndex|$codec',
        );
        if (downloadError != null) throw downloadError!;
        if (downloadResult == null) return null;
        return 'C:/cache/$streamIndex.$codec';
      },
      cache: (videoPath, path, streamIndex, codec) async {
        events.add('cache:$streamIndex');
        cachedIndexes.add(streamIndex);
        return true;
      },
      activate: (path, streamIndex) async {
        events.add('activate:$streamIndex');
        activatedServerIndexes.add(streamIndex);
        if (activationError != null) throw activationError!;
        activeExternalSubtitlePath = path;
      },
      followDefault: () async {
        events.add('follow-default');
        followDefaultLoads++;
      },
    );
  }
}

EmbyResolvedTrackBundle _bundleWithSubtitle(
  EmbyExternalSubtitleAction action,
) {
  return EmbyResolvedTrackBundle(
    audio: const EmbyResolvedTrackSelection.followDefault(),
    subtitle: EmbyResolvedTrackSelection.track(
      sourceIndex: action.streamIndex!,
      fingerprint: action.fingerprint!,
    ),
  );
}

class _DefaultSubtitleHarness {
  final int capturedGeneration = 1;
  final String capturedPath = 'emby://episode-1';
  int generation = 1;
  String currentPath = 'emby://episode-1';
  final List<int> downloadedIndexes = <int>[];
  final List<int> activatedIndexes = <int>[];
  int cacheCalls = 0;

  bool get isCurrent =>
      generation == capturedGeneration && currentPath == capturedPath;

  Future<void> run({
    required Future<List<Map<String, dynamic>>> Function() getTracks,
    Future<String?> Function(int streamIndex, String codec)? download,
    Future<bool> Function(
      List<Map<String, dynamic>> downloaded,
      String? activePath,
    )? cache,
  }) {
    return applyEmbyExternalSubtitleAction(
      action: const EmbyExternalSubtitleAction.followDefault(),
      videoPath: capturedPath,
      itemId: 'episode-1',
      mediaSourceId: 'source-a',
      download: (itemId, mediaSourceId, streamIndex, codec) async => null,
      cache: (videoPath, subtitlePath, streamIndex, codec) async => false,
      activate: (subtitlePath, streamIndex) async {},
      followDefault: () => loadDefaultEmbyExternalSubtitles(
        getTracks: getTracks,
        download: download ??
            (streamIndex, codec) async {
              downloadedIndexes.add(streamIndex);
              return 'C:/cache/$streamIndex.$codec';
            },
        cache: cache ??
            (downloaded, activePath) async {
              cacheCalls++;
              return true;
            },
        activate: (subtitlePath, streamIndex) async {
          activatedIndexes.add(streamIndex);
        },
        isCurrent: () => isCurrent,
      ),
    );
  }
}

List<Map<String, dynamic>> _defaultTracks({int count = 2}) {
  return <Map<String, dynamic>>[
    for (var index = 1; index <= count; index++)
      <String, dynamic>{
        'index': index,
        'type': 'external',
        'language': index == 1 ? 'zho' : 'eng',
        'title': index == 1 ? 'Simplified Chinese' : 'English',
        'codec': index == 1 ? 'ASS' : 'srt',
        'isDefault': index == 1,
      },
  ];
}

class _AsyncSubtitlePlayer implements AsyncExternalSubtitlePlayer {
  _AsyncSubtitlePlayer({required this.onSet});

  final Future<void> Function(String path) onSet;
  final List<String> paths = <String>[];

  @override
  Future<void> setExternalSubtitleAsync(String path) {
    paths.add(path);
    return onSet(path);
  }
}
