import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 旧版本（代码里的数据库版本号还是 1）打开过已经升级过的库时，sqflite
/// 会把 user_version 改小却不动表结构，于是留下「版本号是 1、但列已经
/// 存在」的库。这里手工还原这种状态。
const String _v1SchemaWithMediaKey = '''
CREATE TABLE watch_history(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT UNIQUE NOT NULL,
  media_key TEXT,
  anime_name TEXT NOT NULL,
  episode_title TEXT,
  episode_id INTEGER,
  anime_id INTEGER,
  watch_progress REAL NOT NULL,
  last_position INTEGER NOT NULL,
  duration INTEGER NOT NULL,
  last_watch_time TEXT NOT NULL,
  thumbnail_path TEXT,
  is_from_scan INTEGER NOT NULL
)
''';

/// 标准的 v1 建表语句：没有 media_key，v2 迁移需要补上这一列。
const String _v1SchemaWithoutMediaKey = '''
CREATE TABLE watch_history(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT UNIQUE NOT NULL,
  anime_name TEXT NOT NULL,
  episode_title TEXT,
  episode_id INTEGER,
  anime_id INTEGER,
  watch_progress REAL NOT NULL,
  last_position INTEGER NOT NULL,
  duration INTEGER NOT NULL,
  last_watch_time TEXT NOT NULL,
  thumbnail_path TEXT,
  is_from_scan INTEGER NOT NULL
)
''';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nipaplay_history_migrate');
    dbPath = '${tempDir.path}/watch_history.db';
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 造一个 user_version = 1 的历史库，并塞一条记录。
  Future<void> createV1Database({
    required String schema,
    required bool hasMediaKey,
    String? path,
  }) async {
    final db = await openDatabase(
      path ?? dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(schema);
        await db.execute(
          'CREATE INDEX idx_file_path ON watch_history(file_path)',
        );
      },
    );
    await db.insert('watch_history', {
      'file_path': '/tmp/anime/EP01.mkv',
      if (hasMediaKey) 'media_key': 'episode:1',
      'anime_name': '测试番剧',
      'watch_progress': 0.5,
      'last_position': 120,
      'duration': 1440,
      'last_watch_time': '2026-09-10T00:00:00.000',
      'is_from_scan': 0,
    });
    await db.close();
  }

  /// 用生产同款迁移逻辑从 v1 升到 v2。
  Future<Database> upgradeToV2({String? path}) {
    return openDatabase(
      path ?? dbPath,
      version: 2,
      onUpgrade: WatchHistoryDatabase.applyMigrations,
    );
  }

  Future<bool> hasColumn(Database db, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info("watch_history")');
    return rows.any((row) => row['name'] == column);
  }

  Future<bool> hasMediaKeyIndex(Database db) async {
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'index' AND name = 'idx_media_key'",
    );
    return indexes.isNotEmpty;
  }

  test('v1 库已含 media_key 时升级到 v2 不再抛 duplicate column', () async {
    await createV1Database(
      schema: _v1SchemaWithMediaKey,
      hasMediaKey: true,
    );

    // 回归点：旧实现会无条件 ALTER，抛 "duplicate column name: media_key"，
    // 整个 onUpgrade 失败 -> 数据库打不开 -> 观看历史永远加载不出来。
    final db = await upgradeToV2();
    addTearDown(db.close);

    expect(await db.getVersion(), 2);
    expect(await hasColumn(db, 'media_key'), isTrue);
    expect(await hasMediaKeyIndex(db), isTrue);
    final count = await db.rawQuery('SELECT COUNT(*) AS c FROM watch_history');
    expect(count.first['c'], 1);
  });

  test('标准 v1 库升级到 v2 会补上 media_key 列并保留数据', () async {
    await createV1Database(
      schema: _v1SchemaWithoutMediaKey,
      hasMediaKey: false,
    );

    final db = await upgradeToV2();
    addTearDown(db.close);

    expect(await db.getVersion(), 2);
    expect(await hasColumn(db, 'media_key'), isTrue);
    expect(await hasMediaKeyIndex(db), isTrue);

    final rows = await db.query('watch_history');
    expect(rows, hasLength(1));
    expect(rows.single['anime_name'], '测试番剧');
    expect(rows.single['media_key'], isNull);
  });
}
