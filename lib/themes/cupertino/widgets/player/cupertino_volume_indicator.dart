import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/cupertino/widgets/player/cupertino_indicator.dart';

class CupertinoVolumeIndicator extends StatelessWidget {
  const CupertinoVolumeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
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
        return CupertinoPlayerIndicator(
          isVisible: videoState.isVolumeUIVisible,
          value: volume,
          icon: icon,
          label: '${(volume * 100).round()}%',
        );
      },
    );
  }
}
