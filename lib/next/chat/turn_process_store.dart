import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../harness_redaction.dart';

/// Bounded, redacted execution facts, separate from Codex's transcript.
///
/// One directory per harness, one file per turn, named in the order the
/// turns began. A turn's file is JSON lines: the first is the turn, each
/// further line a change to it, an item as it now is (`item`) or fields of
/// the turn (`turn`). Read back, an item's last line wins, in the order the
/// items first came. A finished turn's file is rewritten to one line per item.
///
/// The main isolate encodes only the line that changed and keeps a small
/// index of the kept turns. Files are appended one write at a time; reading,
/// folding and rewriting them run on other isolates.
final class TurnProcessStore {
  /// What the store keeps itself; Codex's history keeps the rest.
  static const _process = {
    'commandExecution',
    'reasoning',
    'collabAgentToolCall',
  };

  /// Items kept per turn; past them the turn is marked truncated.
  static const maxItems = 128;

  static String _harnessKey(String harnessPath) =>
      '${sha256.convert(utf8.encode(harnessPath))}';

  /// The single file earlier versions kept for a harness; its turns move
  /// into [directoryFor] the first time the store opens.
  static File fileFor(Directory root, String harnessPath) =>
      File('${root.path}/turn-process/${_harnessKey(harnessPath)}.json');

  static Directory directoryFor(Directory root, String harnessPath) =>
      Directory('${root.path}/turn-process/${_harnessKey(harnessPath)}');

  /// Opens on another isolate: moves the turns of [legacy] in, once, and
  /// reads the index. What is observed meanwhile is applied once it is open.
  TurnProcessStore(this.directory,
      {this.legacy, this.maxTurns = 60, this.maxBytes = 4 * 1024 * 1024}) {
    _tail = _open();
  }

  /// The store of the harness at [harnessPath], under the Next data [root].
  TurnProcessStore.forHarness(Directory root, String harnessPath,
      {int maxTurns = 60, int maxBytes = 4 * 1024 * 1024})
      : this(directoryFor(root, harnessPath),
            legacy: fileFor(root, harnessPath),
            maxTurns: maxTurns,
            maxBytes: maxBytes);

  final Directory directory;
  final File? legacy;
  final int maxTurns, maxBytes;

  /// The kept turns, oldest first.
  final _turns = <_Turn>[];
  final _byKey = <String, _Turn>{};
  static String _keyOf(String threadId, String turnId) =>
      '$threadId\u0000$turnId';

  /// Bytes of the kept turns, written and waiting.
  int _total = 0;
  int _nextSeq = 0;
  bool _ready = false, _unusable = false;
  final _early = <(Map<String, dynamic>, String, DateTime)>[];
  final _deletions = <int>[];

  /// Writes, reads and the opening run one at a time, in this order.
  late Future<void> _tail;
  bool _writeQueued = false;

  /// Why the latest state is not on disk; the next change writes it all.
  Object? _failure;

  /// Bytes handed to files since this store opened, for tests of the cost.
  int get bytesWritten => _written;
  int _written = 0;

  File _fileOf(int seq) => File('${directory.path}/$seq.jsonl');

