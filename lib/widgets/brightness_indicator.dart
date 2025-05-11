import 'package:flutter/material.dart';
import 'dart:ui'; // For ImageFilter.blur
import 'package:kmbal_ionicons/kmbal_ionicons.dart'; // For Ionicons
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart'; // Assuming VideoPlayerState is in utils

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
                filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
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
                      SizedBox(
                        // Replacing Expanded with SizedBox for testing
                        height: globals.isPhone ? 100.0 : 250.0, // Temporary fixed height
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SizedBox(
                            height: 6, // Thickness of the bar - RESTORED
                            child: LinearProgressIndicator(
                              value: videoState.currentScreenBrightness,
                              backgroundColor: Colors.white.withOpacity(0.25),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withOpacity(0.9)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(
                          "${(videoState.currentScreenBrightness * 100).toInt()}%",
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.w500),
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
