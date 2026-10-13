import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media/identity_store.dart';
import '../harness_redaction.dart';
import '../mesh/library_codec.dart';
import '../state/query.dart';
import 'library.dart';
import 'library_source_cache.dart';
import 'service.dart';
import 'ui_data.dart';

/// Classic clients are attached by the GUI host; catalogue facts stay local.
abstract interface class LibrarySourcePort {
  Future<List<JsonMap>> sources({bool initialize = true});
  Future<List<JsonMap>> roots(String sourceId);
  Future<JsonMap> browse(String sourceId, String parentId,
      {int offset = 0,
      int limit = 60,
      String? sort,
      bool recursive = false,
      String? filters});
  Future<JsonMap> item(String sourceId, String itemId);
  Future<String?> image(String sourceId, JsonMap item, String kind);
  Future<String?> currentSort(String sourceId, String parentId);
}

String sourceEntityId(String kind, String sourceId, String itemId,
        {String? serverId}) =>
    'source-$kind:${base64Url.encode(utf8.encode(jsonEncode([
          sourceId,
          itemId,
          if (serverId != null) serverId
        ])))}';
List<String>? sourceEntityRef(String id, String kind) {
  if (!id.startsWith('source-$kind:')) return null;
  try {
    final value = jsonDecode(
        utf8.decode(base64Url.decode(id.substring('source-$kind:'.length))));
    if (value is List &&
        (value.length == 2 || value.length == 3) &&
        value.every((v) => v is String)) return value.cast<String>();
  } on FormatException {
    throw const Failure(
        FailureCode.invalidInput, 'Malformed source entity id.');
  }
  throw const Failure(FailureCode.invalidInput, 'Malformed source entity id.');
}

final class LibraryDataService implements NextLibraryData, NextLibraryActions {
  LibraryDataService(this.ui, {this.port});
  final UiDataService ui;
  LibrarySourcePort? port;
  LibrarySourceCache? _cache;
  LibrarySourcePort? get _sourcePort {
    final delegate = port;
    if (delegate == null) return null;
    if (_cache?.delegate != delegate) _cache = LibrarySourceCache(delegate, db);
    return _cache;
  }

  bool _prepared = false;
  Future<void>? _preparing;
  bool _sourcesRead = false;
  Future<void> _prepare() => _preparing ??= (() async {
        if (!_prepared) {
          await ui.meshLibrary?.prepareIndex();
          _prepared = true;
        }
      })()
          .whenComplete(() => _preparing = null);
  Database get db => ui.db;
  @override
  Stream<void> get changes => ui.changes;
  Future<List<JsonMap>> _sources({bool initialize = true}) async {
    if (initialize) _sourcesRead = true;
    return [
      {'sourceId': 'local', 'name': '本地', 'type': 'local', 'connected': true},
      ...await _sourcePort?.sources(initialize: initialize) ?? <JsonMap>[]
    ];
  }

  Future<String> sourceStamp() async =>
      _sourcesRead ? jsonEncode(await _sources(initialize: false)) : '';
  @override
  Future<List<UiLibrarySource>> sources() async {
    final rows = await _sources();
    return [
      for (final row in rows)
        UiLibrarySource(
            sourceId: row['sourceId'] as String,
            name: row['name'] as String,
            kind: UiSourceKind.values.byName(row['type'] as String),
            online: row['connected'] == true)
    ];
  }

  Future<void> _requireSource(String id) async {
    if (!(await _sources()).any((s) => s['sourceId'] == id)) {
      throw const Failure(
          FailureCode.notFound, 'Use a sourceId from ui.library.sources.');
    }
  }

  Future<List<String>?> validatedSourceRef(String id, String kind) async {
    final ref = sourceEntityRef(id, kind);
    if (ref == null) return null;
    await _validateRef(ref);
    return ref;
  }

  Future<void> _validateRef(List<String> ref) async {
    final current =
        (await _sources()).where((s) => s['sourceId'] == ref[0]).firstOrNull;
    if (current == null)
      throw const Failure(FailureCode.notFound, 'Source was removed.');
    if (ref.length == 3 && current['serverId'] != ref[2])
      throw const Failure(FailureCode.conflict,
          'Source now points to a different server; read its current page.');
  }

  Future<JsonMap> _layout(String id, {DatabaseExecutor? tx}) async {
    final rows = await (tx ?? db)
        .query('ui_cache', where: 'id=?', whereArgs: ['library:layout:$id']);
    return rows.isEmpty
        ? {
            'sourceId': id,
            'form': 'shelves',
            'original': true,
            'originalOrder': <String>[],
            'hiddenOriginal': <String>[],
            'categories': <Object?>[]
          }
        : decodeMediaJson(rows.single['payload']);
  }

