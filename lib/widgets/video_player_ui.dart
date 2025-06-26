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
import 'blur_dialog.dart';

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI> {
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

  // <<< ADDED: Hold a reference to VideoPlayerState for managing the callback
  VideoPlayerState? _videoPlayerStateInstance;

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
    
    // 使用安全的方式初始化，避免在卸载后访问context
    _safeInitialize();

    // <<< ADDED: Setup callback for serious errors
    // We need to get the VideoPlayerState instance.
    // Since this is initState, and Consumer is used in build,
    // we use Provider.of with listen: false.
    // It's often safer to do this in didChangeDependencies if context is needed
    // more reliably, but for listen:false, initState is usually fine.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _videoPlayerStateInstance = Provider.of<VideoPlayerState>(context, listen: false);
        _videoPlayerStateInstance?.onSeriousPlaybackErrorAndShouldPop = () async {
          if (mounted && _videoPlayerStateInstance != null) {
            // 获取当前的错误信息用于显示
            final String errorMessage = _videoPlayerStateInstance!.error ?? "发生未知播放错误，已停止播放。";

            // 显示 BlurDialog
            BlurDialog.show<void>(
              context: context, // 使用 VideoPlayerUI 的 context
              title: '播放错误',
              content: errorMessage,
              actions: [
                TextButton(
                  child: const Text('确定'),
                  onPressed: () {
                    // 1. Pop the dialog
                    //    这里的 context 是 BlurDialog.show 内部创建的用于对话框的 context
                    Navigator.of(context).pop(); 

                    // 2. Reset the player state.
                    //    这将导致 VideoPlayerUI 重建并因 hasVideo 为 false 而显示 VideoUploadUI。
                    _videoPlayerStateInstance!.resetPlayer();
                  },
                ),
              ],
            );
          } else {
            print("[VideoPlayerUI] onSeriousPlaybackErrorAndShouldPop: Not mounted or _videoPlayerStateInstance is null.");
          }
        };

        // 设置上下文，以便 VideoPlayerState 可以访问
        _videoPlayerStateInstance?.setContext(context);

        // 其他初始化逻辑...
        // ...
      }
    });
  }
  
  // 使用单独的方法进行安全初始化
  Future<void> _safeInitialize() async {
    // 使用微任务确保在当前帧渲染完成后执行
    Future.microtask(() {
      // 首先检查组件是否仍然挂载
      if (!mounted) return;
      
      try {
        _registerKeyboardShortcuts();
        
        // 安全获取视频状态
        final videoState = Provider.of<VideoPlayerState>(context, listen: false);
        videoState.setContext(context);
        
        // 如果不是手机，重置鼠标隐藏计时器
        if (!globals.isPhone) {
          _resetMouseHideTimer();
        }
      } catch (e) {
        // 捕获并记录任何异常
        print('VideoPlayerUI初始化出错: $e');
      }
    });
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
    
    // 注册上一话/下一话的动作处理器
    KeyboardShortcuts.registerActionHandler('previous_episode', () {
      if (videoState.canPlayPreviousEpisode) {
        videoState.playPreviousEpisode();
      }
    });

    KeyboardShortcuts.registerActionHandler('next_episode', () {
      if (videoState.canPlayNextEpisode) {
        videoState.playNextEpisode();
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

  @override
  void dispose() {
    // <<< ADDED: Clear the callback to prevent memory leaks
    _videoPlayerStateInstance?.onSeriousPlaybackErrorAndShouldPop = null;

    // 确保清理所有资源
    _focusNode.dispose();
    _doubleTapTimer?.cancel();
    _mouseMoveTimer?.cancel();
    
    // 清理键盘快捷键注册
    // 注意：KeyboardShortcuts没有提供unregisterActionHandler方法
    // 我们可以替换之前注册的处理程序为空函数，以防止在组件卸载后被调用
    try {
      if (!mounted) {
        // 用空函数替换所有注册的处理程序
        KeyboardShortcuts.registerActionHandler('play_pause', () {});
        KeyboardShortcuts.registerActionHandler('fullscreen', () {});
        KeyboardShortcuts.registerActionHandler('rewind', () {});
        KeyboardShortcuts.registerActionHandler('forward', () {});
        KeyboardShortcuts.registerActionHandler('toggle_danmaku', () {});
        KeyboardShortcuts.registerActionHandler('volume_up', () {});
        KeyboardShortcuts.registerActionHandler('volume_down', () {});
      }
    } catch (e) {
      print('清理VideoPlayerUI键盘快捷键时出错: $e');
    }
    
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

        if (textureId != null && textureId >= 0) {
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
                                      child: Texture(
                                        textureId: textureId,
                                        filterQuality: FilterQuality.medium,
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
                                  highPriorityAnimation: !videoState.isInFinalLoadingPhase,
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
                                        child: Texture(
                                          textureId: textureId,
                                          filterQuality: FilterQuality.medium,
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
                                    highPriorityAnimation: !videoState.isInFinalLoadingPhase,
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