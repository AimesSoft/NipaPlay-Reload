import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class DesktopPipLaunchPayload {
  DesktopPipLaunchPayload({
    required this.windowId,
    required this.videoPath,
    required this.positionMs,
    required this.shouldPlay,
    required this.aspectRatio,
    this.actualPlayUrl,
    this.animeTitle,
    this.episodeTitle,
    this.windowType = _pipWindowType,
  });

  static const String _subWindowEntryFlag = 'multi_window';
  static const String _pipWindowType = 'pip';

  final int windowId;
  final String windowType;
  final String videoPath;
  final String? actualPlayUrl;
  final int positionMs;
  final bool shouldPlay;
  final double aspectRatio;
  final String? animeTitle;
  final String? episodeTitle;

  bool get isPipWindow => windowType == _pipWindowType;

  static DesktopPipLaunchPayload? tryParse(List<String> args) {
    if (args.length < 2 || args.first != _subWindowEntryFlag) {
      return null;
    }
    final int? windowId = int.tryParse(args[1]);
    if (windowId == null || windowId <= 0) {
      return null;
    }

    Map<String, dynamic> payload = const {};
    if (args.length >= 3 && args[2].isNotEmpty) {
      try {
        final decoded = jsonDecode(args[2]);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        }
      } catch (_) {}
    }

    final String windowType = _stringValue(payload['windowType']) ?? _pipWindowType;
    final String? videoPath = _stringValue(payload['videoPath']);
    if (windowType == _pipWindowType && (videoPath == null || videoPath.isEmpty)) {
      return null;
    }

    return DesktopPipLaunchPayload(
      windowId: windowId,
      windowType: windowType,
      videoPath: videoPath ?? '',
      actualPlayUrl: _stringValue(payload['actualPlayUrl']),
      positionMs: _intValue(payload['positionMs']),
      shouldPlay: _boolValue(payload['shouldPlay']),
      aspectRatio:
          DesktopPipWindowService.normalizeAspectRatio(_doubleValue(payload['aspectRatio'])),
      animeTitle: _stringValue(payload['animeTitle']),
      episodeTitle: _stringValue(payload['episodeTitle']),
    );
  }

  String toWindowArgumentsJson() {
    return jsonEncode(<String, dynamic>{
      'windowType': _pipWindowType,
      'videoPath': videoPath,
      'actualPlayUrl': actualPlayUrl,
      'positionMs': positionMs,
      'shouldPlay': shouldPlay,
      'aspectRatio': aspectRatio,
      'animeTitle': animeTitle,
      'episodeTitle': episodeTitle,
    });
  }

  static String? _stringValue(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static bool _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lowered = value.trim().toLowerCase();
      return lowered == '1' || lowered == 'true';
    }
    return false;
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  static double _doubleValue(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim()) ?? (16 / 9);
    }
    return 16 / 9;
  }
}

class DesktopPipWindowService {
  DesktopPipWindowService._();

  static final DesktopPipWindowService instance = DesktopPipWindowService._();
  // 暂时关闭入口，等待官方稳定的多窗口支持
  static const bool isFeatureEnabled = false;

  static const String _methodRestorePlayback = 'pip.restorePlayback';
  static const String _methodClosed = 'pip.closed';
  static const String _windowTitle = 'NipaPlay 小窗播放';

  int _currentWindowId = 0;
  bool _isPipWindow = false;
  int? _activePipWindowId;
  bool _restoreReportedInPipWindow = false;
  bool _mainMethodHandlerInstalled = false;

  static DesktopPipLaunchPayload? tryParseLaunchPayload(List<String> args) {
    return DesktopPipLaunchPayload.tryParse(args);
  }

  bool get isCurrentWindowPip => _isPipWindow;
  bool get hasActivePipWindow => _activePipWindowId != null;
  int? get activePipWindowId => _activePipWindowId;

  void configureCurrentWindow({
    required int windowId,
    required bool isPipWindow,
  }) {
    _currentWindowId = windowId;
    _isPipWindow = isPipWindow;
    if (isPipWindow) {
      _restoreReportedInPipWindow = false;
    }
  }

  Future<void> installMainMethodHandler() async {
    if (!isFeatureEnabled || _isPipWindow || _mainMethodHandlerInstalled) {
      return;
    }
    DesktopMultiWindow.setMethodHandler(_handleMainMethodCall);
    _mainMethodHandlerInstalled = true;
  }

