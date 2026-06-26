import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_menu_theme.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_overlay_surface.dart';

class SpeedBoostIndicator extends StatelessWidget {
  const SpeedBoostIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!videoState.hasVideo) {
              return const SizedBox.shrink();
            }
            final bool shouldShow = videoState.isSpeedBoostActive;

            final mediaQuery = MediaQuery.of(context);
            final double availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : mediaQuery.size.width;
            final double availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : mediaQuery.size.height;

            if (availableWidth <= 0 || availableHeight <= 0) {
              return const SizedBox.shrink();
            }

            final double aspectRatio =
                (videoState.aspectRatio.isNaN || videoState.aspectRatio <= 0)
                    ? (16 / 9)
                    : videoState.aspectRatio;

            double videoWidth = availableWidth;
            double videoHeight = videoWidth / aspectRatio;
            if (videoHeight > availableHeight) {
              videoHeight = availableHeight;
              videoWidth = videoHeight * aspectRatio;
            }

            final double verticalLetterBox =
                ((availableHeight - videoHeight) / 2)
                    .clamp(0.0, double.infinity);
            final bool fillsScreenHeight =
                (availableHeight - mediaQuery.size.height).abs() < 1.0;
            final double safeTop =
                fillsScreenHeight ? mediaQuery.padding.top : 0.0;
            final double indicatorTopPadding =
                verticalLetterBox + safeTop + 16.0;

            return IgnorePointer(
              child: AnimatedOpacity(
                opacity: shouldShow ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: EdgeInsets.only(top: indicatorTopPadding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Builder(
                      builder: (context) {
                        final colors = PlayerMenuTheme.colorsOf(context);
                        return PlayerOverlaySurface(
                          borderRadius: 12,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 18,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fast_forward_rounded,
                                color: colors.accent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "${videoState.speedBoostRate}x 倍速",
                                locale: const Locale("zh-Hans", "zh"),
                                style: TextStyle(
                                  color: colors.foreground,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
