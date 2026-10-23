import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import '../../capabilities/player_facts.dart';
import '../../harness_redaction.dart';

// Facts read from Classic's player state, for the transitional playback.

/// The danmaku layer drawn over the current video: the player kernel's own,
/// a plugin's, or a built-in engine.
JsonMap danmakuRendererFacts(VideoPlayerState state) {
  if (state.isNativeDanmakuActive) {
    return {
      'id': 'player_native',
      'kernel': playerKernelId(state.player.getPlayerKernelName())
    };
  }
  final plugin = DanmakuKernelFactory.activePluginRenderer;
  if (plugin != null) {
    return {
      'id': 'plugin',
      'pluginId': plugin.pluginId,
      'rendererId': plugin.id,
      'name': plugin.name
    };
  }
  final engine = DanmakuKernelFactory.getKernelType();
  return {
    'id': switch (engine) {
      DanmakuRenderEngine.cpu => 'cpu',
      DanmakuRenderEngine.gpu => 'gpu',
      DanmakuRenderEngine.canvas => 'canvas',
      DanmakuRenderEngine.nipaplayNext => 'nipaplay_next',
      DanmakuRenderEngine.next2 => 'next2',
      DanmakuRenderEngine.dfmPlus => 'dfm_plus',
    },
    if (engine == DanmakuRenderEngine.nipaplayNext)
      'nextPlusPlus': DanmakuKernelFactory.isNextPlusPlusEnabled,
  };
}

/// What happens when the video ends, and the countdown to the next episode.
JsonMap autoNextFacts(VideoPlayerState state) {
  final service = AutoNextEpisodeService.instance;
  final counting = service.isCountingDown;
  final next = counting ? service.nextEpisode : null;
  return {
    'endAction': state.playbackEndAction.name,
    'countingDown': counting,
    'remainingSeconds': counting ? service.remainingSeconds : null,
    'next': next == null
        ? null
        : {
            'path': redactHarnessText(next.videoPath),
            'title': next.title,
            'subtitle': next.subtitle,
            'animeId': next.animeId,
            'episodeId': next.episodeId,
          },
  };
}

/// The current error of the internal player, as playback.state reports it.
/// A failure already recorded for this session gives its probed category.
JsonMap? playbackErrorFacts(VideoPlayerState state, String sessionId) {
  final player = state.player;
  final kernelMessage = player.mediaLoadError;
  if (!player.hasMediaLoadFailed && state.error == null) return null;
  final recorded = PlaybackFailures.instance.latestFor(sessionId);
  final kernel = playerKernelId(player.getPlayerKernelName());
  final mediaMessage = player.mediaInfo.specificErrorMessage;
  return {
    'code': 'media_load_failed',
    'message': redactHarnessText(
        kernelMessage ?? state.error ?? 'The current source failed to load.'),
    'reason': kernelMessage == null && state.error == null
        ? 'kernel_load_failure'
        : 'source_or_decoder_failure',
    'retryable': true,
    'recoveryAction': 'playback.retry',
    'stage': state.errorStage,
    'category': recorded?['category'] ??
        playbackFailureCategory(
            stage: state.errorStage,
            kernelMessage: kernelMessage,
            mediaMessage: mediaMessage,
            playerMessage: state.error),
    'kernel': kernel,
    'kernelRetryable':
        player.hasMediaLoadFailed ? player.mediaLoadErrorRetryable : null,
    'messages': {
      'player': safePlayerText(state.error),
      'kernel': safePlayerText(kernelMessage),
      'media': safePlayerText(mediaMessage),
    },
    if (recorded != null) 'failureId': recorded['failureId'],
  };
}

/// What Classic's player says now about its failure;
/// [PlaybackFailures.record] completes it with a look at a local file.
JsonMap captureClassicFailure(VideoPlayerState state, String sessionId) {
  final player = state.player;
  final kernel = playerKernelId(player.getPlayerKernelName());
  final kernelMessage = player.mediaLoadError;
  return {
    'at': DateTime.now().toUtc().toIso8601String(),
    'sessionId': sessionId,
    'path': state.currentVideoPath == null
        ? null
        : redactHarnessText(state.currentVideoPath!),
    'kernel': kernel,
    'stage': state.errorStage,
    'kernelRetryable':
        player.hasMediaLoadFailed ? player.mediaLoadErrorRetryable : null,
    'messages': {
      'player': safePlayerText(state.error),
      'kernel': safePlayerText(kernelMessage),
      'media': safePlayerText(player.mediaInfo.specificErrorMessage),
    },
    '_localPath': PlaybackFailures.localPathOf(state.currentVideoPath),
  };
}
