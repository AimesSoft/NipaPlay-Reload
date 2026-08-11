// lib/models/external_player_session/vlc_session.dart
// Linux VLC 外部播放器会话

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/session.dart';


/// 管理 Linux 平台上的 VLC 进程和生命周期.
class VlcSession extends ChangeNotifier implements ExternalPlayerLaunchSession {

  VlcSession({
    required this.playerPath,
    required this.mediaPath,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    List<String> extraArgs = const <String>[],
  }) : _extraArgs = extraArgs;

  @override
  ExternalPlayerType get type => ExternalPlayerType.vlc;
  @override
  final String playerPath;
  @override
  final String mediaPath;
  @override
  int get processId => _processId ?? 0;
  @override
  String? get ipcPath => _rcSocketPath;

  @override
  Duration duration;
  @override
  Duration? position;
  @override
  bool? isPaused = false;

  final List<String> _extraArgs;
  Process? _process;
  int? _processId;
  String? _rcSocketPath;
  Future<int>? _processExitCode;

  static const Duration _processPollingInterval = Duration(milliseconds: 250);
  Timer? _processPollingTimer;
  Future<void> _rcCommandQueue = Future<void>.value();
  bool _closed = false;
  bool _disposed = false;

  @override
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> launch() async {
    if (!Platform.isLinux) {
      throw UnsupportedError('VlcSession 仅支持 Linux 平台');
    }
    if (_disposed) throw StateError('VlcSession 已释放');
    if (_processId != null) throw StateError('VlcSession 已启动');

    final socketPath = _createRcSocketPath();
    late Process process;
    try {
      process = await Process.start(
        playerPath,
        [
          mediaPath,
          ..._extraArgs,
          '--extraintf=oldrc',
          '--rc-fake-tty',
          '--rc-unix=$socketPath',
        ],
        mode: ProcessStartMode.normal,
      );
    } catch (_) {
      _deleteRcSocket(socketPath);
      rethrow;
    }
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    _process = process;
    _rcSocketPath = socketPath;
    _processId = process.pid;
    _processExitCode = process.exitCode;
    _startLifecycleMonitoring();
  }

  @override
  void terminate() {
    if (_closed) return;
    final processId = _processId;
    if (processId == null) {
      _close();
      return;
    }

    try {
      final killed = Process.killPid(processId, ProcessSignal.sigterm);
      if (!killed) {
        debugPrint('[VlcSession] Failed to terminate VLC: pid=$processId');
      }
    } catch (error) {
      debugPrint('[VlcSession] Failed to terminate VLC: $error');
    }
    _process?.stdin.close();
    _close();
  }

  @override
  void togglePause() {
    if (_closed || _rcSocketPath == null) return;
    unawaited(_toggleVlcPause());
  }

