import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/services/emby_media_preference_store.dart';
import 'package:nipaplay/services/emby_media_selection_resolver.dart';
import 'package:nipaplay/services/emby_player_menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPreferenceStore store;
  late _RecordingResolver resolver;
  late EmbyPlayerMenuSelectionService service;
  late EmbyMediaSourceDescriptor sourceA;
  late EmbyMediaSourceDescriptor sourceB;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _RecordingPreferenceStore(
      await SharedPreferences.getInstance(),
      layers: const EmbyPreferenceLayers(
        series: EmbySeriesPreference(
          normalizedFullName: '[lolihouse] episode 01',
        ),
      ),
    );
    resolver = _RecordingResolver(
      <String, EmbyResolvedTrackBundle>{
        'source-a': _bundle(audioIndex: 1, subtitleIndex: 2),
        'source-b': _bundle(audioIndex: 3, subtitleIndex: 4),
      },
      expectedPreferences: store.layers,
    );
    service = EmbyPlayerMenuSelectionService(
      store: store,
      resolver: resolver,
    );
    sourceA = _source('source-a', '[Baha] Episode 01');
    sourceB = _source('source-b', '[LoliHouse] Episode 01');
  });

  test('extracts the series id only from an Emby detail source key', () {
    expect(
      embySeriesIdFromSourceKey('emby:series-9:season-2'),
      'series-9',
    );
    expect(
      embySeriesIdFromSourceKey('jellyfin:series-9:season-2'),
      isNull,
    );
    expect(embySeriesIdFromSourceKey('emby::season-2'), isNull);
    expect(embySeriesIdFromSourceKey(null), isNull);
  });

  test('adapts server and native menu track shapes centrally', () {
    final source = describeEmbyMediaSource(
      const PlaybackMediaSource(
        id: 'source-tracks',
        name: '[LoliHouse] Episode 01',
        mediaStreams: <Map<String, dynamic>>[
          <String, dynamic>{
            'Type': 'Audio',
            'Index': 3,
            'Language': 'jpn',
            'Title': 'Main Audio',
            'Codec': 'EAC3',
            'Channels': 6,
            'IsExternal': false,
          },
          <String, dynamic>{
            'Type': 'Subtitle',
            'Index': 4,
            'Language': 'zho',
            'Title': 'Simplified Chinese',
            'Codec': 'ASS',
            'IsExternal': true,
          },
        ],
      ),
      ordinal: 0,
    );

    final serverAudio = preferenceForEmbyServerAudio(source, 3);
    expect(serverAudio, isNotNull);
    final selectedServerAudio = serverAudio!;
    expect(selectedServerAudio.mode, EmbyTrackPreferenceMode.track);
    expect(selectedServerAudio.sourceIndex, 3);
    expect(selectedServerAudio.mediaSourceId, 'source-tracks');
    expect(selectedServerAudio.fingerprint?.language, 'jpn');
    expect(selectedServerAudio.fingerprint?.normalizedTitle, 'main audio');
    expect(selectedServerAudio.fingerprint?.codec, 'EAC3');
    expect(selectedServerAudio.fingerprint?.channels, 6);

    final serverSubtitle = preferenceForEmbyServerSubtitle(source, 4);
    expect(serverSubtitle, isNotNull);
    final selectedServerSubtitle = serverSubtitle!;
    expect(selectedServerSubtitle.mode, EmbyTrackPreferenceMode.track);
    expect(selectedServerSubtitle.sourceIndex, 4);
    expect(selectedServerSubtitle.mediaSourceId, 'source-tracks');
    expect(selectedServerSubtitle.fingerprint?.language, 'zho');
    expect(selectedServerSubtitle.fingerprint?.isExternal, isTrue);

    final nativeAudio = preferenceForEmbyNativeAudio(
      _nativeAudio(
        language: 'jpn',
        title: 'Main Audio',
        codec: 'eac3',
        channels: 6,
      ),
    );
    expect(nativeAudio.mode, EmbyTrackPreferenceMode.track);
    expect(nativeAudio.sourceIndex, isNull);
    expect(nativeAudio.mediaSourceId, isNull);
    expect(nativeAudio.fingerprint?.language, 'jpn');
    expect(nativeAudio.fingerprint?.normalizedTitle, 'main audio');
    expect(nativeAudio.fingerprint?.codec, 'eac3');
    expect(nativeAudio.fingerprint?.channels, 6);

    final nativeSubtitle = preferenceForEmbyNativeSubtitle(
      _nativeSubtitle(
        language: 'zho',
        title: 'Simplified Chinese',
        codec: 'ass',
      ),
    );
    expect(nativeSubtitle.mode, EmbyTrackPreferenceMode.track);
    expect(nativeSubtitle.sourceIndex, isNull);
    expect(nativeSubtitle.mediaSourceId, isNull);
    expect(nativeSubtitle.fingerprint?.language, 'zho');
    expect(nativeSubtitle.fingerprint?.normalizedTitle, 'simplified chinese');
    expect(nativeSubtitle.fingerprint?.codec, 'ass');
  });

  test('rejects stale server track indexes instead of clearing preferences',
      () {
    final source = _source('source-a', '[Baha] Episode 01');

    expect(preferenceForEmbyServerAudio(source, 999), isNull);
    expect(preferenceForEmbyServerSubtitle(source, 999), isNull);
  });

  test('native adapters fall back to non-empty metadata values', () {
    final audio = preferenceForEmbyNativeAudio(
      PlayerAudioStreamInfo(
        codec: PlayerAudioCodecParams(name: '', channels: 2),
        title: '',
        language: '',
        metadata: const <String, String>{
          'title': 'Main Audio',
          'language': 'jpn',
          'codec': 'aac',
        },
        rawRepresentation: 'audio',
      ),
    );
    final subtitle = preferenceForEmbyNativeSubtitle(
      PlayerSubtitleStreamInfo(
        title: '',
        language: '',
        metadata: const <String, String>{
          'title': 'Simplified Chinese',
          'language': 'zho',
          'codec': 'ass',
        },
        rawRepresentation: 'subtitle',
      ),
    );

    expect(audio.fingerprint?.language, 'jpn');
    expect(audio.fingerprint?.normalizedTitle, 'main audio');
    expect(audio.fingerprint?.codec, 'aac');
    expect(subtitle.fingerprint?.language, 'zho');
    expect(subtitle.fingerprint?.normalizedTitle, 'simplified chinese');
    expect(subtitle.fingerprint?.codec, 'ass');
  });

  test('source switch resolves its track bundle before reloading', () async {
    final events = <String>[];

    final persisted = await runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplaySource,
      true,
      () async {
        final tracks = await service.resolveTracksForSource(
          context: _context,
          currentSource: sourceB,
        );
        events.add('reload:${sourceB.source.id}');
        expect(tracks, same(resolver.bundles['source-b']));
      },
      () async {
        events.add('persist:${sourceB.source.id}');
        return service.persistCurrentManualPatch(
          context: _context,
          currentSource: sourceB,
          patch: EmbyManualSelectionPatch(source: sourceB),
        );
      },
    );

    expect(persisted, isTrue);
    expect(resolver.sourceIds, <String>['source-b']);
    expect(resolver.preferencesSeen, <EmbyPreferenceLayers>[store.layers]);
    expect(events, <String>['reload:source-b', 'persist:source-b']);
    expect(store.reads, 1);
    expect(store.writes, 1);
    expect(store.lastWrite?.currentSource, same(sourceB));
    expect(store.lastWrite?.patch.source, same(sourceB));
    expect(store.lastWrite?.patch.audio, isNull);
    expect(store.lastWrite?.patch.subtitle, isNull);
  });

  test('successful audio selection writes one audio-only patch', () async {
    final preference = EmbyTrackPreference.track(
      sourceA.audioTracks.single.fingerprint,
      sourceIndex: sourceA.audioTracks.single.index,
      mediaSourceId: sourceA.source.id,
    );
    var applied = 0;

    final persisted = await runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplayAudio,
      true,
      () async => applied++,
      () => service.persistCurrentManualPatch(
        context: _context,
        currentSource: sourceA,
        patch: EmbyManualSelectionPatch(audio: preference),
      ),
    );

    expect(persisted, isTrue);
    expect(applied, 1);
    expect(store.writes, 1);
    expect(store.lastWrite?.context.episodeId, 'episode-1');
    expect(store.lastWrite?.context.seriesId, 'series-9');
    expect(store.lastWrite?.patch.source, isNull);
    expect(store.lastWrite?.patch.audio?.fingerprint, preference.fingerprint);
    expect(store.lastWrite?.patch.subtitle, isNull);
  });

  test('subtitle selection and subtitle off patch only subtitles', () async {
    final selectedSubtitle = EmbyTrackPreference.track(
      sourceB.subtitleTracks.single.fingerprint,
      sourceIndex: sourceB.subtitleTracks.single.index,
      mediaSourceId: sourceB.source.id,
    );

    await runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplaySubtitle,
      true,
      () async {},
      () => service.persistCurrentManualPatch(
        context: _context,
        currentSource: sourceB,
        patch: EmbyManualSelectionPatch(subtitle: selectedSubtitle),
      ),
    );

    expect(store.lastWrite?.patch.source, isNull);
    expect(store.lastWrite?.patch.audio, isNull);
    expect(store.lastWrite?.patch.subtitle?.sourceIndex, 4);
    expect(store.lastWrite?.patch.subtitle?.mediaSourceId, 'source-b');

    await runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplaySubtitle,
      true,
      () async {},
      () => service.persistCurrentManualPatch(
        context: _context,
        currentSource: sourceB,
        patch: const EmbyManualSelectionPatch(
          subtitle: EmbyTrackPreference.disabled(),
        ),
      ),
    );

    expect(store.writes, 2);
    expect(store.lastWrite?.patch.source, isNull);
    expect(store.lastWrite?.patch.audio, isNull);
    expect(
      store.lastWrite?.patch.subtitle?.mode,
      EmbyTrackPreferenceMode.disabled,
    );
  });

  test('reload or track application failure never persists a patch', () async {
    final reloadFailure = StateError('reload failed');
    await expectLater(
      runMediaServerMenuSelection(
        MediaServerMenuSurface.nipaplaySource,
        true,
        () async => throw reloadFailure,
        () => service.persistCurrentManualPatch(
          context: _context,
          currentSource: sourceB,
          patch: EmbyManualSelectionPatch(source: sourceB),
        ),
      ),
      throwsA(same(reloadFailure)),
    );
    expect(store.writes, 0);

    final applyFailure = StateError('track apply failed');
    await expectLater(
      runMediaServerMenuSelection(
        MediaServerMenuSurface.nipaplayAudio,
        true,
        () async => throw applyFailure,
        () => service.persistCurrentManualPatch(
          context: _context,
          currentSource: sourceA,
          patch: EmbyManualSelectionPatch(
            audio: EmbyTrackPreference.track(
              sourceA.audioTracks.single.fingerprint,
            ),
          ),
        ),
      ),
      throwsA(same(applyFailure)),
    );
    expect(store.writes, 0);
  });

  test('missing identity switches successfully without Store access', () async {
    EmbyResolvedTrackBundle? reloadedTracks;

    final persisted = await runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplaySource,
      true,
      () async {
        reloadedTracks = await service.resolveTracksForSource(
          context: null,
          currentSource: sourceB,
        );
      },
      () => service.persistCurrentManualPatch(
        context: null,
        currentSource: sourceB,
        patch: EmbyManualSelectionPatch(source: sourceB),
      ),
    );

    expect(persisted, isFalse);
    expect(store.reads, 0);
    expect(store.writes, 0);
    expect(resolver.sourceIds, <String>['source-b']);
    expect(reloadedTracks, same(resolver.bundles['source-b']));
  });

  test('missing identity still applies an audio switch without persistence',
      () async {
    var switchCount = 0;
    final preference = preferenceForEmbyNativeAudio(
      _nativeAudio(
        language: 'jpn',
        title: 'Main Audio',
        codec: 'aac',
        channels: 2,
      ),
    );

    final persisted = await runMediaServerMenuSelection(
      MediaServerMenuSurface.cupertinoAudio,
      true,
      () async => switchCount++,
      () => service.persistCurrentManualPatch(
        context: null,
        currentSource: sourceA,
        patch: EmbyManualSelectionPatch(audio: preference),
      ),
    );

    expect(switchCount, 1);
    expect(persisted, isFalse);
    expect(store.reads, 0);
    expect(store.writes, 0);
  });

  test('missing identity still disables subtitles without persistence',
      () async {
    var switchCount = 0;

    final persisted = await runMediaServerMenuSelection(
      MediaServerMenuSurface.cupertinoSubtitle,
      true,
      () async => switchCount++,
      () => service.persistCurrentManualPatch(
        context: null,
        currentSource: sourceA,
        patch: const EmbyManualSelectionPatch(
          subtitle: EmbyTrackPreference.disabled(),
        ),
      ),
    );

    expect(switchCount, 1);
    expect(persisted, isFalse);
    expect(store.reads, 0);
    expect(store.writes, 0);
  });

  test('all six menu entries share the production coordinator contract',
      () async {
    const surfaces = <MediaServerMenuSurface>[
      MediaServerMenuSurface.nipaplaySource,
      MediaServerMenuSurface.nipaplayAudio,
      MediaServerMenuSurface.nipaplaySubtitle,
      MediaServerMenuSurface.cupertinoSource,
      MediaServerMenuSurface.cupertinoAudio,
      MediaServerMenuSurface.cupertinoSubtitle,
    ];
    final applied = <MediaServerMenuSurface>[];
    final persisted = <MediaServerMenuSurface>[];

    for (final surface in surfaces) {
      final result = await runMediaServerMenuSelection(
        surface,
        true,
        () async => applied.add(surface),
        () async {
          persisted.add(surface);
          return true;
        },
      );
      expect(result, isTrue);
    }

    expect(applied, surfaces);
    expect(persisted, surfaces);
  });

  test('a menu surface rejects re-entry until its selection completes',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var secondApplyCalls = 0;
    var secondPersistCalls = 0;

    final first = runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplayAudio,
      true,
      () async {
        entered.complete();
        await release.future;
      },
      () async => true,
    );
    await entered.future;

    try {
      final otherSurface = await runMediaServerMenuSelection(
        MediaServerMenuSurface.cupertinoAudio,
        true,
        () async {},
        () async => true,
      );
      final second = await runMediaServerMenuSelection(
        MediaServerMenuSurface.nipaplayAudio,
        true,
        () async => secondApplyCalls++,
        () async {
          secondPersistCalls++;
          return true;
        },
      );

      expect(otherSurface, isTrue);
      expect(second, isFalse);
      expect(secondApplyCalls, 0);
      expect(secondPersistCalls, 0);
    } finally {
      if (!release.isCompleted) release.complete();
    }
    expect(await first, isTrue);

    final afterCompletion = await runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplayAudio,
      true,
      () async => secondApplyCalls++,
      () async => true,
    );
    expect(afterCompletion, isTrue);
    expect(secondApplyCalls, 1);
  });

  test('a failed menu selection releases its surface lock', () async {
    final failure = StateError('apply failed');
    await expectLater(
      runMediaServerMenuSelection(
        MediaServerMenuSurface.cupertinoSubtitle,
        true,
        () async => throw failure,
        () async => true,
      ),
      throwsA(same(failure)),
    );

    final retry = await runMediaServerMenuSelection(
      MediaServerMenuSurface.cupertinoSubtitle,
      true,
      () async {},
      () async => true,
    );
    expect(retry, isTrue);

    final persistFailure = StateError('persist failed');
    await expectLater(
      runMediaServerMenuSelection(
        MediaServerMenuSurface.cupertinoSubtitle,
        true,
        () async {},
        () async => throw persistFailure,
      ),
      throwsA(same(persistFailure)),
    );
    final retryAfterPersistFailure = await runMediaServerMenuSelection(
      MediaServerMenuSurface.cupertinoSubtitle,
      true,
      () async {},
      () async => true,
    );
    expect(retryAfterPersistFailure, isTrue);
  });
}

