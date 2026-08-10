import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/services/emby_track_application.dart';

void main() {
  group('resolveNativeEmbyTracks', () {
    test('remaps Emby stream indexes to native tracks by fingerprint', () {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.track(
          sourceIndex: 7,
          fingerprint: EmbyTrackFingerprint(
            language: 'jpn',
            normalizedTitle: 'main audio',
            codec: 'aac',
            channels: 2,
            isExternal: false,
          ),
        ),
        subtitle: EmbyResolvedTrackSelection.track(
          sourceIndex: 9,
          fingerprint: EmbyTrackFingerprint(
            language: 'zho',
            normalizedTitle: 'simplified chinese',
            codec: 'ass',
            isExternal: false,
          ),
        ),
      );
      final mediaInfo = PlayerMediaInfo(
        duration: 1000,
        audio: <PlayerAudioStreamInfo>[
          _audio(language: 'eng', title: 'Main Audio', codec: 'aac'),
          _audio(language: 'jpn', title: 'Main Audio', codec: 'aac'),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          _subtitle(
            language: 'zho',
            title: 'Simplified Chinese',
            codec: 'ass',
          ),
          _subtitle(language: 'eng', title: 'English', codec: 'srt'),
        ],
      );

      final result = resolveNativeEmbyTracks(selection, mediaInfo);

      expect(result.audioIndex, 1);
      expect(result.subtitleIndex, 0);
      expect(result.disableSubtitles, isFalse);
      expect(
        result.externalSubtitle.kind,
        EmbyExternalSubtitleActionKind.disabled,
      );
      expect(result.audioIndex, isNot(selection.audio.sourceIndex));
      expect(result.subtitleIndex, isNot(selection.subtitle.sourceIndex));
    });

    test('audio and subtitle fallbacks are resolved independently', () {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.track(
          sourceIndex: 4,
          fingerprint: EmbyTrackFingerprint(
            language: 'jpn',
            normalizedTitle: 'main audio',
            codec: 'flac',
            channels: 6,
            isExternal: false,
          ),
        ),
        subtitle: EmbyResolvedTrackSelection.track(
          sourceIndex: 5,
          fingerprint: EmbyTrackFingerprint(
            language: 'eng',
            normalizedTitle: 'signs',
            codec: 'ass',
            isExternal: false,
          ),
        ),
      );
      final mediaInfo = PlayerMediaInfo(
        duration: 1000,
        audio: <PlayerAudioStreamInfo>[
          _audio(language: 'eng', title: 'Main Audio', codec: 'aac'),
          _audio(
            language: 'jpn',
            title: 'Main Audio',
            codec: 'eac3',
          ),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          _subtitle(language: 'zho', title: 'Signs', codec: 'ass'),
        ],
      );

      final result = resolveNativeEmbyTracks(selection, mediaInfo);

      expect(result.audioIndex, 1,
          reason: 'language and title are a stable fallback');
      expect(result.subtitleIndex, isNull,
          reason: 'an unmatched subtitle must leave the player default alone');
      expect(result.disableSubtitles, isFalse);
    });

    test('subtitle can fall back by language while audio stays at default', () {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.track(
          sourceIndex: 2,
          fingerprint: EmbyTrackFingerprint(
            language: 'fra',
            normalizedTitle: 'commentary',
            codec: 'aac',
            channels: 2,
            isExternal: false,
          ),
        ),
        subtitle: EmbyResolvedTrackSelection.track(
          sourceIndex: 8,
          fingerprint: EmbyTrackFingerprint(
            language: 'zho',
            normalizedTitle: 'traditional',
            codec: 'ass',
            isExternal: false,
          ),
        ),
      );
      final mediaInfo = PlayerMediaInfo(
        duration: 1000,
        audio: <PlayerAudioStreamInfo>[
          _audio(language: 'jpn', title: 'Main Audio', codec: 'aac'),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          _subtitle(language: 'eng', title: 'English', codec: 'srt'),
          _subtitle(language: 'zho', title: 'Simplified', codec: 'ass'),
        ],
      );

      final result = resolveNativeEmbyTracks(selection, mediaInfo);

      expect(result.audioIndex, isNull);
      expect(result.subtitleIndex, 1);
      expect(result.disableSubtitles, isFalse);
    });

    test('audio falls back by channel count and codec', () {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.track(
          sourceIndex: 6,
          fingerprint: EmbyTrackFingerprint(
            language: 'jpn',
            normalizedTitle: 'main audio',
            codec: 'eac3',
            channels: 6,
            isExternal: false,
          ),
        ),
        subtitle: EmbyResolvedTrackSelection.followDefault(),
      );
      final mediaInfo = PlayerMediaInfo(
        duration: 1000,
        audio: <PlayerAudioStreamInfo>[
          _audio(
            language: 'eng',
            title: 'Commentary',
            codec: 'eac3',
            channels: 2,
          ),
          _audio(
            language: 'und',
            title: 'Surround',
            codec: 'eac3',
            channels: 6,
          ),
        ],
      );

      final result = resolveNativeEmbyTracks(selection, mediaInfo);

      expect(result.audioIndex, 1);
      expect(result.subtitleIndex, isNull);
    });

    test('follow default leaves native tracks and external behavior unchanged',
        () {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.followDefault(),
        subtitle: EmbyResolvedTrackSelection.followDefault(),
      );
      final mediaInfo = PlayerMediaInfo(
        duration: 1000,
        audio: <PlayerAudioStreamInfo>[
          _audio(language: 'jpn', title: 'Main Audio', codec: 'aac'),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          _subtitle(language: 'zho', title: 'Chinese', codec: 'ass'),
        ],
      );

      final result = resolveNativeEmbyTracks(selection, mediaInfo);

      expect(result.audioIndex, isNull);
      expect(result.subtitleIndex, isNull);
      expect(result.disableSubtitles, isFalse);
      expect(
        result.externalSubtitle.kind,
        EmbyExternalSubtitleActionKind.followDefault,
      );
    });

    test('selected external subtitle is not mapped as an embedded track', () {
      const selection = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.followDefault(),
        subtitle: EmbyResolvedTrackSelection.track(
          sourceIndex: 4,
          fingerprint: EmbyTrackFingerprint(
            language: 'zho',
            normalizedTitle: 'simplified',
            codec: 'ASS',
            isExternal: true,
          ),
        ),
      );

      final result = resolveNativeEmbyTracks(
        selection,
        PlayerMediaInfo(
          duration: 1000,
          subtitle: <PlayerSubtitleStreamInfo>[
            _subtitle(language: 'zho', title: 'Simplified', codec: 'ass'),
          ],
        ),
      );

      expect(result.subtitleIndex, isNull);
      expect(result.disableSubtitles, isFalse);
      expect(
          result.externalSubtitle.kind, EmbyExternalSubtitleActionKind.select);
      expect(result.externalSubtitle.streamIndex, 4);
      expect(result.externalSubtitle.codec, 'ass');
    });
  });

  group('applyEmbyResolvedTracksAfterOpen', () {
    test('writes remapped native indexes to the real target setters', () async {
      const bundle = EmbyResolvedTrackBundle(
        audio: EmbyResolvedTrackSelection.track(
          sourceIndex: 7,
          fingerprint: EmbyTrackFingerprint(
            language: 'jpn',
            normalizedTitle: 'main audio',
            codec: 'aac',
            channels: 2,
            isExternal: false,
          ),
        ),
        subtitle: EmbyResolvedTrackSelection.track(
          sourceIndex: 9,
          fingerprint: EmbyTrackFingerprint(
            language: 'zho',
            normalizedTitle: 'simplified chinese',
            codec: 'ass',
            isExternal: false,
          ),
        ),
      );
      final audioWrites = <List<int>>[];
      final subtitleWrites = <List<int>>[];
      final externalLoads = <EmbyExternalSubtitleAction>[];
      var externalClears = 0;

      await applyEmbyResolvedTracksAfterOpen(
        mediaInfo: PlayerMediaInfo(
          duration: 1000,
          audio: <PlayerAudioStreamInfo>[
            _audio(language: 'eng', title: 'Main Audio', codec: 'aac'),
            _audio(language: 'jpn', title: 'Main Audio', codec: 'aac'),
          ],
          subtitle: <PlayerSubtitleStreamInfo>[
            _subtitle(
              language: 'zho',
              title: 'Simplified Chinese',
              codec: 'ass',
            ),
          ],
        ),
        bundle: bundle,
        setActiveAudio: (indexes) {
          audioWrites.add(List<int>.of(indexes));
        },
        setActiveSubtitle: (indexes) {
          subtitleWrites.add(List<int>.of(indexes));
        },
        clearExternal: () async {
          externalClears++;
        },
        loadExternal: (action) async {
          externalLoads.add(action);
        },
      );

      expect(audioWrites, <List<int>>[
        <int>[1],
      ]);
      expect(subtitleWrites, <List<int>>[
        <int>[0],
      ]);
      expect(externalClears, 1);
      expect(externalLoads, isEmpty);
    });
  });
}

PlayerAudioStreamInfo _audio({
  required String language,
  required String title,
  required String codec,
  int channels = 2,
}) {
  return PlayerAudioStreamInfo(
    codec: PlayerAudioCodecParams(name: codec, channels: channels),
    title: title,
    language: language,
    metadata: <String, String>{
      'title': title,
      'language': language,
      'codec': codec,
      'channels': channels.toString(),
      'isExternal': 'false',
    },
    rawRepresentation: '$language|$title|$codec|$channels',
  );
}

PlayerSubtitleStreamInfo _subtitle({
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
