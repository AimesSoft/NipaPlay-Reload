import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
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
    final uiTheme = context.watch<UIThemeProvider?>();
    final bool useCupertinoStyle =
        uiTheme?.isCupertinoTheme == true && globals.isPhone;

    if (!useCupertinoStyle) {
      return Consumer<VideoPlayerState>(
        builder: (context, videoState, child) {
          return AnimatedOpacity(
            opacity: videoState.isSeekIndicatorVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: context
                              .watch<AppearanceSettingsProvider>()
                              .enableWidgetBlurEffect
                          ? 25
                          : 0,
                      sigmaY: context
                              .watch<AppearanceSettingsProvider>()
                              .enableWidgetBlurEffect
                          ? 25
                          : 0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 18,
                      ),
                      decoration: BoxDecoration(
                        color:
                            const Color.fromARGB(255, 139, 139, 139).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        "${_formatDuration(videoState.dragSeekTargetPosition)} / ${_formatDuration(videoState.duration)}",
                        style: const TextStyle(
                          color: Color.fromARGB(139, 255, 255, 255),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
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
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return AnimatedOpacity(
          opacity: videoState.isSeekIndicatorVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Center(
            child: IgnorePointer(
              child: AdaptiveBlurView(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 20,
                  ),
                  child: Text(
                    "${_formatDuration(videoState.dragSeekTargetPosition)} / ${_formatDuration(videoState.duration)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                      shadows: [
                        Shadow(
                          color: Color.fromARGB(120, 0, 0, 0),
                          offset: Offset(0, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
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
