import 'dart:io';

import 'package:nipaplay/models/bangumi_model.dart';

import 'identity_store.dart';

/// A read projection only. Classic caches and personal ratings stay untouched.
final class ClassicMetadataView {
  const ClassicMetadataView(this.store);
  final IdentityStore store;

  Future<BangumiAnime> apply(BangumiAnime anime) async {
    final works = await store.database.rawQuery(
        'SELECT DISTINCT e.id FROM media_entities e JOIN media_bindings b ON b.entity_id=e.id '
        'JOIN media_external_objects o ON o.id=b.object_id WHERE e.kind=? AND b.status=? '
        'AND o.provider=? AND o.object_type=? AND o.external_id=? AND o.scope=?',
        ['work', 'accepted', 'dandanplay', 'anime', '${anime.id}', '']);
    // Conflicting owners are visible to the agent in Next; Classic keeps its own data.
    if (works.length != 1) return anime;
    return _applyWork(anime, works.single['id'] as String);
  }

  Future<BangumiAnime> applyForPath(String path, BangumiAnime anime) async {
    // Streams and unmounted shares have no local file to resolve.
    final file = File(path);
    final canonicalPath =
        await file.exists() ? await file.resolveSymbolicLinks() : path;
    final works = await store.database.rawQuery(
        'SELECT DISTINCT r.parent_id AS id FROM media_locations l '
        'JOIN media_file_episodes f ON f.file_id=l.file_id '
        'JOIN media_entities e ON e.id=f.episode_id JOIN media_entities r ON r.id=e.parent_id '
        'WHERE l.locator IN (?,?) AND l.owner_device_id=?',
        [path, canonicalPath, store.ownerDeviceId]);
    if (works.length != 1) return anime;
    return _applyWork(anime, works.single['id'] as String);
  }

  Future<BangumiAnime> _applyWork(BangumiAnime anime, String workId) async {
    final view = await store.mergedMetadata(workId);
    final fields = view['fields'] as Map;
    final provenance = view['provenance'] as Map;
    final projected = <String, Object?>{
      for (final field in fields.keys)
        if ((provenance[field] as Map)['source'] != 'classic_match')
          field as String: fields[field],
    };
    if (projected.isEmpty) return anime;
    final ratings = <String, dynamic>{...?(anime.ratingDetails)};
    final credits = <String>[];
    for (final entry in {'directors': '导演', 'actors': '主演'}.entries) {
      if (projected[entry.key] case final List names) {
        credits.add('${entry.value}: ${names.join('、')}');
      }
    }
    for (final rating in view['ratings'] as List) {
      final label = rating['label'] ?? rating['source'];
      final key = ratings.containsKey('$label评分')
          ? '$label (${rating['source']})评分'
          : '$label评分';
      ratings[key] =
          (rating['value'] as num).toDouble() * 10 / (rating['max'] as num);
      if (rating['count'] != null) {
        credits.add('$label评价人数: ${rating['count']}');
      }
    }
    // fromJson also preserves explicit null edits, which copyWith cannot express.
    return BangumiAnime.fromJson({
      ...anime.toJson(),
      if (projected.containsKey('title')) ...{
        'name': projected['title'] ?? '',
        'name_cn': projected['title'] ?? '',
      },
      if (projected.containsKey('overview')) 'summary': projected['overview'],
      if (projected.containsKey('imageUrl'))
        'imageUrl': projected['imageUrl'] ?? '',
      if (projected.containsKey('genres')) 'tags': projected['genres'],
      'ratingDetails': ratings,
      'metadata': [...?(anime.metadata), ...credits],
    });
  }
}