  Future<List<JsonMap>> arrangements(int offset, int limit) async {
    final rows = await db.query('ui_cache',
        where: "id LIKE 'library:layout:%'", orderBy: 'id');
    final saved = {
      for (final r in rows)
        (decodeMediaJson(r['payload']))['sourceId'] as String:
            decodeMediaJson(r['payload'])
    };
    final ids = <String>{
      'local',
      ...(await _sources(initialize: false))
          .map((s) => s['sourceId'] as String),
      ...saved.keys
    };
    return [
      for (final id in ids.skip(offset).take(limit))
        {
          'id': id,
          ...saved[id] ??
              {
                'sourceId': id,
                'form': 'shelves',
                'original': true,
                'originalOrder': [],
                'hiddenOriginal': [],
                'categories': []
              }
        }
    ];
  }

  void register(StateCapability state) {
    state.views['library.catalogue'] = StateView(
        name: 'library.catalogue',
        description:
            'Local X47 condition projection. Membership dimensions apply to the merged work as a whole. Rating is its first displayed rating; missing facts stay null. Updated by local/Mesh refresh, never by Nipa classification.',
        fields: const ObjectSchema({
          'id': StringSchema(),
          'workId': StringSchema(),
          'title': StringSchema(),
          'sourceIds': ArraySchema(StringSchema()),
          'deviceIds': ArraySchema(StringSchema()),
          'types': ArraySchema(StringSchema()),
          'identified': BooleanSchema(),
          'watch': StringSchema(),
          'genres': ArraySchema(StringSchema()),
          'year': IntegerSchema(nullable: true),
          'rating': NumberSchema(nullable: true),
          'ratingSource': StringSchema(nullable: true),
          'addedAt': StringSchema()
        }),
        read: (offset, limit) async => [
              for (final row in await db.query('next_library_index',
                  orderBy: 'added DESC,id', offset: offset, limit: limit))
                {
                  'id': row['id'],
                  'workId': row['id'],
                  'title': decodeMediaJson(row['payload'])['title'],
                  ...decodeMediaJson(row['facts']),
                  'addedAt': DateTime.fromMicrosecondsSinceEpoch(
                          row['added'] as int,
                          isUtc: true)
                      .toIso8601String()
                }
            ]);
    state.views['library.arrangements'] = StateView(
        name: 'library.arrangements',
        description:
            'Persisted source arrangements and local originalOrder/hiddenOriginal category IDs. Hidden originals are restored with ui.library.restore; server/share contents never change. No classification is inferred.',
        fields: const ObjectSchema({
          'id': StringSchema(),
          'sourceId': StringSchema(),
          'form': StringSchema(),
          'original': BooleanSchema(),
          'originalOrder': ArraySchema(StringSchema()),
          'hiddenOriginal': ArraySchema(StringSchema()),
          'categories':
              ArraySchema(ObjectSchema({}, additionalProperties: true))
        }),
        read: arrangements);
  }

  @override
  Future<UiLibraryPage> page(String sourceId) async {
    await _requireSource(sourceId);
    final layout = await _layout(sourceId);
    final categories = (layout['categories'] as List).cast<Map>();
    final arranged = layout['original'] == false;
    final originals = await _originalSpecs(sourceId);
    final hidden = (layout['hiddenOriginal'] as List? ?? []).cast<String>();
    final specs = arranged ? categories : _orderedOriginals(originals, layout);
    return UiLibraryPage(
        form: UiLibraryForm.values.byName(layout['form'] as String),
        arranged: arranged,
        hasArrangement: categories.isNotEmpty,
        hiddenCategories: [
          for (final spec in originals)
            if (hidden.contains(spec['id']))
              UiCategory(
                  categoryId: spec['id'] as String,
                  title: spec['title'] as String,
                  sorts: _sorts(spec))
        ],
        categories: [
          for (final spec in specs)
            await _category(spec, previews: layout['form'] == 'shelves')
        ]);
  }

  Future<List<Map>> _originalSpecs(String sourceId) async => sourceId == 'local'
      ? <Map>[
          {
            'id': sourceEntityId('folder', 'local', ''),
            'title': '全部',
            'content': {'kind': 'condition', 'filter': {}, 'allLocal': true}
          }
        ]
      : [
          for (final r in await _sourcePort!.roots(sourceId))
            {
              'id': sourceEntityId('folder', sourceId, r['id'] as String,
                  serverId: r['serverId'] as String?),
              'title': r['name'],
              'sort': r['sort'],
              'content': {
                'kind': 'original',
                'sourceId': sourceId,
                'parentId': r['id'],
                if (r['serverId'] != null) 'serverId': r['serverId']
              }
            }
        ];

