import 'package:nipa_harness/nipa_harness.dart';

import '../media/presentation.dart';

/// Someone a provider knows: a TMDB person or a Bangumi person.
typedef UiPersonRef = ({String provider, String id});

/// A person as a work's page lists them: who, as what, and their picture.
final class UiCredit {
  const UiCredit({required this.name, this.role, this.image, this.person});
  final String name;

  /// The character played, or the job (“导演 · 编剧”).
  final String? role;
  final String? image;
  final UiPersonRef? person;

  JsonMap toJson() => {
        'name': name,
        if (role != null) 'role': role,
        if (image != null) 'image': image,
        if (person case final p?)
          'person': {'provider': p.provider, 'id': p.id},
      };

  static UiCredit fromJson(Map json) => UiCredit(
        name: json['name'] as String,
        role: json['role'] as String?,
        image: json['image'] as String?,
        person: switch (json['person']) {
          {'provider': final String provider, 'id': final String id} => (
              provider: provider,
              id: id
            ),
          _ => null,
        },
      );
}

/// A character of the work, with who voices or plays it.
final class UiCharacter {
  const UiCharacter(
      {required this.name, this.role, this.image, this.actors = const []});
  final String name;

  /// 主角, 配角…
  final String? role;
  final String? image;
  final List<UiCredit> actors;

  JsonMap toJson() => {
        'name': name,
        if (role != null) 'role': role,
        if (image != null) 'image': image,
        if (actors.isNotEmpty) 'actors': [for (final a in actors) a.toJson()],
      };

  static UiCharacter fromJson(Map json) => UiCharacter(
        name: json['name'] as String,
        role: json['role'] as String?,
        image: json['image'] as String?,
        actors: [
          for (final a in (json['actors'] as List? ?? const []).cast<Map>())
            UiCredit.fromJson(a)
        ],
      );
}

/// A line of the facts table: “首播” “2024-04-06”.
typedef UiFact = ({String label, String value});

/// A page elsewhere about the work: “TMDB”, “Bangumi”, “官网”.
typedef UiLink = ({String label, String url});

/// The TMDB object whose pictures the page's gallery shows, read when the
/// gallery comes into view.
typedef UiGalleryRef = ({String objectType, String id});

/// Pictures of a work: wide stills and backdrops, and posters.
final class UiGallery {
  const UiGallery({this.wide = const [], this.posters = const []});
  final List<String> wide;
  final List<String> posters;
  bool get isEmpty => wide.isEmpty && posters.isEmpty;
}

/// What a work's page shows below its episodes, read when the page opens.
/// Built from what the work's sources say (see [buildWorkMore]), by the
/// rule the page follows ([PresentationRule]).
final class UiWorkMore {
  const UiWorkMore({
    this.sections = const [],
    this.characters = const [],
    this.cast = const [],
    this.crew = const [],
    this.gallery,
    this.facts = const [],
    this.tags = const [],
    this.links = const [],
  });

  /// Sections to lay out, in order; a section without entries is left out.
  final List<String> sections;
  final List<UiCharacter> characters;
  final List<UiCredit> cast;
  final List<UiCredit> crew;
  final UiGalleryRef? gallery;
  final List<UiFact> facts;
  final List<String> tags;
  final List<UiLink> links;

  static const empty = UiWorkMore();

  bool get hasContent =>
      characters.isNotEmpty ||
      cast.isNotEmpty ||
      crew.isNotEmpty ||
      facts.isNotEmpty ||
      tags.isNotEmpty ||
      links.isNotEmpty;

  static UiWorkMore fromJson(Map json) => UiWorkMore(
        sections: (json['sections'] as List? ?? const []).cast<String>(),
        characters: [
          for (final c in (json['characters'] as List? ?? const []).cast<Map>())
            UiCharacter.fromJson(c)
        ],
        cast: [
          for (final c in (json['cast'] as List? ?? const []).cast<Map>())
            UiCredit.fromJson(c)
        ],
        crew: [
          for (final c in (json['crew'] as List? ?? const []).cast<Map>())
            UiCredit.fromJson(c)
        ],
        gallery: switch (json['gallery']) {
          {'objectType': final String type, 'id': final String id} => (
              objectType: type,
              id: id
            ),
          _ => null,
        },
        facts: [
          for (final f in (json['facts'] as List? ?? const []).cast<Map>())
            (label: f['label'] as String, value: f['value'] as String)
        ],
        tags: (json['tags'] as List? ?? const []).cast<String>(),
        links: [
          for (final l in (json['links'] as List? ?? const []).cast<Map>())
            (label: l['label'] as String, url: l['url'] as String)
        ],
      );
}

