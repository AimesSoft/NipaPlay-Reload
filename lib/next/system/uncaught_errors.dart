import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../harness_redaction.dart';

/// Uncaught errors of this process and runs that ended outside NipaPlay's
/// exit path, recorded only while Next is on. Each handler it wraps keeps
/// running as before.
final class UncaughtErrors {
  UncaughtErrors(this.directory, {this.appVersion});

  final Directory directory;
  final String? appVersion;

  /// What was playing, for the record of an error.
  JsonMap? Function()? context;

  static const _keptRecords = 300;
  static const _updateEvery = Duration(seconds: 10);
  final DateTime startedAt = DateTime.now().toUtc();
  final _open = <String, JsonMap>{};
  final _persistedAt = <String, DateTime>{};
  final _persistedCount = <String, Object?>{};
  bool _attached = false;
  bool _checkedPrevious = false;
  JsonMap? _lastPlayback;
  FlutterExceptionHandler? _flutterBefore;
  ErrorCallback? _dispatcherBefore;
  RawReceivePort? _isolatePort;
  Future<void> _writes = Future.value();
  int _sequence = 0;

  bool get recording => _attached;
  File get _records => File('${directory.path}/errors.jsonl');
  File get _session => File('${directory.path}/session.json');

  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    try {
      await directory.create(recursive: true);
      if (!_checkedPrevious) {
        _checkedPrevious = true;
        await _checkPrevious();
        await _compact();
      }
    } catch (_) {}
    _writeSession('running');
    _flutterBefore = FlutterError.onError;
    FlutterError.onError = _onFlutterError;
    _dispatcherBefore = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _onPlatformError;
    final port = _isolatePort = RawReceivePort(_onIsolateError);
    Isolate.current.addErrorListener(port.sendPort);
  }

  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    if (FlutterError.onError == _onFlutterError) {
      FlutterError.onError = _flutterBefore;
    }
    if (PlatformDispatcher.instance.onError == _onPlatformError) {
      PlatformDispatcher.instance.onError = _dispatcherBefore;
    }
    final port = _isolatePort;
    _isolatePort = null;
    if (port != null) {
      Isolate.current.removeErrorListener(port.sendPort);
      port.close();
    }
    _flushCounts();
    _writeSession('untracked');
    await _writes;
  }

  /// The app is leaving through NipaPlay's exit path.
  Future<void> exiting() async {
    if (!_attached) return;
    _flushCounts();
    _writeSession('exited');
    await _writes;
  }

  /// What plays now, kept so a run that ends abruptly says what it played.
  void notePlayback(JsonMap playback) {
    _lastPlayback = playback;
    if (_attached) _writeSession('running');
  }

  void _onFlutterError(FlutterErrorDetails details) {
    record('flutter', details.exception, details.stack,
        library: details.library,
        detail: details.context?.toDescription());
    _flutterBefore?.call(details);
  }

  bool _onPlatformError(Object error, StackTrace stack) {
    record('platform_dispatcher', error, stack);
    return _dispatcherBefore?.call(error, stack) ?? false;
  }

  void _onIsolateError(dynamic message) {
    final pair = message is List ? message : [message, null];
    final stack = pair.length > 1 ? pair[1] : null;
    record('isolate', pair.first,
        stack is String ? StackTrace.fromString(stack) : null);
  }

  /// Records one uncaught error. The same error again counts on the same
  /// record; the same error from a second channel within two seconds is one
  /// occurrence.
  JsonMap record(String channel, Object? error, StackTrace? stack,
      {String? library, String? detail}) {
    final now = DateTime.now().toUtc();
    final message = _clip(redactHarnessText('$error'), 4000);
    final frames = [
      for (final line in '${stack ?? ''}'.split('\n'))
        if (line.trim().isNotEmpty) _clip(redactHarnessText(line.trim()), 300)
    ].take(16).toList();
    final fingerprint =
        '${_clip(message, 300)}|${frames.isEmpty ? '' : frames.first}';
    final open = _open[fingerprint];
    if (open != null) {
      final channels = open['channels'] as List;
      final last = DateTime.parse(open['lastAt'] as String);
      if (!channels.contains(channel) &&
          now.difference(last) < const Duration(seconds: 2)) {
        channels.add(channel);
      } else {
        open['count'] = (open['count'] as int) + 1;
      }
      open['lastAt'] = now.toIso8601String();
      final persisted = _persistedAt[open['id']];
      if (persisted == null || now.difference(persisted) >= _updateEvery) {
        _append(open);
      }
      return open;
    }
    final created = <String, Object?>{
      'id': 'err-${now.microsecondsSinceEpoch}-${++_sequence}',
      'kind': 'uncaught_error',
      'channels': [channel],
      'type': error?.runtimeType.toString(),
      'message': message,
      'stack': frames,
      'library': library,
      'context': detail == null ? null : _clip(redactHarnessText(detail), 500),
      'firstAt': now.toIso8601String(),
      'lastAt': now.toIso8601String(),
      'count': 1,
      'processId': pid,
      'appVersion': appVersion,
      'playback': _safeContext(),
    };
    _open[fingerprint] = created;
    if (_open.length > 200) _open.remove(_open.keys.first);
    _append(created);
    return created;
  }

  JsonMap? _safeContext() {
    try {
      return context?.call();
    } catch (_) {
      return null;
    }
  }

  /// Records, newest first: this file's history merged with this run's
  /// counts.
  Future<JsonMap> read({int limit = 50, String? kind}) async {
    await _writes;
    final merged = await _load();
    for (final open in _open.values) {
      merged[open['id'] as String] = open;
    }
    final records = merged.values
        .where((r) => kind == null || r['kind'] == kind)
        .toList()
      ..sort((a, b) =>
          (b['lastAt'] as String? ?? '').compareTo(a['lastAt'] as String? ?? ''));
    return {
      'recording': _attached,
      'session': {
        'startedAt': startedAt.toIso8601String(),
        'processId': pid,
      },
      'records': records.take(limit).toList(),
      'total': records.length,
    };
  }

  Future<Map<String, JsonMap>> _load() async {
    final merged = <String, JsonMap>{};
    try {
      if (!await _records.exists()) return merged;
      for (final line in await _records.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final record = Map<String, Object?>.from(jsonDecode(line) as Map);
          merged[record['id'] as String] = record;
        } catch (_) {}
      }
    } catch (_) {}
    return merged;
  }

  Future<void> _checkPrevious() async {
    if (!await _session.exists()) return;
    JsonMap previous;
    try {
      previous =
          Map<String, Object?>.from(jsonDecode(await _session.readAsString()) as Map);
    } catch (_) {
      return;
    }
    if (previous['state'] != 'running') return;
    final now = DateTime.now().toUtc();
    _append({
      'id': 'exit-${now.microsecondsSinceEpoch}',
      'kind': 'unclean_exit',
      'firstAt': previous['startedAt'],
      'lastAt': previous['updatedAt'] ?? previous['startedAt'],
      'detectedAt': now.toIso8601String(),
      'processId': previous['processId'],
      'appVersion': previous['appVersion'],
      'playback': previous['lastPlayback'],
    });
  }

  /// Keeps the file to its last records.
  Future<void> _compact() async {
    if (!await _records.exists() || await _records.length() < 1024 * 1024) {
      return;
    }
    final merged = (await _load()).values.toList()
      ..sort((a, b) =>
          (a['lastAt'] as String? ?? '').compareTo(b['lastAt'] as String? ?? ''));
    final kept = merged.skip(merged.length > _keptRecords
        ? merged.length - _keptRecords
        : 0);
    await _records.writeAsString(
        kept.map((r) => '${jsonEncode(r)}\n').join(),
        flush: true);
  }

  /// Writes the counts that grew since their record was last written.
  void _flushCounts() {
    for (final open in _open.values) {
      if (_persistedCount[open['id']] != open['count']) _append(open);
    }
  }

  void _append(JsonMap record) {
    _persistedAt[record['id'] as String] = DateTime.now().toUtc();
    _persistedCount[record['id'] as String] = record['count'];
    final line = '${jsonEncode(record)}\n';
    _writes = _writes.then((_) async {
      try {
        await _records.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {}
    });
  }

  void _writeSession(String state) {
    final text = jsonEncode({
      'state': state,
      'processId': pid,
      'startedAt': startedAt.toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': appVersion,
      'lastPlayback': _lastPlayback,
    });
    _writes = _writes.then((_) async {
      try {
        await _session.writeAsString(text, flush: true);
      } catch (_) {}
    });
  }

  static String _clip(String text, int max) =>
      text.length > max ? '${text.substring(0, max)}[truncated]' : text;
}
