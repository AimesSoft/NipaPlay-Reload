import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

import '../harness_redaction.dart';
import 'mdk_native_log.dart';

/// The last lines player kernels delivered to the app while Next is on, and
/// mpv's own full log file when asked for. Lines are kept as given and
/// redacted when read. MDK's own log, one for the process, comes through
/// [mdk] (instance 0).
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
  Player? _filePlayer;

  bool get recording => _recording;
  File? get file => _file;

  void attach() {
    _recording = true;
    PlayerNativeLogTap.observer = add;
    mdk?.attach((level, text) => add('mdk', 0, level, 'log', text));
  }

  /// Stops keeping lines, gives MDK's log handler back and has mpv stop
  /// writing its file.
  Future<void> detach() async {
    _recording = false;
    if (PlayerNativeLogTap.observer == add) PlayerNativeLogTap.observer = null;
    mdk?.detach();
    await stopFile();
  }

  void add(String kernel, int instance, String level, String source,
      String text) {
    _lines.add(_Line(++_sequence, DateTime.now().toUtc(), kernel, instance,
        level, source, text));
    while (_lines.length > capacity) {
      _lines.removeFirst();
      _evicted++;
    }
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
      'lines': selected,
      'nextSequence': last,
      'more': more,
      'oldestSequence': _lines.isEmpty ? null : _lines.first.sequence,
      'evicted': _evicted,
      'capacity': capacity,
    };
  }

  /// Has [player]'s kernel write its full log to a new file in [directory].
  /// Returns the file, or null when the kernel keeps no such log.
  Future<File?> startFile(Player player, Directory directory) async {
    await stopFile();
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9T]'), '')
        .substring(0, 15);
    final file = File('${directory.path}/mpv-$stamp.log');
    if (!await player.setNativeLogFile(file.path)) return null;
    _filePlayer = player;
    return _file = file;
  }

  Future<void> stopFile() async {
    final player = _filePlayer;
    _filePlayer = null;
    if (player != null) await player.setNativeLogFile('');
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
      this.source, this.text);
  final int sequence;
  final DateTime at;
  final String kernel;
  final int instance;
  final String level;
  final String source;
  final String text;
}
