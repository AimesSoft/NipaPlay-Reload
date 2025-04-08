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
import 'loading_overlay.dart';
import 'danmaku_overlay.dart';
import 'video_controls_overlay.dart';

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
          return Stack(
            children: [
              const VideoUploadUI(),
              if (videoState.status == PlayerStatus.recognizing || videoState.status == PlayerStatus.loading)
                LoadingOverlay(
                  messages: videoState.statusMessages,
                  backgroundOpacity: 0.5,
                ),
            ],
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
          return Stack(
            children: [
              FocusScope(
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
                        onTapDown: (_) {
                          // 触摸屏幕时重置自动隐藏定时器
                          if (videoState.hasVideo && videoState.showControls) {
                            videoState.resetAutoHideTimer();
                          }
                        },
                        child: MouseRegion(
                          onHover: (event) => videoState.handleMouseMove(event.position),
                          cursor: videoState.showControls ? SystemMouseCursors.basic : SystemMouseCursors.none,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: videoState.aspectRatio,
                              child: Texture(textureId: textureId),
                            ),
                          ),
                        ),
                      ),

                      // 弹幕层
                      if (videoState.hasVideo)
                        DanmakuOverlay(
                          isPlaying: videoState.status == PlayerStatus.playing,
                          currentPosition: videoState.position.inMilliseconds,
                          danmakuList: videoState.danmakuList,
                        ),
                      
                      // 垂直指示器
                      if (videoState.hasVideo)
                        VerticalIndicator(videoState: videoState),
                    ],
                  ),
                ),
              ),

              // 控制栏 Overlay
              const VideoControlsOverlay(),
            ],
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