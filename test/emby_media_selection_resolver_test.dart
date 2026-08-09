import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_selection_resolver.dart';

void main() {
  const japaneseStereo = EmbyTrackFingerprint(
    language: 'jpn',
    normalizedTitle: 'japanese stereo',
    codec: 'aac',
    channels: 2,
    isExternal: false,
  );

  final resolver = DefaultEmbyMediaSelectionResolver();

  test('orders exact episode, global, series, technical and default', () {
    final sources = [
      _source(id: 'episode', name: 'WEB-DL.Crunchyroll', height: 2160),
      _source(id: 'series', name: 'WEB-DL.LoliHouse', height: 720),
      _source(id: 'family', name: 'WEB-DL.Baha', height: 480),
      _source(id: 'technical', name: 'RAW.Custom', height: 1080),
      _source(id: 'default', name: 'RAW.Default', height: 360),
    ];

    final plan = resolver.resolve(
      sources: sources,
      preferences: EmbyPreferenceLayers(
        episode: EmbyEpisodePreference(
          mediaSourceId: 'episode',
          updatedAt: DateTime(2026, 8, 9),
        ),
        series: EmbySeriesPreference(normalizedFullName: 'web dl lolihouse'),
        global: EmbyGlobalPreference(
          families: {'baha'},
          technical: EmbyTechnicalFingerprint(height: 1080),
        ),
      ),
    );

    expect(
      plan.candidates.map((candidate) => candidate.reason),
      [
        EmbySelectionReason.episodeExact,
        EmbySelectionReason.globalFamily,
        EmbySelectionReason.technical,
        EmbySelectionReason.seriesFullName,
        EmbySelectionReason.embyDefault,
      ],
    );
    expect(
      plan.candidates.map((candidate) => candidate.source.source.id),
      ['episode', 'family', 'technical', 'series', 'default'],
    );
  });

  test('uses an exact stream index only for the media source that owns it', () {
    final layers = EmbyPreferenceLayers(
      episode: EmbyEpisodePreference(
        audio: const EmbyTrackPreference.track(
          japaneseStereo,
          mediaSourceId: 'source-b',
          sourceIndex: 7,
        ),
        updatedAt: DateTime(2026, 8, 9),
      ),
    );
    final sourceB = _source(
      id: 'source-b',
      name: 'WEB-DL.Baha',
      audioTracks: [_audio(index: 7, fingerprint: japaneseStereo)],
    );
    final sourceA = _source(
      id: 'source-a',
      name: 'WEB-DL.LoliHouse',
      audioTracks: [_audio(index: 1, fingerprint: japaneseStereo)],
    );

    final sameSource =
        resolver.resolve(sources: [sourceB], preferences: layers);
    final otherSource =
        resolver.resolve(sources: [sourceA], preferences: layers);

    expect(sameSource.candidates.single.tracks.audio.sourceIndex, 7);
    expect(otherSource.candidates.single.tracks.audio.sourceIndex, 1);
    expect(otherSource.candidates.single.tracks.audio.sourceIndex, isNot(7));
  });

  test('binds each fallback candidate to its own remapped track bundle', () {
    final sourceB = _source(
      id: 'source-b',
      name: 'WEB-DL.Baha',
      height: 720,
      audioTracks: [_audio(index: 7, fingerprint: japaneseStereo)],
    );
    final sourceA = _source(
      id: 'source-a',
      name: 'RAW.Custom',
      height: 1080,
      audioTracks: [_audio(index: 1, fingerprint: japaneseStereo)],
    );

    final plan = resolver.resolve(
      sources: [sourceB, sourceA],
      preferences: EmbyPreferenceLayers(
        episode: EmbyEpisodePreference(
          mediaSourceId: 'source-b',
          audio: const EmbyTrackPreference.track(
            japaneseStereo,
            mediaSourceId: 'source-b',
            sourceIndex: 7,
          ),
          updatedAt: DateTime(2026, 8, 9),
        ),
        global: const EmbyGlobalPreference(
          technical: EmbyTechnicalFingerprint(height: 1080),
        ),
      ),
    );

    expect(plan.candidates.map((candidate) => candidate.reason), [
      EmbySelectionReason.episodeExact,
      EmbySelectionReason.technical,
    ]);
    expect(plan.candidates[0].source.source.id, 'source-b');
    expect(plan.candidates[0].tracks.audio.sourceIndex, 7);
    expect(plan.candidates[1].source.source.id, 'source-a');
    expect(plan.candidates[1].tracks.audio.sourceIndex, 1);
  });

  test('prefers global technical settings before series fallback', () {
    final plan = resolver.resolve(
      sources: [
        _source(id: 'global', name: 'RAW.Global', height: 2160),
        _source(id: 'series', name: 'RAW.Series', height: 1080),
      ],
      preferences: const EmbyPreferenceLayers(
        series: EmbySeriesPreference(
          technical: EmbyTechnicalFingerprint(height: 1080),
        ),
        global: EmbyGlobalPreference(
          technical: EmbyTechnicalFingerprint(height: 2160),
        ),
      ),
    );

    expect(plan.candidates.first.source.source.id, 'global');
    expect(plan.candidates.first.reason, EmbySelectionReason.technical);
  });

  test('ranks global family candidates only with global preferences', () {
    final plan = resolver.resolve(
      sources: [
        _source(
          id: 'series-shaped',
          name: 'WEB-DL.Baha.1080p',
          height: 1080,
        ),
        _source(
          id: 'global-shaped',
          name: 'WEB-DL.Baha.2160p',
          height: 2160,
        ),
      ],
      preferences: const EmbyPreferenceLayers(
        global: EmbyGlobalPreference(
          families: {'baha'},
          technical: EmbyTechnicalFingerprint(height: 2160),
        ),
        series: EmbySeriesPreference(
          families: {'baha'},
          technical: EmbyTechnicalFingerprint(height: 1080),
        ),
      ),
    );

    expect(plan.candidates.first.source.source.id, 'global-shaped');
    expect(plan.candidates.first.reason, EmbySelectionReason.globalFamily);
  });

  test('uses series technical settings when global criteria do not match', () {
    final plan = resolver.resolve(
      sources: [
        _source(id: 'default', name: 'RAW.Default', height: 720),
        _source(id: 'series', name: 'RAW.Series', height: 1080),
      ],
      preferences: const EmbyPreferenceLayers(
        global: EmbyGlobalPreference(
          technical: EmbyTechnicalFingerprint(height: 2160),
        ),
        series: EmbySeriesPreference(
          technical: EmbyTechnicalFingerprint(height: 1080),
        ),
      ),
    );

    expect(plan.candidates.first.source.source.id, 'series');
    expect(plan.candidates.first.reason, EmbySelectionReason.technical);
  });

  test('falls through unmatched episode and global tracks to series', () {
    const unavailable = EmbyTrackFingerprint(
      language: 'eng',
      normalizedTitle: 'commentary',
      codec: 'ac3',
      channels: 6,
      isExternal: false,
    );
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      audioTracks: [_audio(index: 4, fingerprint: japaneseStereo)],
    );

    final tracks = resolver
        .resolve(
          sources: [source],
          preferences: EmbyPreferenceLayers(
            episode: EmbyEpisodePreference(
              audio: const EmbyTrackPreference.track(unavailable),
              updatedAt: DateTime(2026, 8, 9),
            ),
            global: const EmbyGlobalPreference(
              audio: EmbyTrackPreference.track(unavailable),
            ),
            series: const EmbySeriesPreference(
              audio: EmbyTrackPreference.track(japaneseStereo),
            ),
          ),
        )
        .candidates
        .single
        .tracks;

    expect(tracks.audio.sourceIndex, 4);
  });

  test('uses a matching global track before the series track', () {
    const seriesAudio = EmbyTrackFingerprint(
      language: 'jpn',
      normalizedTitle: 'commentary',
      codec: 'aac',
      channels: 2,
      isExternal: false,
    );
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      audioTracks: [
        _audio(index: 1, fingerprint: seriesAudio),
        _audio(index: 2, fingerprint: japaneseStereo),
      ],
    );

    final tracks = resolver
        .resolve(
          sources: [source],
          preferences: const EmbyPreferenceLayers(
            global: EmbyGlobalPreference(
              audio: EmbyTrackPreference.track(japaneseStereo),
            ),
            series: EmbySeriesPreference(
              audio: EmbyTrackPreference.track(seriesAudio),
            ),
          ),
        )
        .candidates
        .single
        .tracks;

    expect(tracks.audio.sourceIndex, 2);
  });

  test('ranks family variants by matching features and technical details', () {
    final plan = resolver.resolve(
      sources: [
        _source(
          id: 'other-variant',
          name: 'WEB-DL.Baha.\u7b80\u4f53\u5185\u5d4c.720p',
          height: 720,
        ),
        _source(
          id: 'preferred-variant',
          name: 'WEB-DL.Baha.\u7b80\u7e41\u65e5\u5185\u5c01.1080p',
          height: 1080,
        ),
      ],
      preferences: const EmbyPreferenceLayers(
        series: EmbySeriesPreference(
          families: {'baha'},
          features: {'\u7b80\u7e41\u65e5\u5185\u5c01'},
          technical: EmbyTechnicalFingerprint(height: 1080),
        ),
      ),
    );

    expect(
      plan.candidates.map((candidate) => candidate.source.source.id),
      ['preferred-variant', 'other-variant'],
    );
  });

  test('deduplicates a shared media source id at its highest priority', () {
    final plan = resolver.resolve(
      sources: [
        _source(id: 'shared', name: 'WEB-DL.Baha'),
        _source(id: 'shared', name: 'WEB-DL.Baha mirror'),
        _source(id: 'fallback', name: 'RAW.Default'),
      ],
      preferences: EmbyPreferenceLayers(
        episode: EmbyEpisodePreference(
          mediaSourceId: 'shared',
          updatedAt: DateTime(2026, 8, 9),
        ),
        global: const EmbyGlobalPreference(families: {'baha'}),
      ),
    );

    expect(
      plan.candidates.map((candidate) => candidate.source.source.id),
      ['shared', 'fallback'],
    );
    expect(
      plan.candidates.map((candidate) => candidate.reason),
      [EmbySelectionReason.episodeExact, EmbySelectionReason.embyDefault],
    );
  });

  test('remaps subtitle independently by fingerprint across media sources', () {
    const simplifiedChinese = EmbyTrackFingerprint(
      language: 'chi',
      normalizedTitle: 'simplified chinese',
      codec: 'ass',
      isExternal: false,
    );
    final source = _source(
      id: 'source-a',
      name: 'WEB-DL.LoliHouse',
      subtitleTracks: [_subtitle(index: 4, fingerprint: simplifiedChinese)],
    );

    final plan = resolver.resolve(
      sources: [source],
      preferences: EmbyPreferenceLayers(
        episode: EmbyEpisodePreference(
          subtitle: const EmbyTrackPreference.track(
            simplifiedChinese,
            mediaSourceId: 'source-b',
            sourceIndex: 9,
          ),
          updatedAt: DateTime(2026, 8, 9),
        ),
      ),
    );

    final tracks = plan.candidates.single.tracks;
    expect(tracks.audio.mode, EmbyResolvedTrackMode.followDefault);
    expect(tracks.subtitle.mode, EmbyResolvedTrackMode.track);
    expect(tracks.subtitle.sourceIndex, 4);
    expect(tracks.subtitle.sourceIndex, isNot(9));
  });

  test(
      'remaps audio by language and title while subtitles use their own language match',
      () {
    const preferredAudio = EmbyTrackFingerprint(
      language: 'jpn',
      normalizedTitle: 'main',
      codec: 'flac',
      channels: 2,
      isExternal: false,
    );
    const preferredSubtitle = EmbyTrackFingerprint(
      language: 'chi',
      normalizedTitle: 'traditional',
      codec: 'ass',
      isExternal: false,
    );
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      audioTracks: [
        _audio(
          index: 1,
          fingerprint: const EmbyTrackFingerprint(
            language: 'jpn',
            normalizedTitle: 'commentary',
            codec: 'aac',
            channels: 2,
            isExternal: false,
          ),
        ),
        _audio(
          index: 2,
          fingerprint: const EmbyTrackFingerprint(
            language: 'jpn',
            normalizedTitle: 'main',
            codec: 'aac',
            channels: 2,
            isExternal: false,
          ),
        ),
      ],
      subtitleTracks: [
        _subtitle(
          index: 3,
          fingerprint: const EmbyTrackFingerprint(
            language: 'chi',
            normalizedTitle: 'simplified',
            codec: 'ass',
            isExternal: false,
          ),
        ),
      ],
    );

    final tracks = resolver
        .resolve(
          sources: [source],
          preferences: EmbyPreferenceLayers(
            episode: EmbyEpisodePreference(
              audio: const EmbyTrackPreference.track(preferredAudio),
              subtitle: const EmbyTrackPreference.track(preferredSubtitle),
              updatedAt: DateTime(2026, 8, 9),
            ),
          ),
        )
        .candidates
        .single
        .tracks;

    expect(tracks.audio.sourceIndex, 2);
    expect(tracks.subtitle.sourceIndex, 3);
  });

  test('falls back by audio technical details and subtitle kind plus codec',
      () {
    const preferredAudio = EmbyTrackFingerprint(
      language: 'jpn',
      normalizedTitle: 'main',
      codec: 'eac3',
      channels: 6,
      isExternal: false,
    );
    const unavailableSubtitle = EmbyTrackFingerprint(
      language: 'eng',
      normalizedTitle: 'english',
      codec: 'ass',
      isExternal: false,
    );
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      audioTracks: [
        _audio(
          index: 5,
          fingerprint: const EmbyTrackFingerprint(
            language: 'und',
            normalizedTitle: 'surround',
            codec: 'eac3',
            channels: 6,
            isExternal: false,
          ),
        ),
      ],
      subtitleTracks: [
        _subtitle(
          index: 9,
          fingerprint: const EmbyTrackFingerprint(
            language: 'chi',
            normalizedTitle: 'simplified',
            codec: 'ass',
            isExternal: false,
          ),
        ),
      ],
    );

    final tracks = resolver
        .resolve(
          sources: [source],
          preferences: EmbyPreferenceLayers(
            episode: EmbyEpisodePreference(
              audio: const EmbyTrackPreference.track(preferredAudio),
              subtitle: const EmbyTrackPreference.track(unavailableSubtitle),
              updatedAt: DateTime(2026, 8, 9),
            ),
          ),
        )
        .candidates
        .single
        .tracks;

    expect(tracks.audio.sourceIndex, 5);
    expect(tracks.subtitle.mode, EmbyResolvedTrackMode.track);
    expect(tracks.subtitle.sourceIndex, 9);
  });

  test('subtitle technical fallback keeps embedded and external distinct', () {
    const preferred = EmbyTrackFingerprint(
      language: 'eng',
      normalizedTitle: 'english',
      codec: 'ass',
      isExternal: true,
    );
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      subtitleTracks: [
        _subtitle(
          index: 3,
          fingerprint: const EmbyTrackFingerprint(
            language: 'chi',
            normalizedTitle: 'embedded',
            codec: 'ass',
            isExternal: false,
          ),
        ),
        _subtitle(
          index: 8,
          fingerprint: const EmbyTrackFingerprint(
            language: 'chi',
            normalizedTitle: 'external',
            codec: 'ass',
            isExternal: true,
          ),
        ),
      ],
    );

    final subtitle = resolver
        .resolve(
          sources: [source],
          preferences: const EmbyPreferenceLayers(
            global: EmbyGlobalPreference(
              subtitle: EmbyTrackPreference.track(preferred),
            ),
          ),
        )
        .candidates
        .single
        .tracks
        .subtitle;

    expect(subtitle.sourceIndex, 8);
  });

  test('audio technical fallback ignores external state by itself', () {
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      audioTracks: [
        _audio(
          index: 4,
          fingerprint: const EmbyTrackFingerprint(isExternal: false),
        ),
      ],
    );

    final audio = resolver
        .resolve(
          sources: [source],
          preferences: const EmbyPreferenceLayers(
            global: EmbyGlobalPreference(
              audio: EmbyTrackPreference.track(
                EmbyTrackFingerprint(isExternal: false),
              ),
            ),
          ),
        )
        .candidates
        .single
        .tracks
        .audio;

    expect(audio.mode, EmbyResolvedTrackMode.followDefault);
  });

  test('incomplete global subtitle fingerprint falls through to series', () {
    const incompleteGlobal = EmbyTrackFingerprint(
      language: 'eng',
      normalizedTitle: 'english',
      isExternal: true,
    );
    const seriesSubtitle = EmbyTrackFingerprint(
      language: 'chi',
      normalizedTitle: 'traditional',
      codec: 'ass',
      isExternal: true,
    );
    final source = _source(
      id: 'candidate',
      name: 'WEB-DL.Baha',
      subtitleTracks: [
        _subtitle(
          index: 7,
          fingerprint: const EmbyTrackFingerprint(
            language: 'chi',
            normalizedTitle: 'simplified',
            codec: 'srt',
            isExternal: true,
          ),
        ),
        _subtitle(index: 8, fingerprint: seriesSubtitle),
      ],
    );

    final subtitle = resolver
        .resolve(
          sources: [source],
          preferences: const EmbyPreferenceLayers(
            global: EmbyGlobalPreference(
              subtitle: EmbyTrackPreference.track(incompleteGlobal),
            ),
            series: EmbySeriesPreference(
              subtitle: EmbyTrackPreference.track(seriesSubtitle),
            ),
          ),
        )
        .candidates
        .single
        .tracks
        .subtitle;

    expect(subtitle.sourceIndex, 8);
  });

  test(
      'ranks a source with more matching families ahead of a partial family match',
      () {
    final plan = resolver.resolve(
      sources: [
        _source(id: 'one-family', name: 'WEB-DL.LoliHouse'),
        _source(id: 'two-families', name: 'WEB-DL.LoliHouse.Baha'),
      ],
      preferences: const EmbyPreferenceLayers(
        series: EmbySeriesPreference(families: {'lolihouse', 'baha'}),
      ),
    );

    expect(
      plan.candidates.map((candidate) => candidate.source.source.id),
      ['two-families', 'one-family'],
    );
  });

  test(
      'keeps Emby first source as the default fallback outside similarity ranking',
      () {
    final plan = resolver.resolve(
      sources: [
        _source(
          id: 'emby-default',
          name: 'WEB-DL.Default.\u7b80\u4f53\u5185\u5d4c',
        ),
        _source(
          id: 'preferred',
          name: 'WEB-DL.Preferred.\u7b80\u7e41\u65e5\u5185\u5c01',
        ),
      ],
      preferences: const EmbyPreferenceLayers(
        series: EmbySeriesPreference(
          features: {'\u7b80\u7e41\u65e5\u5185\u5c01'},
        ),
      ),
    );

    expect(
      plan.candidates.map((candidate) => candidate.source.source.id),
      ['emby-default', 'preferred'],
    );
    expect(plan.candidates.first.reason, EmbySelectionReason.embyDefault);
  });

  test(
      'ranks technical candidates by partial similarity instead of requiring an exact match',
      () {
    final plan = resolver.resolve(
      sources: [
        _source(
          id: 'distant',
          name: 'RAW.Distant',
          height: 720,
          technical: const EmbyTechnicalFingerprint(
            height: 720,
            videoCodec: 'av1',
            hdr: 'HLG',
            container: 'mkv',
          ),
        ),
        _source(
          id: 'closest',
          name: 'RAW.Closest',
          height: 1080,
          technical: const EmbyTechnicalFingerprint(
            height: 1080,
            videoCodec: 'h265',
            hdr: 'HDR10',
            container: 'mp4',
          ),
        ),
      ],
      preferences: const EmbyPreferenceLayers(
        global: EmbyGlobalPreference(
          technical: EmbyTechnicalFingerprint(
            height: 1080,
            videoCodec: 'h265',
            hdr: 'HDR10',
            container: 'mkv',
          ),
        ),
      ),
    );

    expect(plan.candidates.first.source.source.id, 'closest');
    expect(plan.candidates.first.reason, EmbySelectionReason.technical);
  });
}

