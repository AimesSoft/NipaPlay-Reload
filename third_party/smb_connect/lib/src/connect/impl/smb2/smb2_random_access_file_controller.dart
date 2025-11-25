import 'dart:async';
import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/smb_file.dart';
import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_random_access_file.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_create_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/io/smb2_write_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/io/smb2_write_response.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/smb/request_param.dart';
import 'package:smb_connect/src/smb_constants.dart';

typedef OpenFileSmb2Fuction = Future<Smb2CreateResponse> Function(SmbFile file,
    {required int access,
    required int openFlags,
    required int sharing,
    required int attrs});

class Smb2RandomAccessFileController extends SmbRandomAccessFileController {
  final OpenFileSmb2Fuction openFile;
  Uint8List? fileId;

  Smb2RandomAccessFileController(
      super.file, super.tree, super.mode, this.openFile);

  @override
  Future<int?> open() async {
    var resp = await openFile(file,
        access: modeToAccess(),
        openFlags: 0,
        sharing: SmbConstants.DEFAULT_SHARING,
        attrs: SmbConstants.ATTR_NORMAL);

    if (resp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(resp.status);
    }
    fileId = resp.fileId;
    if (resp.status == NtStatus.NT_STATUS_OK && fileId != null) {
      return resp.getSize();
    } else {
      return null;
    }
  }

  @override
  Future close() async {
    await smbCloseFile(file, tree, fileId, 0);
  }

  @override
  Future<int> read(Uint8List buff, int offset, int length) {
    return smbReadFromFile(file, tree, fileId, 0, buff, offset, 0, length);
  }

  @override
  Future<int> write(
      List<int> buff, int position, int offset, int length) async {
    Smb2WriteRequest wr = Smb2WriteRequest(
      tree.config,
      fileId!,
      data2: buff,
      dataOffset: offset,
      dataLength: length,
      offset: position,
      credit: 1,
    );

    tree.prepare(wr);
    Smb2WriteResponse resp =
        await tree.transport.sendrecv(wr, params: {RequestParam.NO_RETRY});
    if (resp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(resp.status);
    }
    return resp.count;
  }
}