  Future<bool> openPipWindow(VideoPlayerState videoState) async {
    if (!isFeatureEnabled ||
        kIsWeb ||
        !globals.isDesktop ||
        _isPipWindow ||
        !videoState.hasVideo) {
      return false;
    }

    await _clearStalePipWindowReference();
    if (_activePipWindowId != null) {
      return false;
    }

    final String? videoPath = videoState.currentVideoPath;
    if (videoPath == null || videoPath.isEmpty) {
      return false;
    }

    final bool shouldPlayInPip = videoState.status == PlayerStatus.playing;
    final double aspectRatio = normalizeAspectRatio(videoState.aspectRatio);

    final payload = DesktopPipLaunchPayload(
      windowId: 0,
      videoPath: videoPath,
      actualPlayUrl: _normalizeString(videoState.currentActualPlayUrl),
      positionMs: videoState.position.inMilliseconds,
      shouldPlay: shouldPlayInPip,
      aspectRatio: aspectRatio,
      animeTitle: _normalizeString(videoState.animeTitle),
      episodeTitle: _normalizeString(videoState.episodeTitle),
    );

    try {
      final controller =
          await DesktopMultiWindow.createWindow(payload.toWindowArgumentsJson());
      _activePipWindowId = controller.windowId;

      final Rect frame = preferredWindowFrameForAspect(aspectRatio);
      await controller.setFrame(frame);
      await controller.setTitle(_windowTitle);
      await controller.center();
      await controller.show();

      if (shouldPlayInPip) {
        videoState.togglePlayPause();
      }

      return true;
    } catch (e) {
      debugPrint('[DesktopPiP] 打开小窗失败: $e');
      _activePipWindowId = null;
      return false;
    }
  }

  Future<void> closeCurrentPipWindowAndRestore(VideoPlayerState videoState) async {
    if (!_isPipWindow || _currentWindowId <= 0) {
      return;
    }
    await notifyMainRestoreFromPip(videoState);
    try {
      await WindowController.fromWindowId(_currentWindowId).close();
    } catch (e) {
      debugPrint('[DesktopPiP] 关闭小窗失败: $e');
    }
  }

  Future<void> notifyMainRestoreFromPip(VideoPlayerState videoState) async {
    if (!_isPipWindow || _currentWindowId <= 0 || _restoreReportedInPipWindow) {
      return;
    }

    final String? videoPath = _normalizeString(videoState.currentVideoPath);
    if (videoPath == null) {
      await notifyMainPipClosed();
      return;
    }

    _restoreReportedInPipWindow = true;

    final Map<String, dynamic> payload = <String, dynamic>{
      'videoPath': videoPath,
      'actualPlayUrl': _normalizeString(videoState.currentActualPlayUrl),
      'positionMs': videoState.position.inMilliseconds,
      'shouldPlay': videoState.status == PlayerStatus.playing,
      'animeTitle': _normalizeString(videoState.animeTitle),
      'episodeTitle': _normalizeString(videoState.episodeTitle),
    };

    try {
      await DesktopMultiWindow.invokeMethod(0, _methodRestorePlayback, payload);
    } catch (e) {
      debugPrint('[DesktopPiP] 回传播放状态失败: $e');
    }
  }

  Future<void> notifyMainPipClosed() async {
    if (!_isPipWindow || _currentWindowId <= 0 || _restoreReportedInPipWindow) {
      return;
    }
    _restoreReportedInPipWindow = true;
    try {
      await DesktopMultiWindow.invokeMethod(0, _methodClosed, <String, dynamic>{
        'windowId': _currentWindowId,
      });
    } catch (e) {
      debugPrint('[DesktopPiP] 通知小窗关闭失败: $e');
    }
  }

  Future<dynamic> _handleMainMethodCall(MethodCall call, int fromWindowId) async {
    switch (call.method) {
      case _methodRestorePlayback:
        _activePipWindowId = null;
        await _restoreMainWindowPlayback(call.arguments);
        return true;
      case _methodClosed:
        if (_activePipWindowId == fromWindowId) {
          _activePipWindowId = null;
        }
        return true;
      default:
        return null;
    }
  }

