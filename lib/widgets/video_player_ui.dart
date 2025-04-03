import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'modern_video_controls.dart';
import 'video_upload_ui.dart';
import 'dart:ui';
import 'dart:io' show Platform;
import '../utils/globals.dart' as globals;

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI> {
  bool _isLeftPressed = false;
  bool _isRightPressed = false;
  bool _isSpacePressed = false;
  bool _isEnterPressed = false;
  bool _isWhiteBarHovered = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final textureId = videoState.player.textureId.value;

        if (!videoState.hasVideo) {
          return const VideoUploadUI();
        }

        if (videoState.status == PlayerStatus.loading) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Colors.white,
                ),
                SizedBox(height: 16),
                Text(
                  '加载中...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        if (videoState.error != null) {
          return Center(
            child: Text(
              videoState.error!,
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (textureId != null) {
          return RawKeyboardListener(
            focusNode: FocusNode(),
            autofocus: true,
            onKey: (event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.space && !_isSpacePressed) {
                  if (videoState.hasVideo) {
                    setState(() => _isSpacePressed = true);
                    videoState.togglePlayPause();
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.enter && !_isEnterPressed) {
                  setState(() => _isEnterPressed = true);
                  videoState.toggleFullscreen();
                } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && !_isLeftPressed) {
                  if (videoState.hasVideo) {
                    setState(() => _isLeftPressed = true);
                    final newPosition = videoState.position - const Duration(seconds: 10);
                    videoState.seekTo(newPosition);
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && !_isRightPressed) {
                  if (videoState.hasVideo) {
                    setState(() => _isRightPressed = true);
                    final newPosition = videoState.position + const Duration(seconds: 10);
                    videoState.seekTo(newPosition);
                  }
                }
              } else if (event is RawKeyUpEvent) {
                if (event.logicalKey == LogicalKeyboardKey.space) {
                  setState(() => _isSpacePressed = false);
                } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                  setState(() => _isEnterPressed = false);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  setState(() => _isLeftPressed = false);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  setState(() => _isRightPressed = false);
                }
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 视频纹理
                GestureDetector(
                  onTap: () {
                    if (Platform.isAndroid || Platform.isIOS) {
                      // 触摸屏设备：切换控制栏显示/隐藏
                      videoState.toggleControls();
                    } else {
                      // 鼠标点击：切换播放/暂停
                      if (videoState.hasVideo) {
                        videoState.togglePlayPause();
                      }
                    }
                  },
                  child: MouseRegion(
                    onHover: (event) => videoState.handleMouseMove(event.position),
                    cursor: videoState.showControls ? SystemMouseCursors.basic : SystemMouseCursors.none,
                    child: Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: videoState.aspectRatio,
                          child: Texture(textureId: textureId),
                        ),
                        // 添加右侧白色竖线指示器
                        if ((videoState.status == PlayerStatus.playing || videoState.status == PlayerStatus.paused) && 
                            (globals.isPhone || (Platform.isWindows || Platform.isMacOS || Platform.isLinux) && videoState.isFullscreen))
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            right: videoState.showControls ? 10 : -20,
                            top: (MediaQuery.of(context).size.height - 
                                (_isWhiteBarHovered 
                                    ? MediaQuery.of(context).size.height * (1/2)
                                    : MediaQuery.of(context).size.height * (1/3))) / 2,
                            child: MouseRegion(
                              onEnter: (_) => setState(() => _isWhiteBarHovered = true),
                              onExit: (_) => setState(() => _isWhiteBarHovered = false),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: videoState.showControls ? 1.0 : 0.0,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutBack,
                                  width: 8,
                                  height: _isWhiteBarHovered 
                                      ? MediaQuery.of(context).size.height * (1/2)
                                      : MediaQuery.of(context).size.height * (1/3),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                
                // 现代风格控制栏
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: videoState.showControls ? 1.0 : 0.0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 150),
                    offset: Offset(0, videoState.showControls ? 0 : 0.1),
                    child: const ModernVideoControls(),
                  ),
                ),
              ],
            ),
          );
        }

        return const Center(
          child: Text(
            '无法显示视频',
            style: TextStyle(color: Colors.red),
          ),
        );
      },
    );
  }
} 