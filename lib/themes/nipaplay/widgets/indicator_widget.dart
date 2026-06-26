import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_menu_theme.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_overlay_surface.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class IndicatorWidget extends StatelessWidget {
  final bool Function(VideoPlayerState) isVisible;
  final double Function(VideoPlayerState) getValue;
  final IconData Function(VideoPlayerState) getIcon;

  const IndicatorWidget({
    super.key,
    required this.isVisible,
    required this.getValue,
    required this.getIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final colors = PlayerMenuTheme.colorsOf(context);
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: isVisible(videoState) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: PlayerOverlaySurface(
              width: 55,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Icon(
                    getIcon(videoState),
                    color: colors.accent,
                    size: 20,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: globals.isDesktopOrTablet
                        ? MediaQuery.of(context).size.height * 0.3
                        : MediaQuery.of(context).size.height * 0.7,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SizedBox(
                        height: 6,
                        child: LinearProgressIndicator(
                          value: getValue(videoState),
                          backgroundColor: colors.controlBackground,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.accent,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      "${(getValue(videoState) * 100).toInt()}%",
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                          color: colors.secondaryForeground,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
