import 'package:nipaplay/utils/video_player_state.dart';

import 'media_models.dart';
import 'playback_capability.dart';

final class VideoPlayerStatePort implements PlayerPort {
  VideoPlayerStatePort(VideoPlayerState state) : _state = state;

  final VideoPlayerState _state;

  @override
  PlaybackSnapshot snapshot() => PlaybackSnapshot(
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

  @override
  void setPaused(bool paused) {
    if (paused) {
      _state.pause();
    } else {
      _state.play();
    }
  }

  @override
  void seekTo(Duration position) => _state.seekTo(position);

  @override
  Future<void> switchEpisode(EpisodeDirection direction) => switch (direction) {
        EpisodeDirection.next => _state.playNextEpisode(),
        EpisodeDirection.previous => _state.playPreviousEpisode(),
      };
}
