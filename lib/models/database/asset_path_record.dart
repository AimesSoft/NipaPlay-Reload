
// lib/models/database/asset_path_record.dart

import 'dart:typed_data';


class AssetPath {

  int             mediaSourceId;
  AssetPathInSource pathInSource;

  AssetPath({
    required this.mediaSourceId,
    required this.pathInSource,
  });
}

class AssetPathInSource {

  final String  path;      // 媒体源根目录下的相对路径
  final String  nameNoExt; // 文件名 (不包含扩展名)
  final String  ext;       // 文件扩展名 (不包含点号)

  AssetPathInSource({
    required this.path,
    required this.nameNoExt,
    required this.ext,
  });
}

class DbPathAssetRecord {

  final AssetPath assetPath;

  // 前 16MiB 的 MD5 哈希值 (用于快速查重)
  final Uint8List? hashPre16MiBMd5;

  // 文件创建/修改时间
  final String? createdAt;
  final String? updatedAt;

  DbPathAssetRecord({
    required this.assetPath,
    this.hashPre16MiBMd5,
    this.createdAt,
    this.updatedAt,
  });
}