import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/video_player_widget.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../widgets/vertical_indicator.dart';
import '../services/dandanplay_service.dart';
import '../widgets/danmaku_overlay.dart';
import '../utils/globals.dart' as globals;
import '../widgets/video_controls_overlay.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/anime_info_widget.dart';

class PlayVideoPage extends StatefulWidget {
  final String? videoPath;
  
  const PlayVideoPage({super.key, this.videoPath});

  @override
  State<PlayVideoPage> createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  @override
  void initState() {
    super.initState();
  }

  double getFontSize() {
    if (globals.isPhone) {
      return 20.0;
    } else {
      return 30.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          color: videoState.hasVideo 
              ? Colors.black 
              : Colors.transparent,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                const VideoPlayerWidget(),
                if (videoState.hasVideo) ...[
                  Positioned.fill(
                    child: Consumer<VideoPlayerState>(
                      builder: (context, videoState, _) {
                        if (!videoState.danmakuVisible) {
                          return const SizedBox.shrink();
                        }
                        return DanmakuOverlay(
                          currentPosition: videoState.position.inMilliseconds.toDouble(),
                          videoDuration: videoState.videoDuration.inMilliseconds.toDouble(),
                          isPlaying: videoState.status == PlayerStatus.playing,
                          fontSize: getFontSize(),
                          isVisible: videoState.danmakuVisible,
                          opacity: videoState.mappedDanmakuOpacity,
                        );
                      },
                    ),
                  ),
                  Consumer<VideoPlayerState>(
                    builder: (context, videoState, _) {
                      return VerticalIndicator(videoState: videoState);
                    },
                  ),
                  BackButtonWidget(videoState: videoState),
                  AnimeInfoWidget(videoState: videoState),
                ],
                // 添加控制栏到根 Stack
                if (videoState.hasVideo)
                  const VideoControlsOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }
} 