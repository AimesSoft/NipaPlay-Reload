import 'dart:typed_data';

import 'package:nipaplay/services/smb_service.dart';

class Smb2NativeService {
  Smb2NativeService._();

  static final Smb2NativeService instance = Smb2NativeService._();

  bool get isSupported => false;

  Future<List<SMBFileEntry>> listDirectory(
    SMBConnection connection,
    String path,
  ) {
    throw UnsupportedError('libsmb2 is not supported on this platform.');
  }

  Future<Smb2Stat> stat(
    SMBConnection connection,
    String path,
  ) {
    throw UnsupportedError('libsmb2 is not supported on this platform.');
  }

  Stream<Uint8List> openReadStream(
    SMBConnection connection,
    String path, {
    required int start,
    required int endExclusive,
    int chunkSize = 256 * 1024,
  }) {
    throw UnsupportedError('libsmb2 is not supported on this platform.');
  }
}

class Smb2Stat {
  final int type;
  final int size;

  const Smb2Stat({
    required this.type,
    required this.size,
  });

  bool get isDirectory => type == 1;
}

