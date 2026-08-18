import 'package:nipaplay/models/database/bangumi_anime_package.dart';
import 'package:nipaplay/models/database/bangumi_anime_record.dart';
import 'package:nipaplay/models/database/bangumi_episode_record.dart';
import 'package:nipaplay/models/database/dandanplay_anime_package.dart';
import 'package:nipaplay/models/database/dandanplay_anime_record.dart';
import 'package:nipaplay/models/database/dandanplay_episode_record.dart';
import 'package:nipaplay/models/database/file_record.dart';
import 'package:nipaplay/services/database/sql.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  static Future<int> _createAnime() async =>
      _database.rawInsert('INSERT INTO ${DatabaseSql.animeTable} DEFAULT VALUES');

  static Future<int> _createEpisode() async =>
      _database.rawInsert('INSERT INTO ${DatabaseSql.episodeTable} DEFAULT VALUES');

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
    return _createEpisode();
  }

  static Future<void> upsertDanDanPlayAnimePackage(
    DbDandanplayAnimePackage package,
  ) async {
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
        : await _createEpisode();
    final values = file.toMap()..[DatabaseSql.episodeId] = episodeId;
    await _upsert(
      DatabaseSql.fileTable,
      DatabaseSql.fileHash,
      file.fileHash,
      values,
    );
  }

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
}
