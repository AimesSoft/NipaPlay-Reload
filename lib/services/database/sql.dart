class DatabaseSql {
  const DatabaseSql._();

  static const animeTable = 'anime';
  static const episodeTable = 'episode';
  static const dandanplayAnimeTable = 'dandanplay_anime';
  static const dandanplayEpisodeTable = 'dandanplay_episode';
  static const dandanplayDanmakuTable = 'dandanplay_danmaku';
  static const bangumiAnimeTable = 'bangumi_anime';
  static const bangumiEpisodeTable = 'bangumi_episode';
  static const fileTable = 'file';
  static const fileDanmakuTable = 'file_danmaku';
  static const watchHistoryTable = 'watch_history';
  static const sourceTable = 'source';
  static const addressTable = 'address';

  static const animeId = 'anime_id';
  static const episodeId = 'episode_id';
  static const dandanplayAnimeId = 'dandanplay_anime_id';
  static const dandanplayEpisodeId = 'dandanplay_episode_id';
  static const bangumiAnimeId = 'bangumi_anime_id';
  static const bangumiEpisodeId = 'bangumi_episode_id';
  static const fileHash = 'file_hash';
  static const danmakuOffsetDandanplay = 'danmaku_offset_dandanplay';
  static const danmakuOffsetUser = 'danmaku_offset_user';

  static const createAnimeTable = '''
    CREATE TABLE $animeTable(
      $animeId INTEGER PRIMARY KEY
    )
  ''';

  static const createEpisodeTable = '''
    CREATE TABLE $episodeTable(
      $episodeId INTEGER PRIMARY KEY
    )
  ''';

  static const createDandanplayAnimeTable = '''
    CREATE TABLE $dandanplayAnimeTable(
      $dandanplayAnimeId INTEGER PRIMARY KEY,
      $animeId INTEGER NOT NULL,
      $bangumiAnimeId INTEGER,
      cover_image_url TEXT,
      title TEXT,
      description TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY ($animeId) REFERENCES $animeTable ($animeId) ON DELETE CASCADE
    )
  ''';

  static const createDandanplayEpisodeTable = '''
    CREATE TABLE $dandanplayEpisodeTable(
      $dandanplayEpisodeId INTEGER PRIMARY KEY,
      $episodeId INTEGER NOT NULL,
      $dandanplayAnimeId INTEGER NOT NULL,
      title TEXT,
      sort_order REAL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY ($episodeId) REFERENCES $episodeTable ($episodeId) ON DELETE CASCADE,
      FOREIGN KEY ($dandanplayAnimeId) REFERENCES $dandanplayAnimeTable ($dandanplayAnimeId) ON DELETE CASCADE
    )
  ''';

  static const createDandanplayDanmakuTable = '''
    CREATE TABLE $dandanplayDanmakuTable(
      $dandanplayEpisodeId INTEGER PRIMARY KEY,
      danmaku_json TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY ($dandanplayEpisodeId) REFERENCES $dandanplayEpisodeTable ($dandanplayEpisodeId) ON DELETE CASCADE
    )
  ''';

  static const createBangumiAnimeTable = '''
    CREATE TABLE $bangumiAnimeTable(
      $bangumiAnimeId INTEGER PRIMARY KEY,
      $animeId INTEGER NOT NULL,
      air_date TEXT,
      title TEXT,
      title_cn TEXT,
      aliases TEXT,
      description TEXT,
      episode_count INTEGER,
      url_official_site TEXT,
      url_cover TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY ($animeId) REFERENCES $animeTable ($animeId) ON DELETE CASCADE
    )
  ''';

  static const createBangumiEpisodeTable = '''
    CREATE TABLE $bangumiEpisodeTable(
      $bangumiEpisodeId INTEGER PRIMARY KEY,
      $episodeId INTEGER NOT NULL,
      $bangumiAnimeId INTEGER NOT NULL,
      episode_number INTEGER,
      sort_order REAL,
      air_date TEXT,
      duration_seconds INTEGER,
      title TEXT,
      title_cn TEXT,
      description TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY ($episodeId) REFERENCES $episodeTable ($episodeId) ON DELETE CASCADE,
      FOREIGN KEY ($bangumiAnimeId) REFERENCES $bangumiAnimeTable ($bangumiAnimeId) ON DELETE CASCADE
    )
  ''';

  static const createFileTable = '''
    CREATE TABLE $fileTable(
      $fileHash TEXT PRIMARY KEY,
      $episodeId INTEGER NOT NULL,
      file_name TEXT,
      file_size INTEGER,
      duration INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY ($episodeId) REFERENCES $episodeTable ($episodeId) ON DELETE CASCADE
    )
  ''';

  static const createFileDanmakuTable = '''
    CREATE TABLE $fileDanmakuTable(
      $fileHash TEXT PRIMARY KEY,
      $dandanplayEpisodeId INTEGER,
      danmaku_offset_dandanplay REAL,
      danmaku_offset_user REAL,
      FOREIGN KEY ($fileHash) REFERENCES $fileTable ($fileHash) ON DELETE CASCADE,
      FOREIGN KEY ($dandanplayEpisodeId) REFERENCES $dandanplayEpisodeTable ($dandanplayEpisodeId) ON DELETE SET NULL
    )
  ''';

  static const createWatchHistoryTable = '''
    CREATE TABLE $watchHistoryTable(
      $episodeId INTEGER PRIMARY KEY,
      $fileHash TEXT NOT NULL,
      watch_progress REAL NOT NULL,
      last_position INTEGER NOT NULL,
      duration INTEGER NOT NULL,
      last_watch_time TEXT NOT NULL,
      thumbnail_path TEXT,
      FOREIGN KEY ($episodeId) REFERENCES $episodeTable ($episodeId) ON DELETE CASCADE,
      FOREIGN KEY ($fileHash) REFERENCES $fileTable ($fileHash) ON DELETE CASCADE
    )
  ''';

  static const createSourceTable = '''
    CREATE TABLE $sourceTable(
      id TEXT PRIMARY KEY,
      source_type TEXT NOT NULL,
      url TEXT NOT NULL,
      username TEXT,
      password TEXT,
      metadata_json TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const createAddressTable = '''
    CREATE TABLE $addressTable(
      source_id TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      $fileHash TEXT,
      last_synced_at TEXT NOT NULL,
      PRIMARY KEY (source_id, relative_path),
      FOREIGN KEY (source_id) REFERENCES $sourceTable (id) ON DELETE CASCADE,
      FOREIGN KEY ($fileHash) REFERENCES $fileTable ($fileHash) ON DELETE SET NULL
    )
  ''';

  static const createIndexes = <String>[
    'CREATE INDEX idx_dandanplay_episode_anime_id ON $dandanplayEpisodeTable($dandanplayAnimeId)',
    'CREATE INDEX idx_bangumi_episode_anime_id ON $bangumiEpisodeTable($bangumiAnimeId)',
    'CREATE INDEX idx_media_file_episode_id ON $fileTable($episodeId)',
    'CREATE INDEX idx_file_danmaku_episode_id ON $fileDanmakuTable($dandanplayEpisodeId)',
    'CREATE INDEX idx_watch_history_file_hash ON $watchHistoryTable($fileHash)',
    'CREATE INDEX idx_watch_history_last_watch_time ON $watchHistoryTable(last_watch_time)',
    'CREATE INDEX idx_media_address_file_hash ON $addressTable($fileHash)',
  ];

  static const createTables = <String>[
    createAnimeTable,
    createEpisodeTable,
    createDandanplayAnimeTable,
    createDandanplayEpisodeTable,
    createDandanplayDanmakuTable,
    createBangumiAnimeTable,
    createBangumiEpisodeTable,
    createFileTable,
    createFileDanmakuTable,
    createWatchHistoryTable,
    createSourceTable,
    createAddressTable,
  ];
}
