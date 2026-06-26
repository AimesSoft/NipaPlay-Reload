import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_menu_theme.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_overlay_surface.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class SeekIndicator extends StatelessWidget {
  const SeekIndicator({super.key});

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final colors = PlayerMenuTheme.colorsOf(context);
        return AnimatedOpacity(
          opacity: videoState.isSeekIndicatorVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200), // Fade duration
          child: Center(
            child: IgnorePointer(
              child: PlayerOverlaySurface(
                borderRadius: 12,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                child: Text(
                  "${_formatDuration(videoState.dragSeekTargetPosition)} / ${_formatDuration(videoState.duration)}",
                  style: TextStyle(
                    color: colors.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
