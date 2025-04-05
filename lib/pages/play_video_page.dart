import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/widgets/video_player_widget.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'package:fvp/mdk.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../widgets/tooltip_bubble.dart';
import '../utils/globals.dart' as globals;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import '../widgets/vertical_indicator.dart';

class PlayVideoPage extends StatefulWidget {
  const PlayVideoPage({super.key});

  @override
  State<PlayVideoPage> createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  bool _isBackButtonHovered = false;
  bool _isBackButtonPressed = false;

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
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: child!,
                    ),
                  ),
                  Consumer<VideoPlayerState>(
                    builder: (context, videoState, _) {
                      return VerticalIndicator(videoState: videoState);
                    },
                  ),
                  if (videoState.hasVideo)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: videoState.showControls ? 1.0 : 0.0,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: MouseRegion(
                          onEnter: (_) {
                            setState(() => _isBackButtonHovered = true);
                            videoState.setControlsHovered(true);
                          },
                          onExit: (_) {
                            setState(() => _isBackButtonHovered = false);
                            videoState.setControlsHovered(false);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                TooltipBubble(
                                  text: '返回',
                                  showOnRight: true,
                                  verticalOffset: 8,
                                  child: GestureDetector(
                                    onTapDown: (_) => setState(() => _isBackButtonPressed = true),
                                    onTapUp: (_) => setState(() => _isBackButtonPressed = false),
                                    onTapCancel: () => setState(() => _isBackButtonPressed = false),
                                    onTap: () async {
                                      try {
                                        // 重置播放器状态
                                        await videoState.resetPlayer();
                                      } catch (e) {
                                        print('重置播放器时出错: $e');
                                      }
                                    },
                                    child: GlassmorphicContainer(
                                      width: 48,
                                      height: 48,
                                      borderRadius: 25,
                                      blur: 30,
                                      alignment: Alignment.center,
                                      border: 1,
                                      linearGradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          const Color(0xFFffffff).withOpacity(0.2),
                                          const Color(0xFFFFFFFF).withOpacity(0.2),
                                        ],
                                      ),
                                      borderGradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          const Color(0xFFffffff).withOpacity(0.5),
                                          const Color((0xFFFFFFFF)).withOpacity(0.5),
                                        ],
                                      ),
                                      child: AnimatedOpacity(
                                        duration: const Duration(milliseconds: 200),
                                        opacity: _isBackButtonHovered ? 1.0 : 0.6,
                                        child: AnimatedScale(
                                          duration: const Duration(milliseconds: 100),
                                          scale: _isBackButtonPressed ? 0.9 : 1.0,
                                          child: const Icon(
                                            Ionicons.chevron_back_outline,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      child: const VideoPlayerWidget(),
    );
  }
} 