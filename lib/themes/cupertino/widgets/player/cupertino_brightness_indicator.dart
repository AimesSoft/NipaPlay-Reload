import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/cupertino/widgets/player/cupertino_indicator.dart';

class CupertinoBrightnessIndicator extends StatelessWidget {
  const CupertinoBrightnessIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        final brightness = videoState.currentScreenBrightness.clamp(0.0, 1.0);
        return CupertinoPlayerIndicator(
          isVisible: videoState.isBrightnessIndicatorVisible,
          value: brightness,
          icon: CupertinoIcons.sun_max_fill,
          label: '${(brightness * 100).round()}%',
        );
      },
    );
  }
}
