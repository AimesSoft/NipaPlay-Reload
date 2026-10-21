import 'package:nipa_harness/nipa_harness.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import 'discover.dart';

/// What the search box asks, one group at a time; each group answers on its
/// own and may fail on its own, the sources each on their own too. Read
/// only.
abstract interface class NextSearchData {
  /// Works (and episodes) the viewer has, on this device and the others in
  /// the mesh, matching [query].
  Future<UiLibraryHits> library(String query);

  /// Works found online. One the library has carries its library workId
  /// (its page opens); the others are found works ([Found]), for their page
  /// with “让 Nipa 准备”.
  Future<List<UiWork>> online(String query);

  /// The media sources the box looks in (Jellyfin, Emby, SMB, WebDAV), read
  /// when the panel opens. None: there is no 来源 group.
  Future<List<UiSearchSource>> sources();

  /// What [source] holds matching [query], at most [limit].
  Future<UiSourceAnswer> searchSource(UiSearchSource source, String query,
      {int limit});

  /// The picture of [hit] the search came without, fetched from its source
  /// now: a path on this device, or null when there is none.
  Future<String?> sourceArtwork(UiSourceHit hit);
}

final class UiLibraryHits {
  const UiLibraryHits({this.works = const [], this.episodes = const []});
  final List<UiWork> works;

  /// Episodes whose own title matches, each with its work.
  final List<(UiWork, UiEpisode)> episodes;

  bool get isEmpty => works.isEmpty && episodes.isEmpty;
}

/// A media source the search box looks in.
final class UiSearchSource {
  const UiSearchSource(
      {required this.sourceId, required this.name, required this.kind});

  /// What it is asked by; never shown.
  final String sourceId;

  /// As the viewer named it: “客厅 Jellyfin”.
  final String name;
  final UiSourceKind kind;
}

/// One source's answer.
final class UiSourceAnswer {
  const UiSourceAnswer(this.hits, {this.failed = false});
  final List<UiSourceHit> hits;

  /// It could not be searched now: what it holds is unknown, not nothing.
  /// [hits], if any, are what it held when last seen.
  final bool failed;
}

enum UiSourceHitKind {
  /// A series or a film: its page opens.
  work,

  /// An episode or a video: it plays.
  episode,

  /// A file of a share.
  file,
}

/// Something a media source holds that matches.
///
/// What it opens: an [episode] plays (or, when it cannot, its [work]'s page
/// opens); otherwise the [work]'s page; a file no work holds plays from the
/// source itself, by [itemId].
final class UiSourceHit {
  const UiSourceHit({
    required this.source,
    required this.itemId,
    required this.kind,
    required this.title,
    this.work,
    this.episode,
    this.poster,
    this.workTitle,
    this.playable = false,
    this.reachable = true,
  });

  final UiSearchSource source;

  /// Its picture on this device, when the search had one: a work's
  /// poster; for an episode or a file, its own or its work's.
  final String? poster;

  /// The name of the library's work it is bound to.
  final String? workTitle;

  /// What the source calls it; never shown, and never a work's ID.
  final String itemId;
  final UiSourceHitKind kind;

  /// Its name there: the series', the episode's, the file's.
  final String title;

  /// The work it is, or the one it belongs to; null for a file no work
  /// holds yet.
  final UiWork? work;

  /// What plays, for an episode or a file of one.
  final UiEpisode? episode;

  /// It plays from here now. False is not “offline”: a share's state may be
  /// unknown ([reachable] still true), and a series is not played itself.
  final bool playable;

  /// False when the source could not be reached: what it held when last
  /// seen.
  final bool reachable;

  /// A server's item may have a picture to fetch; a share's file has none
  /// of its own.
  bool get hasArtwork =>
      source.kind == UiSourceKind.jellyfin || source.kind == UiSourceKind.emby;
}

