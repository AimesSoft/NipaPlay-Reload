import 'package:nipaplay/models/database/bangumi_anime_package.dart';
import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';
import 'package:nipaplay/models/database/dandanplay_anime_package.dart';
import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/dandanplay_danmaku_record.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/database/sql.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class FileDanmaku {

  final String danmakuJson;
  final double danmakuOffsetDandanplay;
  final double danmakuOffsetUser;
  final DateTime lastUpdated;

  FileDanmaku({
    required this.danmakuJson,
    required this.danmakuOffsetDandanplay,
    required this.danmakuOffsetUser,
    required this.lastUpdated,
  });
}

class FileDanmakuResult {

  final bool fileRecordExists;    // 数据库 file 表中是否存在 fileHash 对应的记录
  final bool episodeRecordExists; // 数据库 dandanplay_episode 表中是否存在 ddpEpiId 对应的记录

  final FileDanmaku? fileDanmaku; // file_danmaku 表中是否存在 fileHash & ddpEpiId 对应的记录, 如果存在则返回弹幕信息, 否则返回 null

  FileDanmakuResult({
    this.fileDanmaku,
    required this.fileRecordExists,
    required this.episodeRecordExists,
  });
}


class DatabaseService {
  DatabaseService._(this._path, this._db);

  static DatabaseService? _instance;
  final String _path;
  final Database _db;

