
// lib/models/external_player_session/potplayer_session.dart
// Windows PotPlayer 外部播放器会话

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/potplayer_window_api.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';


/// 使用 PotPlayer 的 Windows 消息接口管理播放状态, 并用 ASS 文件承载弹幕.
class PotPlayerSession extends ChangeNotifier implements ExternalPlayerLaunchSession {

  factory PotPlayerSession({
    required String playerPath,
    required String mediaPath,
    required Duration duration,
    Duration initialPosition = Duration.zero,
    List<String> extraArgs = const <String>[],
    DanmakuItemSet? initialDanmakuSet,
  }) {
    return PotPlayerSession._(
      playerPath: playerPath,
      mediaPath: mediaPath,
      duration: duration,
      initialPosition: initialPosition,
      extraArgs: extraArgs,
      assFilePath: _createAssFilePath(),
      initialDanmakuSet: initialDanmakuSet,
    );
  }

  PotPlayerSession._({
    required this.playerPath,
    required this.mediaPath,
    required this.duration,
    required Duration initialPosition,
    required List<String> extraArgs,
    required String assFilePath,
    required DanmakuItemSet? initialDanmakuSet,
  })  : _assFilePath = assFilePath,
        _initialDanmakuSet = initialDanmakuSet,
        position = initialPosition,
        _extraArgs = buildExtraArgs(
          initialPosition,
          extraArgs,
          assFilePath: assFilePath,
        );

  @override
  ExternalPlayerType get type => ExternalPlayerType.potPlayer;
  @override
  final String playerPath;
  @override
  final String mediaPath;
  @override
  int get processId => _processId ?? 0;
  @override
  Duration duration;
  @override
  Duration? position;
  @override
  bool? isPaused = false;

  final String _assFilePath;
  final DanmakuItemSet? _initialDanmakuSet;
  final List<String> _extraArgs;
  int? _processId;
  int _windowHandle = 0;
  Timer? _stateTimer;
  bool _closed = false;
  bool _potPlayerDisposed = false;

  static const int _wmCommand = 0x0111;
  static const int _wmUser = 0x0400;
  static const int _playPauseCommand = 10014;
  static const int _getTotalTime = 20482;
  static const int _getCurrentTime = 20484;
  static const int _setCurrentTime = 20485;
  static const int _getPlayStatus = 20486;

  @override
  String? get ipcPath => _windowHandle == 0 ? null : 'hwnd:$_windowHandle';

