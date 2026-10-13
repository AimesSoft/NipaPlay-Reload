import 'package:nipa_harness/nipa_harness.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import 'discover.dart';

/// What the search box asks, one group at a time; each group answers on its
/// own and may fail on its own. Read only.
abstract interface class NextSearchData {
  /// Works (and episodes) the viewer has, on this device and the others in
  /// the mesh, matching [query].
  Future<UiLibraryHits> library(String query);

  /// Works found online, for their page with “让 Nipa 准备” ([Found]).
  Future<List<UiWork>> online(String query);

  /// What the media sources (Jellyfin, Emby, SMB…) hold matching [query].
  /// Null: sources cannot be searched; the group is not shown.
  Future<List<UiSourceHit>>? sources(String query);
}

final class UiLibraryHits {
  const UiLibraryHits({this.works = const [], this.episodes = const []});
  final List<UiWork> works;

  /// Episodes whose own title matches, each with its work.
  final List<(UiWork, UiEpisode)> episodes;

  bool get isEmpty => works.isEmpty && episodes.isEmpty;
}

/// A work in one of the media sources.
final class UiSourceHit {
  const UiSourceHit(this.work, {required this.source, required this.kind});

  /// What opens: its page.
  final UiWork work;

  /// The source as the viewer named it: “客厅 Jellyfin”.
  final String source;
  final UiSourceKind kind;
}

/// The real searches, invoked as the interface (`origin: gui`):
///
/// - 片库: `state.query` over `library.merged`, the viewer's library across
///   the mesh, whose IDs `work()` and `ui.open` accept. Its title only (the
///   view declares no original title); no episodes (nothing searches
///   episode titles yet).
/// - 在线: `media.metadata.search` on 弹弹play, whose works the found page
///   ([CoreDiscover.details]) can read.
/// - 来源: none. Sources are only searched by `media.sources.browse`, which
///   writes what it finds into the file index: not for every keystroke.
final class CoreSearch implements NextSearchData {
  /// [harness]: the runtime's, read at each call (it may come later).
  CoreSearch(this.harness);
  final Harness Function() harness;

  static const _limit = 12;

  Future<JsonMap> _call(String action, JsonMap input) async {
    final outcome =
        await harness().invokeJson(action, input, Invocation(origin: 'gui'));
    return switch (outcome) {
      Completed(:final value) => value.toJson(),
      Failed(:final failure) => throw failure,
      NeedsDecision() => throw StateError('$action asked for a decision'),
    };
  }

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  @override
  Future<UiLibraryHits> library(String query) async {
    final result = await _call('state.query', {
      'view': 'library.merged',
      'filter': {
        'title': {'contains': query}
      },
      'limit': _limit,
    });
    return UiLibraryHits(works: [
      for (final row in (result['rows'] as List).cast<Map>())
        if (_text(row['workId']) case final id?) _work(id, row),
    ]);
  }

  /// The view's public fields only: no year or original title (they are
  /// not declared), the count from its episodes as the library's codec does.
  static UiWork _work(String id, Map row) {
    final art = row['artwork'] is Map ? row['artwork'] as Map : const {};
    final devices = row['devices'] is List ? row['devices'] as List : const [];
    final episodes =
        row['episodes'] is List ? row['episodes'] as List : const [];
    return UiWork(
      workId: id,
      title: _text(row['title']) ?? '',
      episodeCount: episodes.isEmpty ? null : episodes.length,
      artwork: UiArtwork(
        backdrop: _text(art['backdrop']),
        poster: _text(art['poster']),
        tint: art['tint'] is int ? art['tint'] as int : null,
      ),
      devices: [
        for (final d in devices.whereType<Map>())
          if (_text(d['name']) case final name?)
            UiDevice(name: name, online: d['online'] != false)
      ],
    );
  }

  @override
  Future<List<UiWork>> online(String query) async {
    final result = await _call(
        'media.metadata.search', {'provider': 'dandanplay', 'query': query});
    return [
      for (final r in (result['results'] as List).cast<Map>().take(_limit))
        if ((r['ref'] as Map?)?['externalId'] case final String external)
          UiWork(
            workId: Found.id('dandanplay', external),
            title: _text(r['title']) ?? '',
            originalTitle: _text(r['originalTitle']),
            year: r['year'] as int?,
            overview: _text(r['overview']),
            artwork: UiArtwork(poster: _text(r['imageUrl'])),
          ),
    ];
  }

  @override
  Future<List<UiSourceHit>>? sources(String query) => null;
}
