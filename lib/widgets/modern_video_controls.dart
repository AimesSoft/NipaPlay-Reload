import 'package:flutter/material.dart';
import 'dart:ui';
import '../utils/video_player_state.dart';
import '../utils/keyboard_shortcuts.dart';
import '../utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'tooltip_bubble.dart';
import 'video_progress_bar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'bounce_hover_scale.dart';
import 'video_settings_menu.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class ModernVideoControls extends StatefulWidget {
  const ModernVideoControls({super.key});

  @override
  State<ModernVideoControls> createState() => _ModernVideoControlsState();
}

class _ModernVideoControlsState extends State<ModernVideoControls> {
  bool _isRewindPressed = false;
  bool _isForwardPressed = false;
  bool _isPlayPressed = false;
  bool _isSettingsPressed = false;
  bool _isFullscreenPressed = false;
  bool _isRewindHovered = false;
  bool _isForwardHovered = false;
  bool _isPlayHovered = false;
  bool _isSettingsHovered = false;
  bool _isFullscreenHovered = false;
  bool _isDragging = false;
  bool? _wasPlayingBeforeDrag;
  bool _playStateChangedByDrag = false;
  OverlayEntry? _settingsOverlay;
  Timer? _doubleTapTimer;
  int _tapCount = 0;
  static const _doubleTapTimeout = Duration(milliseconds: 300);
  bool _isProcessingTap = false;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildControlButton({
    required Widget icon,
    required VoidCallback onTap,
    required bool isPressed,
    required bool isHovered,
    required void Function(bool) onHover,
    required void Function(bool) onPressed,
    required String tooltip,
    bool useAnimatedSwitcher = false,
    bool useCustomAnimation = false,
  }) {
    Widget iconWidget = icon;
    if (useAnimatedSwitcher) {
      iconWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: animation,
            child: child,
          );
        },
        child: icon,
      );
    } else if (useCustomAnimation) {
      iconWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            ),
          );
        },
        child: icon,
      );
    }

    return TooltipBubble(
      text: tooltip,
      showOnTop: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onPressed(true),
          onTapUp: (_) => onPressed(false),
          onTapCancel: () => onPressed(false),
          onTap: onTap,
          child: BounceHoverScale(
            isHovered: isHovered,
            isPressed: isPressed,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isHovered ? 1.0 : 0.6,
              child: iconWidget,
            ),
          ),
        ),
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    _settingsOverlay?.remove();
    
    _settingsOverlay = OverlayEntry(
      builder: (context) => VideoSettingsMenu(
        onClose: () {
          _settingsOverlay?.remove();
          _settingsOverlay = null;
        },
      ),
    );

    Overlay.of(context).insert(_settingsOverlay!);
  }

  @override
  void dispose() {
    _settingsOverlay?.remove();
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_isProcessingTap) return;
    
    _tapCount++;
    if (_tapCount == 1) {
      // 立即处理单次点击
      _handleSingleTap();
      // 启动双击检测定时器
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(_doubleTapTimeout, () {
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
      videoState.togglePlayPause();
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      _isProcessingTap = false;
    });
  }

  void _handleDoubleTap() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      videoState.toggleFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final backgroundColor = isDarkMode 
            ? const Color.fromARGB(255, 130, 130, 130).withOpacity(0.5)
            : const Color.fromARGB(255, 193, 193, 193).withOpacity(0.5);
        final borderColor = Colors.white.withOpacity(0.5);

        return Focus(
          canRequestFocus: true,
          autofocus: true,
          child: RawKeyboardListener(
            focusNode: videoState.focusNode,
            onKey: (event) {
              if (event is! RawKeyDownEvent) {
                return;
              }
              //print('RawKeyboardListener 收到按键事件: ${event.logicalKey}');
              // 消费事件，防止事件继续传播
              final result = KeyboardShortcuts.handleKeyEvent(event);
              if (result == KeyEventResult.handled) {
                return;
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: videoState.controlBarHeight,
                        left: globals.isPhone ? 20 : 100,
                        right: globals.isPhone ? 20 : 100,
                      ),
                      child: MouseRegion(
                        onEnter: (_) => videoState.setControlsHovered(true),
                        onExit: (_) => videoState.setControlsHovered(false),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: borderColor,
                                    width: 0.5,
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: globals.isPhone ? 6 : 20,
                                  ),
                                  child: Row(
                                    children: [
                                      // 快退按钮
                                      _buildControlButton(
                                        icon: Icon(
                                          Icons.fast_rewind_rounded,
                                          key: const ValueKey('rewind'),
                                          color: Colors.white,
                                          size: globals.isPhone ? 36 : 28,
                                        ),
                                        onTap: () {
                                          final newPosition = videoState.position - const Duration(seconds: 10);
                                          videoState.seekTo(newPosition);
                                        },
                                        isPressed: _isRewindPressed,
                                        isHovered: _isRewindHovered,
                                        onHover: (value) => setState(() => _isRewindHovered = value),
                                        onPressed: (value) => setState(() => _isRewindPressed = value),
                                        tooltip: KeyboardShortcuts.formatActionWithShortcut(
                                          '快退 10 秒',
                                          KeyboardShortcuts.getShortcutText('rewind')
                                        ),
                                        useAnimatedSwitcher: true,
                                      ),
                                      
                                      // 播放/暂停按钮
                                      _buildControlButton(
                                        icon: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 200),
                                          transitionBuilder: (child, animation) {
                                            return ScaleTransition(
                                              scale: animation,
                                              child: child,
                                            );
                                          },
                                          child: Icon(
                                            videoState.status == PlayerStatus.playing 
                                                ? Ionicons.pause
                                                : Ionicons.play,
                                            key: ValueKey<bool>(videoState.status == PlayerStatus.playing),
                                            color: Colors.white,
                                            size: globals.isPhone ? 48 : 36,
                                          ),
                                        ),
                                        onTap: () => videoState.togglePlayPause(),
                                        isPressed: _isPlayPressed,
                                        isHovered: _isPlayHovered,
                                        onHover: (value) => setState(() => _isPlayHovered = value),
                                        onPressed: (value) => setState(() => _isPlayPressed = value),
                                        tooltip: KeyboardShortcuts.formatActionWithShortcut(
                                          videoState.status == PlayerStatus.playing ? '暂停' : '播放',
                                          KeyboardShortcuts.getShortcutText('play_pause')
                                        ),
                                        useAnimatedSwitcher: true,
                                      ),
                                      
                                      // 快进按钮
                                      _buildControlButton(
                                        icon: Icon(
                                          Icons.fast_forward_rounded,
                                          key: const ValueKey('forward'),
                                          color: Colors.white,
                                          size: globals.isPhone ? 36 : 28,
                                        ),
                                        onTap: () {
                                          final newPosition = videoState.position + const Duration(seconds: 10);
                                          videoState.seekTo(newPosition);
                                        },
                                        isPressed: _isForwardPressed,
                                        isHovered: _isForwardHovered,
                                        onHover: (value) => setState(() => _isForwardHovered = value),
                                        onPressed: (value) => setState(() => _isForwardPressed = value),
                                        tooltip: KeyboardShortcuts.formatActionWithShortcut(
                                          '快进 10 秒',
                                          KeyboardShortcuts.getShortcutText('forward')
                                        ),
                                        useAnimatedSwitcher: true,
                                      ),
                                      
                                      const SizedBox(width: 20),
                                      
                                      // 进度条
                                      Expanded(
                                        child: VideoProgressBar(
                                          videoState: videoState,
                                          hoverTime: null,
                                          isDragging: _isDragging,
                                          onPositionUpdate: (position) {},
                                          onDraggingStateChange: (isDragging) {
                                            if (isDragging) {
                                              // 开始拖动时，保存当前的播放状态
                                              _wasPlayingBeforeDrag = videoState.status == PlayerStatus.playing;
                                              // 如果是暂停状态，开始拖动时恢复播放
                                              if (videoState.status == PlayerStatus.paused) {
                                                _playStateChangedByDrag = true;
                                                videoState.togglePlayPause();
                                              }
                                            } else {
                                              // 拖动结束时，只有当是因为拖动而改变的播放状态时才恢复
                                              if (_playStateChangedByDrag) {
                                                videoState.togglePlayPause();
                                                _playStateChangedByDrag = false;
                                              }
                                              _wasPlayingBeforeDrag = null;
                                            }
                                            setState(() {
                                              _isDragging = isDragging;
                                            });
                                          },
                                          formatDuration: _formatDuration,
                                        ),
                                      ),
                                      
                                      const SizedBox(width: 6),
                                      
                                      // 时间显示
                                      DefaultTextStyle(
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          height: 1.0,
                                          textBaseline: TextBaseline.alphabetic,
                                        ),
                                        textAlign: TextAlign.center,
                                        child: SizedBox(
                                          width: 140,
                                          child: Text(
                                            '${_formatDuration(videoState.position)} / ${_formatDuration(videoState.duration)}',
                                          ),
                                        ),
                                      ),
                                      
                                      //const SizedBox(width: 0),
                                      
                                      // 设置按钮
                                      _buildControlButton(
                                        icon: Icon(
                                          Icons.tune_rounded,
                                          key: const ValueKey('settings'),
                                          color: Colors.white,
                                          size: globals.isPhone ? 36 : 28,
                                        ),
                                        onTap: () {
                                          _showSettingsMenu(context);
                                        },
                                        isPressed: _isSettingsPressed,
                                        isHovered: _isSettingsHovered,
                                        onHover: (value) => setState(() => _isSettingsHovered = value),
                                        onPressed: (value) => setState(() => _isSettingsPressed = value),
                                        tooltip: '设置',
                                        useAnimatedSwitcher: true,
                                      ),
                                      
                                      // 全屏按钮
                                      if (!globals.isPhone)
                                        _buildControlButton(
                                          icon: Icon(
                                            videoState.isFullscreen 
                                              ? Icons.fullscreen_exit_rounded 
                                              : Icons.fullscreen_rounded,
                                            key: ValueKey<bool>(videoState.isFullscreen),
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                          onTap: () => videoState.toggleFullscreen(),
                                          isPressed: _isFullscreenPressed,
                                          isHovered: _isFullscreenHovered,
                                          onHover: (value) => setState(() => _isFullscreenHovered = value),
                                          onPressed: (value) => setState(() => _isFullscreenPressed = value),
                                          tooltip: KeyboardShortcuts.formatActionWithShortcut(
                                            videoState.isFullscreen ? '退出全屏' : '全屏',
                                            KeyboardShortcuts.getShortcutText('fullscreen')
                                          ),
                                          useCustomAnimation: true,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
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
        );
      },
    );
  }

} 