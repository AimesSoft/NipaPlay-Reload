class DatabaseSql {
  const DatabaseSql._();

  static const Map<String, String> expectedCreateTableSql = {
    DatabaseSql.watchHistoryTable: DatabaseSql.createWatchHistoryTable,
    DatabaseSql.mediaAnimeTable: DatabaseSql.createMediaAnimeTable,
    DatabaseSql.mediaEpisodeTable: DatabaseSql.createMediaEpisodeTable,
    DatabaseSql.mediaFileTable: DatabaseSql.createMediaFileTable,
    DatabaseSql.mediaSourceTable: DatabaseSql.createMediaSourceTable,
    DatabaseSql.mediaAddressTable: DatabaseSql.createMediaAddressTable,
    DatabaseSql.bangumiAnimeTable: DatabaseSql.createBangumiAnimeTable,
    DatabaseSql.bangumiEpisodeTable: DatabaseSql.createBangumiEpisodeTable,
    DatabaseSql.dandanplayBangumiAnimeRelationTable: DatabaseSql.createDandanplayBangumiAnimeRelationTable,
    DatabaseSql.dandanplayBangumiEpisodeRelationTable: DatabaseSql.createDandanplayBangumiEpisodeRelationTable,
  };

  // 表名
  static const String watchHistoryTable = 'watch_history';
  static const String mediaAnimeTable   = 'dandanplay_anime';
  static const String mediaEpisodeTable = 'dandanplay_episode';
  static const String mediaFileTable    = 'file';
  static const String mediaSourceTable  = 'source';
  static const String mediaAddressTable = 'address';
  static const String bangumiAnimeTable = 'bangumi_anime';
  static const String bangumiEpisodeTable = 'bangumi_episode';
  static const String dandanplayBangumiAnimeRelationTable = 'relation_dandanplay_bangumi_anime';
  static const String dandanplayBangumiEpisodeRelationTable = 'relation_dandanplay_bangumi_episode';

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
  static const String maDandanplayAnimeId = 'dandanplay_anime_id';
  static const String maTitle = 'title';
  static const String maCoverImageUrl = 'cover_image_url';
  static const String maDescription = 'description';
  static const String maUpdatedAt = 'updated_at';

  // media_episode 字段
  static const String meDandanplayEpisodeId = 'dandanplay_episode_id';
  static const String meDandanplayAnimeId = 'dandanplay_anime_id';
  static const String meTitle = 'title';
  static const String meSortOrder = 'sort_order';
  static const String meUpdatedAt = 'updated_at';

  // media_file 字段
  static const String mfFileHash = 'file_hash';
  static const String mfDandanplayAnimeId = 'dandanplay_anime_id';
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

  // bangumi_anime 字段
  static const String baId = 'bangumi_anime_id';
  static const String baAirDate = 'air_date';
  static const String baTitle = 'title';
  static const String baTitleCn = 'title_cn';
  static const String baAliases = 'aliases';
  static const String baDescription = 'description';
  static const String baEpisodeCount = 'episode_count';
  static const String baOfficialSiteUrl = 'url_official_site';
  static const String baCoverImageUrl = 'url_cover';
  static const String baUpdatedAt = 'updated_at';

  // bangumi_episode 字段
  static const String beId = 'bangumi_episode_id';
  static const String beAnimeId = 'bangumi_anime_id';
  static const String beEpisodeNumber = 'episode_number';
  static const String beSortOrder = 'sort_order';
  static const String beAirDate = 'air_date';
  static const String beDurationSeconds = 'duration_seconds';
  static const String beTitle = 'title';
  static const String beTitleCn = 'title_cn';
  static const String beDescription = 'description';
  static const String beUpdatedAt = 'updated_at';

  // relation 字段
  static const String raDandanplayAnimeId = 'dandanplay_anime_id';
  static const String raBangumiAnimeId = 'bangumi_anime_id';
  static const String reDandanplayEpisodeId = 'dandanplay_episode_id';
  static const String reBangumiEpisodeId = 'bangumi_episode_id';

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
      $maDandanplayAnimeId INTEGER PRIMARY KEY,
      $maCoverImageUrl TEXT,
      $maTitle TEXT,
      $maDescription TEXT,
      $maUpdatedAt TEXT NOT NULL
    )
  ''';

  static const String createMediaEpisodeTable = '''
    CREATE TABLE IF NOT EXISTS $mediaEpisodeTable(
      $meDandanplayEpisodeId INTEGER PRIMARY KEY,
      $meDandanplayAnimeId INTEGER NOT NULL,
      $meTitle TEXT,
      $meSortOrder REAL,
      $meUpdatedAt TEXT NOT NULL,
      FOREIGN KEY ($meDandanplayAnimeId) REFERENCES $mediaAnimeTable ($maDandanplayAnimeId) ON DELETE CASCADE
    )
  ''';

  static const String createMediaFileTable = '''
    CREATE TABLE IF NOT EXISTS $mediaFileTable(
      $mfFileHash TEXT PRIMARY KEY,
      $mfDandanplayAnimeId INTEGER,
      $mfEpisodeId INTEGER,
      $mfFileName TEXT,
      $mfFileSize INTEGER,
      $mfDuration INTEGER,
      $mfCreatedAt TEXT NOT NULL,
      $mfUpdatedAt TEXT NOT NULL,
      FOREIGN KEY ($mfDandanplayAnimeId) REFERENCES $mediaAnimeTable ($maDandanplayAnimeId) ON DELETE SET NULL,
      FOREIGN KEY ($mfEpisodeId) REFERENCES $mediaEpisodeTable ($meDandanplayEpisodeId) ON DELETE SET NULL
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

  static const String createBangumiAnimeTable = '''
    CREATE TABLE IF NOT EXISTS $bangumiAnimeTable(
      $baId INTEGER PRIMARY KEY,
      $baAirDate TEXT,
      $baTitle TEXT,
      $baTitleCn TEXT,
      $baAliases TEXT,
      $baDescription TEXT,
      $baEpisodeCount INTEGER,
      $baOfficialSiteUrl TEXT,
      $baCoverImageUrl TEXT,
      $baUpdatedAt TEXT NOT NULL
    )
  ''';

  static const String createBangumiEpisodeTable = '''
    CREATE TABLE IF NOT EXISTS $bangumiEpisodeTable(
      $beId INTEGER PRIMARY KEY,
      $beAnimeId INTEGER NOT NULL,
      $beEpisodeNumber INTEGER,
      $beSortOrder REAL,
      $beAirDate TEXT,
      $beDurationSeconds INTEGER,
      $beTitle TEXT,
      $beTitleCn TEXT,
      $beDescription TEXT,
      $beUpdatedAt TEXT NOT NULL,
      FOREIGN KEY ($beAnimeId) REFERENCES $bangumiAnimeTable ($baId) ON DELETE CASCADE
    )
  ''';

  static const String createDandanplayBangumiAnimeRelationTable = '''
    CREATE TABLE IF NOT EXISTS $dandanplayBangumiAnimeRelationTable(
      $raDandanplayAnimeId INTEGER NOT NULL UNIQUE,
      $raBangumiAnimeId INTEGER NOT NULL UNIQUE,
      PRIMARY KEY ($raDandanplayAnimeId, $raBangumiAnimeId),
      FOREIGN KEY ($raDandanplayAnimeId) REFERENCES $mediaAnimeTable ($maDandanplayAnimeId) ON DELETE CASCADE,
      FOREIGN KEY ($raBangumiAnimeId) REFERENCES $bangumiAnimeTable ($baId) ON DELETE CASCADE
    )
  ''';

  static const String createDandanplayBangumiEpisodeRelationTable = '''
    CREATE TABLE IF NOT EXISTS $dandanplayBangumiEpisodeRelationTable(
      $reDandanplayEpisodeId INTEGER NOT NULL UNIQUE,
      $reBangumiEpisodeId INTEGER NOT NULL UNIQUE,
      PRIMARY KEY ($reDandanplayEpisodeId, $reBangumiEpisodeId),
      FOREIGN KEY ($reDandanplayEpisodeId) REFERENCES $mediaEpisodeTable ($meDandanplayEpisodeId) ON DELETE CASCADE,
      FOREIGN KEY ($reBangumiEpisodeId) REFERENCES $bangumiEpisodeTable ($beId) ON DELETE CASCADE
    )
  ''';

  static const String createBangumiEpisodeAnimeIdIndex =
      'CREATE INDEX IF NOT EXISTS idx_bangumi_episode_anime_id ON $bangumiEpisodeTable($beAnimeId)';

  static const String createMediaFileEpisodeIdIndex =
      'CREATE INDEX IF NOT EXISTS idx_media_file_episode_id ON $mediaFileTable($mfEpisodeId)';
  static const String createMediaFileAnimeIdIndex =
      'CREATE INDEX IF NOT EXISTS idx_media_file_anime_id ON $mediaFileTable($mfDandanplayAnimeId)';
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
