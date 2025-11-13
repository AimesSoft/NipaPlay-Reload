import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
            final blurEnabled =
                context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect;
            final double availableWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : mediaQuery.size.width;
            final double availableHeight =
                constraints.maxHeight.isFinite ? constraints.maxHeight : mediaQuery.size.height;

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
                ((availableHeight - videoHeight) / 2).clamp(0.0, double.infinity);
            final bool fillsScreenHeight =
                (availableHeight - mediaQuery.size.height).abs() < 1.0;
            final double safeTop = fillsScreenHeight ? mediaQuery.padding.top : 0.0;
            final double indicatorTopPadding = verticalLetterBox + safeTop + 16.0;

            return IgnorePointer(
              child: AnimatedOpacity(
                opacity: shouldShow ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: EdgeInsets.only(top: indicatorTopPadding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blurEnabled ? 25 : 0,
                          sigmaY: blurEnabled ? 25 : 0,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 18),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 139, 139, 139)
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.7),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.fast_forward_rounded,
                                color: Color.fromARGB(139, 255, 255, 255),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "${videoState.speedBoostRate}x 倍速",
                                locale: const Locale("zh-Hans", "zh"),
                                style: const TextStyle(
                                  color: Color.fromARGB(139, 255, 255, 255),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
