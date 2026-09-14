
// lib/services/database/database_service.dart
// 数据库的公开访问入口

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/database/anime_episode_relation.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/services/database/sql.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

part 'database_anime_episode_repository.dart';
part 'database_asset_repository.dart';
part 'database_debug.dart';
part 'database_repository_support.dart';


class DatabaseService {

  static String?   _path;
  static Database? _database;

  static Future<void> initialize(String dbFilePath) async {

    sqfliteFfiInit();
    await DatabaseSql.load();

    final database = await databaseFactoryFfi.openDatabase(
      dbFilePath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          final existing = await db.rawQuery("SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
              "AND name != 'android_metadata'");
          if (existing.isNotEmpty && !await _isUnifiedDatabase(db)) {
            throw StateError('不是 NipaPlay 统一媒体数据库，拒绝修改: $dbFilePath');
          }
          await db.execute(DatabaseSql.enableForeignKeys);
        },
        onCreate: (db, _) async {
          for (final sql in DatabaseSql.createTables ) { await db.execute(sql); }
          for (final sql in DatabaseSql.createIndexes) { await db.execute(sql); }
        },
        onUpgrade: (db, oldVersion, _) async {
          // This is the unified database only. Never stamp or migrate a legacy
          // watch_history.db accidentally supplied by a caller.
          if (oldVersion != 2 || !await _isUnifiedDatabase(db)) {
            throw StateError('不支持的数据库，拒绝修改原有数据: $dbFilePath');
          }
          await db.execute('ALTER TABLE anime ADD COLUMN merged_into INTEGER '
              'REFERENCES anime (anime_id) CHECK (merged_into != anime_id)');
          await db.execute('ALTER TABLE episode ADD COLUMN merged_into INTEGER '
              'REFERENCES episode (episode_id) CHECK (merged_into != episode_id)');
          for (final sql in DatabaseSql.mergeIndexes) { await db.execute(sql); }
        },
        onOpen: (db) async {
          if (!await _isUnifiedDatabase(db)) {
            throw StateError('不是 NipaPlay 统一媒体数据库: $dbFilePath');
          }
        },
      ),
    );

    _path     = dbFilePath;
    _database = database;
  }

  static Future<void> close() async {
    final database = _database;
    _database = null;
    _path = null;
    await database?.close();
  }


  // 数据库操作方法
  // ======================================================================== //
  static Future<void> upsertSourceAnimeEpisodeRelation(AniEpiRltType type, AniEpiRlt relation)  => _withDb((db) => _AnimeEpisodeRepository(db).upsert(relation, type));
  static Future<void> upsertAssetRecord               (DbAssetRecord asset)                     => _withDb((db) => _AssetRepository(db)       .upsert(asset));

  static Future<void> linkSourceAnimeToCommonAnime    (AniEpiRltType type, int typAniId, int comAniId) => _withDb((db) => _AnimeEpisodeRepository(db).linkAnime    (type, typAniId, comAniId));
  static Future<void> linkSourceEpisodeToCommonEpisode(AniEpiRltType type, int typEpiId, int comEpiId) => _withDb((db) => _AnimeEpisodeRepository(db).linkEpisode  (type, typEpiId, comEpiId));
  static Future<void> linkVideoAssetToEpisode                           (Uint8List hash, int comEpiId) => _withDb((db) => _AssetRepository       (db).linkToEpisode(hash, comEpiId));


  // getters
  // ======================================================================== //

  // 检查数据库中是否存在指定的 Anime/Episode 记录
  static Future<bool> hasAnime   (AniEpiRltType type, int aniId) => _withDb((db) => _AnimeEpisodeRepository(db).hasAnime  (type, aniId));
  static Future<bool> hasEpisode (AniEpiRltType type, int epiId) => _withDb((db) => _AnimeEpisodeRepository(db).hasEpisode(type, epiId));

  // 外部数据源 ID 与共通 ID 之间双向转换
  static Future<int?>     getCommonAnimeId  (AniEpiRltType type, int srcAniId) => _withDb((db) => _AnimeEpisodeRepository(db).findCommonAnimeId  (type, srcAniId));
  static Future<int?>     getSourceAnimeId  (AniEpiRltType type, int comAniId) => _withDb((db) => _AnimeEpisodeRepository(db).findSourceAnimeId  (type, comAniId));
  static Future<int?>     getCommonEpisodeId(AniEpiRltType type, int srcEpiId) => _withDb((db) => _AnimeEpisodeRepository(db).findCommonEpisodeId(type, srcEpiId));
  static Future<int?>     getSourceEpisodeId(AniEpiRltType type, int comEpiId) => _withDb((db) => _AnimeEpisodeRepository(db).findSourceEpisodeId(type, comEpiId));
  static Future<Set<int>> getAllAnimeIds    (AniEpiRltType type              ) => _withDb((db) => _AnimeEpisodeRepository(db).findAllAnimeIds    (type          ));
  static Future<Set<int>> getAllEpisodeIds  (AniEpiRltType type, int aniId   ) => _withDb((db) => _AnimeEpisodeRepository(db).findAllEpisodeIds  (type, aniId   ));

  // 获取视频资产记录和关联信息
  static Future<DbAssetRecord?>      getAssetRecord     (Uint8List hash) =>_withDb((db) => _AssetRepository(db).find(hash));
  static Future<int?> getCommonEpisodeIdByAssetHash(Uint8List hash) =>_withDb((db) => _AssetRepository(db).findCommonEpisodeId(hash));
  static Future<int?> getDandanplayEpisodeIdByAssetHash(Uint8List hash) =>_withDb((db) => _AssetRepository(db).findDandanplayEpisodeId(hash));

  /// Serialize metadata access with ID merges. IDs are ordered with the
  /// canonical record last, so its explicitly saved fields take precedence.
  /// Original JSON files remain intact; SQL redirects make them reachable.
  static Future<T> withAnimeJsonIds<T>(int id, Future<T> Function(List<int>) operation) =>
      _withDb((db) => db.transaction((txn) async =>
          operation(await _jsonIds(txn, 'anime', id))));

  static Future<T> withEpisodeJsonIds<T>(int id, Future<T> Function(List<int>) operation) =>
      _withDb((db) => db.transaction((txn) async =>
          operation(await _jsonIds(txn, 'episode', id))));


  // debug
  // ======================================================================== //

  static String getInfo() => 'DatabaseService: path=$_path';
  static Future<void> printAnimeEpisodeTables() =>_withDb((db) => _DatabaseDebugPrinter(db).printTables());
  static Future<String> getTableNames() =>_withDb((db) async {
    final tables = await db.rawQuery(DatabaseSql.selectTableNames);
    return 'DatabaseService: tables=${tables.map((row) => row['name']).join(', ')}';
  });

  static Future<String> buildAnimeEpisodeRelationReport({
    required Map<int, String> dandanplayAnimeTitles,
    required Map<int, String> bangumiAnimeTitles,
    required Map<int, String> dandanplayEpisodeTitles,
    required Map<int, String> bangumiEpisodeTitles,
  }) => _withDb(
    (db) => _DatabaseDebugPrinter(db).printAnimeEpisodeRelations(
      dandanplayAnimeTitles: dandanplayAnimeTitles,
      bangumiAnimeTitles: bangumiAnimeTitles,
      dandanplayEpisodeTitles: dandanplayEpisodeTitles,
      bangumiEpisodeTitles: bangumiEpisodeTitles,
    ),
  );


  // 私有方法
  // ======================================================================== //

  static Future<T> _withDb<T>(Future<T> Function(Database database) operation) {

    final database = _database;
    if (database == null) throw StateError('DatabaseService 未初始化');

    return operation(database);
  }
}
