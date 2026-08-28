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

Future<void> _deleteAnimeIfUnreferenced(
  DatabaseExecutor executor,
  int animeId,
) async {
  await executor.rawDelete(
    'DELETE FROM anime '
    'WHERE anime_id = ? '
    'AND NOT EXISTS (SELECT 1 FROM episode WHERE anime_id = ?) '
    'AND NOT EXISTS (SELECT 1 FROM dandanplay_anime WHERE anime_id = ?) '
    'AND NOT EXISTS (SELECT 1 FROM bangumi_anime WHERE anime_id = ?)',
    <Object>[animeId, animeId, animeId, animeId],
  );
}

Future<void> _deleteEpisodeIfUnreferenced(
  DatabaseExecutor executor,
  int episodeId,
) async {
  final animeId = await _readIntColumn(
    executor,
    'episode',
    'anime_id',
    'episode_id',
    episodeId,
  );
  final deleted = await executor.rawDelete(
    'DELETE FROM episode '
    'WHERE episode_id = ? '
    'AND NOT EXISTS (SELECT 1 FROM dandanplay_episode '
    'WHERE episode_id = ?) '
    'AND NOT EXISTS (SELECT 1 FROM bangumi_episode WHERE episode_id = ?) '
    'AND NOT EXISTS (SELECT 1 FROM asset_episode WHERE episode_id = ?)',
    <Object>[episodeId, episodeId, episodeId, episodeId],
  );
  if (deleted > 0 && animeId != null) {
    await _deleteAnimeIfUnreferenced(executor, animeId);
  }
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
