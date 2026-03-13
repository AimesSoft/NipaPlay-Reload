import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/http_client_initializer.dart';
import 'package:nipaplay/services/desktop_pip_window_service.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runDesktopPipWindowApp(DesktopPipLaunchPayload payload) async {
  DesktopPipWindowService.instance.configureCurrentWindow(
    windowId: payload.windowId,
    isPipWindow: true,
  );

  try {
    MediaKit.ensureInitialized();
  } catch (_) {}
  MediaKitPlayerAdapter.setMpvLogLevelNone();

  await HttpClientInitializer.install();
  await PlayerFactory.initialize();
  await DanmakuKernelFactory.initialize();
  WatchHistoryDatabase.ensureInitialized();

  runApp(_DesktopPipWindowApp(payload: payload));
}

class _DesktopPipWindowApp extends StatelessWidget {
  const _DesktopPipWindowApp({required this.payload});

  final DesktopPipLaunchPayload payload;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => VideoPlayerState()),
        ChangeNotifierProvider(create: (_) => TabChangeNotifier()),
        ChangeNotifierProvider(create: (_) => WatchHistoryProvider()),
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
        ChangeNotifierProvider(create: (_) => UIThemeProvider()),
        ChangeNotifierProvider(create: (_) => JellyfinTranscodeProvider()),
        ChangeNotifierProvider(create: (_) => EmbyTranscodeProvider()),
      ],
      child: MaterialApp(
        title: 'NipaPlay PiP',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: _DesktopPipWindowPage(payload: payload),
      ),
    );
  }
}

class _DesktopPipWindowPage extends StatefulWidget {
  const _DesktopPipWindowPage({required this.payload});

  final DesktopPipLaunchPayload payload;

  @override
  State<_DesktopPipWindowPage> createState() => _DesktopPipWindowPageState();
}

class _DesktopPipWindowPageState extends State<_DesktopPipWindowPage>
    with WindowListener {
  VideoPlayerState? _videoState;
  bool _playbackInitialized = false;
  double _lastAspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    _lastAspectRatio =
        DesktopPipWindowService.normalizeAspectRatio(widget.payload.aspectRatio);
    windowManager.addListener(this);
    unawaited(_configureWindow(_lastAspectRatio));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final videoState = context.read<VideoPlayerState>();
      _videoState = videoState;
      videoState.addListener(_handleVideoStateChanged);
      unawaited(_initializePlayback(videoState));
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _videoState?.removeListener(_handleVideoStateChanged);
    unawaited(_notifyRestoreToMain());
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_notifyRestoreToMain());
  }

  Future<void> _configureWindow(double aspectRatio) async {
    final Size preferredSize =
        DesktopPipWindowService.preferredWindowSizeForAspect(aspectRatio);
    final Size minSize =
        DesktopPipWindowService.minimumWindowSizeForAspect(aspectRatio);

    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: 'NipaPlay 小窗播放',
        size: preferredSize,
        minimumSize: minSize,
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
      ),
      () async {
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setAspectRatio(aspectRatio);
        await windowManager.setMinimumSize(minSize);
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  Future<void> _initializePlayback(VideoPlayerState videoState) async {
    if (_playbackInitialized) {
      return;
    }
    _playbackInitialized = true;

    try {
      await videoState.initializePlayer(
        widget.payload.videoPath,
        actualPlayUrl: widget.payload.actualPlayUrl,
        resetManualDanmakuOffset: false,
      );
      if (widget.payload.animeTitle != null) {
        videoState.setAnimeTitle(widget.payload.animeTitle);
      }
      if (widget.payload.episodeTitle != null) {
        videoState.setEpisodeTitle(widget.payload.episodeTitle);
      }

      if (widget.payload.positionMs > 0) {
        videoState.seekTo(Duration(milliseconds: widget.payload.positionMs));
      }

      final bool isPlaying = videoState.status == PlayerStatus.playing;
      if (widget.payload.shouldPlay != isPlaying && videoState.hasVideo) {
        videoState.togglePlayPause();
      }
    } catch (e) {
      debugPrint('[DesktopPiP] 初始化播放失败: $e');
    }
  }

  void _handleVideoStateChanged() {
    final videoState = _videoState;
    if (videoState == null) {
      return;
    }
    final nextAspectRatio =
        DesktopPipWindowService.normalizeAspectRatio(videoState.aspectRatio);
    if ((nextAspectRatio - _lastAspectRatio).abs() < 0.01) {
      return;
    }
    _lastAspectRatio = nextAspectRatio;
    unawaited(_applyAspectRatio(nextAspectRatio));
  }

  Future<void> _applyAspectRatio(double aspectRatio) async {
    final Size minSize =
        DesktopPipWindowService.minimumWindowSizeForAspect(aspectRatio);
    try {
      await windowManager.setAspectRatio(aspectRatio);
      await windowManager.setMinimumSize(minSize);
    } catch (e) {
      debugPrint('[DesktopPiP] 更新窗口比例失败: $e');
    }
  }

  Future<void> _notifyRestoreToMain() async {
    final videoState = _videoState;
    if (videoState != null) {
      await DesktopPipWindowService.instance.notifyMainRestoreFromPip(videoState);
    } else {
      await DesktopPipWindowService.instance.notifyMainPipClosed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const PlayVideoPage();
  }
}
