
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

  static String getInfo() => 'DatabaseService: path=$_path';
  static Future<String> getTableNames() async {
    return _withDb((db) async {
      final tables = await db.rawQuery(DatabaseSql.selectTableNames);
      return 'DatabaseService: tables=${tables.map((row) => row['name']).join(', ')}';
    });
  }

  // 数据库操作方法
  // ======================================================================== //
  static Future<void> upsertAnimeEpisodeRelation(AniEpiRlt relation, AniEpiRltType type)  => _withDb((db) => _AnimeEpisodeRepository(db).upsert(relation, type));
  static Future<void> upsertAssetRecord(DbAssetRecord asset)                              => _withDb((db) => _AssetRepository(db).upsert(asset));

  static Future<void> linkToAnime(AniEpiRltType type, int typeAnimeId, int animeId  )     => _withDb((db) => _AnimeEpisodeRepository(db).linkAnime(type,typeAnimeId,animeId,));
  static Future<void> linkToEpisode(AniEpiRltType type, int typeEpisodeId, int episodeId) => _withDb((db) => _AnimeEpisodeRepository(db).linkEpisode(type,typeEpisodeId,episodeId,),);
  static Future<void> linkVideoAssetToEpisode(Uint8List assetHash, int episodeId)         => _withDb((db) => _AssetRepository(db).linkToEpisode(assetHash, episodeId),);


  // getters
  // ======================================================================== //

  static Future<bool> hasAnime(AniEpiRltType type, int id) =>
      _withDb((db) => _AnimeEpisodeRepository(db).hasAnime(type, id));

  static Future<bool> hasEpisode(AniEpiRltType type, int id) =>
      _withDb((db) => _AnimeEpisodeRepository(db).hasEpisode(type, id));

  static Future<bool> hasDandanplayAnime(int id) =>
      hasAnime(AniEpiRltType.dandanplay, id);

  static Future<bool> hasDandanplayEpisode(int id) =>
      hasEpisode(AniEpiRltType.dandanplay, id);

  static Future<bool> hasBangumiAnime(int id) =>
      hasAnime(AniEpiRltType.bangumi, id);

  static Future<bool> hasBangumiEpisode(int id) =>
      hasEpisode(AniEpiRltType.bangumi, id);

  static Future<int?> getDandanplayEpisodeIdByAssetHash(Uint8List hash) =>
      _withDb(
        (db) => _AssetRepository(db).findDandanplayEpisodeId(hash),
      );

  static Future<int?> getBangumiEpisodeIdByDandanplayEpisodeId(int id) =>
      _withDb(
        (db) => _AnimeEpisodeRepository(db).findBangumiEpisodeId(id),
      );

  static Future<int?> getBangumiAnimeIdByDandanplayEpisodeId(int id) =>
      _withDb(
        (db) => _AnimeEpisodeRepository(db).findBangumiAnimeId(id),
      );

  static Future<void> setAssetLinkOptions(Uint8List hash, int value) =>
      _withDb(
        (db) => _AssetRepository(db).setLinkOptions(hash, value),
      );

  static Future<int?> getAssetLinkOptions(Uint8List hash) =>
      _withDb((db) => _AssetRepository(db).readLinkOptions(hash));

  static Future<void> setAssetDanmakuOffsets(
    Uint8List hash, {
    double? dandanplay,
    double? user,
  }) =>
      _withDb(
        (db) => _AssetRepository(db).setDanmakuOffsets(
          hash,
          dandanplay: dandanplay,
          user: user,
        ),
      );

  static Future<double?> getAssetDandanplayDanmakuOffset(Uint8List hash) =>
      _withDb(
        (db) => _AssetRepository(db).readDouble(
          hash,
          'danmaku_offset_dandanplay',
        ),
      );

  static Future<double?> getAssetUserDanmakuOffset(Uint8List hash) =>
      _withDb(
        (db) => _AssetRepository(db).readDouble(
          hash,
          'danmaku_offset_user',
        ),
      );

  static Future<void> printAnimeEpisodeTables() =>
      _withDb((db) => _DatabaseDebugPrinter(db).printTables());


  // 私有方法
  // ======================================================================== //

  static Future<T> _withDb<T>(Future<T> Function(Database database) operation) {
    final database = _database;
    if (database == null) throw StateError('DatabaseService 未初始化');
    return operation(database);
  }
}
