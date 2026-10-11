import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import 'classic_playback_controls.dart';

import 'media_models.dart';
import 'playback_capability.dart';

final class VideoPlayerStatePort implements PlayerPort {
  VideoPlayerStatePort(VideoPlayerState state) : _state = state;

  final VideoPlayerState _state;

  @override
  PlaybackSnapshot snapshot() {
    if (ExternalPlayerConsoleService.hasActiveSession) {
      final telemetry = ExternalPlayerConsoleService.supportsPlaybackTelemetry;
      final position = telemetry ? ExternalPlayerConsoleService.position?.inMilliseconds : null;
      final paused = telemetry ? ExternalPlayerConsoleService.isPaused : null;
      return PlaybackSnapshot(
        player: 'external',
        status: paused == null ? 'external' : (paused ? 'paused' : 'playing'),
        hasVideo: true, paused: paused ?? false,
        // The launch path can contain server authentication query parameters.
        path: null, seriesTitle: ExternalPlayerConsoleService.animeTitle,
        episodeTitle: ExternalPlayerConsoleService.episodeTitle,
        animeId: null, episodeId: ExternalPlayerConsoleService.episodeId,
        positionMs: position ?? 0,
        durationMs: ExternalPlayerConsoleService.duration.inMilliseconds,
        rate: 1, canPrevious: false, canNext: false,
        external: {'player': ExternalPlayerConsoleService.playerType?.name,
          'positionMs': position, 'paused': paused},
      );
    }
    return PlaybackSnapshot(
        player: 'internal',
        volume: _state.currentSystemVolume,
        brightness: globals.isMobilePlatform ? _state.currentScreenBrightness : null,
        status: _state.status.name,
        hasVideo: _state.hasVideo,
        paused: _state.isPaused,
        path: _state.currentVideoPath,
        seriesTitle: _state.animeTitle,
        episodeTitle: _state.episodeTitle,
        animeId: _state.animeId,
        episodeId: _state.episodeId,
        positionMs: _state.position.inMilliseconds,
        durationMs: _state.duration.inMilliseconds,
        rate: _state.playbackRate,
        canPrevious: _state.canPlayPreviousEpisode,
        canNext: _state.canPlayNextEpisode,
      );
  }

  @override
  Future<void> setPaused(bool paused) async {
    if (ExternalPlayerConsoleService.hasActiveSession) {
      await ClassicPlaybackControls(_state).external({'command': paused ? 'pause' : 'resume'});
      return;
    }
    if (paused) {
      _state.pause();
    } else {
      _state.play();
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (ExternalPlayerConsoleService.hasActiveSession) {
      await ClassicPlaybackControls(_state).external({'command': 'seek', 'positionMs': position.inMilliseconds});
    } else {
      _state.seekTo(position);
    }
  }

  @override
  Future<void> switchEpisode(EpisodeDirection direction) => switch (direction) {
        EpisodeDirection.next => _state.playNextEpisode(),
        EpisodeDirection.previous => _state.playPreviousEpisode(),
      };
}
