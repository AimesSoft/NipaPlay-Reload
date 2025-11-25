import 'dart:typed_data';

abstract class BufferCache {
  Uint8List getBuffer();

  void releaseBuffer(Uint8List buf);
}
