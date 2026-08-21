
// lib/models/database/asset_record.dart

import 'dart:typed_data';


class DbAssetRecord {

  final Uint8List  hashPre16MiBMd5;
  final int?       size;
  final String?    codec;
  final Uint8List? hashSha256;

  DbAssetRecord({
    required this.hashPre16MiBMd5,
    this.size,
    this.codec,
    this.hashSha256,
  });
}


enum DbAssetType {
  video,
  image,
}
