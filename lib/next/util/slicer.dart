import 'dart:async';

/// Keeps long work on the main isolate in short pieces: [call] returns at
/// once while the piece has run for less than [budget], and otherwise lets
/// the event loop turn (frames, input, messages) before the next piece.
/// A piece ends after its budget plus whatever the last item took, so the
/// budget sits well under the 4 ms a single stretch of Next's work may hold
/// the main isolate (the same on a slower or busier machine).
///
/// ```dart
/// final slice = Slicer();
/// for (final item in items) {
///   work(item);
///   await slice();
/// }
/// ```
final class Slicer {
  Slicer({this.budget = const Duration(milliseconds: 2)}) {
    _piece.start();
  }

  final Duration budget;
  final _piece = Stopwatch();

  Future<void> call() async {
    if (_piece.elapsed < budget) return;
    await Future<void>.delayed(Duration.zero);
    _piece
      ..reset()
      ..start();
  }
}

/// [items] sorted by [compare] (a total order) in pieces of a few
/// milliseconds: runs of 256 are sorted, then merged two at a time.
Future<List<T>> slicedSort<T>(
    List<T> items, int Function(T a, T b) compare, Slicer slice) async {
  if (items.length <= 512) return items..sort(compare);
  var runs = <List<T>>[];
  for (var i = 0; i < items.length; i += 256) {
    runs.add(items.sublist(i, i + 256 > items.length ? items.length : i + 256)
      ..sort(compare));
    await slice();
  }
  while (runs.length > 1) {
    final merged = <List<T>>[];
    for (var i = 0; i < runs.length; i += 2) {
      if (i + 1 == runs.length) {
        merged.add(runs[i]);
        continue;
      }
      final a = runs[i], b = runs[i + 1], out = <T>[];
      var x = 0, y = 0;
      while (x < a.length && y < b.length) {
        out.add(compare(a[x], b[y]) <= 0 ? a[x++] : b[y++]);
        if (out.length & 255 == 0) await slice();
      }
      out
        ..addAll(a.skip(x))
        ..addAll(b.skip(y));
      merged.add(out);
      await slice();
    }
    runs = merged;
  }
  return runs.single;
}
