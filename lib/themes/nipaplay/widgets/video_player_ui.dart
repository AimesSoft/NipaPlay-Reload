import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/context_menu/context_menu.dart';
import 'package:nipaplay/widgets/danmaku_overlay.dart';
import 'package:provider/provider.dart';
import 'brightness_gesture_area.dart';
import 'volume_gesture_area.dart';
import 'blur_dialog.dart';
import 'blur_snackbar.dart';
import 'hover_scale_text_button.dart';
import 'right_edge_hover_menu.dart';
import 'minimal_progress_bar.dart';
import 'danmaku_density_bar.dart';
import 'speed_boost_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'loading_overlay.dart';
import 'vertical_indicator.dart';
import 'video_upload_ui.dart';
import 'playback_info_menu.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final bool _isIndicatorHovered = false;
  Timer? _doubleTapTimer;
  Timer? _mouseMoveTimer;
  OverlayEntry? _playbackInfoOverlay;
  int _tapCount = 0;
  static const _phoneDoubleTapTimeout = Duration(milliseconds: 360);
  static const _desktopDoubleTapTimeout = Duration(milliseconds: 220);
  Duration get _doubleTapTimeout =>
      globals.isPhone ? _phoneDoubleTapTimeout : _desktopDoubleTapTimeout;
  static const _mouseHideDelay = Duration(seconds: 3);
  bool _isProcessingTap = false;
  bool _isMouseVisible = true;
  bool _isHorizontalDragging = false;
  final OverlayContextMenuController _contextMenuController =
      OverlayContextMenuController();

  // <<< ADDED: Hold a reference to VideoPlayerState for managing the callback
  VideoPlayerState? _videoPlayerStateInstance;
  String? _currentAnimeCoverUrl; // 当前番剧封面URL
  int? _lastAnimeId; // 上次获取封面的番剧ID，用于避免重复请求

  // 获取番剧封面URL
  Future<String?> _getAnimeCoverUrl(int? animeId) async {
    if (animeId == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      const prefsKeyPrefix = 'media_library_image_url_';
      return prefs.getString('$prefsKeyPrefix$animeId');
    } catch (e) {
      debugPrint('获取番剧封面失败: $e');
      return null;
    }
  }

  // 更新封面URL（如果番剧ID变化）
  void _updateAnimeCoverUrl(int? animeId) async {
    if (animeId != _lastAnimeId) {
      _lastAnimeId = animeId;
      final coverUrl = await _getAnimeCoverUrl(animeId);
      if (mounted && coverUrl != _currentAnimeCoverUrl) {
        setState(() {
          _currentAnimeCoverUrl = coverUrl;
        });
      }
    }
  }

  double getFontSize(VideoPlayerState videoState) {
    return videoState.actualDanmakuFontSize;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _videoPlayerStateInstance =
            Provider.of<VideoPlayerState>(context, listen: false);
        _videoPlayerStateInstance?.onSeriousPlaybackErrorAndShouldPop =
            () async {
          if (mounted && _videoPlayerStateInstance != null) {
            // 获取当前的错误信息用于显示
            final String errorMessage =
                _videoPlayerStateInstance!.error ?? "发生未知播放错误，已停止播放。";

            // 显示 BlurDialog
            BlurDialog.show<void>(
              context: context, // 使用 VideoPlayerUI 的 context
              title: '播放错误',
              content: errorMessage,
              actions: [
                HoverScaleTextButton(
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
            print(
                "[VideoPlayerUI] onSeriousPlaybackErrorAndShouldPop: Not mounted or _videoPlayerStateInstance is null.");
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
        final videoState =
            Provider.of<VideoPlayerState>(context, listen: false);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!globals.isPhone) return;
    if (!mounted) return;
    _videoPlayerStateInstance ??=
        Provider.of<VideoPlayerState>(context, listen: false);
    _videoPlayerStateInstance?.handleAppLifecycleState(state);
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
        if (!mounted) return;
        if (_tapCount == 1 && !_isProcessingTap) {
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
    if (!videoState.hasVideo) return;

    if (globals.isDesktop) {
      unawaited(videoState.toggleFullscreen());
    } else {
      videoState.togglePlayPause();
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

  void _handleHorizontalDragStart(
      BuildContext context, DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      _isHorizontalDragging = true;
      videoState.startSeekDrag(context);
      _doubleTapTimer?.cancel();
      _tapCount = 0;
    }
  }

  void _handleHorizontalDragUpdate(
      BuildContext context, DragUpdateDetails details) {
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
    WidgetsBinding.instance.removeObserver(this);
    // <<< ADDED: Clear the callback to prevent memory leaks
    _videoPlayerStateInstance?.onSeriousPlaybackErrorAndShouldPop = null;
    _contextMenuController.dispose();
    _hidePlaybackInfoOverlay();

    // 确保清理所有资源
    _focusNode.dispose();
    _doubleTapTimer?.cancel();
    _mouseMoveTimer?.cancel();

    super.dispose();
  }

  // 移除键盘事件处理方法
  // KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) { ... }

  Future<void> _shareCurrentMedia(VideoPlayerState videoState) async {
    if (!SystemShareService.isSupported) return;

    final currentVideoPath = videoState.currentVideoPath;
    final currentActualUrl = videoState.currentActualPlayUrl;

    String? filePath;
    String? url;

    if (currentVideoPath != null && currentVideoPath.isNotEmpty) {
      final uri = Uri.tryParse(currentVideoPath);
      final scheme = uri?.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        url = currentVideoPath;
      } else if (scheme == 'jellyfin' || scheme == 'emby') {
        url = currentActualUrl;
      } else if (scheme == 'smb' || scheme == 'webdav' || scheme == 'dav') {
        url = currentVideoPath;
      } else {
        filePath = currentVideoPath;
      }
    } else {
      url = currentActualUrl;
    }

    final titleParts = <String>[
      if ((videoState.animeTitle ?? '').trim().isNotEmpty)
        videoState.animeTitle!.trim(),
      if ((videoState.episodeTitle ?? '').trim().isNotEmpty)
        videoState.episodeTitle!.trim(),
    ];
    final subject = titleParts.isEmpty ? null : titleParts.join(' · ');

    if ((filePath == null || filePath.isEmpty) && (url == null || url.isEmpty)) {
      if (!mounted) return;
      BlurSnackBar.show(context, '没有可分享的内容');
      return;
    }

    try {
      await SystemShareService.share(
        text: subject,
        url: url,
        filePath: filePath,
        subject: subject,
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '分享失败: $e');
    }
  }

  void _showPlaybackInfoOverlay() {
    if (_playbackInfoOverlay != null) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _playbackInfoOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hidePlaybackInfoOverlay,
              onSecondaryTap: _hidePlaybackInfoOverlay,
            ),
          ),
          PlaybackInfoMenu(onClose: _hidePlaybackInfoOverlay),
        ],
      ),
    );

    overlay.insert(_playbackInfoOverlay!);
  }

  void _hidePlaybackInfoOverlay() {
    _playbackInfoOverlay?.remove();
    _playbackInfoOverlay = null;
  }

  Future<void> _captureScreenshot(VideoPlayerState videoState) async {
    try {
      final path = await videoState.captureScreenshot();
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        BlurSnackBar.show(context, '截图失败');
        return;
      }
      final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
      if (isMac) {
        BlurSnackBar.show(
          context,
          '截图已保存',
          actionText: '打开',
          onAction: () => unawaited(_openScreenshot(path)),
        );
      } else {
        BlurSnackBar.show(context, '截图已保存: $path');
      }
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '截图失败: $e');
    }
  }

  Future<void> _openScreenshot(String path) async {
    final uri = Uri.file(path);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      BlurSnackBar.show(context, '无法打开截图文件');
    }
  }

  List<ContextMenuAction> _buildContextMenuActions(VideoPlayerState videoState) {
    final actions = <ContextMenuAction>[
      ContextMenuAction(
        icon: Icons.skip_previous_rounded,
        label: '上一话',
        enabled: videoState.canPlayPreviousEpisode,
        onPressed: () => unawaited(videoState.playPreviousEpisode()),
      ),
      ContextMenuAction(
        icon: Icons.skip_next_rounded,
        label: '下一话',
        enabled: videoState.canPlayNextEpisode,
        onPressed: () => unawaited(videoState.playNextEpisode()),
      ),
      ContextMenuAction(
        icon: Icons.fast_forward_rounded,
        label: '快进 ${videoState.seekStepSeconds} 秒',
        enabled: videoState.hasVideo,
        onPressed: () {
          final newPosition = videoState.position +
              Duration(seconds: videoState.seekStepSeconds);
          videoState.seekTo(newPosition);
        },
      ),
      ContextMenuAction(
        icon: Icons.fast_rewind_rounded,
        label: '快退 ${videoState.seekStepSeconds} 秒',
        enabled: videoState.hasVideo,
        onPressed: () {
          final newPosition = videoState.position -
              Duration(seconds: videoState.seekStepSeconds);
          videoState.seekTo(newPosition);
        },
      ),
      ContextMenuAction(
        icon: Icons.chat_bubble_outline_rounded,
        label: '发送弹幕',
        enabled: videoState.episodeId != null,
        onPressed: () => unawaited(videoState.showSendDanmakuDialog()),
      ),
      ContextMenuAction(
        icon: Icons.camera_alt_outlined,
        label: '截图',
        enabled: videoState.hasVideo,
        onPressed: () => unawaited(_captureScreenshot(videoState)),
      ),
      ContextMenuAction(
        icon: Icons.double_arrow_rounded,
        label: '跳过',
        enabled: videoState.hasVideo,
        onPressed: videoState.skip,
      ),
      ContextMenuAction(
        icon: videoState.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        label: videoState.isFullscreen ? '窗口化' : '全屏',
        enabled: globals.isDesktop,
        onPressed: () => unawaited(videoState.toggleFullscreen()),
      ),
      ContextMenuAction(
        icon: Icons.close_rounded,
        label: '关闭播放',
        enabled: videoState.hasVideo,
        onPressed: () => unawaited(videoState.resetPlayer()),
      ),
      ContextMenuAction(
        icon: Icons.info_outline_rounded,
        label: '播放信息',
        enabled: videoState.hasVideo,
        onPressed: _showPlaybackInfoOverlay,
      ),
    ];

    if (SystemShareService.isSupported) {
      actions.add(
        ContextMenuAction(
          icon: Icons.share_rounded,
          label: '分享',
          enabled: videoState.hasVideo,
          onPressed: () => unawaited(_shareCurrentMedia(videoState)),
        ),
      );
    }

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final textureId = videoState.player.textureId.value;

        // 更新番剧封面URL（如果有番剧ID）
        _updateAnimeCoverUrl(videoState.animeId);

        if (!videoState.hasVideo) {
          return Stack(
            children: [
              const VideoUploadUI(),
              if (videoState.status == PlayerStatus.recognizing ||
                  videoState.status == PlayerStatus.loading)
                LoadingOverlay(
                  messages: videoState.statusMessages,
                  backgroundOpacity: 0.5,
                  highPriorityAnimation: !videoState.isInFinalLoadingPhase,
                  animeTitle: videoState.animeTitle,
                  episodeTitle: videoState.episodeTitle,
                  fileName: videoState.currentVideoPath?.split('/').last,
                  coverImageUrl: _currentAnimeCoverUrl,
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
            cursor: _isMouseVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onSecondaryTapDown: globals.isDesktop
                      ? (details) {
                          if (!videoState.hasVideo) return;
                          _hidePlaybackInfoOverlay();

                          _contextMenuController.showActionsMenu(
                            context: context,
                            globalPosition: details.globalPosition,
                            style: ContextMenuStyles.glass(context),
                            actions: _buildContextMenuActions(videoState),
                          );
                        }
                      : null,
                  onLongPressStart: globals.isPhone
                      ? (details) => _handleLongPressStart(videoState)
                      : null,
                  onLongPressEnd: globals.isPhone
                      ? (details) => _handleLongPressEnd(videoState)
                      : null,
                  onHorizontalDragStart: globals.isPhone
                      ? (details) =>
                          _handleHorizontalDragStart(context, details)
                      : null,
                  onHorizontalDragUpdate: globals.isPhone
                      ? (details) =>
                          _handleHorizontalDragUpdate(context, details)
                      : null,
                  onHorizontalDragEnd: globals.isPhone
                      ? (details) => _handleHorizontalDragEnd(context, details)
                      : null,
                  child: FocusScope(
                    node: FocusScopeNode(),
                    child: globals.isPhone
                        ? RepaintBoundary(
                            key: videoState.screenshotBoundaryKey,
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

                              if (videoState.hasVideo &&
                                  videoState.danmakuVisible)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: true,
                                    child: Consumer<VideoPlayerState>(
                                      builder: (context, videoState, _) {
                                        // 使用高频时间轴驱动弹幕帧率
                                        return ValueListenableBuilder<double>(
                                          valueListenable:
                                              videoState.playbackTimeMs,
                                          builder: (context, posMs, __) {
                                            return DanmakuOverlay(
                                              key: ValueKey(
                                                  'danmaku_${videoState.danmakuOverlayKey}'),
                                              currentPosition: posMs,
                                              videoDuration: videoState
                                                  .videoDuration.inMilliseconds
                                                  .toDouble(),
                                              isPlaying: videoState.status ==
                                                  PlayerStatus.playing,
                                              fontSize: getFontSize(videoState),
                                              isVisible:
                                                  videoState.danmakuVisible,
                                              opacity: videoState
                                                  .mappedDanmakuOpacity,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),

                              if (videoState.status ==
                                      PlayerStatus.recognizing ||
                                  videoState.status == PlayerStatus.loading)
                                Positioned.fill(
                                  child: LoadingOverlay(
                                    messages: videoState.statusMessages,
                                    backgroundOpacity: 0.5,
                                    highPriorityAnimation:
                                        !videoState.isInFinalLoadingPhase,
                                    animeTitle: videoState.animeTitle,
                                    episodeTitle: videoState.episodeTitle,
                                    fileName:
                                        videoState.currentVideoPath?.split('/').last,
                                    coverImageUrl: _currentAnimeCoverUrl,
                                  ),
                                ),

                              if (videoState.hasVideo)
                                VerticalIndicator(videoState: videoState),

                              if (videoState.hasVideo)
                                const Positioned.fill(
                                  child: SpeedBoostIndicator(),
                                ),

                              if (globals.isPhone && videoState.hasVideo)
                                const BrightnessGestureArea(),

                              if (globals.isPhone && videoState.hasVideo)
                                const VolumeGestureArea(),

                              // 底部1像素白色进度条
                              const MinimalProgressBar(),

                              // 弹幕密度曲线
                              const DanmakuDensityBar(),
                              ],
                            ),
                          )
                        : Focus(
                            focusNode: _focusNode,
                            autofocus: true,
                            canRequestFocus: true,
                            child: RepaintBoundary(
                              key: videoState.screenshotBoundaryKey,
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

                                if (videoState.hasVideo &&
                                    videoState.danmakuVisible)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: true,
                                      child: Consumer<VideoPlayerState>(
                                        builder: (context, videoState, _) {
                                          // 使用高频时间轴驱动弹幕帧率
                                          return ValueListenableBuilder<double>(
                                            valueListenable:
                                                videoState.playbackTimeMs,
                                            builder: (context, posMs, __) {
                                              return DanmakuOverlay(
                                                key: ValueKey(
                                                    'danmaku_${videoState.danmakuOverlayKey}'),
                                                currentPosition: posMs,
                                                videoDuration: videoState
                                                    .videoDuration
                                                    .inMilliseconds
                                                    .toDouble(),
                                                isPlaying: videoState.status ==
                                                    PlayerStatus.playing,
                                                fontSize:
                                                    getFontSize(videoState),
                                                isVisible:
                                                    videoState.danmakuVisible,
                                                opacity: videoState
                                                    .mappedDanmakuOpacity,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                                if (videoState.status ==
                                        PlayerStatus.recognizing ||
                                    videoState.status == PlayerStatus.loading)
                                  Positioned.fill(
                                    child: LoadingOverlay(
                                      messages: videoState.statusMessages,
                                      backgroundOpacity: 0.5,
                                      highPriorityAnimation: !videoState
                                          .isInFinalLoadingPhase,
                                      animeTitle: videoState.animeTitle,
                                      episodeTitle: videoState.episodeTitle,
                                      fileName:
                                          videoState.currentVideoPath?.split('/').last,
                                      coverImageUrl: _currentAnimeCoverUrl,
                                    ),
                                  ),

                                if (videoState.hasVideo)
                                  VerticalIndicator(videoState: videoState),

                                if (videoState.hasVideo)
                                  const Positioned.fill(
                                    child: SpeedBoostIndicator(),
                                  ),

                                // 右边缘悬浮菜单（仅桌面版）
                                if (videoState.desktopHoverSettingsMenuEnabled)
                                  const RightEdgeHoverMenu(),

                                // 底部1像素白色进度条
                                const MinimalProgressBar(),

                                // 弹幕密度曲线
                                const DanmakuDensityBar(),
                                ],
                              ),
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
