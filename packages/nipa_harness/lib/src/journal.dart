part of 'kernel.dart';

final class JsonlJournal implements InvocationObserver {
  JsonlJournal(
    File file, {
    Set<Effect> effects = const {Effect.write, Effect.destructive},
  })  : _file = file,
        _effects = Set.of(effects);

  final File _file;
  final Set<Effect> _effects;
  Future<void> _written = Future.value();

  /// The line is worked out (secrets replaced, encoded) on a background
  /// isolate from the record as it is now; lines are appended and flushed in
  /// the order invocations end, and the invocation's outcome is returned
  /// once its line is on disk, as before.
  @override
  Future<void>? onInvocation(InvocationRecord record) {
    if (!_effects.contains(record.effect)) return null;
    final line = _journalLine(record);
    final previous = _written;
    final written = () async {
      final text = await line;
      try {
        await previous;
      } catch (_) {
        // An earlier line's failure is that invocation's.
      }
      await _file.parent.create(recursive: true);
      await _file.writeAsString(text, mode: FileMode.append, flush: true);
    }();
    _written = written;
    return written;
  }
}

Future<String> _journalLine(InvocationRecord record) =>
    Isolate.run(() => '${jsonEncode(record.toJson())}\n');
