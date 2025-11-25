import 'dart:typed_data';

abstract class RequestWithFileId {
  void setFileId(Uint8List fileId);
}