/// The real searches, invoked as the interface (`origin: gui`):
///
/// - 片库: `media.library.search_merged`, the viewer's library across the
///   mesh by title, original title, other titles, year and episode titles;
///   its IDs open the work page and play.
/// - 在线: `media.metadata.search` on 弹弹play. A result the library has
///   names its library work.
/// - 来源: `media.sources.list` for the sources, then
///   `media.sources.search` for each one on its own; a picture it had not
///   cached, `media.sources.artwork`.
final class CoreSearch implements NextSearchData {
  /// [harness]: the runtime's, read at each call (it may come later).
  CoreSearch(this.harness);
  final Harness Function() harness;

  static const _limit = 12;
  static const _episodeLimit = 4;
  static const _searchable = {
    'jellyfin': UiSourceKind.jellyfin,
    'emby': UiSourceKind.emby,
    'smb': UiSourceKind.smb,
    'webdav': UiSourceKind.webdav,
  };

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

  static int? _int(Object? v) => v is int ? v : null;

  static List<Map> _maps(Object? v) =>
      v is List ? v.whereType<Map>().toList() : const [];

  @override
  Future<UiLibraryHits> library(String query) async {
    final result = await _call('media.library.search_merged', {
      'query': query,
      'limit': _limit,
      'episodeLimit': _episodeLimit,
    });
    return UiLibraryHits(works: [
      for (final w in _maps(result['works']))
        if (_work(w) case final work?) work,
    ], episodes: [
      for (final hit in _maps(result['episodes']))
        if (hit['work'] case final Map w)
          if (_work(w) case final work?)
            if (hit['episode'] case final Map e)
              if (_episode(e) case final episode?) (work, episode),
    ]);
  }

  /// A work of the merged catalogue as the library writes it (`workJson`):
  /// its counts, year and devices are the catalogue's own.
  static UiWork? _work(Map w) {
    final id = _text(w['workId']);
    if (id == null) return null;
    final art = w['artwork'] is Map ? w['artwork'] as Map : const {};
    return UiWork(
      workId: id,
      title: _text(w['title']) ?? '',
      originalTitle: _text(w['originalTitle']),
      year: _int(w['year']),
      genres: [
        for (final g in w['genres'] is List ? w['genres'] as List : const [])
          if (_text(g) case final genre?) genre
      ],
      episodeCount: _int(w['episodeCount']),
      studio: _text(w['studio']),
      overview: _text(w['overview']),
      ratings: [
        for (final r in _maps(w['ratings']))
          if ((_text(r['source']), r['value']) case (final s?, final num v))
            UiRating(s, v.toDouble())
      ],
      artwork: UiArtwork(
        backdrop: _text(art['backdrop']),
        poster: _text(art['poster']),
        logo: _text(art['logo']),
        tint: _int(art['tint']),
      ),
      next: w['next'] is Map ? _episode(w['next'] as Map) : null,
      devices: [
        for (final d in _maps(w['devices']))
          if (_device(d) case final device?) device
      ],
    );
  }

  static UiDevice? _device(Map d) => switch (_text(d['name'])) {
        final name? => UiDevice(name: name, online: d['online'] != false),
        null => null,
      };

  /// An episode as the library writes it (`episodeJson`); [playable]
  /// already says whether its device answers.
  static UiEpisode? _episode(Map e) {
    final id = _text(e['episodeId']), workId = _text(e['workId']);
    final number = _int(e['number']);
    if (id == null || workId == null || number == null) return null;
    final heat = e['heat'] is List ? e['heat'] as List : null;
    return UiEpisode(
      episodeId: id,
      workId: workId,
      number: number,
      season: _int(e['season']),
      title: _text(e['title']),
      runtime: switch (e['runtimeMs']) {
        final int ms when ms > 0 => Duration(milliseconds: ms),
        _ => null,
      },
      still: _text(e['still']),
      progress: (e['progress'] as num?)?.toDouble(),
      heat: heat?.whereType<num>().map((n) => n.toDouble()).toList(),
      playable: e['playable'] == true,
      device: e['device'] is Map ? _device(e['device'] as Map) : null,
    );
  }

