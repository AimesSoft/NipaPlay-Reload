part of 'kernel.dart';

final class JsonlJournal implements InvocationObserver {
  /// Journals the invocations whose effect is in [effects] to [file].
  ///
  /// [keepsResult] names the reads whose line keeps its result; other reads
  /// are journalled without it. [rotateBytes] moves [file] into an archive
  /// once it has grown past that size (see [JournalAppender]).
  JsonlJournal(
    File file, {
    Set<Effect> effects = const {Effect.write, Effect.destructive},
    bool Function(InvocationRecord record)? keepsResult,
    int? rotateBytes,
  })  : _appender = JournalAppender.of(file, rotateBytes: rotateBytes),
        _effects = Set.of(effects),
        _keepsResult = keepsResult;

  final JournalAppender _appender;
  final Set<Effect> _effects;
  final bool Function(InvocationRecord record)? _keepsResult;

  /// A write or destructive invocation's line is the whole record (input and
  /// result, secrets replaced), worked out on a background isolate from the
  /// record as it is now; it is appended and flushed in the order
  /// invocations end, and the invocation's outcome is returned once the line
  /// is on disk, as before.
  ///
  /// A read's line has the same shape without the result
  /// (`resultOmitted: true` says a completed read's result was left out),
  /// unless [keepsResult] keeps it. It takes its place in the same order but
  /// the read does not wait for it, and it is not flushed on its own: it
  /// goes to disk with the lines around it.
  @override
  Future<void>? onInvocation(InvocationRecord record) {
    if (!_effects.contains(record.effect)) return null;
    if (record.effect != Effect.read) {
      return _appender.append(_journalLine(record));
    }
    final keep =
        record._rawResult != null && (_keepsResult?.call(record) ?? false);
    _appender
        .append(keep ? _journalLine(record) : _compactLine(record),
            durable: false)
        .ignore();
    return null;
  }

  /// Completes once every line handed in so far has been written.
  Future<void> drain() => _appender.drain();
}

Future<List<int>> _journalLine(InvocationRecord record) =>
    Isolate.run(() => utf8.encode('${jsonEncode(record.toJson())}\n'));

/// Only the input is walked; the result is not touched.
List<int> _compactLine(InvocationRecord record) =>
    utf8.encode('${jsonEncode(record.toJson(withResult: false))}\n');

/// The one writer of a JSONL file in this isolate. Everything appended to
/// the file — invocation records, chat turn boundaries, other events — goes
/// through it, so lines are written whole and in the order they were handed
/// in, whoever handed them in.
///
/// With [rotateBytes] set, a file that the next text appended would take
/// past that size is first moved, whole lines only, into [archiveDirectory]
/// as an immutable segment (`<name>-<UTC time>.jsonl`); segments are kept.
/// [segments] lists them oldest first, then the file itself.
final class JournalAppender {
  JournalAppender._(this.file);

  static final _byPath = <String, JournalAppender>{};

  /// The appender of [file]. [rotateBytes], when given, turns rotation on
  /// for that file; omitted, the file's earlier setting stays.
  static JournalAppender of(File file, {int? rotateBytes}) {
    final path = pathOf(file);
    final appender = _byPath[path] ??= JournalAppender._(File(path));
    if (rotateBytes != null) appender.rotateBytes = rotateBytes;
    return appender;
  }

  /// The absolute, normalized path appenders are kept by.
  static String pathOf(File file) =>
      file.absolute.uri.normalizePath().toFilePath();

  final File file;
  int? rotateBytes;
  final _pending = <_Append>[];
  bool _writing = false;

  /// Queues [bytes] (whole lines, each ending in a newline) after
  /// everything queued before. The future completes once they have been
  /// written and, when [durable], flushed to disk together with everything
  /// before them. Text that is not durable is written with the next batch,
  /// which is formed as soon as the writer is free.
  Future<void> append(FutureOr<List<int>> bytes, {bool durable = true}) {
    final entry = _Append(bytes, durable);
    _pending.add(entry);
    if (!_writing) {
      _writing = true;
      unawaited(_run());
    }
    return entry.done.future;
  }

