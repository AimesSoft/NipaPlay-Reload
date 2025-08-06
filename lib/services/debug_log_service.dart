import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 日志条目模型
class LogEntry {
  final DateTime timestamp;
  final String message;
  final String level;
  final String tag;

  LogEntry({
    required this.timestamp,
    required this.message,
    this.level = 'DEBUG',
    this.tag = 'App',
  });

  @override
  String toString() {
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '[$timeStr] [$level] [$tag] $message';
  }

  /// 格式化为适合复制的文本
  String toFormattedString() {
    final dateStr = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '$dateStr $timeStr [$level] [$tag] $message';
  }
}

/// 调试日志服务
/// 提供统一的日志收集、存储和查看功能
class DebugLogService extends ChangeNotifier {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  /// 日志条目队列，限制最大数量避免内存溢出
  static const int _maxLogEntries = 5000;
  final Queue<LogEntry> _logEntries = Queue<LogEntry>();

  /// 获取所有日志条目
  List<LogEntry> get logEntries => _logEntries.toList();

  /// 获取日志条目数量
  int get logCount => _logEntries.length;

  /// 是否正在收集日志
  bool _isCollecting = true;
  bool get isCollecting => _isCollecting;

  /// 原始的debugPrint函数引用
  void Function(String? message, {int? wrapWidth})? _originalDebugPrint;

  /// 初始化日志服务
  void initialize() {
    if (!_isCollecting) return;

    // 保存原始的debugPrint函数
    _originalDebugPrint = debugPrint;

    // 替换debugPrint函数
    debugPrint = _interceptDebugPrint;

    // 添加启动日志
    _addLogEntry(LogEntry(
      timestamp: DateTime.now(),
      message: 'DebugLogService 已启动，开始收集日志',
      level: 'INFO',
      tag: 'LogService',
    ));
  }

  /// 拦截debugPrint调用
  void _interceptDebugPrint(String? message, {int? wrapWidth}) {
    // 调用原始的debugPrint
    _originalDebugPrint?.call(message, wrapWidth: wrapWidth);

    // 收集日志
    if (_isCollecting && message != null) {
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        message: message,
        level: 'DEBUG',
        tag: _extractTag(message),
      ));
    }
  }

  /// 从消息中提取标签
  String _extractTag(String message) {
    // 尝试从消息中提取标签，如[VideoPlayer]、[Network]等
    final tagMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(message);
    if (tagMatch != null) {
      return tagMatch.group(1) ?? 'App';
    }

    // 根据消息内容推断标签
    if (message.contains('网络') || message.contains('HTTP') || message.contains('API')) {
      return 'Network';
    } else if (message.contains('播放') || message.contains('视频') || message.contains('音频')) {
      return 'Player';
    } else if (message.contains('数据库') || message.contains('存储')) {
      return 'Database';
    } else if (message.contains('弹幕')) {
      return 'Danmaku';
    } else if (message.contains('设置') || message.contains('配置')) {
      return 'Settings';
    }

    return 'App';
  }

  /// 添加日志条目
  void _addLogEntry(LogEntry entry) {
    _logEntries.add(entry);

    // 限制日志数量，移除最旧的条目
    while (_logEntries.length > _maxLogEntries) {
      _logEntries.removeFirst();
    }

    // 延迟通知监听器，避免在构建阶段调用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCollecting) {
        notifyListeners();
      }
    });
  }

  /// 手动添加日志
  void addLog(String message, {String level = 'INFO', String tag = 'App'}) {
    if (_isCollecting) {
      _addLogEntry(LogEntry(
        timestamp: DateTime.now(),
        message: message,
        level: level,
        tag: tag,
      ));
    }
  }

  /// 添加错误日志
  void addError(String message, {String tag = 'Error'}) {
    addLog(message, level: 'ERROR', tag: tag);
  }

  /// 添加警告日志
  void addWarning(String message, {String tag = 'Warning'}) {
    addLog(message, level: 'WARN', tag: tag);
  }

  /// 开始收集日志
  void startCollecting() {
    if (!_isCollecting) {
      _isCollecting = true;
      initialize();
      addLog('日志收集已启动', level: 'INFO', tag: 'LogService');
    }
  }

  /// 停止收集日志
  void stopCollecting() {
    if (_isCollecting) {
      addLog('日志收集即将停止', level: 'INFO', tag: 'LogService');
      _isCollecting = false;
      
      // 恢复原始的debugPrint
      if (_originalDebugPrint != null) {
        debugPrint = _originalDebugPrint!;
      }
    }
  }

  /// 清空所有日志
  void clearLogs() {
    _logEntries.clear();
    addLog('日志已清空', level: 'INFO', tag: 'LogService');
    // 移除直接调用 notifyListeners()，因为 addLog 中的 _addLogEntry 已经处理了
  }

  /// 根据标签过滤日志
  List<LogEntry> getLogsByTag(String tag) {
    return _logEntries.where((entry) => entry.tag == tag).toList();
  }

  /// 根据级别过滤日志
  List<LogEntry> getLogsByLevel(String level) {
    return _logEntries.where((entry) => entry.level == level).toList();
  }

  /// 获取最近的日志
  List<LogEntry> getRecentLogs(int count) {
    final entries = _logEntries.toList();
    if (entries.length <= count) return entries;
    return entries.sublist(entries.length - count);
  }

  /// 导出日志为文本
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('============ NipaPlay 调试日志 ============');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('日志条目数: ${_logEntries.length}');
    buffer.writeln('系统信息: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('');

    for (final entry in _logEntries) {
      buffer.writeln(entry.toFormattedString());
    }

    buffer.writeln('');
    buffer.writeln('============ 日志导出结束 ============');
    return buffer.toString();
  }

  /// 获取日志统计信息
  Map<String, int> getLogStatistics() {
    final stats = <String, int>{};
    
    // 按级别统计
    for (final entry in _logEntries) {
      final levelKey = 'level_${entry.level}';
      stats[levelKey] = (stats[levelKey] ?? 0) + 1;
    }

    // 按标签统计
    for (final entry in _logEntries) {
      final tagKey = 'tag_${entry.tag}';
      stats[tagKey] = (stats[tagKey] ?? 0) + 1;
    }

    stats['total'] = _logEntries.length;
    return stats;
  }

  /// 释放资源
  void dispose() {
    stopCollecting();
    _logEntries.clear();
    super.dispose();
  }
} 