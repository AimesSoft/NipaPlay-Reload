part of 'fake_world.dart';

/// The 片库 page's sources for screenshots and experiments: this device
/// (everything, or Nipa's arrangement of it), a Jellyfin server with its
/// libraries and folders, an SMB share by folder, a WebDAV share of one
/// folder and an Emby server that cannot be reached. Over a thousand works, the sample posters reused.
final class FakeLibrary implements NextLibraryData, NextLibraryActions {
  FakeLibrary(this.world) {
    _sources = _build();
  }

  final FakeWorld world;
  late final List<_Source> _sources;
  final _categories = <String, _Category>{};

  /// What more works are made from: the library's samples, then 发现's.
  late final List<String> _bases = [...world._meta.keys, ...world._found.keys];

  static const _sorts = [
    UiSort('added', '最近添加'),
    UiSort('title', '名称'),
    UiSort('year', '年份'),
    UiSort('rating', '评分'),
  ];

  static const _suffixes = [
    ' 第二季',
    ' 剧场版',
    ' 第三季',
    ' OVA',
    ' 特别篇',
    ' 第四季',
    ' 总集篇',
    ' 外传',
    ' 续篇',
    ' 前传',
    ' 新篇',
    ' 完全版',
  ];

  /// Files on the share that nothing recognised: no pictures.
  static const _unrecognised = [
    '[字幕组] 未知作品 - 01',
    'VID_20240512_2130',
    '下载完成 (3)',
    'Episode 07 [1080p]',
    '新建文件夹 - 剪辑',
    '录屏 2026-09-30',
    '生日会',
    '毕业典礼',
    '旅行 Vlog',
  ];

  List<_Source> _build() {
    _Category c(String id, String title,
        {List<String> works = const [],
        List<_Category> folders = const [],
        int? tint}) {
      final category = _Category(id, title,
          works: [
            for (final k in works)
              if (_exists(k)) k
          ],
          folders: folders,
          tint: tint);
      return _categories[id] = category;
    }

    List<String> gen(int from, int count) =>
        [for (var n = from; n < from + count; n++) 'gen:$n'];
    final b = _bases.length;
    const here = FakeWorld._added;
    return [
      _Source('local', '本地', UiSourceKind.local, original: [
        c('local:all', '全部', works: [...here, ...gen(0, 1200)]),
      ], arrangement: [
        c('local:anime', '番剧', works: [
          for (final k in here)
            if (k != 'sintel' && k != 'changan') k,
          ...gen(0, 1200),
        ]),
        c('local:movies', '电影', works: ['sintel']),
        c('local:unfinished', '工作站上没看完的', works: ['lycoris', 'spyfamily']),
      ]),
      _Source('jellyfin', '客厅 Jellyfin', UiSourceKind.jellyfin,
          form: UiLibraryForm.cards,
          original: [
            c('jf:anime', '动画', works: gen(1200, 1100), folders: [
              c('jf:anime/new', '新番', works: [
                'frieren',
                'kusuriya',
                'dungeon',
                'oshinoko',
                'kaiju8',
                'yurucamp',
              ]),
              c('jf:anime/years', '按年份', folders: [
                for (final (i, year) in ['2024', '2023', '2022', '2019'].indexed)
                  c('jf:anime/years/$year', year, works: gen(2400 + i * 15, 15)),
              ]),
              c('jf:anime/classic', '经典', works: [
                'changan',
                'edgerunners',
              ], folders: [
                c('jf:anime/classic/kyoani', '京都动画',
                    works: ['violet', 'bocchi']),
              ]),
            ]),
            c('jf:movies', '电影', works: ['sintel', ...gen(b, b)]),
          ],
          arrangement: [
            c('jf:healing', '治愈系',
                works: ['violet', 'yurucamp', 'frieren', 'bocchi', 'spyfamily']),
            c('jf:hot', '热血',
                works: ['kaiju8', 'edgerunners', 'lycoris', 'dungeon']),
            c('jf:binge', '一口气看完',
                works: ['lycoris', 'edgerunners', 'oshinoko', ...gen(2500, 9)]),
          ]),
      _Source('smb', '家里的 NAS', UiSourceKind.smb, original: [
        c('smb:anime', '动画', works: gen(2600, 30), folders: [
          c('smb:anime/old', '旧番', works: gen(2630, 12)),
        ]),
        c('smb:movies', '电影', works: ['sintel', 'gen:${b + 3}']),
        c('smb:downloads', '下载',
            works: [for (var n = 0; n < 6; n++) 'raw:$n'], tint: 0xFF35506A),
        c('smb:recordings', '录像', works: [for (var n = 5; n < 9; n++) 'raw:$n']),
      ]),
      _Source('webdav', '网盘', UiSourceKind.webdav, original: [
        c('dav:series', '剧集', works: gen(2700, 40)),
      ]),
      _Source('emby', '书房 Emby', UiSourceKind.emby,
          online: false,
          original: [
            c('emby:movies', '电影', works: gen(b * 2, 8)),
          ]),
    ];
  }

