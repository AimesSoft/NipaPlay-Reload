CREATE TABLE asset_episode (

  asset_pre16mib_md5            BLOB PRIMARY KEY CHECK (length(asset_pre16mib_md5) = 16),
  episode_id                    INTEGER NOT NULL,
  link_options                  BLOB    NOT NULL DEFAULT X'FFFFFFFF' CHECK (length(link_options) = 4),
  danmaku_offset_dandanplay     REAL    NOT NULL DEFAULT 0.0         CHECK (danmaku_offset_dandanplay >= 0),
  danmaku_offset_user           REAL    NOT NULL DEFAULT 0.0         CHECK (danmaku_offset_user >= 0),
  duration                      INTEGER,
  internal_subtitle_track_count INTEGER,

  FOREIGN KEY (asset_pre16mib_md5) REFERENCES asset   (asset_pre16mib_md5) ON DELETE CASCADE,
  FOREIGN KEY (episode_id        ) REFERENCES episode (episode_id        ) ON DELETE CASCADE

) STRICT;
