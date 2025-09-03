import 'package:flutter/material.dart';
import 'dart:ui'; // For ImageFilter.blur
import 'package:kmbal_ionicons/kmbal_ionicons.dart'; // For Ionicons
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart'; // Assuming VideoPlayerState is in utils
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class BrightnessIndicator extends StatelessWidget {
  const BrightnessIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to VideoPlayerState for brightness and visibility
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // Only build if the indicator should be visible (controlled by VideoPlayerState)
        // Removed: if (!videoState.isBrightnessIndicatorVisible) { return const SizedBox.shrink(); }

        return IgnorePointer(
          // So it doesn't block other gestures under it
          child: AnimatedOpacity(
            opacity: videoState.isBrightnessIndicatorVisible
                ? 1.0
                : 0.0, // Made opacity dynamic
            duration: const Duration(
                milliseconds:
                    150), // Opacity animation (though now mostly for show if parent handles visibility)
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                child: Container(
                  width: 55,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 255, 255)
                        .withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.6), width: 0.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Icon(Ionicons.sunny_outline,
                          color: Colors.white.withOpacity(0.8), size: 20),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // 获取屏幕高度
                          final screenHeight = MediaQuery.of(context).size.height;
                          // 根据设备类型计算滑条高度
                          final sliderHeight = globals.isDesktopOrTablet 
                              ? screenHeight / 3.0  // 平板/桌面：屏幕高度的1/3
                              : screenHeight * 0.8;  // 手机：屏幕高度的80%
                          
                          return SizedBox(
                            height: sliderHeight,
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SizedBox(
                                height: 6, 
                                child: LinearProgressIndicator(
                                  value: videoState.currentScreenBrightness,
                                  backgroundColor: Colors.white.withOpacity(0.25),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white.withOpacity(0.9)),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(
                          "${(videoState.currentScreenBrightness * 100).toInt()}%",
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none),
                        ),
                      )
                    ],
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
