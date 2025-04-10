import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../utils/keyboard_shortcuts.dart';
import '../utils/globals.dart' as globals;
import 'video_upload_ui.dart';
import 'vertical_indicator.dart';
import 'dart:io' show Platform;
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
  final bool _isIndicatorHovered = false;

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

    KeyboardShortcuts.registerActionHandler('toggle_danmaku', () {
      videoState.toggleDanmakuVisible();
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
                child: globals.isPhone
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => videoState.toggleControls(),
                      onDoubleTap: () => videoState.togglePlayPause(),
                      child: Stack(
                        children: [
                          // 视频纹理
                          Center(
                            child: AspectRatio(
                              aspectRatio: videoState.aspectRatio,
                              child: Texture(textureId: textureId),
                            ),
                          ),
                          
                          // 加载中遮罩
                          if (videoState.status == PlayerStatus.recognizing || videoState.status == PlayerStatus.loading)
                            LoadingOverlay(
                              messages: videoState.statusMessages,
                              backgroundOpacity: 0.5,
                            ),
                          
                          // 垂直指示器
                          if (videoState.hasVideo)
                            VerticalIndicator(videoState: videoState),
                        ],
                      ),
                    )
                  : Focus(
                      focusNode: _focusNode,
                      autofocus: true,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 视频纹理
                          GestureDetector(
                            onTap: () {
                              if (videoState.hasVideo) {
                                videoState.togglePlayPause();
                              }
                            },
                            onDoubleTap: () {
                              if (videoState.hasVideo) {
                                videoState.toggleFullscreen();
                              }
                            },
                            onTapDown: (_) {
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
                          
                          // 加载中遮罩
                          if (videoState.status == PlayerStatus.recognizing || videoState.status == PlayerStatus.loading)
                            LoadingOverlay(
                              messages: videoState.statusMessages,
                              backgroundOpacity: 0.5,
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