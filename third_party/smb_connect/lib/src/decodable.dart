import 'dart:typed_data';

abstract class Decodable {
  int decode(Uint8List buffer, int bufferIndex, int len);
}
