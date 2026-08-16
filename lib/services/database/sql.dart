class DatabaseSql {
  const DatabaseSql._();

  static const Map<String, String> expectedCreateTableSql = {
    DatabaseSql.watchHistoryTable: DatabaseSql.createWatchHistoryTable,
    DatabaseSql.mediaAnimeTable: DatabaseSql.createMediaAnimeTable,
    DatabaseSql.mediaEpisodeTable: DatabaseSql.createMediaEpisodeTable,
    DatabaseSql.mediaFileTable: DatabaseSql.createMediaFileTable,
    DatabaseSql.mediaSourceTable: DatabaseSql.createMediaSourceTable,
    DatabaseSql.mediaAddressTable: DatabaseSql.createMediaAddressTable,
  };

  // 表名
  static const String watchHistoryTable = 'watch_history';
  static const String mediaAnimeTable   = 'anime';
  static const String mediaEpisodeTable = 'episode';
  static const String mediaFileTable    = 'file';
  static const String mediaSourceTable  = 'source';
  static const String mediaAddressTable = 'address';

  // watch_history 字段
  static const String whId = 'id';
  static const String whFilePath = 'file_path';
  static const String whAnimeName = 'anime_name';
  static const String whEpisodeTitle = 'episode_title';
  static const String whEpisodeId = 'episode_id';
  static const String whAnimeId = 'anime_id';
  static const String whWatchProgress = 'watch_progress';
  static const String whLastPosition = 'last_position';
  static const String whDuration = 'duration';
  static const String whLastWatchTime = 'last_watch_time';
  static const String whThumbnailPath = 'thumbnail_path';
  static const String whIsFromScan = 'is_from_scan';
  static const String whVideoHash = 'video_hash';

  // media_anime 字段
  static const String maId = 'id';
  static const String maTitle = 'title';
  static const String maCoverImageUrl = 'cover_image_url';
  static const String maDescription = 'description';
  static const String maCreatedAt = 'created_at';
  static const String maUpdatedAt = 'updated_at';

  // media_episode 字段
  static const String meId = 'id';
  static const String meAnimeId = 'anime_id';
  static const String meTitle = 'title';
  static const String meSortOrder = 'sort_order';
  static const String meCreatedAt = 'created_at';
  static const String meUpdatedAt = 'updated_at';

  // media_file 字段
  static const String mfFileHash = 'file_hash';
  static const String mfAnimeId = 'anime_id';
  static const String mfEpisodeId = 'episode_id';
  static const String mfFileName = 'file_name';
  static const String mfFileSize = 'file_size';
  static const String mfDuration = 'duration';
  static const String mfCreatedAt = 'created_at';
  static const String mfUpdatedAt = 'updated_at';

  // media_source 字段
  static const String msId = 'id';
  static const String msSourceType = 'source_type';
  static const String msUrl = 'url';
  static const String msUsername = 'username';
  static const String msPassword = 'password';
  static const String msMetadataJson = 'metadata_json';
  static const String msCreatedAt = 'created_at';
  static const String msUpdatedAt = 'updated_at';

  // media_address 字段
  static const String mdSourceId = 'source_id';
  static const String mdRelativePath = 'relative_path';
  static const String mdFileHash = 'file_hash';
  static const String mdLastSyncedAt = 'last_synced_at';

  static const String createWatchHistoryTable = '''
    CREATE TABLE $watchHistoryTable(
      $whId INTEGER PRIMARY KEY AUTOINCREMENT,
      $whFilePath TEXT UNIQUE NOT NULL,
      $whAnimeName TEXT NOT NULL,
      $whEpisodeTitle TEXT,
      $whEpisodeId INTEGER,
      $whAnimeId INTEGER,
      $whWatchProgress REAL NOT NULL,
      $whLastPosition INTEGER NOT NULL,
      $whDuration INTEGER NOT NULL,
      $whLastWatchTime TEXT NOT NULL,
      $whThumbnailPath TEXT,
      $whIsFromScan INTEGER NOT NULL,
      $whVideoHash TEXT
    )
  ''';

  static const String createWatchHistoryFilePathIndex =
      'CREATE INDEX idx_file_path ON $watchHistoryTable($whFilePath)';
  static const String createWatchHistoryAnimeIdIndex =
      'CREATE INDEX idx_anime_id ON $watchHistoryTable($whAnimeId)';
  static const String createWatchHistoryLastWatchTimeIndex =
      'CREATE INDEX idx_last_watch_time ON $watchHistoryTable($whLastWatchTime)';
  static const String selectWatchHistoryCount =
      'SELECT COUNT(*) FROM $watchHistoryTable';
  static const String alterWatchHistoryAddVideoHash =
      'ALTER TABLE $watchHistoryTable ADD COLUMN $whVideoHash TEXT';

  static const String createMediaAnimeTable = '''
    CREATE TABLE IF NOT EXISTS $mediaAnimeTable(
      $maId INTEGER PRIMARY KEY,
      $maTitle TEXT NOT NULL,
      $maCoverImageUrl TEXT,
      $maDescription TEXT,
      $maCreatedAt TEXT NOT NULL,
      $maUpdatedAt TEXT NOT NULL
    )
  ''';

  static const String createMediaEpisodeTable = '''
    CREATE TABLE IF NOT EXISTS $mediaEpisodeTable(
      $meId INTEGER PRIMARY KEY,
      $meAnimeId INTEGER NOT NULL,
      $meTitle TEXT,
      $meSortOrder REAL,
      $meCreatedAt TEXT NOT NULL,
      $meUpdatedAt TEXT NOT NULL,
      FOREIGN KEY ($meAnimeId) REFERENCES $mediaAnimeTable ($maId) ON DELETE CASCADE
    )
  ''';

  static const String createMediaFileTable = '''
    CREATE TABLE IF NOT EXISTS $mediaFileTable(
      $mfFileHash TEXT PRIMARY KEY,
      $mfAnimeId INTEGER,
      $mfEpisodeId INTEGER,
      $mfFileName TEXT,
      $mfFileSize INTEGER,
      $mfDuration INTEGER,
      $mfCreatedAt TEXT NOT NULL,
      $mfUpdatedAt TEXT NOT NULL,
      FOREIGN KEY ($mfAnimeId) REFERENCES $mediaAnimeTable ($maId) ON DELETE SET NULL,
      FOREIGN KEY ($mfEpisodeId) REFERENCES $mediaEpisodeTable ($meId) ON DELETE SET NULL
    )
  ''';

  static const String createMediaSourceTable = '''
    CREATE TABLE IF NOT EXISTS $mediaSourceTable(
      $msId TEXT PRIMARY KEY,
      $msSourceType TEXT NOT NULL,
      $msUrl TEXT NOT NULL,
      $msUsername TEXT,
      $msPassword TEXT,
      $msMetadataJson TEXT,
      $msCreatedAt TEXT NOT NULL,
      $msUpdatedAt TEXT NOT NULL
    )
  ''';

  static const String createMediaAddressTable = '''
    CREATE TABLE IF NOT EXISTS $mediaAddressTable(
      $mdSourceId TEXT NOT NULL,
      $mdRelativePath TEXT NOT NULL,
      $mdFileHash TEXT,
      $mdLastSyncedAt TEXT NOT NULL,
      PRIMARY KEY ($mdSourceId, $mdRelativePath),
      FOREIGN KEY ($mdSourceId) REFERENCES $mediaSourceTable ($msId) ON DELETE CASCADE,
      FOREIGN KEY ($mdFileHash) REFERENCES $mediaFileTable ($mfFileHash) ON DELETE SET NULL
    )
  ''';

  static const String createMediaFileEpisodeIdIndex =
      'CREATE INDEX IF NOT EXISTS idx_media_file_episode_id ON $mediaFileTable($mfEpisodeId)';
  static const String createMediaFileAnimeIdIndex =
      'CREATE INDEX IF NOT EXISTS idx_media_file_anime_id ON $mediaFileTable($mfAnimeId)';
  static const String createMediaAddressFileHashIndex =
      'CREATE INDEX IF NOT EXISTS idx_media_address_file_hash ON $mediaAddressTable($mdFileHash)';

  static const String whereFilePathEq = '$whFilePath = ?';
  static const String whereFilePathLike = '$whFilePath LIKE ?';
  static const String whereFileHashEq = '$mfFileHash = ?';
  static const String whereAnimeEpisodeEq = '$whAnimeId = ? AND $whEpisodeId = ?';
  static const String whereAnimeEpisodeNotNull =
      '$whAnimeId = ? AND $whEpisodeId IS NOT NULL';
  static const String whereAnimeEpisodeLessThanNotNull =
      '$whAnimeId = ? AND $whEpisodeId < ? AND $whEpisodeId IS NOT NULL';
  static const String whereAnimeEpisodeGreaterThanNotNull =
      '$whAnimeId = ? AND $whEpisodeId > ? AND $whEpisodeId IS NOT NULL';
  static const String whereAnimeIdEq = '$whAnimeId = ?';

  static const String orderByLastWatchTimeDesc = '$whLastWatchTime DESC';
  static const String orderByEpisodeAsc = '$whEpisodeId ASC';
  static const String orderByEpisodeDesc = '$whEpisodeId DESC';
  static const String orderByLastSyncedAtDesc = '$mdLastSyncedAt DESC';

  static String pragmaTableInfo(String tableName) =>
      'PRAGMA table_info($tableName)';

  static String whereIn(String column, int count) =>
      '$column IN (${List.filled(count, '?').join(',')})';
}