  @override
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> launch() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('PotPlayerSession 仅支持 Windows 平台');
    }
    if (_potPlayerDisposed) throw StateError('PotPlayerSession 已释放');
    if (_processId != null) throw StateError('PotPlayerSession 已启动');
    final initialDanmakuSet = _initialDanmakuSet;
    try {
      if (initialDanmakuSet != null && initialDanmakuSet.isNotEmpty) {
        await _writeDanmakuAss(initialDanmakuSet, DanmakuStyle());
      } else {
        await File(_assFilePath).create(recursive: true);
      }
      final process = await Process.start(
        playerPath,
        [mediaPath, ..._extraArgs],
        mode: ProcessStartMode.detached,
      );
      _processId = process.pid;
    } catch (_) {
      _deleteAssFile();
      rethrow;
    }
    _windowHandle = await _waitForPlayerWindow(processId);
    if (_windowHandle == 0) {
      terminate();
      throw StateError('找不到 PotPlayer 窗口: pid=$processId');
    }
    if (initialDanmakuSet != null && initialDanmakuSet.isNotEmpty) {
      await _selectOriginalSubtitleAsSecondary();
    }
    _startStatePolling();
  }

  @override
  void togglePause() {
    if (isClosed || _windowHandle == 0) return;
    WindowsPotPlayerApi.instance.postMessage(
      _windowHandle,
      _wmCommand,
      _playPauseCommand,
      0,
    );
    isPaused = !(isPaused ?? false);
    notifyListeners();
  }

  @override
  void seekToFraction(double fraction) {
    if (duration <= Duration.zero) return;
    final value = fraction.clamp(0.0, 1.0).toDouble();
    seekToPosition(Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    ));
  }

  @override
  bool seekToPosition(Duration target) {
    if (isClosed || _windowHandle == 0 || target < Duration.zero) return false;
    final milliseconds = duration > Duration.zero
        ? target.inMilliseconds.clamp(0, duration.inMilliseconds)
        : target.inMilliseconds;
    WindowsPotPlayerApi.instance.postMessage(
      _windowHandle,
      _wmUser,
      _setCurrentTime,
      milliseconds,
    );
    position = Duration(milliseconds: milliseconds);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> refreshDanmaku(
    DanmakuItemSet danmakuSet,
    DanmakuStyle style,
  ) async {
    if (isClosed) return false;
    try {
      await _writeDanmakuAss(danmakuSet, style);

      // `/current /sub=...` asks the already running PotPlayer instance to
      // load the newly generated ASS without restarting the media.
      final loader = await Process.start(
        playerPath,
        ['/current', '/sub=$_assFilePath'],
        mode: ProcessStartMode.normal,
      );
      // PotPlayer preserves the selected secondary track when the same ASS is
      // reloaded, so do not cycle tracks again here.
      return await loader.exitCode == 0;
    } catch (error, stackTrace) {
      debugPrint('[PotPlayerSession] 刷新 ASS 弹幕失败: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  /// PotPlayer 将 `/sub` 加载的 ASS 作为主字幕。连续两次执行官方的
  /// Ctrl+Alt+L「切换次字幕」命令，会跳过重复的弹幕轨并选中原字幕轨；
  /// 没有原字幕时第二次切换回关闭状态，因此不会重复显示弹幕。
  Future<void> _selectOriginalSubtitleAsSecondary() async {
    if (_windowHandle == 0 || isClosed) return;
    final api = WindowsPotPlayerApi.instance;
    final previousForegroundWindow = api.getForegroundWindow();
    api.setForegroundWindow(_windowHandle);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    for (var index = 0; index < 2; index++) {
      api.sendCtrlAltL();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (previousForegroundWindow != 0 &&
        previousForegroundWindow != _windowHandle) {
      api.setForegroundWindow(previousForegroundWindow);
    }
  }

  Future<void> _writeDanmakuAss(
    DanmakuItemSet danmakuSet,
    DanmakuStyle style,
  ) async {
    final settings = AssExportSettings(
      fontSize: style.danmakuFontSize,
      opacity: style.opacity,
      timeOffsetSeconds: style.danmakuOffset,
      allowStacking: style.danmakuAllowStacking,
      outlineStyle:
          style.outlineEnabled ? AssOutlineStyle.uniform : AssOutlineStyle.none,
      outlineWidth: style.outlineWidth,
    );
    final ass = await generateExternalPlayerDanmakuAss(
      danmakuSet.toList(growable: false),
      settings,
    );
    final directory = File(_assFilePath).parent;
    await directory.create(recursive: true);
    final temporaryFile = File('$_assFilePath.nipaplay.tmp');
    try {
      await temporaryFile.writeAsString(ass, flush: true);
      await temporaryFile.rename(_assFilePath);
    } finally {
      if (temporaryFile.existsSync()) await temporaryFile.delete();
    }
  }

  void _startStatePolling() {
    _stateTimer?.cancel();
    _stateTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refreshState(),
    );
    _refreshState();
  }

  void _refreshState() {
    if (isClosed || _windowHandle == 0) {
      _stateTimer?.cancel();
      return;
    }
    final api = WindowsPotPlayerApi.instance;
    if (api.isWindow(_windowHandle) == 0) {
      _windowHandle = 0;
      _deleteAssFile();
      _close();
      return;
    }
    final nextDuration = api.sendMessage(
      _windowHandle,
      _wmUser,
      _getTotalTime,
      0,
    );
    final nextPosition = api.sendMessage(
      _windowHandle,
      _wmUser,
      _getCurrentTime,
      0,
    );
    final playStatus = api.sendMessage(
      _windowHandle,
      _wmUser,
      _getPlayStatus,
      0,
    );
    final nextPaused = switch (playStatus) {
      1 => true,
      2 => false,
      _ => isPaused,
    };
    if (nextDuration >= 0) duration = Duration(milliseconds: nextDuration);
    if (nextPosition >= 0) position = Duration(milliseconds: nextPosition);
    isPaused = nextPaused;
    notifyListeners();
  }

  static Future<int> _waitForPlayerWindow(int processId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    do {
      final handle = WindowsPotPlayerApi.instance.findWindowForProcess(
        processId,
      );
      if (handle != 0) return handle;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } while (DateTime.now().isBefore(deadline));
    return 0;
  }

  @override
  void terminate() {
    if (_closed) return;
    _stateTimer?.cancel();
    final processId = _processId;
    try {
      if (processId != null) {
        Process.runSync('taskkill', ['/PID', '$processId', '/T', '/F']);
      }
    } catch (error) {
      debugPrint('[PotPlayerSession] 关闭播放器失败: $error');
    } finally {
      _deleteAssFile();
      _close();
    }
  }

  @override
  void dispose() {
    if (_potPlayerDisposed) return;
    _potPlayerDisposed = true;
    _stateTimer?.cancel();
    if (!_closed) terminate();
    super.dispose();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _stateTimer?.cancel();
    if (!_potPlayerDisposed) notifyListeners();
  }

  void _deleteAssFile() {
    for (final path in [_assFilePath, '$_assFilePath.nipaplay.tmp']) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException catch (error) {
        debugPrint('[PotPlayerSession] 删除临时弹幕失败: $error');
      }
    }
  }

  static List<String> buildExtraArgs(
    Duration position,
    List<String> extraArgs, {
    String? assFilePath,
  }) =>
      <String>[
        '/new',
        if (position > Duration.zero) '/seek=${formatSeekPosition(position)}',
        if (assFilePath != null && assFilePath.isNotEmpty) '/sub=$assFilePath',
        ...extraArgs,
      ];

  static String formatSeekPosition(Duration position) {
    final milliseconds = position.inMilliseconds.clamp(0, 359999999);
    final hours = milliseconds ~/ Duration.millisecondsPerHour;
    final minutes =
        (milliseconds ~/ Duration.millisecondsPerMinute).remainder(60);
    final seconds =
        (milliseconds ~/ Duration.millisecondsPerSecond).remainder(60);
    final millis = milliseconds.remainder(1000);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  static String _createAssFilePath() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'nipaplay_danmaku${Platform.pathSeparator}potplayer_$timestamp.ass';
    return path;
  }
}
