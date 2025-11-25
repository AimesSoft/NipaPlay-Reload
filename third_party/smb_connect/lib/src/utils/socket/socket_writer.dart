import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/src/utils/extensions.dart';

class SocketWriter {
  final bool debugPrint;
  final Socket _socket;

  SocketWriter(this._socket, {this.debugPrint = false});

  int lastWrite = 0;

  void write(Uint8List buffer, int offset, int length) async {
    var buf = Uint8List.view(buffer.buffer, offset, length);
    _socket.add(buf);
    lastWrite += buf.length;
    if (debugPrint) {
      print("write[$length]: ${buf.toHexString2(offset, length)}");
    }
  }

  Future<void> flush() async {
    if (debugPrint) {
      print("write flush $lastWrite");
    }
    await _socket.flush();
    lastWrite = 0;
  }
}
