import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_write_response.dart';
import 'package:smb_connect/src/connect/smb_file.dart';
import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_random_access_file.dart';
import 'package:smb_connect/src/connect/smb_stream_consumer.dart';
import 'package:smb_connect/src/smb_constants.dart';

typedef OpenFileSmb1Fuction = Future<(int, SmbFile)> Function(
    String path, String share, String uncPath,
    {required int openFlags,
    required int access,
    required int sharing,
    required int attrs});

class Smb1RandomAccessFileController extends SmbRandomAccessFileController {
  final OpenFileSmb1Fuction openFile;
  final bool isCapabilitiyNtSMBS;
  int fid = 0;

  Smb1RandomAccessFileController(
    super.file,
    super.tree,
    super.mode,
    this.openFile,
    this.isCapabilitiyNtSMBS,
  );

  @override
  Future<int> open() async {
    final res = await openFile(file.path, file.share, file.uncPath,
        openFlags: 0,
        access: modeToAccess(),
        sharing: SmbConstants.DEFAULT_SHARING,
        attrs: SmbConstants.ATTR_NORMAL);
    fid = res.$1;
    return res.$2.size;
  }

  @override
  Future close() => smbCloseFile(file, tree, null, fid);

  @override
  Future<int> read(Uint8List buff, int offset, int length) {
    return smbReadFromFile(file, tree, null, fid, buff, offset, 0, length);
  }

  @override
  Future<int> write(List<int> buff, int position, int offset, int length) {
    if (isCapabilitiyNtSMBS) {
      return _writeCom(buff, position, offset, length);
    } else {
      return _writeComAndX(buff, position, offset, length);
    }
  }

  Future<int> _writeCom(
      List<int> buff, int position, int offset, int length) async {
    final SmbComWrite req = SmbComWrite(tree.config);
    final SmbComWriteResponse resp = SmbComWriteResponse(tree.config);

    int off = 0;
    int len = length;

    do {
      int w =
          len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;
      w = len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;

      req.setParam2(fid, position, len - w, buff, off, w);
      tree.prepare(req);
      await tree.transport.sendrecv(req, response: resp);
      int cnt = resp.getCount();
      position += cnt;
      len -= cnt;
      off += cnt;
    } while (len > 0);
    return length;
  }

  Future<int> _writeComAndX(
      List<int> buff, int position, int offset, int length) async {
    final SmbComWriteAndX req = SmbComWriteAndX(tree.config);
    final SmbComWriteAndXResponse resp = SmbComWriteAndXResponse(tree.config);

    int off = 0;
    int len = length;

    do {
      int w =
          len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;
      w = len > SmbStreamConsumer.blockSize ? SmbStreamConsumer.blockSize : len;

      req.setParam2(fid, position, len - w, buff, off, w);
      tree.prepare(req);
      await tree.transport.sendrecv(req, response: resp);
      int cnt = resp.getCount();
      position += cnt;
      len -= cnt;
      off += cnt;
    } while (len > 0);
    return length;
  }
}
