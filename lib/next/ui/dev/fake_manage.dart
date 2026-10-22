part of 'fake_world.dart';

/// The scripted world's work management: matches, words and pictures,
/// works of their own, and each episode's danmaku, subtitles and files,
/// all kept in memory. `ext.nipaplay.nextui` `manage fail=` makes chosen
/// operations refuse (`conflict=true`: as if something changed between;
/// `stale=true`: the next match applied after its preview), to show how
/// the sheets say so. Previews, file places and file-manager answers are
/// made in the Actions' shapes and read by the same code as the real ones.
final class FakeManage implements NextWorkManage {
  FakeManage(this.world);
  final FakeWorld world;

  /// Operations that refuse: read, search, match, save, art, refresh,
  /// local, danmaku, subtitle, delete, confirm, reveal.
  final fail = <String>{};
  bool conflict = false;

  /// The next match or unmatch finds things changed since its preview.
  bool stale = false;

  /// What the last confirmed deletion removed, for the record.
  final deleted = <String>{};

  void _check(String op) {
    if (fail.contains(op)) throw UiManageError(conflict: conflict);
  }

  Future<void> _wait([int ms = 260]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void _changed() => world._changes.add(null);

  void _stale() {
    if (!stale) return;
    stale = false;
    throw const UiManageError(conflict: true);
  }

  // —— State ——

  final _text = <String, Map<UiTextField, String?>>{};
  final _art = <String, Map<UiArtKind, String?>>{};
  final _episodeTitles = <String, String?>{'fake:frieren:2': '启程之日'};
  final _unmatched = <String>{};
  final _matchedAs = <String, UiMatchCandidate>{};

  /// Raw files that became part of a work.
  final _absorbed = <String>{};
  final _locals = <String, _LocalWork>{
    'local:summer': _LocalWork('2024 夏天', [
      _LocalEpisode('1', '海边', [_home('VID_20240712_1830.mov')]),
      _LocalEpisode('2', '烟花大会', [_home('VID_20240713_2041.mov')]),
      _LocalEpisode('3', '回程的车上', [_home('VID_20240714_1702.mov')]),
    ]),
  };
  var _localCount = 0;
  final _danmaku = <String, List<_FakeTrack>>{};
  final _subtitles = <String, _FakeSubs>{};

  static String _home(String name) => '/Users/nipa/Movies/家庭录像/$name';

  /// The other devices' systems, for how they show a file.
  static const _platforms = {'工作站': 'windows', '旧笔记本': 'macos'};

  /// Places the library does not show: the first episode of 葬送的芙莉莲
  /// also kept in a backup folder here and on the workstation.
  static const _copies = <String, List<(String?, String)>>{
    'frieren:1': [
      (null, '/Users/nipa/Movies/备份'),
      ('工作站', r'D:\备份\动画'),
    ],
  };

  /// The copies of episode [n] of [key]: the same file in other folders.
  List<(String?, String)> _copiesOf(String key, int n) {
    final main = _allFiles(key, n).firstOrNull;
    if (main == null) return const [];
    return [
      for (final (device, folder) in _copies['$key:$n'] ?? const <(String?, String)>[])
        (
          device,
          '$folder${_platforms[device] == 'windows' ? '\\' : '/'}${main.name}'
        )
    ];
  }

  // —— What FakeWorld asks ——

  String? textOf(String key, UiTextField field, String? fallback) {
    final edits = _text[key];
    return edits != null && edits.containsKey(field) ? edits[field] : fallback;
  }

  String? artOf(String key, UiArtKind kind, String? fallback) {
    final edits = _art[key];
    return edits != null && edits.containsKey(kind) ? edits[kind] : fallback;
  }

  String? episodeTitle(String episodeId, String? fallback) =>
      _episodeTitles.containsKey(episodeId)
          ? _episodeTitles[episodeId]
          : fallback;

  bool gone(String key) =>
      _absorbed.contains(key) || (_locals[key]?.removed ?? false);

  bool owns(String key) => _locals.containsKey(key);

  List<String> get localKeys => [
        for (final e in _locals.entries)
          if (!e.value.removed) e.key
      ];

  bool fileDeleted(String episodeId) {
    final (key, n) = _split(episodeId);
    final paths = [
      for (final f in _allFiles(key, n)) f.path,
      for (final (device, path) in _copiesOf(key, n))
        if (device == null) path
    ];
    return paths.isNotEmpty && paths.every(deleted.contains);
  }

  UiWork localWork(String key) {
    final local = _locals[key]!;
    final episodes = localEpisodes(key);
    return UiWork(
      workId: 'fake:$key',
      title: textOf(key, UiTextField.title, local.title) ?? '未命名作品',
      overview: textOf(key, UiTextField.overview, null),
      originalTitle: textOf(key, UiTextField.originalTitle, null),
      year: 2024,
      genres: const ['家庭录像'],
      episodeCount: episodes.length,
      artwork: UiArtwork(
        backdrop: artOf(key, UiArtKind.backdrop, null),
        poster: artOf(key, UiArtKind.poster, null),
        logo: artOf(key, UiArtKind.logo, null),
        tint: 0xFF3E4A44,
      ),
      next: episodes.where((e) => (e.progress ?? 0) < 1).firstOrNull ??
          episodes.firstOrNull,
    );
  }

  List<UiEpisode> localEpisodes(String key) {
    final watched = world._watched[key] ?? const {};
    return [
      for (final (i, e) in _locals[key]!.episodes.indexed)
        UiEpisode(
          episodeId: 'fake:$key:${i + 1}',
          workId: 'fake:$key',
          number: int.tryParse(e.number),
          season: e.season ?? 1,
          title: e.title,
          runtime: Duration(minutes: 4 + (e.files.first.hashCode % 9).abs()),
          progress: watched[i + 1],
          playable: e.files.any((f) => !deleted.contains(f)),
        )
    ];
  }

  // —— Keys and files ——

  static String _keyOf(String workId) =>
      workId.startsWith('fake:') ? workId.substring(5) : workId;

  /// `fake:frieren:3` → (frieren, 3); `fake:raw:2:1` → (raw:2, 1).
  static (String, int) _split(String episodeId) {
    final parts = _keyOf(episodeId).split(':');
    return (parts.sublist(0, parts.length - 1).join(':'), int.parse(parts.last));
  }

  List<UiFile> _allFiles(String key, int n) {
    if (_locals[key] case final local?) {
      if (n < 1 || n > local.episodes.length) return const [];
      return [
        for (final path in local.episodes[n - 1].files)
            UiFile(
                path: path,
                size: 180000000 + (path.hashCode % 90).abs() * 4000000,
                duration: Duration(minutes: 4 + (path.hashCode % 9).abs()),
                modified: DateTime(2024, 7, 11 + n),
                handle: path)
      ];
    }
    if (key.startsWith('raw:')) {
      final i = int.parse(key.substring(4));
      final name = FakeLibrary._unrecognised[i];
      final path = i < 2 || i == 3
          ? '/Volumes/媒体/下载/$name.mkv'
          : '/Users/nipa/Movies/$name.mov';
      return [
          UiFile(
              path: path,
              size: 640000000 + i * 37000000,
              duration: Duration(minutes: 9 + i * 3),
              modified: DateTime(2026, 9, 2 + i),
              handle: path)
      ];
    }
    final m = (world._meta[key] ?? world._found[key]) as Map<String, dynamic>?;
    if (m == null) return const [];
    final name = (m['original'] as String?) ?? (m['title'] as String);
    final path = m['kind'] == 'movie'
        ? '/Volumes/媒体/电影/$name (${m['year']}).mkv'
        : '/Volumes/媒体/动画/${m['title']}/[Nipa] $name - '
            '${n.toString().padLeft(2, '0')} [1080p].mkv';
    final runtime = ((m['eps'] as List?)
            ?.cast<Map>()
            .where((e) => e['n'] == n)
            .firstOrNull?['runtime'] as int?) ??
        24;
    return [
      UiFile(
        path: path,
        size: 1100000000 + ((key.hashCode + n * 7919) % 500).abs() * 1000000,
        duration: Duration(minutes: runtime, seconds: 12),
        modified: DateTime(2024, 1, 3 + n % 25),
        handle: path,
      )
    ];
  }

  // —— Works ——

  UiMatchCandidate _candidate(String key, UiProvider provider,
      {bool current = false}) {
    final m = (world._meta[key] ?? world._found[key]) as Map<String, dynamic>?;
    return UiMatchCandidate(
      provider: provider,
      title: (m?['title'] as String?) ?? key,
      originalTitle: m?['original'] as String?,
      year: int.tryParse('${m?['year'] ?? ''}'),
      image: m?['poster'] == null ? null : '${world.dir}/${m!['poster']}',
      movie: m?['kind'] == 'movie',
      current: current,
      elsewhere: world._has(key),
      ref: {
        'provider': provider.name,
        'objectType': m?['kind'] == 'movie' ? 'movie' : 'tv',
        'externalId': key,
        'scope': ''
      },
    );
  }

  /// The devices with episode [n] of [key] (null: this one), and whether
  /// they answer now.
  Map<String?, bool> _holders(String key, int n) {
    final device = world._device(key, n);
    return {
      if (device == null) null: true else device.name: device.online,
      for (final (d, _) in _copiesOf(key, n)) d: d == null || world._online[d]!,
    };
  }

  /// Where on another device a file of the library is kept.
  static String _remotePath(String device, UiFile f) {
    final folder = f.folder.split('/').last;
    return _platforms[device] == 'windows'
        ? 'D:\\动画\\$folder\\${f.name}'
        : '/Users/nipa/Movies/$folder/${f.name}';
  }

  /// Every place of episode [n] of [key] on a device that answers, as
  /// `media.files.list` lists them.
  List<UiFile> _placesOf(String key, int n) {
    final files = _allFiles(key, n);
    final device = world._device(key, n)?.name;
    final places = <(String?, String, UiFile)>[
      for (final f in files)
        (device, device == null ? f.path : _remotePath(device, f), f),
      for (final (d, path) in _copiesOf(key, n)) (d, path, files.first),
    ];
    return [
      for (final (d, path, like) in places)
        if ((d == null || world._online[d]!) && !deleted.contains(path))
          UiFile.listed({
            'fileId': 'fake-file:$d:${like.path}',
            'path': path,
            'size': like.size,
            'durationMs': like.duration?.inMilliseconds,
            'modifiedAt': like.modified?.toIso8601String(),
            'bindings': const [],
            'episodes': const [],
          },
              device: d,
              manager:
                  UiFileManager.of(d == null ? 'macos' : _platforms[d]),
              handle: path)
    ];
  }

  /// Each file once per device: a second place of the same file is not
  /// another file.
  static List<UiFile> _distinct(Iterable<UiFile> places) {
    final seen = <String>{};
    return [
      for (final p in places)
        if (seen.add('${p.device}/${p.name}')) p
    ];
  }

  static List<String> _away(Map<String?, bool> holders) => [
        for (final h in holders.entries)
          if (!h.value)
            uiAway(const {'online': false, 'reason': 'source_device_offline'},
                h.key)!
      ];

  UiManagedEpisode _managed(String key, UiEpisode e, {String? number}) =>
      UiManagedEpisode(
        episode: e,
        number: number ?? '${e.number ?? ''}',
        season: e.season,
        title: e.title,
        titleEdited: _episodeTitles.containsKey(e.episodeId),
        files: _distinct(_placesOf(key, _split(e.episodeId).$2)),
        handle: e.episodeId,
      );

  @override
  Future<UiManagedWork> work(UiWork work) async {
    await _wait();
    _check('read');
    final key = _keyOf(work.workId);
    if (_locals.containsKey(key)) {
      return UiManagedWork(
        work: work,
        kind: UiWorkKind.local,
        text: _textFacts(key, work),
        art: _artFacts(key, work),
        episodes: [
          for (final (i, e) in localEpisodes(key).indexed)
            _managed(key, e, number: _locals[key]!.episodes[i].number)
        ],
        handle: key,
      );
    }
    if (key.startsWith('raw:')) {
      final episode = world.catalog.work(key).next!;
      return UiManagedWork(
        work: work,
        kind: UiWorkKind.files,
        episodes: [_managed(key, episode)],
        handle: key,
      );
    }
    final present = [
      for (final e in await world.episodes(work.workId))
        if (e.device != null || e.playable) e
    ];
    final holders = <String?, bool>{
      for (final e in present) ..._holders(key, _split(e.episodeId).$2)
    };
    final away = _away(holders);
    final reachable = [
      for (final h in holders.entries)
        if (h.value) h.key
    ];
    if (reachable.isEmpty) {
      return UiManagedWork(
          work: work,
          kind: UiWorkKind.loose,
          away: away,
          unavailable: away.first,
          handle: key);
    }
    final managed = [
      for (final e in present)
        if (_managed(key, e) case final m when m.files.isNotEmpty) m
    ];
    final matched = !_unmatched.contains(key);
    final candidate = _matchedAs[key] ?? _candidate(key, UiProvider.tmdb, current: true);
    return UiManagedWork(
      work: work,
      kind: matched ? UiWorkKind.matched : UiWorkKind.loose,
      match: matched
          ? UiMatch(
              provider: candidate.provider,
              title: candidate.title,
              year: candidate.year,
              image: candidate.image,
              candidate: candidate,
            )
          : null,
      text: _textFacts(key, work),
      art: _artFacts(key, work),
      episodes: managed,
      device: reachable.contains(null) ? null : reachable.first,
      away: away,
      handle: key,
    );
  }

  Map<UiTextField, UiText> _textFacts(String key, UiWork work) => {
        UiTextField.title: UiText(work.title,
            edited: _text[key]?.containsKey(UiTextField.title) ?? false),
        UiTextField.originalTitle: UiText(work.originalTitle,
            edited:
                _text[key]?.containsKey(UiTextField.originalTitle) ?? false),
        UiTextField.overview: UiText(work.overview,
            edited: _text[key]?.containsKey(UiTextField.overview) ?? false),
      };

  Map<UiArtKind, UiArt> _artFacts(String key, UiWork work) => {
        UiArtKind.backdrop: UiArt(work.artwork.backdrop,
            edited: _art[key]?.containsKey(UiArtKind.backdrop) ?? false),
        UiArtKind.poster: UiArt(work.artwork.poster,
            edited: _art[key]?.containsKey(UiArtKind.poster) ?? false),
        UiArtKind.logo: UiArt(work.artwork.logo,
            edited: _art[key]?.containsKey(UiArtKind.logo) ?? false),
      };

  // —— 匹配 ——

  @override
  Future<List<UiMatchCandidate>> search(
      UiProvider provider, String query) async {
    await _wait(420);
    _check('search');
    final q = query.trim().toLowerCase();
    final keys = [...world._meta.keys, ...world._found.keys];
    bool hit(String k) {
      final m = (world._meta[k] ?? world._found[k]) as Map;
      final title = '${m['title']}'.toLowerCase();
      final original = '${m['original'] ?? ''}'.toLowerCase();
      return title.contains(q) ||
          q.contains(title) ||
          (original.isNotEmpty && (original.contains(q) || q.contains(original)));
    }

    final hits = keys.where(hit).toList();
    if (q == '没有' || q == 'none') return const [];
    return [
      for (final k in hits.isEmpty ? keys.take(5) : hits.take(8))
        _candidate(k, provider)
    ];
  }

  @override
  Future<List<UiCandidateEpisode>> candidateEpisodes(
      UiMatchCandidate candidate) async {
    await _wait(300);
    _check('match');
    final key = candidate.ref['externalId'] as String;
    final m = world._meta[key] as Map<String, dynamic>?;
    if (m?['kind'] == 'movie') {
      return [UiCandidateEpisode.film({...candidate.ref})];
    }
    final total =
        (FakeWorld._overrides[key]?['episodes'] as int?) ?? (m?['episodes'] as int?) ?? 12;
    final names = {
      for (final e in (m?['eps'] as List? ?? const []).cast<Map>())
        e['n'] as int: e['name'] as String?
    };
    // TMDB's within its seasons as the library splits them, its specials
    // (season 0) after; the others' one list, by number.
    final tmdb = candidate.provider == UiProvider.tmdb;
    final seasons = tmdb ? (m?['seasons'] as int?) ?? 1 : 1;
    final perSeason = (total / seasons).ceil();
    UiCandidateEpisode one(int season, int number, String? title) =>
        UiCandidateEpisode(
          number: '$number',
          season: tmdb ? season : null,
          title: title,
          ref: {
            ...candidate.ref,
            'objectType': 'episode',
            'externalId': '$key-$season-$number',
            'scope': 'tv/$key/season/$season/episode/$number'
          },
          release: tmdb
              ? {
                  ...candidate.ref,
                  'objectType': 'season',
                  'scope': 'tv/$key/season/$season'
                }
              : null,
          seasons: tmdb,
        );
    return [
      for (var n = 1; n <= total; n++)
        one((n - 1) ~/ perSeason + 1, (n - 1) % perSeason + 1, names[n]),
      if (tmdb) one(0, 1, '总集篇'),
    ];
  }

  /// What `media.management.*_batch` would preview for [files] of [work]:
  /// the work, their episodes, the files with their progress, and the
  /// matches on them.
  Map<String, Object?> _impact(UiManagedWork work, Iterable<UiFile> files) {
    final key = work.handle as String;
    final watched = world._watched[key] ?? const <int, double>{};
    final sources = [
      if (work.match case final m?)
        {'provider': m.provider.name, 'status': 'accepted'}
    ];
    JsonMap entity(String id, String kind, {String? title}) =>
        {'id': id, 'kind': kind, 'attributes': {if (title != null) 'title': title}};
    return {
      'entities': [
        {
          'entity': entity('work:$key', 'work', title: work.work.title),
          'associations': const [],
          'sources': sources,
          'locations': const [],
          'progress': const [],
        },
        for (final e in work.episodes)
          if (e.files.any(files.contains)) ...[
            {
              'entity': entity('episode:${e.handle}', 'episode', title: e.title),
              'associations': const [],
              'sources': sources,
              'locations': const [],
              'progress': const [],
            },
            for (final f in e.files)
              if (files.contains(f))
                {
                  'entity': entity('file:${f.device}:${f.path}', 'file'),
                  'associations': const [],
                  'sources': const [],
                  'locations': [
                    {'locator': f.path}
                  ],
                  'progress': [
                    {
                      'watchProgress':
                          watched[_split(e.handle as String).$2],
                      'lastPosition': null,
                    }
                  ],
                }
          ],
      ],
      'diskFilesDeleted': false,
      'progressChanged': false,
    };
  }

  @override
  Future<UiAssociation> previewMatch(UiManagedWork work,
      UiMatchCandidate candidate, Map<UiFile, UiCandidateEpisode> files) async {
    await _wait(420);
    _check('match');
    return UiAssociation.fromPreviews([_impact(work, files.keys)],
        devices: {for (final f in files.keys) f.device}.toList(),
        apply: () => _match(work, candidate));
  }

  Future<void> _match(UiManagedWork work, UiMatchCandidate candidate) async {
    await _wait(500);
    _stale();
    _check('match');
    final key = work.handle as String;
    if (key.startsWith('raw:')) {
      _absorbed.add(key);
    } else {
      _unmatched.remove(key);
      _matchedAs[key] = UiMatchCandidate(
        provider: candidate.provider,
        title: candidate.title,
        originalTitle: candidate.originalTitle,
        year: candidate.year,
        image: candidate.image,
        ref: candidate.ref,
        current: true,
      );
    }
    _changed();
  }

  @override
  Future<UiAssociation> previewUnmatch(UiManagedWork work) async {
    await _wait(360);
    _check('match');
    return UiAssociation.fromPreviews([_impact(work, work.files)],
        devices: {for (final f in work.files) f.device}.toList(),
        apply: () async {
      await _wait();
      _stale();
      _check('match');
      _unmatched.add(work.handle as String);
      _matchedAs.remove(work.handle);
      _changed();
    });
  }

  // —— 本地作品 ——

  @override
  Future<String> createLocal(UiManagedWork from, String title) async {
    await _wait(400);
    _check('local');
    final key = 'local:new${++_localCount}';
    // Each episode as it is, with its files here.
    _locals[key] = _LocalWork(title, [
      for (final e in from.episodes)
        if ([
          for (final f in e.files)
            if (f.device == null) f
        ]
            case final files when files.isNotEmpty)
          _LocalEpisode(
              e.number,
              e.title ?? files.first.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
              [for (final f in files) f.path],
              season: e.season)
    ]);
    _absorbed.add(from.handle as String);
    _changed();
    return 'fake:$key';
  }

  @override
  Future<void> saveLocal(
      UiManagedWork work, List<UiLocalEpisodeEdit> edits) async {
    await _wait(400);
    _check('save');
    final local = _locals[work.handle as String]!;
    local.episodes
      ..clear()
      ..addAll([
        for (final e in edits)
          _LocalEpisode(e.number, e.title, [for (final f in e.files) f.path],
              season: e.season)
      ]);
    _changed();
  }

  @override
  Future<void> addFile(UiManagedWork work, String path) async {
    await _wait(400);
    _check('save');
    final local = _locals[work.handle as String]!;
    local.episodes.add(_LocalEpisode('${local.episodes.length + 1}',
        path.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), ''), [path]));
    _changed();
  }

  @override
  Future<UiUndo> removeLocal(UiManagedWork work,
      {UiManagedEpisode? episode}) async {
    await _wait(300);
    _check('local');
    final key = work.handle as String;
    final local = _locals[key]!;
    if (episode == null) {
      local.removed = true;
      _changed();
      return UiUndo(('work', key));
    }
    final index = _split(episode.handle as String).$2 - 1;
    final removed = local.episodes.removeAt(index);
    _changed();
    return UiUndo(('episode', key, index, removed));
  }

  @override
  Future<void> restore(UiUndo undo) async {
    await _wait();
    _check('local');
    switch (undo.handle) {
      case ('work', final String key):
        _locals[key]!.removed = false;
      case ('episode', final String key, final int index,
            final _LocalEpisode episode):
        _locals[key]!.episodes.insert(index, episode);
    }
    _changed();
  }

  // —— 资料与图片 ——

  @override
  Future<void> editText(
      UiManagedWork work, Map<UiTextField, String?> values) async {
    await _wait(360);
    _check('save');
    (_text[work.handle as String] ??= {}).addAll(values);
    _changed();
  }

  @override
  Future<void> editEpisodeTitles(Map<UiManagedEpisode, String?> titles) async {
    await _wait(360);
    _check('save');
    for (final e in titles.entries) {
      _episodeTitles[e.key.handle as String] = e.value;
    }
    _changed();
  }

  @override
  Future<void> clearEpisodeTitle(UiManagedEpisode episode) async {
    await _wait();
    _check('save');
    _episodeTitles.remove(episode.handle);
    _changed();
  }

  @override
  Future<void> clearText(UiManagedWork work, UiTextField field) async {
    await _wait();
    _check('save');
    _text[work.handle as String]?.remove(field);
    _changed();
  }

  @override
  Future<void> setArt(UiManagedWork work, UiArtKind kind, String file) async {
    await _wait(500);
    _check('art');
    (_art[work.handle as String] ??= {})[kind] = file;
    _changed();
  }

  @override
  Future<void> clearArt(UiManagedWork work, UiArtKind kind) async {
    await _wait();
    _check('art');
    _art[work.handle as String]?.remove(kind);
    _changed();
  }

  @override
  Future<void> refresh(UiManagedWork work) async {
    await _wait(400);
    _check('refresh');
  }

  // —— 剧集 ——

  List<_FakeTrack> _tracksOf(String episodeId) => _danmaku.putIfAbsent(
        episodeId,
        () {
          final (key, n) = _split(episodeId);
          if (!world._meta.containsKey(key)) return [];
          final title = (world._meta[key] as Map)['title'];
          final seed = (key.hashCode + n * 131).abs();
          return [
            _FakeTrack('弹弹play', '$title 第$n话', 900 + seed % 6200),
            if (n == 1) _FakeTrack('本地文件', null, 1268, removable: false),
            if (n == 3)
              _FakeTrack('B 站', '$title 第$n话', 4210,
                  offset: const Duration(milliseconds: 1500)),
          ];
        },
      );

  _FakeSubs _subsOf(String episodeId) => _subtitles.putIfAbsent(episodeId, () {
        final (_, n) = _split(episodeId);
        return _FakeSubs([
          const UiSubtitleTrack(
              id: 'embedded:0',
              kind: UiSubtitleKind.embedded,
              language: 'ja',
              format: 'ass'),
          const UiSubtitleTrack(
              id: 'sidecar:sc',
              kind: UiSubtitleKind.external,
              language: 'zh-Hans',
              title: '简中',
              format: 'ass'),
          if (n == 1)
            const UiSubtitleTrack(
                id: 'import:tc',
                kind: UiSubtitleKind.imported,
                language: 'zh-Hant',
                title: '繁中（自校）',
                format: 'srt'),
        ], detached: [
          if (n == 1) '/Users/nipa/Library/NipaPlay/subtitles/旧版简中.ass'
        ]);
      });

  @override
  Future<UiManagedEpisode> episode(UiWork work, UiEpisode episode) async {
    await _wait();
    _check('read');
    final (key, n) = _split(episode.episodeId);
    final holders = _holders(key, n);
    final reachable = [
      for (final h in holders.entries)
        if (h.value) h.key
    ];
    final device = reachable.contains(null) ? null : reachable.firstOrNull;
    final locations = _placesOf(key, n);
    final files =
        _distinct([for (final p in locations) if (p.device == device) p]);
    final subs = _subsOf(episode.episodeId);
    return UiManagedEpisode(
      episode: episode,
      number: '${episode.number ?? ''}',
      season: episode.season,
      title: episode.title,
      files: files,
      locations: locations,
      device: device,
      away: _away(holders),
      unavailable: reachable.isEmpty ? _away(holders).first : null,
      danmaku: [
        if (reachable.isNotEmpty)
          for (final t in _tracksOf(episode.episodeId))
            UiDanmakuTrack(
              source: t.source,
              name: t.name,
              count: t.loading ? null : t.count,
              enabled: t.enabled,
              offset: t.offset,
              loading: t.loading,
              removable: t.removable,
              handle: t,
            )
      ],
      subtitles: [
        for (final f in files)
          UiSubtitles(
            file: f,
            tracks: subs.tracks,
            selected: subs.explicit ? subs.selected : 'sidecar:sc',
            explicit: subs.explicit,
            detached: subs.detached,
            handle: subs,
          )
      ],
      handle: episode.episodeId,
    );
  }

  @override
  Future<void> setDanmaku(UiDanmakuTrack track,
      {bool? enabled, Duration? offset}) async {
    await _wait(180);
    _check('danmaku');
    final t = track.handle as _FakeTrack;
    if (enabled != null) t.enabled = enabled;
    if (offset != null) t.offset = offset;
  }

  @override
  Future<List<UiDanmakuCandidate>> searchDanmaku(String query) async {
    await _wait(480);
    _check('search');
    final number = int.tryParse(RegExp(r'(\d+)\s*$').firstMatch(query)?[1] ?? '');
    final title = query.replaceFirst(RegExp(r'\s*\d+\s*$'), '');
    if (title.isEmpty) return const [];
    return [
      for (final n in [number ?? 1, (number ?? 1) + 1])
        UiDanmakuCandidate(
            title: '$title 第$n话', source: '弹弹play', handle: n),
      UiDanmakuCandidate(
          title: '$title 总集篇', source: '弹弹play', handle: 0),
    ];
  }

  @override
  Future<void> addDanmaku(
      UiManagedEpisode episode, UiDanmakuCandidate found) async {
    await _wait(300);
    _check('danmaku');
    final track = _FakeTrack(found.source, found.title, 2300 + found.title.length * 97,
        loading: true);
    _tracksOf(episode.handle as String).add(track);
    Timer(const Duration(seconds: 3), () {
      track.loading = false;
      _changed();
    });
  }

  @override
  Future<void> importDanmaku(UiManagedEpisode episode, String path) async {
    await _wait(400);
    _check('danmaku');
    _tracksOf(episode.handle as String)
        .add(_FakeTrack('本地文件', path.split('/').last, 1876));
  }

  @override
  Future<void> removeDanmaku(UiDanmakuTrack track) async {
    await _wait();
    _check('danmaku');
    for (final list in _danmaku.values) {
      list.remove(track.handle);
    }
  }

  @override
  Future<void> selectSubtitle(UiSubtitles file, String? trackId) async {
    await _wait(180);
    _check('subtitle');
    final subs = file.handle as _FakeSubs;
    subs
      ..explicit = true
      ..selected = trackId;
  }

  @override
  Future<void> automaticSubtitle(UiSubtitles file) async {
    await _wait(180);
    _check('subtitle');
    final subs = file.handle as _FakeSubs;
    subs
      ..explicit = false
      ..selected = null;
  }

  @override
  Future<void> importSubtitle(UiSubtitles file, String path) async {
    await _wait(400);
    _check('subtitle');
    final subs = file.handle as _FakeSubs;
    subs.tracks.add(UiSubtitleTrack(
        id: 'import:${subs.tracks.length}',
        kind: UiSubtitleKind.imported,
        language: 'und',
        title: path.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        format: path.split('.').last));
  }

  @override
  Future<void> editSubtitle(UiSubtitles file, UiSubtitleTrack track,
      {String? language, String? title}) async {
    await _wait(220);
    _check('subtitle');
    final subs = file.handle as _FakeSubs;
    final i = subs.tracks.indexWhere((t) => t.id == track.id);
    subs.tracks[i] = UiSubtitleTrack(
        id: track.id,
        kind: track.kind,
        language: language ?? track.language,
        title: title ?? track.title,
        format: track.format);
  }

  @override
  Future<void> detachSubtitle(UiSubtitles file, UiSubtitleTrack track) async {
    await _wait(260);
    _check('subtitle');
    final subs = file.handle as _FakeSubs;
    subs.tracks.removeWhere((t) => t.id == track.id);
    if (subs.selected == track.id) {
      subs
        ..explicit = false
        ..selected = null;
    }
    subs.detached.add('/Users/nipa/Library/NipaPlay/subtitles/'
        '${track.title ?? track.id}.${track.format ?? 'ass'}');
  }

  @override
  Future<UiConfirm> deleteSubtitleCopies(UiSubtitles file) async {
    await _wait(200);
    _check('delete');
    final subs = file.handle as _FakeSubs;
    final paths = [...subs.detached];
    return UiConfirm(
      items: [for (final p in paths) p.split('/').last],
      run: () async {
        await _wait(300);
        _check('confirm');
        subs.detached.removeWhere(paths.contains);
      },
    );
  }

  @override
  Future<void> reveal(UiFile file) async {
    await _wait(120);
    debugPrint('[NextUi dev] reveal ${file.device ?? 'here'} ${file.path}');
    uiRevealed({
      'results': [
        fail.contains('reveal')
            ? {
                'index': 0,
                'requested': false,
                'error': {
                  'code': 'unavailable',
                  'message': 'System file manager rejected the request.'
                }
              }
            : {'index': 0, 'requested': true, 'mode': 'select_file'}
      ]
    });
  }

  @override
  Future<UiConfirm> deleteFile(UiFile file) async {
    await _wait(200);
    _check('delete');
    return UiConfirm(
      items: [file.name],
      run: () async {
        await _wait(400);
        _check('confirm');
        deleted.add(file.path);
        _changed();
      },
    );
  }

  /// Native pickers would steal focus from the quiet lab window: a sample
  /// of each kind instead.
  @override
  Future<String?> pickFile(List<String> kinds) async {
    await _wait(120);
    if (kinds.contains('png')) return '${world.dir}/frieren-backdrop2.jpg';
    if (kinds.contains('xml')) return '/Users/nipa/Downloads/第3话 弹幕.xml';
    if (kinds.contains('ass')) return '/Users/nipa/Downloads/繁中字幕.zh-Hant.ass';
    return _home('VID_20240715_1102.mov');
  }
}

final class _LocalWork {
  _LocalWork(this.title, this.episodes);
  final String title;
  final List<_LocalEpisode> episodes;
  bool removed = false;
}

final class _LocalEpisode {
  _LocalEpisode(this.number, this.title, this.files, {this.season});
  final String number;
  final String? title;
  final List<String> files;
  final int? season;
}

final class _FakeTrack {
  _FakeTrack(this.source, this.name, this.count,
      {this.offset = Duration.zero, this.removable = true, this.loading = false});
  final String source;
  final String? name;
  final int count;
  bool enabled = true;
  Duration offset;
  final bool removable;
  bool loading;
}

final class _FakeSubs {
  _FakeSubs(this.tracks, {required this.detached});
  final List<UiSubtitleTrack> tracks;
  final List<String> detached;
  bool explicit = false;
  String? selected;
}
