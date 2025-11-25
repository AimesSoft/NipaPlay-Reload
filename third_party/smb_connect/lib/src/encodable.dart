import 'dart:typed_data';

abstract class Encodable {
  int encode(Uint8List dst, int dstIndex);

  int size();
}
