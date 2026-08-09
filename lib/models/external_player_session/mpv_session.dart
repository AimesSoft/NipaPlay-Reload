
// lib/models/external_player_session/mpv_session.dart
// 外部播放器相关的模型

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';


/// 掌管外部播放器会话的神
///
/// 管理一个 Linux, macOS 或 Windows mpv 进程, IPC, 播放状态和 ASS 弹幕交互.
///
/// 本类保存当前媒体路径; 番剧和剧集展示信息由控制台服务管理.
class MpvSession extends ChangeNotifier implements ExternalPlayerLaunchSession {

  // 私有字段
  final String _playerPath; // 外部播放器的可执行文件路径
  final String _mediaPath;  // 当前播放的媒体路径
  String?   _ipcPath;    // 外部播放器的 IPC 通信路径
  int?      _processId;  // 外部播放器进程的 PID
  Duration? _duration;   // 外部播放器的总时长
  Duration? _position;   // 外部播放器的当前播放位置
  bool?     _isPaused;   // 外部播放器是否处于暂停状态
  String? _assFilePath; // mpv 弹幕 ASS 文件路径
  String? _luaFilePath; // mpv 弹幕 Lua 脚本路径

  final List<String> _extraArgs; // mpv 启动参数, 由外部传入
  final bool _isMpvNet;

  // 进程轮询相关
  static const Duration _processPollingInterval = Duration(milliseconds: 250);
  Timer? _processPollingTimer;
  bool _closed = false;
  bool _disposed = false; // ChangeNotifier 是否已被 dispose, dispose 后不再通知监听器
  Future<int>? _processExitCode;

  // 构造函数
  MpvSession(String playerPath, String mediaPath, {
    List<String> extraArgs = const <String>[],
    bool isMpvNet = false,
    Duration duration = Duration.zero,
    Duration position = Duration.zero,
  }) :
  _playerPath = playerPath,
  _mediaPath = mediaPath,
  _extraArgs = extraArgs,
  _isMpvNet = isMpvNet,
  _duration = duration,
  _position = position,
  _isPaused = false;


  // --- Setters & Getters --- //

  @override
  ExternalPlayerType get type => _isMpvNet ? ExternalPlayerType.mpvNet : ExternalPlayerType.mpv;
  @override
  String get playerPath => _playerPath;
  @override
  String get mediaPath => _mediaPath;
  @override
  int get processId => _processId ?? 0;
  @override
  String? get ipcPath => _ipcPath;
  @override
  Duration get duration => _duration ?? Duration.zero;
  @override
  Duration? get position => _position;
  @override
  bool? get isPaused => _isPaused;

