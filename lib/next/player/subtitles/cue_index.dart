import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';

/// What the overlay shows at a time: [text] ('' for nothing) from [from]
/// until [until] (cue time, before any delay; [until] null: to the end).
@immutable
final class CueLine {
  const CueLine(this.text, this.from, this.until);
  static const blank = CueLine('', 0, null);
  final String text;
  final int from;
  final int? until;
}

/// One page of cues for subtitle.cues: [items] in the file's order, the
/// matching [total], and where the next page starts.
final class CuePage {
  const CuePage(this.items, this.total, this.nextCursor);
  final List<({int index, int startMs, int endMs, String text, bool current})>
      items;
  final int total;
  final int? nextCursor;
}

/// One subtitle file's timed text, parsed off the main isolate and indexed
/// there (player-core design §4.2): the main isolate gets the finished
/// index and only ever binary-searches it, for the overlay ([lineAt]) and
/// for subtitle.cues ([page]).
final class CueIndex {
  CueIndex._({
    required this.path,
    required this.format,
    required this.encoding,
    required this.starts,
    required this.ends,
    required this.texts,
    required this.maxEnd,
    required this.sortedEnds,
    required this.bounds,
    required this.lines,
    required this.parseUs,
  });

  final String path;
  final String format;
  final String encoding;

  /// The cues in start order: start and end (ms) and the text as parsed.
  final Int32List starts;
  final Int32List ends;
  final List<String> texts;

  /// The largest end among the cues up to each one.
  final Int32List maxEnd;
  final Int32List sortedEnds;

  /// The overlay's lines: from [bounds][i] until [bounds][i + 1] it shows
  /// [lines][i], the text of every cue on then, each once.
  final Int32List bounds;
  final List<String> lines;

  /// How long the parse and index took, off the main isolate.
  final int parseUs;

  int get length => starts.length;

  /// Parses [path] and indexes it in a background isolate; the index comes
  /// back without a copy ([Isolate.run] exits with it).
  static Future<CueIndex> load(String path) =>
      Isolate.run(() => _loadInBackground(path), debugName: 'cue index');

  static Future<CueIndex> _loadInBackground(String path) async {
    final watch = Stopwatch()..start();
    final parsed = await SubtitleParser.parseSubtitleFile(path);
    return build(path, parsed.entries,
        format: parsed.format.name,
        encoding: parsed.encoding,
        parseUs: watch.elapsedMicroseconds);
  }

  /// The index of [entries] (pure: runs where it is called).
  static CueIndex build(String path, List<SubtitleEntry> entries,
      {String format = 'unknown', String encoding = 'unknown', int parseUs = 0}) {
    final cues = [
      for (final e in entries)
        if (e.endTimeMs > e.startTimeMs && e.content.trim().isNotEmpty) e
    ];
    // Stable: cues starting together keep the file's order.
    final order = List<int>.generate(cues.length, (i) => i)
      ..sort((a, b) {
        final c = cues[a].startTimeMs.compareTo(cues[b].startTimeMs);
        return c != 0 ? c : a.compareTo(b);
      });
    final n = cues.length;
    final starts = Int32List(n), ends = Int32List(n), maxEnd = Int32List(n);
    final texts = List<String>.filled(n, '');
    var high = -1;
    for (var i = 0; i < n; i++) {
      final c = cues[order[i]];
      starts[i] = c.startTimeMs;
      ends[i] = c.endTimeMs;
      texts[i] = c.content;
      if (c.endTimeMs > high) high = c.endTimeMs;
      maxEnd[i] = high;
    }
    final sortedEnds = Int32List.fromList(ends)..sort();
    // The overlay's lines: every time a cue starts or ends, what is on.
    final times = SplayTreeSet<int>();
    for (var i = 0; i < n; i++) {
      times
        ..add(starts[i])
        ..add(ends[i]);
    }
    final bounds = Int32List.fromList(times.toList());
    final lines = List<String>.filled(bounds.length, '');
    final on = <int>[];
    var next = 0;
    for (var b = 0; b < bounds.length; b++) {
      final t = bounds[b];
      on.removeWhere((i) => ends[i] <= t);
      while (next < n && starts[next] <= t) {
        if (ends[next] > t) on.add(next);
        next++;
      }
      final shown = <String>[];
      for (final i in on) {
        final text = displayText(texts[i]);
        if (text.isNotEmpty && !shown.contains(text)) shown.add(text);
      }
      lines[b] = shown.join('\n');
    }
    return CueIndex._(
      path: path,
      format: format,
      encoding: encoding,
      starts: starts,
      ends: ends,
      texts: texts,
      maxEnd: maxEnd,
      sortedEnds: sortedEnds,
      bounds: bounds,
      lines: lines,
      parseUs: parseUs,
    );
  }

