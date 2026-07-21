
// lib/models/external_player_session/linux_session.dart
// 外部播放器相关的模型

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/utils/danmaku/assets.dart';


/// 掌管外部播放器会话的神
///
/// 管理一个 Linux mpv 进程, IPC, 播放状态和 ASS 弹幕交互.
///
/// 本类保存当前媒体路径; 番剧和剧集展示信息由控制台服务管理.
class LinuxSession extends ChangeNotifier implements ExternalPlayerLaunchSession {

  /// 关联一个已经存在的外部播放器进程.
  LinuxSession.attach(
    {
      required this.playerPath,
      required this.mediaPath,
      required this.processId,
      required this.ipcPath,
      required this.duration,

      this.position = Duration.zero,
      this.isPaused = false,
      this.danmakuAssets,
      bool monitorProcess = true,
    }
  ) { if (monitorProcess) _startLifecycleMonitoring(); }

  /// 启动 Linux mpv, 并启用 IPC 和生命周期监控.
  static Future<LinuxSession> launch({
    required String       playerPath,
    required String       mediaPath,
    required List<String> extraArgs,
    DanmakuLaunchAssets? danmakuAssets,
    Duration duration = Duration.zero,
    Duration position = Duration.zero,
  }) async {

    final ipcPath    = _createMpvIpcPath();
    final launchArgs = [mediaPath, ...extraArgs, '--input-ipc-server=$ipcPath'];

    debugPrint('[LinuxSession] Launching Linux mpv: playerPath="$playerPath", args=$launchArgs');

    final process = await Process.start(playerPath, launchArgs, mode: ProcessStartMode.detached);

    debugPrint('[LinuxSession] Linux mpv started: pid=${process.pid}, ipcPath=$ipcPath');

    return LinuxSession.attach(
      playerPath : playerPath,
      mediaPath  : mediaPath,
      processId  : process.pid,
      ipcPath    : ipcPath,
      duration   : duration,
      position   : position,
      danmakuAssets: danmakuAssets,
    );
  }

  // 外部播放器相关
  @override
  ExternalPlayerType get type => ExternalPlayerType.mpv;
  @override
  final String   playerPath;     // 外部播放器的路径
  @override
  final String   mediaPath;      // 当前播放的媒体路径
  @override
  final int      processId;      // 外部播放器进程 ID
  @override
  final String?  ipcPath;        // 外部播放器的 IPC 通道路径
  DanmakuLaunchAssets? danmakuAssets; // 启动时加载的弹幕文件和导出设置

  // 播放相关
  @override
  Duration       duration;       // 媒体文件总时长
  @override
  Duration?      position;       // 当前播放位置
  @override
  bool?          isPaused;       // 是否暂停

  // 进程轮询相关
  static const Duration _processPollingInterval = Duration(milliseconds: 250);
  Timer? _processPollingTimer;
  bool   _closed   = false; // 外部播放器会话是否已关闭, 关闭后不再轮询进程和播放状态
  bool   _disposed = false; // ChangeNotifier 是否已被 dispose, dispose 后不再通知监听器


  // --- Setters & Getters --- //