  /// 获取播放进度的百分比, 范围 0.0 ~ 1.0
  @override
  double? get fraction {
    if (_position == null || duration <= Duration.zero) return null;
    return (_position!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool get isClosed => _closed;


  // ======================================================================== //
  // =================== mpv Process Interaction ============================ //
  // ======================================================================== //

  /// 启动 Linux, macOS 或 Windows mpv, 并启用 IPC 和生命周期监控.
  ///
  /// 弹幕文件由本会话创建并管理, 后续更新由 [refreshDanmaku] 完成.
  @override
  Future<void> launch() async {

    if (_disposed) throw StateError('MpvSession 已释放');
    if (_processId != null) throw StateError('MpvSession 已启动');

    final ipcPath = _createMpvIpcPath();
    final executablePath = await _resolveExecutablePath(_playerPath);

    final directory = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}nipaplay_danmaku');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final assPath = '${directory.path}${Platform.pathSeparator}danmaku_$timestamp.ass';
    final luaPath = '${directory.path}${Platform.pathSeparator}nipaplay_danmaku_$timestamp.lua';
    final assName = assPath.split(Platform.pathSeparator).last;
    try {
      await File(assPath).writeAsString('', encoding: utf8, flush: true);
      await File(luaPath).writeAsString(
        _danmakuLuaScript.replaceAll('__NIPAPLAY_ASS_BASENAME__', assName),
        encoding: utf8,
        flush: true,
      );
    } catch (_) {
      _deleteDanmakuFilePaths(assPath, luaPath);
      rethrow;
    }
    _assFilePath = assPath;
    _luaFilePath = luaPath;

    final launchArgs = [
      _mediaPath,
      ..._extraArgs,
      '--sub-file=$_assFilePath',
      '--script=$_luaFilePath',
      _isMpvNet ? '--secondary-sub-override=no' : '--secondary-sub-ass-override=no',
      '--input-ipc-server=$ipcPath',
    ];
    debugPrint(
      '[MpvSession] Launching mpv: playerPath="$_playerPath", '
      'executablePath="$executablePath", args=$launchArgs',
    );

    // 不通过 `open --args` 启动 mpv.app。沙盒应用交给 LaunchServices 后，
    // 参数可能不会转交给新实例，最终只会出现一个未加载媒体的空白 mpv 窗口。
    // 直接执行包内主程序也能让 processId 精确指向本次 mpv 会话。
    //
    // Windows 下使用 detached 模式启动 mpv, 进程存活检测通过 tasklist 实现。
    late Process process;
    try {
      process = await Process.start(
        executablePath,
        launchArgs,
        mode: Platform.isMacOS
            ? ProcessStartMode.normal
            : ProcessStartMode.detached,
      );
    } catch (_) {
      _deleteDanmakuFilePaths(
        _assFilePath,
        _luaFilePath,
      );
      _assFilePath = null;
      _luaFilePath = null;
      rethrow;
    }
    if (Platform.isMacOS) {
      process.stdin.close();
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      _processExitCode = process.exitCode;
    }

    _ipcPath = ipcPath;
    _processId = process.pid;

    debugPrint('[MpvSession] mpv started: pid=${process.pid}, ipcPath=$ipcPath');

    _startLifecycleMonitoring(); // 启动进程轮询和生命周期监控
  }

  /// 终止当前外部播放器进程.
  @override
  void terminate() {

    if (isClosed) return;

    final processId = _processId;
    try {
      if (processId == null) {
        return;
      } else if (Platform.isWindows) {
        // Windows 没有 SIGTERM, detached 进程需要通过 taskkill 终止.
        // /T 终止进程树, /F 强制终止.
        Process.runSync('taskkill', ['/PID', '$processId', '/T', '/F']);
      } else {
        final killed = Process.killPid(processId, ProcessSignal.sigterm);
        if (!killed) {
          debugPrint('[MpvSession] Failed to terminate player: pid=$processId');
        }
      }
    } catch (error) {
      debugPrint('[MpvSession] Failed to close player: $error');
    } finally {
      _close();
    }
  }

  /// 切换 mpv 的暂停状态.
  @override
  void togglePause() {

    if (isClosed || _ipcPath == null) return;

    var paused = _isPaused;
    paused ??= false;
    _setMpvPaused(!paused);
  }

  /// 将 mpv 跳转到总时长中的指定比例.
  @override
  void seekToFraction(double fraction) {
    if (isClosed || _ipcPath == null || duration <= Duration.zero) return;
    final value = fraction.clamp(0.0, 1.0).toDouble();
    final target = Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    );
    seekToPosition(target);
  }

  /// 将 mpv 精确跳转到指定的绝对播放位置.
  @override
  bool seekToPosition(Duration target) {
    if (isClosed || _ipcPath == null || target < Duration.zero) return false;
    final targetMilliseconds = duration > Duration.zero
        ? target.inMilliseconds.clamp(0, duration.inMilliseconds)
        : target.inMilliseconds;
    final value = Duration(milliseconds: targetMilliseconds);
    _position = value;
    notifyListeners();
    _seekMpv(value);
    return true;
  }

  /// 重新生成 ASS 弹幕文件并通知 mpv Lua 脚本重载弹幕轨.
  @override
  Future<bool> refreshDanmaku(DanmakuItemSet danmakuSet, DanmakuStyle style) async {

    if (isClosed || _assFilePath == null || _luaFilePath == null || _ipcPath == null) {
      return false;
    }

    final String assPath = _assFilePath!;
    final String luaPath = _luaFilePath!;
    final String ipcPath = _ipcPath!;

    final settings = _createAssExportSettings(style);
    final luaFilename = luaPath.split(Platform.pathSeparator).last;
    final luaScriptName = luaFilename.toLowerCase().endsWith('.lua')
        ? luaFilename.substring(0, luaFilename.length - 4)
        : luaFilename;

    Socket? socket;
    File? temporaryFile;
    try {
      final ass = await generateExternalPlayerDanmakuAss(danmakuSet.toList(growable: false), settings);
      temporaryFile = File('$assPath.nipaplay.tmp');
      await temporaryFile.writeAsString(ass, encoding: utf8, flush: true);
      temporaryFile.renameSync(assPath);
      temporaryFile = null;

      socket = await _connectToIpc(ipcPath);
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
      if (temporaryFile?.existsSync() == true) temporaryFile?.deleteSync();
      socket?.destroy();
    }
  }

  // --- Private Methods --- //

  void _startLifecycleMonitoring() {
    _stopLifecycleMonitoring();
    final processExitCode = _processExitCode;
    if (processExitCode != null) {
      processExitCode.then(
        (_) {
          if (!_closed) _close();
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[MpvSession] Failed to watch player exit: $error');
        },
      );
    }
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
    _deleteDanmakuFiles();
    if (!_disposed) notifyListeners();
  }

