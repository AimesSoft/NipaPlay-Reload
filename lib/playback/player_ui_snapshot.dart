import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/video_player_state.dart';

/// Immutable values consumed by the player layout. Position is deliberately
/// absent: clocks and progress controls have their own subscriptions.
List<Object?> playerUiSnapshot(VideoPlayerState state) {
  final tracks = state.player.mediaInfo.video;
  final codec = tracks == null || tracks.isEmpty ? null : tracks.first.codec;
  return [
    state.player,
    state.playerSurfaceGeneration,
    state.player.prefersPlatformVideoSurface,
    state.player.handlesVideoAspectFit,
    if (kIsWeb) state.player.videoPlayerController,
    state.hasVideo,
    state.isDfmStartupGatePending,
    state.supportsVideoAspectModes,
    state.status,
    state.error,
    state.currentVideoPath,
    state.videoAspectMode,
    state.aspectRatio,
    codec?.width,
    codec?.height,
    state.danmakuVisible,
    state.isFullscreen,
    state.showControls,
    state.desktopHoverSettingsMenuEnabled,
    state.isInFinalLoadingPhase,
    state.animeTitle,
    state.episodeTitle,
    state.animeId,
    state.loadingCoverImageUrl,
    List<String>.of(state.statusMessages),
  ];
}

List<Object?> danmakuUiSnapshot(VideoPlayerState state) => [
      state.danmakuOverlayKey,
      state.videoDuration,
      state.status,
      state.actualDanmakuFontSize,
      state.danmakuVisible,
      state.shouldHideDanmakuForScreenshot,
      state.mappedDanmakuOpacity,
      state.isNativeDanmakuActive,
    ];
