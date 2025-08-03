import 'package:flutter/material.dart';
import 'dart:ui'; // For ImageFilter.blur
import 'package:kmbal_ionicons/kmbal_ionicons.dart'; // For Ionicons
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart'; // Assuming VideoPlayerState is in utils

class VolumeIndicator extends StatelessWidget { // Changed class name
  const VolumeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: videoState.isVolumeUIVisible // <<< UPDATED to isVolumeUIVisible
                ? 1.0
                : 0.0, 
            duration: const Duration(
                milliseconds:
                    150), 
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
                      Builder( // Using Builder to get specific Icon based on volume
                        builder: (context) {
                          IconData iconData;
                          double volume = videoState.currentSystemVolume; // 0.0 to 1.0
                          if (volume == 0) {
                            iconData = Ionicons.volume_off_outline;
                          } else if (volume <= 0.3) {
                            iconData = Ionicons.volume_low_outline;
                          } else if (volume <= 0.6) {
                            iconData = Ionicons.volume_medium_outline;
                          } else {
                            iconData = Ionicons.volume_high_outline;
                          }
                          return Icon(iconData, color: Colors.white.withOpacity(0.8), size: 20);
                        }
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: globals.isPhone ? 100.0 : 250.0, 
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SizedBox(
                            height: 6, 
                            child: LinearProgressIndicator(
                              value: videoState.currentSystemVolume, // <<< CHANGED to currentSystemVolume
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
                          "${(videoState.currentSystemVolume * 100).toInt()}%", // <<< CHANGED to currentSystemVolume
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