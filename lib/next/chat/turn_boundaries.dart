import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';

/// The chat turn each origin is in, as this process wrote it to a journal:
/// a `chat.turn_boundary` row goes to journal.jsonl through the file's one
/// appender, and is remembered here so ui.present knows the current turn
/// without reading the journal.
abstract final class TurnBoundaries {
  static final _latest = <String, Map<String, JsonMap>>{};

  /// Remembers [row] as its origin's latest boundary now, and appends it to
  /// [journal] after every line handed in before it; the future completes
  /// once it is on disk.
  static Future<void> write(File journal, JsonMap row) {
    (_latest[JournalAppender.pathOf(journal)] ??= {})[row['origin'] as String] =
        Map.of(row);
    return JournalAppender.of(journal).appendText('${jsonEncode(row)}\n');
  }

  /// The latest boundary of [origin] this process wrote to [journal], or
  /// null when it wrote none.
  static JsonMap? latest(File journal, String origin) =>
      _latest[JournalAppender.pathOf(journal)]?[origin];
}
