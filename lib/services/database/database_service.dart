
// lib/services/database/database_service.dart
// 数据库服务类, 提供数据库操作和迁移功能

import 'dart:async';
import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_anime_package.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';
import 'package:nipaplay/models/database/dandanplay_anime_package.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/database/sql.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class DatabaseService {

  // 单例
  static DatabaseService? _instance;
  DatabaseService._init(String dbFilePath, Database db) : _path = dbFilePath, _db = db;

  final String?   _path;
  final Database? _db;

  /// 初始化
  static Future<void> initialize(String dbFilePath) async {

    sqfliteFfiInit(); // 初始化 sqflite_ffi
    databaseFactory = databaseFactoryFfi; // 使用 sqflite_ffi 的数据库工厂

    Future<void> createBangumiAndRelationTables(DatabaseExecutor db) async {
      await db.execute(DatabaseSql.createBangumiAnimeTable);
      await db.execute(DatabaseSql.createBangumiEpisodeTable);
      await db.execute(DatabaseSql.createBangumiEpisodeAnimeIdIndex);
      await db.execute(DatabaseSql.createDandanplayBangumiAnimeRelationTable);
      await db.execute(DatabaseSql.createDandanplayBangumiEpisodeRelationTable);
    }

    // 打开数据库连接, 如果不存在则创建
    final db = await openDatabase(
      dbFilePath,
      version: 4,
      // 打开连接后先启用外键约束, 确保关联关系真实生效
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      // 新建数据库时按既定顺序创建主历史表和资源库表
      onCreate: (db, _) async {

        // 主历史表与索引
        await db.execute(DatabaseSql.createWatchHistoryTable);
        await db.execute(DatabaseSql.createWatchHistoryFilePathIndex);
        await db.execute(DatabaseSql.createWatchHistoryAnimeIdIndex);
        await db.execute(DatabaseSql.createWatchHistoryLastWatchTimeIndex);

        // 媒体库相关表与索引
        await db.execute(DatabaseSql.createMediaAnimeTable);
        await db.execute(DatabaseSql.createMediaEpisodeTable);
        await db.execute(DatabaseSql.createMediaFileTable);
        await db.execute(DatabaseSql.createMediaSourceTable);
        await db.execute(DatabaseSql.createMediaAddressTable);
        await db.execute(DatabaseSql.createMediaFileEpisodeIdIndex);
        await db.execute(DatabaseSql.createMediaFileAnimeIdIndex);
        await db.execute(DatabaseSql.createMediaAddressFileHashIndex);
        await createBangumiAndRelationTables(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 4) {
          await createBangumiAndRelationTables(db);
        }
      },
    );

    // 检查数据库所有表:
    // 如果不存在表, 则直接报错退出
    // 如果存在表, 则对比 sqlite_master 里的建表语句与预期 SQL, 不一致则报错退出
    for (final entry in DatabaseSql.expectedCreateTableSql.entries) {
      final tableName = entry.key;
      final expectedCreateSql = entry.value.trim().replaceAll(' IF NOT EXISTS ', ' ');

      // 1) 读取 sqlite_master 中数据库当前实际的建表语句
      final rows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [tableName],
      );
      final actualCreateSql = (rows.isEmpty ? null : (rows.first['sql'] as String?)?.trim());

      // 2) 表不存在或建表语句为空, 视为不符合预期
      final notStandard = actualCreateSql == null || actualCreateSql.trim().isEmpty;

      // 3) 表存在时做标准化后字符串比对
      final mismatched = !notStandard && (actualCreateSql) != (expectedCreateSql);

      if (notStandard) {
        throw StateError(
          'Database schema error: table "$tableName" create sql mismatch.\n'
          'Expected: $expectedCreateSql\n'
          'Actual: ${actualCreateSql ?? '<null>'}',
        );
      }
      if (mismatched) {
        throw StateError(
          'Database schema error: table "$tableName" create sql mismatch.\n'
          'Expected: $expectedCreateSql\n'
          'Actual: $actualCreateSql',
        );
      }
    }

    _instance = DatabaseService._init(dbFilePath, db);
  }

  String getInfo() {
    final info = 'DatabaseService: path=${_instance?._path}, db=${_instance?._db}';
    return info;
  }

  static Future<String?> getTableNames() async {
    if (_instance == null) return null;
    final db = _instance!._db;
    if (db == null) return null;
    final tableNames = await db.rawQuery('SELECT name FROM sqlite_master WHERE type="table"');
    return 'DatabaseService: tables=${tableNames.map((e) => e['name']).join(', ')}';
  }

  static Future<Set<DbDandanplayAnimeRecord>?> getAnimeRecords(int limit) async {
    if (_instance == null) return null;
    final db = _instance!._db;
    if (db == null) return null;
    final rows = await db.query(DatabaseSql.mediaAnimeTable, limit: limit);
    return rows.map(DbDandanplayAnimeRecord.fromMap).toSet();
  }


  // ======================================================================== //
  // =============================== 插入数据 =============================== //
  // ======================================================================== //

  static Future<void> upsertMediaFile(DbFileRecord file) async {

    if (_instance == null) throw StateError('DatabaseService is not initialized');
    final db = _instance!._db!;

    await db.insert(
      DatabaseSql.mediaFileTable,
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> upsertBangumiAnimePackage(DbBangumiAnimePackage animeSet) async {

    Future<void> upsertBangumiAnime(DbBangumiAnimeRecord anime) async {
      if (_instance == null) {
        throw StateError('DatabaseService is not initialized');
      }
      final db = _instance!._db!;
      final values = anime.toMap();
      final updated = await db.update(
        DatabaseSql.bangumiAnimeTable,
        values,
        where: '${DatabaseSql.baId} = ?',
        whereArgs: <Object>[anime.bangumiAnimeId],
      );
      if (updated == 0) {
        await db.insert(DatabaseSql.bangumiAnimeTable, values);
      }
    }

    Future<void> upsertBangumiEpisode(
      DbBangumiEpisodeRecord episode,
    ) async {
      if (_instance == null) {
        throw StateError('DatabaseService is not initialized');
      }
      final db = _instance!._db!;
      final values = episode.toMap();
      final updated = await db.update(
        DatabaseSql.bangumiEpisodeTable,
        values,
        where: '${DatabaseSql.beId} = ?',
        whereArgs: <Object>[episode.bangumiEpisodeId],
      );
      if (updated == 0) {
        await db.insert(DatabaseSql.bangumiEpisodeTable, values);
      }
    }

    await upsertBangumiAnime(animeSet.anime);
    for (final episode in animeSet.episodes) { await upsertBangumiEpisode(episode); }
  }

  static Future<void> upsertDanDanPlayAnimePackage(DbDandanplayAnimePackage animeSet) async {

    Future<void> upsertDanDanPlayAnime(DbDandanplayAnimeRecord anime) async {
      final animeId = anime.dandanplayAnimeId;
      if (animeId == null) {
        throw ArgumentError(
          '无法写入缺少弹弹play 动画 ID 的记录',
        );
      }
      if (_instance == null) {
        throw StateError('DatabaseService is not initialized');
      }
      final db = _instance!._db!;
      final values = anime.toMap();
      final updated = await db.update(
        DatabaseSql.mediaAnimeTable,
        values,
        where: '${DatabaseSql.maDandanplayAnimeId} = ?',
        whereArgs: <Object>[animeId],
      );
      if (updated == 0) {
        await db.insert(DatabaseSql.mediaAnimeTable, values);
      }
    }

    Future<void> upsertDanDanPlayEpisode(
      DbDandanplayEpisodeRecord episode,
    ) async {
      final episodeId = episode.dandanplayEpisodeId;
      final animeId = episode.animeId;
      if (episodeId == null || animeId == null) {
        throw ArgumentError(
          '无法写入缺少弹弹play 动画 ID 或剧集 ID 的记录',
        );
      }
      if (_instance == null) {
        throw StateError('DatabaseService is not initialized');
      }
      final db = _instance!._db!;
      final values = episode.toMap();
      final updated = await db.update(
        DatabaseSql.mediaEpisodeTable,
        values,
        where: '${DatabaseSql.meDandanplayEpisodeId} = ?',
        whereArgs: <Object>[episodeId],
      );
      if (updated == 0) {
        await db.insert(DatabaseSql.mediaEpisodeTable, values);
      }
    }

    await upsertDanDanPlayAnime(animeSet.anime);
    for (final episode in animeSet.episodes) { await upsertDanDanPlayEpisode(episode); }
  }


  // ======================================================================== //
  // =============================== 查询数据 =============================== //
  // ======================================================================== //

  static Future<DbBangumiAnimeRecord?> getBangumiAnimeRecordById(int bgmAniId) async {
    if (_instance == null) {
      throw StateError('DatabaseService is not initialized');
    }
    final rows = await _instance!._db!.query(
      DatabaseSql.bangumiAnimeTable,
      where: '${DatabaseSql.baId} = ?',
      whereArgs: <Object>[bgmAniId],
      limit: 1,
    );
    return rows.isEmpty ? null : DbBangumiAnimeRecord.fromMap(rows.first);
  }

  static Future<Set<DbBangumiEpisodeRecord>?> getBangumiEpisodeRecordsById(int bgmAniId) async {
    if (_instance == null) {
      throw StateError('DatabaseService is not initialized');
    }
    final rows = await _instance!._db!.query(
      DatabaseSql.bangumiEpisodeTable,
      where: '${DatabaseSql.beAnimeId} = ?',
      whereArgs: <Object>[bgmAniId],
      orderBy: '${DatabaseSql.beSortOrder} ASC, ${DatabaseSql.beId} ASC',
    );
    return rows.map(DbBangumiEpisodeRecord.fromMap).toSet();
  }

  static Future<Set<DbDandanplayAnimeRecord>?> getDandanplayAnimeRecordById(int ddpAniId) async {
    if (_instance == null) {
      throw StateError('DatabaseService is not initialized');
    }
    final rows = await _instance!._db!.query(
      DatabaseSql.mediaAnimeTable,
      where: '${DatabaseSql.maDandanplayAnimeId} = ?',
      whereArgs: <Object>[ddpAniId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.map(DbDandanplayAnimeRecord.fromMap).toSet();
  }

  /// 按 animeId 读取该动画下的所有单集记录
  static Future<Set<DbDandanplayEpisodeRecord>?> getDandanplayEpisodeRecordsById(int ddpAniId) async {
    if (_instance == null) throw StateError('DatabaseService is not initialized');
    final db = _instance!._db!;
    final rows = await db.query(
      DatabaseSql.mediaEpisodeTable,
      where: '${DatabaseSql.meDandanplayAnimeId} = ?',
      whereArgs: [ddpAniId],
      orderBy: '${DatabaseSql.meDandanplayEpisodeId} ASC',
    );
    return rows.map(DbDandanplayEpisodeRecord.fromMap).toSet();
  }


  static Future<DbFileRecord?> getMediaFileByHash(String fileHash) async {
    if (_instance == null) throw StateError('DatabaseService is not initialized');
    final db = _instance!._db!;
    final rows = await db.query(
      DatabaseSql.mediaFileTable,
      where: DatabaseSql.whereFileHashEq,
      whereArgs: [fileHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DbFileRecord.fromMap(rows.first);
  }
}
