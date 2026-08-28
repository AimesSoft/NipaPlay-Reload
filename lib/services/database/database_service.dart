
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

  static const int linkDandanplay = 0x1;
  static const int linkBangumi = 0x2;
  static const int defaultLinkOptions = 0xFFFFFFFF;

  static String? _path;
  static Database? _database;


  static Future<void> initialize(String dbFilePath) async {

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseSql.load();

    final database = await openDatabase(
      dbFilePath,
      version: 2,
      onConfigure: (db) => db.execute(DatabaseSql.enableForeignKeys),
      onCreate: (db, _) async {
        for (final sql in DatabaseSql.createTables ) { await db.execute(sql); }
        for (final sql in DatabaseSql.createIndexes) { await db.execute(sql); }
      },
    );

    _path = dbFilePath;
    _database = database;
  }


  // 数据库操作方法
  // ======================================================================== //
  static Future<void> upsertAnimeEpisodeRelation(AniEpiRlt relation, AniEpiRltType type)  => _withDb((db) => _AnimeEpisodeRepository(db).upsert(relation, type));
  static Future<void> upsertAssetRecord(DbAssetRecord asset)                              => _withDb((db) => _AssetRepository(db).upsert(asset));

  static Future<void> linkToAnime  (AniEpiRltType type, int typAniId, int comAniId) => _withDb((db) => _AnimeEpisodeRepository(db).linkAnime    (type, typAniId, comAniId));
  static Future<void> linkToEpisode(AniEpiRltType type, int typEpiId, int comEpiId) => _withDb((db) => _AnimeEpisodeRepository(db).linkEpisode  (type, typEpiId, comEpiId));
  static Future<void> linkVideoAssetToEpisode        (Uint8List hash, int comEpiId) => _withDb((db) => _AssetRepository       (db).linkToEpisode(hash, comEpiId));


  // getters
  // ======================================================================== //

  // 检查数据库中是否存在指定的 Anime/Episode 记录
  static Future<bool> hasAnime   (AniEpiRltType type, int aniId) => _withDb((db) => _AnimeEpisodeRepository(db).hasAnime  (type, aniId));
  static Future<bool> hasEpisode (AniEpiRltType type, int epiId) => _withDb((db) => _AnimeEpisodeRepository(db).hasEpisode(type, epiId));

  // 外部数据源 ID 与共通 ID 之间双向转换
  static Future<int?>     getCommonAnimeId  (AniEpiRltType type, int srcAniId) =>_withDb((db) => _AnimeEpisodeRepository(db).findCommonAnimeId  (type, srcAniId));
  static Future<int?>     getSourceAnimeId  (AniEpiRltType type, int comAniId) =>_withDb((db) => _AnimeEpisodeRepository(db).findSourceAnimeId  (type, comAniId));
  static Future<int?>     getCommonEpisodeId(AniEpiRltType type, int srcEpiId) =>_withDb((db) => _AnimeEpisodeRepository(db).findCommonEpisodeId(type, srcEpiId));
  static Future<int?>     getSourceEpisodeId(AniEpiRltType type, int comEpiId) =>_withDb((db) => _AnimeEpisodeRepository(db).findSourceEpisodeId(type, comEpiId));
  static Future<Set<int>> getAllAnimeIds    (AniEpiRltType type              ) =>_withDb((db) => _AnimeEpisodeRepository(db).findAllAnimeIds    (type          ));
  static Future<Set<int>> getAllEpisodeIds  (AniEpiRltType type, int aniId   ) =>_withDb((db) => _AnimeEpisodeRepository(db).findAllEpisodeIds  (type, aniId   ));

  // 获取视频资产记录和关联信息
  static Future<DbAssetRecord?>      getAssetRecord     (Uint8List hash) =>_withDb((db) => _AssetRepository(db).find(hash));
  static Future<int?> getCommonEpisodeIdByAssetHash(Uint8List hash) =>_withDb((db) => _AssetRepository(db).findCommonEpisodeId(hash));


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
