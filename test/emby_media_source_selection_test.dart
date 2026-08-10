import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_selection_resolver.dart';
import 'package:nipaplay/services/emby_media_source_selection.dart';
import 'package:nipaplay/services/emby_service.dart';
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

EmbyMediaSourceDescriptor _descriptor(String id, String name) {
  final source = _source(id, '/media/$name.mkv');
  return EmbyMediaSourceDescriptor(
    source: source,
    displayName: name,
    summary: '1080p',
    technical: const EmbyTechnicalFingerprint(
      height: 1080,
      videoCodec: 'hevc',
      container: 'mkv',
    ),
    videoTracks: const <EmbyVideoStreamDescriptor>[],
    audioTracks: const <EmbyAudioTrackDescriptor>[],
    subtitleTracks: const <EmbySubtitleTrackDescriptor>[],
  );
}

EmbyResolvedTrackBundle _tracks({
  required int audioIndex,
  required int subtitleIndex,
}) {
  return EmbyResolvedTrackBundle(
    audio: EmbyResolvedTrackSelection.track(
      sourceIndex: audioIndex,
      fingerprint: const EmbyTrackFingerprint(
        language: 'jpn',
        codec: 'aac',
        channels: 2,
      ),
    ),
    subtitle: EmbyResolvedTrackSelection.track(
      sourceIndex: subtitleIndex,
      fingerprint: const EmbyTrackFingerprint(
        language: 'zho',
        normalizedTitle: '简体中文',
        codec: 'ass',
        isExternal: true,
      ),
    ),
  );
}

PlaybackSession _sessionFor(EmbySourceCandidate candidate) {
  return _session(
    selectedId: candidate.source.source.id,
    sources: <PlaybackMediaSource>[candidate.source.source],
  );
}