  List<Map> _orderedOriginals(List<Map> specs, Map layout) {
    final hidden = (layout['hiddenOriginal'] as List? ?? []).cast<String>();
    final order = (layout['originalOrder'] as List? ?? []).cast<String>();
    final byId = {for (final s in specs) s['id']: s};
    return [
      for (final id in order)
        if (byId.containsKey(id) && !hidden.contains(id)) byId[id]!,
      for (final s in specs)
        if (!order.contains(s['id']) && !hidden.contains(s['id'])) s
    ];
  }

  Future<UiCategory> _category(Map spec, {required bool previews}) async {
    final slice = await _items(spec, offset: 0, limit: previews ? 8 : 3);
    final works = <UiWork>[
      for (final id in spec['coverWorkIds'] as List? ?? [])
        if (await ui.work(id as String) case final UiWork w) w,
      ...slice.items.whereType<UiWorkItem>().map((i) => i.work)
    ];
    final art = works.map((w) => w.artwork).toList();
    return UiCategory(
        categoryId: spec['id'] as String,
        title: spec['title'] as String,
        count: slice.total,
        posters: art.map((a) => a.poster).whereType<String>().take(3).toList(),
        backdrop: art.map((a) => a.backdrop).whereType<String>().firstOrNull,
        tint: art.map((a) => a.tint).whereType<int>().firstOrNull,
        preview: previews ? slice.items : const [],
        sorts: _sorts(spec));
  }

  List<UiSort> _sorts(Map spec) {
    if ((spec['content'] as Map)['kind'] == 'manual')
      return const [UiSort('manual', '手选顺序')];
    final original = (spec['content'] as Map)['kind'] == 'original' &&
        (spec['content'] as Map)['sourceId'] != 'local';
    final options = original
        ? const [
            UiSort('SortName:Ascending', '名称'),
            UiSort('DateCreated:Descending', '最近添加'),
            UiSort('PremiereDate:Descending', '上映时间'),
            UiSort('CommunityRating:Descending', '评分')
          ]
        : const [
            UiSort('added', '最近添加'),
            UiSort('title', '名称'),
            UiSort('year', '年份'),
            UiSort('rating', '评分')
          ];
    final share = original &&
        ((spec['content'] as Map)['sourceId'] as String)
            .startsWith(RegExp(r'(smb|webdav):'));
    final available = share
        ? const [
            UiSort('SortName:Ascending', '名称'),
            UiSort('DateCreated:Descending', '修改时间')
          ]
        : options;
    return [
      if (original &&
          spec['sort'] is String &&
          !available.any((s) => s.id == spec['sort']))
        UiSort(spec['sort'] as String, '服务器排序'),
      for (final s in available)
        if (s.id == spec['sort']) s,
      for (final s in available)
        if (s.id != spec['sort']) s
    ];
  }

  Future<JsonMap> _spec(String id) async {
    final ref = sourceEntityRef(id, 'folder');
    if (ref != null) {
      await _validateRef(ref);
      return {
        'id': id,
        'title': '',
        'content': ref[0] == 'local'
            ? {'kind': 'condition', 'allLocal': true, 'filter': {}}
            : {
                'kind': 'original',
                'sourceId': ref[0],
                'parentId': ref[1],
                if (ref.length == 3) 'serverId': ref[2]
              },
        if (ref[0] != 'local')
          'sort': await _sourcePort!.currentSort(ref[0], ref[1])
      };
    }
    for (final row in await arrangements(0, 1 << 30)) {
      for (final c in row['categories'] as List) {
        if ((c as Map)['id'] == id) return Map<String, Object?>.from(c);
      }
    }
    throw const Failure(
        FailureCode.notFound, 'Use a categoryId from the source page.');
  }

  @override
  Future<UiSlice> items(String categoryId,
      {int offset = 0, int limit = 60, String? sort}) async {
    if (offset < 0 || limit < 1 || limit > 500)
      throw const Failure(
          FailureCode.invalidInput, 'offset >= 0, limit 1..500.');
    final spec = await _spec(categoryId);
    if (sort != null && !_sorts(spec).any((s) => s.id == sort))
      throw const Failure(FailureCode.invalidInput, 'Use a category sort id.');
    return _items(spec, offset: offset, limit: limit, sort: sort);
  }