  @override
  Future<List<UiWork>> online(String query) async {
    final result = await _call(
        'media.metadata.search', {'provider': 'dandanplay', 'query': query});
    return [
      for (final r in _maps(result['results']).take(_limit))
        if ((r['ref'] as Map?)?['externalId'] case final String external)
          UiWork(
            // In the library: its page there, not the found one.
            workId: _text(r['workId']) ?? Found.id('dandanplay', external),
            title: _text(r['title']) ?? '',
            originalTitle: _text(r['originalTitle']),
            year: _int(r['year']),
            overview: _text(r['overview']),
            artwork: UiArtwork(poster: _text(r['imageUrl'])),
          ),
    ];
  }

  @override
  Future<List<UiSearchSource>> sources() async {
    final result = await _call('media.sources.list', {});
    return [
      for (final s in _maps(result['sources']))
        if ((_text(s['sourceId']), _searchable[s['type']])
            case (final id?, final kind?))
          UiSearchSource(sourceId: id, name: _text(s['name']) ?? '', kind: kind)
    ];
  }

  @override
  Future<UiSourceAnswer> searchSource(UiSearchSource source, String query,
      {int limit = 6}) async {
    final result = await _call('media.sources.search', {
      'query': query,
      'sourceIds': [source.sourceId],
      'limit': limit,
    });
    final answer = _maps(result['sources'])
        .where((s) => s['sourceId'] == source.sourceId)
        .firstOrNull;
    if (answer == null) return const UiSourceAnswer([], failed: true);
    // A source that failed has no total: not “nothing there”. A share that
    // could not be reached still tells what it held; `unverified` is
    // unknown, not offline.
    final reachable = answer['connectionState'] != 'failed';
    return UiSourceAnswer([
      for (final e in _maps(answer['entries']))
        if (_hit(source, e, reachable: reachable) case final hit?) hit
    ], failed: answer['error'] != null || answer['total'] == null);
  }

  @override
  Future<String?> sourceArtwork(UiSourceHit hit) async => _text((await _call(
      'media.sources.artwork',
      {'sourceId': hit.source.sourceId, 'itemId': hit.itemId}))['poster']);

  /// A source's entry: a series or a film opens its page (the library's
  /// when bound, else the source's own); an episode, a video or a file of
  /// one plays; a file no work holds plays from the source by its item.
  static UiSourceHit? _hit(UiSearchSource source, Map e,
      {required bool reachable}) {
    final itemId = _text(e['itemId']);
    if (itemId == null) return null;
    final meta = e['metadata'] is Map ? e['metadata'] as Map : const {};
    final title = _text(e['title']) ?? '';
    final workId = _text(e['workId']) ?? _text(e['sourceWorkId']);
    final episodeId = _text(e['episodeId']) ?? _text(e['sourceEpisodeId']);
    final playable = e['playable'] == true && reachable;
    final poster = _text(e['poster']);
    final workTitle = _text(e['workTitle']);
    final kind = switch (e['kind']) {
      'Series' || 'Movie' => UiSourceHitKind.work,
      'File' => UiSourceHitKind.file,
      _ => UiSourceHitKind.episode,
    };
    if (kind == UiSourceHitKind.work) {
      if (workId == null) return null;
      return UiSourceHit(
        source: source,
        itemId: itemId,
        kind: kind,
        title: title,
        work: UiWork(
          workId: workId,
          title: title,
          originalTitle: _text(e['originalTitle']),
          year: _int(e['year']),
        ),
        poster: poster,
        workTitle: workTitle,
        reachable: reachable,
      );
    }
    // A file's work is known by its name when bound; its page reads the
    // rest.
    final series = workTitle ??
        _text(meta['SeriesName']) ??
        (kind == UiSourceHitKind.file ? null : title);
    final work = workId == null
        ? null
        : UiWork(workId: workId, title: series ?? '', year: _int(e['year']));
    return UiSourceHit(
      source: source,
      itemId: itemId,
      kind: kind,
      title: title,
      work: work,
      episode: work == null || episodeId == null
          ? null
          : UiEpisode(
              episodeId: episodeId,
              workId: work.workId,
              number: kind == UiSourceHitKind.episode
                  ? _int(meta['IndexNumber']) ?? 0
                  : 0,
              season: _int(meta['ParentIndexNumber']),
              title: title,
              playable: playable,
            ),
      poster: poster,
      workTitle: workTitle,
      playable: playable,
      reachable: reachable,
    );
  }
}
