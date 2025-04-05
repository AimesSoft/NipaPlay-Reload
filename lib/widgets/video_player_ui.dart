import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../utils/keyboard_shortcuts.dart';
import 'modern_video_controls.dart';
import 'video_upload_ui.dart';
import 'vertical_indicator.dart';
import 'dart:ui';
import 'dart:io' show Platform;
import '../utils/globals.dart' as globals;

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI> {
  final FocusNode _focusNode = FocusNode();
  bool _isIndicatorHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode.onKey = _handleKeyEvent;
    _registerKeyboardShortcuts();
  }

  void _registerKeyboardShortcuts() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    
    KeyboardShortcuts.registerActionHandler('play_pause', () {
      if (videoState.hasVideo) {
        videoState.togglePlayPause();
      }
    });

    KeyboardShortcuts.registerActionHandler('fullscreen', () {
      videoState.toggleFullscreen();
    });

    KeyboardShortcuts.registerActionHandler('rewind', () {
      if (videoState.hasVideo) {
        final newPosition = videoState.position - const Duration(seconds: 10);
        videoState.seekTo(newPosition);
      }
    });

    KeyboardShortcuts.registerActionHandler('forward', () {
      if (videoState.hasVideo) {
        final newPosition = videoState.position + const Duration(seconds: 10);
        videoState.seekTo(newPosition);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    return KeyboardShortcuts.handleKeyEvent(event);
  }

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
          return FocusScope(
            node: FocusScopeNode(),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
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
                        ],
                      ),
                    ),
                  ),
                  
                  // 现代风格控制栏
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: videoState.showControls ? 1.0 : 0.0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 150),
                        offset: Offset(0, videoState.showControls ? 0 : 0.1),
                        child: const ModernVideoControls(),
                      ),
                    ),
                  ),
                ],
              ),
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