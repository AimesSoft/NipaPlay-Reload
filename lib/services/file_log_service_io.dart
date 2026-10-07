import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

class FileLogService {
  FileLogService._internal() : _logService = DebugLogService();

  @visibleForTesting
  FileLogService.forTesting(DebugLogService logService, Directory directory)
      : _logService = logService,
        _logDirectory = directory,
        _initialized = true;

  final DebugLogService _logService;

  static final FileLogService _instance = FileLogService._internal();

  factory FileLogService() => _instance;

  static const int _maxLogFiles = 5;
  static const Duration _flushInterval = Duration(seconds: 1);

  bool _initialized = false;
  bool _isRunning = false;
  Future<void>? _activeFlush;
  Future<void> _lifecycle = Future.value();
  StreamSubscription<LogEntry>? _subscription;
  Queue<LogEntry> _pending = Queue();
  static const int _maxPendingEntries = 5000;
  int _droppedEntries = 0;
  Timer? _timer;
  Directory? _logDirectory;
  File? _currentLogFile;

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

  Future<void> _enqueueLifecycle(Future<void> Function() action) {
    final operation = _lifecycle.then((_) => action(),
        onError: (Object _, StackTrace __) => action());
    _lifecycle = operation;
    return operation;
  }

  Future<void> start() => _enqueueLifecycle(_start);

  Future<void> _start() async {
    if (_isRunning) return;
    await initialize();
    if (_logDirectory == null) return;
    await _prepareCurrentLogFile();
    _isRunning = true;
    // Snapshot once, then consume only newly appended entries.
    _pending = Queue.of(_logService.logEntries);
    _subscription = _logService.entries.listen((entry) {
      _pending.add(entry);
      _boundPending();
      _scheduleFlush();
    });
    await _flushLogs();
    _scheduleFlush();
  }

  void _boundPending() {
    final excess = _pending.length - _maxPendingEntries;
    if (excess <= 0) return;
    for (var i = 0; i < excess; i++) {
      _pending.removeFirst();
    }
    _droppedEntries += excess;
  }

  void _scheduleFlush() {
    if (!_isRunning || _timer != null || _pending.isEmpty) return;
    _timer = Timer(_flushInterval, () async {
      _timer = null;
      await _flushLogs();
      _scheduleFlush();
    });
  }

  Future<void> stop() => _enqueueLifecycle(_stop);

  Future<void> _stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    await _activeFlush;
    await _flushLogs();
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
    _droppedEntries = 0;
    await _cleanupOldLogs();
  }

  Future<void> _flushLogs() async {
    if (_activeFlush != null) return _activeFlush;
    if (_currentLogFile == null || _pending.isEmpty) return;
    final batch = _pending;
    _pending = Queue();
    final dropped = _droppedEntries;
    _droppedEntries = 0;
    final flush = _writeBatch(batch, dropped);
    _activeFlush = flush;
    try {
      await flush;
    } finally {
      _activeFlush = null;
    }
  }

  Future<void> _writeBatch(Queue<LogEntry> batch, int dropped) async {
    try {
      final buffer = StringBuffer();
      if (dropped > 0) {
        buffer.writeln('[FileLogService] 待写队列溢出，丢弃 $dropped 条旧日志');
      }
      for (final entry in batch) {
        buffer.writeln(entry.toFormattedString());
      }
      await _currentLogFile!.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      _pending = Queue.of([...batch, ..._pending]);
      _droppedEntries += dropped;
      _boundPending();
      // Do not feed a disk failure back into the queue being retried.
      debugPrintSynchronously('[FileLogService] 写入日志失败: $e');
    }
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
