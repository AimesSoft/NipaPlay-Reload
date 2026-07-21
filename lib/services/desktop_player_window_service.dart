import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/pages/desktop_player_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// Moves the player page between the main view and one same-engine desktop
/// window. Playback state is never copied or recreated.
class DesktopPlayerWindowService extends ChangeNotifier {
  DesktopPlayerWindowService._();

  static final DesktopPlayerWindowService instance =
      DesktopPlayerWindowService._();

  static bool get isFeatureEnabled =>
      !kIsWeb && globals.isDesktop && DesktopMultiWindow.isSupported;

  static const String _windowTitle = 'NipaPlay 独立播放器';

  /// Keeps the exact player Element/State subtree alive while it is reparented
  /// between the main FlutterView and the detached FlutterView.
  final GlobalKey playerPageKey = GlobalKey(
    debugLabel: 'shared-desktop-player-page',
  );

  WindowController? _activeWindow;
  TabChangeNotifier? _tabChangeNotifier;
  VideoPlayerState? _videoState;
  bool _playerDetached = false;
  bool _transitionInProgress = false;
  String? _lastWindowTitle;
  double? _lastAspectRatio;

  bool get isPlayerDetached => _playerDetached;
  bool get isTransitionInProgress => _transitionInProgress;
  WindowController? get activeWindow => _activeWindow;

  Future<bool> detachPlayer(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    if (!isFeatureEnabled || !videoState.hasVideo) return false;

    final existingWindow = _activeWindow;
    if (existingWindow != null && !existingWindow.isClosed) {
      await existingWindow.show();
      return true;
    }
    if (_transitionInProgress) return false;

    _transitionInProgress = true;
    _tabChangeNotifier = context.read<TabChangeNotifier>();
    _attachVideoState(videoState);

    // Register the destination FlutterView in the same frame. The GlobalKey
    // reparents the existing page instead of disposing it and rebuilding a
    // second playback page.
    _playerDetached = true;
    notifyListeners();

    try {
      final aspectRatio = normalizeAspectRatio(videoState.aspectRatio);
      final window = await DesktopMultiWindow.createWindow(
        title: _buildWindowTitle(videoState),
        size: preferredWindowSizeForAspect(aspectRatio),
        minimumSize: minimumWindowSizeForAspect(aspectRatio),
        frameless: true,
        aspectRatio: aspectRatio,
        builder: (context, controller) => const DesktopPlayerWindow(),
        onClosed: _handleWindowClosed,
      );
      if (window.isClosed) {
        _handleWindowClosed();
        return false;
      }
      _activeWindow = window;
      _lastWindowTitle = window.title;
      _lastAspectRatio = aspectRatio;
      _tabChangeNotifier?.changePage(AppPageIds.home);
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[DesktopPlayerWindow] 创建同引擎播放窗口失败: $error\n$stackTrace',
      );
      _playerDetached = false;
      _detachVideoState();
      _tabChangeNotifier?.changePage(AppPageIds.video);
      notifyListeners();
      return false;
    } finally {
      _transitionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> returnPlayerToMain() async {
    final window = _activeWindow;
    if (window == null || window.isClosed) {
      _handleWindowClosed();
      return;
    }
    await window.close();
  }

  Future<void> focusDetachedPlayer() async {
    final window = _activeWindow;
    if (window != null && !window.isClosed) await window.show();
  }

  Future<void> toggleDetachedFullscreen() async {
    final window = _activeWindow;
    if (window == null || window.isClosed) return;
    await window.setFullscreen(!window.isFullscreen);
  }

  Future<void> resizeDetachedWindowToVideo() async {
    final window = _activeWindow;
    final videoState = _videoState;
    if (window == null || window.isClosed || videoState == null) return;
    await window.setSize(
      preferredWindowSizeForAspect(videoState.aspectRatio),
    );
  }

  void _handleWindowClosed() {
    if (!_playerDetached && _activeWindow == null) return;
    _activeWindow = null;
    _playerDetached = false;
    _transitionInProgress = false;
    _lastWindowTitle = null;
    _lastAspectRatio = null;
    _detachVideoState();
    _tabChangeNotifier?.changePage(AppPageIds.video);
    notifyListeners();
  }

  void _attachVideoState(VideoPlayerState videoState) {
    if (identical(_videoState, videoState)) return;
    _detachVideoState();
    _videoState = videoState;
    videoState.addListener(_handleVideoStateChanged);
  }

  void _detachVideoState() {
    _videoState?.removeListener(_handleVideoStateChanged);
    _videoState = null;
  }

  void _handleVideoStateChanged() {
    final window = _activeWindow;
    final videoState = _videoState;
    if (window == null || window.isClosed || videoState == null) return;
    final nextTitle = _buildWindowTitle(videoState);
    if (nextTitle != _lastWindowTitle) {
      _lastWindowTitle = nextTitle;
      unawaited(window.setTitle(nextTitle));
    }
    final nextAspectRatio = normalizeAspectRatio(videoState.aspectRatio);
    if (_lastAspectRatio == null ||
        (nextAspectRatio - _lastAspectRatio!).abs() > 0.001) {
      _lastAspectRatio = nextAspectRatio;
      unawaited(window.setAspectRatio(nextAspectRatio));
    }
  }

  static String _buildWindowTitle(VideoPlayerState videoState) {
    final animeTitle = videoState.animeTitle?.trim() ?? '';
    final episodeTitle = videoState.episodeTitle?.trim() ?? '';
    final mediaTitle = <String>[
      if (animeTitle.isNotEmpty) animeTitle,
      if (episodeTitle.isNotEmpty && episodeTitle != animeTitle) episodeTitle,
    ].join(' · ');
    return mediaTitle.isEmpty ? _windowTitle : '$mediaTitle — NipaPlay';
  }

  static double normalizeAspectRatio(double value) {
    if (!value.isFinite || value <= 0) return 16 / 9;
    return value.clamp(0.5, 3.0).toDouble();
  }

  static Size preferredWindowSizeForAspect(double aspectRatio) {
    final ratio = normalizeAspectRatio(aspectRatio);
    const shortEdge = 540.0;
    if (ratio >= 1) {
      return Size((shortEdge * ratio).clamp(720.0, 1440.0), shortEdge);
    }
    return Size(shortEdge, (shortEdge / ratio).clamp(720.0, 1440.0));
  }

  static Size minimumWindowSizeForAspect(double aspectRatio) {
    final ratio = normalizeAspectRatio(aspectRatio);
    const shortEdge = 360.0;
    if (ratio >= 1) {
      return Size((shortEdge * ratio).clamp(480.0, 960.0), shortEdge);
    }
    return Size(shortEdge, (shortEdge / ratio).clamp(480.0, 960.0));
  }
}