const _context = EmbySelectionContext(
  accountKey: 'server:user',
  seriesId: 'series-9',
  episodeId: 'episode-1',
);

EmbyMediaSourceDescriptor _source(String id, String name) {
  return describeEmbyMediaSource(
    PlaybackMediaSource(
      id: id,
      name: name,
      container: 'mkv',
      mediaStreams: const <Map<String, dynamic>>[
        <String, dynamic>{
          'Type': 'Audio',
          'Index': 3,
          'Language': 'jpn',
          'Title': 'Main Audio',
          'Codec': 'aac',
          'Channels': 2,
          'IsExternal': false,
        },
        <String, dynamic>{
          'Type': 'Subtitle',
          'Index': 4,
          'Language': 'zho',
          'Title': 'Simplified Chinese',
          'Codec': 'ass',
          'IsExternal': true,
        },
      ],
    ),
    ordinal: 0,
  );
}

EmbyResolvedTrackBundle _bundle({
  required int audioIndex,
  required int subtitleIndex,
}) {
  return EmbyResolvedTrackBundle(
    audio: EmbyResolvedTrackSelection.track(
      sourceIndex: audioIndex,
      fingerprint: const EmbyTrackFingerprint(
        language: 'jpn',
        normalizedTitle: 'main audio',
        codec: 'aac',
        channels: 2,
        isExternal: false,
      ),
    ),
    subtitle: EmbyResolvedTrackSelection.track(
      sourceIndex: subtitleIndex,
      fingerprint: const EmbyTrackFingerprint(
        language: 'zho',
        normalizedTitle: 'simplified chinese',
        codec: 'ass',
        isExternal: true,
      ),
    ),
  );
}

