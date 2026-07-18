// lib/models/external_player_session/other_session.dart
// 其他平台/播放器的会话

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/external_player_session/session.dart';


/// 管理非 Linux mpv 外部播放器进程的轻量会话.
class OtherSession extends ChangeNotifier implements ExternalPlayerLaunchSession {

  OtherSession.attach({
    required this.type,
    required this.playerPath,
    required this.mediaPath,
    required this.processId,
    required this.duration,
    this.position = Duration.zero,
    this.isPaused = false,
    bool monitorProcess = false,
  }) { if (monitorProcess) _startLifecycleMonitoring(); }

  @override
  final ExternalPlayerType type;
  @override
  final String playerPath;
  @override
  final String mediaPath;
  @override
  final int processId;
  @override
  String? get ipcPath => null;

  @override
  Duration duration;
  @override
  Duration? position;
  @override
  bool? isPaused;

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
  void togglePause() {}

  @override
  void seekToFraction(double fraction) {}

  @override
  bool seekToPosition(Duration target) => false;

  @override
  Future<bool> refreshDanmaku(String assPath, String luaPath) async => false;

  @override
  void terminate() {
    if (_closed) return;
    try {
      final killed = Process.killPid(processId, ProcessSignal.sigterm);
      if (!killed) debugPrint('[OtherSession] Failed to terminate player: pid=$processId');
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
