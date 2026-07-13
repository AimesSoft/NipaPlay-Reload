import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'package:nipaplay/utils/shortcut_tooltip_manager.dart'; // 添加新的快捷键提示管理器
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'tooltip_bubble.dart';
import 'video_progress_bar.dart';
import 'control_shadow.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'bounce_hover_scale.dart';
import 'video_settings_menu.dart';
import 'dart:async';
import 'package:nipaplay/services/desktop_pip_window_service.dart';
import 'keyboard_activatable.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_player_menu.dart';

class ModernVideoControls extends StatefulWidget {
  final bool showFullscreenButton;
  final bool compactPortrait;

  const ModernVideoControls({
    super.key,
    this.showFullscreenButton = true,
    this.compactPortrait = false,
  });

  @override
  State<ModernVideoControls> createState() => _ModernVideoControlsState();
}

class _ModernVideoControlsState extends State<ModernVideoControls> {
  final GlobalKey _playlistButtonKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey();
  final GlobalKey _progressBarKey = GlobalKey();
  bool _isRewindPressed = false;
  bool _isForwardPressed = false;
  bool _isPlayPressed = false;
  bool _isPlaylistPressed = false;
  bool _isSettingsPressed = false;
  bool _isFullscreenPressed = false;
  bool _isRewindHovered = false;
  bool _isForwardHovered = false;
  bool _isPlayHovered = false;
  bool _isPlaylistHovered = false;
  bool _isSettingsHovered = false;
  bool _isFullscreenHovered = false;
  bool _isDragging = false;
  bool _playStateChangedByDrag = false;
  OverlayEntry? _playlistOverlay;
  OverlayEntry? _settingsOverlay;
  Timer? _doubleTapTimer;
  int _tapCount = 0;
  static const _doubleTapTimeout = Duration(milliseconds: 360);
  bool _isProcessingTap = false;
  bool _ignoreNextTap = false;

  // 快捷键提示管理器
  final ShortcutTooltipManager _tooltipManager = ShortcutTooltipManager();

