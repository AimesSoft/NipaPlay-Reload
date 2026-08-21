CREATE TABLE episode_watch_status (

  episode_id      INTEGER PRIMARY KEY,
  is_watched      INTEGER NOT NULL DEFAULT 0 CHECK (is_watched IN (0, 1)),
  last_progress   REAL CHECK (last_progress >= 0 AND last_progress <= 1),
  last_position   REAL CHECK (last_position >= 0),
  last_watch_time TEXT,
  video_file_hash BLOB CHECK (video_file_hash IS NULL OR length(video_file_hash) = 16),
  thumbnail_hash  BLOB CHECK (thumbnail_hash  IS NULL OR length(thumbnail_hash ) = 16),

  FOREIGN KEY (episode_id     ) REFERENCES episode (episode_id        ) ON DELETE CASCADE,
  FOREIGN KEY (video_file_hash) REFERENCES asset   (asset_pre16mib_md5) ON DELETE SET NULL,
  FOREIGN KEY (thumbnail_hash ) REFERENCES asset   (asset_pre16mib_md5) ON DELETE SET NULL

) STRICT;
