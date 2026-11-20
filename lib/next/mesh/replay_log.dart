import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

enum ReplayAdmission { accepted, duplicate, full }

/// Serializes admissions with the durable log. Only a successful append may
/// admit a request; a failed append is repaired before another can begin.
final class MeshReplayLog {
  MeshReplayLog(this.file, {int Function()? now, this.compactAfter = 1024})
      : _now = now ?? _wallTime;

  final File file;
  final int Function() _now;
  final int compactAfter;
  static const capacity = 20000;
  static int _wallTime() => DateTime.now().millisecondsSinceEpoch;
  final _keys = <String, int>{};
  Future<void> _writes = Future.value();
  bool _loaded = false;
  int _appended = 0;

  int get retainedKeys => _keys.length;
  Future<void> get idle => _writes;

  Future<void> load() async {
    if (_loaded) return;
    final path = file.path;
    final now = _now();
    final keys = await Isolate.run(() => _load(path, now));
    _keys
      ..clear()
      ..addAll(keys);
    await _compact();
    _loaded = true;
  }

  Future<ReplayAdmission> admit(List<String> keys, int deadline) {
    final write = _writes.then((_) async {
      final now = _now();
      _keys.removeWhere((_, expiry) => expiry <= now);
      if (keys.any(_keys.containsKey)) return ReplayAdmission.duplicate;
      if (_keys.length + keys.length > capacity) return ReplayAdmission.full;
      if (_appended >= compactAfter) await _compact();
      try {
        await file.writeAsString('${_record(keys, deadline)}\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        _appended = compactAfter;
        rethrow;
      }
      for (final key in keys) {
        _keys[key] = deadline;
      }
      _appended++;
      return ReplayAdmission.accepted;
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }

  Future<void> _compact() async {
    final path = file.path;
    final entries = Map<String, int>.of(_keys);
    await Isolate.run(() async {
      final temp = File('$path.tmp');
      final body = StringBuffer();
      for (final entry in entries.entries) {
        body.writeln(_record([entry.key], entry.value));
      }
      await temp.writeAsString(body.toString(), flush: true);
      await temp.rename(path);
    });
    _appended = 0;
  }

  static String _record(List<String> keys, int deadline) =>
      jsonEncode({'keys': keys, 'deadline': deadline});

  static Future<Map<String, int>> _load(String path, int now) async {
    final file = File(path);
    final keys = <String, int>{};
    if (!await file.exists()) return keys;
    final line = <int>[];
    void readRecord() {
      final text = utf8.decode(line).trim();
      if (text.isEmpty) return;
      final record = jsonDecode(text);
      if (record is! Map ||
          record['deadline'] is! int ||
          record['keys'] is! List ||
          !(record['keys'] as List).every((key) => key is String)) {
        throw const FormatException('Invalid Mesh replay record.');
      }
      final deadline = record['deadline'] as int;
      if (deadline <= now) return;
      for (final key in (record['keys'] as List).cast<String>()) {
        keys[key] = deadline;
      }
    }

    await for (final bytes in file.openRead()) {
      for (final byte in bytes) {
        if (byte == 10) {
          readRecord();
          line.clear();
        } else {
          line.add(byte);
        }
      }
    }
    if (line.isNotEmpty) {
      try {
        readRecord();
      } on FormatException {
        return keys;
      }
    }
    return keys;
  }
}