/// The page's sections from a work's merged metadata (`fields`, `sources`,
/// `presentation`, as `IdentityStore.mergedMetadata` returns it, or a found
/// work's `details`). Pure, so it runs where the metadata already is (the
/// library's worker); its output is small whatever the sources hold.
JsonMap buildWorkMore(Map metadata, {bool film = false}) {
  final fields = (metadata['fields'] as Map?) ?? const {};
  final sources = [
    for (final s in (metadata['sources'] as List? ?? const []).whereType<Map>())
      if (s['fields'] is Map) s
  ];
  final rule =
      PresentationRule.tryParse((metadata['presentation'] as Map?)?['rule']) ??
          const PresentationRule();

  // The work-level object of a provider (not a season or an episode).
  Map? source(String provider) {
    const kinds = {'tv', 'movie', 'subject', 'anime'};
    for (final s in sources) {
      if (s['provider'] == provider && kinds.contains(s['objectType'])) {
        return s['fields'] as Map;
      }
    }
    return null;
  }

  final tmdb = source('tmdb');
  final bangumi = source('bangumi');
  final dandanplay = source('dandanplay');
  final nativeSource = source('https://sources.nipaplay.app');
  // Fields of a single found record live in its one source.
  Object? field(String name) =>
      fields[name] ??
      [tmdb, bangumi, dandanplay].map((f) => f?[name]).firstWhere(
          (v) =>
              v != null && v != '' && v is! List || v is List && v.isNotEmpty,
          orElse: () => null);

  // ---- people ----
  final peopleOrder = rule.sourcesFor('people');
  List<JsonMap> castOf(String provider) => switch (provider) {
        'tmdb' => _tmdbCast(tmdb),
        'bangumi' => _bangumiVoices(bangumi),
        'https://sources.nipaplay.app' => _sourceCredits(nativeSource, 'cast'),
        _ => const [],
      };
  List<JsonMap> crewOf(String provider) => switch (provider) {
        'tmdb' => _tmdbCrew(tmdb, fields['creators'] ?? tmdb?['creators']),
        'bangumi' => _bangumiStaff(bangumi),
        'https://sources.nipaplay.app' => _sourceCredits(nativeSource, 'crew'),
        _ => const [],
      };
  List<JsonMap> first(List<JsonMap> Function(String) of) {
    for (final provider in [...peopleOrder, 'tmdb', 'bangumi', 'https://sources.nipaplay.app']) {
      final list = of(provider);
      if (list.isNotEmpty) return list;
    }
    return const [];
  }

  final characters = _bangumiCharacters(bangumi);
  final cast = first(castOf);
  final crew = first(crewOf);

  // ---- sections ----
  final explicit = rule.sections;
  final sections = [
    for (final s in explicit ?? PresentationRule.sectionIds)
      // By default a work's characters, with who voices them, stand for its
      // cast: the same people would otherwise be listed twice.
      if (explicit != null || s != 'cast' || characters.isEmpty) s
  ];

  final tmdbRef = [
    for (final s in sources)
      if (s['provider'] == 'tmdb' &&
          (s['objectType'] == 'tv' || s['objectType'] == 'movie'))
        (s['objectType'] as String, '${s['externalId']}')
  ].firstOrNull;

  return {
    'sections': sections,
    'characters': characters.take(rule.limit('characters')).toList(),
    'cast': cast.take(rule.limit('cast')).toList(),
    'crew': crew.take(rule.limit('crew')).toList(),
    if (tmdbRef != null)
      'gallery': {'objectType': tmdbRef.$1, 'id': tmdbRef.$2},
    'facts': _facts(field, fields, tmdb, bangumi, film: film),
    'tags': _tags(field('tags')),
    'links': _links(sources, tmdb, dandanplay, fields),
  };
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String? _bangumiImage(Object? images) => images is Map
    ? _text(images['medium']) ?? _text(images['large']) ?? _text(images['grid'])
    : null;

JsonMap? _person(String provider, Object? id) =>
    id == null ? null : {'provider': provider, 'id': '$id'};

List<JsonMap> _sourceCredits(Map? fields, String kind) => [
  for (final p in (((fields?['credits'] as Map?)?[kind]) as List? ?? const []).whereType<Map>())
    if (_text(p['name']) case final name?)
      {'name': name, if (_text(p['role']) case final role?) 'role': role},
];

List<JsonMap> _tmdbCast(Map? fields) {
  final cast = (fields?['credits'] as Map?)?['cast'];
  if (cast is! List) return const [];
  final seen = <String>{};
  return [
    for (final p in cast.whereType<Map>())
      if (_text(p['name']) case final name?)
        if (seen.add('${p['id'] ?? name}'))
          {
            'name': name,
            if (_text(p['role']) case final role?) 'role': role,
            if (_text(p['imageUrl']) case final image?) 'image': image,
            if (_person('tmdb', p['id']) case final person?) 'person': person,
          }
  ];
}

/// TMDB's jobs as the page names them, in the order they are listed.
const _jobs = <String, String>{
  'Director': '导演',
  'Series Director': '导演',
  'Original Story': '原作',
  'Original Concept': '原作',
  'Novel': '原作',
  'Comic Book': '原作',
  'Author': '原作',
  'Characters': '原作',
  'Series Composition': '系列构成',
  'Screenplay': '编剧',
  'Writer': '编剧',
  'Teleplay': '编剧',
  'Character Designer': '角色设计',
  'Animation Director': '作画监督',
  'Chief Animation Director': '总作画监督',
  'Original Music Composer': '音乐',
  'Music': '音乐',
  'Director of Photography': '摄影',
  'Art Direction': '美术',
  'Art Director': '美术',
  'Editor': '剪辑',
  'Sound Director': '音响监督',
  'Executive Producer': '执行制片',
  'Producer': '制片',
};

List<JsonMap> _tmdbCrew(Map? fields, Object? creators) {
  final crew = (fields?['credits'] as Map?)?['crew'];
  final byPerson = <String, JsonMap>{};
  final ranks = <String, int>{};
  final labels = _jobs.values.toSet().toList();
  void add(String key, String name, String label, Object? id, Object? image) {
    final rank = labels.indexOf(label);
    final entry = byPerson.putIfAbsent(key, () {
      ranks[key] = rank;
      return {
        'name': name,
        'roles': <String>[],
        if (_text(image) case final i?) 'image': i,
        if (_person('tmdb', id) case final p?) 'person': p,
      };
    });
    final roles = entry['roles'] as List<String>;
    if (!roles.contains(label)) roles.add(label);
    if (rank < ranks[key]!) ranks[key] = rank;
  }

  if (creators is List) {
    for (final c in creators.whereType<Map>()) {
      if (_text(c['name']) case final name?) {
        add(
            '${c['id'] ?? name}',
            name,
            '主创',
            c['id'],
            c['profile_path'] == null
                ? null
                : 'https://image.tmdb.org/t/p/w185${c['profile_path']}');
      }
    }
  }
  if (crew is List) {
    for (final p in crew.whereType<Map>()) {
      final name = _text(p['name']);
      if (name == null) continue;
      for (final job in '${p['role'] ?? ''}'.split(' / ')) {
        if (_jobs[job.trim()] case final label?) {
          add('${p['id'] ?? name}', name, label, p['id'], p['imageUrl']);
        }
      }
    }
  }
  final keys = byPerson.keys.toList()
    ..sort((a, b) => ranks[a]!.compareTo(ranks[b]!));
  return [
    for (final key in keys)
      {
        for (final e in byPerson[key]!.entries)
          if (e.key != 'roles') e.key: e.value,
        'role': (byPerson[key]!['roles'] as List<String>).join(' · '),
      }
  ];
}

List<JsonMap> _bangumiStaff(Map? fields) {
  final staff = fields?['staff'];
  if (staff is! List) return const [];
  final byPerson = <String, JsonMap>{};
  for (final p in staff.whereType<Map>()) {
    final name = _text(p['name']);
    if (name == null) continue;
    final key = '${p['id'] ?? name}';
    final entry = byPerson.putIfAbsent(
        key,
        () => {
              'name': name,
              'role': '',
              if (_bangumiImage(p['images']) case final i?) 'image': i,
              if (_person('bangumi', p['id']) case final person?)
                'person': person,
            });
    final relation = _text(p['relation']);
    if (relation != null) {
      final role = entry['role'] as String;
      if (!role.split(' · ').contains(relation)) {
        entry['role'] = role.isEmpty ? relation : '$role · $relation';
      }
    }
  }
  return [
    for (final e in byPerson.values)
      {...e, if ((e['role'] as String).isEmpty) 'role': null}
        ..removeWhere((_, v) => v == null)
  ];
}

List<JsonMap> _bangumiCharacters(Map? fields) {
  final characters = fields?['characters'];
  if (characters is! List) return const [];
  return [
    for (final c in characters.whereType<Map>())
      if (_text(c['name']) case final name?)
        {
          'name': name,
          if (_text(c['relation']) case final role?) 'role': role,
          if (_bangumiImage(c['images']) case final image?) 'image': image,
          'actors': [
            for (final a in (c['actors'] as List? ?? const []).whereType<Map>())
              if (_text(a['name']) case final actor?)
                {
                  'name': actor,
                  if (_bangumiImage(a['images']) case final i?) 'image': i,
                  if (_person('bangumi', a['id']) case final p?) 'person': p,
                }
          ],
        }
  ];
}

/// Bangumi's cast is who voices each character.
List<JsonMap> _bangumiVoices(Map? fields) {
  final seen = <String>{};
  return [
    for (final c in _bangumiCharacters(fields))
      for (final a in (c['actors'] as List).cast<JsonMap>())
        if (seen.add('${(a['person'] as Map?)?['id'] ?? a['name']}'))
          {...a, 'role': c['name']}
  ];
}

const _status = {
  'Returning Series': '连载中',
  'Ended': '已完结',
  'Canceled': '已取消',
  'In Production': '制作中',
  'Planned': '计划中',
  'Pilot': '试播',
  'Released': '已上映',
  'Post Production': '后期制作',
  'Rumored': '传闻',
};

const _countries = {
  'JP': '日本',
  'CN': '中国大陆',
  'TW': '中国台湾',
  'HK': '中国香港',
  'KR': '韩国',
  'US': '美国',
  'GB': '英国',
  'FR': '法国',
  'DE': '德国',
  'CA': '加拿大',
  'AU': '澳大利亚',
  'IT': '意大利',
  'ES': '西班牙',
  'TH': '泰国',
  'IN': '印度',
};

const _languages = {
  'ja': '日语',
  'zh': '汉语',
  'cn': '粤语',
  'ko': '韩语',
  'en': '英语',
  'fr': '法语',
  'de': '德语',
  'es': '西班牙语',
  'it': '意大利语',
  'th': '泰语',
};

String? _names(Object? list) {
  if (list is! List) return _text(list);
  final names = [
    for (final item in list)
      if (item is String)
        item
      else if (item is Map && _text(item['name']) != null)
        _text(item['name'])!
  ];
  return names.isEmpty ? null : names.join(' / ');
}

String? _date(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  return parsed == null
      ? text
      : '${parsed.year} 年 ${parsed.month} 月 ${parsed.day} 日';
}

String? _money(Object? value) {
  if (value is! num || value <= 0) return null;
  if (value >= 1e8) {
    return '${(value / 1e8).toStringAsFixed(value >= 1e9 ? 1 : 2)} 亿美元';
  }
  if (value >= 1e4) return '${(value / 1e4).round()} 万美元';
  return '$value 美元';
}

String? _runtime(Object? ms, {required bool film}) {
  if (ms is! num || ms <= 0) return null;
  final minutes = (ms / 60000).round();
  if (!film) return '每集约 $minutes 分钟';
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0
      ? '$m 分钟'
      : m == 0
          ? '$h 小时'
          : '$h 小时 $m 分钟';
}

/// The infobox Bangumi keeps, by key (“放送开始”, “动画制作”…).
String? _infobox(Map? fields, String key) {
  final box = fields?['infobox'];
  if (box is! List) return null;
  for (final item in box.whereType<Map>()) {
    if (item['key'] != key) continue;
    final value = item['value'];
    if (value is String) return _text(value);
    if (value is List) {
      final parts = [
        for (final v in value)
          if (v is Map && _text(v['v']) != null) _text(v['v'])!
      ];
      if (parts.isNotEmpty) return parts.join(' / ');
    }
  }
  return null;
}

List<JsonMap> _facts(
    Object? Function(String) field, Map fields, Map? tmdb, Map? bangumi,
    {required bool film}) {
  final out = <JsonMap>[];
  void add(String label, String? value) {
    if (value != null && value.isNotEmpty) {
      out.add({'label': label, 'value': value});
    }
  }

  final title = _text(field('title'));
  final original = _text(field('originalTitle'));
  if (original != title) add('原名', original);
  add('类型', _names(field('genres')));
  final status = _text(tmdb?['status']);
  if (film) {
    add('上映', _date(tmdb?['releaseDate'] ?? field('releaseDate')));
  } else {
    add(
        '首播',
        _date(tmdb?['firstAirDate'] ?? field('releaseDate')) ??
            _infobox(bangumi, '放送开始'));
    if (status == 'Ended' || status == 'Canceled') {
      add('完结', _date(tmdb?['lastAirDate']));
    }
  }
  add('状态', status == null ? null : _status[status] ?? status);
  final seasons = tmdb?['seasonCount'];
  final episodes = field('episodeCount');
  if (!film) {
    add(
        '规模',
        [
          if (seasons is num && seasons > 1) '${seasons.toInt()} 季',
          if (episodes is num && episodes > 0) '${episodes.toInt()} 集',
        ].join(' · '));
  }
  add('时长', _runtime(field('runtimeMs'), film: film));
  add('形式', _text(bangumi?['platform']));
  add('播出', _names(tmdb?['networks']));
  add(
      '制作',
      _names(field('studios')) ??
          _text(field('studio')) ??
          _infobox(bangumi, '动画制作'));
  final countries = tmdb?['countries'];
  if (countries is List) {
    add(
        '国家/地区',
        [
          for (final c in countries)
            if (c is String) _countries[c] ?? c
        ].join(' / '));
  }
  final language = _text(tmdb?['originalLanguage']);
  add('原始语言', language == null ? null : _languages[language] ?? language);
  if (film) {
    add('预算', _money(tmdb?['budget']));
    add('票房', _money(tmdb?['revenue']));
  }
  return out;
}

List<String> _tags(Object? tags) {
  if (tags is! List) return const [];
  final named = <({String name, num count})>[
    for (final t in tags)
      if (t is String && _text(t) != null)
        (name: _text(t)!, count: 0)
      else if (t is Map && _text(t['name']) != null)
        (name: _text(t['name'])!, count: (t['count'] as num?) ?? 0)
  ];
  // Bangumi's tags carry how many people gave them; the most given first.
  if (named.any((t) => t.count > 0)) {
    named.sort((a, b) => b.count.compareTo(a.count));
  }
  return {for (final t in named) t.name}.take(12).toList();
}

List<JsonMap> _links(
    List<Map> sources, Map? tmdb, Map? dandanplay, Map fields) {
  final out = <JsonMap>[];
  final urls = <String>{};
  void add(String label, Object? url) {
    final text = _text(url);
    if (text == null ||
        !(text.startsWith('https://') || text.startsWith('http://'))) {
      return;
    }
    if (urls.add(text)) out.add({'label': label, 'url': text});
  }

  for (final s in sources) {
    final id = s['externalId'];
    switch ((s['provider'], s['objectType'])) {
      case ('tmdb', final String type) when type == 'tv' || type == 'movie':
        add('TMDB', 'https://www.themoviedb.org/$type/$id');
      case ('bangumi', 'subject'):
        add('Bangumi', 'https://bgm.tv/subject/$id');
    }
  }
  final imdb = (tmdb?['externalIds'] as Map?)?['imdb_id'];
  if (_text(imdb) case final id?)
    add('IMDb', 'https://www.imdb.com/title/$id/');
  add('弹弹play', dandanplay?['homepage']);
  add('官网', tmdb?['homepage']);
  return out;
}

/// A work a person took part in, as their page lists it. [workId] is a
/// found work (`Found.id`): opening it shows the work as its provider knows
/// it, or the library's work when it is there.
typedef UiPersonWork = ({
  String workId,
  String title,
  String? role,
  int? year,
  String? poster,
});

/// A person's page: who they are and what they took part in.
final class UiPerson {
  const UiPerson({
    required this.name,
    this.alias,
    this.image,
    this.biography,
    this.facts = const [],
    this.links = const [],
    this.credits = const [],
    this.libraryWorkIds = const [],
  });
  final String name;

  /// Another name they are known by here (a Chinese one, when the provider
  /// lists one).
  final String? alias;
  final String? image;
  final String? biography;
  final List<UiFact> facts;
  final List<UiLink> links;
  final List<UiPersonWork> credits;

  /// Works of the library crediting them, in the library's order.
  final List<String> libraryWorkIds;

  UiPerson withLibrary(List<String> ids) => UiPerson(
      name: name,
      alias: alias,
      image: image,
      biography: biography,
      facts: facts,
      links: links,
      credits: credits,
      libraryWorkIds: ids);
}

const _departments = {
  'Acting': '表演',
  'Directing': '导演',
  'Writing': '编剧',
  'Production': '制作',
  'Sound': '音乐与声音',
  'Art': '美术',
  'Camera': '摄影',
  'Editing': '剪辑',
  'Creator': '创作',
  'Visual Effects': '视觉效果',
  'Crew': '职员',
  'Lighting': '灯光',
  'Costume & Make-Up': '服装化妆',
};

const _careers = {
  'seiyu': '声优',
  'actor': '演员',
  'producer': '制作人',
  'mangaka': '漫画家',
  'artist': '音乐人',
  'writer': '作家',
  'illustrator': '插画家',
};

bool _cjk(String text) => RegExp(r'[一-鿿]').hasMatch(text);

/// A TMDB person (`/3/person/{id}` with `combined_credits,external_ids`);
/// [biography] stands in when the localized one is empty.
UiPerson tmdbPerson(Map row,
    {String? biography,
    required String Function(String type, Object id) foundId}) {
  final name = _text(row['name']) ?? '';
  final alias = [
    for (final a in (row['also_known_as'] as List? ?? const []))
      if (a is String && _cjk(a) && a != name) a
  ].firstOrNull;
  final facts = <UiFact>[
    if (_date(row['birthday']) case final born?) (label: '出生', value: born),
    if (_date(row['deathday']) case final died?) (label: '逝世', value: died),
    if (_text(row['place_of_birth']) case final place?)
      (label: '出生地', value: place),
    if (_text(row['known_for_department']) case final d?)
      (label: '知名于', value: _departments[d] ?? d),
  ];
  final imdb = _text((row['external_ids'] as Map?)?['imdb_id']);
  final links = <UiLink>[
    (label: 'TMDB', url: 'https://www.themoviedb.org/person/${row['id']}'),
    if (imdb != null) (label: 'IMDb', url: 'https://www.imdb.com/name/$imdb/'),
    if (_text(row['homepage']) case final home? when home.startsWith('http'))
      (label: '主页', url: home),
  ];
  final credits = row['combined_credits'] as Map?;
  final byWork = <String, ({Map row, List<String> roles})>{};
  for (final list in [credits?['cast'], credits?['crew']]) {
    if (list is! List) continue;
    for (final c in list.whereType<Map>()) {
      final type = c['media_type'];
      if (type != 'tv' && type != 'movie' || c['id'] == null) continue;
      final key = '$type:${c['id']}';
      final entry = byWork.putIfAbsent(key, () => (row: c, roles: <String>[]));
      final role = _text(c['character']) ?? _jobs[c['job']] ?? _text(c['job']);
      if (role != null && !entry.roles.contains(role)) entry.roles.add(role);
    }
  }
  final works = byWork.values.toList()
    ..sort((a, b) => ((b.row['vote_count'] as num?) ?? 0)
        .compareTo((a.row['vote_count'] as num?) ?? 0));
  return UiPerson(
    name: name,
    alias: alias,
    image: row['profile_path'] == null
        ? null
        : 'https://image.tmdb.org/t/p/w500${row['profile_path']}',
    biography: _text(row['biography']) ?? _text(biography),
    facts: facts,
    links: links,
    credits: [
      for (final w in works.take(40))
        (
          workId: foundId(w.row['media_type'] as String, w.row['id'] as Object),
          title: _text(w.row['title']) ?? _text(w.row['name']) ?? '',
          role: w.roles.isEmpty ? null : w.roles.join(' · '),
          year: int.tryParse(
              '${w.row['release_date'] ?? w.row['first_air_date'] ?? ''}'
                  .split('-')
                  .first),
          poster: w.row['poster_path'] == null
              ? null
              : 'https://image.tmdb.org/t/p/w342${w.row['poster_path']}',
        )
    ],
  );
}

/// A Bangumi person (`/v0/persons/{id}`), with the anime they worked on
/// (`/subjects`) and the characters they voiced (`/characters`).
UiPerson bangumiPerson(Map row,
    {List subjects = const [],
    List characters = const [],
    required String Function(Object id) foundId}) {
  final name = _text(row['name']) ?? '';
  final chinese = _infobox(row, '简体中文名');
  final birthday = [
    if (row['birth_year'] is int) '${row['birth_year']} 年',
    if (row['birth_mon'] is int) '${row['birth_mon']} 月',
    if (row['birth_day'] is int) '${row['birth_day']} 日',
  ].join(' ');
  final careers = [
    for (final c in (row['career'] as List? ?? const []))
      if (c is String) _careers[c] ?? c
  ];
  final byWork =
      <String, ({String title, String? poster, List<String> roles})>{};
  for (final s in subjects.whereType<Map>()) {
    if (s['type'] != null && s['type'] != 2 || s['id'] == null) continue;
    final entry = byWork.putIfAbsent(
        '${s['id']}',
        () => (
              title: _text(s['name_cn']) ?? _text(s['name']) ?? '',
              poster: _text(s['image']),
              roles: <String>[]
            ));
    if (_text(s['staff']) case final role? when !entry.roles.contains(role)) {
      entry.roles.add(role);
    }
  }
  for (final c in characters.whereType<Map>()) {
    if (c['subject_id'] == null) continue;
    final entry = byWork.putIfAbsent(
        '${c['subject_id']}',
        () => (
              title:
                  _text(c['subject_name_cn']) ?? _text(c['subject_name']) ?? '',
              poster: null,
              roles: <String>[]
            ));
    if (_text(c['name']) case final character?
        when !entry.roles.contains(character)) {
      entry.roles.add(character);
    }
  }
  return UiPerson(
    name: name,
    alias: chinese != null && chinese != name ? chinese : null,
    image: _text((row['images'] as Map?)?['large']) ??
        _bangumiImage(row['images']),
    biography: _text(row['summary']),
    facts: [
      if (birthday.isNotEmpty) (label: '出生', value: birthday),
      if (_infobox(row, '出生地') case final place?) (label: '出生地', value: place),
      if (careers.isNotEmpty) (label: '职业', value: careers.join(' / ')),
    ],
    links: [
      (label: 'Bangumi', url: 'https://bgm.tv/person/${row['id']}'),
    ],
    credits: [
      for (final e in byWork.entries.take(40))
        if (e.value.title.isNotEmpty)
          (
            workId: foundId(e.key),
            title: e.value.title,
            role: e.value.roles.isEmpty ? null : e.value.roles.join(' · '),
            year: null,
            poster: e.value.poster,
          )
    ],
  );
}

/// Pictures of a TMDB work (`/3/{type}/{id}/images`): its backdrops wide,
/// best voted first, then its posters.
UiGallery tmdbGallery(Map row, {int limit = 12}) {
  List<String> pick(String key, String size) {
    final list = [
      for (final i in (row[key] as List? ?? const []).whereType<Map>())
        if (_text(i['file_path']) != null) i
    ]..sort((a, b) =>
        (((b['vote_count'] as num?) ?? 0) * ((b['vote_average'] as num?) ?? 0))
            .compareTo(((a['vote_count'] as num?) ?? 0) *
                ((a['vote_average'] as num?) ?? 0)));
    return [
      for (final i in list.take(limit))
        'https://image.tmdb.org/t/p/$size${i['file_path']}'
    ];
  }

  return UiGallery(
      wide: pick('backdrops', 'w1280'), posters: pick('posters', 'w500'));
}
