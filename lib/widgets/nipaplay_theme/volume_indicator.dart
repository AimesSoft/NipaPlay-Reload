import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/cupertino/player/cupertino_indicator.dart';
import 'package:nipaplay/widgets/nipaplay_theme/indicator_widget.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class VolumeIndicator extends StatelessWidget {
  const VolumeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final uiTheme = context.watch<UIThemeProvider?>();
    final bool useCupertinoStyle =
        uiTheme?.isCupertinoTheme == true && globals.isPhone;

    if (!useCupertinoStyle) {
      return IndicatorWidget(
        isVisible: (videoState) => videoState.isVolumeUIVisible,
        getValue: (videoState) => videoState.currentSystemVolume,
        getIcon: (videoState) {
          double volume = videoState.currentSystemVolume;
          if (volume == 0) {
            return Ionicons.volume_off_outline;
          } else if (volume <= 0.3) {
            return Ionicons.volume_low_outline;
          } else if (volume <= 0.6) {
            return Ionicons.volume_medium_outline;
          } else {
            return Ionicons.volume_high_outline;
          }
        },
      );
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        final volume = videoState.currentSystemVolume.clamp(0.0, 1.0);
        IconData icon;
        if (volume == 0) {
          icon = CupertinoIcons.speaker_slash_fill;
        } else if (volume <= 0.3) {
          icon = CupertinoIcons.speaker_fill;
        } else if (volume <= 0.6) {
          icon = CupertinoIcons.speaker_2_fill;
        } else {
          icon = CupertinoIcons.speaker_3_fill;
        }
        final label = '${(volume * 100).round()}%';
        return CupertinoPlayerIndicator(
          isVisible: videoState.isVolumeUIVisible,
          value: volume,
          icon: icon,
          label: label,
        );
      },
    );
  }
}