  Future<UiSlice> _items(Map spec,
      {required int offset, required int limit, String? sort}) async {
    final content = spec['content'] as Map;
    switch (content['kind']) {
      case 'original':
        final sourceId = content['sourceId'] as String;
        await _validateRef([
          sourceId,
          content['parentId'] as String,
          if (content['serverId'] is String) content['serverId'] as String
        ]);
        if (sourceId == 'local')
          return _items({
            ...spec,
            'content': {'kind': 'condition', 'allLocal': true, 'filter': {}}
          }, offset: offset, limit: limit, sort: sort);
        final result = await _sourcePort!.browse(
            sourceId, content['parentId'] as String,
            offset: offset,
            limit: limit,
            sort: sort ?? spec['sort'] as String?);
        return UiSlice([
          for (final raw in result['entries'] as List)
            await _sourceItem(sourceId, Map<String, Object?>.from(raw as Map))
        ], total: result['total'] as int?);
      case 'manual':
        final ids = (content['workIds'] as List).cast<String>();
        final result = <UiLibraryItem>[];
        for (final id in ids.skip(offset).take(limit)) {
          final w = await ui.work(id);
          if (w != null) result.add(UiWorkItem(await _availableWork(w)));
        }
        return UiSlice(result, total: ids.length);
      default:
        await _prepare();
        final where = <String>[];
        final args = <Object?>[];
        if (content['allLocal'] != true)
          where.add(
              "(json_extract(facts,'\$.identified')=1 OR EXISTS (SELECT 1 FROM json_each(facts,'\$.sourceIds') WHERE value='local' OR value LIKE 'smb:%' OR value LIKE 'webdav:%'))");
        final filter = content['filter'] as Map? ?? {};
        for (final key in ['sourceIds', 'deviceIds', 'types', 'genres']) {
          final values = filter[key] as List?;
          if (values == null || values.isEmpty) continue;
          where.add(
              "EXISTS (SELECT 1 FROM json_each(facts,'\$.$key') WHERE value IN (${List.filled(values.length, '?').join(',')}))");
          args.addAll(values);
        }
        if (filter['watch'] != null) {
          where.add("json_extract(facts,'\$.watch')=?");
          args.add(filter['watch']);
        }
        for (final entry in {
          'yearMin': ('year', '>='),
          'yearMax': ('year', '<='),
          'ratingMin': ('rating', '>='),
          'ratingMax': ('rating', '<=')
        }.entries) {
          if (filter[entry.key] == null) continue;
          where.add(
              "json_extract(facts,'\$.${entry.value.$1}')${entry.value.$2}?");
          args.add(filter[entry.key]);
        }
        for (final entry in {'addedAfter': '>=', 'addedBefore': '<='}.entries) {
          if (filter[entry.key] == null) continue;
          where.add('added${entry.value}?');
          args.add(DateTime.parse(filter[entry.key] as String)
              .microsecondsSinceEpoch);
        }
        // Local means the merged device catalogue, including indexed remote locators.
        final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
        final ordering = switch (sort ?? spec['sort'] ?? 'added') {
          'title' => "json_extract(payload,'\$.title') COLLATE NOCASE,id",
          'year' => "json_extract(facts,'\$.year') DESC,id",
          'rating' => "json_extract(facts,'\$.rating') DESC,id",
          _ => 'added DESC,id'
        };
        final count = (await db.rawQuery(
                'SELECT COUNT(*) AS n FROM next_library_index $clause', args))
            .single['n'] as int;
        final rows = await db.rawQuery(
            'SELECT payload FROM next_library_index $clause ORDER BY $ordering LIMIT ? OFFSET ?',
            [...args, limit, offset]);
        return UiSlice([
          for (final r in rows)
            UiWorkItem(await _availableWork(
                _decodeWork(decodeMediaJson(r['payload']))))
        ], total: count);
    }
  }

