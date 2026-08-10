import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_preference_store.dart';
import 'package:nipaplay/services/emby_media_selection_controller.dart';
import 'package:nipaplay/services/emby_media_selection_resolver.dart';
import 'package:nipaplay/services/emby_media_source_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load exposes immutable source and dirty-dimension collections',
      () async {
    final controller = await _controller();
    addTearDown(controller.dispose);

    await controller.load();

    expect(
      () => controller.state.sources.add(_descriptor('extra')),
      throwsUnsupportedError,
    );
    expect(
      () => controller.state.dirtyDimensions.add(EmbySelectionDimension.source),
      throwsUnsupportedError,
    );
  });

  test('cancel discards a source draft without persisting or reloading',
      () async {
    final store = await _TrackingStore.create();
    var loaderCalls = 0;
    final controller =
        await _controller(store: store, onLoad: () => loaderCalls++);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSource('source-b');
    controller.cancel();

    expect(controller.state.selectedSourceId, 'source-a');
    expect(controller.state.dirtyDimensions, isEmpty);
    expect(store.writes, 0);
    expect(loaderCalls, 1);
  });

  test('apply writes one dirty patch and does not reload the catalog',
      () async {
    final store = await _TrackingStore.create();
    var loaderCalls = 0;
    final controller =
        await _controller(store: store, onLoad: () => loaderCalls++);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSource('source-b');
    final applied = await controller.apply();

    expect(applied, isTrue);
    expect(store.writes, 1);
    expect(store.lastPatch?.source?.source.id, 'source-b');
    expect(store.lastPatch?.audio, isNull);
    expect(store.lastPatch?.subtitle, isNull);
    expect(loaderCalls, 1);
    expect(controller.state.dirtyDimensions, isEmpty);
  });

  test('audio apply writes only the audio dimension', () async {
    final store = await _TrackingStore.create();
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectAudio(const EmbyTrackPreference.track(_japaneseAudio));
    await controller.apply();

    expect(store.writes, 1);
    expect(store.lastPatch?.source, isNull);
    expect(store.lastPatch?.audio?.mode, EmbyTrackPreferenceMode.track);
    expect(store.lastPatch?.audio?.fingerprint, _japaneseAudio);
    expect(store.lastPatch?.subtitle, isNull);
  });

  test('subtitle apply writes only the subtitle dimension', () async {
    final store = await _TrackingStore.create();
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSubtitle(const EmbyTrackPreference.disabled());
    await controller.apply();

    expect(store.writes, 1);
    expect(store.lastPatch?.source, isNull);
    expect(store.lastPatch?.audio, isNull);
    expect(store.lastPatch?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
  });

  test('apply updates the cancel baseline to the saved selection', () async {
    final store = await _TrackingStore.create();
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSource('source-b');
    await controller.apply();
    controller.selectSource('source-a');
    controller.cancel();

    expect(store.writes, 1);
    expect(controller.state.selectedSourceId, 'source-b');
    expect(controller.state.dirtyDimensions, isEmpty);
  });

  test(
      'cancel restores source and track baselines while clearing every dirty dimension',
      () async {
    final store = await _TrackingStore.create(
      layers: EmbyPreferenceLayers(
        episode: EmbyEpisodePreference(
          mediaSourceId: 'source-a',
          audio: const EmbyTrackPreference.track(
            _japaneseAudio,
            mediaSourceId: 'source-a',
            sourceIndex: 1,
          ),
          subtitle: const EmbyTrackPreference.track(
            _chineseSubtitle,
            mediaSourceId: 'source-a',
            sourceIndex: 2,
          ),
          updatedAt: DateTime(2026, 8, 9),
        ),
      ),
    );
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSource('source-b');
    controller.selectAudio(
      const EmbyTrackPreference.track(
        _japaneseAudio,
        mediaSourceId: 'source-b',
        sourceIndex: 4,
      ),
    );
    controller.selectSubtitle(const EmbyTrackPreference.disabled());
    controller.cancel();

    expect(controller.state.selectedSourceId, 'source-a');
    expect(controller.state.audio.sourceIndex, 1);
    expect(controller.state.audio.mediaSourceId, 'source-a');
    expect(controller.state.subtitle.mode, EmbyTrackPreferenceMode.track);
    expect(controller.state.subtitle.sourceIndex, 2);
    expect(controller.state.subtitle.mediaSourceId, 'source-a');
    expect(controller.state.dirtyDimensions, isEmpty);
  });

  test('source selection re-resolves tracks but marks only source as dirty',
      () async {
    final store = await _TrackingStore.create(
      layers: EmbyPreferenceLayers(
        episode: EmbyEpisodePreference(
          mediaSourceId: 'source-a',
          audio: const EmbyTrackPreference.track(
            _japaneseAudio,
            mediaSourceId: 'source-a',
            sourceIndex: 1,
          ),
          subtitle: const EmbyTrackPreference.track(
            _chineseSubtitle,
            mediaSourceId: 'source-a',
            sourceIndex: 2,
          ),
          updatedAt: DateTime(2026, 8, 9),
        ),
      ),
    );
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSource('source-b');

    expect(controller.state.selectedSourceId, 'source-b');
    expect(controller.state.audio.mode, EmbyTrackPreferenceMode.track);
    expect(controller.state.audio.sourceIndex, 4);
    expect(controller.state.audio.mediaSourceId, 'source-b');
    expect(controller.state.subtitle.mode, EmbyTrackPreferenceMode.track);
    expect(controller.state.subtitle.sourceIndex, 5);
    expect(controller.state.subtitle.mediaSourceId, 'source-b');
    expect(
      controller.state.dirtyDimensions,
      {EmbySelectionDimension.source},
    );
  });

  test('audio and subtitle edits keep separate dirty dimensions', () async {
    final controller = await _controller();
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectAudio(const EmbyTrackPreference.track(_japaneseAudio));
    expect(controller.state.dirtyDimensions, {EmbySelectionDimension.audio});

    controller.selectSubtitle(const EmbyTrackPreference.disabled());
    expect(
      controller.state.dirtyDimensions,
      {EmbySelectionDimension.audio, EmbySelectionDimension.subtitle},
    );
  });

  test('save failure stays visible and clears the saving flag', () async {
    final error = StateError('disk unavailable');
    final store = await _TrackingStore.create(saveError: error);
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSubtitle(const EmbyTrackPreference.disabled());

    await expectLater(controller.apply(), throwsStateError);
    expect(store.writes, 1);
    expect(controller.state.isSaving, isFalse);
    expect(controller.state.error, same(error));
    expect(controller.state.dirtyDimensions, {EmbySelectionDimension.subtitle});
  });

  test('retry bypasses a failed catalog entry', () async {
    var loaderCalls = 0;
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) async {
        loaderCalls++;
        if (loaderCalls == 1) throw StateError('transient failure');
        return _sources;
      },
    );
    final controller = await _controller(catalog: catalog);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state.error, isA<StateError>());
    await controller.load(forceRefresh: true);

    expect(controller.state.error, isNull);
    expect(controller.state.sources, hasLength(2));
    expect(loaderCalls, 2);
  });

  test('a stale load cannot overwrite a newer force-refresh result', () async {
    final catalog = _QueuedCatalog();
    final controller = await _controller(catalog: catalog);
    addTearDown(controller.dispose);

    final loadA = controller.load();
    final loadB = controller.load(forceRefresh: true);
    expect(catalog.forceRefreshes, [false, true]);

    catalog.requests[1].complete([_descriptor('source-b')]);
    await loadB;
    expect(controller.state.selectedSourceId, 'source-b');

    catalog.requests[0].complete([_descriptor('source-a')]);
    await loadA;

    expect(controller.state.selectedSourceId, 'source-b');
    expect(
      controller.state.sources.map((source) => source.source.id),
      ['source-b'],
    );
  });

  test('apply freezes selectors and saves an immutable dirty snapshot',
      () async {
    final saveGate = Completer<void>();
    final store = await _TrackingStore.create(saveGate: saveGate);
    final controller = await _controller(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectSource('source-b');
    final applying = controller.apply();
    expect(controller.state.isSaving, isTrue);

    controller.selectSource('source-a');
    controller.selectAudio(const EmbyTrackPreference.track(_japaneseAudio));
    controller.selectSubtitle(const EmbyTrackPreference.disabled());

    expect(controller.state.selectedSourceId, 'source-b');
    expect(controller.state.audio.mode, EmbyTrackPreferenceMode.followDefault);
    expect(
      controller.state.subtitle.mode,
      EmbyTrackPreferenceMode.followDefault,
    );
    expect(controller.state.dirtyDimensions, {EmbySelectionDimension.source});
    expect(store.lastPatch?.source?.source.id, 'source-b');
    expect(store.lastPatch?.audio, isNull);
    expect(store.lastPatch?.subtitle, isNull);

    saveGate.complete();
    await applying;
    controller.selectAudio(const EmbyTrackPreference.track(_japaneseAudio));

    expect(controller.state.selectedSourceId, 'source-b');
    expect(controller.state.audio.mode, EmbyTrackPreferenceMode.track);
    expect(controller.state.dirtyDimensions, {EmbySelectionDimension.audio});
  });

  test('missing identity loads sources without reading or writing preferences',
      () async {
    final store = await _TrackingStore.create();
    final controller = await _controller(context: null, store: store);
    addTearDown(controller.dispose);

    await controller.load();
    final applied = await controller.apply();

    expect(controller.state.sources, isNotEmpty);
    expect(controller.state.canPersist, isFalse);
    expect(applied, isFalse);
    expect(controller.state.error, isA<StateError>());
    expect(store.reads, 0);
    expect(store.writes, 0);
  });
}

