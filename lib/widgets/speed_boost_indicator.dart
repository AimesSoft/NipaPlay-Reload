import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class SpeedBoostIndicator extends StatelessWidget {
  const SpeedBoostIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return AnimatedOpacity(
          opacity: videoState.isSpeedBoostActive ? 1.0 : 0.0, 
          duration: const Duration(milliseconds: 200),
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fast_forward_rounded,
                          color: Color.fromARGB(139, 255, 255, 255),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "2x 倍速",
                          style: TextStyle(
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
        );
      },
    );
  }
} 