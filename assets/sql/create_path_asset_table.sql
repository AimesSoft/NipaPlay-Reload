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
