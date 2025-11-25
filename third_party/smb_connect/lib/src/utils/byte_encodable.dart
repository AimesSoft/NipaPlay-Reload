import 'dart:typed_data';

import 'package:smb_connect/src/encodable.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class ByteEncodable implements Encodable {
  final Uint8List _bytes;
  final int _off;
  final int _len;

  ByteEncodable(this._bytes, this._off, this._len);

  @override
  int size() {
    return _len;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    arrayCopy(_bytes, _off, dst, dstIndex, _len);
    return _len;
  }
}
