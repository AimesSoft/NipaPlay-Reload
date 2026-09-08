CREATE TABLE anime (

  anime_id INTEGER PRIMARY KEY CHECK (anime_id >= 0)

) STRICT;

CREATE TABLE asset_episode (

  asset_pre16mib_md5            BLOB PRIMARY KEY CHECK (length(asset_pre16mib_md5) = 16),
  episode_id                    INTEGER NOT NULL,

  FOREIGN KEY (asset_pre16mib_md5) REFERENCES asset   (asset_pre16mib_md5) ON DELETE CASCADE,
  FOREIGN KEY (episode_id        ) REFERENCES episode (episode_id        ) ON DELETE CASCADE

) STRICT;

CREATE TABLE asset (

  asset_pre16mib_md5 BLOB PRIMARY KEY CHECK (length(asset_pre16mib_md5) = 16),
  asset_size         INTEGER CHECK (asset_size >= 0),
  asset_codec        TEXT,
  asset_sha256       BLOB CHECK (asset_sha256 IS NULL OR length(asset_sha256) = 32)

) STRICT;

CREATE TABLE bangumi_anime (

  bangumi_anime_id INTEGER PRIMARY KEY CHECK (bangumi_anime_id >= 0),
  anime_id INTEGER NOT NULL UNIQUE,
  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;

CREATE TABLE bangumi_episode (

  bangumi_episode_id INTEGER PRIMARY KEY CHECK (bangumi_episode_id >= 0),
  bangumi_anime_id   INTEGER NOT NULL,
  episode_id         INTEGER NOT NULL UNIQUE,

  FOREIGN KEY (bangumi_anime_id) REFERENCES bangumi_anime (bangumi_anime_id) ON DELETE CASCADE,
  FOREIGN KEY (episode_id      ) REFERENCES episode       (episode_id      ) ON DELETE CASCADE

) STRICT;

CREATE TABLE dandanplay_anime (

  dandanplay_anime_id INTEGER PRIMARY KEY CHECK (dandanplay_anime_id >= 0),
  anime_id INTEGER NOT NULL UNIQUE,

  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;

CREATE TABLE dandanplay_episode (

  dandanplay_episode_id INTEGER PRIMARY KEY CHECK (dandanplay_episode_id >= 0),
  dandanplay_anime_id   INTEGER NOT NULL,
  episode_id            INTEGER NOT NULL UNIQUE,

  FOREIGN KEY (dandanplay_anime_id) REFERENCES dandanplay_anime (dandanplay_anime_id) ON DELETE CASCADE,
  FOREIGN KEY (episode_id         ) REFERENCES episode          (episode_id         ) ON DELETE CASCADE

) STRICT;

CREATE TABLE episode (

  episode_id INTEGER PRIMARY KEY CHECK (episode_id >= 0),
  anime_id   INTEGER NOT NULL,

  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;

CREATE TABLE net_asset (

  net_url            TEXT PRIMARY KEY,
  asset_pre16mib_md5 BLOB CHECK (asset_pre16mib_md5 IS NULL OR length(asset_pre16mib_md5) = 16),

  FOREIGN KEY (asset_pre16mib_md5) REFERENCES asset (asset_pre16mib_md5) ON DELETE SET NULL

) STRICT;

CREATE TABLE path_asset (

  source_id         INTEGER NOT NULL DEFAULT 0 CHECK (source_id >= 0),
  asset_address     TEXT    NOT NULL DEFAULT '',
  asset_name_no_ext TEXT    NOT NULL DEFAULT '',
  asset_extension   TEXT    NOT NULL DEFAULT '',

  updated_at         TEXT NOT NULL,
  asset_pre16mib_md5 BLOB CHECK (asset_pre16mib_md5 IS NULL OR length(asset_pre16mib_md5) = 16),
  asset_created_at   TEXT,
  asset_updated_at   TEXT,

  PRIMARY KEY (source_id, asset_address, asset_name_no_ext, asset_extension),
  FOREIGN KEY (asset_pre16mib_md5) REFERENCES asset (asset_pre16mib_md5) ON DELETE SET NULL

) STRICT;

CREATE INDEX idx_asset_episode_episode_id
ON asset_episode (episode_id);

CREATE INDEX idx_bangumi_episode_anime_id
ON bangumi_episode (bangumi_anime_id);

CREATE INDEX idx_dandanplay_episode_anime_id
ON dandanplay_episode (dandanplay_anime_id);

CREATE INDEX idx_episode_anime_id
ON episode (anime_id);

CREATE INDEX idx_net_asset_asset_pre16mib_md5
ON net_asset (asset_pre16mib_md5);

CREATE INDEX idx_path_asset_asset_pre16mib_md5
ON path_asset (asset_pre16mib_md5);

