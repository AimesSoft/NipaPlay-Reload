import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'video_upload_ui.dart';
import 'vertical_indicator.dart';
import 'loading_overlay.dart';
import '../danmaku_overlay.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'brightness_gesture_area.dart';
import 'volume_gesture_area.dart';
import 'blur_dialog.dart';
import 'right_edge_hover_menu.dart';

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

  double getFontSize(VideoPlayerState videoState) {
    return videoState.actualDanmakuFontSize;
  }

  @override
  void initState() {
    super.initState();
    // 移除键盘事件处理
    // _focusNode.onKey = _handleKeyEvent;
    
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
        // 移除键盘快捷键注册
        // _registerKeyboardShortcuts();
        
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

  // 移除键盘快捷键注册方法
  // void _registerKeyboardShortcuts() { ... }

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
    if (_isProcessingTap) return;
    _tapCount = 0;
    _doubleTapTimer?.cancel();
    
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      if (globals.isPhone) {
        videoState.togglePlayPause();
      } else {
        videoState.toggleFullscreen();
      }
    }
  }
  
  // 添加长按手势处理方法
  void _handleLongPressStart(VideoPlayerState videoState) {
    if (!globals.isPhone || !videoState.hasVideo) return;
    
    // 开始倍速播放
    videoState.startSpeedBoost();
    
    // 触觉反馈
    HapticFeedback.lightImpact();
  }
  
  void _handleLongPressEnd(VideoPlayerState videoState) {
    if (!globals.isPhone || !videoState.hasVideo) return;
    
    // 结束倍速播放
    videoState.stopSpeedBoost();
    
    // 触觉反馈
    HapticFeedback.lightImpact();
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
    

    
    super.dispose();
  }

  // 移除键盘事件处理方法
  // KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) { ... }

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
                  onLongPressStart: globals.isPhone ? (details) => _handleLongPressStart(videoState) : null,
                  onLongPressEnd: globals.isPhone ? (details) => _handleLongPressEnd(videoState) : null,
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
                                        // 修改：保持DanmakuOverlay组件始终存在，通过isVisible控制可见性
                                        // 避免销毁重建导致的延迟问题
                                        return DanmakuOverlay(
                                          key: ValueKey('danmaku_${videoState.danmakuOverlayKey}'),
                                          currentPosition: videoState.position.inMilliseconds.toDouble(),
                                          videoDuration: videoState.videoDuration.inMilliseconds.toDouble(),
                                          isPlaying: videoState.status == PlayerStatus.playing,
                                          fontSize: getFontSize(videoState),
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
                                        // 修改：保持DanmakuOverlay组件始终存在，通过isVisible控制可见性
                                        // 避免销毁重建导致的延迟问题
                                        return DanmakuOverlay(
                                          key: ValueKey('danmaku_${videoState.danmakuOverlayKey}'),
                                          currentPosition: videoState.position.inMilliseconds.toDouble(),
                                          videoDuration: videoState.videoDuration.inMilliseconds.toDouble(),
                                          isPlaying: videoState.status == PlayerStatus.playing,
                                          fontSize: getFontSize(videoState),
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
                              
                              // 右边缘悬浮菜单（仅桌面版）
                              const RightEdgeHoverMenu(),
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