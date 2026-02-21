import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

class FileLogService {
  FileLogService._internal();

  static final FileLogService _instance = FileLogService._internal();

  factory FileLogService() => _instance;

  static const int _maxLogFiles = 5;
  static const Duration _flushInterval = Duration(seconds: 1);

  bool _initialized = false;
  bool _isRunning = false;
  bool _isFlushing = false;
  Timer? _timer;
  Directory? _logDirectory;
  File? _currentLogFile;
  String? _lastWrittenKey;
  int? _lastWrittenTimestampMs;

  bool get isRunning => _isRunning;

  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      _logDirectory = await _resolveLogDirectory();
      await _cleanupOldLogs();
      _initialized = true;
    } catch (e) {
      debugPrint('[FileLogService] 初始化失败: $e');
    }
  }

  Future<void> start() async {
    if (_isRunning) return;
    await initialize();
    if (_logDirectory == null) return;

    await _prepareCurrentLogFile();
    _isRunning = true;
    _timer = Timer.periodic(_flushInterval, (_) {
      _flushLogs();
    });
    await _flushLogs(force: true);
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    await _flushLogs(force: true);
  }

  Future<String?> getLogDirectoryPath() async {
    if (_logDirectory != null) return _logDirectory!.path;
    await initialize();
    return _logDirectory?.path;
  }

  Future<bool> openLogDirectory() async {
    final dirPath = await getLogDirectoryPath();
    if (dirPath == null || dirPath.isEmpty) return false;

    try {
      final uri = Uri.file(dirPath);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[FileLogService] 打开日志目录失败: $e');
      return false;
    }
  }

  Future<Directory?> _resolveLogDirectory() async {
    final appDir = await StorageService.getAppStorageDirectory();
    final logDir = Directory(path.join(appDir.path, 'logs'));
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    return logDir;
  }

  Future<void> _prepareCurrentLogFile() async {
    if (_logDirectory == null) return;
    final filename = '${DateTime.now().millisecondsSinceEpoch}.txt';
    final logFile = File(path.join(_logDirectory!.path, filename));
    if (!await logFile.exists()) {
      await logFile.create(recursive: true);
    }
    _currentLogFile = logFile;
    _lastWrittenKey = null;
    _lastWrittenTimestampMs = null;
    await _cleanupOldLogs();
  }

  Future<void> _flushLogs({bool force = false}) async {
    if ((!_isRunning && !force) || _isFlushing || _currentLogFile == null) {
      return;
    }

    _isFlushing = true;
    try {
      final entries = DebugLogService().logEntries;
      if (entries.isEmpty) return;

      int startIndex = 0;
      if (_lastWrittenKey != null) {
        final lastIndex = entries.lastIndexWhere(
          (entry) => _entryKey(entry) == _lastWrittenKey,
        );
        if (lastIndex >= 0) {
          startIndex = lastIndex + 1;
        } else if (_lastWrittenTimestampMs != null) {
          final newerIndex = entries.indexWhere(
            (entry) =>
                entry.timestamp.millisecondsSinceEpoch >
                _lastWrittenTimestampMs!,
          );
          if (newerIndex < 0) return;
          startIndex = newerIndex;
        }
      }

      if (startIndex >= entries.length) return;

      final buffer = StringBuffer();
      for (var i = startIndex; i < entries.length; i++) {
        buffer.writeln(entries[i].toFormattedString());
      }

      if (buffer.isEmpty) return;

      await _currentLogFile!.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
      final lastEntry = entries.last;
      _lastWrittenKey = _entryKey(lastEntry);
      _lastWrittenTimestampMs = lastEntry.timestamp.millisecondsSinceEpoch;
    } catch (e) {
      debugPrint('[FileLogService] 写入日志失败: $e');
    } finally {
      _isFlushing = false;
    }
  }

  String _entryKey(LogEntry entry) {
    return '${entry.timestamp.millisecondsSinceEpoch}|${entry.level}|${entry.tag}|${entry.message}';
  }

  Future<void> _cleanupOldLogs() async {
    if (_logDirectory == null) return;

    final entities = await _logDirectory!.list().toList();
    final logFiles = <_LogFileInfo>[];

    for (final entity in entities) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.txt')) continue;
      final fileName = path.basenameWithoutExtension(entity.path);
      final parsedTimestamp = int.tryParse(fileName);
      final stat = await entity.stat();
      final sortKey = parsedTimestamp ?? stat.modified.millisecondsSinceEpoch;
      logFiles.add(_LogFileInfo(entity, sortKey));
    }

    if (logFiles.length <= _maxLogFiles) return;

    logFiles.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    final deleteCount = logFiles.length - _maxLogFiles;

    for (var i = 0; i < deleteCount; i++) {
      try {
        await logFiles[i].file.delete();
      } catch (e) {
        debugPrint('[FileLogService] 删除旧日志失败: $e');
      }
    }
  }
}

class _LogFileInfo {
  _LogFileInfo(this.file, this.sortKey);

  final File file;
  final int sortKey;
}
