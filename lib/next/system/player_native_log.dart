import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/abstract_player.dart'
    show PlayerNativeLogTap;

import '../player/kernel/driver.dart' show KernelFenced;

import '../harness_redaction.dart';
import 'mdk_native_log.dart';

/// The last lines player kernels delivered to the app while Next is on, and
/// mpv's own full log file when asked for. Lines are kept as given and
/// redacted when read. MDK's own log, one for the process, comes through
/// [mdk] (instance 0); so does Erika's, a ring kept inside Erika that is
/// copied in through [pullEngineLog].
final class PlayerNativeLog {
  PlayerNativeLog({this.capacity = 1000, this.mdk});
  static final instance = PlayerNativeLog(mdk: MdkNativeLog.instance);

  final int capacity;
  final MdkNativeLog? mdk;
  final _lines = ListQueue<_Line>();
  int _sequence = 0;
  int _evicted = 0;
  bool _recording = false;
  File? _file;
  Future<void> Function(String path)? _fileWriter;

  /// Erika's ring: the next of its entries to copy, entries that left the
  /// ring before they were copied, and whether it captures FFmpeg's log.
  int? _erikaNextSeq;
  int _erikaMissed = 0;
  String? _erikaCapture;
  bool _erikaRead = false;
  Future<void> _engineWork = Future.value();

  bool get recording => _recording;
  File? get file => _file;

  void attach() {
    _recording = true;
    PlayerNativeLogTap.observer = add;
    PlayerNativeLogTap.engineLog = pullEngineLog;
    mdk?.attach((level, text) => add('mdk', 0, level, 'log', text));
  }

  /// Stops keeping lines, gives MDK's log handler back and has mpv stop
  /// writing its file.
  Future<void> detach() async {
    _recording = false;
    if (PlayerNativeLogTap.observer == add) PlayerNativeLogTap.observer = null;
    if (PlayerNativeLogTap.engineLog == pullEngineLog) {
      PlayerNativeLogTap.engineLog = null;
    }
    mdk?.detach();
    await stopFile();
  }

  void add(String kernel, int instance, String level, String source,
      String text, {DateTime? at, int repeated = 1}) {
    _lines.add(_Line(++_sequence, at ?? DateTime.now().toUtc(), kernel,
        instance, level, source, text, repeated));
    while (_lines.length > capacity) {
      _lines.removeFirst();
      _evicted++;
    }
  }

  /// Copies the entries a kernel's own log gained since the last copy;
  /// [read] returns them from a sequence on. Only Erika keeps such a log:
  /// its engine lines (source engine) and FFmpeg's warnings and errors
  /// (source ffmpeg), for the whole process (instance 0). Copies run one at
  /// a time.
  Future<void> pullEngineLog(String kernel,
      Future<Map<String, Object?>?> Function(int? sinceSeq) read) {
    if (!_recording || kernel != 'erika') return Future.value();
    final work = _engineWork.then((_) => _pullErika(read));
    _engineWork = work.catchError((Object _) {});
    return work;
  }

  Future<void> _pullErika(
      Future<Map<String, Object?>?> Function(int? sinceSeq) read) async {
    final export = await read(_erikaNextSeq);
    if (export == null || !_recording) return;
    _erikaRead = true;
    final since = _erikaNextSeq;
    final oldest = (export['oldestSeq'] as num?)?.toInt();
    if (since != null && oldest != null && oldest > since) {
      _erikaMissed += oldest - since;
    }
    for (final entry in (export['entries'] as List?) ?? const []) {
      if (entry is! Map) continue;
      final data = entry['data'];
      final text = entry['message'] as String? ??
          (data == null ? '' : jsonEncode(data));
      final unixMs = entry['unixMs'];
      add('erika', 0, '${entry['level'] ?? 'info'}',
          entry['source'] == 'ffmpeg' ? 'ffmpeg' : 'engine', text,
          at: unixMs is num
              ? DateTime.fromMillisecondsSinceEpoch(unixMs.toInt(), isUtc: true)
              : null,
          repeated: (entry['count'] as num?)?.toInt() ?? 1);
    }
    _erikaNextSeq = (export['nextSeq'] as num?)?.toInt() ?? since;
    _erikaCapture = export['ffmpegCapture'] as String? ?? _erikaCapture;
  }

