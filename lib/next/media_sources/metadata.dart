import 'package:nipa_harness/nipa_harness.dart';
import '../media/identity_store.dart';

JsonMap sourceProvenance(JsonMap source, String itemId, String observedAt) => {
      'sourceId': source['sourceId'],
      'type': source['type'],
      'name': source['name'],
      'url': source['address'],
      'itemId': itemId,
      'observedAt': observedAt,
    };

/// Preserve the source's own hierarchy and rich facts without accepting its
/// ProviderIds as cross-provider matches. Agents can inspect those candidates.
List<JsonMap> sourceCatalogRecords(String sourceId, JsonMap item) {
  final kind = item['kind'];
  if (!const {'Series', 'Season', 'Episode', 'Movie', 'Video', 'File'}
      .contains(kind)) return [];
  final m = Map<String, Object?>.from(item['metadata'] as Map? ?? const {});
  final itemId = item['id'] as String;
  final serverId = item['serverId'] as String?;
  final workItem = kind == 'Series' || kind == 'Movie'
      ? itemId
      : '${m['SeriesId'] ?? itemId}';
  final releaseItem =
      kind == 'Season' ? itemId : '${m['SeasonId'] ?? '$workItem/default'}';
  String id(String kind, String item) =>
      sourceCatalogId(kind, sourceId, item, serverId: serverId);
  final workId = id('work', workItem), releaseId = id('release', releaseItem);
  final ownWork = const {'Series', 'Movie', 'Video', 'File'}.contains(kind);
  final studios = [
    for (final s in (m['Studios'] as List? ?? const []))
      if (s is Map && s['Name'] is String) s['Name']
  ];
  final fields = <String, Object?>{
    'title': item['name'],
    if (m['OriginalTitle'] != null) 'originalTitle': m['OriginalTitle'],
    if (m['Overview'] != null) 'overview': m['Overview'],
    if (m['ProductionYear'] != null) 'year': m['ProductionYear'],
    if (m['Genres'] != null) 'genres': m['Genres'],
    if (m['Tags'] != null) 'tags': m['Tags'],
    if (m['IndexNumber'] != null) 'number': '${m['IndexNumber']}',
    if (m['ParentIndexNumber'] != null) 'season': m['ParentIndexNumber'],
    if (m['EpisodeCount'] != null) 'episodeCount': m['EpisodeCount'],
    if (m['RunTimeTicks'] is num)
      'runtimeMs': (m['RunTimeTicks'] as num).toInt() ~/ 10000,
    if (m['PremiereDate'] != null) 'firstAirDate': m['PremiereDate'],
    if (studios.isNotEmpty) ...{'studio': studios.first, 'studios': studios},
    if (m['CommunityRating'] is num)
      'rating': {'value': m['CommunityRating'], 'max': 10, 'label': '服务器'},
    if (m['People'] is List)
      'credits': {
        for (final group in ['cast', 'crew'])
          group: [
            for (final p in (m['People'] as List).whereType<Map>())
              if ((p['Type'] == 'Actor') == (group == 'cast'))
                {'name': p['Name'], 'role': p['Role'] ?? p['Type']},
          ],
      },
    'sourceProviderIds': m['ProviderIds'] ?? const {},
    'providerData': m,
  };
  JsonMap record(String kind, String itemId, String? parent, JsonMap fields,
          {bool placeholder = false}) =>
      {
        'id': id(kind, itemId),
        'kind': kind,
        'parentId': parent,
        'objectType': kind == 'work'
            ? (item['kind'] == 'Movie' ? 'movie' : 'tv')
            : kind == 'release'
                ? 'season'
                : 'episode',
        'film': item['kind'] == 'Movie',
        'fields': fields,
        'placeholder': placeholder,
        'source': {
          'sourceId': sourceId,
          'serverId': serverId,
          'itemId': itemId
        },
      };
  return [
    record('work', workItem, null,
        ownWork ? fields : {'title': m['SeriesName'] ?? item['name']},
        placeholder: !ownWork),
    if (kind != 'Series')
      record(
          'release',
          releaseItem,
          workId,
          kind == 'Season'
              ? fields
              : {'title': m['SeasonName'] ?? m['SeriesName'] ?? item['name']},
          placeholder: kind != 'Season'),
    if (kind != 'Series' && kind != 'Season')
      {
        ...record('episode', itemId, releaseId, fields),
        if (item['fileId'] != null) 'fileId': item['fileId'],
      },
  ];
}
