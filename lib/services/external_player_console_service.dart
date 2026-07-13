import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/external_player_session.dart';

/// Owns the single Linux external-player session displayed by the app.
class ExternalPlayerConsoleService extends ChangeNotifier {
  ExternalPlayerConsoleService({
    Duration monitorInterval = const Duration(seconds: 1),
  }) : _monitorInterval = monitorInterval;

  static final ExternalPlayerConsoleService instance =
      ExternalPlayerConsoleService();

  static bool get isSupportedPlatform => !kIsWeb && Platform.isLinux;

  final Duration _monitorInterval;

  ExternalPlayerSession? _session;
  ExternalPlayerPlaybackProgress? _progress;
  Timer? _monitorTimer;
  bool _isClosing = false;
  bool _isCheckingProcess = false;
  bool _isPaused = false;
  bool _isSendingPauseCommand = false;

  ExternalPlayerSession? get session => _session;
  ExternalPlayerPlaybackProgress? get progress => _progress;
  bool get hasActiveSession => _session != null;
  bool get isClosing => _isClosing;
  bool get isPaused => _isPaused;
  bool get isSendingPauseCommand => _isSendingPauseCommand;

  /// Replaces the active session and terminates the previously tracked player.
  void showSession(ExternalPlayerSession session) {
    final previous = _session;
    if (previous != null && previous.processId != session.processId) {
      _terminate(previous.processId);
    }

    _monitorTimer?.cancel();
    _session = session;
    _progress = null;
    _isClosing = false;
    _isPaused = false;
    notifyListeners();

    _monitorTimer = Timer.periodic(
      _monitorInterval,
      (_) => unawaited(_refreshProcessState()),
    );
  }

  /// Hides the console session immediately and asks the player to terminate.
  void closePlayerAndConsole() {
    final current = _session;
    if (_isClosing || current == null) return;

    _isClosing = true;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _session = null;
    _progress = null;
    _isPaused = false;
    notifyListeners();

    try {
      _terminate(current.processId);
    } finally {
      _isClosing = false;
    }
  }

  /// Toggles pause for an mpv session through its JSON IPC socket.
  Future<void> togglePause() async {
    final current = _session;
    if (current?.ipcPath == null || _isSendingPauseCommand) return;

    _isSendingPauseCommand = true;
    notifyListeners();
    try {
      final targetPaused = !_isPaused;
      final changed = await _setMpvPaused(current!, targetPaused);
      if (!changed || !identical(_session, current)) return;

      _isPaused = targetPaused;
      final previous = _progress;
      if (previous != null) {
        _progress = ExternalPlayerPlaybackProgress(
          position: previous.position,
          duration: previous.duration,
          isPaused: targetPaused,
        );
      }
    } finally {
      _isSendingPauseCommand = false;
      notifyListeners();
    }
  }

  Future<void> _refreshProcessState() async {
    final current = _session;
    if (current == null || _isClosing || _isCheckingProcess) return;
    _isCheckingProcess = true;

    try {
      final running = await _isLinuxProcessRunning(current.processId);
      if (!identical(_session, current)) return;

      if (!running) {
        _clearSession();
        return;
      }

      final nextProgress = await _readMpvProgress(current);
      if (!identical(_session, current) || nextProgress == null) return;

      final previous = _progress;
      if (previous?.position == nextProgress.position &&
          previous?.duration == nextProgress.duration &&
          previous?.isPaused == nextProgress.isPaused) {
        return;
      }

      _progress = nextProgress;
      _isPaused = nextProgress.isPaused;
      notifyListeners();
    } catch (error) {
      debugPrint('[ExtPlayerConsole] Failed to refresh player state: $error');
    } finally {
      _isCheckingProcess = false;
    }
  }

  void _clearSession() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _session = null;
    _progress = null;
    _isPaused = false;
    notifyListeners();
  }

  void _terminate(int processId) {
    try {
      final killed = Process.killPid(processId, ProcessSignal.sigterm);
      if (!killed) {
        debugPrint(
          '[ExtPlayerConsole] Failed to terminate player: pid=$processId',
        );
      }
    } catch (error) {
      debugPrint('[ExtPlayerConsole] Failed to close player: $error');
    }
  }

  static Future<bool> _isLinuxProcessRunning(int processId) async {
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

  static Future<ExternalPlayerPlaybackProgress?> _readMpvProgress(
    ExternalPlayerSession session,
  ) async {
    final ipcPath = session.ipcPath;
    if (ipcPath == null || ipcPath.isEmpty) return null;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(ipcPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('${jsonEncode({
            'command': ['get_property', 'time-pos'],
            'request_id': 1,
          })}\n');
      socket.write('${jsonEncode({
            'command': ['get_property', 'duration'],
            'request_id': 2,
          })}\n');
      socket.write('${jsonEncode({
            'command': ['get_property', 'pause'],
            'request_id': 3,
          })}\n');
      await socket.flush();

      double? positionSeconds;
      double? durationSeconds;
      bool? isPaused;
      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['error'] != 'success') {
          continue;
        }

        final data = value['data'];
        switch (value['request_id']) {
          case 1 when data is num:
            positionSeconds = data.toDouble();
          case 2 when data is num:
            durationSeconds = data.toDouble();
          case 3 when data is bool:
            isPaused = data;
        }
        if (positionSeconds != null &&
            durationSeconds != null &&
            isPaused != null) {
          break;
        }
      }

      if (positionSeconds == null ||
          durationSeconds == null ||
          isPaused == null) {
        return null;
      }
      return ExternalPlayerPlaybackProgress(
        position: Duration(milliseconds: (positionSeconds * 1000).round()),
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
        isPaused: isPaused,
      );
    } catch (_) {
      // mpv may not have created its socket yet; the next poll will retry.
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static Future<bool> _setMpvPaused(
    ExternalPlayerSession session,
    bool paused,
  ) async {
    final ipcPath = session.ipcPath;
    if (ipcPath == null || ipcPath.isEmpty) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(ipcPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('${jsonEncode({
            'command': ['set_property', 'pause', paused],
            'request_id': 4,
          })}\n');
      await socket.flush();

      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['request_id'] != 4) {
          continue;
        }
        return value['error'] == 'success';
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }
}
