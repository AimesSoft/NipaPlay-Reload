import 'dart:async';
import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/smb_file_stream.dart';
import 'package:smb_connect/src/connect/smb_files_enumerator.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_create_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_create_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/info/smb2_query_directory_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/info/smb2_query_directory_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/smb/file_entry.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/smb_constants.dart';

class Smb2FilesEnumerator extends SmbFilesEnumerator {
  int _num = 0;
  int _fileIndex = 0;
  Uint8List? _fileId;
  bool _canMore = true;

  Smb2FilesEnumerator(
    super.tree,
    super.transport,
    super.folder,
    super.wildcard,
    super.searchAttributes,
  );

  @override
  bool canNext() => _canMore;

  @override
  Future<void> close() async {
    await smbCloseFile(folder, tree, _fileId, 0);
  }

  Future<List<FileEntry>?> _first() async {
    final createReq = Smb2CreateRequest(transport.config, folder.uncPath);
    createReq.setCreateOptions(Smb2Constants.FILE_DIRECTORY_FILE);
    createReq.setDesiredAccess(
        SmbConstants.FILE_READ_DATA | SmbConstants.FILE_READ_ATTRIBUTES);

    final queryReq = Smb2QueryDirectoryRequest(transport.config);
    queryReq.setFileName(wildcard);
    queryReq.setQueryFlags(Smb2QueryDirectoryRequest.SMB2_INDEX_SPECIFIED);
    createReq.chain(queryReq);

    tree.prepare(createReq);
    final Smb2CreateResponse createResp =
        await tree.transport.sendrecv(createReq);

    if (createResp.status != NtStatus.NT_STATUS_OK) {
      throw SmbException.getMessageByCode(createResp.status);
    }
    _fileId = createResp.fileId;
    // _fileIndex = createResp.fil
    return queryReq.getResponse()?.getResults();
  }

  Future<List<FileEntry>?> _more() async {
    Smb2QueryDirectoryRequest queryReq =
        Smb2QueryDirectoryRequest(transport.config, fileId: _fileId);
    queryReq.setFileName(wildcard);
    queryReq.setFileIndex(_fileIndex);
    queryReq.setQueryFlags(Smb2QueryDirectoryRequest.SMB2_INDEX_SPECIFIED);

    tree.prepare(queryReq);
    Smb2QueryDirectoryResponse queryResp =
        await tree.transport.sendrecv(queryReq);
    return queryResp.getResults();
  }

  @override
  Future<List<FileEntry>?> next() async {
    var prevNum = _num;
    _num++;
    List<FileEntry>? res;
    if (prevNum == 0) {
      res = await _first();
    } else {
      res = await _more();
    }
    _fileIndex = res?.lastOrNull?.getFileIndex() ?? _fileIndex;
    _canMore = res?.isNotEmpty == true;
    return res;
  }
}