PlayerAudioStreamInfo _nativeAudio({
  required String language,
  required String title,
  required String codec,
  required int channels,
}) {
  return PlayerAudioStreamInfo(
    codec: PlayerAudioCodecParams(name: codec, channels: channels),
    title: title,
    language: language,
    metadata: <String, String>{
      'title': title,
      'language': language,
      'codec': codec,
      'channels': '$channels',
      'isExternal': 'false',
    },
    rawRepresentation: '$language|$title|$codec|$channels',
  );
}

PlayerSubtitleStreamInfo _nativeSubtitle({
  required String language,
  required String title,
  required String codec,
}) {
  return PlayerSubtitleStreamInfo(
    title: title,
    language: language,
    metadata: <String, String>{
      'title': title,
      'language': language,
      'codec': codec,
      'isExternal': 'false',
    },
    rawRepresentation: '$language|$title|$codec',
  );
}

class _RecordingResolver implements EmbyMediaSelectionResolver {
  _RecordingResolver(
    this.bundles, {
    required this.expectedPreferences,
  });

  final Map<String, EmbyResolvedTrackBundle> bundles;
  final EmbyPreferenceLayers expectedPreferences;
  final List<String> sourceIds = <String>[];
  final List<EmbyPreferenceLayers> preferencesSeen = <EmbyPreferenceLayers>[];

