import 'package:nipa_harness/nipa_harness.dart' show JsonMap;

import 'gui_calls.dart';

/// What was watched, latest first: the public `history.entries` view
/// (`state.query`), `history.remove` to forget, `playback.open` to go on.
final class NextHistory {
  NextHistory(this.calls);
  final GuiCalls calls;

  static const _page = 80;

  /// A page of the record; [cursor] from the previous one.
  Future<UiHistoryPage> page({String? cursor}) async {
    final r = await calls.call('state.query', {
      'view': 'history.entries',
      'limit': _page,
      if (cursor != null) 'cursor': cursor,
    });
    return UiHistoryPage(
      entries: [
        for (final row in (r['rows'] as List).cast<Map>()) UiHistoryEntry.from(row)
      ],
      cursor: r['nextCursor'] as String?,
    );
  }

  /// Forgets [entries]; the videos stay where they are.
  Future<void> remove(List<UiHistoryEntry> entries) async {
    final paths = [
      for (final e in entries)
        if (e.locator != null) e.locator!
    ];
    if (paths.isEmpty) return;
    await calls.call('history.remove', {'paths': paths});
  }

  /// Forgets everything recorded.
  Future<void> clear() async {
    final paths = <String>{}, works = <int>{};
    String? cursor;
    do {
      final page = await this.page(cursor: cursor);
      for (final e in page.entries) {
        if (e.locator != null) paths.add(e.locator!);
        if (e.animeId != null) works.add(e.animeId!);
      }
      cursor = page.cursor;
    } while (cursor != null);
    if (paths.isEmpty && works.isEmpty) return;
    await calls.call('history.remove', {
      if (paths.isNotEmpty) 'paths': paths.toList(),
      if (works.isNotEmpty) 'animeIds': works.toList(),
    });
  }

  /// Plays it again from where it was left. Several copies of it ask which
  /// one ([DecisionNeeded]).
  Future<JsonMap> resume(UiHistoryEntry entry) =>
      calls.call('playback.open', {'path': entry.locator!});
}

final class UiHistoryPage {
  const UiHistoryPage({required this.entries, this.cursor});
  final List<UiHistoryEntry> entries;
  final String? cursor;
}

final class UiHistoryEntry {
  const UiHistoryEntry({
    required this.entryId,
    required this.title,
    this.episode,
    this.locator,
    this.animeId,
    this.progress,
    this.position,
    this.duration,
    this.at,
  });

  final String entryId;
  final String title;
  final String? episode;

  /// Where the video is (a path or a source's address); null when this
  /// device may not see it.
  final String? locator;
  final int? animeId;
  final double? progress;
  final Duration? position;
  final Duration? duration;
  final DateTime? at;

  bool get playable => locator != null;

  factory UiHistoryEntry.from(Map row) {
    final title = (row['title'] as String?)?.trim();
    final locator = row['locator'] as String?;
    final position = (row['positionMs'] as num?)?.toInt();
    final duration = (row['durationMs'] as num?)?.toInt();
    return UiHistoryEntry(
      entryId: '${row['entryId']}',
      title: title != null && title.isNotEmpty
          ? title
          : _fileName(locator) ?? '',
      episode: (row['episodeTitle'] as String?)?.trim(),
      locator: locator,
      animeId: (row['animeId'] as num?)?.toInt(),
      progress: (row['progress'] as num?)?.toDouble(),
      position: position == null ? null : Duration(milliseconds: position),
      duration: duration == null || duration == 0
          ? null
          : Duration(milliseconds: duration),
      at: DateTime.tryParse('${row['lastWatchedAt']}')?.toLocal(),
    );
  }

  static String? _fileName(String? locator) {
    if (locator == null) return null;
    final name = Uri.decodeComponent(locator.split(RegExp(r'[/\\]')).last);
    return name.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '');
  }
}