  /// 获取播放进度的百分比, 范围 0.0 ~ 1.0
  @override
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }
  @override
  bool get isClosed => _closed;

  // --- mpv Process Interaction --- //

  /// 终止当前外部播放器进程.
  @override
  void terminate() {
    if (_closed) return;
    try {
      final killed = Process.killPid(processId, ProcessSignal.sigterm);
      if (!killed) debugPrint('[LinuxSession] Failed to terminate player: pid=$processId');
    }
    catch (error) { debugPrint('[LinuxSession] Failed to close player: $error'); }
    _close();
  }

  /// 切换 mpv 的暂停状态.
  @override
  void togglePause() {
    final paused = isPaused;
    if (_closed || ipcPath == null || paused == null) return;
    _setMpvPaused(!paused);
  }

  /// 将 mpv 跳转到总时长中的指定比例.
  @override
  void seekToFraction(double fraction) {
    if (_closed || ipcPath == null || duration <= Duration.zero) return;
    final value = fraction.clamp(0.0, 1.0).toDouble();
    final target = Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    );
    seekToPosition(target);
  }

  /// 将 mpv 精确跳转到指定的绝对播放位置.
  @override
  bool seekToPosition(Duration target) {
    if (_closed || ipcPath == null || target < Duration.zero) return false;
    final targetMilliseconds = duration > Duration.zero
        ? target.inMilliseconds.clamp(0, duration.inMilliseconds)
        : target.inMilliseconds;
    final value = Duration(milliseconds: targetMilliseconds);
    position = value;
    notifyListeners();
    _seekMpv(value);
    return true;
  }


  /// 通知指定的 mpv Lua 脚本重新加载 ASS 弹幕轨.
  @override
  Future<bool> refreshDanmaku(String assPath, String luaPath) async {
    final path = ipcPath;
    if (_closed || path == null || path.isEmpty ||
        assPath.isEmpty || luaPath.isEmpty) {
      return false;
    }

    final luaFilename = luaPath.split(Platform.pathSeparator).last;
    final luaScriptName = luaFilename.toLowerCase().endsWith('.lua')
        ? luaFilename.substring(0, luaFilename.length - 4)
        : luaFilename;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('${jsonEncode({
            'command': [
              'script-message-to',
              luaScriptName,
              'nipaplay-danmaku-reload',
              assPath,
            ],
            'request_id': 5,
          })}\n');
      await socket.flush();

      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['request_id'] != 5) {
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

  // --- Private Methods --- //

  void _startLifecycleMonitoring() {
    _stopLifecycleMonitoring();
    _scheduleNextProcessPoll();
  }

  void _stopLifecycleMonitoring() {
    _processPollingTimer?.cancel();
    _processPollingTimer = null;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _stopLifecycleMonitoring();
    _deleteIpcSocket();
    if (!_disposed) notifyListeners();
  }

  void _deleteIpcSocket() {
    final path = ipcPath;
    if (path == null || path.isEmpty) return;
    try {
      final socketFile = File(path);
      if (socketFile.existsSync()) socketFile.deleteSync();
    } catch (error) {
      debugPrint('[LinuxSession] Failed to delete IPC socket: $error');
    }
  }

  static String _createMpvIpcPath() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'nipaplay_mpv_${pid}_$timestamp.sock';
  }

  Future<void> _setMpvPaused(bool paused) async {
    final path = ipcPath;
    if (_closed || path == null) return;

    Socket? socket;
    var changed = false;
    try {
      final host = InternetAddress(path, type: InternetAddressType.unix);
      final command = jsonEncode({
        'command': ['set_property', 'pause', paused],
        'request_id': 4,
      });
      socket = await Socket.connect(
        host,
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('$command\n');
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
        debugPrint(
          '[LinuxSession] _setMpvPaused response: ${value['error']}',
        );
        changed = value['error'] == 'success';
        break;
      }
    } catch (error) {
      debugPrint('[LinuxSession] Failed to set mpv pause: $error');
    } finally {
      socket?.destroy();
    }

    if (!_closed && changed) {
      isPaused = paused;
      notifyListeners();
    }
  }

  Future<void> _seekMpv(Duration target) async {
    final path = ipcPath;
    if (_closed || path == null) return;

    Socket? socket;
    try {
      final host = InternetAddress(path, type: InternetAddressType.unix);
      socket = await Socket.connect(
        host,
        0,
        timeout: const Duration(milliseconds: 500),
      );
      if (_closed) return;

      final command = jsonEncode({
        'command': [
          'seek',
          target.inMilliseconds / 1000.0,
          'absolute+exact',
        ],
        'request_id': 6,
      });
      socket.write('$command\n');
      await socket.flush();

      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['request_id'] != 6) {
          continue;
        }
        if (value['error'] != 'success') {
          debugPrint(
            '[LinuxSession] Failed to seek mpv: ${value['error']}',
          );
        }
        return;
      }
    } catch (error) {
      debugPrint('[LinuxSession] Failed to seek mpv: $error');
    } finally {
      socket?.destroy();
    }
  }

  /// 计划下一次轮询
  void _scheduleNextProcessPoll() {
    late final Timer timer;
    timer = Timer(
      _processPollingInterval,
      () => unawaited(_pollProcessState(timer)),
    );
    _processPollingTimer = timer;
  }

  /// 轮询外部播放器进程和播放状态
  Future<void> _pollProcessState(Timer timer) async {
    bool running;
    try {
      running = await _refreshProcessState(timer);
    } catch (error) {
      debugPrint('[LinuxSession] Failed to refresh player state: $error');
      running = true;
    }

    if (!identical(_processPollingTimer, timer)) return;
    if (!running) {
      _close();
      return;
    }

    // 继续轮询
    _scheduleNextProcessPoll();
  }

  Future<bool> _refreshProcessState(Timer timer) async {
    final running = await _isLinuxProcessRunning();
    if (!identical(_processPollingTimer, timer) || !running) return running;

    final nextState = await _readMpvState();
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

  Future<bool> _isLinuxProcessRunning() async {
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

  Future<_ExternalPlayerPlaybackState?> _readMpvState() async {
    if (ipcPath == null || ipcPath!.isEmpty) return null;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(ipcPath!, type: InternetAddressType.unix),
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
      bool? paused;
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
            paused = data;
        }
        if (positionSeconds != null &&
            durationSeconds != null &&
            paused != null) {
          break;
        }
      }

      if (positionSeconds == null ||
          durationSeconds == null ||
          paused == null) {
        return null;
      }
      return _ExternalPlayerPlaybackState(
        position: Duration(milliseconds: (positionSeconds * 1000).round()),
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
        isPaused: paused,
      );
    } catch (error) {
      debugPrint('[LinuxSession] Failed to read mpv state: $error');
      return null;
    } finally {
      socket?.destroy();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_closed) terminate();
    _stopLifecycleMonitoring();
    super.dispose();
  }

}

/// 外部播放器本轮轮询得到的播放状态
class _ExternalPlayerPlaybackState {
  const _ExternalPlayerPlaybackState({
    required this.position,
    required this.duration,
    required this.isPaused,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;
}
