
// lib/services/external_player_console_service.dart
// Linux 外部播放器控制台服务

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/external_player_danmaku_item.dart';
import 'package:nipaplay/models/external_player_session.dart';


/// 项目里掌管外部播放器控制台的唯一神
class ExternalPlayerConsoleService extends ChangeNotifier {

  // 单例
  ExternalPlayerConsoleService._();
  static final ExternalPlayerConsoleService _instance = ExternalPlayerConsoleService._();
  static ExternalPlayerConsoleService get instance => _instance;

  ExternalPlayerSession? _session; // 当前活跃的外部播放器会话
  Future<void> _danmakuStyleUpdateQueue = Future<void>.value();

  static bool get isSupportedPlatform => !kIsWeb && Platform.isLinux;

  // --- Setters & Getters --- //

  ExternalPlayerSession? get session => _session;
  bool get hasActiveSession => _session != null;
  bool get supportsDanmakuOpacity => _session?.ipcPath != null && _session?.danmakuAssPath != null;
  bool get supportsDanmakuOutline => _session?.ipcPath != null && _session?.danmakuAssPath != null;

  /// 获取当前播放位置正在显示的弹幕索引列表, 按照 startTime 升序排列
  List<int> get activeDanmakuIndices {
    final current = _session;
    final position = current?.position;
    if (current == null || position == null) return const [];
    return current.activeDanmakuIndicesAt(position);
  }

  /// 获取当前播放位置正在显示的弹幕, 按照 startTime 升序排列
  List<ExternalPlayerDanmakuItem> get activeDanmakuItems {
    final current = _session;
    final position = current?.position;
    if (current == null || position == null) return const [];
    return current.activeDanmakuAt(position);
  }


  // --- 主要功能 --- //

  /// 设置新的外部播放器会话, 并显示控制台
  static void showSession(ExternalPlayerSession session) {

    // 如已经有活跃会话, 则先终止它
    final previous = _instance._session;
    previous?.removeListener(_handleSessionChanged);
    previous?.stopProcessPolling();
    if (previous != null && previous.processId != session.processId) {
      _terminate(previous.processId);
    }

    // 设置新的会话
    _instance._session = session;
    session.addListener(_handleSessionChanged);
    session.startProcessPolling(() => _clearSession(session));

    // 通知监听器更新 UI
    _instance.notifyListeners();
  }

  /// 关闭当前外部播放器会话, 并关闭控制台
  static void closePlayerAndConsole() {

    // 如果没有活跃会话, 则直接返回
    final current = _instance._session;
    if (current == null) return;

    current.removeListener(_handleSessionChanged);
    current.stopProcessPolling();
    _terminate(current.processId);

    // 设置为无活跃会话, 并清理相关状态
    _instance._session = null;

    // 通知监听器更新 UI
    _instance.notifyListeners();
  }

  /// 切换当前外部播放器的暂停状态
  static void togglePause() {

    // 参数检查
    final current = _instance._session;
    if (current == null || current.ipcPath == null) return;

    // 向 mpv 发送命令
    final targetPaused = !current.isPaused!;
    _setMpvPaused(current.ipcPath!, targetPaused);
  }

  /// 将 mpv 跳转到总时长中的指定比例
  static void seekToFraction(double fraction) {

    // 参数检查
    final current = _instance._session;
    if (!_isIpcOK(current) || current!.duration <= Duration.zero) return;

    final value = fraction.clamp(0.0, 1.0).toDouble();
    final position = Duration(milliseconds: (current.duration.inMilliseconds * value).round());

    // 先更新控制台显示, mpv 的实际位置会由后续轮询校正
    current.position = position;
    _instance.notifyListeners();
    _seekMpv(current, position);
  }

  /// 设置当前外部播放器的弹幕透明度
  static void setDanmakuOpacity(double opacity) {

    // 参数检查
    final current = _instance._session;
    if (!_isIpcOK(current)) return;
    final assPath = current!.danmakuAssPath;
    if (current.ipcPath == null || assPath == null || assPath.isEmpty) return;

    final value = opacity.clamp(0.0, 1.0).toDouble();
    current.danmakuOpacity = value;
    _instance.notifyListeners();
    _instance._danmakuStyleUpdateQueue =
        _instance._danmakuStyleUpdateQueue.then((_) async {
      if (!_isCurrentSession(current) || current.danmakuOpacity != value) {
        return;
      }
      await _setDanmakuOpacity(current, assPath, value);
    });
  }

