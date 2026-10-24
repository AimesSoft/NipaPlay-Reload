import 'package:flutter/widgets.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:provider/provider.dart';

import '../core/arbiter.dart';
import 'debug_local_operations.dart';

/// Where Next meets Classic's player. Classic plays only in Classic's own
/// interface; here it is the lease's other side (Next takes the lease and
/// Classic lets its kernel go, its progress and watch record saved) and the
/// session Next closes when it takes over. Nothing in Next plays through it.
class ClassicBoundary {
  ClassicBoundary(this.state);

  /// Over Classic's player state in [context].
  factory ClassicBoundary.of(BuildContext context) =>
      ClassicBoundary(context.read<VideoPlayerState>());

  final VideoPlayerState state;

  bool get _playing =>
      state.hasVideo ||
      const {PlayerStatus.loading, PlayerStatus.recognizing}
          .contains(state.status);

  /// When Next takes the lease while Classic still plays, Classic closes
  /// it its own way before Next opens anything.
  void registerEvictor(KernelArbiter arbiter) => arbiter.registerEvictor(
      KernelOwner.classic, (reason) => close(reason: reason),
      busy: () => _playing);

  /// Lab-only fixtures and Classic observations.
  void installDebug() => installDebugLocalOperations(state);

  /// Closes what Classic plays, its progress and watch record saved as
  /// leaving it does.
  Future<void> close({required String reason}) async {
    if (!_playing) return;
    debugPrint('[ClassicBoundary] close ($reason)');
    AutoNextEpisodeService.instance.cancelAutoNext();
    if (state.isFullscreen) await state.toggleFullscreen();
    final path = state.currentVideoPath;
    if (path != null && state.hasVideo) {
      await state.persistCurrentPositionForHotSwap(
          path: path, positionMs: state.position.inMilliseconds);
    }
    // Classic's own way out: the exit frame for the watch record, then the
    // watch record and progress saved as the player resets.
    if (state.hasVideo) await state.handleBackButton();
    await state.resetPlayer();
  }
}