  @override
  EmbyResolutionPlan resolve({
    required List<EmbyMediaSourceDescriptor> sources,
    required EmbyPreferenceLayers preferences,
  }) {
    final source = sources.single;
    sourceIds.add(source.source.id);
    preferencesSeen.add(preferences);
    if (!preferences.isEmpty) {
      expect(preferences, same(expectedPreferences));
    }
    return EmbyResolutionPlan(
      candidates: <EmbySourceCandidate>[
        EmbySourceCandidate(
          source: source,
          reason: EmbySelectionReason.embyDefault,
          tracks: bundles[source.source.id]!,
        ),
      ],
    );
  }
}

class _StoreWrite {
  const _StoreWrite({
    required this.context,
    required this.currentSource,
    required this.patch,
  });

  final EmbySelectionContext context;
  final EmbyMediaSourceDescriptor currentSource;
  final EmbyManualSelectionPatch patch;
}

class _RecordingPreferenceStore extends EmbyMediaPreferenceStore {
  _RecordingPreferenceStore(
    super.preferences, {
    required this.layers,
  });

  final EmbyPreferenceLayers layers;
  int reads = 0;
  int writes = 0;
  _StoreWrite? lastWrite;

  @override
  Future<EmbyPreferenceLayers> load(EmbySelectionContext context) async {
    reads++;
    return layers;
  }

  @override
  Future<void> saveManualPatch(
    EmbySelectionContext context,
    EmbyMediaSourceDescriptor currentSource,
    EmbyManualSelectionPatch patch,
  ) async {
    writes++;
    lastWrite = _StoreWrite(
      context: context,
      currentSource: currentSource,
      patch: patch,
    );
  }
}