  JsonMap read({
    int afterSequence = 0,
    List<String>? levels,
    String? contains,
    int limit = 200,
    int? currentInstance,
  }) {
    final selected = <JsonMap>[];
    var last = afterSequence;
    var more = false;
    for (final line in _lines) {
      if (line.sequence <= afterSequence) continue;
      if (levels != null && !levels.contains(line.level)) {
        last = line.sequence;
        continue;
      }
      final text = redactHarnessText(line.text.length > 4000
          ? '${line.text.substring(0, 4000)}[truncated]'
          : line.text);
      if (contains != null && !text.contains(contains)) {
        last = line.sequence;
        continue;
      }
      if (selected.length >= limit) {
        more = true;
        break;
      }
      selected.add({
        'sequence': line.sequence,
        'at': line.at.toIso8601String(),
        'kernel': line.kernel,
        // MDK's own log belongs to no one player.
        'currentPlayer': currentInstance == null || line.instance == 0
            ? null
            : line.instance == currentInstance,
        'level': line.level,
        'source': line.source,
        'text': text,
        if (line.repeated > 1) 'repeated': line.repeated,
      });
      last = line.sequence;
    }
    return {
      'recording': _recording,
      if (mdk != null)
        'mdkLog': {
          'reading': _recording && mdk!.notAttached == null,
          'reason': _recording ? mdk!.notAttached : null,
        },
      if (_erikaRead)
        'erikaLog': {
          'nextSeq': _erikaNextSeq,
          'missed': _erikaMissed,
          'ffmpegCapture': _erikaCapture,
        },
      'lines': selected,
      'nextSequence': last,
      'more': more,
      'oldestSequence': _lines.isEmpty ? null : _lines.first.sequence,
      'evicted': _evicted,
      'capacity': capacity,
    };
  }

  /// Has a kernel write its full log to a new file in [directory], through
  /// [write] (null: the kernel keeps no such log). Returns the file, or null
  /// when the kernel keeps none.
  Future<File?> startFile(
      Future<void> Function(String path)? write, Directory directory) async {
    await stopFile();
    if (write == null) return null;
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9T]'), '')
        .substring(0, 15);
    final file = File('${directory.path}/mpv-$stamp.log');
    await write(file.path);
    _fileWriter = write;
    return _file = file;
  }

  Future<void> stopFile() async {
    final write = _fileWriter;
    _fileWriter = null;
    try {
      if (write != null) await write('');
    } on KernelFenced {
      // The kernel it was writing for is gone, and its file with it.
    }
  }

  /// Lines of a log file this module started, from line [cursor], redacted.
  static Future<JsonMap> readFile(File file,
      {int cursor = 0, int limit = 200, String? contains}) async {
    if (!await file.exists()) {
      return {'path': file.path, 'exists': false, 'lines': <String>[],
        'nextCursor': null};
    }
    final lines = <String>[];
    var consumed = 0, characters = 0;
    var more = false;
    await for (final raw in file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())) {
      if (consumed < cursor) {
        consumed++;
        continue;
      }
      if (lines.length >= limit || characters >= 256 * 1024) {
        more = true;
        break;
      }
      consumed++;
      final line = redactHarnessText(raw);
      if (contains != null && !line.contains(contains)) continue;
      lines.add(line);
      characters += line.length;
    }
    return {
      'path': file.path,
      'exists': true,
      'bytes': await file.length(),
      'lines': lines,
      'nextCursor': more ? consumed : null,
      'endCursor': consumed,
    };
  }
}

final class _Line {
  _Line(this.sequence, this.at, this.kernel, this.instance, this.level,
      this.source, this.text, this.repeated);
  final int sequence;
  final DateTime at;
  final String kernel;
  final int instance;
  final String level;
  final String source;
  final String text;
  final int repeated;
}
