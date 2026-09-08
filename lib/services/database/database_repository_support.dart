part of 'database_service.dart';

typedef _RelationSchema = ({
  String animeTable,
  String animeSourceId,
  String episodeTable,
  String episodeSourceId,
});

_RelationSchema _relationSchema(AniEpiRltType type) => switch (type) {
      AniEpiRltType.common => (
          animeTable: 'anime',
          animeSourceId: 'anime_id',
          episodeTable: 'episode',
          episodeSourceId: 'episode_id',
        ),
      AniEpiRltType.dandanplay => (
          animeTable: 'dandanplay_anime',
          animeSourceId: 'dandanplay_anime_id',
          episodeTable: 'dandanplay_episode',
          episodeSourceId: 'dandanplay_episode_id',
        ),
      AniEpiRltType.bangumi => (
          animeTable: 'bangumi_anime',
          animeSourceId: 'bangumi_anime_id',
          episodeTable: 'bangumi_episode',
          episodeSourceId: 'bangumi_episode_id',
        ),
    };

Future<int> _createAnime(DatabaseExecutor executor) =>
    executor.rawInsert(DatabaseSql.insertAnime);

Future<int> _createEpisode(DatabaseExecutor executor, int animeId) =>
    executor.insert(
      'episode',
      <String, Object?>{'anime_id': animeId},
    );

Future<int?> _readIntColumn(
  DatabaseExecutor executor,
  String table,
  String column,
  String keyColumn,
  Object keyValue,
) async {
  final rows = await executor.query(
    table,
    columns: <String>[column],
    where: '$keyColumn = ?',
    whereArgs: <Object>[keyValue],
    limit: 1,
  );
  return _firstInt(rows, column);
}

int? _firstInt(List<Map<String, Object?>> rows, String column) {
  if (rows.isEmpty) return null;
  final value = rows.first[column];
  return value is num ? value.toInt() : null;
}

Future<bool> _hasRow(
  DatabaseExecutor executor,
  String table,
  String column,
  Object value,
) async {
  final rows = await executor.query(
    table,
    columns: <String>[column],
    where: '$column = ?',
    whereArgs: <Object>[value],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<bool> _isUnifiedDatabase(DatabaseExecutor executor) async {
  for (final table in const ['anime', 'episode', 'dandanplay_anime',
      'dandanplay_episode', 'bangumi_anime', 'bangumi_episode', 'asset',
      'asset_episode', 'path_asset', 'net_asset']) {
    if (!await _hasRow(executor, 'sqlite_master', 'name', table)) return false;
  }
  return true;
}

Future<int?> _canonicalId(DatabaseExecutor executor, String table, int id) async {
  _requireNonNegative(id, '${table}Id');
  final visited = <int>{};
  while (visited.add(id)) {
    final rows = await executor.query(table,
        columns: ['merged_into'], where: '${table}_id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final target = rows.single['merged_into'] as int?;
    if (target == null) return id;
    id = target;
  }
  throw StateError('数据库中的 $table ID 重定向形成循环');
}

Future<void> _markMerged(
  DatabaseExecutor executor, String table, int oldId, int targetId,
) async {
  if (oldId == targetId) return;
  // Keep the old row to reserve its ID forever. Keep the redirect chain as
  // well: an intermediate canonical JSON must override its older ancestors.
  await executor.update(table, {'merged_into': targetId},
      where: '${table}_id = ?', whereArgs: [oldId]);
}

Future<List<int>> _jsonIds(DatabaseExecutor executor, String table, int id) async {
  final target = await _canonicalId(executor, table, id);
  if (target == null) throw StateError('不存在的 $table ID: $id');
  final rows = await executor.rawQuery('''
    WITH RECURSIVE metadata_ids(id, depth) AS (
      SELECT ?, 0
      UNION ALL
      SELECT item.${table}_id, parent.depth + 1
      FROM $table item JOIN metadata_ids parent ON item.merged_into = parent.id
    )
    SELECT id FROM metadata_ids ORDER BY depth DESC, id ASC
  ''', [target]);
  return rows.map((row) => row['id'] as int).toList();
}

Future<void> _redirectEpisodeIfUnreferenced(
  DatabaseExecutor executor,
  int episodeId,
  int targetId,
) async {
  for (final table in const ['dandanplay_episode', 'bangumi_episode', 'asset_episode']) {
    if (await _hasRow(executor, table, 'episode_id', episodeId)) return;
  }
  await _markMerged(executor, 'episode', episodeId, targetId);
  final animeId = await _readIntColumn(executor, 'episode', 'anime_id', 'episode_id', episodeId);
  final targetAnimeId = await _readIntColumn(executor, 'episode', 'anime_id', 'episode_id', targetId);
  if (animeId == null || targetAnimeId == null || animeId == targetAnimeId) return;
  for (final table in const ['dandanplay_anime', 'bangumi_anime']) {
    if (await _hasRow(executor, table, 'anime_id', animeId)) return;
  }
  final activeEpisodes = await executor.query('episode', columns: ['episode_id'],
      where: 'anime_id = ? AND merged_into IS NULL', whereArgs: [animeId], limit: 1);
  if (activeEpisodes.isEmpty) await _markMerged(executor, 'anime', animeId, targetAnimeId);
}

Uint8List _validateHash(Uint8List value, int expectedBytes) {
  if (value.length != expectedBytes) {
    throw FormatException('哈希必须为 $expectedBytes 字节');
  }
  return Uint8List.fromList(value);
}

void _requireNonNegative(int value, String name) {
  if (value < 0) throw ArgumentError.value(value, name, '不能小于 0');
}
