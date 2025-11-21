import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class MinimalProgressBar extends StatelessWidget {
  const MinimalProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (!videoState.hasVideo || !videoState.minimalProgressBarEnabled) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 2,
            child: FractionallySizedBox(
              widthFactor: videoState.progress,
              alignment: Alignment.centerLeft,
              child: Container(
                height: 2,
                color: videoState.minimalProgressBarColor,
              ),
            ),
          ),
        );
      },
    );
  }
}