  /// Appends [text] as UTF-8; see [append].
  Future<void> appendText(String text, {bool durable = true}) =>
      append(utf8.encode(text), durable: durable);

  /// Completes once everything appended so far has been written.
  Future<void> drain() {
    if (!_writing) return Future.value();
    final done = append(const <int>[], durable: false);
    return done.then((_) {}, onError: (_) {});
  }

  Future<void> _run() async {
    while (_pending.isNotEmpty) {
      final batch = List.of(_pending);
      _pending.clear();
      final parts = <List<int>>[];
      final written = <_Append>[];
      var durable = false;
      for (final entry in batch) {
        try {
          final bytes = await entry.bytes;
          if (bytes.isNotEmpty) parts.add(bytes);
          written.add(entry);
          durable |= entry.durable;
        } catch (error, stack) {
          entry.done.completeError(error, stack);
        }
      }
      try {
        await _write(parts, durable);
        for (final entry in written) {
          entry.done.complete();
        }
      } catch (error, stack) {
        for (final entry in written) {
          entry.done.completeError(error, stack);
        }
      }
    }
    _writing = false;
  }

  /// Writes [parts] (each whole lines) with one write per run between
  /// rotations, and flushes at the end when [durable].
  Future<void> _write(List<List<int>> parts, bool durable) async {
    if (parts.isEmpty && !durable) return;
    await file.parent.create(recursive: true);
    var handle = await file.open(mode: FileMode.append);
    try {
      final limit = rotateBytes;
      var length = limit == null ? 0 : await handle.length();
      var rotate = limit != null;
      final run = BytesBuilder(copy: false);
      for (final part in parts) {
        if (rotate && length > 0 && length + part.length > limit!) {
          if (run.isNotEmpty) await handle.writeFrom(run.takeBytes());
          await handle.flush();
          await handle.close();
          try {
            await _archive();
          } catch (_) {
            // The file stays hot (a reader may hold it open); the next
            // batch tries again.
            rotate = false;
          }
          handle = await file.open(mode: FileMode.append);
          length = await handle.length();
        }
        run.add(part);
        length += part.length;
      }
      if (run.isNotEmpty) await handle.writeFrom(run.takeBytes());
      if (durable) await handle.flush();
    } finally {
      await handle.close();
    }
  }

  /// Where [file]'s rotated segments are kept.
  static Directory archiveDirectory(File file) {
    final (stem, _) = _split(file);
    return Directory('${file.parent.path}/$stem-archive');
  }

  /// [file]'s archived segments, oldest first, then [file] itself; only
  /// those that exist.
  static Future<List<File>> segments(File file) async {
    final (stem, extension) = _split(file);
    final directory = archiveDirectory(file);
    final archived = <File>[
      if (await directory.exists())
        await for (final entity in directory.list(followLinks: false))
          if (entity is File &&
              entity.uri.pathSegments.last.startsWith('$stem-') &&
              entity.path.endsWith(extension))
            entity
    ]..sort((a, b) => a.path.compareTo(b.path));
    return [...archived, if (await file.exists()) file];
  }

  Future<void> _archive() async {
    final (stem, extension) = _split(file);
    final directory = archiveDirectory(file);
    await directory.create(recursive: true);
    var at = DateTime.now().toUtc();
    File target() => File('${directory.path}/$stem-${_stamp(at)}$extension');
    while (await target().exists()) {
      at = at.add(const Duration(microseconds: 1));
    }
    await file.rename(target().path);
  }

  static (String, String) _split(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? (name, '') : (name.substring(0, dot), name.substring(dot));
  }

  /// Fixed width, so names sort in time order.
  static String _stamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year.toString().padLeft(4, '0')}${two(at.month)}${two(at.day)}'
        'T${two(at.hour)}${two(at.minute)}${two(at.second)}'
        '.${(at.millisecond * 1000 + at.microsecond).toString().padLeft(6, '0')}Z';
  }
}

final class _Append {
  _Append(this.bytes, this.durable);
  final FutureOr<List<int>> bytes;
  final bool durable;
  final done = Completer<void>();
}
