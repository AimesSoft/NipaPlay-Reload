import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/indicator_widget.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class VolumeIndicator extends StatelessWidget {
  const VolumeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
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
} 