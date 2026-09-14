CREATE TABLE asset_episode (

  asset_pre16mib_md5            BLOB PRIMARY KEY CHECK (length(asset_pre16mib_md5) = 16),
  episode_id                    INTEGER NOT NULL,

  FOREIGN KEY (asset_pre16mib_md5) REFERENCES asset   (asset_pre16mib_md5) ON DELETE CASCADE,
  FOREIGN KEY (episode_id        ) REFERENCES episode (episode_id        ) ON DELETE CASCADE

) STRICT;
