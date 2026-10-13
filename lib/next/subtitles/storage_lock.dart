import 'dart:async';
import 'dart:io';

final _tails = <String, Future<void>>{};

/// Imports and explicit disk cleanup share one storage ownership boundary.
Future<T> withSubtitleStorage<T>(
    Directory root, Future<T> Function() run) async {
  final key = root.absolute.path;
  final previous = _tails[key] ?? Future<void>.value();
  final done = Completer<void>();
  _tails[key] = done.future;
  await previous;
  try {
    return await run();
  } finally {
    done.complete();
    if (identical(_tails[key], done.future)) _tails.remove(key);
  }
}
