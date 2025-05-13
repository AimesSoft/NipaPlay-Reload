import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../utils/keyboard_shortcuts.dart';
import '../utils/globals.dart' as globals;
import 'video_upload_ui.dart';
import 'vertical_indicator.dart';
import 'loading_overlay.dart';
import 'danmaku_overlay.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'brightness_gesture_area.dart';
import 'volume_gesture_area.dart';
import 'dart:io';
import 'dart:math' as math;

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI> with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  final bool _isIndicatorHovered = false;
  Timer? _doubleTapTimer;
  Timer? _mouseMoveTimer;
  int _tapCount = 0;
  static const _doubleTapTimeout = Duration(milliseconds: 200);
  static const _mouseHideDelay = Duration(seconds: 3);
  bool _isProcessingTap = false;
  bool _isMouseVisible = true;
  bool _isHorizontalDragging = false;
  late AnimationController _linuxRefreshController;
  late AnimationController _linuxFastRefreshController;

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
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.setContext(context);
      if (!globals.isPhone) {
        _resetMouseHideTimer();
      }
    });
    
    _linuxRefreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    _linuxFastRefreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );
    
    final bool isLinuxPlatform = Platform.isLinux;
    
    if (isLinuxPlatform) {
      _startLinuxRefreshAnimation();
    }
  }

  void _registerKeyboardShortcuts() {
    if (!mounted) return;
    
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

    KeyboardShortcuts.registerActionHandler('volume_up', () {
      if (videoState.hasVideo) {
        videoState.increaseVolume();
      }
    });

    KeyboardShortcuts.registerActionHandler('volume_down', () {
      if (videoState.hasVideo) {
        videoState.decreaseVolume();
      }
    });
  }

  void _resetMouseHideTimer() {
    _mouseMoveTimer?.cancel();
    if (!globals.isPhone) {
      _mouseMoveTimer = Timer(_mouseHideDelay, () {
        if (mounted && !_isProcessingTap) {
          setState(() {
            _isMouseVisible = false;
          });
        }
      });
    }
  }

  void _handleTap() {
    if (_isProcessingTap) return;
    if (_isHorizontalDragging) return;
    
    _tapCount++;
    if (_tapCount == 1) {
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(_doubleTapTimeout, () {
        if (_tapCount == 1) {
          _handleSingleTap();
        }
        _tapCount = 0;
      });
    } else if (_tapCount == 2) {
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

  void _handleMouseMove(PointerEvent event) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;

    if (!_isMouseVisible) {
      setState(() {
        _isMouseVisible = true;
      });
    }
    videoState.setShowControls(true);

    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(_mouseHideDelay, () {
      if (mounted && !_isIndicatorHovered) {
        setState(() {
          _isMouseVisible = false;
        });
        videoState.setShowControls(false);
      }
    });
  }

  void _handleHorizontalDragStart(BuildContext context, DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      _isHorizontalDragging = true;
      videoState.startSeekDrag(context);
      _doubleTapTimer?.cancel();
      _tapCount = 0;
    }
  }

  void _handleHorizontalDragUpdate(BuildContext context, DragUpdateDetails details) {
    if (_isHorizontalDragging) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      if (details.primaryDelta != null && details.primaryDelta!.abs() > 0) {
        if ((details.delta.dx.abs() > details.delta.dy.abs())) {
          videoState.updateSeekDrag(details.delta.dx, context);
        }
      }
    }
  }

  void _handleHorizontalDragEnd(BuildContext context, DragEndDetails details) {
    if (_isHorizontalDragging) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.endSeekDrag();
      _isHorizontalDragging = false;
    }
  }

  void _startLinuxRefreshAnimation() {
    _linuxRefreshController.repeat(reverse: true);
    _linuxFastRefreshController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _doubleTapTimer?.cancel();
    _mouseMoveTimer?.cancel();
    _linuxRefreshController.dispose();
    _linuxFastRefreshController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    debugPrint('[VideoPlayerUI] _handleKeyEvent: ${event.logicalKey}');
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final result = KeyboardShortcuts.handleKeyEvent(event, context);
    if (result == KeyEventResult.handled) {
      return result;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bool isLinuxPlatform = Platform.isLinux;

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
          return const SizedBox.shrink();
        }

        if (textureId != null && textureId > 0) {
          return MouseRegion(
            onHover: _handleMouseMove,
            cursor: _isMouseVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onHorizontalDragStart: globals.isPhone ? (details) => _handleHorizontalDragStart(context, details) : null,
                  onHorizontalDragUpdate: globals.isPhone ? (details) => _handleHorizontalDragUpdate(context, details) : null,
                  onHorizontalDragEnd: globals.isPhone ? (details) => _handleHorizontalDragEnd(context, details) : null,
                  child: FocusScope(
                    node: FocusScopeNode(),
                    child: globals.isPhone
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: ColoredBox(
                                  color: Colors.black,
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: videoState.aspectRatio,
                                      child: Stack(
                                        children: [
                                          Texture(
                                            textureId: textureId,
                                            filterQuality: FilterQuality.medium,
                                          ),
                                          if (isLinuxPlatform) ...[
                                            TickerMode(
                                              enabled: true,
                                              child: Positioned.fill(
                                                child: AnimatedBuilder(
                                                  animation: _linuxRefreshController,
                                                  builder: (context, child) {
                                                    return CustomPaint(
                                                      painter: _LinuxRefreshPainter(
                                                        animationValue: _linuxRefreshController.value,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            TickerMode(
                                              enabled: true,
                                              child: Positioned.fill(
                                                child: AnimatedBuilder(
                                                  animation: _linuxFastRefreshController,
                                                  builder: (context, child) {
                                                    return Opacity(
                                                      opacity: 0.001 + 0.001 * _linuxFastRefreshController.value,
                                                      child: Container(
                                                        color: Colors.transparent,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            if (videoState.hasVideo)
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: true,
                                  child: Consumer<VideoPlayerState>(
                                    builder: (context, videoState, _) {
                                      if (!videoState.danmakuVisible) {
                                        return const SizedBox.shrink();
                                      }
                                      return DanmakuOverlay(
                                        key: ValueKey('danmaku_${videoState.currentVideoPath ?? DateTime.now().millisecondsSinceEpoch}'),
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
                              ),
                            
                            if (videoState.status == PlayerStatus.recognizing || videoState.status == PlayerStatus.loading)
                              Positioned.fill(
                                child: LoadingOverlay(
                                  messages: videoState.statusMessages,
                                  backgroundOpacity: 0.5,
                                ),
                              ),
                            
                            if (videoState.hasVideo)
                              VerticalIndicator(videoState: videoState),
                            
                            if (globals.isPhone && videoState.hasVideo)
                              const BrightnessGestureArea(),
                            
                            if (globals.isPhone && videoState.hasVideo)
                              const VolumeGestureArea(),
                          ],
                        )
                      : Focus(
                          focusNode: _focusNode,
                          autofocus: true,
                          canRequestFocus: true,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: videoState.aspectRatio,
                                        child: Stack(
                                          children: [
                                            Texture(
                                              textureId: textureId,
                                              filterQuality: FilterQuality.medium,
                                            ),
                                            if (isLinuxPlatform) ...[
                                              TickerMode(
                                                enabled: true,
                                                child: Positioned.fill(
                                                  child: AnimatedBuilder(
                                                    animation: _linuxRefreshController,
                                                    builder: (context, child) {
                                                      return CustomPaint(
                                                        painter: _LinuxRefreshPainter(
                                                          animationValue: _linuxRefreshController.value,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                              TickerMode(
                                                enabled: true,
                                                child: Positioned.fill(
                                                  child: AnimatedBuilder(
                                                    animation: _linuxFastRefreshController,
                                                    builder: (context, child) {
                                                      return Opacity(
                                                        opacity: 0.001 + 0.001 * _linuxFastRefreshController.value,
                                                        child: Container(
                                                          color: Colors.transparent,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              
                              if (videoState.hasVideo)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: true,
                                    child: Consumer<VideoPlayerState>(
                                      builder: (context, videoState, _) {
                                        if (!videoState.danmakuVisible) {
                                          return const SizedBox.shrink();
                                        }
                                        return DanmakuOverlay(
                                          key: ValueKey('danmaku_${videoState.currentVideoPath ?? DateTime.now().millisecondsSinceEpoch}'),
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
                                ),
                              
                              if (videoState.status == PlayerStatus.recognizing || videoState.status == PlayerStatus.loading)
                                Positioned.fill(
                                  child: LoadingOverlay(
                                    messages: videoState.statusMessages,
                                    backgroundOpacity: 0.5,
                                  ),
                                ),
                              
                              if (videoState.hasVideo)
                                VerticalIndicator(videoState: videoState),
                            ],
                          ),
                        ),
                  ),
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

/// Linux专用的刷新画布，绘制透明内容触发重绘
class _LinuxRefreshPainter extends CustomPainter {
  final double animationValue;
  
  _LinuxRefreshPainter({required this.animationValue});
  
  @override
  void paint(Canvas canvas, Size size) {
    // 完全透明的绘制，但每一帧都会绘制，迫使视频纹理刷新
    final paint = Paint()
      ..color = Colors.transparent.withOpacity(0.001)
      ..style = PaintingStyle.fill;
      
    // 在不同位置绘制一些点，但它们是不可见的
    final x = size.width * (0.1 + 0.1 * math.sin(animationValue * math.pi * 2));
    final y = size.height * (0.1 + 0.1 * math.cos(animationValue * math.pi * 2));
    
    canvas.drawCircle(Offset(x, y), 1.0, paint);
  }
  
  @override
  bool shouldRepaint(_LinuxRefreshPainter oldDelegate) => 
      oldDelegate.animationValue != animationValue;
} 