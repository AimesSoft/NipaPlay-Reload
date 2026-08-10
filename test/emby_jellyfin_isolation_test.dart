import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_preference_store.dart';
import 'package:nipaplay/services/emby_media_selection_resolver.dart';
import 'package:nipaplay/services/emby_player_menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Jellyfin selections on the same surface are not locked', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var applyCalls = 0;

    final first = runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplaySource,
      false,
      () async {
        applyCalls++;
        firstStarted.complete();
        await releaseFirst.future;
      },
      () async => throw StateError('Jellyfin must not persist Emby state'),
    );
    await firstStarted.future;

    final second = runMediaServerMenuSelection(
      MediaServerMenuSurface.nipaplaySource,
      false,
      () async => applyCalls++,
      () async => throw StateError('Jellyfin must not persist Emby state'),
    );
    await second;

    expect(applyCalls, 2);
    releaseFirst.complete();
    await first;
  });

  for (final surface in _sixMenuSurfaces) {
    test('${surface.name} Jellyfin path only applies its existing switch',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = _CountingStore(await SharedPreferences.getInstance());
      final service = EmbyPlayerMenuSelectionService(
        store: store,
        resolver: DefaultEmbyMediaSelectionResolver(),
      );
      var quality = JellyfinVideoQuality.original;
      int? audioIndex = 1;
      int? subtitleIndex = 2;
      Object embyPlaybackState = Object();
      final initialEmbyPlaybackState = embyPlaybackState;
      var switchCalls = 0;
      var embyCallbacks = 0;

      final persisted = await runMediaServerMenuSelection(
        surface,
        false,
        () async {
          switchCalls++;
          if (_sourceSurfaces.contains(surface)) {
            quality = JellyfinVideoQuality.bandwidth10m;
          } else if (_audioSurfaces.contains(surface)) {
            audioIndex = 6;
          } else {
            subtitleIndex = null;
          }
        },
        () async {
          embyCallbacks++;
          await service.resolveTracksForSource(
            context: _context,
            currentSource: _source,
          );
          return service.persistCurrentManualPatch(
            context: _context,
            currentSource: _source,
            patch: EmbyManualSelectionPatch(source: _source),
          );
        },
      );

      expect(switchCalls, 1);
      expect(persisted, isFalse);
      expect(embyCallbacks, 0);
      expect(store.reads, 0);
      expect(store.writes, 0);
      expect(embyPlaybackState, same(initialEmbyPlaybackState));

      if (_sourceSurfaces.contains(surface)) {
        expect(quality, JellyfinVideoQuality.bandwidth10m);
        expect(audioIndex, 1);
        expect(subtitleIndex, 2);
      } else if (_audioSurfaces.contains(surface)) {
        expect(quality, JellyfinVideoQuality.original);
        expect(audioIndex, 6);
        expect(subtitleIndex, 2);
      } else {
        expect(quality, JellyfinVideoQuality.original);
        expect(audioIndex, 1);
        expect(subtitleIndex, isNull);
      }
    });
  }
}

const _sixMenuSurfaces = <MediaServerMenuSurface>[
  MediaServerMenuSurface.nipaplaySource,
  MediaServerMenuSurface.nipaplayAudio,
  MediaServerMenuSurface.nipaplaySubtitle,
  MediaServerMenuSurface.cupertinoSource,
  MediaServerMenuSurface.cupertinoAudio,
  MediaServerMenuSurface.cupertinoSubtitle,
];

const _sourceSurfaces = <MediaServerMenuSurface>{
  MediaServerMenuSurface.nipaplaySource,
  MediaServerMenuSurface.cupertinoSource,
};

const _audioSurfaces = <MediaServerMenuSurface>{
  MediaServerMenuSurface.nipaplayAudio,
  MediaServerMenuSurface.cupertinoAudio,
};

const _context = EmbySelectionContext(
  accountKey: 'server:user',
  seriesId: 'series-9',
  episodeId: 'episode-1',
);

final _source = EmbyMediaSourceDescriptor(
  source: const PlaybackMediaSource(
    id: 'source-a',
    name: '[Baha] Episode 01',
  ),
  displayName: '[Baha] Episode 01',
  summary: '1080p',
  technical: const EmbyTechnicalFingerprint(height: 1080),
  videoTracks: const <EmbyVideoStreamDescriptor>[],
  audioTracks: const <EmbyAudioTrackDescriptor>[],
  subtitleTracks: const <EmbySubtitleTrackDescriptor>[],
);

class _CountingStore extends EmbyMediaPreferenceStore {
  _CountingStore(super.preferences);

  int reads = 0;
  int writes = 0;

  @override
  Future<EmbyPreferenceLayers> load(EmbySelectionContext context) async {
    reads++;
    return const EmbyPreferenceLayers(
      series: EmbySeriesPreference(normalizedFullName: 'baha episode 01'),
    );
  }

  @override
  Future<void> saveManualPatch(
    EmbySelectionContext context,
    EmbyMediaSourceDescriptor currentSource,
    EmbyManualSelectionPatch patch,
  ) async {
    writes++;
  }
}
