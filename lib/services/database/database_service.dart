
// lib/services/database/database_service.dart
// 数据库服务类, 提供数据库操作和迁移功能

import 'dart:async';
import 'package:nipaplay/models/database/anime_record.dart';
import 'package:nipaplay/models/database/episode_record.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/database/sql.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class DatabaseService {

  // 单例
  static DatabaseService? _instance;
  DatabaseService._init(String dbFilePath, Database db) : _path = dbFilePath, _db = db;

  final String? _path;
  final Database? _db;

  /// 初始化
  static Future<void> initialize(String dbFilePath) async {

    sqfliteFfiInit(); // 初始化 sqflite_ffi
    databaseFactory = databaseFactoryFfi; // 使用 sqflite_ffi 的数据库工厂

    // 打开数据库连接, 如果不存在则创建
    final db = await openDatabase(
      dbFilePath,
      version: 2,
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

  static Future<Set<DbAnimeRecord>?> getAnimeRecords(int limit) async {
    if (_instance == null) return null;
    final instance = _instance!;
    final db = instance._db;

    if (db == null) return null;

    // 解析 anime 表名的逻辑
    String? table;
    for (final candidate in const ['anime', DatabaseSql.mediaAnimeTable]) {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [candidate],
      );
      if (rows.isNotEmpty) {
        table = candidate;
        break;
      }
    }
    if (table == null) return null;
    final rows = await db.query(table, limit: limit);
    return rows.map((row) => DbAnimeRecord.fromMap(row)).toSet();
  }


  // ======================================================================== //
  // ============================= 数据库操作 =============================== //
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

  /// 向 anime 表插入或更新一条记录 (主键冲突时覆盖)
  static Future<void> upsertMediaAnime(DbAnimeRecord anime) async {
    if (_instance == null) throw StateError('DatabaseService is not initialized');
    final db = _instance!._db!;
    await db.insert(
      DatabaseSql.mediaAnimeTable,
      anime.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 向 episode 表插入或更新一条记录 (主键冲突时覆盖)
  static Future<void> upsertMediaEpisode(DbEpisodeRecord episode) async {
    if (_instance == null) throw StateError('DatabaseService is not initialized');
    final db = _instance!._db!;
    await db.insert(
      DatabaseSql.mediaEpisodeTable,
      episode.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  /// 按 animeId 读取该动画下的所有单集记录
  static Future<List<DbEpisodeRecord>> getEpisodeRecordsByAnimeId(
    int animeId,
  ) async {
    if (_instance == null) throw StateError('DatabaseService is not initialized');
    final db = _instance!._db!;
    final rows = await db.query(
      DatabaseSql.mediaEpisodeTable,
      where: '${DatabaseSql.meAnimeId} = ?',
      whereArgs: [animeId],
      orderBy: '${DatabaseSql.meId} ASC',
    );
    return rows.map(DbEpisodeRecord.fromMap).toList();
  }
}
