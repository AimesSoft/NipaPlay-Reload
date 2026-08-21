CREATE TABLE net_asset (

  net_url            TEXT PRIMARY KEY,
  asset_pre16mib_md5 BLOB CHECK (asset_pre16mib_md5 IS NULL OR length(asset_pre16mib_md5) = 16),

  FOREIGN KEY (asset_pre16mib_md5) REFERENCES asset (asset_pre16mib_md5) ON DELETE SET NULL

) STRICT;