  void _deleteDanmakuFiles() {
    _deleteDanmakuFilePaths(_assFilePath, _luaFilePath);
  }

  static AssExportSettings _createAssExportSettings(DanmakuStyle style) {
    final outlineStyle = style.outlineEnabled
        ? AssOutlineStyle.uniform
        : AssOutlineStyle.none;
    return AssExportSettings(
      fontSize: style.danmakuFontSize,
      opacity: style.opacity,
      timeOffsetSeconds: style.danmakuOffset,
      allowStacking: style.danmakuAllowStacking,
      outlineStyle: outlineStyle,
      outlineWidth: style.outlineWidth,
    );
  }

  static void _deleteDanmakuFilePaths(String? assPath, String? luaPath) {
    for (final path in [assPath, luaPath]) {
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
        final temporaryFile = File('$path.nipaplay.tmp');
        if (temporaryFile.existsSync()) temporaryFile.deleteSync();
      } on FileSystemException catch (error) {
        debugPrint('[MpvSession] Failed to delete danmaku file: $error');
      }
    }
  }

  void _deleteIpcSocket() {
    final path = _ipcPath;
    if (path == null || path.isEmpty) return;
    // Windows 命名管道无需手动删除文件
    if (Platform.isWindows) return;
    try {
      final socketFile = File(path);
      if (socketFile.existsSync()) socketFile.deleteSync();
    } catch (error) {
      debugPrint('[MpvSession] Failed to delete IPC socket: $error');
    }
  }

  static String _createMpvIpcPath() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    if (Platform.isWindows) {
      // Windows mpv 使用命名管道作为 IPC 通道.
      // 格式: \\.\pipe\name, 名称需保持简洁.
      final compactTimestamp = timestamp.toRadixString(36);
      return r'\\.\pipe\' 'nipaplay_${pid}_$compactTimestamp';
    }
    // macOS 的 sockaddr_un.sun_path 最多只能容纳 104 字节（含结尾的 NUL）。
    // 沙盒的 systemTemp 本身已经很长，因此文件名必须保持紧凑。
    final compactTimestamp = timestamp.toRadixString(36);
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'np_${pid}_$compactTimestamp.sock';
  }

  static Future<String> _resolveExecutablePath(String playerPath) async {
    if (!Platform.isMacOS || !playerPath.toLowerCase().endsWith('.app')) {
      return playerPath;
    }

    final executablePath = [
      playerPath,
      'Contents',
      'MacOS',
      'mpv',
    ].join(Platform.pathSeparator);
    if (await File(executablePath).exists()) return executablePath;

    throw ProcessException(
      playerPath,
      const [],
      'mpv.app 中未找到 Contents/MacOS/mpv',
    );
  }

  /// 连接到 mpv 的 IPC 端点.
  ///
  /// - Linux/macOS: 直接使用 Dart 的 Unix Domain Socket
  /// - Windows: 使用 dart_ipc 的命名管道 (Named Pipe)
  ///
  /// mpv 的 --input-ipc-server 在 Windows 上接受命名管道路径 (如 \\.\pipe\xxx).
  static Future<Socket> _connectToIpc(String path) async {
    final connection = Platform.isWindows
        ? connect(path)
        : Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
          );
    return await connection.timeout(const Duration(milliseconds: 500));
  }

  Future<void> _setMpvPaused(bool paused) async {
    final path = _ipcPath;
    if (_closed || path == null) return;

    Socket? socket;
    var changed = false;
    try {
      final command = jsonEncode({
        'command': ['set_property', 'pause', paused],
        'request_id': 4,
      });
      socket = await _connectToIpc(path);
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
          '[MpvSession] _setMpvPaused response: ${value['error']}',
        );
        changed = value['error'] == 'success';
        break;
      }
    } catch (error) {
      debugPrint('[MpvSession] Failed to set mpv pause: $error');
    } finally {
      socket?.destroy();
    }

    if (!_closed && changed) {
      _isPaused = paused;
      notifyListeners();
    }
  }

  Future<void> _seekMpv(Duration target) async {
    final path = _ipcPath;
    if (_closed || path == null) return;

    Socket? socket;
    try {
      socket = await _connectToIpc(path);
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
            '[MpvSession] Failed to seek mpv: ${value['error']}',
          );
        }
        return;
      }
    } catch (error) {
      debugPrint('[MpvSession] Failed to seek mpv: $error');
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
      debugPrint('[MpvSession] Failed to refresh player state: $error');
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
    final running = await _isProcessRunning();
    if (!identical(_processPollingTimer, timer) || !running) return running;

    final nextState = await _readMpvState();
    if (!identical(_processPollingTimer, timer) || nextState == null) {
      return true;
    }

    if (_position == nextState.position &&
        _duration == nextState.duration &&
        _isPaused == nextState.isPaused) {
      return true;
    }

    _position = nextState.position;
    _duration = nextState.duration;
    _isPaused = nextState.isPaused;
    notifyListeners();
    return true;
  }

  Future<bool> _isProcessRunning() async {
    if (processId <= 0) return false;

    // macOS 沙盒内执行 `ps` 可能失败并把仍在播放的 mpv 误判为已退出。
    // launch 创建的会话通过 Process.exitCode 精确监听，轮询期间保持存活。
    if (_processExitCode != null) return true;

    if (Platform.isLinux) {
      try {
        final value = await File('/proc/$processId/stat').readAsString();
        final closingParen = value.lastIndexOf(')');
        if (closingParen < 0 || closingParen + 2 >= value.length) return true;
        return value.substring(closingParen + 2, closingParen + 3) != 'Z';
      } on FileSystemException {
        return false;
      }
    }

    if (Platform.isMacOS) {
      try {
        final result = await Process.run(
          '/bin/ps',
          ['-p', '$processId', '-o', 'stat='],
        );
        if (result.exitCode != 0) return false;
        final state = (result.stdout as String).trim();
        return state.isNotEmpty && !state.startsWith('Z');
      } on ProcessException {
        return false;
      }
    }

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

    return false;
  }

  Future<_ExternalPlayerPlaybackState?> _readMpvState() async {
    final path = _ipcPath;
    if (path == null || path.isEmpty) return null;

    Socket? socket;
    try {
      socket = await _connectToIpc(path);
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
      debugPrint('[MpvSession] Failed to read mpv state: $error');
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


/// NipaPlay 弹幕外挂 Lua 脚本模板
const String _danmakuLuaScript = r'''-- NipaPlay 弹幕外挂脚本: 把弹幕字幕轨设为次字幕(secondary-sid)
-- 由 NipaPlay 自动生成; 目标弹幕文件名: __NIPAPLAY_ASS_BASENAME__
-- 不抢占主字幕（内嵌/外挂）, 弹幕作为次字幕始终显示.
local TARGET = "__NIPAPLAY_ASS_BASENAME__"
local function find_danmaku_track()
    local tracks = mp.get_property_native("track-list")
    if not tracks then return nil end
    local did = nil
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.external and t.title
           and string.find(t.title, TARGET, 1, true) then
            did = t.id
        end
    end
    return did, tracks
end

local function select_danmaku_track()
    local did, tracks = find_danmaku_track()
    if not did then return end
    local cur = mp.get_property("sid")
    if cur and tonumber(cur) == did then
        local switched = false
        for _, t in ipairs(tracks) do
            if t.type == "sub" and t.id ~= did then
                mp.set_property("sid", tostring(t.id))
                switched = true
                break
            end
        end
        if not switched then
            -- 没有其它字幕轨, 弹幕作为主字幕显示即可
            return
        end
    end
    mp.set_property("secondary-sid", tostring(did))
end

mp.register_event("file-loaded", select_danmaku_track)

local reload_timer = nil

local function restore_primary_track(primary)
    -- sub-reload 会选中重载后的轨道, 但不会同步 sid 选项值.
    -- 先显式取消主字幕, 再恢复原主字幕, 避免相同 sid 被 mpv 当作无变化.
    mp.set_property("sid", "no")
    if primary and primary ~= "no" then
        mp.set_property("sid", primary)
    end
end

local function reload_danmaku_track()
    reload_timer = nil
    local did = find_danmaku_track()
    if not did then return end
    local primary = mp.get_property("sid")
    local was_primary = tonumber(primary) == did
    local was_secondary = tonumber(mp.get_property("secondary-sid")) == did
    mp.commandv("sub-reload", tostring(did))

    mp.add_timeout(0, function()
        local reloaded_did = find_danmaku_track()
        if not reloaded_did then
            restore_primary_track(primary)
            return
        end

        if was_secondary then
            restore_primary_track(primary)
            mp.add_timeout(0, function()
                local current_did = find_danmaku_track()
                if current_did then
                    mp.set_property("secondary-sid", tostring(current_did))
                end
            end)
        elseif was_primary then
            mp.set_property("sid", tostring(reloaded_did))
        else
            restore_primary_track(primary)
        end
    end)
end

mp.register_script_message("nipaplay-danmaku-reload", function(ass_path)
    if ass_path and ass_path ~= "" then
        local ass_name = string.match(ass_path, "([^/\\]+)$")
        if ass_name then TARGET = ass_name end
    end
    if reload_timer then reload_timer:kill() end
    reload_timer = mp.add_timeout(0.05, reload_danmaku_track)
end)
''';