  Future<void> _open() async {
    try {
      final (kept, top) =
          await _loadIn(directory.path, legacy?.path, maxTurns, maxBytes);
      for (final turn in kept) {
        _turns.add(turn);
        _byKey[_keyOf(turn.threadId, turn.turnId)] = turn;
        _total += turn.bytes;
      }
      _nextSeq = top + 1;
    } catch (error) {
      // Nothing is written over files that could not be listed.
      _unusable = true;
      _failure = error is FileSystemException
          ? error
          : FileSystemException('$error', directory.path);
    }
    _ready = true;
    final early = List.of(_early);
    _early.clear();
    for (final (message, origin, now) in early) {
      observe(message, origin, now);
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace _) {
      // The caller receives the error; the next operation still runs.
    });
    return result;
  }

  /// The saved process of a turn, or null; read and folded off the main
  /// isolate.
  Future<Map<String, dynamic>?> read(String threadId, String turnId) async =>
      (await _read(threadId, [turnId]))[turnId];

  /// Puts the saved process back into Codex's [turn]; see [restoreAll].
  Future<void> restore(String threadId, Map turn) =>
      restoreAll(threadId, [turn]);

  /// Puts the saved process back into each of Codex's [turns], in the order
  /// it happened: saved markers stand for Codex's own items (messages,
  /// tools), matched by type in order. All the turns are read and decoded
  /// together, off the main isolate.
  Future<void> restoreAll(String threadId, Iterable<Map> turns) async {
    final list = turns.toList();
    if (list.isEmpty) return;
    final saved =
        await _read(threadId, [for (final turn in list) turn['id'] as String]);
    for (final turn in list) {
      if (saved[turn['id']] case final process?) _merge(turn, process);
    }
  }

  Future<Map<String, Map<String, dynamic>>> _read(
          String threadId, List<String> turnIds) =>
      _enqueue<Map<String, Map<String, dynamic>>>(() async {
        if (_unusable) return {};
        final found = [
          for (final id in turnIds)
            if (_byKey[_keyOf(threadId, id)] case final turn?) turn
        ];
        if (found.isEmpty) return {};
        final folded = await _foldIn([
          for (final turn in found) _fileOf(turn.seq).path
        ], [
          for (final turn in found) turn.disk
        ], [
          for (final turn in found) _joined(turn.waiting)
        ]);
        return {
          for (var i = 0; i < found.length; i++)
            if (folded[i] case final turn?) found[i].turnId: turn
        };
      });

  static void _merge(Map turn, Map<String, dynamic> saved) {
    bool own(Object? item) => item is Map && !_process.contains(item['type']);
    final codex = [
      for (final item in turn['items'] as List)
        if (own(item)) item as Map
    ];
    final process = saved['items'] as List;
    if (!process.any((v) => v is Map && v['marker'] == true)) {
      turn['items'] = [...codex, ...process];
    } else {
      final byType = <Object?, List<Map>>{};
      for (final item in codex) {
        (byType[item['type']] ??= []).add(item);
      }
      final used = <Object?, int>{};
      final merged = <Object?>[];
      for (final v in process.cast<Map>()) {
        if (v['marker'] != true) {
          merged.add(v);
          continue;
        }
        final list = byType[v['type']] ?? const [];
        final i = used[v['type']] ?? 0;
        if (i < list.length) {
          merged.add(list[i]);
          used[v['type']] = i + 1;
        }
      }
      final seen = <Object?, int>{};
      for (final item in codex) {
        final i = seen[item['type']] ?? 0;
        seen[item['type']] = i + 1;
        if (i >= (used[item['type']] ?? 0)) merged.add(item);
      }
      turn['items'] = merged;
    }
    if (turn['durationMs'] == null && saved['durationMs'] != null) {
      turn['durationMs'] = saved['durationMs'];
    }
  }

  /// Costs the size of the item that changed, not of its turn.
  void observe(Map<String, dynamic> message, String origin, DateTime now) {
    if (!_ready) {
      _early.add((message, origin, now));
      return;
    }
    if (_unusable) return;
    final method = message['method'];
    final params = message['params'];
    if (params is! Map) return;
    final thread = params['threadId'];
    final id = method == 'turn/started' || method == 'turn/completed'
        ? params['turn']['id']
        : params['turnId'];
    if (thread is! String || id is! String) return;
    final turn = _byKey[_keyOf(thread, id)];
    if (method == 'turn/started') {
      if (turn != null) return;
      final startedAt = now.toUtc().toIso8601String();
      final started = _Turn(_nextSeq++, thread, id, startedAt)..items = {};
      _turns.add(started);
      _byKey[_keyOf(thread, id)] = started;
      _append(started, {
        'threadId': thread,
        'turnId': id,
        'origin': origin,
        'startedAt': startedAt,
        'status': 'inProgress',
      });
      return;
    }
    if (turn == null) return;
    if (method == 'turn/completed') {
      turn.finished = true;
      _append(turn, {
        'turn': {
          'status': params['turn']['status'],
          'endedAt': now.toUtc().toIso8601String(),
          'durationMs':
              now.difference(DateTime.parse(turn.startedAt)).inMilliseconds,
        }
      });
      return;
    }
    if (method != 'item/started' && method != 'item/completed') return;
    final item = params['item'] as Map;
    final items = turn.items ??= {};
    final known = items.containsKey(item['id']);
    if (!_process.contains(item['type'])) {
      // Where Codex's own item came, without its content.
      if (known || items.length >= maxItems) return;
      items[item['id']] = null;
      _append(turn, {
        'item': {'id': item['id'], 'type': item['type'], 'marker': true}
      });
      return;
    }
    if (!known && items.length >= maxItems) {
      if (!turn.truncated) {
        turn.truncated = true;
        _append(turn, {
          'turn': {'truncated': true}
        });
      }
      return;
    }
    final previous = items[item['id']];
    var cut = false;
    String clip(Object? value, int limit) {
      final raw = value is List ? value.join(' ') : '${value ?? ''}';
      // Only the start of a long output is kept, so only a window well
      // past what is kept is redacted: a secret beginning in the kept part
      // ends inside the window. Should redaction shrink the window to near
      // the limit, the whole text is redacted as before.
      final window = 2 * limit + 16384;
      final over = raw.length > window;
      var text = redactHarnessText(over ? raw.substring(0, window) : raw);
      if (over && text.runes.length < limit + 4096) {
        text = redactHarnessText(raw);
      }
      if (text.runes.length <= limit) return text;
      cut = true;
      return '${String.fromCharCodes(text.runes.take(limit))}…';
    }

    final safe = <String, dynamic>{
      'id': item['id'],
      'type': item['type'],
      'status': item['status'],
      'startedAt': previous ?? now.toUtc().toIso8601String(),
      if (method == 'item/completed') 'endedAt': now.toUtc().toIso8601String(),
      if (item['type'] == 'commandExecution') ...{
        'command': clip(item['command'], 4096),
        'exitCode': item['exitCode'],
        'durationMs': item['durationMs'] ??
            (method == 'item/completed'
                ? now
                    .difference(
                        DateTime.parse(previous ?? now.toIso8601String()))
                    .inMilliseconds
                : null),
        'aggregatedOutput': clip(item['aggregatedOutput'], 8192),
      },
      // A helper sent off: what it was asked and where it works.
      if (item['type'] == 'collabAgentToolCall') ...{
        'tool': item['tool'],
        'prompt': clip(item['prompt'], 4096),
        'receiverThreadIds': [
          for (final id in (item['receiverThreadIds'] as List? ?? const [])
              .take(8))
            '$id'
        ],
      },
      if (item['type'] == 'reasoning') ...{
        'summary': [
          for (final part in (item['summary'] as List? ?? const []).take(8))
            {
              'type': 'summary_text',
              'text': clip(part is Map ? part['text'] : part, 2048)
            }
        ],
        // Models that think without a summary keep their thinking here.
        if ((item['summary'] as List? ?? const []).isEmpty)
          'content': [
            for (final part in (item['content'] as List? ?? const []).take(8))
              clip(part is Map ? part['text'] : part, 4096)
          ],
      },
    };
    items[item['id']] = safe['startedAt'] as String;
    _append(turn, {
      'item': safe,
      if (cut && !turn.truncated) 'turn': {'truncated': true},
    });
    if (cut) turn.truncated = true;
  }

  /// One line for [turn]'s file. The oldest turns are dropped beyond
  /// [maxTurns], or while the kept files and lines pass [maxBytes].
  void _append(_Turn turn, Map<String, Object?> line) {
    final bytes = utf8.encode('${jsonEncode(line)}\n');
    turn.waiting.add(bytes);
    turn.bytes += bytes.length;
    _total += bytes.length;
    while (_turns.length > maxTurns || (_total > maxBytes && _turns.isNotEmpty)) {
      final oldest = _turns.removeAt(0);
      oldest.dropped = true;
      _total -= oldest.bytes;
      oldest.waiting.clear();
      final key = _keyOf(oldest.threadId, oldest.turnId);
      if (identical(_byKey[key], oldest)) _byKey.remove(key);
      _deletions.add(oldest.seq);
    }
    if (!_writeQueued) {
      _writeQueued = true;
      unawaited(_enqueue(_writePass));
    }
  }

  /// Deletes dropped turns, appends the waiting lines and rewrites the
  /// finished turns. Changes made meanwhile wait for the next pass.
  Future<void> _writePass() async {
    _writeQueued = false;
    _failure = null;
    final deletions = List.of(_deletions);
    _deletions.clear();
    for (final seq in deletions) {
      try {
        await _fileOf(seq).delete();
      } on PathNotFoundException {
        // Dropped before it was written.
      } on FileSystemException catch (error) {
        _failure = error;
        _deletions.add(seq);
      }
    }
    var created = false;
    for (final turn in List.of(_turns)) {
      if (turn.dropped || turn.waiting.isEmpty) continue;
      final lines = List.of(turn.waiting);
      turn.waiting.clear();
      final bytes = _joined(lines);
      try {
        if (!created) {
          await directory.create(recursive: true);
          created = true;
        }
        final file = await _fileOf(turn.seq).open(mode: FileMode.append);
        try {
          // A write that failed part way left a torn line past what is known.
          if (await file.length() > turn.disk) {
            await file.truncate(turn.disk);
            await file.setPosition(turn.disk);
          }
          await file.writeFrom(bytes);
          await file.flush();
        } finally {
          await file.close();
        }
        _written += bytes.length;
        turn.disk += bytes.length;
      } on FileSystemException catch (error) {
        _failure = error;
        if (!turn.dropped) turn.waiting.insertAll(0, lines);
      }
    }
    for (final turn in List.of(_turns)) {
      if (!turn.finished || turn.compacted || turn.dropped || turn.disk == 0) {
        continue;
      }
      turn.compacted = true;
      final size = await _compactIn(_fileOf(turn.seq).path, turn.disk);
      if (size == null) continue;
      _written += size;
      if (turn.dropped) continue;
      final change = size - turn.disk;
      turn.disk = size;
      turn.bytes += change;
      _total += change;
    }
  }

  /// Completes once the files hold every change observed so far; throws
  /// what kept the latest state from being written.
  Future<void> flush() async {
    for (var tail = _tail;; tail = _tail) {
      await tail;
      if (identical(tail, _tail)) break;
    }
    if (_failure case final failure?) throw failure;
  }

  /// One saved turn, without a store that writes: what a reader uses while
  /// no conversation host runs. Reads a single file not yet moved as well.
  static Future<Map<String, dynamic>?> readSaved(
      Directory root, String harnessPath, String threadId, String turnId) {
    final dir = directoryFor(root, harnessPath).path;
    final single = fileFor(root, harnessPath).path;
    return Isolate.run(() => _readSaved(dir, single, threadId, turnId),
        debugName: 'turn-process read');
  }

  // Below, what runs on other isolates. Each starts from a static method, so
  // that its closure holds only its own arguments.

  static Future<(List<_Turn>, int)> _loadIn(
          String dir, String? legacy, int maxTurns, int maxBytes) =>
      Isolate.run(() => _load(dir, legacy, maxTurns, maxBytes),
          debugName: 'turn-process open');

  static Future<List<Map<String, dynamic>?>> _foldIn(
          List<String> paths, List<int> lengths, List<Uint8List> waiting) =>
      Isolate.run(() => _foldAll(paths, lengths, waiting),
          debugName: 'turn-process read');

  static Future<int?> _compactIn(String path, int length) =>
      Isolate.run(() => _compact(path, length),
          debugName: 'turn-process rewrite');

  static final _numbered = RegExp(r'^(\d+)\.jsonl$');
  static final _decoder =
      const Utf8Decoder(allowMalformed: true).fuse(const JsonDecoder());

  static Uint8List _joined(List<Uint8List> lines) {
    if (lines.length == 1) return lines.single;
    final out = BytesBuilder(copy: false);
    for (final line in lines) {
      out.add(line);
    }
    return out.takeBytes();
  }

  static void _delete(File file) {
    try {
      file.deleteSync();
    } on FileSystemException {
      // Gone already, or left for a later start.
    }
  }

  /// The kept turns, oldest first, and the highest number a file has.
  static (List<_Turn>, int) _load(
      String dir, String? legacy, int maxTurns, int maxBytes) {
    final directory = Directory(dir)..createSync(recursive: true);
    var top = -1;
    final kept = <_Turn>[];
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        _delete(entity);
        continue;
      }
      final seq = int.tryParse(_numbered.firstMatch(name)?[1] ?? '');
      if (seq == null) continue;
      top = max(top, seq);
      try {
        final turn = _inspect(entity, seq);
        if (turn == null) {
          // Its first line never finished being written.
          _delete(entity);
        } else {
          kept.add(turn);
        }
      } on FileSystemException {
        // Unreadable now; left as it is.
      }
    }
    kept.sort((a, b) => a.seq.compareTo(b.seq));
    if (legacy != null) top = _migrate(File(legacy), dir, kept, top);
    var total = 0;
    for (final turn in kept) {
      total += turn.bytes;
    }
    while (kept.length > maxTurns || (total > maxBytes && kept.isNotEmpty)) {
      final oldest = kept.removeAt(0);
      total -= oldest.bytes;
      _delete(File('$dir/${oldest.seq}.jsonl'));
    }
    return (kept, top);
  }

  /// A turn's index entry. One still running when it was last written is
  /// folded for what its later changes need; one that finished without its
  /// rewrite, or ends in a torn line, is rewritten now.
  static _Turn? _inspect(File file, int seq) {
    final head = _firstLine(file);
    if (head == null) return null;
    final threadId = head['threadId'];
    final turnId = head['turnId'];
    final startedAt = head['startedAt'];
    if (threadId is! String || turnId is! String || startedAt is! String) {
      return null;
    }
    final turn = _Turn(seq, threadId, turnId, startedAt);
    if (head['status'] != 'inProgress' && _endsLine(file)) {
      return turn
        ..disk = turn.bytes = file.lengthSync()
        ..finished = turn.compacted = true
        ..truncated = head['truncated'] == true;
    }
    var bytes = file.readAsBytesSync();
    final end = bytes.lastIndexOf(0x0a) + 1;
    if (end < bytes.length) {
      // A torn last line.
      final open = file.openSync(mode: FileMode.append);
      try {
        open.truncateSync(end);
      } finally {
        open.closeSync();
      }
      bytes = Uint8List.sublistView(bytes, 0, end);
    }
    final folded = _fold(bytes)!;
    turn.truncated = folded['truncated'] == true;
    if (folded['status'] != 'inProgress') {
      turn.disk = turn.bytes = _rewrite(file, folded);
      return turn..finished = turn.compacted = true;
    }
    turn.disk = turn.bytes = bytes.length;
    turn.items = _itemStarts(folded);
    return turn;
  }

  static bool _endsLine(File file) {
    final open = file.openSync();
    try {
      final length = open.lengthSync();
      if (length == 0) return false;
      open.setPositionSync(length - 1);
      return open.readByteSync() == 0x0a;
    } finally {
      open.closeSync();
    }
  }

  static Map<Object?, String?> _itemStarts(Map<String, dynamic> turn) => {
        for (final item in (turn['items'] as List).cast<Map>())
          item['id']: item['marker'] == true ? null : item['startedAt'] as String?
      };

  static Map<String, dynamic>? _firstLine(File file) {
    final open = file.openSync();
    try {
      final head = BytesBuilder(copy: false);
      while (true) {
        final chunk = open.readSync(4096);
        if (chunk.isEmpty) return null;
        final end = chunk.indexOf(0x0a);
        if (end < 0) {
          head.add(chunk);
          continue;
        }
        head.add(Uint8List.sublistView(chunk, 0, end));
        final line = _decoder.convert(head.takeBytes());
        return line is Map<String, dynamic> ? line : null;
      }
    } on FormatException {
      return null;
    } finally {
      open.closeSync();
    }
  }

  /// Moves the turns of the single file earlier versions kept, oldest
  /// first, after those already moved; then removes it. A file that cannot
  /// be read is left where it is.
  static int _migrate(File legacy, String dir, List<_Turn> kept, int top) {
    if (!legacy.existsSync()) return top;
    final List turns;
    try {
      turns = jsonDecode(legacy.readAsStringSync()) as List;
    } on FormatException {
      return top;
    } on FileSystemException {
      return top;
    } on TypeError {
      return top;
    }
    final present = {for (final turn in kept) _keyOf(turn.threadId, turn.turnId)};
    for (final value in turns) {
      if (value is! Map) continue;
      final saved = Map<String, dynamic>.from(value);
      final threadId = saved['threadId'];
      final turnId = saved['turnId'];
      final startedAt = saved['startedAt'];
      if (threadId is! String ||
          turnId is! String ||
          startedAt is! String ||
          saved['items'] is! List ||
          !present.add(_keyOf(threadId, turnId))) {
        continue;
      }
      final turn = _Turn(++top, threadId, turnId, startedAt)
        ..truncated = saved['truncated'] == true;
      turn.disk = turn.bytes = _rewrite(File('$dir/${turn.seq}.jsonl'), saved);
      if (saved['status'] == 'inProgress') {
        turn.items = _itemStarts(saved);
      } else {
        turn.finished = turn.compacted = true;
      }
      kept.add(turn);
    }
    // Should it stay, the next start finds its turns here and skips them.
    _delete(legacy);
    return top;
  }

  /// [turn] as its finished file: the turn, then one line per item.
  static int _rewrite(File file, Map<String, dynamic> turn) {
    final out = BytesBuilder(copy: false);
    out.add(utf8.encode('${jsonEncode({...turn}..remove('items'))}\n'));
    for (final item in turn['items'] as List) {
      out.add(utf8.encode('${jsonEncode({'item': item})}\n'));
    }
    final bytes = out.takeBytes();
    final temp = File('${file.path}.tmp');
    temp.writeAsBytesSync(bytes, flush: true);
    temp.renameSync(file.path);
    return bytes.length;
  }

  static int? _compact(String path, int length) {
    try {
      final file = File(path);
      final turn = _fold(_prefix(file, length));
      return turn == null ? null : _rewrite(file, turn);
    } on FileSystemException {
      // The appended lines stay as they are.
      return null;
    }
  }

  static Uint8List _prefix(File file, int length) {
    if (length == 0) return Uint8List(0);
    final open = file.openSync();
    try {
      return open.readSync(length);
    } finally {
      open.closeSync();
    }
  }

  static List<Map<String, dynamic>?> _foldAll(
      List<String> paths, List<int> lengths, List<Uint8List> waiting) {
    return [
      for (var i = 0; i < paths.length; i++) _foldSaved(paths[i], lengths[i], waiting[i])
    ];
  }

  static Map<String, dynamic>? _foldSaved(
      String path, int length, Uint8List waiting) {
    try {
      return _fold(_joined([_prefix(File(path), length), waiting]));
    } on FileSystemException {
      return null;
    }
  }

  /// The turn its lines tell: the first is the turn, each further one a
  /// change; a line that does not decode (torn) is skipped.
  static Map<String, dynamic>? _fold(Uint8List bytes) {
    Map<String, dynamic>? turn;
    final items = <Map<String, dynamic>>[];
    final at = <Object?, int>{};
    var start = 0;
    while (start < bytes.length) {
      var end = bytes.indexOf(0x0a, start);
      if (end < 0) end = bytes.length;
      final Object? line;
      try {
        line = _decoder.convert(Uint8List.sublistView(bytes, start, end));
      } on FormatException {
        start = end + 1;
        continue;
      }
      start = end + 1;
      if (line is! Map<String, dynamic>) continue;
      if (turn == null) {
        if (line['threadId'] is! String || line['turnId'] is! String) {
          return null;
        }
        turn = line;
        continue;
      }
      if (line['turn'] case final Map<String, dynamic> change) {
        turn.addAll(change);
      }
      if (line['item'] case final Map<String, dynamic> item) {
        final i = at[item['id']];
        if (i == null) {
          at[item['id']] = items.length;
          items.add(item);
        } else {
          items[i] = item;
        }
      }
    }
    return turn?..['items'] = items;
  }

  static Map<String, dynamic>? _readSaved(
      String dir, String single, String threadId, String turnId) {
    final directory = Directory(dir);
    if (directory.existsSync()) {
      final numbered = <(int, File)>[
        for (final entity in directory.listSync())
          if (entity is File)
            if (int.tryParse(
                    _numbered.firstMatch(entity.uri.pathSegments.last)?[1] ??
                        '')
                case final seq?)
              (seq, entity)
      ]..sort((a, b) => b.$1.compareTo(a.$1));
      for (final (_, file) in numbered) {
        final head = _firstLine(file);
        if (head?['threadId'] == threadId && head?['turnId'] == turnId) {
          return _fold(file.readAsBytesSync());
        }
      }
    }
    final file = File(single);
    if (!file.existsSync()) return null;
    try {
      for (final turn in jsonDecode(file.readAsStringSync()) as List) {
        if (turn is Map &&
            turn['threadId'] == threadId &&
            turn['turnId'] == turnId) {
          return Map<String, dynamic>.from(turn);
        }
      }
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    return null;
  }
}

/// A kept turn as the main isolate indexes it.
final class _Turn {
  _Turn(this.seq, this.threadId, this.turnId, this.startedAt);

  /// Its file's name; turns that began later have higher numbers.
  final int seq;
  final String threadId, turnId, startedAt;

  /// Bytes in its file; in its file and its waiting lines together.
  int disk = 0, bytes = 0;
  final waiting = <Uint8List>[];

  /// Item id to when it started (null for Codex's own items, kept as
  /// markers). Not kept for a turn that had finished when the store opened.
  Map<Object?, String?>? items;
  bool truncated = false, finished = false, compacted = false, dropped = false;
}