  /// Without the 发现 samples the workstation's own works do not exist.
  bool _exists(String key) =>
      key.startsWith('gen:') || key.startsWith('raw:') || world._has(key);

  bool owns(String key) => key.startsWith('gen:') || key.startsWith('raw:');

  UiWork work(String key) => switch (key.split(':')) {
        ['gen', final n] => _generated(int.parse(n)),
        ['raw', final n] => _unrecognisedWork(int.parse(n)),
        _ => world._detailed(key),
      };

  List<UiEpisode> episodes(String key) {
    if (key.startsWith('raw:')) return [work(key).next!];
    final base = _bases[int.parse(key.substring(4)) % _bases.length];
    return world._meta.containsKey(base)
        ? world._episodesOf(base)
        : [for (var n = 1; n <= 12; n++) world._episode(base, n)];
  }

  /// Another season, film or special of a sample, under its poster.
  UiWork _generated(int n) {
    final base = _bases[n % _bases.length];
    final round = n ~/ _bases.length;
    final from = world._meta.containsKey(base)
        ? world.sample(base)
        : world._broughtWork(base, null);
    final again = round ~/ _suffixes.length;
    return UiWork(
      workId: 'fake:gen:$n',
      title: '${from.title}${_suffixes[round % _suffixes.length]}'
          '${again == 0 ? '' : ' ${again + 1}'}',
      originalTitle: from.originalTitle,
      year: from.year == null ? null : from.year! - round % 9,
      genres: from.genres,
      episodeCount: from.episodeCount ?? 12,
      studio: from.studio,
      overview: from.overview,
      ratings: [
        for (final r in from.ratings)
          UiRating(r.source, (r.value - round % 7 * 0.2).clamp(5.0, 9.9))
      ],
      artwork: from.artwork,
      next: from.next,
    );
  }

  UiWork _unrecognisedWork(int n) => UiWork(
        workId: 'fake:raw:$n',
        title: _unrecognised[n],
        episodeCount: 1,
        next: UiEpisode(
            episodeId: 'fake:raw:$n:1',
            workId: 'fake:raw:$n',
            number: 1,
            playable: true),
      );

  _Source _source(String id) => _sources.firstWhere((s) => s.id == id);

  /// The works of [c] in its current order (cached per order).
  List<String> _ordered(_Category c) => c.orders[c.sort] ??= () {
        if (c.sort == 'added') return c.works;
        final facts = {for (final k in c.works) k: work(k)};
        int compare(String a, String b) {
          final x = facts[a]!, y = facts[b]!;
          return switch (c.sort) {
            'title' => x.title.compareTo(y.title),
            'year' => (y.year ?? 0).compareTo(x.year ?? 0),
            _ => (y.ratings.firstOrNull?.value ?? 0)
                .compareTo(x.ratings.firstOrNull?.value ?? 0),
          };
        }

        return [...c.works]..sort(compare);
      }();

  /// Up to three posters for a cover: its own works first, then inside its
  /// folders.
  List<String> _posters(_Category c) {
    final found = <String>[];
    for (final k in c.works) {
      final poster = work(k).artwork.poster;
      if (poster != null && !found.contains(poster)) found.add(poster);
      if (found.length == 3) return found;
    }
    for (final f in c.folders) {
      for (final poster in _posters(f)) {
        if (!found.contains(poster)) found.add(poster);
        if (found.length == 3) return found;
      }
    }
    return found;
  }

  UiFolderItem _folder(_Category f) => UiFolderItem(
      categoryId: f.id,
      title: f.title,
      count: f.folders.length + f.works.length,
      posters: _posters(f));

