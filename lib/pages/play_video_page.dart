import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/widgets/airplay_route_picker.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_widget.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/vertical_indicator.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/nipaplay/widgets/video_controls_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/back_button_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_info_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/glass_action_button.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:flutter/gestures.dart';
import 'package:nipaplay/themes/nipaplay/widgets/send_danmaku_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/lock_controls_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/skip_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/send_danmaku_dialog.dart';
import '../player_abstraction/player_abstraction.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/hotkey_service.dart';

class PlayVideoPage extends StatefulWidget {
  final String? videoPath;

  const PlayVideoPage({super.key, this.videoPath});

  @override
  State<PlayVideoPage> createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  bool _isHoveringAnimeInfo = false;
  bool _isHoveringBackButton = false;
  double _horizontalDragDistance = 0.0;
  final GlobalKey<SendDanmakuDialogContentState> _danmakuDialogKey =
      GlobalKey();
  bool _isUiLocked = false;
  bool _showUiLockButton = false;
  Timer? _uiLockButtonTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _uiLockButtonTimer?.cancel();
    super.dispose();
  }

  // 处理系统返回键事件
  Future<bool> _handleWillPop() async {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    return await videoState.handleBackButton();
  }

  void _handleSideSwipeDragStart(DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (globals.isPhone && videoState.isFullscreen) {
      _horizontalDragDistance = 0.0;
      //debugPrint("[PlayVideoPage] Side swipe drag start.");
    }
  }

  void _handleSideSwipeDragUpdate(DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (globals.isPhone && videoState.isFullscreen) {
      _horizontalDragDistance += details.delta.dx;
    }
  }

  void _handleSideSwipeDragEnd(DragEndDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!(globals.isPhone && videoState.isFullscreen)) {
      _horizontalDragDistance = 0.0;
      return;
    }

    //debugPrint("[PlayVideoPage] Side swipe drag end.");
    //debugPrint("[PlayVideoPage] Accumulated Drag Distance: $_horizontalDragDistance");
    //debugPrint("[PlayVideoPage] Drag Velocity: ${details.primaryVelocity}");

    // 先检查是否存在DefaultTabController，避免异常
    final TabController? tabController =
        context.findAncestorWidgetOfExactType<DefaultTabController>() != null
            ? DefaultTabController.of(context)
            : null;

    if (tabController == null) {
      // 如果不存在TabController，直接返回
      _horizontalDragDistance = 0.0;
      return;
    }

    final tabChangeNotifier =
        Provider.of<TabChangeNotifier>(context, listen: false);

    final currentIndex = tabController.index;
    final tabCount = tabController.length;
    int newIndex = currentIndex;

    final double dragThreshold = MediaQuery.of(context).size.width / 15;
    //debugPrint("[PlayVideoPage] Drag Threshold: $dragThreshold");

    if (_horizontalDragDistance < -dragThreshold) {
      //debugPrint("[PlayVideoPage] Swipe Left detected (by distance).");
      if (currentIndex < tabCount - 1) {
        newIndex = currentIndex + 1;
      }
    } else if (_horizontalDragDistance > dragThreshold) {
      //debugPrint("[PlayVideoPage] Swipe Right detected (by distance).");
      if (currentIndex > 0) {
        newIndex = currentIndex - 1;
      }
    } else {
      //debugPrint("[PlayVideoPage] Drag distance not enough for side swipe.");
    }

    if (newIndex != currentIndex) {
      //debugPrint("[PlayVideoPage] Changing tab to index: $newIndex via side swipe.");
      tabChangeNotifier.changeTab(newIndex);
    } else {
      //debugPrint("[PlayVideoPage] No tab change needed from side swipe.");
    }
    _horizontalDragDistance = 0.0;
  }

  double getFontSize() {
    if (globals.isPhone) {
      return 20.0;
    } else {
      return 30.0;
    }
  }

  void _toggleUiLock(VideoPlayerState videoState) {
    if (!globals.isPhone) return;
    final nextLocked = !_isUiLocked;
    _uiLockButtonTimer?.cancel();
    setState(() {
      _isUiLocked = nextLocked;
      _showUiLockButton = nextLocked;
    });
    videoState.setShowControls(!nextLocked);

    if (nextLocked) {
      _showUiLockButtonTemporarily();
    }
  }

  void _showUiLockButtonTemporarily(
      [Duration duration = const Duration(seconds: 3)]) {
    if (!mounted) return;
    if (!globals.isPhone) return;
    if (!_isUiLocked) return;

    _uiLockButtonTimer?.cancel();
    setState(() {
      _showUiLockButton = true;
    });
    _uiLockButtonTimer = Timer(duration, () {
      if (!mounted) return;
      if (!_isUiLocked) return;
      setState(() {
        _showUiLockButton = false;
      });
    });
  }

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

    if ((filePath == null || filePath.isEmpty) &&
        (url == null || url.isEmpty)) {
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

  Future<void> _captureScreenshot(VideoPlayerState videoState) async {
    if (kIsWeb) return;
    if (!videoState.hasVideo) return;

    try {
      if (Platform.isIOS) {
        final destination = await BlurDialog.show<String>(
          context: context,
          title: '保存截图',
          content: '请选择保存位置',
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('photos'),
              child: const Text(
                '相册',
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('file'),
              child: const Text(
                '文件',
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        );

        if (!mounted) return;
        if (destination == null) return;

        if (destination == 'photos') {
          final ok = await videoState.captureScreenshotToPhotos();
          if (!mounted) return;
          if (ok) {
            BlurSnackBar.show(context, '截图已保存到相册');
          } else {
            BlurSnackBar.show(context, '截图失败');
          }
          return;
        }
      }

      final path = await videoState.captureScreenshot();
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        BlurSnackBar.show(context, '截图失败');
        return;
      }
      BlurSnackBar.show(context, '截图已保存: $path');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '截图失败: $e');
    }
  }

  Future<void> _showAirPlayPicker() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    await BlurDialog.show(
      context: context,
      title: '投屏',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(height: 8),
          Text(
            '点击下方 AirPlay 图标选择设备',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Center(child: AirPlayRoutePicker(size: 44)),
          SizedBox(height: 12),
          Text(
            '如未发现设备，请确认与接收端在同一局域网。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return WillPopScope(
          onWillPop: _handleWillPop,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            color: videoState.hasVideo ? Colors.black : Colors.transparent,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(
                    child: VideoPlayerWidget(),
                  ),
                  if (videoState.hasVideo)
                    _buildMaterialControls(videoState),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaterialControls(VideoPlayerState videoState) {
    final bool uiLocked = globals.isPhone ? _isUiLocked : false;
    final bool showLockButton = globals.isPhone &&
        (videoState.showControls || (uiLocked && _showUiLockButton));
    final bool showShareButton = SystemShareService.isSupported && !globals.isDesktop;
    final bool showScreenshotButton = !kIsWeb && globals.isPhone;

    return Stack(
      children: [
        Consumer<VideoPlayerState>(
          builder: (context, videoState, _) {
            return VerticalIndicator(videoState: videoState);
          },
        ),
        Positioned(
          top: 16.0,
          left: 16.0,
          child: AnimatedOpacity(
            opacity: videoState.showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !videoState.showControls,
              child: Padding(
                padding: EdgeInsets.only(left: globals.isPhone ? 24.0 : 0.0),
                child: Row(
                  children: [
                    MouseRegion(
                      cursor: _isHoveringBackButton
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onEnter: (_) =>
                          setState(() => _isHoveringBackButton = true),
                      onExit: (_) =>
                          setState(() => _isHoveringBackButton = false),
                      child: BackButtonWidget(videoState: videoState),
                    ),
                    const SizedBox(width: 10.0),
                    MouseRegion(
                      cursor: _isHoveringAnimeInfo
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onEnter: (_) =>
                          setState(() => _isHoveringAnimeInfo = true),
                      onExit: (_) =>
                          setState(() => _isHoveringAnimeInfo = false),
                      child: AnimeInfoWidget(videoState: videoState),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16.0,
          right: 16.0,
          child: AnimatedOpacity(
            opacity: videoState.showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !videoState.showControls,
              child: Padding(
                padding: EdgeInsets.only(right: globals.isPhone ? 24.0 : 0.0),
                child: MouseRegion(
                  onEnter: (_) => videoState.setControlsHovered(true),
                  onExit: (_) => videoState.setControlsHovered(false),
                  child: Row(
                    children: [
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.iOS)
                        GlassActionButton(
                          tooltip: '投屏 (AirPlay)',
                          icon: Icons.airplay_rounded,
                          onPressed: () {
                            videoState.resetHideControlsTimer();
                            _showAirPlayPicker();
                          },
                        ),
                      if (showScreenshotButton) ...[
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.iOS)
                          const SizedBox(width: 12),
                        GlassActionButton(
                          tooltip: '截图',
                          icon: Icons.camera_alt_outlined,
                          onPressed: () {
                            videoState.resetHideControlsTimer();
                            _captureScreenshot(videoState);
                          },
                        ),
                      ],
                      if (showShareButton) ...[
                        const SizedBox(width: 12),
                        GlassActionButton(
                          tooltip: (!kIsWeb &&
                                  defaultTargetPlatform == TargetPlatform.iOS)
                              ? '分享 / AirDrop'
                              : '分享',
                          icon: (!kIsWeb &&
                                  defaultTargetPlatform == TargetPlatform.iOS)
                              ? Icons.ios_share_rounded
                              : Icons.share_rounded,
                          onPressed: () {
                            videoState.resetHideControlsTimer();
                            _shareCurrentMedia(videoState);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16.0 + (globals.isPhone ? 24.0 : 0.0),
          top: 0,
          bottom: 0,
          child: Center(
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: Offset(videoState.showControls ? 0 : -0.1, 0),
              child: AnimatedOpacity(
                opacity: videoState.showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !videoState.showControls,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SendDanmakuButton(
                        onPressed: () => _showSendDanmakuDialog(videoState),
                      ),
                      const SizedBox(height: 12),
                      SkipButton(
                        onPressed: () => videoState.skip(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (globals.isPhone && videoState.isFullscreen)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 60,
            child: GestureDetector(
              onHorizontalDragStart: _handleSideSwipeDragStart,
              onHorizontalDragUpdate: _handleSideSwipeDragUpdate,
              onHorizontalDragEnd: _handleSideSwipeDragEnd,
              behavior: HitTestBehavior.translucent,
              dragStartBehavior: DragStartBehavior.down,
              child: Container(),
            ),
          ),
        const VideoControlsOverlay(),
        if (uiLocked)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showUiLockButtonTemporarily,
              child: const SizedBox.expand(),
            ),
          ),
        if (globals.isPhone)
          Positioned(
            left: 16.0 + (globals.isPhone ? 24.0 : 0.0),
            top: 0,
            bottom: 0,
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -90),
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 150),
                  offset: Offset(showLockButton ? 0 : -0.1, 0),
                  child: AnimatedOpacity(
                    opacity: showLockButton ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: !showLockButton,
                      child: LockControlsButton(
                        locked: uiLocked,
                        onPressed: () => _toggleUiLock(videoState),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showSendDanmakuDialog(VideoPlayerState videoState) async {
    final hotkeyService = HotkeyService();
    final wasPlaying = videoState.player.state == PlaybackState.playing;

    if (wasPlaying) {
      await videoState.player.pauseDirectly();
    }

    final episodeId = videoState.episodeId;
    final currentTime = videoState.position.inSeconds.toDouble();

    if (episodeId == null) {
      BlurSnackBar.show(context, '无法获取剧集信息，无法发送弹幕');
      if (wasPlaying) await videoState.player.playDirectly();
      return;
    }

    hotkeyService.unregisterHotkeys();

    // 检查是否为手机设备
    final window = WidgetsBinding.instance.window;
    final size = window.physicalSize / window.devicePixelRatio;
    final shortestSide = size.width < size.height ? size.width : size.height;
    final bool isRealPhone =
        Platform.isIOS || Platform.isAndroid && shortestSide < 600;

    await BlurDialog.show(
      context: context,
      title: isRealPhone ? '' : '发送弹幕', // 手机设备不显示标题
      contentWidget: SendDanmakuDialogContent(
        episodeId: episodeId,
        currentTime: currentTime,
        onDanmakuSent: (danmaku) {
          videoState.addDanmakuToNewTrack(danmaku);
        },
      ),
      actions: [],
    );

    hotkeyService.registerHotkeys();

    if (wasPlaying) {
      await videoState.player.playDirectly();
    }
  }
}