  static final _tags = RegExp(r'\{\\[^}]*\}|<[^>]+>');

  /// A cue's text as the overlay draws it: no markup, real line breaks.
  static String displayText(String raw) => raw
      .replaceAll(_tags, '')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\h', ' ')
      .trim();

  /// The first index whose value is > [value] in the ascending [list].
  static int _upper(Int32List list, int value) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The first index whose value is >= [value] in the ascending [list].
  static int _lower(Int32List list, int value) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// What the overlay shows at cue time [ms]: O(log n).
  CueLine lineAt(int ms) {
    if (bounds.isEmpty) return CueLine.blank;
    final i = _upper(bounds, ms) - 1;
    if (i < 0) return CueLine('', 0, bounds.first);
    return CueLine(lines[i], bounds[i], i + 1 < bounds.length ? bounds[i + 1] : null);
  }

  /// subtitle.cues over this file, its display times [delayMs] later than
  /// the file's: with [startMs]/[endMs], the cues that overlap that span;
  /// otherwise [context] cues either side of the one at [positionMs] (or
  /// the last one before it). [cursor] skips that many matches. O(log n)
  /// plus the cues it passes over.
  CuePage page({
    required int positionMs,
    int delayMs = 0,
    int context = 2,
    int? startMs,
    int? endMs,
    int cursor = 0,
    int limit = 100,
  }) {
    final items =
        <({int index, int startMs, int endMs, String text, bool current})>[];
    bool current(int i) =>
        starts[i] + delayMs <= positionMs && ends[i] + delayMs >= positionMs;
    void add(int i) => items.add((
          index: i,
          startMs: starts[i] + delayMs,
          endMs: ends[i] + delayMs,
          text: texts[i],
          current: current(i),
        ));
    if (startMs != null || endMs != null) {
      final from = (startMs ?? 0) - delayMs;
      final to = (endMs ?? 0x7fffffff) - delayMs;
      // Every cue that starts by [to], less those over before [from] (each
      // of those starts before [from] too).
      final total =
          (_upper(starts, to) - _lower(sortedEnds, from)).clamp(0, length);
      var skip = cursor;
      for (var i = _lower(maxEnd, from); i < length && starts[i] <= to; i++) {
        if (ends[i] < from) continue;
        if (skip > 0) {
          skip--;
          continue;
        }
        if (items.length >= limit) break;
        add(i);
      }
      final next = cursor + items.length;
      return CuePage(items, total, next < total ? next : null);
    }
    final at = positionMs - delayMs;
    final before = _upper(starts, at) - 1;
    var anchor = before;
    // The first cue on at [at], if any, among those that started by then.
    for (var i = before < 0 ? length : _lower(maxEnd, at); i <= before; i++) {
      if (ends[i] >= at) {
        anchor = i;
        break;
      }
    }
    final lo = (anchor - context).clamp(0, length);
    final hi = (anchor + context).clamp(-1, length - 1);
    final total = hi < lo ? 0 : hi - lo + 1;
    for (var i = lo + cursor; i <= hi && items.length < limit; i++) {
      add(i);
    }
    final next = cursor + items.length;
    return CuePage(items, total, next < total ? next : null);
  }
}

/// Parsed files kept for what plays and what was played last: the same
/// file (same size and time) opened again is not parsed again.
final class CueCache {
  CueCache({this.capacity = 8, Future<CueIndex> Function(String path)? load})
      : _load = load ?? CueIndex.load;
  final int capacity;
  final Future<CueIndex> Function(String path) _load;
  final _entries = <String, Future<CueIndex>>{};

  Future<CueIndex> get(String path) async {
    String key;
    try {
      final stat = await File(path).stat();
      key = '$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
    } catch (_) {
      key = path;
    }
    final hit = _entries.remove(key);
    final entry = hit ?? _load(path);
    _entries[key] = entry;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    try {
      return await entry;
    } catch (_) {
      _entries.remove(key);
      rethrow;
    }
  }
}
