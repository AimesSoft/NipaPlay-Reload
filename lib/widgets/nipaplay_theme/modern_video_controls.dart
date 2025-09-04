import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/utils/video_player_state.dart';

import 'package:nipaplay/utils/shortcut_tooltip_manager.dart'; // 添加新的快捷键提示管理器
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'tooltip_bubble.dart';
import 'video_progress_bar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'bounce_hover_scale.dart';
import 'video_settings_menu.dart';
import 'dart:async';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
  
  // 快捷键提示管理器
  final ShortcutTooltipManager _tooltipManager = ShortcutTooltipManager();
  
  // 添加上一话/下一话按钮的状态变量
  bool _isPreviousEpisodePressed = false;
  bool _isNextEpisodePressed = false;
  bool _isPreviousEpisodeHovered = false;
  bool _isNextEpisodeHovered = false;


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
        // 移除颜色随模式变化的逻辑，直接使用统一的毛玻璃效果
        final backgroundColor = Colors.white.withOpacity(0.15);
        final borderColor = Colors.white.withOpacity(0.3);

        return Focus(
          canRequestFocus: true,
          autofocus: true,
          child: Container(
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
                        left:20,
                        right:20,
                      ),
                      child: MouseRegion(
                        onEnter: (_) => videoState.setControlsHovered(true),
                        onExit: (_) => videoState.setControlsHovered(false),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(30),
                            right: Radius.circular(30),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 50 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 50 : 0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(30),
                                  right: Radius.circular(30),
                                ),
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
                                //height: globals.isPhone && !globals.isTablet? 30.0 : 60.0,
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(30),
                                    right: Radius.circular(30),
                                  ),
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
                                        // 上一话按钮
                                        Consumer<VideoPlayerState>(
                                          builder: (context, videoState, child) {
                                            final canPlayPrevious = videoState.canPlayPreviousEpisode;
                                            return AnimatedOpacity(
                                              opacity: canPlayPrevious ? 1.0 : 0.3,
                                              duration: const Duration(milliseconds: 200),
                                              child: _buildControlButton(
                                                icon: Icon(
                                                  Icons.skip_previous_rounded,
                                                  key: const ValueKey('previous_episode'),
                                                  color: Colors.white,
                                                  size: globals.isPhone ? 36 : 28,
                                                ),
                                                onTap: canPlayPrevious ? () {
                                                  videoState.playPreviousEpisode();
                                                } : () {},
                                                isPressed: _isPreviousEpisodePressed,
                                                isHovered: _isPreviousEpisodeHovered,
                                                onHover: (value) => setState(() => _isPreviousEpisodeHovered = value),
                                                onPressed: (value) => setState(() => _isPreviousEpisodePressed = value),
                                                tooltip: canPlayPrevious 
                                                  ? _tooltipManager.formatActionWithShortcut('previous_episode', '上一话')
                                                  : '无法播放上一话',
                                                useAnimatedSwitcher: true,
                                              ),
                                            );
                                          },
                                        ),
                                        
                                        // 快退按钮
                                        _buildControlButton(
                                          icon: Icon(
                                            Icons.fast_rewind_rounded,
                                            key: const ValueKey('rewind'),
                                            color: Colors.white,
                                            size: globals.isPhone ? 36 : 28,
                                          ),
                                          onTap: () {
                                            final newPosition = videoState.position - Duration(seconds: videoState.seekStepSeconds);
                                            videoState.seekTo(newPosition);
                                          },
                                          isPressed: _isRewindPressed,
                                          isHovered: _isRewindHovered,
                                          onHover: (value) => setState(() => _isRewindHovered = value),
                                          onPressed: (value) => setState(() => _isRewindPressed = value),
                                          tooltip: _tooltipManager.formatActionWithShortcut('rewind', '快退 ${videoState.seekStepSeconds} 秒'),
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
                                        tooltip: videoState.status == PlayerStatus.playing 
                                          ? _tooltipManager.formatActionWithShortcut('play_pause', '暂停')
                                          : _tooltipManager.formatActionWithShortcut('play_pause', '播放'),
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
                                            final newPosition = videoState.position + Duration(seconds: videoState.seekStepSeconds);
                                            videoState.seekTo(newPosition);
                                          },
                                          isPressed: _isForwardPressed,
                                          isHovered: _isForwardHovered,
                                          onHover: (value) => setState(() => _isForwardHovered = value),
                                          onPressed: (value) => setState(() => _isForwardPressed = value),
                                          tooltip: _tooltipManager.formatActionWithShortcut('forward', '快进 ${videoState.seekStepSeconds} 秒'),
                                          useAnimatedSwitcher: true,
                                        ),
                                        
                                        // 下一话按钮
                                        Consumer<VideoPlayerState>(
                                          builder: (context, videoState, child) {
                                            final canPlayNext = videoState.canPlayNextEpisode;
                                            return AnimatedOpacity(
                                              opacity: canPlayNext ? 1.0 : 0.3,
                                              duration: const Duration(milliseconds: 200),
                                              child: _buildControlButton(
                                                icon: Icon(
                                                  Icons.skip_next_rounded,
                                                  key: const ValueKey('next_episode'),
                                                  color: Colors.white,
                                                  size: globals.isPhone ? 36 : 28,
                                                ),
                                                onTap: canPlayNext ? () {
                                                  videoState.playNextEpisode();
                                                } : () {},
                                                isPressed: _isNextEpisodePressed,
                                                isHovered: _isNextEpisodeHovered,
                                                onHover: (value) => setState(() => _isNextEpisodeHovered = value),
                                                onPressed: (value) => setState(() => _isNextEpisodePressed = value),
                                                tooltip: canPlayNext 
                                                  ? _tooltipManager.formatActionWithShortcut('next_episode', '下一话')
                                                  : '无法播放下一话',
                                                useAnimatedSwitcher: true,
                                              ),
                                            );
                                          },
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
                                        child: Text(
                                          '${_formatDuration(videoState.position)} / ${_formatDuration(videoState.duration)}',
                                          softWrap: false,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                      
                                      const SizedBox(width: 12),
                                      
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
                                      
                                      // 全屏按钮（所有平台）或菜单栏切换按钮（平板）
                                      _buildControlButton(
                                        icon: Icon(
                                          globals.isTablet 
                                            ? (videoState.isAppBarHidden 
                                                ? Icons.fullscreen_exit_rounded 
                                                : Icons.fullscreen_rounded)
                                            : (videoState.isFullscreen 
                                                ? Icons.fullscreen_exit_rounded 
                                                : Icons.fullscreen_rounded),
                                          key: ValueKey<bool>(globals.isTablet ? videoState.isAppBarHidden : videoState.isFullscreen),
                                          color: Colors.white,
                                          size: globals.isPhone ? 36 : 32,
                                        ),
                                        onTap: () => globals.isTablet 
                                          ? videoState.toggleAppBarVisibility() 
                                          : videoState.toggleFullscreen(),
                                        isPressed: _isFullscreenPressed,
                                        isHovered: _isFullscreenHovered,
                                        onHover: (value) => setState(() => _isFullscreenHovered = value),
                                        onPressed: (value) => setState(() => _isFullscreenPressed = value),
                                        tooltip: globals.isTablet 
                                          ? (videoState.isAppBarHidden ? '显示菜单栏' : '隐藏菜单栏')
                                          : globals.isPhone
                                            ? (videoState.isFullscreen ? '退出全屏' : '全屏')
                                            : _tooltipManager.formatActionWithShortcut(
                                                'fullscreen',
                                                videoState.isFullscreen ? '退出全屏' : '全屏'
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