  @override
  void seekToFraction(double fraction) {
    if (_closed || _rcSocketPath == null || duration <= Duration.zero) return;
    final value = fraction.clamp(0.0, 1.0).toDouble();
    seekToPosition(Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    ));
  }

  @override
  bool seekToPosition(Duration target) {
    if (_closed || _rcSocketPath == null || target < Duration.zero) {
      return false;
    }
    final targetMilliseconds = duration > Duration.zero
        ? target.inMilliseconds.clamp(0, duration.inMilliseconds)
        : target.inMilliseconds;
    final value = Duration(milliseconds: targetMilliseconds);
    position = value;
    notifyListeners();
    unawaited(_seekVlc(value));
    return true;
  }

  @override
  Future<bool> refreshDanmaku(
    DanmakuItemSet danmakuSet,
    DanmakuStyle style,
  ) async => false;

  void _startLifecycleMonitoring() {
    _stopLifecycleMonitoring();
    _processExitCode?.then(
      (_) {
        if (!_closed) _close();
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[VlcSession] Failed to watch VLC exit: $error');
      },
    );
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
      running = await _refreshProcessState(timer);
    } catch (error) {
      debugPrint('[VlcSession] Failed to refresh VLC state: $error');
      running = true;
    }

    if (!identical(_processPollingTimer, timer)) return;
    if (!running) {
      _close();
      return;
    }
    _scheduleNextProcessPoll();
  }

  Future<bool> _refreshProcessState(Timer timer) async {
    final running = await _isProcessRunning();
    if (!identical(_processPollingTimer, timer) || !running) return running;

    final nextState = await _readVlcState();
    if (!identical(_processPollingTimer, timer) || nextState == null) {
      return true;
    }
    if (position == nextState.position &&
        duration == nextState.duration &&
        isPaused == nextState.isPaused) {
      return true;
    }

    position = nextState.position;
    duration = nextState.duration;
    isPaused = nextState.isPaused;
    notifyListeners();
    return true;
  }

  Future<bool> _isProcessRunning() async {
    final processId = _processId;
    if (processId == null || processId <= 0) return false;
    if (_processExitCode != null) return true;

    try {
      final value = await File('/proc/$processId/stat').readAsString();
      final closingParen = value.lastIndexOf(')');
      if (closingParen < 0 || closingParen + 2 >= value.length) return true;
      return value.substring(closingParen + 2, closingParen + 3) != 'Z';
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _toggleVlcPause() async {
    final paused = isPaused ?? false;
    final succeeded = await _sendRcCommand('pause');
    if (_closed || !succeeded) return;
    isPaused = !paused;
    notifyListeners();
  }

  Future<void> _seekVlc(Duration target) async {
    await _sendRcCommand('seek ${target.inSeconds}');
  }

  Future<_VlcPlaybackState?> _readVlcState() async {
    final lines = await _sendRcCommands([
      'get_time',
      'get_length',
      'status',
    ]);
    if (lines == null) return null;

    final numericValues = lines
        .map((line) => int.tryParse(line.trim()))
        .whereType<int>()
        .toList(growable: false);
    if (numericValues.length < 2) return null;

    final paused = lines.any(
      (line) => line.contains("Type 'pause' to continue."),
    );
    return _VlcPlaybackState(
      position: Duration(seconds: numericValues[0]),
      duration: Duration(seconds: numericValues[1]),
      isPaused: paused,
    );
  }

  Future<bool> _sendRcCommand(String command) async {
    final lines = await _sendRcCommands([command]);
    return lines != null && !lines.any((line) => line.contains('unknown command'));
  }

  Future<List<String>?> _sendRcCommands(List<String> commands) async {
    final completer = Completer<List<String>?>();
    _rcCommandQueue = _rcCommandQueue.then((_) async {
      completer.complete(await _performRcCommands(commands));
    }, onError: (_) async {
      completer.complete(await _performRcCommands(commands));
    });
    return completer.future;
  }

  Future<List<String>?> _performRcCommands(List<String> commands) async {
    final socketPath = _rcSocketPath;
    if (_closed || socketPath == null) return null;

    Socket? socket;
    StreamSubscription<List<int>>? subscription;
    Timer? settleTimer;
    final response = StringBuffer();
    final completer = Completer<void>();

    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    try {
      socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(milliseconds: 500));
      subscription = socket.listen(
        (data) {
          response.write(utf8.decode(data, allowMalformed: true));
          settleTimer?.cancel();
          settleTimer = Timer(const Duration(milliseconds: 250), complete);
        },
        onDone: complete,
        onError: (_) => complete(),
        cancelOnError: true,
      );
      socket.write('${commands.join('\n')}\n');
      await socket.flush();
      await completer.future.timeout(
        const Duration(milliseconds: 800),
        onTimeout: complete,
      );
      return const LineSplitter()
          .convert(response.toString().replaceAll('\r', ''))
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      if (File(socketPath).existsSync()) {
        debugPrint('[VlcSession] RC command failed: $error');
      }
      return null;
    } finally {
      settleTimer?.cancel();
      await subscription?.cancel();
      socket?.destroy();
    }
  }

  static String _createRcSocketPath() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'np_vlc_${pid}_$timestamp.sock';
  }

  static void _deleteRcSocket(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final socketFile = File(path);
      if (socketFile.existsSync()) socketFile.deleteSync();
    } on FileSystemException catch (error) {
      debugPrint('[VlcSession] Failed to delete RC socket: $error');
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _stopLifecycleMonitoring();
    _deleteRcSocket(_rcSocketPath);
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

class _VlcPlaybackState {
  const _VlcPlaybackState({
    required this.position,
    required this.duration,
    required this.isPaused,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;
}
