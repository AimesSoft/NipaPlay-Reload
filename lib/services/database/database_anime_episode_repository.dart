
// lib/services/database/database_anime_episode_repository.dart
// 数据库中 Anime/Episode 相关表的操作仓库

part of 'database_service.dart';


class _AnimeEpisodeRepository {

  const _AnimeEpisodeRepository(this.database);

  final Database database;

  /// 将外部动画与剧集关系写入数据库
  Future<void> upsert(AniEpiRlt relation, AniEpiRltType type) async {

    final schema        = _relationSchema(type);
    final sourceAnimeId = relation.animeId;
    final episodeIds    = relation.episodeIds.toSet();

    // 检查 ID 是否为非负数
    _requireNonNegative(sourceAnimeId, '${type.name}AnimeId');
    for (final id in episodeIds) { _requireNonNegative(id, '${type.name}EpisodeId'); }

    // 如果是共通类型, 禁止插入
    if (type == AniEpiRltType.common) {
      debugPrint('[Database] 禁止写入共通 Anime/Episode 关系');
      return;
    }

    // 事务中写入外部动画与剧集关系
    await database.transaction((txn) async {
      final animeId = await _sourceAnimeId(txn, schema, sourceAnimeId) ?? await _createAnime(txn);
      await txn.insert(
        schema.animeTable,
        <String, Object?>{
          schema.animeSourceId: sourceAnimeId,
          'anime_id': animeId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      for (final sourceEpisodeId in episodeIds) {
        await _upsertEpisode(txn, schema, sourceAnimeId, sourceEpisodeId, animeId);
      }
    });
  }

  /// 将外部动画与通用动画关联
  Future<void> linkAnime(AniEpiRltType type, int sourceAnimeId, int commonAnimeId) async {

    if (type == AniEpiRltType.common) throw ArgumentError.value(type, 'type', '共通 Anime 无需关联到自身');

    _requireNonNegative(sourceAnimeId, '${type.name}AnimeId');
    _requireNonNegative(commonAnimeId, 'commonAnimeId');
    final schema = _relationSchema(type);

    await database.transaction((txn) async {

      final oldAnimeId = await _sourceAnimeId(txn, schema, sourceAnimeId);
      if (oldAnimeId == null) throw StateError('关联 Anime 前必须先写入对应的外部动画记录');
      commonAnimeId = await _canonicalId(txn, 'anime', commonAnimeId) ?? commonAnimeId;

      await txn.insert(
        'anime',
        <String, Object?>{'anime_id': commonAnimeId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (oldAnimeId == commonAnimeId) {
        debugPrint(
          '[Database] 关联 Anime: '
          '${type.name} Anime $sourceAnimeId 已经关联到共通 Anime $commonAnimeId',
        );
        return;
      }

      // Merge the whole common identity. UNIQUE conflicts reject ambiguous
      // merges and roll back every relation instead of detaching one source.
      for (final table in const ['dandanplay_anime', 'bangumi_anime', 'episode']) {
        await txn.update(table, {'anime_id': commonAnimeId},
            where: 'anime_id = ?', whereArgs: [oldAnimeId]);
      }
      await _markMerged(txn, 'anime', oldAnimeId, commonAnimeId);
    });

    debugPrint(
      '[Database] 关联 Anime: '
      '${type.name} Anime $sourceAnimeId 关联到共通 Anime $commonAnimeId',
    );
  }

  /// 将外部剧集与通用剧集关联
  Future<void> linkEpisode(AniEpiRltType type, int sourceEpisodeId, int commonEpisodeId) async {

    if (type == AniEpiRltType.common) throw ArgumentError.value(type, 'type', '共通 Episode 无需关联到自身');

    _requireNonNegative(sourceEpisodeId, '${type.name}EpisodeId');
    _requireNonNegative(commonEpisodeId, 'commonEpisodeId');
    final schema = _relationSchema(type);

    await database.transaction((txn) async {

      final oldEpisodeId = await _sourceEpisodeId(txn, schema, sourceEpisodeId);
      if (oldEpisodeId == null) throw StateError('关联 Episode 前必须先写入对应的外部剧集记录');
      commonEpisodeId = await _canonicalId(txn, 'episode', commonEpisodeId) ?? commonEpisodeId;

      // 获取外部剧集对应的通用动画 ID
      final animeId = await _readIntColumn(txn, 'episode', 'anime_id', 'episode_id', oldEpisodeId);
      if (animeId == null) throw StateError('外部剧集关联的通用 Episode 不存在');
      final targetAnimeId = await _readIntColumn(txn, 'episode', 'anime_id', 'episode_id', commonEpisodeId);

      // 如果目标共通剧集的通用动画 ID 与当前外部剧集的通用动画 ID 不一致, 则取消关联
      if (targetAnimeId != null && targetAnimeId != animeId) {
        throw StateError('无法合并属于不同 Anime 的 Episode: $oldEpisodeId -> $commonEpisodeId');
      }

      // 插入共通剧集记录
      await txn.insert(
        'episode',
        <String, Object?>{
          'episode_id': commonEpisodeId,
          'anime_id': animeId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (oldEpisodeId == commonEpisodeId) return;

      for (final table in const ['dandanplay_episode', 'bangumi_episode', 'asset_episode']) {
        await txn.update(table, {'episode_id': commonEpisodeId},
            where: 'episode_id = ?', whereArgs: [oldEpisodeId]);
      }
      await _markMerged(txn, 'episode', oldEpisodeId, commonEpisodeId);
    });
  }

  Future<bool> hasAnime(AniEpiRltType type, int id) {
    final schema = _relationSchema(type);
    return _hasRow(database, schema.animeTable, schema.animeSourceId, id);
  }

  Future<bool> hasEpisode(AniEpiRltType type, int id) {
    final schema = _relationSchema(type);
    return _hasRow(database, schema.episodeTable, schema.episodeSourceId, id);
  }

  Future<int?> findCommonAnimeId(AniEpiRltType type, int sourceAnimeId) {
    if (type == AniEpiRltType.common) return _canonicalId(database, 'anime', sourceAnimeId);
    return _sourceAnimeId(database, _relationSchema(type), sourceAnimeId);
  }

  Future<int?> findSourceAnimeId(AniEpiRltType type, int commonAnimeId) async {
    final canonical = await _canonicalId(database, 'anime', commonAnimeId);
    if (canonical == null) return null;
    final schema = _relationSchema(type);
    return _readIntColumn(
      database,
      schema.animeTable,
      schema.animeSourceId,
      'anime_id',
      canonical,
    );
  }

  Future<Set<int>> findAllAnimeIds(AniEpiRltType type) async {
    final schema = _relationSchema(type);
    final rows = await database.query(
      schema.animeTable,
      columns: <String>[schema.animeSourceId],
      where: type == AniEpiRltType.common ? 'merged_into IS NULL' : null,
      orderBy: schema.animeSourceId,
    );
    return rows
        .map((row) => (row[schema.animeSourceId] as num).toInt())
        .toSet();
  }

  Future<Set<int>> findAllEpisodeIds(
    AniEpiRltType type,
    int animeId,
  ) async {
    _requireNonNegative(animeId, 'animeId');
    if (type == AniEpiRltType.common) {
      final canonical = await _canonicalId(database, 'anime', animeId);
      if (canonical == null) return {};
      animeId = canonical;
    }
    final schema = _relationSchema(type);
    final rows = await database.query(
      schema.episodeTable,
      columns: <String>[schema.episodeSourceId],
      where: '${schema.animeSourceId} = ?'
          '${type == AniEpiRltType.common ? ' AND merged_into IS NULL' : ''}',
      whereArgs: <Object>[animeId],
      orderBy: schema.episodeSourceId,
    );
    return rows
        .map((row) => (row[schema.episodeSourceId] as num).toInt())
        .toSet();
  }

  Future<int?> findCommonEpisodeId(AniEpiRltType type, int sourceEpisodeId) {
    if (type == AniEpiRltType.common) return _canonicalId(database, 'episode', sourceEpisodeId);
    return _sourceEpisodeId(database, _relationSchema(type), sourceEpisodeId);
  }

  Future<int?> findSourceEpisodeId(AniEpiRltType type, int commonEpisodeId) async {
    final canonical = await _canonicalId(database, 'episode', commonEpisodeId);
    if (canonical == null) return null;
    final schema = _relationSchema(type);
    return _readIntColumn(
      database,
      schema.episodeTable,
      schema.episodeSourceId,
      'episode_id',
      canonical,
    );
  }

  Future<int?> _sourceAnimeId(
    DatabaseExecutor executor,
    _RelationSchema schema,
    int sourceId,
  ) =>
      _readIntColumn(
        executor,
        schema.animeTable,
        'anime_id',
        schema.animeSourceId,
        sourceId,
      );

  Future<int?> _sourceEpisodeId(
    DatabaseExecutor executor,
    _RelationSchema schema,
    int sourceId,
  ) =>
      _readIntColumn(
        executor,
        schema.episodeTable,
        'episode_id',
        schema.episodeSourceId,
        sourceId,
      );

  Future<void> _upsertEpisode(
    DatabaseExecutor executor,
    _RelationSchema schema,
    int sourceAnimeId,
    int sourceEpisodeId,
    int animeId,
  ) async {
    if (await _sourceEpisodeId(executor, schema, sourceEpisodeId) != null) {
      return;
    }
    final episodeId = await _createEpisode(executor, animeId);
    await executor.insert(
      schema.episodeTable,
      <String, Object?>{
        schema.episodeSourceId: sourceEpisodeId,
        schema.animeSourceId: sourceAnimeId,
        'episode_id': episodeId,
      },
    );
  }
}