  Future<void> _restoreMainWindowPlayback(dynamic arguments) async {
    if (arguments is! Map) {
      return;
    }
    final Map<String, dynamic> payload =
        arguments.cast<dynamic, dynamic>().map((key, value) {
      return MapEntry(key.toString(), value);
    });

    final BuildContext? rootContext =
        globals.navigatorKey.currentState?.overlay?.context;
    if (rootContext == null) {
      return;
    }

    try {
      rootContext.read<TabChangeNotifier>().changeTab(1);
    } catch (_) {}

    VideoPlayerState? videoState;
    try {
      videoState = rootContext.read<VideoPlayerState>();
    } catch (_) {}
    if (videoState == null) {
      return;
    }

    final String? videoPath = _normalizeString(payload['videoPath']);
    if (videoPath == null) {
      return;
    }

    final String? actualPlayUrl = _normalizeString(payload['actualPlayUrl']);
    final int positionMs = _intValue(payload['positionMs']);
    final bool shouldPlay = _boolValue(payload['shouldPlay']);
    final String? animeTitle = _normalizeString(payload['animeTitle']);
    final String? episodeTitle = _normalizeString(payload['episodeTitle']);

    await _syncMainWindowPlayback(
      videoState: videoState,
      videoPath: videoPath,
      actualPlayUrl: actualPlayUrl,
      positionMs: positionMs,
      shouldPlay: shouldPlay,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
    );
  }

  Future<void> _syncMainWindowPlayback({
    required VideoPlayerState videoState,
    required String videoPath,
    required int positionMs,
    required bool shouldPlay,
    String? actualPlayUrl,
    String? animeTitle,
    String? episodeTitle,
  }) async {
    final bool sameVideoSource = videoState.currentVideoPath == videoPath;
    try {
      if (!videoState.hasVideo || !sameVideoSource) {
        await videoState.initializePlayer(
          videoPath,
          actualPlayUrl: actualPlayUrl,
          resetManualDanmakuOffset: false,
        );
      }
    } catch (e) {
      debugPrint('[DesktopPiP] 恢复主窗口播放失败: $e');
      return;
    }

    if (animeTitle != null) {
      videoState.setAnimeTitle(animeTitle);
    }
    if (episodeTitle != null) {
      videoState.setEpisodeTitle(episodeTitle);
    }

    if (positionMs > 0) {
      videoState.seekTo(Duration(milliseconds: positionMs));
    }

    final bool isPlaying = videoState.status == PlayerStatus.playing;
    if (shouldPlay != isPlaying && videoState.hasVideo) {
      videoState.togglePlayPause();
    }
  }

  Future<void> _clearStalePipWindowReference() async {
    if (_activePipWindowId == null) {
      return;
    }
    try {
      final ids = await DesktopMultiWindow.getAllSubWindowIds();
      if (!ids.contains(_activePipWindowId)) {
        _activePipWindowId = null;
      }
    } catch (e) {
      debugPrint('[DesktopPiP] 校验小窗状态失败: $e');
    }
  }

  static double normalizeAspectRatio(double value) {
    if (!value.isFinite || value <= 0) {
      return 16 / 9;
    }
    return value.clamp(0.5, 3.0).toDouble();
  }

  static Size preferredWindowSizeForAspect(double aspectRatio) {
    final double ratio = normalizeAspectRatio(aspectRatio);
    const double shortEdge = 320.0;
    if (ratio >= 1) {
      return Size((shortEdge * ratio).clamp(320.0, 860.0), shortEdge);
    }
    return Size(shortEdge, (shortEdge / ratio).clamp(320.0, 860.0));
  }

  static Size minimumWindowSizeForAspect(double aspectRatio) {
    final double ratio = normalizeAspectRatio(aspectRatio);
    const double shortEdge = 200.0;
    if (ratio >= 1) {
      return Size((shortEdge * ratio).clamp(200.0, 560.0), shortEdge);
    }
    return Size(shortEdge, (shortEdge / ratio).clamp(200.0, 560.0));
  }

  static Rect preferredWindowFrameForAspect(double aspectRatio) {
    final Size size = preferredWindowSizeForAspect(aspectRatio);
    return const Offset(120, 120) & size;
  }

  static String? _normalizeString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  static bool _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lowered = value.trim().toLowerCase();
      return lowered == '1' || lowered == 'true';
    }
    return false;
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}
