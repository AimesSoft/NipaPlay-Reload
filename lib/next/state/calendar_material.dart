import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import '../../models/bangumi_model.dart';

/// The airing calendar as Classic keeps it, still undecoded. The main isolate
/// only reads the stored text (and hands over the details it holds in memory);
/// parsing it into rows, which grows with the calendar, happens where the rows
/// are used: in the library worker.
final class CalendarMaterial {
  CalendarMaterial({this.cache, this.saved = const {}, this.memory = const []})
      : _rowsJson = null;

  /// Rows that are already complete, as a JSON array.
  CalendarMaterial.encoded(String rowsJson)
      : _rowsJson = rowsJson,
        cache = null,
        saved = const {},
        memory = const [];

  /// The cached calendar list, as stored.
  final String? cache;

  /// Each saved anime detail by anime ID, as stored.
  final Map<int, String> saved;

  /// Details held in memory; they take precedence over the saved ones.
  final List<BangumiAnime> memory;
  final String? _rowsJson;

  List<JsonMap>? _rows;

  /// The calendar's rows, decoded once per material.
  List<JsonMap> rows() => _rows ??= _decode();

  List<JsonMap> _decode() {
    final encoded = _rowsJson;
    if (encoded != null) {
      return [
        for (final row in jsonDecode(encoded) as List)
          Map<String, Object?>.from(row as Map)
      ];
    }
    final raw = cache;
    if (raw == null) return [];
    final inMemory = {for (final anime in memory) anime.id: anime};
    final rows = <JsonMap>[];
    for (final row in ((jsonDecode(raw) as Map)['animes'] as List).cast<Map>()) {
      final intro = BangumiAnime.fromJson(Map<String, dynamic>.from(row));
      final stored = saved[intro.id];
      final detail = inMemory[intro.id] ??
          (stored == null
              ? null
              : BangumiAnime.fromDandanplayDetail(Map<String, dynamic>.from(
                  (jsonDecode(stored) as Map)['animeDetail'] as Map)));
      rows.add(Map<String, Object?>.from(intro
          .copyWith(
              episodeList: detail?.episodeList,
              isFavorited: detail?.isFavorited ?? intro.isFavorited)
          .toJson()));
    }
    return rows;
  }
}