  static Future<void> initialize(String dbFilePath) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      dbFilePath,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final sql in DatabaseSql.createTables) {
          await db.execute(sql);
        }
        for (final sql in DatabaseSql.createIndexes) {
          await db.execute(sql);
        }
      },
    );
    _instance = DatabaseService._(dbFilePath, db);
  }

  static Database get _database {
    final instance = _instance;
    if (instance == null) throw StateError('DatabaseService is not initialized');
    return instance._db;
  }

  String getInfo() => 'DatabaseService: path=$_path, db=$_db';

  static Future<String> getTableNames() async {
    final tables = await _database.rawQuery(
      'SELECT name FROM sqlite_master WHERE type = "table"',
    );
    return 'DatabaseService: tables=${tables.map((row) => row['name']).join(', ')}';
  }

  static Future<Set<DbDandanplayAnimeRecord>> getAnimeRecords(int limit) async {
    final rows = await _database.query(
      DatabaseSql.dandanplayAnimeTable,
      limit: limit,
    );
    return rows.map(DbDandanplayAnimeRecord.fromMap).toSet();
  }


  // ======================================================================== //
  // ============================== 插入更新 ================================ //
  // ======================================================================== //

  static Future<void> upsertDanDanPlayAnimePackage(DbDandanplayAnimePackage package) async {

    final dandanplayAnimeId = package.anime.dandanplayAnimeId;
    final animeId = await _animeIdForDandanplay(package.anime);
    final animeValues = package.anime.toMap()..[DatabaseSql.animeId] = animeId;

    await _upsert(
      DatabaseSql.dandanplayAnimeTable,
      DatabaseSql.dandanplayAnimeId,
      dandanplayAnimeId,
      animeValues,
    );

    for (final episode in package.episodes) {
      final episodeId = await _episodeIdFor(
        DatabaseSql.dandanplayEpisodeTable,
        DatabaseSql.dandanplayEpisodeId,
        episode.dandanplayEpisodeId,
        animeId,
      );
      final values = episode.toMap()
        ..[DatabaseSql.episodeId] = episodeId
        ..[DatabaseSql.dandanplayAnimeId] = dandanplayAnimeId;
      await _upsert(
        DatabaseSql.dandanplayEpisodeTable,
        DatabaseSql.dandanplayEpisodeId,
        episode.dandanplayEpisodeId,
        values,
      );
    }
  }

  static Future<void> upsertBangumiAnimePackage(DbBangumiAnimePackage pkg) async {

    final animeId = await _animeIdForBangumi(pkg.anime);
    final animeValues = pkg.anime.toMap()..[DatabaseSql.animeId] = animeId;
    await _upsert(
      DatabaseSql.bangumiAnimeTable,
      DatabaseSql.bangumiAnimeId,
      pkg.anime.bangumiAnimeId,
      animeValues,
    );
    for (final episode in pkg.episodes) {
      final episodeId = await _episodeIdFor(
        DatabaseSql.bangumiEpisodeTable,
        DatabaseSql.bangumiEpisodeId,
        episode.bangumiEpisodeId,
        animeId,
      );
      final values = episode.toMap()..[DatabaseSql.episodeId] = episodeId;
      await _upsert(
        DatabaseSql.bangumiEpisodeTable,
        DatabaseSql.bangumiEpisodeId,
        episode.bangumiEpisodeId,
        values,
      );
    }
  }

  // 弹幕表
  static Future<void> upsertDandanplayDanmaku(DbDandanplayDanmakuRecord record) async {
    final values = record.toMap()
      ..['updated_at'] = DateTime.now().toIso8601String();
    final updated = await _database.update(
      DatabaseSql.dandanplayDanmakuTable,
      values,
      where: '${DatabaseSql.dandanplayEpisodeId} = ?',
      whereArgs: <Object>[record.dandanplayEpisodeId],
    );
    if (updated == 0) {
      await _database.insert(
        DatabaseSql.dandanplayDanmakuTable,
        values,
      );
    }
  }

  /// 文件表
  static Future<void> upsertMediaFile(DbFileRecord file) async {
    final existing = await _database.query(
      DatabaseSql.fileTable,
      columns: <String>[DatabaseSql.episodeId],
      where: '${DatabaseSql.fileHash} = ?',
      whereArgs: <Object>[file.fileHash],
      limit: 1,
    );
    final episodeId = existing.isNotEmpty &&
            existing.first[DatabaseSql.episodeId] is num
        ? (existing.first[DatabaseSql.episodeId] as num).toInt()
        : await _createEpisode(await _createAnime());
    final values = file.toMap()..[DatabaseSql.episodeId] = episodeId;
    await _upsert(
      DatabaseSql.fileTable,
      DatabaseSql.fileHash,
      file.fileHash,
      values,
    );
  }

  /// 专门插入更新 file_danmaku
  /// 1. 检查 file 表和 dandanplay_episode 表是否存在匹配的记录
  /// 2. 如果任意一个不存在, 直接返回
  /// 3. 插入更新 file_danmaku 表, 记录 fileHash 对应的 dandanplay_episode_id 和弹幕偏移量
  static Future<void> upsertDandanplayFileDanmaku(String fileHash, int ddpEpiId, double danmakuOffset) async {
    final fileExists = await _hasRow(
      DatabaseSql.fileTable,
      DatabaseSql.fileHash,
      fileHash,
    );
    final episodeExists = await _hasRow(
      DatabaseSql.dandanplayEpisodeTable,
      DatabaseSql.dandanplayEpisodeId,
      ddpEpiId,
    );
    if (!fileExists || !episodeExists) return;

    final danmakuValues = <String, Object?>{
      DatabaseSql.fileHash: fileHash,
      DatabaseSql.dandanplayEpisodeId: ddpEpiId,
      DatabaseSql.danmakuOffsetDandanplay: danmakuOffset,
    };
    final updated = await _database.update(
      DatabaseSql.fileDanmakuTable,
      danmakuValues,
      where: '${DatabaseSql.fileHash} = ?',
      whereArgs: <Object>[fileHash],
    );
    if (updated == 0) {
      await _database.insert(
        DatabaseSql.fileDanmakuTable,
        danmakuValues..[DatabaseSql.danmakuOffsetUser] = null,
      );
    }
  }


  // ======================================================================== //
  // ======================================================================== //
  // ======================================================================== //

  /// 关联 Dandanplay 与 Bangumi 的 Anime 记录, 使两者共享同一个通用 anime_id
  static Future<void> linkAnimeRecordDandanplayBangumi(int ddpAniId, int bgmAniId) async {

    final ddpAnimeId = await _commonAnimeIdOfDandanplayAnime(ddpAniId);
    final bgmAnimeId = await _commonAnimeIdOfBangumiAnime(bgmAniId);
    if (ddpAnimeId == null || bgmAnimeId == null) {
      throw StateError('关联 Anime 前必须先写入 Dandanplay 和 Bangumi 动画记录');
    }

    final updatedAt = DateTime.now().toIso8601String();
    await _database.update(
      DatabaseSql.dandanplayAnimeTable,
      <String, Object?>{
        DatabaseSql.bangumiAnimeId: bgmAniId,
        'updated_at': updatedAt,
      },
      where: '${DatabaseSql.dandanplayAnimeId} = ?',
      whereArgs: <Object>[ddpAniId],
    );
    if (ddpAnimeId == bgmAnimeId) return;

    await _database.update(
      DatabaseSql.bangumiAnimeTable,
      <String, Object?>{
        DatabaseSql.animeId: ddpAnimeId,
        'updated_at': updatedAt,
      },
      where: '${DatabaseSql.bangumiAnimeId} = ?',
      whereArgs: <Object>[bgmAniId],
    );
    await _deleteAnimeIfUnreferenced(bgmAnimeId);
  }

  /// 关联 Dandanplay 与 Bangumi 的 Episode 记录, 使两者共享同一个通用 episode_id
  static Future<void> linkEpisodeRecordDandanplayBangumi(int ddpEpiId, int bgmEpiId) async {

    final ddpEpisodeId = await _commonEpisodeIdOfDandanplayEpisode(ddpEpiId);
    final bgmEpisodeId = await _commonEpisodeIdOfBangumiEpisode(bgmEpiId);
    if (ddpEpisodeId == null || bgmEpisodeId == null) {
      throw StateError('关联 Episode 前必须先写入 Dandanplay 和 Bangumi 剧集记录');
    }
    if (ddpEpisodeId == bgmEpisodeId) return;

    await _database.update(
      DatabaseSql.bangumiEpisodeTable,
      <String, Object?>{
        DatabaseSql.episodeId: ddpEpisodeId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: '${DatabaseSql.bangumiEpisodeId} = ?',
      whereArgs: <Object>[bgmEpiId],
    );
    await _deleteEpisodeIfUnreferenced(bgmEpisodeId);
  }

  /// 关联 Dandanplay 的 Episode 记录与文件记录, 使文件共享该剧集的通用 episode_id
  static Future<void> linkEpisodeDandanplayFile(int ddpEpiId, String fileHash) async {

    final ddpEpisodeId = await _commonEpisodeIdOfDandanplayEpisode(ddpEpiId);
    final fileEpisodeId = await _commonEpisodeIdOfFile(fileHash);
    if (ddpEpisodeId == null || fileEpisodeId == null) {
      throw StateError('关联前必须先写入 Dandanplay 剧集记录和文件记录');
    }
    if (ddpEpisodeId == fileEpisodeId) return;

    await _database.update(
      DatabaseSql.fileTable,
      <String, Object?>{
        DatabaseSql.episodeId: ddpEpisodeId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: '${DatabaseSql.fileHash} = ?',
      whereArgs: <Object>[fileHash],
    );
    await _deleteEpisodeIfUnreferenced(fileEpisodeId);
  }


  // ======================================================================== //
  // ============================ Get Methods =============================== //
  // ======================================================================== //

  static Future<DbDandanplayAnimeRecord?> getDandanplayAnimeRecordById(
    int id,
  ) async {
    final rows = await _database.query(
      DatabaseSql.dandanplayAnimeTable,
      where: '${DatabaseSql.dandanplayAnimeId} = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : DbDandanplayAnimeRecord.fromMap(rows.first);
  }

  static Future<DbBangumiAnimeRecord?> getBangumiAnimeRecordById(int id) async {
    final rows = await _database.query(
      DatabaseSql.bangumiAnimeTable,
      where: '${DatabaseSql.bangumiAnimeId} = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : DbBangumiAnimeRecord.fromMap(rows.first);
  }

  static Future<Set<DbDandanplayEpisodeRecord>> getDandanplayEpisodeRecordsById(
    int animeId,
  ) async {
    final rows = await _database.query(
      DatabaseSql.dandanplayEpisodeTable,
      where: '${DatabaseSql.dandanplayAnimeId} = ?',
      whereArgs: <Object>[animeId],
    );
    return rows.map(DbDandanplayEpisodeRecord.fromMap).toSet();
  }

  static Future<Set<DbBangumiEpisodeRecord>> getBangumiEpisodeRecordsById(
    int animeId,
  ) async {
    final rows = await _database.query(
      DatabaseSql.bangumiEpisodeTable,
      where: '${DatabaseSql.bangumiAnimeId} = ?',
      whereArgs: <Object>[animeId],
    );
    return rows.map(DbBangumiEpisodeRecord.fromMap).toSet();
  }

  static Future<DbFileRecord?> getMediaFileByHash(String hash) async {
    final rows = await _database.query(
      DatabaseSql.fileTable,
      where: '${DatabaseSql.fileHash} = ?',
      whereArgs: <Object>[hash],
      limit: 1,
    );
    return rows.isEmpty ? null : DbFileRecord.fromMap(rows.first);
  }

  static Future<DbDandanplayEpisodeRecord?> getDandanplayEpisodeRecordById(int id) async {
    final rows = await _database.query(
      DatabaseSql.dandanplayEpisodeTable,
      where: '${DatabaseSql.dandanplayEpisodeId} = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : DbDandanplayEpisodeRecord.fromMap(rows.first);
  }

  static Future<DbDandanplayEpisodeRecord?> getDandanplayEpisodeRecordByFileHash(String fileHash) async {
    final rows = await _database.rawQuery(
      'SELECT e.* FROM ${DatabaseSql.dandanplayEpisodeTable} e '
      'JOIN ${DatabaseSql.fileTable} f ON e.${DatabaseSql.episodeId} = f.${DatabaseSql.episodeId} '
      'WHERE f.${DatabaseSql.fileHash} = ?',
      <Object>[fileHash],
    );
    return rows.isEmpty ? null : DbDandanplayEpisodeRecord.fromMap(rows.first);
  }

  static Future<int?> getDandanplayEpisodeIdByFileHash(String fileHash) async {

    final rows = await _database.rawQuery(
      'SELECT e.${DatabaseSql.dandanplayEpisodeId} FROM ${DatabaseSql.dandanplayEpisodeTable} e '
      'JOIN ${DatabaseSql.fileTable} f ON e.${DatabaseSql.episodeId} = f.${DatabaseSql.episodeId} '
      'WHERE f.${DatabaseSql.fileHash} = ?',
      <Object>[fileHash],
    );
    if (rows.isEmpty) return null;
    final id = rows.first[DatabaseSql.dandanplayEpisodeId];
    return id is num ? id.toInt() : null;
  }

  /// 1. 根据 fileHash & ddpEpiId 查询 file_danmaku 表:
  ///    - 如果存在匹配的记录, FileDanmakuResult.fileDanmaku 返回弹幕信息, fileRecordExists = episodeRecordExists = true
  ///    - 如果不存在匹配的记录, FileDanmakuResult.fileDanmaku 返回 null
  /// 2. 继续查询 file 表和 dandanplay_episode 表, 检查是否存在匹配的记录, 并设置 fileRecordExists 和 episodeRecordExists
  /// 3. 返回 FileDanmakuResult 对象
  static Future<FileDanmakuResult> getDandanplayFileDanmakuByFileHashAndEpisodeId(String fileHash, int ddpEpiId) async {

    final fileDanmakuRows = await _database.query(
      DatabaseSql.fileDanmakuTable,
      where:
          '${DatabaseSql.fileHash} = ? AND '
          '${DatabaseSql.dandanplayEpisodeId} = ?',
      whereArgs: <Object>[fileHash, ddpEpiId],
      limit: 1,
    );
    if (fileDanmakuRows.isNotEmpty) {
      final danmakuRows = await _database.query(
        DatabaseSql.dandanplayDanmakuTable,
        columns: <String>['danmaku_json', 'updated_at'],
        where: '${DatabaseSql.dandanplayEpisodeId} = ?',
        whereArgs: <Object>[ddpEpiId],
        limit: 1,
      );
      final danmakuJson =
          danmakuRows.isEmpty ? null : danmakuRows.first['danmaku_json'];
      final updatedAt =
          danmakuRows.isEmpty ? null : danmakuRows.first['updated_at'];
      if (danmakuJson is String && updatedAt is String) {
        final row = fileDanmakuRows.first;
        final dandanplayOffset = row[DatabaseSql.danmakuOffsetDandanplay];
        final userOffset = row[DatabaseSql.danmakuOffsetUser];
        final offset = dandanplayOffset is num
            ? dandanplayOffset.toDouble()
            : 0.0;
        return FileDanmakuResult(
          fileRecordExists: true,
          episodeRecordExists: true,
          fileDanmaku: FileDanmaku(
            danmakuJson: danmakuJson,
            danmakuOffsetDandanplay: offset,
            danmakuOffsetUser:
                userOffset is num ? userOffset.toDouble() : offset,
            lastUpdated: DateTime.parse(updatedAt),
          ),
        );
      }
      return FileDanmakuResult(
        fileRecordExists: true,
        episodeRecordExists: true,
      );
    }

    final fileRows = await _database.query(
      DatabaseSql.fileTable,
      columns: <String>[DatabaseSql.fileHash],
      where: '${DatabaseSql.fileHash} = ?',
      whereArgs: <Object>[fileHash],
      limit: 1,
    );
    final episodeRows = await _database.query(
      DatabaseSql.dandanplayEpisodeTable,
      columns: <String>[DatabaseSql.dandanplayEpisodeId],
      where: '${DatabaseSql.dandanplayEpisodeId} = ?',
      whereArgs: <Object>[ddpEpiId],
      limit: 1,
    );
    return FileDanmakuResult(
      fileRecordExists: fileRows.isNotEmpty,
      episodeRecordExists: episodeRows.isNotEmpty,
    );
  }



  // ======================================================================== //
  // ========================= Private Methods ============================== //
  // ======================================================================== //

  static Future<int> _createAnime() async =>
      _database.rawInsert('INSERT INTO ${DatabaseSql.animeTable} DEFAULT VALUES');

  static Future<int> _createEpisode(int animeId) async =>
      _database.insert(
        DatabaseSql.episodeTable,
        <String, Object?>{DatabaseSql.animeId: animeId},
      );

  static Future<int> _animeIdForDandanplay(
    DbDandanplayAnimeRecord anime,
  ) async {
    final existing = await _database.query(
      DatabaseSql.dandanplayAnimeTable,
      columns: <String>[DatabaseSql.animeId],
      where: '${DatabaseSql.dandanplayAnimeId} = ?',
      whereArgs: <Object?>[anime.dandanplayAnimeId],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first[DatabaseSql.animeId] is num) {
      return (existing.first[DatabaseSql.animeId] as num).toInt();
    }
    if (anime.bangumiAnimeId != null) {
      final bangumi = await _database.query(
        DatabaseSql.bangumiAnimeTable,
        columns: <String>[DatabaseSql.animeId],
        where: '${DatabaseSql.bangumiAnimeId} = ?',
        whereArgs: <Object?>[anime.bangumiAnimeId],
        limit: 1,
      );
      if (bangumi.isNotEmpty && bangumi.first[DatabaseSql.animeId] is num) {
        return (bangumi.first[DatabaseSql.animeId] as num).toInt();
      }
    }
    return _createAnime();
  }

  static Future<int> _animeIdForBangumi(DbBangumiAnimeRecord anime) async {

    // 查找现有的记录
    final existing = await _database.query(
      DatabaseSql.bangumiAnimeTable,
      columns: <String>[DatabaseSql.animeId],
      where: '${DatabaseSql.bangumiAnimeId} = ?',
      whereArgs: <Object>[anime.bangumiAnimeId],
      limit: 1,
    );

    // 如果存在则返回其 anime_id, 否则创建一个新的记录并返回其 anime_id
    if (existing.isNotEmpty && existing.first[DatabaseSql.animeId] is num) {
      return (existing.first[DatabaseSql.animeId] as num).toInt();
    }
    final dandanplay = await _database.query(
      DatabaseSql.dandanplayAnimeTable,
      columns: <String>[DatabaseSql.animeId],
      where: '${DatabaseSql.bangumiAnimeId} = ?',
      whereArgs: <Object>[anime.bangumiAnimeId],
      limit: 1,
    );
    if (dandanplay.isNotEmpty && dandanplay.first[DatabaseSql.animeId] is num) {
      return (dandanplay.first[DatabaseSql.animeId] as num).toInt();
    }

    return _createAnime();
  }

  static Future<void> _upsert(
    String table,
    String idColumn,
    Object id,
    Map<String, Object?> values,
  ) async {
    values['updated_at'] = DateTime.now().toIso8601String();
    final updated = await _database.update(
      table,
      values,
      where: '$idColumn = ?',
      whereArgs: <Object>[id],
    );
    if (updated == 0) await _database.insert(table, values);
  }

  static Future<int> _episodeIdFor(
    String table,
    String sourceEpisodeIdColumn,
    int sourceEpisodeId,
    int animeId,
  ) async {
    final rows = await _database.query(
      table,
      columns: <String>[DatabaseSql.episodeId],
      where: '$sourceEpisodeIdColumn = ?',
      whereArgs: <Object>[sourceEpisodeId],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first[DatabaseSql.episodeId] is num) {
      return (rows.first[DatabaseSql.episodeId] as num).toInt();
    }
    return _createEpisode(animeId);
  }

  static Future<int?> _commonAnimeIdOfDandanplayAnime(int ddpAniId) =>
      _readIntColumn(
        DatabaseSql.dandanplayAnimeTable,
        DatabaseSql.animeId,
        DatabaseSql.dandanplayAnimeId,
        ddpAniId,
      );

  static Future<int?> _commonAnimeIdOfBangumiAnime(int bgmAniId) =>
      _readIntColumn(
        DatabaseSql.bangumiAnimeTable,
        DatabaseSql.animeId,
        DatabaseSql.bangumiAnimeId,
        bgmAniId,
      );

  static Future<int?> _commonEpisodeIdOfDandanplayEpisode(int ddpEpiId) =>
      _readIntColumn(
        DatabaseSql.dandanplayEpisodeTable,
        DatabaseSql.episodeId,
        DatabaseSql.dandanplayEpisodeId,
        ddpEpiId,
      );

  static Future<int?> _commonEpisodeIdOfBangumiEpisode(int bgmEpiId) =>
      _readIntColumn(
        DatabaseSql.bangumiEpisodeTable,
        DatabaseSql.episodeId,
        DatabaseSql.bangumiEpisodeId,
        bgmEpiId,
      );

  static Future<int?> _commonEpisodeIdOfFile(String fileHash) =>
      _readIntColumn(
        DatabaseSql.fileTable,
        DatabaseSql.episodeId,
        DatabaseSql.fileHash,
        fileHash,
      );

  static Future<int?> _readIntColumn(
    String table,
    String column,
    String keyColumn,
    Object keyValue,
  ) async {
    final rows = await _database.query(
      table,
      columns: <String>[column],
      where: '$keyColumn = ?',
      whereArgs: <Object>[keyValue],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first[column];
    return value is num ? value.toInt() : null;
  }

  static Future<void> _deleteAnimeIfUnreferenced(int animeId) async {
    final referenced = await _hasRow(
      DatabaseSql.dandanplayAnimeTable,
      DatabaseSql.animeId,
      animeId,
    ) ||
        await _hasRow(
          DatabaseSql.bangumiAnimeTable,
          DatabaseSql.animeId,
          animeId,
        ) ||
        await _hasRow(
          DatabaseSql.episodeTable,
          DatabaseSql.animeId,
          animeId,
        );
    if (referenced) return;
    await _database.delete(
      DatabaseSql.animeTable,
      where: '${DatabaseSql.animeId} = ?',
      whereArgs: <Object>[animeId],
    );
  }

  static Future<void> _deleteEpisodeIfUnreferenced(int episodeId) async {
    final referenced = await _hasRow(
      DatabaseSql.dandanplayEpisodeTable,
      DatabaseSql.episodeId,
      episodeId,
    ) ||
        await _hasRow(
          DatabaseSql.bangumiEpisodeTable,
          DatabaseSql.episodeId,
          episodeId,
        ) ||
        await _hasRow(
          DatabaseSql.fileTable,
          DatabaseSql.episodeId,
          episodeId,
        );
    if (referenced) return;
    await _database.delete(
      DatabaseSql.episodeTable,
      where: '${DatabaseSql.episodeId} = ?',
      whereArgs: <Object>[episodeId],
    );
  }

  static Future<bool> _hasRow(
    String table,
    String column,
    Object value,
  ) async {
    final rows = await _database.query(
      table,
      columns: <String>[column],
      where: '$column = ?',
      whereArgs: <Object>[value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
