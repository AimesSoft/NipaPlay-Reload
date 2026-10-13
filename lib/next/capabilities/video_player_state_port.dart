import 'dart:io';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import '../public_url.dart';
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
        observedAt: DateTime.now(),
        player: 'external',
        status: paused == null ? 'external' : (paused ? 'paused' : 'playing'),
        hasVideo: true, paused: paused,
        // The launch path can contain server authentication query parameters.
        path: null, seriesTitle: ExternalPlayerConsoleService.animeTitle,
        episodeTitle: ExternalPlayerConsoleService.episodeTitle,
        animeId: null, episodeId: ExternalPlayerConsoleService.episodeId,
        positionMs: position,
        durationMs: telemetry && ExternalPlayerConsoleService.duration > Duration.zero ? ExternalPlayerConsoleService.duration.inMilliseconds : null,
        rate: null, canPrevious: false, canNext: false,
        sessionId: 'external:${ExternalPlayerConsoleService.processId}',
        supportedControls: ['close', if(telemetry) ...['pause','resume','seek']],
        external: {'player': ExternalPlayerConsoleService.playerType?.name,
          'positionMs': position, 'paused': paused},
      );
    }
    return PlaybackSnapshot(
        observedAt: DateTime.now(),
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
        sessionId: 'internal:$pid:${_state.playbackRequestGeneration}:${_state.playbackGeneration}',
        ready: _state.player.isMediaReady,
        buffering: _state.player.supportsBufferingTelemetry ? _state.isBuffering : null,
        bufferedPositionMs: _state.player.supportsBufferingTelemetry ? _state.player.bufferedPosition : null,
        error: _state.player.hasMediaLoadFailed || _state.error != null ? {
          'code': 'media_load_failed',
          'message': redactPrivateUrls(SecretRedactor.text(_state.player.mediaLoadError ?? _state.error ?? 'The current source failed to load.')),
          'reason': _state.player.mediaLoadError == null && _state.error == null ? 'kernel_load_failure' : 'source_or_decoder_failure',
          'retryable': true, 'recoveryAction': 'playback.retry',
        } : null,
        supportedControls: ['pause','resume','seek','retry','chapters','frame','skip','playlist'],
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
