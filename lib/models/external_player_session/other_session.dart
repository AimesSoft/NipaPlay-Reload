// lib/models/external_player_session/other_session.dart
// 其他平台/播放器的会话

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/utils/app_platform.dart';


/// 管理未启用 mpv JSON IPC 的外部播放器进程的轻量会话.
class OtherSession extends ChangeNotifier implements ExternalPlayerLaunchSession {

  OtherSession({
    required this.type,
    required this.playerPath,
    required this.mediaPath,
    required this.duration,
    this.position = Duration.zero,
    this.isPaused = false,
    List<String> extraArgs = const <String>[],
    AppPlatform? platform,
  }) : _extraArgs = extraArgs,
       _platform = platform ?? AppPlatform.current;

  @override
  final ExternalPlayerType type;
  @override
  final String playerPath;
  @override
  final String mediaPath;
  @override
  int get processId => _processId ?? 0;
  @override
  String? get ipcPath => null;

  @override
  Duration duration;
  @override
  Duration? position;
  @override
  bool? isPaused;

  final List<String> _extraArgs;
  final AppPlatform _platform;
  int? _processId;

  static const Duration _processPollingInterval = Duration(milliseconds: 250);
  Timer? _processPollingTimer;
  bool _closed = false;
  bool _disposed = false;

  @override
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> launch() async {
    if (_disposed) throw StateError('OtherSession 已释放');
    if (_processId != null) throw StateError('OtherSession 已启动');

    final config = switch (_platform) {
      AppPlatform.windows => playerPath.toLowerCase().endsWith('.lnk')
          ? (
              executable: 'cmd',
              arguments: [
                '/c',
                'start',
                '',
                playerPath,
                mediaPath,
                ..._extraArgs,
              ],
              mode: ProcessStartMode.normal,
              runInShell: true,
              monitorProcess: false,
            )
          : (
              executable: playerPath,
              arguments: [mediaPath, ..._extraArgs],
              mode: ProcessStartMode.detached,
              runInShell: false,
              monitorProcess: false,
            ),
      AppPlatform.macOS => playerPath.toLowerCase().endsWith('.app')
          ? (
              executable: 'open',
              arguments: [
                '-a',
                playerPath,
                mediaPath,
                if (_extraArgs.isNotEmpty) '--args',
                ..._extraArgs,
              ],
              mode: ProcessStartMode.normal,
              runInShell: false,
              monitorProcess: false,
            )
          : (
              executable: playerPath,
              arguments: [mediaPath, ..._extraArgs],
              mode: ProcessStartMode.normal,
              runInShell: false,
              monitorProcess: false,
            ),
      AppPlatform.linux => (
          executable: playerPath,
          arguments: [mediaPath, ..._extraArgs],
          mode: ProcessStartMode.detached,
          runInShell: false,
          monitorProcess: true,
        ),
      AppPlatform.web ||
      AppPlatform.android ||
      AppPlatform.iOS ||
      AppPlatform.unknown => throw StateError('不支持的平台: $_platform'),
    };

    final process = await Process.start(
      config.executable,
      config.arguments,
      mode: config.mode,
      runInShell: config.runInShell,
    );
    _processId = process.pid;
    if (config.monitorProcess) _startLifecycleMonitoring();
  }

  @override
  void togglePause() {}

  @override
  void seekToFraction(double fraction) {}

  @override
  bool seekToPosition(Duration target) => false;

  @override
  Future<bool> refreshDanmaku(
    DanmakuItemSet danmakuSet,
    DanmakuStyle style,
  ) async => false;

  @override
  void terminate() {
    if (_closed) return;
    final processId = _processId;
    if (processId == null) {
      _close();
      return;
    }
    try {
      if (Platform.isWindows) {
        Process.runSync('taskkill', ['/PID', '$processId', '/T', '/F']);
      } else {
        final killed = Process.killPid(processId, ProcessSignal.sigterm);
        if (!killed) debugPrint('[OtherSession] Failed to terminate player: pid=$processId');
      }
    }
    catch (error) { debugPrint('[OtherSession] Failed to close player: $error'); }
    _close();
  }

  void _startLifecycleMonitoring() {
    _stopLifecycleMonitoring();
    _scheduleNextProcessPoll();
  }

  void _stopLifecycleMonitoring() {
    _processPollingTimer?.cancel();
    _processPollingTimer = null;
  }

  void _scheduleNextProcessPoll() {
    late final Timer timer;
    timer = Timer(
      _processPollingInterval,
      () => unawaited(_pollProcessState(timer)),
    );
    _processPollingTimer = timer;
  }

  Future<void> _pollProcessState(Timer timer) async {
    bool running;
    try {
      running = await _isProcessRunning();
    } catch (error) {
      debugPrint('[OtherSession] Failed to refresh player state: $error');
      running = true;
    }

    if (!identical(_processPollingTimer, timer)) return;
    if (!running) {
      _close();
      return;
    }
    _scheduleNextProcessPoll();
  }

  Future<bool> _isProcessRunning() async {
    if (processId <= 0) return false;

    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $processId', '/NH'],
        );
        if (result.exitCode != 0) return false;
        final output = (result.stdout as String).trim();
        return output.contains('$processId');
      } on ProcessException {
        return false;
      }
    }

    try {
      final value = await File('/proc/$processId/stat').readAsString();
      final closingParen = value.lastIndexOf(')');
      if (closingParen < 0 || closingParen + 2 >= value.length) return true;
      return value.substring(closingParen + 2, closingParen + 3) != 'Z';
    } on FileSystemException {
      return false;
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _stopLifecycleMonitoring();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_closed) terminate();
    _stopLifecycleMonitoring();
    super.dispose();
  }
}