void main() {
  group('resolveEmbyPlaybackSession', () {
    final sourceA = _descriptor('source-a', '[Baha] Episode 01');
    final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
    final sourceATracks = _tracks(audioIndex: 1, subtitleIndex: 3);
    final sourceBTracks = _tracks(audioIndex: 4, subtitleIndex: 7);

    test('plays the remembered source without opening a chooser', () async {
      final requestedIds = <String>[];
      final plan = EmbyResolutionPlan(
        candidates: <EmbySourceCandidate>[
          EmbySourceCandidate(
            source: sourceB,
            reason: EmbySelectionReason.episodeExact,
            tracks: sourceBTracks,
          ),
          EmbySourceCandidate(
            source: sourceA,
            reason: EmbySelectionReason.embyDefault,
            tracks: sourceATracks,
          ),
        ],
      );

      final result = await resolveEmbyPlaybackSession(
        plan: plan,
        createSession: (candidate) async {
          requestedIds.add(candidate.source.source.id);
          return _sessionFor(candidate);
        },
      );

      expect(requestedIds, <String>['source-b']);
      expect(result.session.mediaSourceId, 'source-b');
      expect(result.reason, EmbySelectionReason.episodeExact);
      expect(result.didFallback, isFalse);
      expect(result.tracks, same(sourceBTracks));
    });

    test('falls back in plan order with the successful candidate track bundle',
        () async {
      final requestedIds = <String>[];
      final requestedTracks = <EmbyResolvedTrackBundle>[];
      final plan = EmbyResolutionPlan(
        candidates: <EmbySourceCandidate>[
          EmbySourceCandidate(
            source: sourceB,
            reason: EmbySelectionReason.episodeExact,
            tracks: sourceBTracks,
          ),
          EmbySourceCandidate(
            source: sourceA,
            reason: EmbySelectionReason.seriesFamily,
            tracks: sourceATracks,
          ),
        ],
      );

      final result = await resolveEmbyPlaybackSession(
        plan: plan,
        createSession: (candidate) async {
          requestedIds.add(candidate.source.source.id);
          requestedTracks.add(candidate.tracks);
          if (candidate.source.source.id == 'source-b') {
            throw StateError('source-b unavailable');
          }
          return _sessionFor(candidate);
        },
      );

      expect(requestedIds, <String>['source-b', 'source-a']);
      expect(requestedTracks, hasLength(2));
      expect(requestedTracks[0], same(sourceBTracks));
      expect(requestedTracks[1], same(sourceATracks));
      expect(result.session.mediaSourceId, 'source-a');
      expect(result.reason, EmbySelectionReason.seriesFamily);
      expect(result.didFallback, isTrue);
      expect(result.tracks, same(sourceATracks));
    });

    test('rejects a session for the wrong source without binding its tracks',
        () async {
      final requestedIds = <String>[];
      final plan = EmbyResolutionPlan(
        candidates: <EmbySourceCandidate>[
          EmbySourceCandidate(
            source: sourceB,
            reason: EmbySelectionReason.episodeExact,
            tracks: sourceBTracks,
          ),
          EmbySourceCandidate(
            source: sourceA,
            reason: EmbySelectionReason.seriesFamily,
            tracks: sourceATracks,
          ),
        ],
      );

      final result = await resolveEmbyPlaybackSession(
        plan: plan,
        createSession: (candidate) async {
          requestedIds.add(candidate.source.source.id);
          if (candidate.source.source.id == 'source-b') {
            return _session(
              selectedId: 'source-a',
              sources: <PlaybackMediaSource>[sourceA.source, sourceB.source],
            );
          }
          return _sessionFor(candidate);
        },
      );

      expect(requestedIds, <String>['source-b', 'source-a']);
      expect(result.session.mediaSourceId, 'source-a');
      expect(result.reason, EmbySelectionReason.seriesFamily);
      expect(result.didFallback, isTrue);
      expect(result.tracks, same(sourceATracks));
      expect(result.tracks, isNot(same(sourceBTracks)));
    });

    test('tries each source once and preserves the final failure', () async {
      final requestedIds = <String>[];
      final finalFailure = StateError('source-a unavailable');
      final plan = EmbyResolutionPlan(
        candidates: <EmbySourceCandidate>[
          EmbySourceCandidate(
            source: sourceB,
            reason: EmbySelectionReason.episodeExact,
            tracks: sourceBTracks,
          ),
          EmbySourceCandidate(
            source: sourceB,
            reason: EmbySelectionReason.seriesFamily,
            tracks: sourceBTracks,
          ),
          EmbySourceCandidate(
            source: sourceA,
            reason: EmbySelectionReason.embyDefault,
            tracks: sourceATracks,
          ),
        ],
      );

      final future = resolveEmbyPlaybackSession(
        plan: plan,
        createSession: (candidate) async {
          final id = candidate.source.source.id;
          requestedIds.add(id);
          if (id == 'source-a') throw finalFailure;
          throw StateError('$id unavailable');
        },
      );

      await expectLater(future, throwsA(same(finalFailure)));
      expect(requestedIds, <String>['source-b', 'source-a']);
    });
  });

  group('ensureEmbyPlayerOpened', () {
    test('accepts only a player with no error and an opened video', () {
      expect(() => ensureEmbyPlayerOpened(null, true), returnsNormally);
      expect(() => ensureEmbyPlayerOpened('', true), returnsNormally);
    });

    test('throws the player error even when a video is reported', () {
      expect(
        () => ensureEmbyPlayerOpened('decoder failed', true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'decoder failed',
          ),
        ),
      );
    });

    test('throws when initialization completes without a video', () {
      expect(
        () => ensureEmbyPlayerOpened(null, false),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('initializeEmbyPlayerAttempt', () {
    test('awaits initialize, validates the player, then awaits play', () async {
      final events = <String>[];

      await initializeEmbyPlayerAttempt(
        initialize: () async {
          events.add('initialize-start');
          await Future<void>.delayed(Duration.zero);
          events.add('initialize-done');
        },
        readError: () {
          events.add('read-error');
          return null;
        },
        hasVideo: () {
          events.add('has-video');
          return true;
        },
        play: () async {
          events.add('play-start');
          await Future<void>.delayed(Duration.zero);
          events.add('play-done');
        },
      );

      expect(events, <String>[
        'initialize-start',
        'initialize-done',
        'read-error',
        'has-video',
        'play-start',
        'play-done',
      ]);
    });

    test('does not play when initialized media is unusable', () async {
      final events = <String>[];

      await expectLater(
        initializeEmbyPlayerAttempt(
          initialize: () async => events.add('initialize'),
          readError: () {
            events.add('read-error');
            return null;
          },
          hasVideo: () {
            events.add('has-video');
            return false;
          },
          play: () async => events.add('play'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(events, <String>['initialize', 'read-error', 'has-video']);
    });

    test('does not play when the player reports an error with video', () async {
      final events = <String>[];

      await expectLater(
        initializeEmbyPlayerAttempt(
          initialize: () async => events.add('initialize'),
          readError: () {
            events.add('read-error');
            return 'decoder failed';
          },
          hasVideo: () {
            events.add('has-video');
            return true;
          },
          play: () async => events.add('play'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message.toString(),
            'message',
            contains('decoder failed'),
          ),
        ),
      );

      expect(events, <String>['initialize', 'read-error', 'has-video']);
    });
  });

  group('createEmbyPlaybackSessionForCandidate', () {
    test('passes the candidate source and resolved track indexes', () async {
      final source = _descriptor('source-b', '[LoliHouse] Episode 01');
      final tracks = _tracks(audioIndex: 4, subtitleIndex: 7);
      final candidate = EmbySourceCandidate(
        source: source,
        reason: EmbySelectionReason.episodeExact,
        tracks: tracks,
      );
      dynamic capturedRequest;
      final expectedSession = _sessionFor(candidate);

      final session = await createEmbyPlaybackSessionForCandidate(
        itemId: 'episode-1',
        candidate: candidate,
        startPositionMs: 12000,
        playSessionId: 'play-session-1',
        createSession: (request) async {
          capturedRequest = request;
          return expectedSession;
        },
      );

      expect(session, same(expectedSession));
      expect(capturedRequest.itemId, 'episode-1');
      expect(capturedRequest.mediaSourceId, 'source-b');
      expect(capturedRequest.startPositionMs, 12000);
      expect(capturedRequest.playSessionId, 'play-session-1');
      expect(capturedRequest.audioStreamIndex, 4);
      expect(capturedRequest.subtitleStreamIndex, 7);
      expect(capturedRequest.burnInSubtitle, isFalse);
    });

    test('maps disabled subtitles to no stream and no burn-in', () async {
      final source = _descriptor('source-a', '[Baha] Episode 01');
      final candidate = EmbySourceCandidate(
        source: source,
        reason: EmbySelectionReason.embyDefault,
        tracks: const EmbyResolvedTrackBundle(
          audio: EmbyResolvedTrackSelection.followDefault(),
          subtitle: EmbyResolvedTrackSelection.disabled(),
        ),
      );
      dynamic capturedRequest;

      await createEmbyPlaybackSessionForCandidate(
        itemId: 'episode-1',
        candidate: candidate,
        createSession: (request) async {
          capturedRequest = request;
          return _sessionFor(candidate);
        },
      );

      expect(capturedRequest.mediaSourceId, 'source-a');
      expect(capturedRequest.audioStreamIndex, isNull);
      expect(capturedRequest.subtitleStreamIndex, isNull);
      expect(capturedRequest.burnInSubtitle, isFalse);
    });

    for (final codec in <String>['PGS', 'dvdsub']) {
      test('burns in embedded $codec image subtitles', () async {
        final source = _descriptor('source-image', 'Image Subtitle');
        final candidate = EmbySourceCandidate(
          source: source,
          reason: EmbySelectionReason.episodeExact,
          tracks: EmbyResolvedTrackBundle(
            audio: const EmbyResolvedTrackSelection.followDefault(),
            subtitle: EmbyResolvedTrackSelection.track(
              sourceIndex: 9,
              fingerprint: EmbyTrackFingerprint(
                language: 'zho',
                codec: codec,
                isExternal: false,
              ),
            ),
          ),
        );
        dynamic capturedRequest;

        await createEmbyPlaybackSessionForCandidate(
          itemId: 'episode-1',
          candidate: candidate,
          createSession: (request) async {
            capturedRequest = request;
            return _sessionFor(candidate);
          },
        );

        expect(capturedRequest.subtitleStreamIndex, 9);
        expect(capturedRequest.burnInSubtitle, isTrue);
      });
    }

    test('does not burn in text or external subtitles', () async {
      final cases = <({String codec, bool isExternal})>[
        (codec: 'ass', isExternal: false),
        (codec: 'pgs', isExternal: true),
      ];

      for (final subtitleCase in cases) {
        final source = _descriptor('source-text', 'Text Subtitle');
        final candidate = EmbySourceCandidate(
          source: source,
          reason: EmbySelectionReason.episodeExact,
          tracks: EmbyResolvedTrackBundle(
            audio: const EmbyResolvedTrackSelection.followDefault(),
            subtitle: EmbyResolvedTrackSelection.track(
              sourceIndex: 6,
              fingerprint: EmbyTrackFingerprint(
                language: 'zho',
                codec: subtitleCase.codec,
                isExternal: subtitleCase.isExternal,
              ),
            ),
          ),
        );
        dynamic capturedRequest;

        await createEmbyPlaybackSessionForCandidate(
          itemId: 'episode-1',
          candidate: candidate,
          createSession: (request) async {
            capturedRequest = request;
            return _sessionFor(candidate);
          },
        );

        expect(
          capturedRequest.burnInSubtitle,
          isFalse,
          reason: '${subtitleCase.codec}, external=${subtitleCase.isExternal}',
        );
      }
    });
  });

  test('player coordinator stores and replaces the successful track bundle',
      () async {
    final sourceA = _descriptor('source-a', '[Baha] Episode 01');
    final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
    final sourceATracks = _tracks(audioIndex: 1, subtitleIndex: 3);
    final sourceBTracks = _tracks(audioIndex: 4, subtitleIndex: 7);
    final initializedSessions = <PlaybackSession>[];
    final initializedTracks = <EmbyResolvedTrackBundle>[];
    final coordinator = EmbyPlaybackStateCoordinator(
      initializePlayer: (session, tracks) async {
        initializedSessions.add(session);
        initializedTracks.add(tracks);
      },
    );
    final playbackB = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-b',
        sources: <PlaybackMediaSource>[sourceB.source],
      ),
      reason: EmbySelectionReason.episodeExact,
      didFallback: false,
      tracks: sourceBTracks,
    );
    final playbackA = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-a',
        sources: <PlaybackMediaSource>[sourceA.source],
      ),
      reason: EmbySelectionReason.seriesFamily,
      didFallback: true,
      tracks: sourceATracks,
    );

    await coordinator.initialize(playbackB);

    expect(coordinator.currentTrackSelection, same(sourceBTracks));
    expect(initializedSessions.single.mediaSourceId, 'source-b');
    expect(initializedTracks.single, same(sourceBTracks));

    await coordinator.reload(playbackA);

    expect(coordinator.currentTrackSelection, same(sourceATracks));
    expect(
      initializedSessions.map((session) => session.mediaSourceId),
      <String?>['source-b', 'source-a'],
    );
    expect(initializedTracks[1], same(sourceATracks));
  });

  test('failed reload restores the paused playback snapshot before rethrowing',
      () async {
    final sourceA = _descriptor('source-a', '[Baha] Episode 01');
    final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
    final sourceATracks = _tracks(audioIndex: 1, subtitleIndex: 3);
    final sourceBTracks = _tracks(audioIndex: 4, subtitleIndex: 7);
    final initializationIds = <String?>[];
    final initializationTracks = <EmbyResolvedTrackBundle>[];
    final events = <String>[];
    final newSourceFailure = StateError('new source failed');
    var isPaused = false;
    final coordinator = EmbyPlaybackStateCoordinator(
      initializePlayer: (session, tracks) async {
        initializationIds.add(session.mediaSourceId);
        initializationTracks.add(tracks);
        events.add('initialize:${session.mediaSourceId}');
        if (session.mediaSourceId == 'source-a') throw newSourceFailure;
      },
      restorePlaybackState: () async {
        events.add('restore-volume:0.35');
        events.add('restore-rate:1.5');
        events.add('restore-seek:42000');
        isPaused = true;
        events.add('restore-pause');
      },
    );
    final previousPlayback = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-b',
        sources: <PlaybackMediaSource>[sourceB.source],
      ),
      reason: EmbySelectionReason.episodeExact,
      didFallback: false,
      tracks: sourceBTracks,
    );
    final newPlayback = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-a',
        sources: <PlaybackMediaSource>[sourceA.source],
      ),
      reason: EmbySelectionReason.seriesFamily,
      didFallback: true,
      tracks: sourceATracks,
    );
    await coordinator.initialize(previousPlayback);

    Object? reloadError;
    try {
      await coordinator.reload(newPlayback);
    } catch (error) {
      reloadError = error;
      events.add('throw-new-source-error');
    }

    expect(reloadError, same(newSourceFailure));
    expect(initializationIds, <String?>['source-b', 'source-a', 'source-b']);
    expect(initializationTracks, hasLength(3));
    expect(initializationTracks[0], same(sourceBTracks));
    expect(initializationTracks[1], same(sourceATracks));
    expect(initializationTracks[2], same(sourceBTracks));
    expect(coordinator.currentTrackSelection, same(sourceBTracks));
    expect(isPaused, isTrue);
    expect(events, <String>[
      'initialize:source-b',
      'initialize:source-a',
      'initialize:source-b',
      'restore-volume:0.35',
      'restore-rate:1.5',
      'restore-seek:42000',
      'restore-pause',
      'throw-new-source-error',
    ]);
  });

  test('failed rollback still reports the original reload error', () async {
    final sourceA = _descriptor('source-a', '[Baha] Episode 01');
    final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
    final sourceATracks = _tracks(audioIndex: 1, subtitleIndex: 3);
    final sourceBTracks = _tracks(audioIndex: 4, subtitleIndex: 7);
    final initializationIds = <String?>[];
    final newSourceFailure = StateError('new source failed');
    final rollbackFailure = StateError('old source restore failed');
    var sourceBAttempts = 0;
    var restorePlaybackStateCalls = 0;
    final coordinator = EmbyPlaybackStateCoordinator(
      initializePlayer: (session, tracks) async {
        initializationIds.add(session.mediaSourceId);
        if (session.mediaSourceId == 'source-a') throw newSourceFailure;
        sourceBAttempts++;
        if (sourceBAttempts > 1) throw rollbackFailure;
      },
      restorePlaybackState: () async {
        restorePlaybackStateCalls++;
      },
    );
    final previousPlayback = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-b',
        sources: <PlaybackMediaSource>[sourceB.source],
      ),
      reason: EmbySelectionReason.episodeExact,
      didFallback: false,
      tracks: sourceBTracks,
    );
    final newPlayback = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-a',
        sources: <PlaybackMediaSource>[sourceA.source],
      ),
      reason: EmbySelectionReason.seriesFamily,
      didFallback: true,
      tracks: sourceATracks,
    );
    await coordinator.initialize(previousPlayback);

    await expectLater(
      coordinator.reload(newPlayback),
      throwsA(same(newSourceFailure)),
    );

    expect(initializationIds, <String?>['source-b', 'source-a', 'source-b']);
    expect(restorePlaybackStateCalls, 0);
    expect(coordinator.currentTrackSelection, same(sourceBTracks));
  });

  test('restore-state failure still reports the original reload error',
      () async {
    final sourceA = _descriptor('source-a', '[Baha] Episode 01');
    final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
    final sourceATracks = _tracks(audioIndex: 1, subtitleIndex: 3);
    final sourceBTracks = _tracks(audioIndex: 4, subtitleIndex: 7);
    final events = <String>[];
    final newSourceFailure = StateError('new source failed');
    final restoreStateFailure = StateError('snapshot restore failed');
    final coordinator = EmbyPlaybackStateCoordinator(
      initializePlayer: (session, tracks) async {
        events.add('initialize:${session.mediaSourceId}');
        if (session.mediaSourceId == 'source-a') throw newSourceFailure;
      },
      restorePlaybackState: () async {
        events.add('restore-state');
        throw restoreStateFailure;
      },
    );
    final previousPlayback = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-b',
        sources: <PlaybackMediaSource>[sourceB.source],
      ),
      reason: EmbySelectionReason.episodeExact,
      didFallback: false,
      tracks: sourceBTracks,
    );
    final newPlayback = EmbyResolvedPlayback(
      session: _session(
        selectedId: 'source-a',
        sources: <PlaybackMediaSource>[sourceA.source],
      ),
      reason: EmbySelectionReason.seriesFamily,
      didFallback: true,
      tracks: sourceATracks,
    );
    await coordinator.initialize(previousPlayback);

    await expectLater(
      coordinator.reload(newPlayback),
      throwsA(same(newSourceFailure)),
    );

    expect(events, <String>[
      'initialize:source-b',
      'initialize:source-a',
      'initialize:source-b',
      'restore-state',
    ]);
    expect(coordinator.currentTrackSelection, same(sourceBTracks));
  });

  group('startEmbyEpisodePlayback', () {
    test('missing identity runs the default candidate through playback',
        () async {
      var preferenceStoreReads = 0;
      var playbackStarts = 0;
      dynamic capturedRequest;
      dynamic startedPlayback;
      final defaultSource = _descriptor('source-default', 'Emby Default');

      final result = await startEmbyEpisodePlayback(
        itemId: 'episode-1',
        context: null,
        sources: <EmbyMediaSourceDescriptor>[defaultSource],
        loadPreferences: (context) async {
          preferenceStoreReads++;
          return const EmbyPreferenceLayers();
        },
        resolver: DefaultEmbyMediaSelectionResolver(),
        createSession: (request) async {
          capturedRequest = request;
          return _session(
            selectedId: request.mediaSourceId,
            sources: <PlaybackMediaSource>[defaultSource.source],
          );
        },
        startPlayback: (playback) async {
          playbackStarts++;
          startedPlayback = playback;
        },
      );

      expect(preferenceStoreReads, 0);
      expect(capturedRequest.mediaSourceId, 'source-default');
      expect(playbackStarts, 1);
      expect(startedPlayback, same(result));
      expect(result.session.mediaSourceId, 'source-default');
      expect(result.reason, EmbySelectionReason.embyDefault);
    });

    test('remembered source starts directly without a chooser dependency',
        () async {
      final sourceA = _descriptor('source-a', '[Baha] Episode 01');
      final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
      final requestedSourceIds = <String>[];
      final startedSourceIds = <String?>[];

      final result = await startEmbyEpisodePlayback(
        itemId: 'episode-1',
        context: const EmbySelectionContext(
          accountKey: 'server:user',
          seriesId: 'series-1',
          episodeId: 'episode-1',
        ),
        sources: <EmbyMediaSourceDescriptor>[sourceA, sourceB],
        loadPreferences: (context) async => EmbyPreferenceLayers(
          episode: EmbyEpisodePreference(
            mediaSourceId: 'source-b',
            updatedAt: DateTime.utc(2026),
          ),
        ),
        resolver: DefaultEmbyMediaSelectionResolver(),
        createSession: (request) async {
          requestedSourceIds.add(request.mediaSourceId);
          return _session(
            selectedId: request.mediaSourceId,
            sources: <PlaybackMediaSource>[sourceA.source, sourceB.source],
          );
        },
        startPlayback: (playback) async {
          startedSourceIds.add(playback.session.mediaSourceId);
        },
      );

      expect(requestedSourceIds, <String>['source-b']);
      expect(startedSourceIds, <String?>['source-b']);
      expect(result.session.mediaSourceId, 'source-b');
      expect(result.didFallback, isFalse);
    });

    test('player-open failure continues with the next source candidate',
        () async {
      final sourceA = _descriptor('source-a', '[Baha] Episode 01');
      final sourceB = _descriptor('source-b', '[LoliHouse] Episode 01');
      final createdSourceIds = <String>[];
      final openedSourceIds = <String?>[];
      final events = <String>[];

      final result = await startEmbyEpisodePlayback(
        itemId: 'episode-1',
        context: const EmbySelectionContext(
          accountKey: 'server:user',
          seriesId: 'series-1',
          episodeId: 'episode-1',
        ),
        sources: <EmbyMediaSourceDescriptor>[sourceA, sourceB],
        loadPreferences: (context) async => EmbyPreferenceLayers(
          episode: EmbyEpisodePreference(
            mediaSourceId: 'source-b',
            updatedAt: DateTime.utc(2026),
          ),
        ),
        resolver: DefaultEmbyMediaSelectionResolver(),
        createSession: (request) async {
          createdSourceIds.add(request.mediaSourceId);
          return _session(
            selectedId: request.mediaSourceId,
            sources: <PlaybackMediaSource>[sourceA.source, sourceB.source],
          );
        },
        startPlayback: (playback) async {
          final sourceId = playback.session.mediaSourceId;
          await initializeEmbyPlayerAttempt(
            initialize: () async {
              events.add('initialize:$sourceId');
              await Future<void>.delayed(Duration.zero);
            },
            readError: () {
              events.add('read-error:$sourceId');
              return null;
            },
            hasVideo: () {
              events.add('has-video:$sourceId');
              return sourceId == 'source-a';
            },
            play: () async {
              openedSourceIds.add(sourceId);
              events.add('play:$sourceId');
            },
          );
        },
      );

      expect(createdSourceIds, <String>['source-b', 'source-a']);
      expect(openedSourceIds, <String?>['source-a']);
      expect(events, <String>[
        'initialize:source-b',
        'read-error:source-b',
        'has-video:source-b',
        'initialize:source-a',
        'read-error:source-a',
        'has-video:source-a',
        'play:source-a',
      ]);
      expect(result.session.mediaSourceId, 'source-a');
      expect(result.reason, EmbySelectionReason.embyDefault);
      expect(result.didFallback, isTrue);
    });
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
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

class _RealHttpOverrides extends HttpOverrides {}