  Future<UiWork> _availableWork(UiWork work) async {
    final next = work.next;
    if (next == null || !next.playable) return work;
    final original = sourceEntityRef(next.episodeId, 'episode');
    JsonMap? remote;
    if (original != null) {
      remote = {
        'sourceId': original[0],
        if (original.length == 3) 'serverId': original[2]
      };
    } else {
      final id =
          ui.meshLibrary?.localEpisodeId(next.episodeId) ?? next.episodeId;
      final rows = await db.rawQuery(
          'SELECT f.attributes FROM media_locations l JOIN media_file_episodes e ON e.file_id=l.file_id '
          'JOIN media_entities f ON f.id=l.file_id WHERE e.episode_id=? AND l.owner_device_id=? '
          'AND l.available=1 ORDER BY l.id LIMIT 1',
          [id, ui.media.store.ownerDeviceId]);
      if (rows.isNotEmpty)
        remote = (jsonDecode(rows.single['attributes'] as String)
            as Map)['remoteSource'] as JsonMap?;
    }
    if (remote == null) return work;
    final source = (await _sources())
        .where((s) => s['sourceId'] == remote!['sourceId'])
        .firstOrNull;
    if (source != null &&
        source['connected'] == true &&
        (remote['serverId'] == null ||
            source['serverId'] == remote['serverId'])) return work;
    return UiWork(
        workId: work.workId,
        title: work.title,
        originalTitle: work.originalTitle,
        year: work.year,
        genres: work.genres,
        episodeCount: work.episodeCount,
        studio: work.studio,
        overview: work.overview,
        ratings: work.ratings,
        artwork: work.artwork,
        next: episodeValue({...episodeJson(next), 'playable': false},
            device: next.device),
        danmaku: work.danmaku,
        devices: work.devices);
  }

  UiWork _decodeWork(JsonMap row) => workValue(
          row,
          row['next'] == null
              ? []
              : [
                  episodeValue(Map<String, Object?>.from(row['next'] as Map),
                      device: (row['next'] as Map)['device'] == null
                          ? null
                          : UiDevice(
                              name: ((row['next'] as Map)['device']
                                  as Map)['name'] as String,
                              online: ((row['next'] as Map)['device']
                                  as Map)['online'] as bool))
                ],
          [
            for (final d in row['devices'] as List)
              UiDevice(
                  name: (d as Map)['name'] as String,
                  online: d['online'] as bool)
          ]);
  Future<UiLibraryItem> _sourceItem(String sourceId, JsonMap item) async {
    if (item['isDirectory'] == true && item['kind'] != 'Series') {
      final poster = await _sourcePort!.image(sourceId, item, 'Primary');
      return UiFolderItem(
          categoryId: sourceEntityId('folder', sourceId, item['id'] as String,
              serverId: item['serverId'] as String?),
          title: item['name'] as String,
          count: (item['metadata'] as Map?)?['ChildCount'] as int?,
          posters: poster == null ? [] : [poster]);
    }
    final id = sourceEntityId('work', sourceId, item['id'] as String,
        serverId: item['serverId'] as String?);
    await _cacheItem(id, item);
    return UiWorkItem((await sourceWork(id))!);
  }