EmbyMediaSourceDescriptor _source({
  required String id,
  required String name,
  int? height,
  EmbyTechnicalFingerprint? technical,
  List<EmbyAudioTrackDescriptor> audioTracks = const [],
  List<EmbySubtitleTrackDescriptor> subtitleTracks = const [],
}) {
  return EmbyMediaSourceDescriptor(
    source: PlaybackMediaSource(id: id, name: name),
    displayName: name,
    summary: '',
    technical: technical ?? EmbyTechnicalFingerprint(height: height),
    videoTracks: const [],
    audioTracks: audioTracks,
    subtitleTracks: subtitleTracks,
  );
}

EmbyAudioTrackDescriptor _audio({
  required int index,
  required EmbyTrackFingerprint fingerprint,
}) {
  return EmbyAudioTrackDescriptor(
    index: index,
    language: fingerprint.language,
    title: 'Japanese Stereo',
    codec: fingerprint.codec,
    channels: fingerprint.channels,
    isDefault: false,
    fingerprint: fingerprint,
  );
}

EmbySubtitleTrackDescriptor _subtitle({
  required int index,
  required EmbyTrackFingerprint fingerprint,
}) {
  return EmbySubtitleTrackDescriptor(
    index: index,
    language: fingerprint.language,
    title: 'Simplified Chinese',
    codec: fingerprint.codec,
    isExternal: fingerprint.isExternal ?? false,
    isDefault: false,
    isForced: false,
    fingerprint: fingerprint,
  );
}
