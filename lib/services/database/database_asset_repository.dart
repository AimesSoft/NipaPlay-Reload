part of 'database_service.dart';

class _AssetRepository {
  const _AssetRepository(this.database);

  final Database database;

  Future<void> upsert(DbAssetRecord asset) async {
    final size = asset.size;
    if (size != null && size < 0) {
      throw ArgumentError.value(size, 'asset.size', '不能小于 0');
    }
    final hash = _validateHash(asset.hashPre16MiBMd5, 16);
    final sha256 =
        asset.hashSha256 == null ? null : _validateHash(asset.hashSha256!, 32);

    await database.transaction((txn) async {
      final values = <String, Object?>{
        'asset_size': size,
        'asset_codec': asset.codec,
        'asset_sha256': sha256,
      };
      final updated = await txn.update(
        'asset',
        values,
        where: 'asset_pre16mib_md5 = ?',
        whereArgs: <Object?>[hash],
      );
      if (updated == 0) {
        await txn.insert(
          'asset',
          <String, Object?>{'asset_pre16mib_md5': hash, ...values},
        );
      }
      if (!await _hasRow(
        txn,
        'asset_episode',
        'asset_pre16mib_md5',
        hash,
      )) {
        final episodeId = await _createEpisode(txn, await _createAnime(txn));
        await txn.insert(
          'asset_episode',
          <String, Object?>{
            'asset_pre16mib_md5': hash,
            'episode_id': episodeId,
          },
        );
      }
    });
  }

  Future<DbAssetRecord?> find(Uint8List assetHash) async {
    final hash = _validateHash(assetHash, 16);
    final rows = await database.query(
      'asset',
      columns: const <String>[
        'asset_pre16mib_md5',
        'asset_size',
        'asset_codec',
        'asset_sha256',
      ],
      where: 'asset_pre16mib_md5 = ?',
      whereArgs: <Object?>[hash],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final storedHash = row['asset_pre16mib_md5'] as Uint8List;
    final sha256 = row['asset_sha256'] as Uint8List?;
    return DbAssetRecord(
      hashPre16MiBMd5: Uint8List.fromList(storedHash),
      size: (row['asset_size'] as num?)?.toInt(),
      codec: row['asset_codec'] as String?,
      hashSha256: sha256 == null ? null : Uint8List.fromList(sha256),
    );
  }

  Future<void> linkToEpisode(Uint8List assetHash, int episodeId) async {
    _requireNonNegative(episodeId, 'episodeId');
    final hash = _validateHash(assetHash, 16);

    await database.transaction((txn) async {
      final oldEpisodeId = await _readIntColumn(
        txn,
        'asset_episode',
        'episode_id',
        'asset_pre16mib_md5',
        hash,
      );
      if (oldEpisodeId == null) {
        throw StateError('关联 Episode 前必须先写入视频资产记录');
      }
      final animeId = await _readIntColumn(
        txn,
        'episode',
        'anime_id',
        'episode_id',
        oldEpisodeId,
      );
      if (animeId == null) {
        throw StateError('视频资产关联的通用 Episode 不存在');
      }
      await txn.insert(
        'episode',
        <String, Object?>{
          'episode_id': episodeId,
          'anime_id': animeId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (oldEpisodeId == episodeId) return;

      await txn.update(
        'asset_episode',
        <String, Object?>{'episode_id': episodeId},
        where: 'asset_pre16mib_md5 = ?',
        whereArgs: <Object?>[hash],
      );
      await _deleteEpisodeIfUnreferenced(txn, oldEpisodeId);
    });
  }

  Future<int?> findCommonEpisodeId(Uint8List assetHash) {
    return _readIntColumn(
      database,
      'asset_episode',
      'episode_id',
      'asset_pre16mib_md5',
      _validateHash(assetHash, 16),
    );
  }

  Future<void> setLinkOptions(Uint8List hash, int value) =>
      _updateEpisode(hash, <String, Object?>{
        'link_options': _encodeUint32(value),
      });

  Future<DbAssetEpisodeInfo?> findEpisodeInfo(Uint8List hash) async {
    final rows = await database.query(
      'asset_episode',
      columns: const <String>[
        'link_options',
        'danmaku_offset_dandanplay',
        'danmaku_offset_user',
        'duration',
        'internal_subtitle_track_count',
      ],
      where: 'asset_pre16mib_md5 = ?',
      whereArgs: <Object?>[_validateHash(hash, 16)],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return DbAssetEpisodeInfo(
      linkOptions: _decodeUint32(row['link_options'] as Uint8List),
      dandanplayDanmakuOffset:
          (row['danmaku_offset_dandanplay'] as num).toDouble(),
      userDanmakuOffset: (row['danmaku_offset_user'] as num).toDouble(),
      duration: (row['duration'] as num?)?.toInt(),
      internalSubtitleTrackCount:
          (row['internal_subtitle_track_count'] as num?)?.toInt(),
    );
  }

  Future<void> setDanmakuOffsets(
    Uint8List hash, {
    double? dandanplay,
    double? user,
  }) async {
    final values = <String, Object?>{
      if (dandanplay != null) 'danmaku_offset_dandanplay': dandanplay,
      if (user != null) 'danmaku_offset_user': user,
    };
    if (values.isNotEmpty) await _updateEpisode(hash, values);
  }

  Future<void> _updateEpisode(
    Uint8List hash,
    Map<String, Object?> values,
  ) async {
    final updated = await database.update(
      'asset_episode',
      values,
      where: 'asset_pre16mib_md5 = ?',
      whereArgs: <Object?>[_validateHash(hash, 16)],
    );
    if (updated == 0) throw StateError('视频资产尚未写入 asset_episode');
  }
}