  /// 设置当前外部播放器是否显示弹幕描边
  static void setDanmakuOutlineEnabled(bool enabled) {

    // 参数检查
    final current = _instance._session;
    if (!_isIpcOK(current)) return;
    final assPath = current!.danmakuAssPath;
    if (current.ipcPath == null || assPath == null || assPath.isEmpty) return;

    current.danmakuOutlineEnabled = enabled;
    _instance.notifyListeners();
    _instance._danmakuStyleUpdateQueue =
        _instance._danmakuStyleUpdateQueue.then((_) async {
      if (!_isCurrentSession(current) ||
          current.danmakuOutlineEnabled != enabled) {
        return;
      }
      await _setDanmakuOutlineEnabled(current, assPath, enabled);
    });
  }


  // --- Private Methods --- //

  static void _handleSessionChanged() {
    _instance.notifyListeners();
  }

  static void _clearSession(ExternalPlayerSession session) {
    if (!identical(_instance._session, session)) return;

    session.removeListener(_handleSessionChanged);
    session.stopProcessPolling();
    _instance._session = null;
    _instance.notifyListeners();
  }

  static bool _isCurrentSession(ExternalPlayerSession session) {
    return identical(_instance._session, session);
  }

  static void _terminate(int processId) {
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

  /// 向 mpv 的 JSON IPC 套接字发送暂停/播放命令
  /// 不保证命令一定会成功
  static void _setMpvPaused(String ipcPath, bool paused) async {

    Socket? socket; // 本次命令的套接字连接
    bool changed = false; // 暂停状态是否改变
    try {

      // 创建套接字连接并发送命令
      final host    = InternetAddress(ipcPath, type: InternetAddressType.unix);
      const timeout = Duration(milliseconds: 500);
      final str     = jsonEncode({'command': ['set_property', 'pause', paused], 'request_id': 4});
      socket = await Socket.connect(host, 0, timeout: timeout);
      socket.write('$str\n');

      // 等待 mpv 响应
      await socket.flush();

      // 解析响应, 检查暂停状态是否改变
      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {

        // 只处理 request_id 为 4 的响应, 并检查 error 字段
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['request_id'] != 4) continue;

        // 如果响应为 success, 则认为暂停状态已设置成功
        final res = value['error'];
        debugPrint('[ExtPlayerConsole] _setMpvPaused response: $res');
        if (res == 'success') changed = true;
        break;
      }
    }
    finally { socket?.destroy(); } // 清理套接字连接

    // 如果暂停状态改变, 更新当前会话的暂停状态, 并通知监听器更新 UI
    if (changed) {
      _instance._session?.isPaused = paused;
      _instance.notifyListeners();
    }
  }

