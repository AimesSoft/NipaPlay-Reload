import 'dart:async';
import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_stream_consumer.dart';
import 'package:smb_connect/src/connect/impl/smb2/io/smb2_write_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/io/smb2_write_response.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/smb/request_param.dart';

class Smb2StreamConsumer extends SmbStreamConsumer {
  final Uint8List fileId;

  Smb2StreamConsumer(super.file, super.tree, this.fileId, super.position);

  @override
  Future close() async {
    await smbCloseFile(file, tree, fileId, 0);
  }

  @override
  Future writeToFile(List<int> b) async {
    int off = 0;
    int len = b.length;
    // int blockSize = (this.file.getType() == SmbConstants.TYPE_FILESYSTEM)
    //     ? this.writeSizeFile
    //     : this.writeSize;

    do {
      int w =
          len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;
      Smb2WriteRequest wr = Smb2WriteRequest(
        tree.config,
        fileId,
        data2: b,
        dataOffset: off,
        dataLength: w,
        offset: position,
        credit: 1,
      );

      tree.prepare(wr);
      Smb2WriteResponse resp =
          await tree.transport.sendrecv(wr, params: {RequestParam.NO_RETRY});
      if (resp.status != NtStatus.NT_STATUS_OK) {
        throw SmbException.getMessageByCode(resp.status);
      }
      int cnt = resp.count;
      position += cnt;
      len -= cnt;
      off += cnt;
    } while (len > 0);
  }
}