  // 添加上一话/下一话按钮的状态变量
  bool _isPreviousEpisodePressed = false;
  bool _isNextEpisodePressed = false;
  bool _isPreviousEpisodeHovered = false;
  bool _isNextEpisodeHovered = false;
  bool _isPipPressed = false;
  bool _isPipHovered = false;
  bool _isDanmakuPressed = false;
  bool _isDanmakuHovered = false;

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
    bool enabled = true,
  }) {
    Widget iconWidget = icon;
    if (useAnimatedSwitcher) {
      iconWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return ScaleTransition(scale: animation, child: child);
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
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (enabled) {
            onHover(true);
          }
        },
        onExit: (_) => onHover(false),
        child: KeyboardActivatable(
          enabled: enabled,
          onActivate: onTap,
          onFocusChange: onHover,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => onPressed(true) : null,
            onTapUp: enabled ? (_) => onPressed(false) : null,
            onTapCancel: enabled ? () => onPressed(false) : null,
            onTap: enabled ? onTap : null,
            child: BounceHoverScale(
              isHovered: enabled && isHovered,
              isPressed: enabled && isPressed,
              child: ControlIconShadow(child: iconWidget),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSettingsMenu(BuildContext buttonContext) async {
    final videoState = Provider.of<VideoPlayerState>(
      buttonContext,
      listen: false,
    );
    if (widget.compactPortrait) {
      videoState.setControlsVisibilityLocked(true);
      try {
        await CupertinoBottomSheet.showPage<void>(
          context: buttonContext,
          title: '播放器菜单',
          heightRatio: 0.94,
          floatingTitle: true,
          rootPageBuilder: (_) => const CupertinoPlayerMenu(),
        );
      } finally {
        videoState.setControlsVisibilityLocked(false);
      }
      return;
    }
    _playlistOverlay?.remove();
    _playlistOverlay = null;
    _settingsOverlay?.remove();
    videoState.setControlsVisibilityLocked(true);

    Rect? anchorRect;
    final RenderBox? renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      anchorRect = position & renderBox.size;
    } else {
      final RenderBox? keyRenderBox =
          _settingsButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (keyRenderBox != null && keyRenderBox.hasSize) {
        final position = keyRenderBox.localToGlobal(Offset.zero);
        anchorRect = position & keyRenderBox.size;
      }
    }

    _settingsOverlay = OverlayEntry(
      builder: (context) => VideoSettingsMenu(
        anchorRect: anchorRect,
        anchorKey: _settingsButtonKey,
        onClose: () {
          videoState.setControlsVisibilityLocked(false);
          _settingsOverlay?.remove();
          _settingsOverlay = null;
        },
      ),
    );

    Overlay.of(buttonContext).insert(_settingsOverlay!);
  }

  void _showPlaylistMenu(BuildContext buttonContext) {
    final videoState = Provider.of<VideoPlayerState>(
      buttonContext,
      listen: false,
    );
    _settingsOverlay?.remove();
    _settingsOverlay = null;
    _playlistOverlay?.remove();
    videoState.setControlsVisibilityLocked(true);

    Rect? anchorRect;
    final RenderBox? renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      anchorRect = position & renderBox.size;
    } else {
      final RenderBox? keyRenderBox =
          _playlistButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (keyRenderBox != null && keyRenderBox.hasSize) {
        final position = keyRenderBox.localToGlobal(Offset.zero);
        anchorRect = position & keyRenderBox.size;
      }
    }

    _playlistOverlay = OverlayEntry(
      builder: (context) => VideoSettingsMenu(
        anchorRect: anchorRect,
        anchorKey: _playlistButtonKey,
        initialPaneId: PlayerMenuPaneId.playlist,
        hideBackButtonForInitialPane: true,
        onClose: () {
          videoState.setControlsVisibilityLocked(false);
          _playlistOverlay?.remove();
          _playlistOverlay = null;
        },
      ),
    );

    Overlay.of(buttonContext).insert(_playlistOverlay!);
  }

  @override
  void dispose() {
    _playlistOverlay?.remove();
    _settingsOverlay?.remove();
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_isProcessingTap) return;
    if (_ignoreNextTap || _isDragging) {
      _ignoreNextTap = false;
      _tapCount = 0;
      _doubleTapTimer?.cancel();
      return;
    }

    _tapCount++;
    if (_tapCount == 1) {
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(_doubleTapTimeout, () {
        if (!mounted) return;
        if (_tapCount == 1 && !_isProcessingTap) {
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
      videoState.togglePlayPause();
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      _isProcessingTap = false;
    });
  }

  void _handleDoubleTap() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      videoState.togglePlayPause();
    }
  }

  bool _isTapOnProgressBar(Offset globalPosition) {
    final context = _progressBarKey.currentContext;
    if (context == null) return false;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return rect.contains(globalPosition);
  }

  Future<void> _handlePipButtonTap(VideoPlayerState videoState) async {
    final pipService = DesktopPipWindowService.instance;
    if (pipService.isCurrentWindowPip) {
      await pipService.closeCurrentPipWindowAndRestore(videoState);
      return;
    }
    await pipService.openPipWindow(videoState);
  }

  Widget _buildProgressBar(
    VideoPlayerState videoState, {
    bool compact = false,
  }) {
    return VideoProgressBar(
      key: _progressBarKey,
      videoState: videoState,
      hoverTime: null,
      isDragging: _isDragging,
      compact: compact,
      chapters:
          videoState.chapterMarkersEnabled ? videoState.chapters : const [],
      durationMs: videoState.duration.inMilliseconds,
      currentChapter: videoState.currentChapter,
      onPositionUpdate: (_) {},
      onDraggingStateChange: (isDragging) {
        if (isDragging && videoState.status == PlayerStatus.paused) {
          _playStateChangedByDrag = true;
          videoState.togglePlayPause();
        } else if (!isDragging && _playStateChangedByDrag) {
          videoState.togglePlayPause();
          _playStateChangedByDrag = false;
        }
        setState(() {
          _isDragging = isDragging;
        });
      },
      formatDuration: _formatDuration,
    );
  }

  Widget _buildCompactPortraitControls(VideoPlayerState videoState) {
    const iconSize = 28.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: MouseRegion(
        onEnter: (_) => videoState.setControlsHovered(true),
        onExit: (_) => videoState.setControlsHovered(false),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildControlButton(
              icon: Icon(
                videoState.status == PlayerStatus.playing
                    ? Ionicons.pause
                    : Ionicons.play,
                key: ValueKey<bool>(
                  videoState.status == PlayerStatus.playing,
                ),
                color: Colors.white,
                size: 32,
              ),
              onTap: videoState.togglePlayPause,
              isPressed: _isPlayPressed,
              isHovered: _isPlayHovered,
              onHover: (value) => setState(() => _isPlayHovered = value),
              onPressed: (value) => setState(() => _isPlayPressed = value),
              tooltip: videoState.status == PlayerStatus.playing ? '暂停' : '播放',
              useAnimatedSwitcher: true,
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildProgressBar(videoState, compact: true)),
            const SizedBox(width: 8),
            Builder(
              builder: (buttonContext) => SizedBox(
                key: _settingsButtonKey,
                child: _buildControlButton(
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  onTap: () => unawaited(_showSettingsMenu(buttonContext)),
                  isPressed: _isSettingsPressed,
                  isHovered: _isSettingsHovered,
                  onHover: (value) =>
                      setState(() => _isSettingsHovered = value),
                  onPressed: (value) =>
                      setState(() => _isSettingsPressed = value),
                  tooltip: '播放器菜单',
                ),
              ),
            ),
            if (widget.showFullscreenButton) ...[
              const SizedBox(width: 8),
              _buildControlButton(
                icon: Icon(
                  videoState.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  key: ValueKey<bool>(videoState.isFullscreen),
                  color: Colors.white,
                  size: iconSize,
                ),
                onTap: videoState.toggleFullscreen,
                isPressed: _isFullscreenPressed,
                isHovered: _isFullscreenHovered,
                onHover: (value) =>
                    setState(() => _isFullscreenHovered = value),
                onPressed: (value) =>
                    setState(() => _isFullscreenPressed = value),
                tooltip: videoState.isFullscreen ? '退出全屏' : '全屏',
                useCustomAnimation: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tooltipManager,
      builder: (context, child) {
        return Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            if (widget.compactPortrait) {
              return _buildCompactPortraitControls(videoState);
            }
            return Focus(
              canRequestFocus: true,
              autofocus: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  _ignoreNextTap = _isTapOnProgressBar(details.globalPosition);
                },
                onTapCancel: () {
                  _ignoreNextTap = false;
                },
                onTap: _handleTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: videoState.controlBarHeight,
                          left: 20,
                          right: 20,
                        ),
                        child: MouseRegion(
                          onEnter: (_) => videoState.setControlsHovered(true),
                          onExit: (_) => videoState.setControlsHovered(false),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: globals.isPhone ? 6 : 20,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProgressBar(videoState),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    // 上一话按钮
                                    Consumer<VideoPlayerState>(
                                      builder: (context, videoState, child) {
                                        final canPlayPrevious =
                                            videoState.canPlayPreviousEpisode;
                                        return AnimatedOpacity(
                                          opacity: canPlayPrevious ? 1.0 : 0.3,
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: _buildControlButton(
                                            icon: Icon(
                                              Icons.skip_previous_rounded,
                                              key: const ValueKey(
                                                  'previous_episode'),
                                              color: Colors.white,
                                              size: globals.isPhone ? 36 : 28,
                                            ),
                                            onTap: canPlayPrevious
                                                ? () {
                                                    videoState
                                                        .playPreviousEpisode();
                                                  }
                                                : () {},
                                            enabled: canPlayPrevious,
                                            isPressed:
                                                _isPreviousEpisodePressed,
                                            isHovered:
                                                _isPreviousEpisodeHovered,
                                            onHover: (value) => setState(() =>
                                                _isPreviousEpisodeHovered =
                                                    value),
                                            onPressed: (value) => setState(() =>
                                                _isPreviousEpisodePressed =
                                                    value),
                                            tooltip: canPlayPrevious
                                                ? _tooltipManager
                                                    .formatActionWithShortcut(
                                                        'previous_episode',
                                                        '上一话')
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
                                        videoState.seekBackwardByStep();
                                      },
                                      isPressed: _isRewindPressed,
                                      isHovered: _isRewindHovered,
                                      onHover: (value) => setState(
                                          () => _isRewindHovered = value),
                                      onPressed: (value) => setState(
                                          () => _isRewindPressed = value),
                                      tooltip: _tooltipManager
                                          .formatActionWithShortcut('rewind',
                                              '快退 ${videoState.seekStepDisplayLabel}'),
                                      useAnimatedSwitcher: true,
                                    ),

                                    // 播放/暂停按钮
                                    _buildControlButton(
                                      icon: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        transitionBuilder: (child, animation) {
                                          return ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          );
                                        },
                                        child: Icon(
                                          videoState.status ==
                                                  PlayerStatus.playing
                                              ? Ionicons.pause
                                              : Ionicons.play,
                                          key: ValueKey<bool>(
                                              videoState.status ==
                                                  PlayerStatus.playing),
                                          color: Colors.white,
                                          size: globals.isPhone ? 48 : 36,
                                        ),
                                      ),
                                      onTap: () => videoState.togglePlayPause(),
                                      isPressed: _isPlayPressed,
                                      isHovered: _isPlayHovered,
                                      onHover: (value) => setState(
                                          () => _isPlayHovered = value),
                                      onPressed: (value) => setState(
                                          () => _isPlayPressed = value),
                                      tooltip: videoState.status ==
                                              PlayerStatus.playing
                                          ? _tooltipManager
                                              .formatActionWithShortcut(
                                                  'play_pause', '暂停')
                                          : _tooltipManager
                                              .formatActionWithShortcut(
                                                  'play_pause', '播放'),
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
                                        videoState.seekForwardByStep();
                                      },
                                      isPressed: _isForwardPressed,
                                      isHovered: _isForwardHovered,
                                      onHover: (value) => setState(
                                          () => _isForwardHovered = value),
                                      onPressed: (value) => setState(
                                          () => _isForwardPressed = value),
                                      tooltip: _tooltipManager
                                          .formatActionWithShortcut('forward',
                                              '快进 ${videoState.seekStepDisplayLabel}'),
                                      useAnimatedSwitcher: true,
                                    ),

                                    // 下一话按钮
                                    Consumer<VideoPlayerState>(
                                      builder: (context, videoState, child) {
                                        final canPlayNext =
                                            videoState.canPlayNextEpisode;
                                        return AnimatedOpacity(
                                          opacity: canPlayNext ? 1.0 : 0.3,
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: _buildControlButton(
                                            icon: Icon(
                                              Icons.skip_next_rounded,
                                              key: const ValueKey(
                                                  'next_episode'),
                                              color: Colors.white,
                                              size: globals.isPhone ? 36 : 28,
                                            ),
                                            onTap: canPlayNext
                                                ? () {
                                                    videoState
                                                        .playNextEpisode();
                                                  }
                                                : () {},
                                            enabled: canPlayNext,
                                            isPressed: _isNextEpisodePressed,
                                            isHovered: _isNextEpisodeHovered,
                                            onHover: (value) => setState(() =>
                                                _isNextEpisodeHovered = value),
                                            onPressed: (value) => setState(() =>
                                                _isNextEpisodePressed = value),
                                            tooltip: canPlayNext
                                                ? _tooltipManager
                                                    .formatActionWithShortcut(
                                                        'next_episode', '下一话')
                                                : '无法播放下一话',
                                            useAnimatedSwitcher: true,
                                          ),
                                        );
                                      },
                                    ),

                                    const Spacer(),

                                    // 时间显示
                                    ControlTextShadow(
                                      child: Text(
                                        '${_formatDuration(videoState.position)} / ${_formatDuration(videoState.duration)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          height: 1.0,
                                          textBaseline: TextBaseline.alphabetic,
                                        ),
                                        textAlign: TextAlign.center,
                                        softWrap: false,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    if (globals.isDesktop &&
                                        DesktopPipWindowService
                                            .isFeatureEnabled)
                                      _buildControlButton(
                                        icon: Icon(
                                          DesktopPipWindowService
                                                  .instance.isCurrentWindowPip
                                              ? Icons.picture_in_picture_rounded
                                              : Icons
                                                  .picture_in_picture_alt_rounded,
                                          key: ValueKey<bool>(
                                            DesktopPipWindowService
                                                .instance.isCurrentWindowPip,
                                          ),
                                          color: Colors.white,
                                          size: globals.isPhone ? 36 : 28,
                                        ),
                                        onTap: () {
                                          unawaited(
                                            _handlePipButtonTap(videoState),
                                          );
                                        },
                                        isPressed: _isPipPressed,
                                        isHovered: _isPipHovered,
                                        onHover: (value) => setState(
                                            () => _isPipHovered = value),
                                        onPressed: (value) => setState(
                                            () => _isPipPressed = value),
                                        tooltip: DesktopPipWindowService
                                                .instance.isCurrentWindowPip
                                            ? '关闭小窗并回到主播放'
                                            : '小窗播放',
                                        useAnimatedSwitcher: true,
                                      ),

                                    if (globals.isDesktop &&
                                        DesktopPipWindowService
                                            .isFeatureEnabled)
                                      const SizedBox(width: 12),

                                    // 弹幕开关按钮
                                    _buildControlButton(
                                      icon: _DanmakuToggleIcon(
                                        key: ValueKey<bool>(
                                          videoState.danmakuVisible,
                                        ),
                                        visible: videoState.danmakuVisible,
                                        size: globals.isPhone ? 32 : 24,
                                      ),
                                      onTap: () =>
                                          videoState.toggleDanmakuVisible(),
                                      isPressed: _isDanmakuPressed,
                                      isHovered: _isDanmakuHovered,
                                      onHover: (value) => setState(
                                          () => _isDanmakuHovered = value),
                                      onPressed: (value) => setState(
                                          () => _isDanmakuPressed = value),
                                      tooltip: _tooltipManager
                                          .formatActionWithShortcut(
                                              'toggle_danmaku',
                                              videoState.danmakuVisible
                                                  ? '隐藏弹幕'
                                                  : '显示弹幕'),
                                      useAnimatedSwitcher: true,
                                    ),

                                    const SizedBox(width: 8),

                                    // 播放列表按钮（独立于设置菜单）
                                    Builder(
                                      builder: (buttonContext) {
                                        return SizedBox(
                                          key: _playlistButtonKey,
                                          child: _buildControlButton(
                                            icon: Icon(
                                              Icons.playlist_play_rounded,
                                              key: const ValueKey('playlist'),
                                              color: Colors.white,
                                              size: globals.isPhone ? 36 : 28,
                                            ),
                                            onTap: () {
                                              _showPlaylistMenu(buttonContext);
                                            },
                                            isPressed: _isPlaylistPressed,
                                            isHovered: _isPlaylistHovered,
                                            onHover: (value) => setState(() =>
                                                _isPlaylistHovered = value),
                                            onPressed: (value) => setState(() =>
                                                _isPlaylistPressed = value),
                                            tooltip: '播放列表',
                                            useAnimatedSwitcher: true,
                                          ),
                                        );
                                      },
                                    ),

                                    // 设置按钮
                                    Builder(
                                      builder: (buttonContext) {
                                        return SizedBox(
                                          key: _settingsButtonKey,
                                          child: _buildControlButton(
                                            icon: Icon(
                                              Icons.tune_rounded,
                                              key: const ValueKey('settings'),
                                              color: Colors.white,
                                              size: globals.isPhone ? 36 : 28,
                                            ),
                                            onTap: () {
                                              unawaited(
                                                _showSettingsMenu(
                                                  buttonContext,
                                                ),
                                              );
                                            },
                                            isPressed: _isSettingsPressed,
                                            isHovered: _isSettingsHovered,
                                            onHover: (value) => setState(() =>
                                                _isSettingsHovered = value),
                                            onPressed: (value) => setState(() =>
                                                _isSettingsPressed = value),
                                            tooltip: '设置',
                                            useAnimatedSwitcher: true,
                                          ),
                                        );
                                      },
                                    ),

                                    // 全屏按钮（所有平台）或菜单栏切换按钮（平板）
                                    if (widget.showFullscreenButton)
                                      _buildControlButton(
                                        icon: Icon(
                                          globals.isTablet
                                              ? (videoState.isAppBarHidden
                                                  ? Icons
                                                      .fullscreen_exit_rounded
                                                  : Icons.fullscreen_rounded)
                                              : (videoState.isFullscreen
                                                  ? Icons
                                                      .fullscreen_exit_rounded
                                                  : Icons.fullscreen_rounded),
                                          key: ValueKey<bool>(
                                            globals.isTablet
                                                ? videoState.isAppBarHidden
                                                : videoState.isFullscreen,
                                          ),
                                          color: Colors.white,
                                          size: globals.isPhone ? 36 : 32,
                                        ),
                                        onTap: () => globals.isTablet
                                            ? videoState
                                                .toggleAppBarVisibility()
                                            : videoState.toggleFullscreen(),
                                        isPressed: _isFullscreenPressed,
                                        isHovered: _isFullscreenHovered,
                                        onHover: (value) => setState(
                                            () => _isFullscreenHovered = value),
                                        onPressed: (value) => setState(
                                            () => _isFullscreenPressed = value),
                                        tooltip: globals.isTablet
                                            ? (videoState.isAppBarHidden
                                                ? '显示菜单栏'
                                                : '隐藏菜单栏')
                                            : globals.isPhone
                                                ? (videoState.isFullscreen
                                                    ? '退出全屏'
                                                    : '全屏')
                                                : _tooltipManager
                                                    .formatActionWithShortcut(
                                                    'fullscreen',
                                                    videoState.isFullscreen
                                                        ? '退出全屏'
                                                        : '全屏',
                                                  ),
                                        useCustomAnimation: true,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DanmakuToggleIcon extends StatelessWidget {
  const _DanmakuToggleIcon({
    super.key,
    required this.visible,
    required this.size,
  });

  final bool visible;
  final double size;

  @override
  Widget build(BuildContext context) {
    final offSvgString = visible ? null : _danmakuOffSvgString();

    Widget buildSvg({ColorFilter? colorFilter}) {
      return visible
          ? SvgPicture.asset(
              'assets/danmaku-fill.svg',
              width: size,
              height: size,
              colorFilter: colorFilter,
            )
          : SvgPicture.string(
              offSvgString!,
              width: size,
              height: size,
              colorFilter: colorFilter,
            );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildSvgShadow(
            buildSvg,
            const Offset(0, 1.5),
            2.5,
            const Color.fromARGB(64, 0, 0, 0),
          ),
          _buildSvgShadow(
            buildSvg,
            const Offset(0, 3),
            5,
            const Color.fromARGB(48, 0, 0, 0),
          ),
          Positioned.fill(child: buildSvg()),
        ],
      ),
    );
  }

  Widget _buildSvgShadow(
    Widget Function({ColorFilter? colorFilter}) buildSvg,
    Offset offset,
    double blurSigma,
    Color color,
  ) {
    return Positioned.fill(
      child: Transform.translate(
        offset: offset,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: buildSvg(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  String _danmakuOffSvgString() {
    final accentColor = AppAccentColors.current;
    final r = (accentColor.r * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    final g = (accentColor.g * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    final b = (accentColor.b * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return _danmakuOffFillSvg.replaceAll('{{ACCENT_COLOR}}', '#$r$g$b');
  }

  static const String _danmakuOffFillSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" fill-rule="evenodd"><path fill="white" d="M18 3a3 3 0 0 1 3 3v4.437a7 7 0 0 0-10.232 7.988L8 20.5c-.824.618-2 .03-2-1V18H5a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3h12M9 12H3a1 1 0 1 0 0 2h6a1 1 0 1 0 0-2M7 7H5a1 1 0 0 0-.117 1.993L5 9h2a1 1 0 0 0 .117-1.993zm12 0h-8a1 1 0 0 0-.117 1.993L11 9h8a1 1 0 0 0 .117-1.993z"/><path xmlns="http://www.w3.org/2000/svg" fill="{{ACCENT_COLOR}}" d="M13 16.5a4.5 4.5 0 1 1 9 0a4.5 4.5 0 0 1-9 0m2.172-.914a2.5 2.5 0 0 0 3.241 3.241zm1.414-1.414l3.242 3.242a2.5 2.5 0 0 0-3.241-3.241"/></g></svg>';
}
