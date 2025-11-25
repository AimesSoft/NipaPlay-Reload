import 'dart:async';

import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_stream_consumer.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write_response.dart';
import 'package:smb_connect/src/smb/request_param.dart';

abstract class _Smb1StreamConsumer extends SmbStreamConsumer {
  final int fid;
  _Smb1StreamConsumer(super.file, super.tree, this.fid, super.position);

  @override
  Future close() async {
    await smbCloseFile(file, tree, null, fid);
  }
}

class Smb1ComStreamConsumer extends _Smb1StreamConsumer {
  final SmbComWrite _req;
  final SmbComWriteResponse _rsp;

  Smb1ComStreamConsumer(super.file, super.tree, super.fid, super.position)
      : _req = SmbComWrite(tree.config),
        _rsp = SmbComWriteResponse(tree.config);

  @override
  Future writeToFile(List<int> b) async {
    int off = 0;
    int len = b.length;

    do {
      int w =
          len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;
      w = len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;

      _req.setParam2(fid, position, len - w, b, off, w);
      tree.prepare(_req);
      await tree.transport.sendrecv(_req, response: _rsp);
      int cnt = _rsp.getCount();
      position += cnt;
      len -= cnt;
      off += cnt;
    } while (len > 0);
  }
}

class Smb1ComAndXStreamConsumer extends _Smb1StreamConsumer {
  final SmbComWriteAndX _reqx;
  final SmbComWriteAndXResponse _rspx;

  Smb1ComAndXStreamConsumer(super.file, super.tree, super.fid, super.position)
      : _reqx = SmbComWriteAndX(tree.config),
        _rspx = SmbComWriteAndXResponse(tree.config);

  @override
  Future writeToFile(List<int> b) async {
    int off = 0;
    int len = b.length;

    do {
      int w =
          len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;
      w = len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;

      _reqx.setParam2(fid, position, len - w, b, off, w);
      // if ((flags & 1) != 0) {
      //   _reqx.setParam(fid, position, len, b, off, w);
      //   _reqx.setWriteMode(0x8);
      // } else {
      _reqx.setWriteMode(0);
      // }

      tree.prepare(_reqx);
      await tree.transport
          .sendrecv(_reqx, response: _rspx, params: {RequestParam.NO_RETRY});
      int cnt = _rspx.getCount();
      position += cnt;
      len -= cnt;
      off += cnt;
    } while (len > 0);
  }
}
