
// lib/models/external_player_session.dart
// 外部播放器相关的模型

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';


/// 掌管外部播放器会话的神
///
/// 管理一个 mpv 进程及其 IPC, 播放状态和 ASS 弹幕交互.
///
/// 本类不保存番剧, 剧集或媒体展示信息; 这些信息由控制台服务管理.
class ExternalPlayerSession extends ChangeNotifier {

  /// 构造函数
  ExternalPlayerSession(
    {
      required this.type,
      required this.playerPath,
      required this.processId,
      required this.ipcPath,
      required this.duration,

      this.position = Duration.zero,
      this.isPaused = false,
    }
  );

  // 外部播放器相关
  final ExternalPlayerType type;  // 外部播放器类型
  final String   playerPath;      // 外部播放器的路径
  final int      processId;       // 外部播放器进程 ID
  final String?  ipcPath;         // 外部播放器的 IPC 通道路径

  // 播放相关
  Duration       duration;        // 媒体文件总时长
  Duration?      position;        // 当前播放位置
  bool?          isPaused;        // 是否暂停

  // 进程轮询相关
  static const Duration _processPollingInterval = Duration(milliseconds: 250);
  Timer? _processPollingTimer;
  bool   _closed = false; // 外部播放器会话是否已关闭, 关闭后不再轮询进程和播放状态


  // --- Setters & Getters --- //

  /// 获取播放进度的百分比, 范围 0.0 ~ 1.0
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  // --- mpv Process Interaction --- //

  /// 终止当前外部播放器进程.
  void terminate() {
    if (_closed) return;
    _closed = true;
    stopProcessPolling();
    try {
      final killed = Process.killPid(processId, ProcessSignal.sigterm);
      if (!killed) debugPrint('[ExternalPlayerSession] Failed to terminate player: pid=$processId');
    }
    catch (error) { debugPrint('[ExternalPlayerSession] Failed to close player: $error'); }
  }

  /// 切换 mpv 的暂停状态.
  void togglePause() {
    final paused = isPaused;
    if (_closed || ipcPath == null || paused == null) return;
    _setMpvPaused(!paused);
  }

  /// 将 mpv 跳转到总时长中的指定比例.
  void seekToFraction(double fraction) {
    if (_closed || ipcPath == null || duration <= Duration.zero) return;
    final value = fraction.clamp(0.0, 1.0).toDouble();
    final target = Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    );
    position = target;
    notifyListeners();
    _seekMpv(target);
  }


  /// 通知指定的 mpv Lua 脚本重新加载 ASS 弹幕轨.
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

  // --- Process Polling --- //

  /// 开始轮询外部播放器进程和播放状态
  void startProcessPolling(VoidCallback onProcessExit) {
    stopProcessPolling();
    _scheduleNextProcessPoll(onProcessExit);
  }

  /// 停止轮询外部播放器进程和播放状态
  void stopProcessPolling() {
    _processPollingTimer?.cancel();
    _processPollingTimer = null;
  }


  // --- Private Methods --- //

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
          '[ExternalPlayerSession] _setMpvPaused response: ${value['error']}',
        );
        changed = value['error'] == 'success';
        break;
      }
    } catch (error) {
      debugPrint('[ExternalPlayerSession] Failed to set mpv pause: $error');
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
            '[ExternalPlayerSession] Failed to seek mpv: ${value['error']}',
          );
        }
        return;
      }
    } catch (error) {
      debugPrint('[ExternalPlayerSession] Failed to seek mpv: $error');
    } finally {
      socket?.destroy();
    }
  }

  /// 计划下一次轮询
  void _scheduleNextProcessPoll(VoidCallback onProcessExit) {
    late final Timer timer;
    timer = Timer(
      _processPollingInterval,
      () => unawaited(_pollProcessState(timer, onProcessExit)),
    );
    _processPollingTimer = timer;
  }

  /// 轮询外部播放器进程和播放状态
  Future<void> _pollProcessState(Timer timer, VoidCallback onProcessExit) async {
    bool running;
    try {
      running = await _refreshProcessState(timer);
    } catch (error) {
      debugPrint('[ExternalPlayerSession] Failed to refresh player state: $error');
      running = true;
    }

    if (!identical(_processPollingTimer, timer)) return;
    if (!running) {
      _closed = true;
      _processPollingTimer = null;
      onProcessExit();
      return;
    }

    // 继续轮询
    _scheduleNextProcessPoll(onProcessExit);
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
      debugPrint('[ExternalPlayerSession] Failed to read mpv state: $error');
      return null;
    } finally {
      socket?.destroy();
    }
  }

  @override
  void dispose() {
    _closed = true;
    stopProcessPolling();
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
