import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/cupertino/player/cupertino_indicator.dart';
import 'package:nipaplay/widgets/nipaplay_theme/indicator_widget.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class BrightnessIndicator extends StatelessWidget {
  const BrightnessIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final uiTheme = context.watch<UIThemeProvider?>();
    final bool useCupertinoStyle =
        uiTheme?.isCupertinoTheme == true && globals.isPhone;

    if (!useCupertinoStyle) {
      return IndicatorWidget(
        isVisible: (videoState) => videoState.isBrightnessIndicatorVisible,
        getValue: (videoState) => videoState.currentScreenBrightness,
        getIcon: (videoState) => Ionicons.sunny_outline,
      );
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        final brightness =
            videoState.currentScreenBrightness.clamp(0.0, 1.0);
        final label = '${(brightness * 100).round()}%';
        return CupertinoPlayerIndicator(
          isVisible: videoState.isBrightnessIndicatorVisible,
          value: brightness,
          icon: CupertinoIcons.sun_max_fill,
          label: label,
        );
      },
    );
  }
}
