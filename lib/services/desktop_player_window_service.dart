import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/pages/desktop_player_window.dart';
import 'package:nipaplay/services/desktop_picture_in_picture_preferences.dart';
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
  bool _pictureInPicture = false;
  bool _pictureInPictureTransitionInProgress = false;
  bool _alwaysOnTopBeforePictureInPicture = false;
  String? _lastWindowTitle;
  double? _lastAspectRatio;

  bool get isPlayerDetached => _playerDetached;
  bool get isTransitionInProgress => _transitionInProgress;
  bool get isPictureInPicture => _pictureInPicture;
  bool get isPictureInPictureTransitionInProgress =>
      _pictureInPictureTransitionInProgress;
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
    _clearWindowHostedVideoCutout();

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
    // The detached FlutterView reports coordinates relative to its own
    // window. Never let that rect become the main window's transparent cutout
    // while the shared player subtree is being reparented.
    _clearWindowHostedVideoCutout();
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

  Future<void> togglePictureInPicture() async {
    if (_pictureInPictureTransitionInProgress) return;
    if (_pictureInPicture) {
      await exitPictureInPicture();
    } else {
      await enterPictureInPicture();
    }
  }

  Future<bool> detachAndEnterPictureInPicture(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    final detached = await detachPlayer(context, videoState);
    if (!detached) return false;
    await enterPictureInPicture();
    return _pictureInPicture;
  }

  Future<void> enterPictureInPicture() async {
    final window = _activeWindow;
    final videoState = _videoState;
    if (window == null || window.isClosed || videoState == null) return;
    if (_pictureInPicture || _pictureInPictureTransitionInProgress) return;

    _pictureInPictureTransitionInProgress = true;
    _alwaysOnTopBeforePictureInPicture = window.isAlwaysOnTop;
    _pictureInPicture = true;
    notifyListeners();

    final aspectRatio = normalizeAspectRatio(videoState.aspectRatio);
    try {
      final placement = await DesktopPictureInPicturePreferences.loadPosition();
      debugPrint(
        '[DesktopPlayerWindow] 进入画中画: '
        'aspect=${aspectRatio.toStringAsFixed(4)} '
        'placement=${DesktopPictureInPicturePreferences.serializePosition(placement)}',
      );
      if (window.isFullscreen) await window.setFullscreen(false);
      await window.setMinimumSize(
        pictureInPictureMinimumWindowSizeForAspect(aspectRatio),
      );
      await window.setAspectRatio(aspectRatio);
      await window.setPictureInPictureMode(
        enabled: true,
        aspectRatio: aspectRatio,
        placement:
            DesktopPictureInPicturePreferences.serializePosition(placement),
      );
      await window.setAlwaysOnTop(true);
    } catch (error, stackTrace) {
      debugPrint(
        '[DesktopPlayerWindow] 进入画中画失败: $error\n$stackTrace',
      );
      _pictureInPicture = false;
      try {
        await window.setPictureInPictureMode(
          enabled: false,
          aspectRatio: aspectRatio,
          placement: DesktopPictureInPicturePreferences.serializePosition(
            DesktopPictureInPicturePreferences.defaultPosition,
          ),
        );
        await window.setMinimumSize(minimumWindowSizeForAspect(aspectRatio));
        await window.setAlwaysOnTop(_alwaysOnTopBeforePictureInPicture);
      } catch (rollbackError) {
        debugPrint(
          '[DesktopPlayerWindow] 画中画失败后的窗口恢复也失败: $rollbackError',
        );
      }
    } finally {
      _pictureInPictureTransitionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> exitPictureInPicture() async {
    final window = _activeWindow;
    if (window == null || window.isClosed) {
      _pictureInPicture = false;
      _pictureInPictureTransitionInProgress = false;
      notifyListeners();
      return;
    }
    if (!_pictureInPicture || _pictureInPictureTransitionInProgress) return;

    _pictureInPictureTransitionInProgress = true;
    notifyListeners();
    final aspectRatio = normalizeAspectRatio(
      _videoState?.aspectRatio ?? _lastAspectRatio ?? 16 / 9,
    );
    debugPrint('[DesktopPlayerWindow] 退出画中画并恢复独立窗口');
    try {
      await window.setPictureInPictureMode(
        enabled: false,
        aspectRatio: aspectRatio,
        placement: DesktopPictureInPicturePreferences.serializePosition(
          DesktopPictureInPicturePreferences.defaultPosition,
        ),
      );
      await window.setMinimumSize(minimumWindowSizeForAspect(aspectRatio));
      await window.setAspectRatio(aspectRatio);
      await window.setAlwaysOnTop(_alwaysOnTopBeforePictureInPicture);
    } catch (error, stackTrace) {
      debugPrint(
        '[DesktopPlayerWindow] 退出画中画失败: $error\n$stackTrace',
      );
    } finally {
      _pictureInPicture = false;
      _pictureInPictureTransitionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> updatePictureInPicturePlacement(
    DesktopPictureInPicturePosition placement,
  ) async {
    final window = _activeWindow;
    if (!_pictureInPicture || window == null || window.isClosed) return;
    final aspectRatio = normalizeAspectRatio(
      _videoState?.aspectRatio ?? _lastAspectRatio ?? 16 / 9,
    );
    debugPrint(
      '[DesktopPlayerWindow] 更新画中画停靠位置: '
      '${DesktopPictureInPicturePreferences.serializePosition(placement)}',
    );
    try {
      await window.setPictureInPictureMode(
        enabled: true,
        aspectRatio: aspectRatio,
        placement:
            DesktopPictureInPicturePreferences.serializePosition(placement),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[DesktopPlayerWindow] 更新画中画停靠位置失败: $error\n$stackTrace',
      );
    }
  }

  Future<void> resizeDetachedWindowToVideo() async {
    final window = _activeWindow;
    final videoState = _videoState;
    if (window == null || window.isClosed || videoState == null) return;
    final aspectRatio = normalizeAspectRatio(videoState.aspectRatio);
    if (_pictureInPicture) {
      await _applyPictureInPictureAspectRatio(window, aspectRatio);
      return;
    }
    await window.setAspectRatio(aspectRatio);
    await window.setMinimumSize(minimumWindowSizeForAspect(aspectRatio));
    await window.setSize(preferredWindowSizeForAspect(aspectRatio));
  }

  void _handleWindowClosed() {
    if (!_playerDetached && _activeWindow == null) return;
    final videoState = _videoState;
    _detachVideoState();
    videoState?.setWindowHostedVideoRect(null);
    _activeWindow = null;
    _playerDetached = false;
    _transitionInProgress = false;
    _pictureInPicture = false;
    _pictureInPictureTransitionInProgress = false;
    _alwaysOnTopBeforePictureInPicture = false;
    _lastWindowTitle = null;
    _lastAspectRatio = null;
    _tabChangeNotifier?.changePage(AppPageIds.video);
    notifyListeners();
  }

  void _clearWindowHostedVideoCutout() {
    _videoState?.setWindowHostedVideoRect(null);
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
      if (_pictureInPicture) {
        unawaited(_applyPictureInPictureAspectRatio(window, nextAspectRatio));
      } else {
        unawaited(_applyVideoAspectRatio(window, nextAspectRatio));
      }
    }
  }

  Future<void> _applyPictureInPictureAspectRatio(
    WindowController window,
    double aspectRatio,
  ) async {
    try {
      final placement = await DesktopPictureInPicturePreferences.loadPosition();
      await window.setMinimumSize(
        pictureInPictureMinimumWindowSizeForAspect(aspectRatio),
      );
      await window.setAspectRatio(aspectRatio);
      await window.setPictureInPictureMode(
        enabled: true,
        aspectRatio: aspectRatio,
        placement:
            DesktopPictureInPicturePreferences.serializePosition(placement),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[DesktopPlayerWindow] 根据新视频比例更新画中画失败: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _applyVideoAspectRatio(
    WindowController window,
    double aspectRatio,
  ) async {
    await window.setAspectRatio(aspectRatio);
    await window.setMinimumSize(minimumWindowSizeForAspect(aspectRatio));
    // Metadata can arrive just after the window was created. Resize once the
    // actual stream ratio is known instead of leaving the fallback 16:9 size.
    await window.setSize(preferredWindowSizeForAspect(aspectRatio));
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

  static Size pictureInPictureMinimumWindowSizeForAspect(double aspectRatio) {
    final ratio = normalizeAspectRatio(aspectRatio);
    const shortEdge = 120.0;
    return ratio >= 1
        ? Size(shortEdge * ratio, shortEdge)
        : Size(shortEdge, shortEdge / ratio);
  }
}