  Future<void> _cacheItem(String id, JsonMap item) async {
    final payload = jsonEncode(publicHarnessFacts(item));
    final saved = await db.query('ui_cache',
        where: 'id=? AND fingerprint=?', whereArgs: [id, payload]);
    if (saved.isEmpty)
      await db.insert(
          'ui_cache', {'id': id, 'fingerprint': payload, 'payload': payload},
          conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<JsonMap> _sourceRecord(String id, List<String> ref) async {
    await _validateRef(ref);
    final rows = await db.query('ui_cache', where: 'id=?', whereArgs: [id]);
    if (rows.isNotEmpty) return decodeMediaJson(rows.single['payload']);
    final item =
        publicHarnessFacts(await _sourcePort!.item(ref[0], ref[1])) as JsonMap;
    await _cacheItem(id, item);
    return item;
  }

  Future<UiWork?> sourceWork(String id) async {
    final ref = sourceEntityRef(id, 'work');
    if (ref == null) return null;
    final item = await _sourceRecord(id, ref);
    final m = item['metadata'] as Map? ?? {};
    UiEpisode? next;
    if (item['isDirectory'] == true) {
      for (final filter in ['IsResumable', 'IsUnplayed', null]) {
        final page = await _sourcePort!.browse(ref[0], ref[1],
            limit: 1,
            recursive: true,
            sort: 'ParentIndexNumber,IndexNumber:Ascending',
            filters: filter);
        final entries = (page['entries'] as List).cast<JsonMap>();
        if (entries.isNotEmpty) {
          next = await _sourceEpisode(ref[0], id, entries.first);
          break;
        }
      }
    } else {
      next = await _sourceEpisode(ref[0], id, item);
    }
    return _availableWork(UiWork(
        workId: id,
        title: item['name'] as String,
        originalTitle: m['OriginalTitle'] as String?,
        year: m['ProductionYear'] as int?,
        overview: m['Overview'] as String?,
        genres: (m['Genres'] as List? ?? []).cast<String>(),
        episodeCount: m['EpisodeCount'] as int?,
        ratings: [
          if (m['CommunityRating'] case final num r)
            UiRating('服务器', r.toDouble())
        ],
        artwork: UiArtwork(
            poster: await _sourcePort!.image(ref[0], item, 'Primary'),
            backdrop: await _sourcePort!.image(ref[0], item, 'Backdrop')),
        next: next));
  }

  Future<UiEpisode> _sourceEpisode(
      String sourceId, String workId, JsonMap item) async {
    final episodeId = sourceEntityId('episode', sourceId, item['id'] as String,
        serverId: item['serverId'] as String?);
    await _cacheItem(episodeId, {...item, 'workId': workId});
    final m = item['metadata'] as Map? ?? {};
    final user = m['UserData'] as Map? ?? {};
    final duration = (m['RunTimeTicks'] as num?)?.toInt();
    return UiEpisode(
        episodeId: episodeId,
        workId: workId,
        number: (m['IndexNumber'] as int?) ?? 1,
        season: m['ParentIndexNumber'] as int?,
        title: item['name'] as String,
        runtime:
            duration == null ? null : Duration(microseconds: duration ~/ 10),
        still: await _sourcePort!.image(sourceId, item, 'Primary'),
        playable: (await _sources())
            .any((s) => s['sourceId'] == sourceId && s['connected'] == true),
        progress: user['Played'] == true
            ? 1
            : duration != null &&
                    duration > 0 &&
                    user['PlaybackPositionTicks'] is num
                ? ((user['PlaybackPositionTicks'] as num) / duration)
                    .clamp(0.0, 1.0)
                : null);
  }

  Future<List<UiEpisode>> sourceEpisodes(String id, {int? season}) async {
    final ref = sourceEntityRef(id, 'work');
    if (ref == null) return [];
    final item = await _sourceRecord(id, ref);
    final result = <UiEpisode>[];
    if (item['isDirectory'] != true)
      result.add(await _sourceEpisode(ref[0], id, item));
    else {
      var offset = 0;
      while (true) {
        final page = await _sourcePort!.browse(ref[0], ref[1],
            offset: offset, limit: 200, recursive: true);
        final entries = (page['entries'] as List).cast<JsonMap>();
        for (final e in entries)
          result.add(await _sourceEpisode(ref[0], id, e));
        offset += entries.length;
        if (entries.isEmpty || offset >= (page['total'] as int? ?? offset))
          break;
      }
    }
    result.sort((a, b) => (a.season ?? 0) == (b.season ?? 0)
        ? a.number.compareTo(b.number)
        : (a.season ?? 0).compareTo(b.season ?? 0));
    return result.where((e) => season == null || e.season == season).toList();
  }

  Future<String?> sourceParent(String id) async {
    if (sourceEntityRef(id, 'work') != null) return id;
    final ref = sourceEntityRef(id, 'episode');
    if (ref == null) return null;
    final item = await _sourceRecord(id, ref);
    return item['workId'] as String? ??
        sourceEntityId('work', ref[0],
            (item['metadata'] as Map?)?['SeriesId'] as String? ?? ref[1],
            serverId: ref.length == 3 ? ref[2] : null);
  }

  Future<String> _editOriginal(
      String operation, String id, JsonMap layout, int? index) async {
    final hidden =
        (layout['hiddenOriginal'] as List? ?? []).cast<String>().toList();
    if (operation == 'restore') {
      if (!hidden.remove(id)) {
        throw const Failure(
            FailureCode.notFound, 'Unknown hidden original category.');
      }
      layout['hiddenOriginal'] = hidden;
      return '已恢复原始类别';
    }
    final originals = await _originalSpecs(layout['sourceId'] as String);
    if (!originals.any((s) => s['id'] == id)) {
      throw const Failure(FailureCode.notFound,
          'Use an original categoryId from this source page.');
    }
    if (operation == 'remove') {
      if (!hidden.contains(id)) hidden.add(id);
      layout['hiddenOriginal'] = hidden;
      return '已隐藏原始类别';
    }
    final all = _orderedOriginals(originals, {...layout, 'hiddenOriginal': []})
        .map((s) => s['id'] as String)
        .toList();
    final visible = all.where((id) => !hidden.contains(id)).toList();
    final at = visible.indexOf(id);
    if (at < 0 || index! < 0 || index >= visible.length) {
      throw const Failure(FailureCode.invalidInput,
          'Index must be inside the visible original category list.');
    }
    visible.insert(index, visible.removeAt(at));
    var position = 0;
    layout['originalOrder'] = [
      for (final entry in all)
        hidden.contains(entry) ? entry : visible[position++]
    ];
    return '已调整原始类别顺序';
  }

  /// All writes, from the viewer or Nipa, share validation and one transaction.
  Future<JsonMap> mutate(
          String operation, List<JsonMap> entries, Invocation invocation) =>
      ui.media.mutate(() async {
        final layouts = <String, JsonMap>{};
        final titles = <String, Set<String>>{};
        final effects = <String, List<JsonMap>>{};
        for (final input in entries) {
          final originalRef = input['categoryId'] is String
              ? sourceEntityRef(input['categoryId'] as String, 'folder')
              : null;
          String sourceId;
          if (input['sourceId'] is String)
            sourceId = input['sourceId'] as String;
          else if (originalRef != null) {
            await _validateRef(originalRef);
            sourceId = originalRef[0];
          } else {
            final id = input['categoryId'] as String;
            final row = (await arrangements(0, 1 << 30))
                .where((r) => (r['categories'] as List)
                    .any((c) => (c as Map)['id'] == id))
                .firstOrNull;
            if (row == null)
              throw const Failure(FailureCode.notFound,
                  'Use a categoryId from the source page or its hiddenCategories.');
            sourceId = row['sourceId'] as String;
          }
          await _requireSource(sourceId);
          final layout = layouts[sourceId] ??= await _layout(sourceId);
          final sourceTitles = titles[sourceId] ??= <String>{};
          final sourceEffects = effects[sourceId] ??= <JsonMap>[];
          if (originalRef != null &&
              const ['move', 'remove', 'restore'].contains(operation)) {
            sourceTitles.add(await _editOriginal(operation,
                input['categoryId'] as String, layout, input['index'] as int?));
            sourceEffects.add({
              'operation': operation == 'remove' ? 'hide' : operation,
              'categoryId': input['categoryId']
            });
            continue;
          }
          if (operation == 'restore') {
            throw const Failure(FailureCode.invalidInput,
                'Only hidden original categories can be restored.');
          }
          final categories = (layout['categories'] as List)
              .map((c) => Map<String, Object?>.from(c as Map))
              .toList();
          switch (operation) {
            case 'configure':
              if (!input.containsKey('form') && !input.containsKey('original'))
                throw const Failure(
                    FailureCode.invalidInput, 'Supply form or original.');
              if (input['form'] != null) layout['form'] = input['form'];
              if (input['original'] != null) {
                if (input['original'] == false && categories.isEmpty)
                  throw const Failure(FailureCode.invalidInput,
                      'No arrangement exists for this source.');
                layout['original'] = input['original'];
              }
            case 'put':
              final id = input['categoryId'] as String;
              if (id.startsWith('source-'))
                throw const Failure(
                    FailureCode.invalidInput, 'Reserved source category id.');
              validateViewerText(input['title'] as String);
              final content =
                  Map<String, Object?>.from(input['content'] as Map);
              final allowed = switch (content['kind']) {
                'condition' => {'kind', 'filter'},
                'manual' => {'kind', 'workIds'},
                'original' => {'kind', 'sourceId', 'parentId', 'serverId'},
                _ => <String>{}
              };
              final required = switch (content['kind']) {
                'condition' => {'filter'},
                'manual' => {'workIds'},
                'original' => {'sourceId', 'parentId'},
                _ => {'kind'}
              };
              if (allowed.isEmpty ||
                  content.keys.any((k) => !allowed.contains(k)) ||
                  required.any((k) => !content.containsKey(k))) {
                throw const Failure(FailureCode.invalidInput,
                    'content must have exactly the fields for its kind.');
              }
              if ((input['coverWorkIds'] as List? ?? []).length > 3)
                throw const Failure(
                    FailureCode.invalidInput, 'At most three cover workIds.');
              if (content['kind'] == 'manual') {
                for (final workId
                    in (content['workIds'] as List).cast<String>()) {
                  if (await ui.work(workId) == null)
                    throw const Failure(
                        FailureCode.notFound, 'Unknown manual workId.');
                }
              }
              if (content['kind'] == 'original') {
                await _requireSource(content['sourceId'] as String);
                final target = (await _sources())
                    .firstWhere((s) => s['sourceId'] == content['sourceId']);
                if (content['serverId'] != null &&
                    content['serverId'] != target['serverId'])
                  throw const Failure(FailureCode.conflict,
                      'Original reference belongs to a different server.');
                if (target['serverId'] != null)
                  content['serverId'] = target['serverId'];
                if (content['sourceId'] == 'local' &&
                    content['parentId'] != 'all')
                  throw const Failure(FailureCode.invalidInput,
                      'Local original parentId is all.');
              }
              for (final key in ['addedAfter', 'addedBefore']) {
                if ((content['filter'] as Map?)?[key] case final String value) {
                  if (DateTime.tryParse(value) == null)
                    throw const Failure(
                        FailureCode.invalidInput, 'Use ISO-8601 added dates.');
                }
              }
              for (final workId in input['coverWorkIds'] as List? ?? []) {
                if (await ui.work(workId as String) == null)
                  throw const Failure(
                      FailureCode.notFound, 'Unknown cover workId.');
              }
              final previousOwner = (await arrangements(0, 1 << 30)).where(
                  (r) =>
                      r['sourceId'] != sourceId &&
                      (r['categories'] as List)
                          .any((c) => (c as Map)['id'] == id));
              if (previousOwner.isNotEmpty ||
                  layouts.entries.any((e) =>
                      e.key != sourceId &&
                      (e.value['categories'] as List)
                          .any((c) => (c as Map)['id'] == id))) {
                throw const Failure(
                    FailureCode.conflict, 'categoryId is globally unique.');
              }
              final spec = {
                'id': id,
                'title': input['title'],
                'content': content,
                if (input['sort'] != null) 'sort': input['sort'],
                'coverWorkIds': input['coverWorkIds'] ?? []
              };
              if (input['sort'] != null &&
                  !_sorts(spec).any((s) => s.id == input['sort']))
                throw const Failure(
                    FailureCode.invalidInput, 'Unknown category sort.');
              final at = categories.indexWhere((c) => c['id'] == id);
              if (at < 0)
                categories.add(spec);
              else
                categories[at] = spec;
              layout['original'] = false;
            case 'move':
              final at =
                  categories.indexWhere((c) => c['id'] == input['categoryId']);
              final index = input['index'] as int;
              if (at < 0 || index < 0 || index >= categories.length)
                throw const Failure(FailureCode.invalidInput,
                    'Index must be inside the arranged category list.');
              categories.insert(index, categories.removeAt(at));
            case 'remove':
              final at =
                  categories.indexWhere((c) => c['id'] == input['categoryId']);
              if (at < 0)
                throw const Failure(
                    FailureCode.notFound, 'Unknown arranged category.');
              categories.removeAt(at);
              if (categories.isEmpty) layout['original'] = true;
          }
          layout['categories'] = categories;
          sourceTitles.add(switch (operation) {
            'put' => '已整理片库类别',
            'remove' => '已移除整理类别',
            'move' => '已调整整理类别顺序',
            _ => '已调整片库显示'
          });
          sourceEffects.add({'operation': operation, ...input});
        }
        await db.transaction((tx) async {
          for (final entry in layouts.entries) {
            final before = await _layout(entry.key, tx: tx);
            await tx.insert(
                'ui_cache',
                {
                  'id': 'library:layout:${entry.key}',
                  'fingerprint': 'arrangement',
                  'payload': jsonEncode(entry.value)
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
            await tx.insert('body_changes', {
              'at': DateTime.now().toUtc().toIso8601String(),
              'type': 'ui.library_$operation',
              'subject_id': entry.key,
              'actor': invocation.origin == 'gui' ? 'user' : 'agent',
              'origin': invocation.origin,
              'invocation_id': invocation.id,
              'facts': jsonEncode({
                'title': titles[entry.key]!.join('、'),
                'operations': effects[entry.key],
                'before': before,
                'after': entry.value
              })
            });
          }
        });
        ui.notifyLibraryChanged();
        return {'sources': layouts.values.toList()};
      });
  @override
  Future<void> setForm(String sourceId, UiLibraryForm form) async {
    await mutate(
        'configure',
        [
          {'sourceId': sourceId, 'form': form.name}
        ],
        Invocation(origin: 'gui'));
  }

  @override
  Future<void> useOriginal(String sourceId, bool original) async {
    await mutate(
        'configure',
        [
          {'sourceId': sourceId, 'original': original}
        ],
        Invocation(origin: 'gui'));
  }

  @override
  Future<void> moveCategory(String categoryId, int index) async {
    await mutate(
        'move',
        [
          {'categoryId': categoryId, 'index': index}
        ],
        Invocation(origin: 'gui'));
  }

  @override
  Future<void> removeCategory(String categoryId) async {
    await mutate(
        'remove',
        [
          {'categoryId': categoryId}
        ],
        Invocation(origin: 'gui'));
  }
}