  /// 向 mpv 的 JSON IPC 套接字发送绝对精确跳转命令
  /// 不保证命令一定会成功, 失败时播放状态轮询会恢复实际进度
  static void _seekMpv(ExternalPlayerSession session, Duration position) async {

    // 参数检查
    final ipcPath = session.ipcPath;
    if (!_isIpcOK(session) || !_isCurrentSession(session)) return;

    Socket? socket; // 本次命令的套接字连接
    try {

      // 创建套接字连接并发送命令
      final host = InternetAddress(ipcPath!, type: InternetAddressType.unix);
      const timeout = Duration(milliseconds: 500);
      socket = await Socket.connect(host, 0, timeout: timeout);

      if (!_isCurrentSession(session)) return;

      final str = jsonEncode({'command': ['seek', position.inMilliseconds / 1000.0, 'absolute+exact', ], 'request_id': 6});
      socket.write('$str\n');
      await socket.flush();

      // 等待 mpv 响应, 但不处理响应内容, 只打印日志
      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {

        // 只处理 request_id 为 6 的响应, 并检查 error 字段
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['request_id'] != 6) continue;
        if (value['error'] != 'success') debugPrint('[ExtPlayerConsole] Failed to seek mpv: ${value['error']}');
        return;
      }
    }
    catch (e) { debugPrint('[ExtPlayerConsole] Failed to seek mpv: $e'); } 
    finally { socket?.destroy(); }
  }

  static Future<void> _setDanmakuOpacity(
    ExternalPlayerSession session,
    String assPath,
    double opacity,
  ) async {
    File? temporaryFile;
    try {
      final file = File(assPath);
      final originalAss = await file.readAsString();
      if (!_isCurrentSession(session) || session.danmakuOpacity != opacity) {
        return;
      }

      final alpha = ((1.0 - opacity) * 255.0).round().clamp(0, 255);
      final alphaHex = alpha.toRadixString(16).toUpperCase().padLeft(2, '0');
      final alphaPattern = RegExp(r'\\1a&H[0-9A-Fa-f]{2}&');
      if (!alphaPattern.hasMatch(originalAss)) {
        debugPrint('[ExtPlayerConsole] Danmaku ASS has no opacity tags: $assPath');
        return;
      }
      final updated = originalAss.replaceAll(
        alphaPattern,
        '\\1a&H$alphaHex&',
      );

      temporaryFile = File('$assPath.nipaplay.tmp');
      await temporaryFile.writeAsString(updated, encoding: utf8, flush: true);
      if (!_isCurrentSession(session) || session.danmakuOpacity != opacity) {
        return;
      }

      temporaryFile.renameSync(assPath);
      temporaryFile = null;
      final reloaded = await _reloadMpvDanmaku(session);
      if (!reloaded) {
        debugPrint('[ExtPlayerConsole] Failed to reload danmaku after opacity update');
      }
    } catch (error) {
      debugPrint('[ExtPlayerConsole] Failed to update danmaku opacity: $error');
    } finally {
      if (temporaryFile?.existsSync() == true) {
        temporaryFile?.deleteSync();
      }
    }
  }

  static Future<void> _setDanmakuOutlineEnabled(
    ExternalPlayerSession session,
    String assPath,
    bool enabled,
  ) async {
    File? temporaryFile;
    try {
      final file = File(assPath);
      final originalAss = await file.readAsString();
      if (!_isCurrentSession(session) ||
          session.danmakuOutlineEnabled != enabled) {
        return;
      }

      final stylePattern = RegExp(
        r'^(Style:\s*(?:[^,\r\n]*,){16})([^,\r\n]*)(,.*)$',
        multiLine: true,
      );
      if (!stylePattern.hasMatch(originalAss)) {
        debugPrint('[ExtPlayerConsole] Danmaku ASS has no style outlines: $assPath');
        return;
      }
      final outlineWidth = enabled
          ? session.danmakuOutlineWidth.toStringAsFixed(1)
          : '0.0';
      final updated = originalAss.replaceAllMapped(
        stylePattern,
        (match) => '${match.group(1)}$outlineWidth${match.group(3)}',
      );

      temporaryFile = File('$assPath.nipaplay.tmp');
      await temporaryFile.writeAsString(updated, encoding: utf8, flush: true);
      if (!_isCurrentSession(session) ||
          session.danmakuOutlineEnabled != enabled) {
        return;
      }

      temporaryFile.renameSync(assPath);
      temporaryFile = null;
      final reloaded = await _reloadMpvDanmaku(session);
      if (!reloaded) {
        debugPrint('[ExtPlayerConsole] Failed to reload danmaku after outline update');
      }
    } catch (error) {
      debugPrint('[ExtPlayerConsole] Failed to update danmaku outline: $error');
    } finally {
      if (temporaryFile?.existsSync() == true) {
        temporaryFile?.deleteSync();
      }
    }
  }

  /// 向 mpv 发送命令, 让其重新加载弹幕
  /// 不保证命令一定会成功
  static Future<bool> _reloadMpvDanmaku(
    ExternalPlayerSession session,
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
            'command': ['script-message', 'nipaplay-danmaku-reload'],
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

  static bool _isIpcOK(ExternalPlayerSession? current) {
    return current != null && current.ipcPath != null && current.ipcPath!.isNotEmpty;
  }


  @override
  void dispose() {
    _session?.removeListener(_handleSessionChanged);
    _session?.stopProcessPolling();
    super.dispose();
  }
}
