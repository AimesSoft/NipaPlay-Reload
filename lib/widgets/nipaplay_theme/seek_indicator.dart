import 'package:flutter/material.dart';
import 'dart:ui'; // For ImageFilter.blur
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return AnimatedOpacity(
          opacity: videoState.isSeekIndicatorVisible ? 1.0 : 0.0, 
          duration: const Duration(milliseconds: 200), // Fade duration
          child: Center(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 139, 139, 139).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: Colors.white.withOpacity(0.7), width: 0.5),
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
} 