const _japaneseAudio = EmbyTrackFingerprint(
  language: 'jpn',
  normalizedTitle: 'main',
  codec: 'aac',
  channels: 2,
  isExternal: false,
);

const _chineseSubtitle = EmbyTrackFingerprint(
  language: 'chi',
  normalizedTitle: 'simplified',
  codec: 'ass',
  isExternal: false,
);

final _sources = <PlaybackMediaSource>[
  const PlaybackMediaSource(
    id: 'source-a',
    name: 'WEB-DL.Baha',
    mediaStreams: const [
      {'Index': 0, 'Type': 'Video', 'Codec': 'h264', 'Height': 1080},
      {
        'Index': 1,
        'Type': 'Audio',
        'Language': 'jpn',
        'Title': 'Main',
        'Codec': 'aac',
        'Channels': 2,
      },
      {
        'Index': 2,
        'Type': 'Subtitle',
        'Language': 'chi',
        'Title': 'Simplified',
        'Codec': 'ass',
      },
    ],
  ),
  const PlaybackMediaSource(
    id: 'source-b',
    name: 'WEB-DL.LoliHouse',
    mediaStreams: const [
      {'Index': 0, 'Type': 'Video', 'Codec': 'h264', 'Height': 1080},
      {
        'Index': 4,
        'Type': 'Audio',
        'Language': 'jpn',
        'Title': 'Main',
        'Codec': 'aac',
        'Channels': 2,
      },
      {
        'Index': 5,
        'Type': 'Subtitle',
        'Language': 'chi',
        'Title': 'Simplified',
        'Codec': 'ass',
      },
    ],
  ),
];

