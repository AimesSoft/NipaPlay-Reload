part of 'fake_world.dart';

/// The search panel's groups over the scripted world: the library (its
/// works, then this device's other seasons and films, and episode titles),
/// 发现's works it does not have, and the reachable sources' works. Each
/// answers after its own delay; [failing] groups fail on demand.
final class FakeSearch implements NextSearchData {
  FakeSearch(this.world);
  final FakeWorld world;

  /// `library`, `online`, `sources`: these fail (`search fail=`).
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

  @override
  Future<List<UiWork>> online(String query) async {
    await _answer('online', 650);
    final q = query.toLowerCase();
    return [
      for (final key in world._found.keys)
        if (!world._has(key))
          if (world._discovered(key)?.work case final w? when _matches(w, q)) w,
    ];
  }

  @override
  Future<List<UiSourceHit>>? sources(String query) => _sources(query);

  Future<List<UiSourceHit>> _sources(String query) async {
    await _answer('sources', 950);
    final q = query.toLowerCase();
    final hits = <UiSourceHit>[];
    // A few from each reachable source, its named works first.
    for (final source in world.catalog._sources) {
      if (source.kind == UiSourceKind.local || !source.online) continue;
      final keys = <String>{};
      void walk(_Category c) {
        keys.addAll(c.works);
        c.folders.forEach(walk);
      }

      source.original.forEach(walk);
      final found = [
        for (final key in [
          ...keys.where((k) => !world.catalog.owns(k)),
          ...keys.where(world.catalog.owns),
        ])
          if (world.catalog.work(key) case final w when _matches(w, q)) w,
      ];
      hits.addAll([
        for (final w in found.take(2))
          UiSourceHit(w, source: source.name, kind: source.kind)
      ]);
    }
    return hits;
  }
}
