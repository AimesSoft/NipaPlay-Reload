import 'package:flutter/services.dart';

class DatabaseSql {

  const DatabaseSql._();

  static const _directory = 'assets/sql';

  static const _createTableFiles = <String>[
    'create_anime_table.sql',
    'create_episode_table.sql',
    'create_dandanplay_anime_table.sql',
    'create_dandanplay_episode_table.sql',
    'create_bangumi_anime_table.sql',
    'create_bangumi_episode_table.sql',
    'create_asset_table.sql',
    'create_net_asset_table.sql',
    'create_path_asset_table.sql',
    'create_asset_episode_table.sql',
    'create_episode_watch_status_table.sql',
  ];

  static const _createIndexFiles = <String>[
    'create_episode_anime_id_index.sql',
    'create_dandanplay_anime_anime_id_index.sql',
    'create_dandanplay_episode_anime_id_index.sql',
    'create_dandanplay_episode_episode_id_index.sql',
    'create_bangumi_anime_anime_id_index.sql',
    'create_bangumi_episode_anime_id_index.sql',
    'create_bangumi_episode_episode_id_index.sql',
    'create_net_asset_hash_index.sql',
    'create_path_asset_hash_index.sql',
    'create_asset_episode_episode_id_index.sql',
    'create_watch_status_video_hash_index.sql',
    'create_watch_status_thumbnail_hash_index.sql',
    'create_watch_status_last_watch_time_index.sql',
  ];

  static const enableForeignKeys = 'PRAGMA foreign_keys = ON';
  static const selectTableNames = '''
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
  ''';
  static const insertAnime = 'INSERT INTO anime DEFAULT VALUES';

  static late final List<String> createTables;
  static late final List<String> createIndexes;

  static Future<void>? _loadFuture;

  static Future<void> load() => _loadFuture ??= _loadAll();

  static Future<void> _loadAll() async {
    createTables = await Future.wait(_createTableFiles.map(_load));
    createIndexes = await Future.wait(_createIndexFiles.map(_load));
  }

  static Future<String> _load(String fileName) => rootBundle.loadString('$_directory/$fileName');
}
