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
import 'dart:async';
import 'package:flutter/services.dart';

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI> {
  final FocusNode _focusNode = FocusNode();
  final bool _isIndicatorHovered = false;
  Timer? _doubleTapTimer;
  int _tapCount = 0;
  static const _doubleTapTimeout = Duration(milliseconds: 200);
  bool _isProcessingTap = false;

  double getFontSize() {
    if (globals.isPhone) {
      return 20.0;
    } else {
      return 30.0;
    }
  }

  @override
  void initState() {
    super.initState();
    _focusNode.onKey = _handleKeyEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerKeyboardShortcuts();
    });
  }

  void _registerKeyboardShortcuts() {
    if (!mounted) return;
    
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState == null) return;
    
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

  void _handleTap() {
    if (_isProcessingTap) return;
    
    _tapCount++;
    if (_tapCount == 1) {
      // 启动双击检测定时器
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(_doubleTapTimeout, () {
        if (_tapCount == 1) {
          // 如果定时器结束时还是1次点击，则执行单点操作
          _handleSingleTap();
        }
        _tapCount = 0;
      });
    } else if (_tapCount == 2) {
      // 处理双击
      _doubleTapTimer?.cancel();
      _tapCount = 0;
      _handleDoubleTap();
    }
  }

  void _handleSingleTap() {
    _isProcessingTap = true;
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      if (globals.isPhone) {
        videoState.toggleControls();
      } else {
        videoState.togglePlayPause();
      }
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      _isProcessingTap = false;
    });
  }

  void _handleDoubleTap() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      if (globals.isPhone) {
        videoState.togglePlayPause();
      } else {
        videoState.toggleFullscreen();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final result = KeyboardShortcuts.handleKeyEvent(event);
    if (result == KeyEventResult.handled) {
      return result;
    }

    return KeyEventResult.ignored;
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
                      onTap: _handleTap,
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
                      canRequestFocus: true,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 视频纹理
                          GestureDetector(
                            onTap: _handleTap,
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
                            Consumer<VideoPlayerState>(
                              builder: (context, videoState, _) {
                                if (!videoState.danmakuVisible) {
                                  return const SizedBox.shrink();
                                }
                                return DanmakuOverlay(
                                  danmakuList: videoState.danmakuList,
                                  currentPosition: videoState.position.inMilliseconds.toDouble(),
                                  videoDuration: videoState.videoDuration.inMilliseconds.toDouble(),
                                  isPlaying: videoState.status == PlayerStatus.playing,
                                  fontSize: getFontSize(),
                                  isVisible: videoState.danmakuVisible,
                                  opacity: videoState.mappedDanmakuOpacity,
                                );
                              },
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