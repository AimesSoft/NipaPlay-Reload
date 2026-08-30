part of 'database_service.dart';

class _AssetRepository {
  const _AssetRepository(this.database);

  final Database database;

  Future<void> upsert(DbAssetRecord asset) async {

    final size = asset.size;
    if (size != null && size < 0) throw ArgumentError.value(size, 'asset.size', '不能小于 0');
    final hash = _validateHash(asset.hashPre16MiBMd5, 16);
    final sha256 = asset.hashSha256 == null ? null : _validateHash(asset.hashSha256!, 32);

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


  Future<void> upsertPathRecord(DbPathAssetRecord asset) async {


    final upsertDateTime = DateTime.now().toIso8601String();

    final hash = asset.hashPre16MiBMd5 == null ? null : _validateHash(asset.hashPre16MiBMd5!, 16);
    final sourceId = asset.assetPath.mediaSourceId;
    if (sourceId < 0) throw ArgumentError.value(sourceId, 'asset.sourceId', '不能小于 0');

    final address = asset.assetPath.pathInSource.path;
    final nameNoExt = asset.assetPath.pathInSource.nameNoExt;
    final ext = asset.assetPath.pathInSource.ext;
    final createdAt = asset.createdAt;
    final updatedAt = asset.updatedAt;

    // 事务中执行插入或更新操作
    await database.transaction((txn) async {
      final values = <String, Object?>{
        'asset_pre16mib_md5': hash,
        'asset_created_at': createdAt,
        'asset_updated_at': updatedAt,
        'updated_at': upsertDateTime,
      };
      final updated = await txn.update(
        'path_asset',
        values,
        where: 'source_id = ? AND asset_address = ? AND asset_name_no_ext = ? AND asset_extension = ?',
        whereArgs: <Object?>[sourceId, address, nameNoExt, ext],
      );
      if (updated == 0) {
        await txn.insert(
          'path_asset',
          <String, Object?>{
            'source_id': sourceId,
            'asset_address': address,
            'asset_name_no_ext': nameNoExt,
            'asset_extension': ext,
            ...values,
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

      final oldEpisodeId = await _readIntColumn(txn, 'asset_episode', 'episode_id', 'asset_pre16mib_md5', hash);
      if (oldEpisodeId == null) throw StateError('关联 Episode 前必须先写入视频资产记录');

      final animeId = await _readIntColumn(txn, 'episode', 'anime_id', 'episode_id', oldEpisodeId);
      if (animeId == null) throw StateError('视频资产关联的通用 Episode 不存在');

      // 插入共通剧集记录
      await txn.insert(
        'episode',
        <String, Object?>{
          'episode_id': episodeId,
          'anime_id': animeId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (oldEpisodeId == episodeId) return;

      // 更新视频资产关联的共通剧集 ID
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

  Future<int?> findDandanplayEpisodeId(Uint8List assetHash) async {
    final commonEpisodeId = await findCommonEpisodeId(assetHash);
    if (commonEpisodeId == null) return null;
    return _readIntColumn(
      database,
      'dandanplay_episode',
      'dandanplay_episode_id',
      'episode_id',
      commonEpisodeId,
    );
  }

  /// 给定媒体源 ID 和文件路径集合
  /// 1. 插入更新 filePaths
  /// 2. 删除数据库中媒体源 ID 为 sourceId, 且文件路径不在 filePaths 中的所有视频资产路径记录
  Future<void> synchronizeRecords(int sourceId, Set<AssetPathInSource> filePaths) async {

    _requireNonNegative(sourceId, 'sourceId');


    // 插入或更新所有文件路径记录
    int count = 0;
    for (final filePath in filePaths) {
      final assetPath = AssetPath(
        mediaSourceId: sourceId,
        pathInSource: filePath,
      );
      final pathRecord = DbPathAssetRecord(assetPath: assetPath);
      await upsertPathRecord(pathRecord);
      count++;
    }
    debugPrint('已插入或更新 $count 条媒体源 ID=$sourceId 的文件路径记录');

    // 删除数据库中媒体源 ID 为 sourceId, 且文件路径不在 filePaths 中的所有视频资产路径记录
    await database.transaction((txn) async {

      // 查询数据库中媒体源 ID 为 sourceId 的所有文件路径记录
      final existingPaths = await txn.query(
        'path_asset',
        columns: const <String>['asset_address', 'asset_name_no_ext', 'asset_extension'],
        where: 'source_id = ?',
        whereArgs: <Object?>[sourceId],
      );

      int deletedCount = 0;
      for (final row in existingPaths) {
        final path = row['asset_address'] as String;
        final nameNoExt = row['asset_name_no_ext'] as String;
        final ext = row['asset_extension'] as String;

        bool exists = false;
        for (final filePath in filePaths) {
          if (filePath.path == path && filePath.nameNoExt == nameNoExt && filePath.ext == ext) {
            // 文件路径存在于 filePaths 中, 跳过删除
            exists = true;
            break;
          }
        }
        if (!exists) {
          await txn.delete(
            'path_asset',
            where: 'source_id = ? AND asset_address = ? AND asset_name_no_ext = ? AND asset_extension = ?',
            whereArgs: <Object?>[sourceId, path, nameNoExt, ext],
          );
          deletedCount++;
        }
      }

      debugPrint('已删除 $deletedCount 条媒体源 ID=$sourceId 的文件路径记录');
    });
  }

  Future<Set<AssetPathInSource>> getAssetPathRecordsNoHash(int sourceId) async {
    final rows = await database.query(
      'path_asset',
      columns: const <String>['asset_address', 'asset_name_no_ext', 'asset_extension'],
      where: 'source_id = ? AND asset_pre16mib_md5 IS NULL',
      whereArgs: <Object?>[sourceId],
    );
    final result = <AssetPathInSource>{};
    for (final row in rows) {
      result.add(AssetPathInSource(
        path: row['asset_address'] as String,
        nameNoExt: row['asset_name_no_ext'] as String,
        ext: row['asset_extension'] as String,
      ));
    }
    return result;
  }
}