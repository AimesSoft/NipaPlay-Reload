part of 'fake_world.dart';

/// The search panel's groups over the scripted world: the library (its
/// works, then this device's other seasons and films, and episode titles);
/// online, 发现's works and the library's own (some by another name, which
/// that cannot be reached. Each answers after its own delay; [failing] ones
/// fail on demand. What the library has comes with its picture and its
/// work's name; a server's other items have theirs fetched on request.
final class FakeSearch implements NextSearchData {
  FakeSearch(this.world);
  final FakeWorld world;

  /// What fails (`search fail=`): `library`, `online`, `sources` (their
  /// list), `artwork` (fetching a source's picture) or a source by its ID.
  final failing = <String>{};

  static bool _matches(UiWork w, String q) =>
      w.title.toLowerCase().contains(q) ||
      (w.originalTitle?.toLowerCase().contains(q) ?? false);

  Future<void> _answer(String group, int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (failing.contains(group)) {
      throw StateError('scripted $group failure');
    }
  }

  @override
  Future<UiLibraryHits> library(String query) async {
    await _answer('library', 140);
    final q = query.toLowerCase();
    final works = <UiWork>[
      for (final key in FakeWorld._added)
        if (world._has(key) && _matches(world._detailed(key), q))
          world._detailed(key),
    ];
    // Then a few of this device's other seasons and films of those.
    final bases = world.catalog._bases;
    var more = 0;
    for (final key in world.catalog._categories['local:all']!.works) {
      if (more >= 3) break;
      if (!key.startsWith('gen:')) continue;
      if (!world._has(bases[int.parse(key.substring(4)) % bases.length])) {
        continue;
      }
      final w = world.catalog.work(key);
      if (_matches(w, q)) {
        works.add(w);
        more++;
      }
    }
    final episodes = <(UiWork, UiEpisode)>[
      for (final key in FakeWorld._added)
        if (world._meta.containsKey(key))
          for (final e in world._episodesOf(key))
            if (e.title?.toLowerCase().contains(q) ?? false)
              (world._detailed(key), e),
    ];
    return UiLibraryHits(works: works, episodes: episodes);
  }

  /// What 弹弹play calls some of the library's works: found by these, they
  /// still open their library page.
  static const _onlineTitles = {
    'spyfamily': '间谍家家酒',
    'kusuriya': '药师少女的独语',
    'edgerunners': '电驭叛客：边缘行者',
  };

  @override
  Future<List<UiWork>> online(String query) async {
    await _answer('online', 650);
    final q = query.toLowerCase();
    UiWork known(String key) {
      final w = world.sample(key);
      return UiWork(
        workId: w.workId,
        title: _onlineTitles[key] ?? w.title,
        originalTitle: w.originalTitle,
        year: w.year,
        artwork: UiArtwork(poster: w.artwork.poster),
      );
    }

    return [
      for (final key in FakeWorld._added)
        if (world._has(key))
          if (known(key) case final w when _matches(w, q)) w,
      for (final key in world._found.keys)
        if (!world._has(key))
          if (world._discovered(key)?.work case final w? when _matches(w, q)) w,
    ];
  }

  @override
  Future<List<UiSearchSource>> sources() async {
    await _answer('sources', 60);
    return [
      for (final s in world.catalog._sources)
        if (s.kind != UiSourceKind.local)
          UiSearchSource(sourceId: s.id, name: s.name, kind: s.kind),
    ];
  }

  static const _delays = {
    'smb': 380,
    'webdav': 520,
  };

  @override
  Future<UiSourceAnswer> searchSource(UiSearchSource source, String query,
      {int limit = 6}) async {
    await Future<void>.delayed(
        Duration(milliseconds: _delays[source.sourceId] ?? 600));
    final q = query.toLowerCase();
    final fails = failing.contains(source.sourceId);
    final hits = _files(source, q, reachable: !fails);
    return UiSourceAnswer(hits.take(limit).toList(), failed: fails);
  }

  Iterable<String> _keys(String sourceId) {
    final keys = <String>{};
    void walk(_Category c) {
      keys.addAll(c.works);
      c.folders.forEach(walk);
    }

    world.catalog._source(sourceId).original.forEach(walk);
    // The works the library has first.
    return [
      ...keys.where((k) => !world.catalog.owns(k)),
      ...keys.where(world.catalog.owns),
    ];
  }

  /// A share's files by name: the recognised ones are an episode of their
  /// work (with its name, and its poster when the library has it); the
  /// others are in no work and play from the share. The WebDAV share was
  /// never checked: whether it plays is unknown.
  Iterable<UiSourceHit> _files(UiSearchSource source, String q,
      {required bool reachable}) sync* {
    final playable = reachable &&
        world.catalog._source(source.sourceId).online &&
        source.kind == UiSourceKind.smb;
    for (final key in _keys(source.sourceId)) {
      final w = world.catalog.work(key);
      final raw = key.startsWith('raw:');
      final video = w.title.startsWith('VID') || w.title.startsWith('录屏');
      final name =
          raw ? '${w.title}${video ? '.mp4' : '.mkv'}' : '${w.title} - 01.mkv';
      // An index of names: nothing else is known of a file.
      if (!name.toLowerCase().contains(q)) continue;
      if (raw) {
        yield UiSourceHit(
          source: source,
          itemId: '/下载/$name',
          kind: UiSourceHitKind.file,
          title: name,
          playable: playable,
          reachable: reachable,
        );
        continue;
      }
      final first = world.catalog.owns(key)
          ? world.catalog.episodes(key).first
          : world._episodesOf(key).first;
      yield UiSourceHit(
        source: source,
        itemId: '/动画/$name',
        kind: UiSourceHitKind.file,
        title: name,
        work: UiWork(workId: w.workId, title: w.title),
        episode: UiEpisode(
            episodeId: first.episodeId,
            workId: w.workId,
            number: null,
            title: name,
            playable: playable),
        poster: world.catalog.owns(key) ? w.artwork.poster : null,
        workTitle: w.title,
        playable: playable,
        reachable: reachable,
      );
    }
  }
}