Future<DefaultEmbyMediaSelectionController> _controller({
  _TrackingStore? store,
  EmbyMediaSourceCatalog? catalog,
  EmbySelectionContext? context = const EmbySelectionContext(
    accountKey: 'server-a:user-a',
    seriesId: 'series-1',
    episodeId: 'episode-1',
  ),
  void Function()? onLoad,
}) async {
  final resolvedStore = store ?? await _TrackingStore.create();
  final resolvedCatalog = catalog ??
      CachedEmbyMediaSourceCatalog(
        loader: (_) async {
          onLoad?.call();
          return _sources;
        },
      );
  return DefaultEmbyMediaSelectionController(
    catalog: resolvedCatalog,
    store: resolvedStore,
    resolver: DefaultEmbyMediaSelectionResolver(),
    context: context,
    catalogScopeKey: context?.accountKey ?? 'emby-session',
    itemId: 'episode-1',
  );
}

EmbyMediaSourceDescriptor _descriptor(String id) => EmbyMediaSourceDescriptor(
      source: PlaybackMediaSource(id: id),
      displayName: id,
      summary: '',
      technical: const EmbyTechnicalFingerprint(),
      videoTracks: const [],
      audioTracks: const [],
      subtitleTracks: const [],
    );

class _TrackingStore extends EmbyMediaPreferenceStore {
  _TrackingStore(
    super.preferences, {
    required this.layers,
    this.saveError,
    this.saveGate,
  });

  static Future<_TrackingStore> create({
    EmbyPreferenceLayers layers = const EmbyPreferenceLayers(),
    Object? saveError,
    Completer<void>? saveGate,
  }) async {
    SharedPreferences.setMockInitialValues({});
    return _TrackingStore(
      await SharedPreferences.getInstance(),
      layers: layers,
      saveError: saveError,
      saveGate: saveGate,
    );
  }

  final EmbyPreferenceLayers layers;
  final Object? saveError;
  final Completer<void>? saveGate;
  int reads = 0;
  int writes = 0;
  EmbyManualSelectionPatch? lastPatch;

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
    lastPatch = patch;
    if (saveError != null) throw saveError!;
    await saveGate?.future;
  }
}

class _QueuedCatalog implements EmbyMediaSourceCatalog {
  final requests = <Completer<List<EmbyMediaSourceDescriptor>>>[];
  final forceRefreshes = <bool>[];

  @override
  Future<List<EmbyMediaSourceDescriptor>> load(
    String cacheScopeKey,
    String itemId, {
    bool forceRefresh = false,
  }) {
    forceRefreshes.add(forceRefresh);
    final request = Completer<List<EmbyMediaSourceDescriptor>>();
    requests.add(request);
    return request.future;
  }

  @override
  void clear() {}

  @override
  void invalidateScope(String cacheScopeKey) {}
}
