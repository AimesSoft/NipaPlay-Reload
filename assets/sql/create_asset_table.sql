CREATE TABLE asset (

  asset_pre16mib_md5 BLOB PRIMARY KEY CHECK (length(asset_pre16mib_md5) = 16),
  asset_size         INTEGER CHECK (asset_size >= 0),
  asset_codec        TEXT,
  asset_sha256       BLOB CHECK (asset_sha256 IS NULL OR length(asset_sha256) = 32)

) STRICT;