  List<UiLibraryItem> _slice(_Category c, int offset, int limit) {
    final folders = [for (final f in c.folders) _folder(f)];
    final works = _ordered(c);
    final end = math.min(offset + limit, folders.length + works.length);
    return [
      for (var i = offset; i < end; i++)
        i < folders.length
            ? folders[i]
            : UiWorkItem(work(works[i - folders.length]))
    ];
  }

  UiCategory _view(_Category c, {required bool preview}) {
    final first = c.works.isEmpty ? null : work(c.works.first);
    return UiCategory(
      categoryId: c.id,
      title: c.title,
      count: c.folders.length + c.works.length,
      posters: _posters(c),
      backdrop: [
        for (final k in c.works.take(6))
          if (work(k).artwork.backdrop case final b?) b
      ].firstOrNull,
      tint: c.tint ?? first?.artwork.tint,
      preview: preview ? _slice(c, 0, 20) : const [],
      sorts: [
        for (final s in _sorts)
          if (s.id == c.sort) s,
        for (final s in _sorts)
          if (s.id != c.sort) s,
      ],
    );
  }

  @override
  Future<List<UiLibrarySource>> sources() async => [
        for (final s in _sources)
          UiLibrarySource(
              sourceId: s.id, name: s.name, kind: s.kind, online: s.online)
      ];

  @override
  Future<UiLibraryPage> page(String sourceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final s = _source(sourceId);
    return UiLibraryPage(
      form: s.form,
      arranged: s.arranged,
      hasArrangement: s.arrangement != null,
      categories: [
        for (final c in s.shown)
          _view(c, preview: s.form == UiLibraryForm.shelves)
      ],
      hiddenCategories: [
        if (!s.arranged) for (final c in s.hidden) _view(c, preview: false)
      ],
    );
  }

  @override
  Future<UiSlice> items(String categoryId,
      {int offset = 0, int limit = 60, String? sort}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final c = _categories[categoryId]!;
    if (sort != null) c.sort = sort;
    return UiSlice(_slice(c, offset, limit),
        total: c.folders.length + c.works.length);
  }

  @override
  Stream<void> get changes => world._changes.stream;

  @override
  Future<void> setForm(String sourceId, UiLibraryForm form) async {
    _source(sourceId).form = form;
    world._changes.add(null);
  }

  @override
  Future<void> useOriginal(String sourceId, bool original) async {
    _source(sourceId).arranged = !original;
    world._changes.add(null);
  }

  @override
  Future<void> moveCategory(String categoryId, int index) async {
    final shown = _sources.firstWhere((s) => s.shownIds.contains(categoryId));
    final list = shown.shown;
    final c = list.firstWhere((c) => c.id == categoryId);
    list
      ..remove(c)
      ..insert(index.clamp(0, list.length), c);
    world._changes.add(null);
  }

  /// Original categories only hide; arranged ones go.
  @override
  Future<void> removeCategory(String categoryId) async {
    for (final s in _sources) {
      final i = s.shown.indexWhere((c) => c.id == categoryId);
      if (i < 0) continue;
      final c = s.shown.removeAt(i);
      if (!s.arranged) s.hidden.add(c);
    }
    world._changes.add(null);
  }

  @override
  Future<void> restoreCategory(String categoryId) async {
    for (final s in _sources) {
      final i = s.hidden.indexWhere((c) => c.id == categoryId);
      if (i >= 0) s.original.add(s.hidden.removeAt(i));
    }
    world._changes.add(null);
  }
}

final class _Source {
  _Source(this.id, this.name, this.kind,
      {required List<_Category> original,
      List<_Category>? arrangement,
      this.online = true,
      this.form = UiLibraryForm.shelves})
      : original = [...original],
        arrangement = arrangement == null ? null : [...arrangement];
  final String id;
  final String name;
  final UiSourceKind kind;
  final bool online;
  final List<_Category> original;
  final List<_Category>? arrangement;
  UiLibraryForm form;
  bool arranged = false;
  final hidden = <_Category>[];

  List<_Category> get shown => arranged ? arrangement! : original;
  Iterable<String> get shownIds => shown.map((c) => c.id);
}

final class _Category {
  _Category(this.id, this.title,
      {required this.works, required this.folders, this.tint});
  final String id;
  final String title;
  final List<String> works;
  final List<_Category> folders;
  final int? tint;
  String sort = 'added';

  /// Its works in each order asked for so far.
  final orders = <String, List<String>>{};
}
