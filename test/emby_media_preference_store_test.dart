import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/emby_media_preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const japaneseStereo = EmbyTrackFingerprint(
    language: 'jpn',
    normalizedTitle: 'japanese stereo',
    codec: 'aac',
    channels: 2,
    isExternal: false,
  );
  const chineseAss = EmbyTrackFingerprint(
    language: 'chi',
    normalizedTitle: 'simplified chinese',
    codec: 'ass',
    isExternal: false,
  );
  final sourceA = _source('source-a', 'WEB-DL.LoliHouse');
  final sourceB = _source('source-b', 'WEB-DL.Baha');
  const contextA = EmbySelectionContext(
    accountKey: 'server-a:user-1',
    seriesId: 'series-1',
    episodeId: 'episode-1',
  );
  const contextB = EmbySelectionContext(
    accountKey: 'server-b:user-1',
    seriesId: 'series-1',
    episodeId: 'episode-1',
  );
  const nextEpisodeContext = EmbySelectionContext(
    accountKey: 'server-a:user-1',
    seriesId: 'series-1',
    episodeId: 'episode-2',
  );

  late EmbyMediaPreferenceStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
      maxEpisodeRecords: 2,
    );
  });

  test('isolates accounts and persists episode series and global layers',
      () async {
    await store.saveManualPatch(
      contextA,
      sourceB,
      EmbyManualSelectionPatch(
        source: sourceB,
        audio: const EmbyTrackPreference.track(
          japaneseStereo,
          mediaSourceId: 'source-b',
          sourceIndex: 1,
        ),
        subtitle: const EmbyTrackPreference.track(chineseAss),
      ),
    );

    final layers = await store.load(contextA);
    expect(layers.episode?.mediaSourceId, 'source-b');
    expect(layers.episode?.audio?.fingerprint, japaneseStereo);
    expect(layers.episode?.audio?.sourceIndex, 1);
    expect(layers.episode?.displayName, 'WEB-DL.Baha');
    expect(layers.series?.normalizedFullName, 'web dl baha');
    expect(layers.series?.families, contains('baha'));
    expect(layers.series?.audio?.fingerprint, japaneseStereo);
    expect(layers.global?.families, contains('baha'));
    expect(layers.global?.subtitle?.fingerprint, chineseAss);
    expect((await store.load(contextB)).isEmpty, isTrue);
  });

  test('persists subtitle off for series and global inheritance', () async {
    await store.saveManualPatch(
      contextA,
      sourceB,
      const EmbyManualSelectionPatch(
        subtitle: EmbyTrackPreference.disabled(),
      ),
    );

    final inherited = await store.load(nextEpisodeContext);
    expect(
      inherited.series?.subtitle?.mode,
      EmbyTrackPreferenceMode.disabled,
    );
    expect(
      inherited.global?.subtitle?.mode,
      EmbyTrackPreferenceMode.disabled,
    );
  });

  test(
      'patches only changed dimensions and follow default clears that dimension',
      () async {
    await store.saveManualPatch(
      contextA,
      sourceB,
      EmbyManualSelectionPatch(
        source: sourceB,
        audio: const EmbyTrackPreference.track(
          japaneseStereo,
          mediaSourceId: 'source-b',
          sourceIndex: 1,
        ),
        subtitle: const EmbyTrackPreference.track(chineseAss),
      ),
    );
    await store.saveManualPatch(
      contextA,
      sourceB,
      const EmbyManualSelectionPatch(
        subtitle: EmbyTrackPreference.disabled(),
      ),
    );

    var layers = await store.load(contextA);
    expect(layers.episode?.mediaSourceId, 'source-b');
    expect(layers.episode?.audio?.fingerprint, japaneseStereo);
    expect(layers.episode?.audio?.sourceIndex, 1);
    expect(layers.episode?.audio?.mediaSourceId, 'source-b');
    expect(layers.episode?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
    expect(layers.series?.audio?.fingerprint, japaneseStereo);
    expect(layers.series?.audio?.sourceIndex, isNull);
    expect(layers.series?.audio?.mediaSourceId, isNull);
    expect(layers.global?.audio?.fingerprint, japaneseStereo);
    expect(layers.global?.audio?.sourceIndex, isNull);
    expect(layers.global?.audio?.mediaSourceId, isNull);

    await store.saveManualPatch(
      contextA,
      sourceB,
      const EmbyManualSelectionPatch(
        audio: EmbyTrackPreference.followDefault(),
      ),
    );

    layers = await store.load(contextA);
    expect(layers.episode?.mediaSourceId, 'source-b');
    expect(layers.episode?.audio, isNull);
    expect(layers.series?.audio, isNull);
    expect(layers.global?.audio, isNull);
    expect(layers.episode?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
  });

  test(
      'does not replace a saved source when another current source patches tracks',
      () async {
    await store.saveManualPatch(
      contextA,
      sourceB,
      EmbyManualSelectionPatch(source: sourceB),
    );
    await store.saveManualPatch(
      contextA,
      sourceA,
      const EmbyManualSelectionPatch(
        subtitle: EmbyTrackPreference.disabled(),
      ),
    );

    final layers = await store.load(contextA);
    expect(layers.episode?.mediaSourceId, 'source-b');
    expect(layers.episode?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
    expect(layers.series?.normalizedFullName, 'web dl baha');
    expect(layers.series?.families, contains('baha'));
    expect(layers.series?.families, isNot(contains('lolihouse')));
    expect(layers.global?.families, contains('baha'));
    expect(layers.global?.families, isNot(contains('lolihouse')));
  });

  test('removes subtitle source binding from inherited layers', () async {
    await store.saveManualPatch(
      contextA,
      sourceB,
      const EmbyManualSelectionPatch(
        subtitle: EmbyTrackPreference.track(
          chineseAss,
          mediaSourceId: 'source-b',
          sourceIndex: 2,
        ),
      ),
    );

    final layers = await store.load(contextA);
    expect(layers.episode?.subtitle?.sourceIndex, 2);
    expect(layers.episode?.subtitle?.mediaSourceId, 'source-b');
    expect(layers.series?.subtitle?.fingerprint, chineseAss);
    expect(layers.series?.subtitle?.sourceIndex, isNull);
    expect(layers.series?.subtitle?.mediaSourceId, isNull);
    expect(layers.global?.subtitle?.fingerprint, chineseAss);
    expect(layers.global?.subtitle?.sourceIndex, isNull);
    expect(layers.global?.subtitle?.mediaSourceId, isNull);
  });

  test('rejects disabled audio preferences', () async {
    await expectLater(
      store.saveManualPatch(
        contextA,
        sourceB,
        const EmbyManualSelectionPatch(audio: EmbyTrackPreference.disabled()),
      ),
      throwsArgumentError,
    );
  });

  test('builds an account key only from complete server and user identities',
      () {
    final profileWithServerId =
        _profile(id: 'local-profile', serverId: 'server-a');
    final profileWithoutServerId = _profile(id: 'local-profile');

    expect(embyAccountKey(null, null), isNull);
    expect(embyAccountKey(profileWithoutServerId, 'user-1'),
        'local-profile:user-1');
    expect(embyAccountKey(profileWithServerId, null), isNull);
    expect(
      buildEmbySelectionContext(
        profile: null,
        userId: null,
        seriesId: 'series-1',
        episodeId: 'episode-1',
      ),
      isNull,
    );
  });

  test('ignores malformed or incompatible stored data', () async {
    SharedPreferences.setMockInitialValues({
      'emby_media_preferences_v1': '{',
    });
    final malformedStore = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
    );
    expect((await malformedStore.load(contextA)).isEmpty, isTrue);
    _expectEmptyVersionOneDocument(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    );

    SharedPreferences.setMockInitialValues({
      'emby_media_preferences_v1': '{"version":2,"accounts":{}}',
    });
    final incompatibleStore = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
    );
    expect((await incompatibleStore.load(contextA)).isEmpty, isTrue);
    _expectEmptyVersionOneDocument(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    );
  });

  test('removes source-selected inherited layers without identity or tracks',
      () async {
    SharedPreferences.setMockInitialValues({
      'emby_media_preferences_v1': '''
        {"version":1,"accounts":{"server-a:user-1":{
          "global":{"sourceSelected":true},
          "series":{"series-1":{"sourceSelected":true}},
          "episodes":{}
        }}}
      ''',
    });
    final emptyLayerStore = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
    );

    expect((await emptyLayerStore.load(contextA)).isEmpty, isTrue);
    final persisted = jsonDecode(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    ) as Map<String, dynamic>;
    expect((persisted['accounts'] as Map).containsKey(contextA.accountKey),
        isFalse);
  });

  test(
      'does not persist empty inherited layers after selecting an opaque source',
      () async {
    const opaqueSource = EmbyMediaSourceDescriptor(
      source: PlaybackMediaSource(
        id: 'source-opaque',
        name: '1080p.H265.HDR.AAC',
      ),
      displayName: '1080p.H265.HDR.AAC',
      summary: '',
      technical: EmbyTechnicalFingerprint(),
      videoTracks: [],
      audioTracks: [],
      subtitleTracks: [],
    );

    await store.saveManualPatch(
      contextA,
      opaqueSource,
      const EmbyManualSelectionPatch(source: opaqueSource),
    );

    final persisted = jsonDecode(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    ) as Map<String, dynamic>;
    final account = (persisted['accounts'] as Map)[contextA.accountKey] as Map?;
    expect(account, isNotNull);
    expect(account!['episodes'], isNot(isEmpty));
    expect(account['series'], isNull);
    expect(account['global'], isNull);
  });

  test(
      'strips episode-only source binding from inherited tracks and writes back',
      () async {
    SharedPreferences.setMockInitialValues({
      'emby_media_preferences_v1': '''
        {"version":1,"accounts":{"server-a:user-1":{
          "global":{"audio":{
            "mode":"track","fingerprint":{
              "language":"jpn","normalizedTitle":"japanese stereo",
              "codec":"aac","channels":2,"isExternal":false
            },"sourceIndex":7,"mediaSourceId":"source-b"
          }},
          "series":{"series-1":{"audio":{
            "mode":"track","fingerprint":{
              "language":"jpn","normalizedTitle":"japanese stereo",
              "codec":"aac","channels":2,"isExternal":false
            },"sourceIndex":7,"mediaSourceId":"source-b"
          }}},
          "episodes":{}
        }}}
      ''',
    });
    final inheritedStore = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
    );

    final layers = await inheritedStore.load(contextA);
    expect(layers.series?.audio?.fingerprint, japaneseStereo);
    expect(layers.series?.audio?.sourceIndex, isNull);
    expect(layers.series?.audio?.mediaSourceId, isNull);
    expect(layers.global?.audio?.fingerprint, japaneseStereo);
    expect(layers.global?.audio?.sourceIndex, isNull);
    expect(layers.global?.audio?.mediaSourceId, isNull);

    final persisted = (await SharedPreferences.getInstance())
        .getString('emby_media_preferences_v1')!;
    expect(persisted, isNot(contains('sourceIndex')));
    expect(persisted, isNot(contains('mediaSourceId')));
  });

  test('cleans invalid version one records while decoding', () async {
    SharedPreferences.setMockInitialValues({
      'emby_media_preferences_v1': '''
        {"version":1,"accounts":{"server-a:user-1":{
          "global":{},
          "series":{"series-1":{}},
          "episodes":{"episode-1":{
            "mediaSourceId":"",
            "audio":{"mode":"track","sourceIndex":-1,"mediaSourceId":"source-a"},
            "subtitle":{"mode":"track","sourceIndex":2}
          }}
        }}}
      ''',
    });
    final invalidStore = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
    );

    final layers = await invalidStore.load(contextA);
    expect(layers.isEmpty, isTrue);
    final persisted = jsonDecode(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    ) as Map<String, dynamic>;
    expect((persisted['accounts'] as Map).containsKey(contextA.accountKey),
        isFalse);
  });

  test('evicts the oldest episode record deterministically', () async {
    var tick = DateTime.utc(2026, 8, 9);
    final evictionStore = EmbyMediaPreferenceStore(
      await SharedPreferences.getInstance(),
      maxEpisodeRecords: 2,
      now: () => tick = tick.add(const Duration(seconds: 1)),
    );
    const episode1 = EmbySelectionContext(
      accountKey: 'server-a:user-1',
      seriesId: 'series-1',
      episodeId: 'episode-1',
    );
    const episode2 = EmbySelectionContext(
      accountKey: 'server-a:user-1',
      seriesId: 'series-1',
      episodeId: 'episode-2',
    );
    const episode3 = EmbySelectionContext(
      accountKey: 'server-a:user-1',
      seriesId: 'series-1',
      episodeId: 'episode-3',
    );

    await evictionStore.saveManualPatch(
      episode1,
      sourceA,
      EmbyManualSelectionPatch(source: sourceA),
    );
    await evictionStore.saveManualPatch(
      episode2,
      sourceA,
      EmbyManualSelectionPatch(source: sourceA),
    );
    await evictionStore.saveManualPatch(
      episode3,
      sourceA,
      EmbyManualSelectionPatch(source: sourceA),
    );

    expect((await evictionStore.load(episode1)).episode, isNull);
    expect(
      (await evictionStore.load(episode3)).episode?.mediaSourceId,
      'source-a',
    );
  });

  test('removes empty layer records after clearing the final manual dimension',
      () async {
    await store.saveManualPatch(
      contextA,
      sourceB,
      const EmbyManualSelectionPatch(
        subtitle: EmbyTrackPreference.disabled(),
      ),
    );
    await store.saveManualPatch(
      contextA,
      sourceB,
      const EmbyManualSelectionPatch(
        subtitle: EmbyTrackPreference.followDefault(),
      ),
    );

    expect((await store.load(contextA)).isEmpty, isTrue);
    final persisted = jsonDecode(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    ) as Map<String, dynamic>;
    final account = (persisted['accounts'] as Map)[contextA.accountKey] as Map?;
    expect(account?['episodes'], isNull);
    expect(account?['series'], isNull);
    expect(account?['global'], isNull);
  });

  test('does not persist empty inherited layers after a source patch',
      () async {
    const sourceWithoutInheritedIdentity = EmbyMediaSourceDescriptor(
      source: PlaybackMediaSource(id: 'source-without-identity'),
      displayName: ' ',
      summary: '',
      technical: EmbyTechnicalFingerprint(),
      videoTracks: [],
      audioTracks: [],
      subtitleTracks: [],
    );

    await store.saveManualPatch(
      contextA,
      sourceWithoutInheritedIdentity,
      const EmbyManualSelectionPatch(source: sourceWithoutInheritedIdentity),
    );

    final persisted = jsonDecode(
      (await SharedPreferences.getInstance())
          .getString('emby_media_preferences_v1')!,
    ) as Map<String, dynamic>;
    final account = (persisted['accounts'] as Map)[contextA.accountKey]
        as Map<String, dynamic>;
    expect(account['episodes'], isNotNull);
    expect(account['series'], isNull);
    expect(account['global'], isNull);
  });

  test('never persists playback URLs paths tokens or session identifiers',
      () async {
    final sensitiveSource = EmbyMediaSourceDescriptor(
      source: const PlaybackMediaSource(
        id: 'sensitive-source',
        name: 'WEB-DL.Baha',
        path: '/private/media/episode.mkv',
        directStreamUrl: 'https://example.invalid/direct?token=stream-token',
        transcodingUrl: 'https://example.invalid/transcode?token=stream-token',
      ),
      displayName: 'WEB-DL.Baha',
      summary: '',
      technical: const EmbyTechnicalFingerprint(height: 1080),
      videoTracks: const [],
      audioTracks: const [],
      subtitleTracks: const [],
    );

    await store.saveManualPatch(
      contextA,
      sensitiveSource,
      EmbyManualSelectionPatch(source: sensitiveSource),
    );

    final json = (await SharedPreferences.getInstance())
        .getString('emby_media_preferences_v1');
    expect(json, isNotNull);
    expect(json, isNot(contains('/private/media/episode.mkv')));
    expect(json, isNot(contains('example.invalid')));
    expect(json, isNot(contains('stream-token')));
    expect(json, isNot(contains('PlaySessionId')));
  });
}

ServerProfile _profile({required String id, String? serverId}) => ServerProfile(
      id: id,
      serverName: 'Test server',
      serverType: 'emby',
      addresses: const [],
      username: 'tester',
      serverId: serverId,
    );

EmbyMediaSourceDescriptor _source(String id, String name) =>
    EmbyMediaSourceDescriptor(
      source: PlaybackMediaSource(id: id, name: name),
      displayName: name,
      summary: '',
      technical: const EmbyTechnicalFingerprint(height: 1080),
      videoTracks: const [],
      audioTracks: const [],
      subtitleTracks: const [],
    );

void _expectEmptyVersionOneDocument(String raw) {
  final document = jsonDecode(raw) as Map<String, dynamic>;
  expect(document['version'], 1);
  expect(document['accounts'], isEmpty);
}
